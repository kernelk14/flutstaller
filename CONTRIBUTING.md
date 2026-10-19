# Contributing

Thanks for taking the time to improve this project.

## Getting set up

```powershell
git clone https://github.com/kernelk14/flutstaller.git
cd REPO
```

You do not need to run the installer to work on it. Everything below runs
without installing anything.

## Before you open a pull request

1. **Parse-check the script.** It must parse cleanly in Windows PowerShell 5.1
   (the oldest version this supports):

   ```powershell
   $errors = $null
   [void][System.Management.Automation.Language.Parser]::ParseFile(
       (Resolve-Path .\install.ps1), [ref]$null, [ref]$errors)
   $errors
   ```

2. **Run the analyzer.** CI does this too, using the repository's settings
   file (which documents why a few rules are excluded):

   ```powershell
   Install-Module PSScriptAnalyzer -Scope CurrentUser -Force
   Invoke-ScriptAnalyzer -Path .\install.ps1 -Settings .\PSScriptAnalyzerSettings.psd1
   ```

3. **Run the smoke tests.** Both are read-only and touch nothing on disk
   outside a temporary folder:

   ```powershell
   .\install.ps1 -PreflightOnly   # environment report, no network
   .\install.ps1 -DryRun          # resolves the real vendor manifests, changes nothing
   ```

4. **Check the pipe path.** The script must behave when it is piped into
   `Invoke-Expression`, where there is no file on disk:

   ```powershell
   $env:FLUTSTALLER_PREFLIGHT_ONLY = '1'
   Get-Content .\install.ps1 -Raw | Invoke-Expression
   ```

   It must not close your session, and your `StrictMode` setting must be
   restored afterwards.

## Style

* **PowerShell 5.1 compatible.** No ternary operator, no `??`, no
  `ProcessStartInfo.ArgumentList` (that does not exist in .NET Framework).
  `Set-StrictMode -Version 2.0` is in effect, so every variable must be
  initialised before use.
* **Four spaces, no tabs.** Braces on the same line.
* **Comment the *why*, not the *what*.** Especially where a behaviour looks
  odd — there are several places where something is done in an unusual way on
  purpose.
* **Never return a collection from a function without the comma.**
  `return , @($items)` — PowerShell unrolls collections returned from
  functions, and a single-element result becomes a scalar. This has caused
  real bugs in this script.
* **Never assign to an automatic variable.** `$home`, `$pid`, `$error`,
  `$host`, `$args`, `$matches` and friends are read-only or reserved.
* **Every download URL must come from a vendor manifest** that is read at run
  time, and the artifact must be checksum-verified. Do not hard-code a
  version-specific file name.
* **Do not add an installation step** that the project has not been asked for.
  If a new component is genuinely required, explain why in the issue first.

## Reporting bugs

Open an issue with:

* your Windows version and PowerShell version (`$PSVersionTable`);
* the exact command you ran;
* the relevant part of the log file from `logs/`;
* what you expected and what happened.

The log file is the most useful thing you can attach — it records every
resolved URL, every checksum and every verification result.

## Pull requests

* One logical change per pull request.
* Update `CHANGELOG.md` under *Unreleased*.
* Update `README.md` if you change behaviour or add a switch.
* Make sure CI is green.

## Security issues

Do not open a public issue. See [SECURITY.md](SECURITY.md).
