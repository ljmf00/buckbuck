def cmd_shell(*args) -> cmd_args:
    return cmd_args(delimiter=" ", quote="shell", format="\"{}\"", *args)

def cmd_semi_hermetic_shell(
    cmds: list[cmd_args],
) -> cmd_args:
    return cmd_args([
        "sh", "-c",
        'set -e;export BUCK2_PROJECT_ROOT=\"$PWD\";cd \"$TMPDIR\";eval "$0" "$@"',
        cmd_args(
            [
                cmd_shell(cmd).absolute_prefix("$BUCK2_PROJECT_ROOT/")
                for cmd in cmds
            ],
            format="eval \"{}\";",
        ),
    ])

def cmd_abs_to_rel_depfile(dep_file) -> cmd_args:
    return cmd_args(
        "sed", "-i", "s%$BUCK2_PROJECT_ROOT/%%g", dep_file,
    )
