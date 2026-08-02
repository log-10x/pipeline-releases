# Flavors

A flavor is two independent choices, not one list.

**What the build can do:** run a pipeline, or run a pipeline *and* compile one.
**How the build executes:** as a GraalVM native image, or on a JVM.

That is a 2x2. Three of the four cells ship.

|  | JVM | native |
|---|---|---|
| **compile + run** | `compiler` | impossible, see below |
| **run only** | `runtime-jvm` | `runtime` |

```
  runtime      the native binary. Reporter, Receiver, Retriever, MCP server, CLI.
  runtime-jvm  the same capabilities, executed on a bundled JRE.
  compiler     everything the runtime does, plus generate / compile / link.
```

`runtime` is the default wherever it is built. Windows has no native image, so
`install.ps1` defaults to `runtime-jvm`.

## Why the fourth cell cannot exist

A GraalVM native image is built under a closed-world assumption: every class that
will ever load is known at image build time, and the image contains no compiler
and no class loader for anything else. Compiling a 10x configuration is the
opposite operation. It produces classes and loads them into the running process.
A native image cannot load a class it did not know about when it was built, so a
native compiler is not a build that has not been attempted, it is a build that
cannot be produced.

This is why `compiler` is JVM-only, and it is not a packaging decision that could
be revisited by trying harder.

## What separates `compiler` from the two runtimes

The capability split is baked into the artifact, not read from argv. The
installed native binary has no `generate` factory in its pipeline-unit list;
`log10x/compiler-10x:1.1.32` does, and runs the doc pipeline in 11s. In
`pipeline-extensions`, `PipelineFactory.java` declares
`enum PipelineFactoryType { Cloud, Edge }`: two constants resolved at package
time.

`runtime` and `runtime-jvm` are the *same* capability set. They differ only in
how they execute. Neither can `generate`, compile or link.

## Platform matrix

Verified against the published asset list of release 1.1.38.

| | `compiler` | `runtime` | `runtime-jvm` |
|---|---|---|---|
| Linux amd64 (glibc 2.17+) | `.deb` / `.rpm` | native binary | `.deb` / `.rpm` |
| Linux arm64 (glibc 2.17+) | `.deb` / `.rpm` | native binary | `.deb` / `.rpm` |
| macOS Intel | `.dmg` (Homebrew cask) | native binary | `.dmg`, not installed by script |
| macOS Apple silicon | `.dmg` (Homebrew cask) | native binary | `.dmg`, not installed by script |
| Windows | `.msi` | **not built** | `.msi` |
| musl (Alpine) | no artifact | no artifact | no artifact |

Two squares in that table are the whole reason `runtime-jvm` has a name:

- **Windows has no native image.** Without `runtime-jvm`, the only thing
  installable on Windows is the compiler, which is the wrong tool for anyone who
  wants to *run* 10x.
- **Nothing runs on musl.** The native binary links against glibc, and the JVM
  builds ship as `.deb`/`.rpm`, which Alpine does not install. `runtime-jvm` does
  not change that. Run a glibc container instead.

## How each square is installed

| | Linux | macOS | Windows |
|---|---|---|---|
| `runtime` | `install.sh --flavor runtime` | `install.sh --flavor runtime`, or `brew install log-10x/tap/log10x` | not built, `install.ps1` refuses with that reason |
| `runtime-jvm` | `install.sh --flavor runtime-jvm` | `.dmg` exists, script refuses and points at `runtime` | `install.ps1` (default) |
| `compiler` | `install.sh --flavor compiler` | `brew install --cask log-10x/tap/log10x-cloud` | `$env:TENX_FLAVOR="compiler"; install.ps1` |

`install.sh` refuses both macOS `.dmg` squares rather than half-installing them.
Mounting a DMG and copying the `.app` is not the whole job: the Homebrew cask
also downloads config and symbols, writes the `/usr/local/bin/tenx` launcher that
sets `TENX_CONFIG` and `TENX_SYMBOLS_PATH` before exec'ing into the bundle, and
removes all of it on uninstall. `install.sh` puts its own macOS runtime at that
same `/usr/local/bin/tenx`, so a second unmanaged copy would contend for the path
with no uninstall on either side.

`--print-artifact` still resolves those DMGs, because the compiler DMG is the
input to the Homebrew tap job described under **Lockstep list**.

