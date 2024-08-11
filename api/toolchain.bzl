ToolchainKind = enum('generic', 'compiler', 'linker', 'archiver')
ToolchainInfo = provider(
    doc = """
        Information provider of a toolchain executable

        This is used to describe an executable for generators/compilers/tools.
    """,
    fields = [
        "kind",
    ],
)

def _toolchain_impl(ctx: AnalysisContext) -> list[Provider]:
    if ctx.attrs.command_name and ctx.attrs.executable_dependency:
        fail("you must only specify either 'command_name' or 'executable_dependency' not both")

    if ctx.attrs.executable_dependency:
        default_info = ctx.attrs.executable_dependency[DefaultInfo]
        run_info = ctx.attrs.executable_dependency[RunInfo]
    elif ctx.attrs.command_name:
        default_info = DefaultInfo()
        run_info = RunInfo(
            args = ctx.attrs.command_name,
        )
    else:
        fail("you must specify either 'command_name' or 'executable_dependency'")

    return [
        default_info,
        run_info,
        ToolchainInfo(
            kind = ToolchainKind(ctx.attrs.kind),
        ),
    ]

toolchain = rule(
  impl = _toolchain_impl,
  is_toolchain_rule = True,
  attrs = {
    "command_name": attrs.option(attrs.arg(), default = None),
    "executable_dependency": attrs.option(attrs.exec_dep(), default = None),
    "kind": attrs.enum(ToolchainKind.values(), default = 'generic'),
})
