# flutstaller

[![CI](https://github.com/kernelk14/flutstaller/actions/workflows/ci.yml/badge.svg)](https://github.com/kernelk14/flutstaller/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A single, re-runnable PowerShell program that sets up a **Flutter development
environment on Windows** — Flutter, the Android SDK command-line tools, and
Visual Studio 2026 with the C++ toolchain — all under one directory, from the
vendors' own official sources.

```powershell
irm https://raw.githubusercontent.com/kernelk14/flutstaller/main/install.ps1 | iex
```

That is the whole thing. It resolves the current stable versions from the
vendors' published manifests, verifies every download against a published
checksum, installs the three components, wires up your user `PATH`, and then
tells you exactly what it did and what (if anything) is still missing.

> **Prefer to see what you are running?** Download and read it first:
> ```powershell
> irm https://raw.githubusercontent.com/kernelk14/flutstaller/main/install.ps1 -OutFile install.ps1
> notepad install.ps1
> .\install.ps1
> ```
> See [Remote execution](#remote-execution) for the details.

---

## Contents

- [What gets installed](#what-gets-installed)
- [Quick start](#quick-start)
- [Prerequisites](#prerequisites)
- [Usage](#usage)
- [Remote execution](#remote-execution)
- [How it works](#how-it-works)
- [What it changes on your machine](#what-it-changes-on-your-machine)
- [Re-running it](#re-running-it)
- [Verification](#verification)
- [Disk space](#disk-space)
- [Logs](#logs)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)

---

## What gets installed

Exactly three components, all under one root (`C:\development` by default):

| # | Component | Install location | Official source |
|---|-----------|------------------|-----------------|
| 1 | **Flutter SDK** (current stable) | `C:\development\flutter` | `storage.googleapis.com/flutter_infra_release` (Flutter's own release manifest) |
| 2 | **Android SDK** — command-line tools only | `C:\development\Android\Sdk` | `dl.google.com/android/repository` (Google's own repository manifest) |
| 3 | **Visual Studio 2026** + *Desktop development with C++* | `C:\development\VisualStudio` | `aka.ms/vs/stable` (Microsoft's official bootstrapper) |

**Not installed:** Android Studio, VS Code, any other editor, or anything else
you did not ask for. Git and a JDK are external prerequisites — they are
*detected and reported*, and only installed if you explicitly opt in.

---

## Quick start

### One line, from a URL

```powershell
irm https://raw.githubusercontent.com/kernelk14/flutstaller/main/install.ps1 | iex
```

### From a clone

```powershell
git clone https://github.com/kernelk14/flutstaller.git
cd REPO

.\install.ps1 -PreflightOnly   # read-only environment report
.\install.ps1 -DryRun          # resolve everything, print the plan, change nothing
.\install.ps1                  # do it
```

### Through the launcher (Windows)

```bat
run-setup.cmd -PreflightOnly
run-setup.cmd -DryRun
run-setup.cmd
```

`run-setup.cmd` does **not** change your execution policy and does **not** use
`-ExecutionPolicy Bypass`. It checks first whether PowerShell would refuse to
run the script and, if so, prints the exact command that fixes it.

Open a **new** terminal when you are done, so the updated `PATH` is picked up.

---

## Prerequisites

Two things the three components depend on but do not contain. The script
**detects** both and reports them clearly.

| Prerequisite | Why it is needed | Official source |
|--------------|------------------|-----------------|
| **Git for Windows** | The `flutter` command fails with *"Unable to find git in your PATH"* without it. | <https://git-scm.com/download/win> |
| **JDK 17 or newer** | Gradle needs a JDK to **build** Android apps. (The Android SDK command-line tools carry their own runtime, so the SDK itself can be configured without one.) | <https://learn.microsoft.com/en-us/java/openjdk/download> |

Three ways to satisfy them — pick one:

1. **Already installed** — the script finds and uses the existing copy.
2. **`-InstallPrerequisites`** (or `FLUTSTALLER_INSTALL_PREREQUISITES=1`) —
   installs the official *Git for Windows* and *Microsoft Build of OpenJDK 17*
   under `C:\development\Git` and `C:\development\jdk`, adds them to your
   `PATH`, and points Flutter at the JDK.
3. **The Visual Studio OpenJDK component** — if no JDK is found, the script adds
   Microsoft's official `Component.OpenJDK` to the Visual Studio installation.
   This keeps everything inside the three requested components.

If you would rather not install them, the script finishes the rest of the work
and lists them as remaining actions in the final report.

---

## Usage

### Switches

| Switch | Effect |
|--------|--------|
| `-PreflightOnly` | Report the execution policy, whether the script can run, the detected prerequisites, the state of every install target and the `PATH` entries that would be added — then exit. No network access, nothing changed. |
| `-DryRun` | Resolve every version and URL, print the full plan (downloads, installs, environment-variable changes, disk estimate) and exit. Nothing is changed. |
| `-InstallRoot <path>` | Install everything under a different root. Default `C:\development`. |
| `-VsEdition <Community\|Professional\|Enterprise>` | Visual Studio 2026 edition. Default `Community`. |
| `-Yes` | Do not ask the "proceed with the installation" question. **Licences are never accepted automatically.** |
| `-InstallPrerequisites` | Opt in to installing Git for Windows and Microsoft Build of OpenJDK 17 under the install root. |
| `-SkipVisualStudio` | Do not install Visual Studio. |
| `-SkipAndroidLicenses` | Do not run the Android SDK licence step. |
| `-SkipVerification` | Do not run the post-install checks. |
| `-LogDirectory <path>` | Where to write the run log. Default `.\logs` (or `%TEMP%\flutstaller-logs` when piped). |

### Environment variables

Needed when you cannot pass parameters — which is the case with
`irm ... | iex`. A command-line parameter always wins over an environment
variable, and an environment variable always wins over the built-in default.

| Variable | Equivalent switch |
|----------|-------------------|
| `FLUTSTALLER_INSTALL_ROOT` | `-InstallRoot` |
| `FLUTSTALLER_VS_EDITION` | `-VsEdition` |
| `FLUTSTALLER_INSTALL_PREREQUISITES` | `-InstallPrerequisites` |
| `FLUTSTALLER_SKIP_VISUAL_STUDIO` | `-SkipVisualStudio` |
| `FLUTSTALLER_SKIP_ANDROID_LICENSES` | `-SkipAndroidLicenses` |
| `FLUTSTALLER_SKIP_VERIFICATION` | `-SkipVerification` |
| `FLUTSTALLER_DRY_RUN` | `-DryRun` |
| `FLUTSTALLER_PREFLIGHT_ONLY` | `-PreflightOnly` |
| `FLUTSTALLER_YES` | `-Yes` |
| `FLUTSTALLER_LOG_DIRECTORY` | `-LogDirectory` |
| `FLUTSTALLER_SOURCE_URL` | *(internal)* canonical script URL, used to re-launch elevated while piped |

```powershell
$env:FLUTSTALLER_INSTALL_ROOT = 'D:\dev'
$env:FLUTSTALLER_DRY_RUN = '1'
irm https://raw.githubusercontent.com/kernelk14/flutstaller/main/install.ps1 | iex
```

---

## Remote execution

The script is written to survive being piped into `Invoke-Expression`, where
there is no file on disk:

| Situation | Behaviour |
|-----------|-----------|
| No script file | It never calls `exit` — that would close your PowerShell session. |
| Log location | Written to `%TEMP%\flutstaller-logs`; the path is printed. |
| Your session's `StrictMode` | Restored to whatever it was when the script finishes. |
| Configuration | Read from the environment variables above. |
| Elevation | It fetches the canonical copy of the script to a temporary file and runs that in the elevated window. |

You can also pass parameters by turning the download into a script block:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/kernelk14/flutstaller/main/install.ps1))) -InstallRoot 'D:\dev' -DryRun
```

**A word of caution.** `irm ... | iex` executes whatever the server returns at
that moment, without showing you the code first. That is a property of the
pattern, not of this project. If that trade-off is not for you, download the
file and read it — the script is a single readable file, and every URL it
uses is listed in [How it works](#how-it-works).

---

## How it works

### Versions are resolved at run time, never hard-coded

Every download URL is read from the vendor's own published manifest immediately
before use, so you always get current official artifacts:

| Component | Manifest | Verification |
|-----------|----------|--------------|
| Flutter | `storage.googleapis.com/flutter_infra_release/releases/releases_windows.json` | **SHA-256** from the manifest |
| Android command-line tools | `dl.google.com/android/repository/repository2-3.xml` | **SHA-1** from the manifest |
| Android packages | the same manifest, plus `sdkmanager`/`android sdk list` | vendor-signed |
| Visual Studio 2026 | `aka.ms/vs/stable/vs_community.exe` (always the latest servicing release) | Microsoft installer |
| Git for Windows | the official `git-for-windows/git` release feed | vendor installer |

### The Android SDK is configured with the current Android CLI

`cmdline-tools` 23.0 and newer ship the **Android CLI** (`android.exe`), a
native binary that manages the SDK itself and carries its own Java runtime.
Google currently marks `sdkmanager` as deprecated in favour of `android sdk`,
so the script uses:

```
android.exe --sdk="C:\development\Android\Sdk" sdk install platform-tools build-tools/36.1.0 platforms/android-36
```

If an older `cmdline-tools` without `android.exe` is found, the script falls
back to `sdkmanager` (which does need a JDK).

The Android **platform** that gets installed is not guessed: the script reads
`compileSdkVersion` out of the Flutter SDK it just installed
(`packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt`) and
installs exactly that platform, plus the newest published stable build-tools.

### Licences

* **Android SDK** — the script prints what the Android SDK License Agreement
  is, where to read it (<https://developer.android.com/studio/terms>) and asks
  for an explicit typed confirmation **before** the Android CLI is run for the
  first time (that is the moment the licence is presented and recorded).
  `-Yes` does *not* answer this prompt.
* **Visual Studio** — the installer runs with `--passive`, never `--quiet`, so
  the installer shows Microsoft's licence agreement and **you** accept it in
  that window. The script never accepts it for you.

### Administrator rights

The Visual Studio installer needs administrator rights. The script checks
before starting it and, if the session is not elevated, **asks** whether it may
re-launch itself in an elevated PowerShell window. It never relaunches elevated
silently. If it does re-launch, your original account's `PATH` and environment
variables are still updated for *your* account, even if the elevated window
belongs to a different administrator account.

### Visual Studio 2026 and `C:\development`

Visual Studio 2026 **does** support a custom install path, and the script uses
it:

```
vs_community.exe --installPath C:\development\VisualStudio ...
```

On a machine with no previous Visual Studio installation it also relocates the
shared components and the download cache:

```
--path shared=C:\development\VisualStudio\Shared
--path cache=C:\development\VisualStudio\Cache
```

Those two can only be set on the **first** Visual Studio installation on a
machine; if the installer rejects them the script retries without them.

**Two things always install outside `C:\development` and cannot be moved:**

* the **Visual Studio Installer** → `C:\Program Files (x86)\Microsoft Visual Studio\Installer`
* the **Windows SDK** → `C:\Program Files (x86)\Windows Kits\10`

Microsoft hard-codes both locations, so no installer flag can change them. The
Visual Studio components that *are* relocatable are relocated.

### Which Visual Studio components are installed

Only the C++ workload and what a Flutter Windows desktop build needs:

* `Microsoft.VisualStudio.Workload.NativeDesktop` — *Desktop development with C++*
* `Microsoft.VisualStudio.Component.VC.Tools.x86.x64` — MSVC x64/x86 build tools
* `Microsoft.VisualStudio.Component.VC.CMake.Project` — C++ CMake tools for Windows
* the **Windows SDK** — a *recommended* component of that workload. The
  recommended set is taken so the correct, current SDK build ships with Visual
  Studio 2026, rather than a hard-coded and quickly stale component ID.

No unrelated workload is added. `Component.OpenJDK` is added **only** when no
JDK was found on the machine.

---

## What it changes on your machine

**User environment variables** (your account only — the machine environment is
never modified):

| Variable | Value |
|----------|-------|
| `ANDROID_HOME` | `C:\development\Android\Sdk` |
| `ANDROID_SDK_ROOT` | `C:\development\Android\Sdk` |
| `JAVA_HOME` | only set if this script installed a JDK and `JAVA_HOME` was not already set |

Unrelated variables are never touched. If `ANDROID_HOME` already points
somewhere else, the change is reported before it is made.

**User `PATH`** gains these entries (existing entries, their order and any
unrelated variables are preserved, and duplicates are skipped):

```
C:\development\flutter\bin
C:\development\Android\Sdk\platform-tools
C:\development\Android\Sdk\cmdline-tools\latest\bin
C:\development\jdk\bin              (only with -InstallPrerequisites)
C:\development\Git\cmd              (only with -InstallPrerequisites)
```

**Flutter configuration** (Flutter's own settings file):

```
flutter config --android-sdk C:\development\Android\Sdk
flutter config --jdk-dir <detected JDK>
flutter config --enable-windows-desktop
```

The Android CLI keeps its own state in `%USERPROFILE%\.android` (adb keys,
caches). That is the vendor's standard location and is not configurable.

---

## Re-running it

The script is safe to run again:

* Existing installations are detected and **left untouched** — Flutter, the
  command-line tools, the Android packages and Visual Studio are each skipped.
* `PATH` entries are compared case-insensitively and are never duplicated.
* Nothing is deleted and no existing directory is overwritten. If a target
  directory exists but is not a valid installation, the script stops with an
  error instead of replacing it.
* Environment variables that already hold the right value are left alone.

---

## Verification

At the end the script runs and reports on:

* `flutter --version`
* `flutter config --enable-windows-desktop`
* `flutter doctor -v`
* `flutter doctor --android-licenses` (interactive — you confirm each licence)
* `adb version`
* the MSVC compiler (`cl.exe`), the CMake tools, MSBuild and the Windows SDK
* that `flutter` and `adb` resolve **through `PATH`**
* that the accepted Android SDK licence was recorded in the SDK's `licenses` folder

If any check fails the script says so and exits non-zero — it never reports
success when a verification failed.

### Progress, speed and status

Every download is shown with a live progress bar that is redrawn in place:

```
Downloading  flutter_windows_3.47.7-sta...  [###########------------------]   37.4%  412.3 MB / 1.10 GB  25.0 MB/s  ETA 00:27
```

It shows the phase status (`Connecting`, `Downloading`, `Verifying`,
`Complete`), the percentage, the transferred and total size, the current
throughput (a sliding average over the last 5 seconds) and the ETA. Each phase
also emits a status line:

```
22:14:03 [STATUS] Downloading flutter_windows_3.47.7-stable.zip
22:14:31 [STATUS] Extracted flutter_windows_3.47.7-stable.zip in 00:28
```

When the output is **redirected** (piped to a file, or run by CI) the in-place
bar is automatically replaced by plain status lines, so logs stay readable.

---

## Disk space

Plan for roughly **20 GB free**:

| Component | Approximate size |
|-----------|------------------|
| Flutter SDK | ~3.5 GB |
| Android SDK (tools + packages) | ~2 GB |
| Visual Studio 2026 (C++ workload) | ~10–14 GB |

The script checks the free space and warns you if it looks tight.

---

## Logs

Every run writes `logs\flutter-setup-<timestamp>.log` next to the script (or to
`%TEMP%\flutstaller-logs` when piped), with the full output of each step, the
resolved download URLs, the checksums and the verification results.

**Attach the log to any bug report** — it is by far the most useful thing you
can provide.

---

## Troubleshooting

| Symptom | What to do |
|---------|------------|
| *"Unable to find git in your PATH"* | Git for Windows is missing. Install it from <https://git-scm.com/download/win>, or re-run with `-InstallPrerequisites`. |
| `flutter doctor` reports no Java | A JDK is missing. Re-run with `-InstallPrerequisites`, or allow the Visual Studio OpenJDK component (the script does this automatically when no JDK is found). |
| *"running scripts is disabled on this system"* | See [Script execution policy](#script-execution-policy) below. |
| The Visual Studio installer was cancelled | Exit code 1602 means the installer window was closed. Re-run the script. |
| The Visual Studio installer returns 740 | It needs elevation. Re-run from an elevated PowerShell window. |
| `flutter doctor` cannot find the Android SDK | Run `flutter config --android-sdk C:\development\Android\Sdk`. |
| Not enough disk space | Free up space or point `-InstallRoot` at a drive with room. |
| The script is blocked by the execution policy | `Unblock-File -LiteralPath .\install.ps1` — this changes no policy. |

### Script execution policy

Your effective policy is normally `RemoteSigned`, which runs local scripts
freely and only blocks scripts that Windows has marked as "downloaded from the
internet" (and that are unsigned).

```powershell
Get-ExecutionPolicy -List
```

`run-setup.cmd` checks this for you and prints the right remedy:

| Situation | Remedy |
|-----------|--------|
| The script carries a mark-of-the-web | `Unblock-File -LiteralPath '<path>'` — one file, no policy change |
| The policy is `Restricted` | `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force` — per user, no admin rights needed |
| The policy is `AllSigned` and the script is unsigned | `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force` |

Avoid `Bypass` and `Unrestricted`: `Bypass` disables script security entirely
for that scope or process, so anything that runs in it is unverified. This
project never uses it.

---

## Contributing

Pull requests are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md) for the
checks to run before you open one.

## Security

Please do not open a public issue for a security problem — see
[SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE) © Khyle Angelo Isaias

---

## Official documentation

* Flutter — <https://docs.flutter.dev/install/manual>
* Flutter SDK archive — <https://docs.flutter.dev/install/archive>
* Android command-line tools — <https://developer.android.com/tools/agents/android-cli/download>
* Android CLI reference — <https://developer.android.com/tools/agents/android-cli/commands/sdk>
* Android SDK terms — <https://developer.android.com/studio/terms>
* Visual Studio 2026 command-line parameters — <https://learn.microsoft.com/en-us/visualstudio/install/use-command-line-parameters-to-install-visual-studio>
* Visual Studio workload/component IDs — <https://learn.microsoft.com/en-us/visualstudio/install/workload-and-component-ids>
* Microsoft Build of OpenJDK — <https://learn.microsoft.com/en-us/java/openjdk/download>
* Git for Windows — <https://git-scm.com/download/win>