`install.ps1` refusing `runtime` says *the native runtime is not built for
Windows*, not *invalid flavor*. The spelling is right and the flavor exists; only
the artifact is missing, and only on that one platform. Sending a Windows user
back to the docs to re-read a flavor name would send them back to `runtime`,
which is what the docs say everywhere else.

## Flavor names vs package ids

The flavor name is what you type. The **package id** is what appears in file
names and on disk. They are deliberately different strings, and the package id
does not change.

| Flavor | Package id | Prefix | Release assets |
|---|---|---|---|
| `runtime` | `edge` | `/opt/tenx-edge` | `tenx-edge-<v>-{amd64,aarch64}-native`, `tenx-edge-<v>-macos-{amd64,arm64}-native` |
| `runtime-jvm` | `edge` | `/opt/tenx-edge`, `C:\Program Files\tenx-edge` | `tenx-edge_<v>_{amd64,arm64}.deb`, `tenx-edge-<v>-1.{x86_64,aarch64}.rpm`, `tenx-edge-<v>.msi`, `tenx-edge-<v>.dmg`, `tenx-edge-<v>-intel.dmg` |
| `compiler` | `cloud` | `/opt/tenx-cloud`, `C:\Program Files\tenx-cloud` | `tenx-cloud_<v>_{amd64,arm64}.deb`, `tenx-cloud-<v>-1.{x86_64,aarch64}.rpm`, `tenx-cloud-<v>.msi`, `tenx-cloud-<v>.dmg`, `tenx-cloud-<v>-intel.dmg` |

`runtime` and `runtime-jvm` share the package id `edge`. One id, two asset
shapes: the same capability set packaged twice out of one release. That is why
`install.sh` branches on the flavor, not on the package id, when it picks a
pattern. On Linux both land in `/opt/tenx-edge`, so they cannot be installed side
by side. On Windows only `runtime-jvm` exists, so the question does not arise.

Why the package id is frozen:

- **Published releases are immutable.** `--version` accepts any past tag. Every
  release from 1.0.x through the current one carries `tenx-cloud-*` /
  `tenx-edge-*` assets. A pattern that stopped matching them would break installs
  of every existing version, not just future ones. This is also why renaming the
  flavor was safe and renaming the file would not have been.
- **`install.sh` is fetched from `main`, never pinned.** Five Dockerfiles in
  `log-10x/docker-images` run
  `curl .../pipeline-releases/main/install.sh | bash -s -- --flavor ...`. A
  change here takes effect on the next build of every one of them, including
  rebuilds of old versions.
- **The prefix is baked into published images.** `TENX_HOME=/opt/tenx-edge` and
  `TENX_BIN=/opt/tenx-edge/bin/tenx-edge` are `ENV` lines in the forwarder and
  edge images already on Docker Hub.
- **The binary name comes from the package, not from us.** `tenx-cloud` inside
  `/opt/tenx-cloud/bin/` is created by the jpackage `.deb`, which this script
  only installs.

## Deprecated spellings

Accepted, with a note on stderr. None of them error.

| Old | New | |
|---|---|---|
| `cloud` | `compiler` | |
| `native` | `runtime` | |
| `edge` | `runtime-jvm` | was briefly a hard error, see below |

### `edge`, and the regression that mapping it fixes

`edge` named the jpackage JIT build: a `.deb`/`.rpm`/`.msi`/`.dmg` carrying a
bundled JRE.

It was justified as the flavor musl systems needed, and that justification was
false. The jpackage output is `.deb`/`.rpm`, which Alpine cannot install either.
Retiring the *name* on those grounds was correct.

What went with the name by accident was the only runtime Windows has. The
`tenx-edge` MSI never stopped being published, it is in every release including
the newest, and Windows has no native image. So after the rename `install.ps1`
answered every Windows user who asked to run 10x with:

```
ERROR: invalid TENX_FLAVOR '<x>'. Allowed: compiler
```

The build was still shipping. Only the way to ask for it was gone. Naming the
JVM run-only cell `runtime-jvm` puts it back, and `edge` maps onto it rather
than failing, because `edge` is what every existing script and doc page still
says.

## Lockstep list

If the release assets are ever renamed, all of these change in the same release
or installs break:

