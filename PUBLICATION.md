# Public source snapshot

This repository contains a reviewed source snapshot. Original Git history, credentials, personal records, local signing identities, device diagnostics, build outputs, downloaded model weights, firmware, and unreviewed media are excluded. Existing upstream license and attribution files apply to their respective components. Publication does not grant a new license to third-party content.

Configure your own Apple signing team to run native apps on a physical device. Downloaded datasets, binary runtimes, fonts, demo media, and models may need to be obtained separately using the documented upstream sources or fetch/build tools. This publication review does not certify that this snapshot builds or runs.

## Project-specific setup and exclusions

This source uses sibling dependencies: `../LocalSearchKit`. Clone the corresponding public source repositories beside this project, or update local package paths before generating the Xcode project. Optional Cipher datasets are not bundled.

Model weights and physical benchmark/device evidence were excluded. Obtain compatible weights separately using the LocalSearchKit setup guidance. This snapshot does not claim reproduced physical benchmark results.
