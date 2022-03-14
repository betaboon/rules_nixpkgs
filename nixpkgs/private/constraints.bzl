load("@bazel_tools//tools/cpp:lib_cc_configure.bzl", "get_cpu_value")

def default_constraints(repository_ctx):
    """Calculate the default CPU and OS constraints based on the host platform.

    Args:
      repository_ctx: The repository context of the current repository rule.

    Returns:
      A list containing the cpu and os constraints.
    """
    cpu_value = get_cpu_value(repository_ctx)
    cpu = {
        "darwin": "@platforms//cpu:x86_64",
        "darwin_arm64": "@platforms//cpu:arm64",
    }.get(cpu_value, "@platforms//cpu:x86_64")
    os = {
        "darwin": "@platforms//os:osx",
        "darwin_arm64": "@platforms//os:osx",
    }.get(cpu_value, "@platforms//os:linux")
    return [cpu, os]

def ensure_constraints_pure(default_constraints, target_constraints = [], exec_constraints = []):
    """Build exec and target constraints for repository rules.

    If these are user-provided, then they are passed through.
    Otherwise, use the provided default constraints.
    In either case, exec_constraints always contain the support_nix constraint, so the toolchain can be rejected on non-Nix environments.

    Args:
      target_constraints: optional, User provided target_constraints.
      exec_constraints: optional, User provided exec_constraints.
      default_constraints: Fall-back constraints.

    Returns:
      exec_constraints, The generated list of exec constraints
      target_constraints, The generated list of target constraints
    """
    if not target_constraints and not exec_constraints:
        target_constraints = default_constraints
        exec_constraints = target_constraints
    else:
        target_constraints = list(target_constraints)
        exec_constraints = list(exec_constraints)
    exec_constraints.append("@io_tweag_rules_nixpkgs//nixpkgs/constraints:support_nix")
    return exec_constraints, target_constraints

def ensure_constraints(repository_ctx):
    """Build exec and target constraints for repository rules.

    If these are user-provided, then they are passed through.
    Otherwise we build for the current CPU on the current OS, one of darwin-x86_64, darwin-arm64, or the default linux-x86_64.
    In either case, exec_constraints always contain the support_nix constraint, so the toolchain can be rejected on non-Nix environments.

    Args:
      repository_ctx: The repository context of the current repository rule.

    Returns:
      exec_constraints, The generated list of exec constraints
      target_constraints, The generated list of target constraints
    """
    return ensure_constraints_pure(
        default_constraints = default_constraints(repository_ctx),
        target_constraints = repository_ctx.attr.target_constraints,
        exec_constraints = repository_ctx.attr.exec_constraints,
    )
