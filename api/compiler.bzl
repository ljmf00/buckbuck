CompilerInfo = provider(
    fields = [
        "default_flags",

        "ar",
        "ld",
    ],
)

CompilationKind    = enum('object', 'library', 'executable')
CompilationMode    = enum('by_file', 'by_target', 'at_once')
CompilationLinkage = enum('static', 'dynamic')

CompilationWeightInfo = provider(
    fields = [
        "weight",
    ]
)
CompilationInfo = provider(
    fields = [
        "linkage",
        "lookup_paths_set",
        "dependencies_set",
    ]
)

DeferredCompilationInfo = provider(
    fields = [
        "source",
    ]
)
DeferredLinkInfo = provider(
    fields = [
        "link_flags",
    ]
)

def _compiler_impl(ctx: AnalysisContext) -> list[Provider]:
    providers = [
        CompilerInfo(
            default_flags = ctx.attrs.default_flags,

            ar = ctx.attrs.ar,
            ld = ctx.attrs.ld,
        ),
    ]
    providers.extend(ctx.attrs.toolchain.providers)

    return providers

compiler = rule(
  impl = _compiler_impl,
  attrs = {
    "toolchain": attrs.toolchain_dep(),
    "default_flags": attrs.list(attrs.string(), default = []),

    "ar":  attrs.toolchain_dep(default = "@prelude//toolchain:ar"),
    "ld":  attrs.toolchain_dep(default = "@prelude//toolchain:ld"),
})


