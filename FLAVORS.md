# Flavors

Two builds ship. They differ in what they can do, not in where they run.

| Flavor | What it is | What it can do |
|---|---|---|
| `runtime` | A single native binary (GraalVM). Default. | Reporter, Receiver, Retriever, MCP server, CLI. |
| `compiler` | A JVM build, delivered as a container image or a `.deb`/`.rpm` with a bundled JRE. | Everything the runtime does, **plus** `generate`, compile and link. |

The difference is real and observable, not branding. The installed native binary
has no `generate` factory in its pipeline-unit list; `log10x/compiler-10x:1.1.32`
does, and runs the doc pipeline in 11s. In `pipeline-extensions`,
`PipelineFactory.java` declares `enum PipelineFactoryType { Cloud, Edge }` — two
constants resolved at package time, never from argv. The capability split is
baked into the artifact.

## Where each flavor is installable from

`install.sh` does not cover every square. The compiler's macOS artifact is a
`.dmg`, which the script refuses by name and hands to Homebrew rather than
half-installing.

| | `runtime` | `compiler` |
|---|---|---|
| Linux (glibc 2.17+) | `install.sh --flavor runtime` | `install.sh --flavor compiler` (`.deb`/`.rpm`) |
| macOS | `install.sh --flavor runtime`, or `brew install log-10x/tap/log10x` | `brew install --cask log-10x/tap/log10x-cloud` |
| Windows | no artifact — the native binary is Linux/macOS only | `install.ps1` (`.msi`) |
| musl (Alpine) | no artifact | no artifact — run a glibc container |

`install.sh --flavor compiler` on macOS exits 1 naming the brew command. It does
not mount the DMG itself: the cask also downloads config and symbols, writes the
`/usr/local/bin/tenx` launcher, and removes all of it on uninstall. `install.sh`
puts its own macOS runtime at that same `/usr/local/bin/tenx`, so a second,
unmanaged copy would contend for the path with no uninstall on either side.

`--print-artifact` still resolves the DMG on macOS, because that asset is the
input to the Homebrew tap job described below.

## Retired: `edge`

`edge` named the jpackage JIT build: a `.deb`/`.rpm` carrying a bundled JRE.

It was kept on the grounds that musl systems needed a JVM build. That
justification was false — the jpackage output is `.deb`/`.rpm`, which Alpine
cannot install either. Neither build runs on musl. Run 10x in a glibc container
instead.

`--flavor edge` now exits 1 with that explanation. `TENX_FLAVOR=edge` in
`install.ps1` does the same.

## Flavor names vs package ids

The flavor name is what you type. The **package id** is what appears in file
names and on disk. They are deliberately different strings, and the package id
does not change.

| Flavor | Package id | Linux prefix | Release assets |
|---|---|---|---|
| `runtime` | `edge` | `/opt/tenx-edge` | `tenx-edge-<v>-<arch>-native`, `tenx-edge-<v>-macos-<arch>-native` |
| `compiler` | `cloud` | `/opt/tenx-cloud` | `tenx-cloud_<v>_<arch>.deb`, `tenx-cloud-<v>-1.<arch>.rpm`, `tenx-cloud-<v>.dmg`, `tenx-cloud-<v>.msi` |

Why the package id is frozen:

- **Published releases are immutable.** `--version` accepts any past tag. Every
  release from 1.0.x through 1.1.37 carries `tenx-cloud-*` / `tenx-edge-*`
  assets. A pattern that stopped matching them would break installs of every
  existing version, not just future ones.
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

Accepted, with a note on stderr:

| Old | New |
|---|---|
| `cloud` | `compiler` |
| `native` | `runtime` |

## Lockstep list

If the release assets are ever renamed, all of these change in the same release
or installs break:

| Where | What matches |
|---|---|
| `install.sh` | `tenx-edge-${V}-macos-{amd64,arm64}-native`, `tenx-edge-${V}-{amd64,aarch64}-native`, `${TENX_FLAVOR}...{amd64,arm64}\.deb`, `${TENX_FLAVOR}...{x86_64,aarch64}\.rpm`, `${TENX_FLAVOR}-${V}\.dmg`, `${TENX_FLAVOR}-${V}-intel\.dmg` |
| `install.ps1` | `tenx-$PackageId.*\.msi` |
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

`install.sh --print-artifact` resolves what an invocation would download and
prints it, installing nothing. An empty resolution exits 1.

```
./install.sh --flavor runtime --version 1.1.37 --print-artifact
```

## Other vocabularies for the same distinction

These live in other repos and are not flags, so renaming them has different
costs. Listed so a single grep finds them:

| Repo | Where | Values | Note |
|---|---|---|---|
| `pipeline-extensions` | `PipelineFactory.java` | `Cloud`, `Edge` | Java enum, resolved at package time. |
| `docker-images` | `publish_10x_forwarder.yaml` `tenx_dist` | `Runtime` | Was `Edge`/`Native`. |
| `docker-images` | forwarder image tag suffix | `-native`, `-jit` | Tag suffix, i.e. a published image name. `-jit` is retired. |
| `elastic-helm-charts` | `charts/filebeat/values.yaml` `tenx.variant` | `native`, `jit` | Selects the image tag suffix above, so it is a name, not a flag. |
| `terraform-aws-tenx-retriever-lambda` | `variables.tf` | `jvm`, `native` | Selects the Lambda image variant. |
| `backend/terraform/demo` | `*.tf` comments | "K8s flavor", "Lambda flavor" | Unrelated meaning: Retriever deployment topology, not this distinction. Do not rename. |
