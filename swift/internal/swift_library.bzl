# Copyright 2018 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Implementation of the `swift_library` rule."""

load(":api.bzl", "swift_common")
load(":compiling.bzl", "swift_library_output_map")
load(":providers.bzl", "SwiftToolchainInfo")
load(":utils.bzl", "expand_locations")
load("@bazel_skylib//:lib.bzl", "dicts")
load(
    "@build_bazel_rules_apple//apple:providers.bzl",
    "AppleResourceInfo",
    "AppleResourceSet",
)

def _collect_resource_sets(resources, structured_resources, deps, module_name):
  """Collects resource sets from the target and its dependencies.

  Args:
    resources: The resources associated with the target being built.
    structured_resources: The structured resources associated with the target
        being built.
    deps: The dependencies of the target being built.
    module_name: The name of the Swift module associated with the resources
        (either the user-provided name, or the auto-generated one).
  Returns:
    A list of structs representing the transitive resources to propagate to the
    bundling rules.
  """
  resource_sets = []

  print("here to create")

  # Create a resource set from the resources attached directly to this target.
  if resources or structured_resources:
    print("creating this shit", resources, structured_resources)
    resource_sets.append(AppleResourceSet(
        resources=depset(resources),
        structured_resources=depset(structured_resources),
        swift_module=module_name,
    ))

  # Collect transitive resource sets from dependencies.
  for dep in deps:
    print("has a dep", dep)
    if AppleResourceInfo in dep:
      print("has resource info", dep[AppleResourceInfo].resource_sets)
      resource_sets.extend(dep[AppleResourceInfo].resource_sets)

  return resource_sets

def _swift_library_impl(ctx):
    copts = expand_locations(ctx, ctx.attr.copts, ctx.attr.swiftc_inputs)
    linkopts = expand_locations(ctx, ctx.attr.linkopts, ctx.attr.swiftc_inputs)

    module_name = ctx.attr.module_name
    if not module_name:
        module_name = swift_common.derive_module_name(ctx.label)

    library_name = ctx.attr.module_link_name
    if library_name:
        copts.extend(["-module-link-name", library_name])

    # Bazel fails the build if you try to query a fragment that hasn't been
    # declared, even dynamically with `hasattr`/`getattr`. Thus, we have to use
    # other information to determine whether we can access the `objc`
    # configuration.
    toolchain = ctx.attr._toolchain[SwiftToolchainInfo]
    objc_fragment = (ctx.fragments.objc if toolchain.supports_objc_interop else None)

    compile_results = swift_common.compile_as_library(
        actions = ctx.actions,
        bin_dir = ctx.bin_dir,
        compilation_mode = ctx.var["COMPILATION_MODE"],
        label = ctx.label,
        module_name = module_name,
        srcs = ctx.files.srcs,
        swift_fragment = ctx.fragments.swift,
        toolchain = toolchain,
        additional_inputs = ctx.files.swiftc_inputs,
        cc_libs = ctx.attr.cc_libs,
        copts = copts,
        configuration = ctx.configuration,
        defines = ctx.attr.defines,
        deps = ctx.attr.deps,
        features = ctx.attr.features,
        library_name = library_name,
        linkopts = linkopts,
        objc_fragment = objc_fragment,
    )

    resource_sets = _collect_resource_sets(
        ctx.files.resources, ctx.files.structured_resources, ctx.attr.deps,
        module_name)
    resource_providers = [AppleResourceInfo(resource_sets=resource_sets)]

    return compile_results.providers + resource_providers + [
        DefaultInfo(
            files = depset(direct = [
                compile_results.output_archive,
                compile_results.output_doc,
                compile_results.output_module,
            ]),
            runfiles = ctx.runfiles(
                collect_data = True,
                collect_default = True,
                files = ctx.files.data,
            ),
        ),
        OutputGroupInfo(**compile_results.output_groups),
    ]

swift_library = rule(
    attrs = swift_common.library_rule_attrs(),
    doc = """
Compiles and links Swift code into a static library and Swift module.
""",
    fragments = [
        "objc",
        "swift",
    ],
    outputs = swift_library_output_map,
    implementation = _swift_library_impl,
)