| Where | What matches |
|---|---|
| `install.sh` | `tenx-edge-${V}-macos-{amd64,arm64}-native`, `tenx-edge-${V}-{amd64,aarch64}-native`, `${TENX_FLAVOR}...{amd64,arm64}\.deb`, `${TENX_FLAVOR}...{x86_64,aarch64}\.rpm`, `${TENX_FLAVOR}-${V}\.dmg`, `${TENX_FLAVOR}-${V}-intel\.dmg` (`TENX_FLAVOR` is `tenx-edge` for both runtimes, `tenx-cloud` for the compiler) |
| `install.ps1` | `tenx-$PackageId.*\.msi`, i.e. `tenx-edge-<v>.msi` and `tenx-cloud-<v>.msi` |
| `log-10x/engine` `workflow_release.yaml` | `find . -name "tenx-cloud-*.dmg"`, `tenx-cloud-*-intel.dmg`, `tenx-edge-*-macos-arm64-native`, `tenx-edge-*-macos-amd64-native` |
| `log-10x/homebrew-tap` `Formula/log10x.rb.template` | `tenx-edge-{{VERSION}}-macos-{arm64,amd64}-native` URLs and `Dir["tenx-edge-*-native"]` |
| `log-10x/homebrew-tap` `Casks/log10x-cloud.rb.template` | `tenx-cloud-#{version}.dmg`, `tenx-cloud-#{version}-intel.dmg` |
| `log-10x/docker-images` `pipeline/Dockerfile` | `/opt/tenx-cloud`, `/opt/tenx-cloud/bin/tenx-cloud` |
| `log-10x/docker-images` `edge/Dockerfile` + `fwd/*/Dockerfile` | `/opt/tenx-edge`, `/opt/tenx-edge/bin/tenx-edge` |
| `log-10x/docker-images` `publish_10x_lambda_native.yaml` | `tenx-retriever-native-*-linux-amd64.tar.gz` |

The DMG lookup in `workflow_release.yaml` is the dangerous one. It is:

```bash
ARM_DMG=$(find . -name "tenx-cloud-*.dmg" -not -name "*-intel*" -type f | head -1)
if [ -z "$ARM_DMG" ]; then
  echo "No ARM DMG artifact found — skipping Homebrew tap update"
  exit 0
fi
```

A pattern that stops matching does not fail the release. It exits 0, and the
release reports success while the Homebrew tap silently keeps pointing at the
previous version.

## Checking the mapping

Both installers can resolve what an invocation *would* download, print it, and
install nothing. An empty resolution exits 1, so this can be asserted in CI
against a real release instead of assumed.

```sh
./install.sh --flavor runtime-jvm --version 1.1.38 --print-artifact
#   flavor:     runtime-jvm
#   package id: edge
#   artifact:   tenx-edge_1.1.38_amd64.deb
```

```powershell
$env:TENX_PRINT_ARTIFACT = "true"
$env:TENX_FLAVOR = "runtime-jvm"
./install.ps1
#   artifact:   tenx-edge-1.1.38.msi
```

Everything `install.ps1` does before that point is flavor validation and one
GitHub API read, both of which run anywhere `pwsh` runs, so the Windows mapping
is testable from a Linux container.

## Package family detection on Linux

The `.deb` / `.rpm` choice reads `ID` **and** `ID_LIKE` from `/etc/os-release`.
`ID` alone was a five-name allowlist (`ubuntu`, `debian`, `centos`, `fedora`,
`rhel`) that rejected `rocky`, `almalinux`, `ol` and `amzn` by name for packages
that install on them fine. That is the same distro-name gate already removed from
the native runtime, which gates on glibc version instead.

## Other vocabularies for the same distinction

These live in other repos and are not flags, so renaming them has different
costs. Listed so a single grep finds them:

| Repo | Where | Values | Note |
|---|---|---|---|
| `pipeline-extensions` | `PipelineFactory.java` | `Cloud`, `Edge` | Java enum, resolved at package time. |
| `docker-images` | `publish_10x_forwarder.yaml` `tenx_dist` | `Runtime` | Was `Edge`/`Native`. |
| `docker-images` | forwarder image tag suffix | `-native`, `-jit` | Tag suffix, i.e. a published image name. `-jit` is the same JVM build `runtime-jvm` names. |
| `elastic-helm-charts` | `charts/filebeat/values.yaml` `tenx.variant` | `native`, `jit` | Selects the image tag suffix above, so it is a name, not a flag. |
| `terraform-aws-tenx-retriever-lambda` | `variables.tf` | `jvm`, `native` | Selects the Lambda image variant. The same axis as `runtime` vs `runtime-jvm`. |
| `backend/terraform/demo` | `*.tf` comments | "K8s flavor", "Lambda flavor" | Unrelated meaning: Retriever deployment topology, not this distinction. Do not rename. |
