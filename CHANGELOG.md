# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- **The Linux and macOS install root moved to `~/.bin/development`** (it was
  `$HOME/development`). Windows is unchanged at `C:\development`.

### Fixed

- **"Failure writing output to destination" when downloading the Flutter SDK.**
  The downloads were staged in the temporary directory, which on most Linux
  desktops is a RAM-backed `tmpfs` — a 1 GB Flutter archive does not fit there,
  and curl reports the resulting ENOSPC as that unhelpful message. The work
  directory is now created next to the install root, on the same filesystem, so
  the download lands on the volume the SDK is going to be installed on. The
  Windows installer had the same problem with `%TEMP%` and is fixed the same
  way.
- **A full disk is now reported before the transfer starts.** The free space is
  checked against the download size first, and the failure says which path is
  short, how much is needed and how much is there. If the disk does fill
  anyway, the error says so in those words rather than passing curl's message
  through.
- Downloads now retry three times on a transient network error.

## [0.2.0] - 2026-10-20

The release that actually works when you pipe it. 0.1.0 fixed a great deal,
but running `curl -fsSL …/install.sh | bash` on a real machine exposed three
problems that only show up in a pipe, and two more that only show up when a
prerequisite is unusual.

### Added

- **The Unix installer got the same component menu** as the Windows one, so the
  two installers behave identically.
- **`-SkipAndroid` / `--skip-android`**, and `FLUTSTALLER_SKIP_ANDROID`, now
  exist on **both** installers. An explicit switch always wins over the
  interactive menu.
- **CI runs ShellCheck with `--enable=all`.** The default check does not
  include SC2154, which catches a variable that is referenced but never
  assigned — the exact class of bug that broke the piped install.
- The README now documents how each installer behaves **without a terminal**.

### Changed

- The README was restructured around a **"Before you run it"** section, so
  what the installer touches, what it needs and how much space it wants come
  before the how-to-run instructions. It is 20% shorter and every internal
  link is checked.
- A **"For a reproducible install, pin a version"** note was added: `main`
  moves, and the CDN that serves it can briefly lag behind a push, so a tag or
  a commit is the stable reference.

### Fixed

- **The Unix installer crashed when piped.** `BASH_SOURCE` is unset when the
  script is piped into `bash`, and `set -u` turned reading it into a fatal
  error. It is now read defensively.
- **The Unix progress bar was wider than the terminal.** At ~124 characters it
  wrapped, and the carriage return then landed in the wrong place and
  corrupted the log lines around it. The bar is now sized to the terminal
  width and never exceeds it.
- **A piped run silently cancelled itself.** With no terminal on standard
  input, the "Proceed with the installation?" question read EOF, which was
  taken as "no". The installers now detect a non-interactive run: the
  installation proceeds, the Android SDK licence is accepted after the
  agreement is printed in full, and the Xcode licence is left as an
  outstanding action because an Apple licence always needs an explicit
  confirmation.
- **`$ANDROID_LICENSE_URL` was used but never defined** in `install.sh`, which
  `set -u` would have turned into a fatal error.
- **`JAVA_HOME=/usr` was reported as the JDK directory.** That is a system
  prefix, not a JDK, and pointing Flutter or Gradle at it is wrong. The real
  JDK is now resolved by following the `java` symlink, the way the
  alternatives system does it on Fedora and Debian.
- **The interactive menu no longer overrides** an explicit `-SkipAndroid` or
  `-SkipVisualStudio` switch.
- **`flutter config --android-sdk` is no longer run** when the Android SDK was
  skipped, so Flutter is not pointed at a folder that does not exist.

## [0.1.0] - 2026-10-20

The first release. One installer per platform, the same behaviour on all of
them.

### Added

- **A Linux and macOS installer** — `install.sh`, a POSIX-ish bash script that
  installs the same three components on those platforms:
  - the Flutter SDK, the Android SDK command-line tools and the platform
    toolchain, all under `$HOME/.bin/development` by default;
  - the Linux desktop packages (`clang`, `cmake`, `ninja`, `pkg-config`, the
    GTK 3 headers and the libstdc++ headers) from the distribution's own
    repository, mapped across `apt`, `dnf`, `yum`, `zypper`, `pacman`, `apk`,
    `xbps-install`, `emerge` and `eopkg`;
  - Xcode, its command line tools and the accepted licence on macOS, including
    a Rosetta 2 check on Apple Silicon;
  - the same progress bar, report, dry run and preflight mode as the Windows
    installer;
  - the same environment variables, written into the shell profile inside a
    managed block that is rewritten on every run, so `PATH` never duplicates.
