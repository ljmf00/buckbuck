def _setting_impl(ctx):
    return [
        DefaultInfo(),
        ConstraintSettingInfo(
            label = ctx.label.raw_target()
        ),
    ]

setting = rule(
  impl = _setting_impl,
  attrs = {},
)

def _setting_value_impl(ctx):
    constraint_value = ConstraintValueInfo(
        setting = ctx.attrs.setting[ConstraintSettingInfo],
        label = ctx.label.raw_target(),
    )
    return [
        DefaultInfo(),
        constraint_value,
        ConfigurationInfo(constraints = {
            constraint_value.setting.label: constraint_value,
        }, values = {}),
    ]

setting_value = rule(
    impl = _setting_value_impl,
    attrs = {
        "setting": attrs.configuration_label(),
    },
)


def _settings_to_configuration(values):
    return ConfigurationInfo(constraints = {
        info[ConstraintValueInfo].setting.label: info[ConstraintValueInfo]
        for info in values
    }, values = {})

def _config_impl(ctx):
    infos = [_settings_to_configuration(ctx.attrs.settings)]
    infos.append(ConfigurationInfo(constraints = {}, values = ctx.attrs.values))

    if len(infos) == 0:
        config_info = ConfigurationInfo(
            constraints = {},
            values = {},
        )
    elif len(infos) == 1:
        config_info = infos[0]
    else:
        constraints = {k: v for info in infos for (k, v) in info.constraints.items()}
        values = {k: v for info in infos for (k, v) in info.values.items()}
        config_info = ConfigurationInfo(
            constraints = constraints,
            values = values,
        )

    return [DefaultInfo(), config_info]

config = rule(
    impl = _config_impl,
    is_configuration_rule = True,
    attrs = {
        "settings": attrs.list(attrs.configuration_label(), default = []),
        "values": attrs.dict(key = attrs.string(), value = attrs.string(), sorted = False, default = {}),
    },
)
