"""
Rules for overridding the linker for Apple builds
"""

load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")

# TODO: Remove once we drop bazel 7.x support
_HAS_OBJC_PROVIDER_LINKOPT = hasattr(apple_common.new_objc_provider(), "linkopt")

# Build the provides list, only including Objc if it exists (removed in Bazel 9+)
_PROVIDES = [p for p in [CcInfo, getattr(apple_common, "Objc", None)] if p != None]

def _attrs(linker, extra_attrs):
    """
    Get the shared attributes for all the linker rules

    Args:
        linker: The default linker binary
        extra_attrs: Extra attributes For the specific rule
    """
    attrs = {
        "linker": attr.label(
            default = linker,
            allow_files = True,
            executable = True,
            cfg = "exec",
            doc = "The linker to use",
        ),
        "ld64_linkopts": attr.string_list(
            doc = "The options to pass to ld64 if 'enable' is False. Supports $(location ...) expansion.",
        ),
        "linkopts": attr.string_list(
            doc = "The options to pass to both the overriden linker and ld64. Supports $(location ...) expansion.",
        ),
        "enable": attr.bool(
            default = True,
            doc = "Whether to enable the overriden linker, useful for disabling with select",
        ),
        "data": attr.label_list(
            allow_files = True,
            doc = "Files needed for $(location ...) expansion in linkopt attributes",
        ),
    }
    attrs.update(extra_attrs)
    return attrs

def _linker_override(ctx, override_linkopts):
    """Construct the providers to override the linker

    Args:
        ctx: The rule context, expected to have some shared attrs
        override_linkopts: Linker options to use with the custom linker
    """

    if not ctx.attr.linker:
        fail("error: linker not specified")

    # Expand $(location ...) references in linkopt strings
    data_targets = ctx.attr.data
    expanded_linkopts = [ctx.expand_location(opt, data_targets) for opt in ctx.attr.linkopts]
    expanded_override_linkopts = [ctx.expand_location(opt, data_targets) for opt in override_linkopts]
    expanded_ld64_linkopts = [ctx.expand_location(opt, data_targets) for opt in ctx.attr.ld64_linkopts]

    linkopts = list(expanded_linkopts)
    if ctx.attr.enable:
        linker_inputs_depset = ctx.attr.linker[DefaultInfo].files
        linkopts.append("--ld-path={}".format(ctx.attr.linker[DefaultInfo].files_to_run.executable.path))
        linkopts.extend(expanded_override_linkopts)
    else:
        linker_inputs_depset = depset([])
        linkopts.extend(expanded_ld64_linkopts)

    linkopts_depset = depset(direct = linkopts, order = "topological")

    objc_provider_kwargs = {}
    if _HAS_OBJC_PROVIDER_LINKOPT:
        objc_provider_kwargs = {
            "linkopt": linkopts_depset,
            "link_inputs": linker_inputs_depset,
        }

    return [
        apple_common.new_objc_provider(**objc_provider_kwargs),
        CcInfo(
            linking_context = cc_common.create_linking_context(
                linker_inputs = depset([
                    cc_common.create_linker_input(
                        additional_inputs = linker_inputs_depset,
                        owner = ctx.label,
                        user_link_flags = linkopts_depset,
                    ),
                ]),
            ),
        ),
    ]

def _apple_linker_override(ctx):
    return _linker_override(ctx, ctx.attr.override_linkopts)

apple_linker_override = rule(
    implementation = _apple_linker_override,
    attrs = _attrs(
        None,
        {
            "override_linkopts": attr.string_list(
                mandatory = False,
                doc = "The options to pass to the custom linker, and not ld64 (see enable). Supports $(location ...) expansion.",
            ),
        },
    ),
    provides = _PROVIDES,
)

def _lld_override(ctx):
    return _linker_override(ctx, ctx.attr.lld_linkopts)

lld_override = rule(
    implementation = _lld_override,
    attrs = _attrs(
        "@rules_apple_linker_lld//:lld_bin",
        {
            "lld_linkopts": attr.string_list(
                mandatory = False,
                doc = "The options to pass to lld, and not ld64 (see enable). Supports $(location ...) expansion.",
            ),
        },
    ),
    provides = _PROVIDES,
)