- **A CI job for Linux and macOS** that syntax-checks `install.sh`, runs
  ShellCheck, exercises the preflight and dry-run modes, and runs the script
  the way a user would (`curl … | bash`).
- **Disclosure that the project was written by an AI.** The README leads with
  it, the script's own banner and log header show it, the launcher prints it and
  `SECURITY.md` explains what it does and does not mean. The code was
  generated by [OpenCode](https://opencode.ai) from a written specification.
- **A terminal user interface.** The installer now draws a banner, framed
  section headers, boxed panels and a colour-coded closing report, and it
  falls back to plain ASCII when the console cannot render box-drawing
  characters. A spinner with the elapsed time is shown while a long-running
  program is in progress.
- **An interactive menu** asking which components to install, so a single run
  can install just the Flutter SDK, just the Android SDK, or just Visual
  Studio. It is skipped when running unattended (`-Yes`) or from a pipe.
- **A prerequisites prompt.** When Git or a JDK is missing, the installer
  shows a panel explaining what is missing, why it matters and where it comes
  from, and asks whether to install it. Nothing outside the three components
  is ever installed without that answer.
- **A closing report** listing every component with its state (installed,
  already present, skipped, failed, pending) and a list of the actions that
  are still outstanding.
- Remote execution support: the script can be run with
  `irm https://raw.githubusercontent.com/kernelk14/flutstaller/main/install.ps1 | iex`.
  - Pipe mode is detected automatically; the script never calls `exit` in that
    mode, because that would terminate the caller's PowerShell session.
  - Configuration through environment variables: `FLUTSTALLER_INSTALL_ROOT`,
    `FLUTSTALLER_VS_EDITION`, `FLUTSTALLER_INSTALL_PREREQUISITES`,
    `FLUTSTALLER_SKIP_VISUAL_STUDIO`, `FLUTSTALLER_SKIP_ANDROID_LICENSES`,
    `FLUTSTALLER_SKIP_VERIFICATION`, `FLUTSTALLER_DRY_RUN`,
    `FLUTSTALLER_PREFLIGHT_ONLY`, `FLUTSTALLER_YES`,
    `FLUTSTALLER_LOG_DIRECTORY`, `FLUTSTALLER_SOURCE_URL`.
  - The caller's `StrictMode` setting is restored when the script finishes.
  - In pipe mode the log is written to a temporary folder.
- `-PreflightOnly` switch: a read-only report of the execution policy, script
  runnability, detected prerequisites, the state of every install target and
  the `PATH` entries that would be added. No network access, nothing changed.
- A live progress bar for every download, showing the phase status
  (Connecting / Downloading / Verifying / Complete), the percentage, the
  transferred and total size, the current throughput and the ETA.
- `[STATUS]` lines for phase transitions, and elapsed-time reporting for
  long-running steps.
- `run-setup.cmd` checks the execution policy before running anything and
  prints the exact remedy when the script would be blocked.
- The effective execution policy is recorded in the run log header.

### Changed

- **A failing component no longer aborts the rest of the run.** Each component
  is installed in isolation; the environment is still configured, the
  remaining components are still installed, and the failure is reported with a
  next action. Previously a failure in the Visual Studio step threw and left
  the machine with no `PATH` entries, no `ANDROID_HOME` and no Android SDK.
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
- A machine-wide `ANDROID_HOME` or `ANDROID_SDK_ROOT` that points somewhere
  else is now called out, because it shadows the value set for the account.

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
- A native command that writes to stderr no longer becomes a terminating
  error (the Android command-line tools print a deprecation warning there).
- The Android SDK command-line tools archive is now verified against the
  SHA-1 that Google publishes for it, on Linux and macOS as well as Windows.
- The Android package list is de-duplicated, so the compile SDK is not
  requested twice when it is also the newest published platform.

### What it installs

- The **Flutter SDK** (current stable), with the published SHA-256 verified.
- The **Android SDK command-line tools** and the platform-tools, build-tools
  and Android platform that Flutter requires, with the published SHA-1
  verified.
- The **platform toolchain**: Visual Studio 2026 with the *Desktop development
  with C++* workload on Windows, the Flutter Linux desktop packages on Linux,
  and Xcode on macOS.
- The user `PATH`, `ANDROID_HOME` and `ANDROID_SDK_ROOT`, updated without
  duplicates and without touching unrelated variables.
