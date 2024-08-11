load("@prelude//api:utility.bzl",
    "cmd_semi_hermetic_shell",
    "cmd_abs_to_rel_depfile",
)
load("@prelude//api:compiler.bzl",
     "CompilerInfo",
     "CompilationKind",
     "CompilationMode",
     "CompilationLinkage",
     "CompilationInfo",
     "CompilationWeightInfo",
)

DCompilationInfo = provider(
    fields = [
        "string_paths_set",
    ]
)

DLookupPathSet = transitive_set(
    args_projections = {
        "lookup_paths": lambda value: cmd_args(value, format="-I{}")
    })
DStringPathSet = transitive_set(
    args_projections = {
        "string_paths": lambda value: cmd_args(value, format="-J{}")
    })

def _project_dependencies(value):
    return cmd_args(
        [d[DefaultInfo].default_outputs for d in value],
        format="-L={}"
    )

DDependencySet = transitive_set(
    args_projections = {
        "dependencies": _project_dependencies,
    })

def _d_target_impl(
    ctx: AnalysisContext,
    objects: list = [],
):
    sources = ctx.attrs.sources
    compiler = ctx.attrs.compiler
    flags = ctx.attrs.flags
    linker_flags = ctx.attrs.linker_flags
    lookup_paths = ctx.attrs.lookup_paths
    string_paths = ctx.attrs.string_paths
    kind = ctx.attrs.kind
    mode = ctx.attrs.mode
    linkage = ctx.attrs.linkage
    dependencies = ctx.attrs.dependencies

    identifier = str(ctx.label.raw_target)

    if mode == 'by_file':
        if not objects and kind != 'object':
            return ctx.actions.anon_targets(
                [(d_target, {
                    "name": ctx.label,
                    "kind": 'object',
                    "mode": mode,
                    "linkage": linkage,
                    "sources": [source],
                    "dependencies": dependencies,
                    "lookup_paths": lookup_paths,
                    "string_paths": string_paths,
                    "compiler": compiler,
                    "flags": flags,
                    "linker_flags": linker_flags,
                }) for source in sources]
            ).promise.map(lambda p: _d_target_impl(ctx, p))
    elif mode == 'by_target':
        pass
    else:
        fail("mode '%s' not yet supported".format(mode))

    cmd = cmd_args(compiler[RunInfo])

    # add default flags
    cmd.add(compiler[CompilerInfo].default_flags)

    # add linker
    cmd.add(cmd_args(compiler[CompilerInfo].ld[RunInfo], format="--linker={}"))

    # ensure we use clang
    cmd.add("--gcc=clang")

    # add user provided flags
    cmd.add(flags)

    # add user provided linker flags
    cmd.add(cmd_args(linker_flags, format="-L={}"))

    # add lookup paths
    lookup_paths_set = ctx.actions.tset(
        DLookupPathSet,
        value=lookup_paths,
        children = [d[CompilationInfo].lookup_paths_set for d in dependencies]
    )
    cmd.add(lookup_paths_set.project_as_args("lookup_paths"))

    # add string paths
    string_paths_set = ctx.actions.tset(
        DStringPathSet,
        value=string_paths,
        children = [d[DCompilationInfo].string_paths_set for d in dependencies if d.get(DCompilationInfo)]
    )
    cmd.add(string_paths_set.project_as_args("string_paths"))

    # add dependencies
    dependencies_set = ctx.actions.tset(
        DDependencySet,
        value=dependencies,
        children = [d[CompilationInfo].dependencies_set for d in dependencies]
    )

    # debug
    cmd.add('-g')
    cmd.add('--link-defaultlib-debug')

    # use linkonce_odr linkage on templates
    cmd.add('--linkonce-templates')

    if linkage == 'dynamic' or kind == 'executable':
        # gc unused sections
        cmd.add('-L=--gc-sections')
        cmd.add('-link-defaultlib-shared')

    if linkage == 'static':
        # set library output name
        output_name = 'output.a'

        # no relocatable code
        cmd.add('--relocation-model=static')
        # don't reference relocatable symbols on executables
        cmd.add('-L=-no-pie')
    elif linkage == 'dynamic':
        # set library output name
        output_name = 'output.so'

        # generate relocatable code
        cmd.add('--relocation-model=pic')
    else:
        fail("unknown linkage '%s'".format(linkage))

    if kind == 'library':
        if linkage == 'dynamic':
            # make sure we built a dynamic library
            cmd.add('--shared')

            # avoid erroring on undefined shared library symbols
            cmd.add('-L=--allow-shlib-undefined')

            # export symbols to the dynamic symbol table
            cmd.add('-L=--export-dynamic')

            # add dependencies
            cmd.add(dependencies_set.project_as_args("dependencies"))
        elif linkage == 'static':
            # make sure we built a static library
            cmd.add('--lib')
    elif kind == 'object':
        # make sure we only compile
        cmd.add('-c')

        # write objects with fully qualified names
        cmd.add('--oq')

        if len(sources) == 0:
            fail("please provide 'sources' on 'object' kind targets")

        if len(sources) > 1:
            # make sure we only build one object
            cmd.add('--singleobj')
        else:
            identifier = sources[0].short_path

        output_name = 'output.o'
    elif kind == 'executable':
        output_name = 'output'

        if linkage == 'dynamic':
            # don't reference relocatable symbols on executables
            cmd.add('-L=-pie')

        # add dependencies
        cmd.add(dependencies_set.project_as_args("dependencies"))
    else:
        fail("unknown kind '%s'".format(kind))

    dep_file = None
    dep_files = {}

    # add collected objects
    if objects:
        if linkage == 'static':
            weight = 1
        else:
            weight = len(objects)

        for object in objects:
            cmd.add(object.get(DefaultInfo).default_outputs)
    else:
        weight = len(sources)

        # here we tag files for incremental builds

        sources_tag = ctx.actions.artifact_tag()
        tagged_sources = sources_tag.tag_artifacts(*sources)

        # add tagged sources
        cmd.add(tagged_sources)

        dep_file = ctx.actions.declare_output("deps").as_output()
        tagged_dep_file = sources_tag.tag_artifacts(dep_file)

        # add tagged dep file
        cmd.add(cmd_args(tagged_dep_file, format="--makedeps={}"))

        # add tags to dictionary
        dep_files["sources"] = sources_tag

    # add output
    out = ctx.actions.declare_output(output_name)
    cmd.add(cmd_args(out.as_output(), format="-of={}"))

    cmd_lst = [cmd]
    if dep_file:
        cmd_lst.append(cmd_abs_to_rel_depfile(dep_file))

    ctx.actions.run(
        cmd_semi_hermetic_shell(cmd_lst),
        category = "compile",
        identifier = identifier,
        weight = weight,
        dep_files = dep_files,
    )

    # the default artifact output provider
    providers = [
        DefaultInfo(default_output = out),
        CompilationWeightInfo(weight = weight),
    ]

    if kind == 'executable':
        # for executables we add the run info provider
        providers.append(RunInfo(args = out))

    providers.extend([
        CompilationInfo(
            linkage = linkage,
            lookup_paths_set = lookup_paths_set,
            dependencies_set = dependencies_set,
        ),
        DCompilationInfo(
            string_paths_set = string_paths_set,
        ),
    ])

    return providers


d_target = rule(
    impl = _d_target_impl,
    attrs = {
        "kind": attrs.enum(CompilationKind.values(), default = 'object'),
        "mode": attrs.enum(CompilationMode.values(), default = 'by_file'),
        "linkage": attrs.enum(CompilationLinkage.values(), default = 'static'),
        "sources": attrs.named_set(attrs.source(), sorted = True, default = []),
        "lookup_paths": attrs.set(attrs.source(allow_directory = True), default = []),
        "string_paths": attrs.set(attrs.source(allow_directory = True), default = []),
        "dependencies": attrs.set(attrs.dep(), default = []),
        "compiler": attrs.exec_dep(default = "@prelude//compiler:ldc"),
        "flags": attrs.list(attrs.string(), default = []),
        "linker_flags": attrs.list(attrs.string(), default = []),
    },
)

def d_library(*args, **kwargs):
    return d_target(kind = 'library', *args, **kwargs)

def d_executable(*args, **kwargs):
    return d_target(kind = 'executable', *args, **kwargs)
