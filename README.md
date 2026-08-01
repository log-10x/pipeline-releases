# Log10x Pipeline Releases

This repository hosts the public releases of [Log10x](https://www.log10x.com/?utm_source=github&utm_medium=readme&utm_campaign=pipeline-releases&utm_content=hero).

Log10x is an **Observability runtime**, it is to log/trace data what Chrome V8 is to JavaScript:
an engine for dynamically optimizing execution with the goal improving performance and reducing the cost of data processing.

## Latest Release

You can download the latest version of the project from the [releases page](https://github.com/log-10x/pipeline-releases/releases/latest).

[![Latest Release](https://img.shields.io/github/v/release/log-10x/pipeline-releases?label=Latest%20Release)](https://github.com/log-10x/pipeline-releases/releases/latest)

## How to Use

Visit our [installation instructions](https://doc.log10x.com/install/) for details on how to install and use Log10x, or jump straight to the [Dev App](https://doc.log10x.com/apps/dev/run/).

## Flavors

```sh
# the native binary: Reporter, Receiver, Retriever, MCP, CLI  (default)
curl .../install.sh | bash -s -- --flavor runtime

# the JVM build: everything above, plus generate / compile / link  (Linux)
curl .../install.sh | bash -s -- --flavor compiler

# the compiler on macOS ships as a .dmg, so it comes from the tap
brew install --cask log-10x/tap/log10x-cloud
```

`edge` is retired. `cloud` and `native` are the old names for `compiler` and
`runtime` and still work.

Flavor names are not the same strings as the file names. See [FLAVORS.md](FLAVORS.md)
for the mapping, and for the list of patterns that must change together if a
release asset is ever renamed.

## License

| Component | License |
|-----------|---------|
| `install.sh` (Linux installation script) | Apache 2.0 (open source) |
| `install.ps1` (Windows installation script) | Apache 2.0 (open source) |
| Log10x binaries and runtime | Proprietary (commercial license required) |

The installation scripts are open source — you can freely use, modify, and distribute them.

**The Log10x software it installs requires a commercial license for production use.** Visit [log10x.com/pricing](https://www.log10x.com/pricing?utm_source=github&utm_medium=readme&utm_campaign=pipeline-releases&utm_content=inline) for licensing options, or contact sales@log10x.com for enterprise inquiries.

See [LICENSE](LICENSE) for the proprietary license terms that apply to Log10x binaries. Each release includes a `LICENSE.txt` file that is automatically installed during installation, to `/opt/tenx-edge/LICENSE` for the runtime and `/opt/tenx-cloud/LICENSE` for the compiler ([why the paths keep the old names](FLAVORS.md#flavor-names-vs-package-ids)).
