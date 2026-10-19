# Security Policy

## Supported versions

Only the `main` branch is supported. Fixes are applied to `main` and released
there; there are no tagged maintenance branches.

## Reporting a vulnerability

**Please do not open a public issue for a security problem.**

Report it privately through GitHub's "Report a vulnerability" button on the
repository's Security tab, or by email to the address listed in the repository
metadata.

Include:

* what the problem is and the impact you believe it has;
* the steps to reproduce it;
* the version or commit you tested.

You can expect an acknowledgement within a few days. Please do not disclose
the issue publicly until it has been addressed.

## Scope and threat model

This project is a **setup script**, so its security properties are unusual and
worth stating plainly.

### What this tool does

`install.ps1` downloads and installs three developer tools from their vendors'
official distribution points, and adds entries to the **user** `PATH` and two
user environment variables. It does not modify the machine-wide environment,
does not install a service, does not start anything at boot, and does not
phone home.

### Hardening decisions

* **No execution-policy changes.** The script never calls
  `Set-ExecutionPolicy` and never uses `-ExecutionPolicy Bypass`. It reports
  the policy in force and, if the script would be blocked, tells you exactly
  which command fixes it. `run-setup.cmd` performs the same check before it
  runs anything.
* **Official sources only.** Every download comes from the component vendor's
  own published manifest or distribution host, resolved at run time:
  * Flutter — `storage.googleapis.com/flutter_infra_release`
  * Android SDK — `dl.google.com/android/repository`
  * Visual Studio — `aka.ms/vs/stable` (redirects to `download.visualstudio.microsoft.com`)
  * Git for Windows — the official `git-for-windows/git` release feed
  * Microsoft Build of OpenJDK — `aka.ms/download-jdk`
* **Checksums are verified.** The Flutter archive is checked against the
  SHA-256 published in Flutter's release manifest; the Android command-line
  tools are checked against the SHA-1 published in Google's repository
  manifest. A mismatch aborts the installation.
* **No unrequested software.** Android Studio, VS Code, editors and other
  IDEs are never installed. Git and a JDK are only installed when you opt in
  explicitly (`-InstallPrerequisites`, or `FLUTSTALLER_INSTALL_PREREQUISITES=1`).
* **Least privilege.** The user environment (`PATH`, `ANDROID_HOME`,
  `ANDROID_SDK_ROOT`) is only modified for the current account, never
  machine-wide. Administrator rights are requested only for the Visual Studio
  step, and only after the script explains why and asks.
* **Licences are never accepted on your behalf.** The Android SDK licence
  needs an explicit typed confirmation, and the Visual Studio installer is run
  with `--passive` (never `--quiet`) so that you accept Microsoft's licence in
  the installer window yourself.

### Remote execution (`irm ... | iex`)

Running the script straight from a URL is supported, and the script is
written for it:

* when there is no script file on disk it never calls `exit` — that would
  close your PowerShell session;
* it writes its log to a temporary folder and prints the path;
* it restores your session's `StrictMode` setting before it finishes;
* it takes its configuration from environment variables
  (`FLUTSTALLER_INSTALL_ROOT` and friends).

That said, piping a script into `Invoke-Expression` executes whatever the
server returns at that moment, without showing you the code first. If you
prefer to see what you are running, download and read it first:

```powershell
irm https://raw.githubusercontent.com/OWNER/REPO/main/install.ps1 -OutFile install.ps1
notepad install.ps1
.\install.ps1
```

The launcher `run-setup.cmd` is the recommended path on a workstation: it
checks the execution policy first and prints a precise remedy if the script
would be blocked.

### Checksum pinning

For a reproducible or audited install, pin the script to a commit and verify
it yourself:

```powershell
irm https://raw.githubusercontent.com/OWNER/REPO/<COMMIT>/install.ps1 -OutFile install.ps1
Get-FileHash install.ps1 -Algorithm SHA256
```

The script's own integrity guarantees cover the *artifacts it downloads*; the
integrity of the script itself is your responsibility, which is why the
vendors publish checksums and why you should read before you pipe.
