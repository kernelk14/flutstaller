# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Remote execution support: the script can be run with
  `irm https://raw.githubusercontent.com/OWNER/REPO/main/install.ps1 | iex`.
  - Pipe mode is detected automatically; the script never calls `exit` in that
    mode, because that would terminate the caller's PowerShell session.
  - Configuration through environment variables: `FLUTSTALLER_INSTALL_ROOT`,
    `FLUTSTALLER_VS_EDITION`, `FLUTSTALLER_INSTALL_PREREQUISITES`,
    `FLUTSTALLER_SKIP_VISUAL_STUDIO`, `FLUTSTALLER_SKIP_ANDROID_LICENSES`,
    `FLUTSTALLER_SKIP_VERIFICATION`, `FLUTSTALLER_DRY_RUN`,
    `FLUTSTALLER_PREFLIGHT_ONLY`, `FLUTSTALLER_YES`,
    `FLUTSTALLER_LOG_DIRECTORY`, `FLUTSTALLER_SOURCE_URL`.
  - The caller's `StrictMode` setting is restored when the script finishes.
  - In pipe mode the log is written to `%TEMP%\flutstaller-logs`.
- `-PreflightOnly` switch: a read-only report of the execution policy, script
  runnability, detected prerequisites, the state of every install target and
  the `PATH` entries that would be added. No network access, nothing changed.
- A live progress bar for every download, showing the phase status
  (Connecting / Downloading / Verifying / Complete), the percentage, the
  transferred and total size, the current throughput and the ETA.
- `[STATUS]` lines for phase transitions, and elapsed-time reporting for
  long-running steps.
- `run-setup.cmd` now checks the execution policy before running anything and
  prints the exact remedy when the script would be blocked.
- The effective execution policy is recorded in the run log header.

### Changed

- The Android SDK is now configured with the **Android CLI** (`android.exe`),
  the tool shipped with command-line tools 23.0 and newer and the one the
  Android documentation now recommends. `sdkmanager` is deprecated and is only
  used as a fallback for older command-line tools. The Android CLI is a native
  binary, so it does not need an external JDK and it handles SDK paths
  containing spaces correctly.
- The Android platform that gets installed is read from the Flutter SDK's own
  `compileSdkVersion` rather than guessed.
- Visual Studio is installed with `--passive` instead of `--quiet`, so the
  Microsoft licence agreement is always shown and accepted by the operator.

### Fixed

- The Android repository manifest is parsed with namespace-agnostic XPath.
  Only the manifest's root element carries the `sdk:` prefix, so the previous
  `//sdk:remotePackage` query matched nothing.
- The namespace manager is no longer returned from a function by value
  (`XmlNamespaceManager` implements `IEnumerable`, so PowerShell unrolled it
  into a string array and broke the two-argument `SelectSingleNode` overload).
- `$home` is read-only in PowerShell; the variable was renamed.
- Functions that return a collection now return it without PowerShell
  unrolling it, so a single-element result is still an array.
- Script-level `return` statements no longer print their value to standard
  output.

## [0.1.0] - Initial release

- Flutter SDK (current stable) installed to `C:\development\flutter`, with the
  published SHA-256 verified.
- Android SDK command-line tools installed to `C:\development\Android\Sdk`,
  with the published SHA-1 verified, plus platform-tools, build-tools and the
  Android platform required by Flutter.
- Visual Studio 2026 with the *Desktop development with C++* workload installed
  to `C:\development\VisualStudio`.
- User `PATH`, `ANDROID_HOME` and `ANDROID_SDK_ROOT` updated without
  duplicates and without touching unrelated variables.
- `-DryRun` mode, structured logging, and post-install verification.
