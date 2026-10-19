## What this changes

<!-- One or two sentences. -->

## Why

<!-- The problem this solves, or a link to the issue. -->

## How it was verified

<!-- Tick the ones you ran. -->

- [ ] `install.ps1 -PreflightOnly`
- [ ] `install.ps1 -DryRun`
- [ ] The piped path (`Get-Content .\install.ps1 -Raw | Invoke-Expression`)
- [ ] Ran it for real
- [ ] PSScriptAnalyzer is clean

## Checklist

- [ ] The script still parses in Windows PowerShell 5.1.
- [ ] No new software is installed that the project has not been asked for.
- [ ] Every new download URL still comes from a vendor manifest and is checksum-verified.
- [ ] No collection is returned from a function without the `,` (unrolling guard).
- [ ] No automatic variable (`$home`, `$pid`, `$error`, …) is assigned to.
- [ ] `CHANGELOG.md` updated under *Unreleased*.
- [ ] `README.md` updated if behaviour or a switch changed.
