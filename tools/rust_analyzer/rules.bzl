"""
Rules for managing a cargo-free workspace with rust-analyzer that supports an equivalent of
`cargo check`.

To use, use the `rust_analyzer` macro at a suitable location in your workspace. Then run
`//path/to:update` whenever you change rust targets (add a new target, add a source file, etc.)
and configure your LSP plugin to use `bazel run //path/to:check` as the cargo check override
command. For example, for VS Code:

```
{
    "rust-analyzer.checkOnSave.overrideCommand": ["bazel", "run", "//path/to:check"]
}
```

This workflow replaces `gen_rust_project`, which is called interally by the update command.

Check performs a bazel build of just the metadata for all crates, just like `cargo check` does.
The stdout from each crate build action is collected and printed in the format that
rust-analyzer is expecting. Update determines the list of rustc output paths, which is much
slower than performing the incremental bazel build, so that they can be cached for use by update.

The list of rustc output paths must be stored somewhere; this is the rustc_outputs argument, and
it defaults to "rustc_outputs.txt" at to the root of your workspace. It is a build artifact, so
it should be added to .gitignore.
"""

load("@bazel_skylib//rules:write_file.bzl", "write_file")

def rust_analyzer(
        update_name = "update",
        check_name = "check",
        rustc_outputs = "rustc_outputs.txt",
        symlink_prefix = "",
        extra_build_args = [],
        **kwargs):
    """
    Create update and check targets. See docstring above for usage.

    Args:
      update_name: name of the update target
      check_name: name of the check target
      rustc_outputs: path to a file containing the cache of rustc stdout file locations
      symlink_prefix: the value of --symlink_prefix passed to bazel
      extra_build_args: extra flags to pass to bazel
    """

    fmt = dict(
        rustc_outputs = rustc_outputs,
        symlink_prefix = symlink_prefix,
        extra_build_args = " ".join(extra_build_args),
    )

    check_file = "_{}.script".format(check_name)
    write_file(
        name = check_file,
        out = "{}.sh".format(check_file),
        is_executable = True,
        content = ["""
#!/bin/sh
cd "$BUILD_WORKSPACE_DIRECTORY"

bazel build {extra_build_args} //... --keep_going --output_groups=rust_metadata_rustc_output >/dev/null 2>&1 || true

while read target; do
    if [ -f "$target" ]; then
        cat "$target";
    fi
done < "{rustc_outputs}"
""".format(**fmt)],
        visibility = ["//visibility:private"],
    )

    native.sh_binary(
        name = check_name,
        srcs = [check_file],
        **kwargs
    )

    update_file = "_{}.script".format(update_name)
    write_file(
        name = update_file,
        out = "{}.sh".format(update_file),
        is_executable = True,
        content = ["""
#!/bin/sh
cd "$BUILD_WORKSPACE_DIRECTORY"

bazel run {extra_build_args} @rules_rust//tools/rust_analyzer:gen_rust_project
bazel cquery {extra_build_args} //... --output_groups=rust_metadata_rustc_output --output=files --color=yes > "{rustc_outputs}"
sed -i 's|.*|{symlink_prefix}&|g' "{rustc_outputs}"
""".format(**fmt)],
        visibility = ["//visibility:private"],
    )

    native.sh_binary(
        name = update_name,
        srcs = [update_file],
        **kwargs
    )
