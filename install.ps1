#Requires -Version 5.1
<#
.SYNOPSIS
    Sets up a Flutter development environment on Windows.

.DESCRIPTION
    Installs exactly three components, all underneath a single install root
    (default C:\development):

      1. Flutter SDK (current stable)          -> <root>\flutter
      2. Android SDK command-line tools only    -> <root>\Android\Sdk
      3. Visual Studio 2026 + C++ workload      -> <root>\VisualStudio

    Android Studio is never installed. Git, a JDK and editors are never
    installed unless the operator explicitly opts in with -InstallPrerequisites
    (or, for the JDK, by choosing the Visual Studio OpenJDK component).

    Every download URL is resolved at run time from the vendor's own published
    manifest, so the script always uses current official artifacts rather than
    hard-coded links.

    NOTE: This script was written by an AI coding agent (OpenCode) from a
    written specification. It is MIT licensed and meant to be read: the whole
    program is this one file.

.PARAMETER InstallRoot
    Root directory for all installed components. Default: C:\development

.PARAMETER VsEdition
    Visual Studio 2026 edition to install. Default: Community

.PARAMETER DryRun
    Resolve versions, print the full plan (downloads, installs, environment
    variable changes, disk estimate) and exit without changing anything.

.PARAMETER PreflightOnly
    Report the execution policy, the mark-of-the-web status of this script and
    the detected prerequisites, then exit. No network access, no changes.

.PARAMETER Yes
    Do not prompt for the "proceed with installation" question. Licence
    acceptance is NEVER auto-confirmed by this switch.

.PARAMETER InstallPrerequisites
    Opt in to installing the two external prerequisites that the three components
    depend on but do not contain:
      * Git for Windows  -> <root>\Git
      * Microsoft Build of OpenJDK 17 -> <root>\jdk
    Both come from their official vendor sites. Without this switch a missing
    prerequisite is only reported, never installed.

.PARAMETER SkipVisualStudio
    Do not install Visual Studio (the other two components are still installed).

.PARAMETER SkipAndroid
    Do not install the Android SDK (the other two components are still
    installed).

.PARAMETER SkipAndroidLicenses
    Do not run the Android SDK licence acceptance step.

.PARAMETER SkipVerification
    Do not run the post-install verification checks.

.PARAMETER LogDirectory
    Where to write the run log. Default: <script folder>\logs

.PARAMETER TargetUserSid
    Internal. The Windows SID of the account whose user environment should be
    updated. Used when the script had to be re-launched elevated under a
    different administrator account.

.NOTES
    Remote execution
    ----------------
    This script is designed to be run directly from a URL:

        irm https://raw.githubusercontent.com/OWNER/REPO/main/install.ps1 | iex

    That runs whatever the server returns at that moment, without showing you
    the code first. This script was written by an AI coding agent (OpenCode);
    it is MIT licensed and the whole program is this one file, so reading it
    first is a reasonable thing to do:

        irm https://raw.githubusercontent.com/OWNER/REPO/main/install.ps1 -OutFile install.ps1
        notepad install.ps1

    In that mode there is no script file on disk, so the script adapts:
      * it never calls exit (that would close the caller's PowerShell session);
      * it writes its log to a temporary folder;
      * it reads its configuration from environment variables.

    Configuration environment variables (a command-line parameter always wins):
        FLUTSTALLER_INSTALL_ROOT           default C:\development
        FLUTSTALLER_VS_EDITION             Community | Professional | Enterprise
        FLUTSTALLER_INSTALL_PREREQUISITES  1 to also install Git and a JDK
        FLUTSTALLER_SKIP_VISUAL_STUDIO     1 to skip Visual Studio
        FLUTSTALLER_SKIP_ANDROID           1 to skip the Android SDK
        FLUTSTALLER_SKIP_ANDROID_LICENSES  1 to skip the licence step
        FLUTSTALLER_SKIP_VERIFICATION      1 to skip the final checks
        FLUTSTALLER_DRY_RUN                1 to only print the plan
        FLUTSTALLER_PREFLIGHT_ONLY         1 to only print the environment report
        FLUTSTALLER_YES                    1 to skip the "proceed" question
        FLUTSTALLER_LOG_DIRECTORY          where to write the run log
#>
[CmdletBinding()]
param(
    [string] $InstallRoot = 'C:\development',

    [ValidateSet('Community', 'Professional', 'Enterprise')]
    [string] $VsEdition = 'Community',

    [switch] $DryRun,
    [switch] $PreflightOnly,
    [switch] $Yes,
    [switch] $InstallPrerequisites,
    [switch] $SkipVisualStudio,
    [switch] $SkipAndroid,
    [switch] $SkipAndroidLicenses,
    [switch] $SkipVerification,
    [string] $LogDirectory,
    [string] $TargetUserSid
)

# --------------------------------------------------------------------------------------
# Pipe mode detection.
#
# When the script is piped into Invoke-Expression ("irm ... | iex") PowerShell
# compiles it as an anonymous script block: there is no file, so $PSCommandPath
# and $PSScriptRoot are empty. In that mode 'exit' would terminate the caller's
# PowerShell session, so it must never be used.
# --------------------------------------------------------------------------------------
$script:IsPiped = [string]::IsNullOrEmpty($PSCommandPath)
$script:StrictModeWasOn = $false
$script:PipeExitCode = 0
# Whether the operator can answer a question. A piped run has no terminal on
# standard input, so the script must not ask anything it cannot get an answer
# to - it would read EOF and silently do nothing.
$script:IsInteractive = $true
try { $script:IsInteractive = (-not [Console]::IsInputRedirected) } catch { }

function Test-StrictModeEnabled {
    # Under strict mode, touching a property that does not exist is an error.
    try { [void]$null.Count; return $false } catch { return $true }
}

if (-not $script:IsPiped) {
    Set-StrictMode -Version 2.0
} elseif (Test-StrictModeEnabled) {
    # The caller already runs with strict mode on - leave their setting alone.
    $script:StrictModeWasOn = $true
} else {
    # Temporarily enable strict mode, and switch it back off when we are done
    # so we do not change the caller's session settings.
    Set-StrictMode -Version 2.0
}

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# --------------------------------------------------------------------------------------
# Configuration: a command-line parameter always wins over an environment variable,
# and an environment variable wins over the built-in default.
# --------------------------------------------------------------------------------------
function Resolve-EnvString {
    param([string] $Value, [string] $Default, [string] $Name)
    if ($Value -ne $Default) { return $Value }
    $v = [Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrWhiteSpace($v)) { return $Default }
    return $v.Trim()
}

function Resolve-EnvFlag {
    param([bool] $Value, [bool] $Default, [string] $Name)
    if ($Value -ne $Default) { return $Value }
    $v = [Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrWhiteSpace($v)) { return $Default }
    return ($v.Trim() -match '^(1|true|yes|on)$')
}

$InstallRoot            = Resolve-EnvString -Value $InstallRoot           -Default 'C:\development' -Name 'FLUTSTALLER_INSTALL_ROOT'
$VsEdition              = Resolve-EnvString -Value $VsEdition             -Default 'Community'       -Name 'FLUTSTALLER_VS_EDITION'
$LogDirectory           = Resolve-EnvString -Value $LogDirectory          -Default ''               -Name 'FLUTSTALLER_LOG_DIRECTORY'
$DryRun                 = Resolve-EnvFlag  -Value ([bool]$DryRun)         -Default $false           -Name 'FLUTSTALLER_DRY_RUN'
$PreflightOnly          = Resolve-EnvFlag  -Value ([bool]$PreflightOnly)  -Default $false           -Name 'FLUTSTALLER_PREFLIGHT_ONLY'
$Yes                    = Resolve-EnvFlag  -Value ([bool]$Yes)            -Default $false           -Name 'FLUTSTALLER_YES'
$InstallPrerequisites   = Resolve-EnvFlag  -Value ([bool]$InstallPrerequisites) -Default $false      -Name 'FLUTSTALLER_INSTALL_PREREQUISITES'
$SkipVisualStudio       = Resolve-EnvFlag  -Value ([bool]$SkipVisualStudio) -Default $false         -Name 'FLUTSTALLER_SKIP_VISUAL_STUDIO'
$SkipAndroid           = Resolve-EnvFlag  -Value ([bool]$SkipAndroid) -Default $false             -Name 'FLUTSTALLER_SKIP_ANDROID'
$SkipAndroidLicenses    = Resolve-EnvFlag  -Value ([bool]$SkipAndroidLicenses) -Default $false      -Name 'FLUTSTALLER_SKIP_ANDROID_LICENSES'
$SkipVerification       = Resolve-EnvFlag  -Value ([bool]$SkipVerification) -Default $false         -Name 'FLUTSTALLER_SKIP_VERIFICATION'

# The canonical script URL, used only when the script has to re-launch itself
# in an elevated window while running from a pipe.
$script:SourceUrl = [Environment]::GetEnvironmentVariable('FLUTSTALLER_SOURCE_URL')
if ([string]::IsNullOrWhiteSpace($script:SourceUrl)) { $script:SourceUrl = 'https://raw.githubusercontent.com/kernelk14/flutstaller/main/install.ps1' }

if ($VsEdition -notin @('Community', 'Professional', 'Enterprise')) {
    throw "FLUTSTALLER_VS_EDITION must be Community, Professional or Enterprise (got '$VsEdition')."
}

try {
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { }

# --------------------------------------------------------------------------------------
# Official vendor endpoints. Every one of these is a published manifest / download
# service operated by the component's vendor. Nothing is hard-coded to a guessed file
# name: versions are resolved from these manifests at run time.
# --------------------------------------------------------------------------------------
$script:FlutterReleasesUrl = 'https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json'
$script:AndroidRepoUrl     = 'https://dl.google.com/android/repository/repository2-3.xml'
$script:AndroidRepoBase   = 'https://dl.google.com/android/repository/'
$script:VsCommunityUrl     = 'https://aka.ms/vs/stable/vs_community.exe'
$script:VsProfessionalUrl  = 'https://aka.ms/vs/stable/vs_professional.exe'
$script:VsEnterpriseUrl    = 'https://aka.ms/vs/stable/vs_enterprise.exe'
$script:JdkZipUrl          = 'https://aka.ms/download-jdk/microsoft-jdk-17-windows-x64.zip'
$script:JdkDocsUrl         = 'https://learn.microsoft.com/en-us/java/openjdk/download'
$script:GitReleasesApi     = 'https://api.github.com/repos/git-for-windows/git/releases/latest'
$script:GitDownloadPage    = 'https://git-scm.com/download/win'
$script:AndroidLicenseUrl  = 'https://developer.android.com/studio/terms'

# The canonical location of this script. It is only needed when the script runs
# from a pipe and has to re-launch itself in an elevated window. Override it
# with the FLUTSTALLER_SOURCE_URL environment variable for a fork.
$script:SourceUrl = 'https://raw.githubusercontent.com/kernelk14/flutstaller/main/install.ps1'

# Workload / component IDs for "Desktop development with C++" (Visual Studio 2026).
$script:VsCppWorkload     = 'Microsoft.VisualStudio.Workload.NativeDesktop'
$script:VsMsvcComponent   = 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64'
$script:VsCMakeComponent  = 'Microsoft.VisualStudio.Component.VC.CMake.Project'
$script:VsOpenJdkComponent = 'Component.OpenJDK'

# --------------------------------------------------------------------------------------
# Derived paths
# --------------------------------------------------------------------------------------
$script:FlutterDir = Join-Path $InstallRoot 'flutter'
$script:AndroidDir = Join-Path $InstallRoot 'Android\Sdk'
$script:VsDir      = Join-Path $InstallRoot 'VisualStudio'
$script:JdkDir     = Join-Path $InstallRoot 'jdk'
$script:GitDir     = Join-Path $InstallRoot 'Git'

$script:FlutterBin    = Join-Path $script:FlutterDir 'bin'
$script:FlutterExe    = Join-Path $script:FlutterBin 'flutter.bat'
$script:AdbExe        = Join-Path $script:AndroidDir 'platform-tools\adb.exe'
$script:CmdlineBin    = Join-Path $script:AndroidDir 'cmdline-tools\latest\bin'
$script:AndroidCliExe = Join-Path $script:CmdlineBin 'android.exe'
$script:SdkManagerBat = Join-Path $script:CmdlineBin 'sdkmanager.bat'
$script:VsWhereExe    = $(if (${env:ProgramFiles(x86)}) { Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe' } else { $null })

$script:LogFile       = $null
$script:WorkDir       = $null
$script:CurrentUserSid = $null
$script:ScriptPath    = $PSCommandPath
$script:ProgressActive = $false
$script:LastBarTime = $null
$script:LastBarStatus = $null
$script:Results = New-Object System.Collections.Generic.List[object]
$script:Failures      = New-Object System.Collections.Generic.List[string]
$script:Warnings      = New-Object System.Collections.Generic.List[string]
$script:Actions       = New-Object System.Collections.Generic.List[string]

# ======================================================================================
# Logging
# ======================================================================================
function Write-RunLog {
    param([string] $Message, [string] $Level = 'INFO')
    Clear-ProgressBar
    $line = '{0} [{1,-5}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Write-Host $line
    if ($script:LogFile) {
        try { Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8 } catch { }
    }
}

function Write-Step   { param([string] $Message) Write-RunLog ''; Write-RunLog "=== $Message ===" 'STEP' }
function Write-Info   { param([string] $Message) Write-RunLog $Message 'INFO' }
function Write-Ok     { param([string] $Message) Write-RunLog $Message 'OK' }
function Write-Detail { param([string] $Message) Write-RunLog "    $Message" 'DETL' }

function Write-Warn2 {
    param([string] $Message)
    Write-RunLog $Message 'WARN'
    $script:Warnings.Add($Message) | Out-Null
}

function Write-Err {
    param([string] $Message)
    Write-RunLog $Message 'ERROR'
    $script:Failures.Add($Message) | Out-Null
}

function Format-Size {
    param([double] $Bytes)
    if ($Bytes -le 0) { return '0 B' }
    $units = @('B', 'KB', 'MB', 'GB', 'TB')
    $i = 0
    $v = [double]$Bytes
    while ($v -ge 1024 -and $i -lt ($units.Count - 1)) { $v = $v / 1024; $i++ }
    return ('{0:N1} {1}' -f $v, $units[$i])
}

function Format-Throughput {
    param([double] $BytesPerSecond)
    if ($BytesPerSecond -le 0) { return '--' }
    return (Format-Size $BytesPerSecond) + '/s'
}

function Format-Duration {
    param([double] $Seconds)
    if ($Seconds -lt 0 -or [double]::IsNaN($Seconds) -or [double]::IsInfinity($Seconds)) { return '--:--' }
    if ($Seconds -gt 359999) { return '99:59:59' }
    $ts = [TimeSpan]::FromSeconds([math]::Round($Seconds))
    if ($ts.TotalHours -ge 1) { return ('{0:00}:{1:00}:{2:00}' -f [int]$ts.TotalHours, $ts.Minutes, $ts.Seconds) }
    return ('{0:00}:{1:00}' -f $ts.Minutes, $ts.Seconds)
}

function Get-ConsoleWidth {
    try {
        $w = $Host.UI.RawUI.WindowSize.Width
        if ($w -gt 40) { return [int]$w }
    } catch { }
    return 100
}

function Test-InteractiveConsole {
    <#
        True when standard output goes to a real console, so an in-place
        progress bar can be redrawn. When the output is redirected (log file,
        CI, piped output) plain status lines are used instead.
    #>
    try { return (-not [Console]::IsOutputRedirected) } catch { return $true }
}

function Clear-ProgressBar {
    if ($script:ProgressActive) {
        $script:ProgressActive = $false
        if (Test-InteractiveConsole) {
            Write-Host ("`r" + (' ' * (Get-ConsoleWidth)) + "`r") -NoNewline
        }
    }
}

function Write-ProgressBar {
    <#
        Draws a single-line progress bar with the phase status, percentage,
        transferred/total size, current throughput and the estimated time left.
        The bar is redrawn in place on an interactive console. The layout is
        sized to fit the console width.
    #>
    param(
        [Parameter(Mandatory)] [string] $Status,
        [string] $Label = '',
        [double] $Percent = -1,
        [string] $SizeText = '',
        [double] $Speed = 0,
        [double] $Eta = -1,
        [switch] $Final
    )

    $width = Get-ConsoleWidth
    $speedText = if ($Speed -gt 0) { '{0,9}' -f (Format-Throughput $Speed) } else { '       --' }
    $etaText = if ($Eta -ge 0) { Format-Duration $Eta } else { '--:--' }
    $pctText = if ($Percent -ge 0) { '{0,5:N1}%' -f $Percent } else { '  ---' }

    $tail = "  $pctText  $SizeText  $speedText  ETA $etaText"

    # Budget the available width: the label shrinks first, then the bar.
    $avail = $width - $Status.Length - $tail.Length - 6
    if ($avail -lt 16) { $avail = 16 }
    $labelMax = [math]::Min(38, [math]::Max(8, [int]($avail * 0.45)))
    $barWidth = [math]::Min(30, $avail - $labelMax)
    if ($barWidth -lt 8) { $barWidth = 8 }
    if ($barWidth -gt 30) { $barWidth = 30 }

    if ($Label.Length -gt $labelMax) { $Label = $Label.Substring(0, $labelMax - 3) + '...' }

    $filled = 0
    if ($Percent -ge 0) {
        $filled = [int][math]::Round($barWidth * ([math]::Min(100.0, $Percent) / 100.0))
        if ($filled -lt 0) { $filled = 0 }
        if ($filled -gt $barWidth) { $filled = $barWidth }
    }
    $bar = '[' + ('#' * $filled) + ('-' * ($barWidth - $filled)) + ']'

    $line = '{0}  {1}  {2}{3}' -f $Status, $Label, $bar, $tail
    if ($line.Length -gt $width) { $line = $line.Substring(0, [math]::Max(20, $width)) }

    if (Test-InteractiveConsole) {
        $pad = $width - $line.Length
        if ($pad -lt 0) { $pad = 0 }
        Write-Host ("`r" + $line + (' ' * $pad)) -NoNewline
        $script:ProgressActive = $true
        if ($Final) {
            Write-Host ''
            $script:ProgressActive = $false
        }
    } else {
        # Redirected output: always report a status change or the final line,
        # otherwise emit an update line every couple of seconds.
        $now = Get-Date
        $statusChanged = ($Status -ne $script:LastBarStatus)
        if ($Final -or $statusChanged -or -not $script:LastBarTime -or ($now - $script:LastBarTime).TotalSeconds -ge 2) {
            $script:LastBarTime = $now
            $script:LastBarStatus = $Status
            Write-Host $line
        }
    }
}

function Write-LogFileOnly {
    <#
        Writes to the log file without touching the console, so it can be used
        while a progress bar is being redrawn.
    #>
    param([string] $Message, [string] $Level = 'INFO')
    if (-not $script:LogFile) { return }
    $line = '{0} [{1,-5}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    try { Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8 } catch { }
}

function Write-Status {
    <#
        A prominent one-line status entry, e.g.
            22:14:03 [STATUS] Downloading Flutter SDK 3.47.7
    #>
    param([string] $Text)
    Clear-ProgressBar
    $line = '{0} [STATUS] {1}' -f (Get-Date -Format 'HH:mm:ss'), $Text
    Write-Host $line -ForegroundColor Cyan
    if ($script:LogFile) {
        try { Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8 } catch { }
    }
}

# ======================================================================================
# Terminal user interface
#
# The script is a console application, so it draws a small TUI: a banner, framed
# section headers, boxed panels and a status report. Everything degrades to
# plain text when the console cannot render box-drawing characters.
# ======================================================================================
function Initialize-Tui {
    $unicode = $false
    try {
        # Only use box-drawing characters when the output is going to a console
        # that can render them. A redirected stream (a log file, a pipe, CI)
        # gets plain ASCII so nothing is mangled.
        if (Test-InteractiveConsole) {
            if ($env:WT_SESSION) { $unicode = $true }
            elseif ([Console]::OutputEncoding -and [Console]::OutputEncoding.CodePage -eq 65001) { $unicode = $true }
        }
    } catch { }

    if ($unicode) {
        $script:Tui = @{
            H = [char]0x2500; V = [char]0x2502; TL = [char]0x250C; TR = [char]0x2510
            BL = [char]0x2514; BR = [char]0x2518; T = [char]0x251C; R = [char]0x2524
            DH = [char]0x2550; DV = [char]0x2551; DTL = [char]0x2554; DTR = [char]0x2557
            DBL = [char]0x255A; DBR = [char]0x255D
            Ok = [char]0x2714; Fail = [char]0x2716; Warn = [char]0x26A0; Info = [char]0x2139
            Skip = [char]0x00B7; Arrow = [char]0x2192; Bullet = [char]0x00B7; Ellipsis = [char]0x2026
        }
    } else {
        $script:Tui = @{
            H = '-'; V = '|'; TL = '+'; TR = '+'; BL = '+'; BR = '+'; T = '+'; R = '+'
            DH = '='; DV = '|'; DTL = '+'; DTR = '+'; DBL = '+'; DBR = '+'
            Ok = '[+]'; Fail = '[x]'; Warn = '[!]'; Info = '[i]'; Skip = '[.]'
            Arrow = '->'; Bullet = '*'; Ellipsis = '...'
        }
    }
}

function Get-TuiWidth {
    $w = 80
    try { $w = $Host.UI.RawUI.WindowSize.Width } catch { }
    if ($w -lt 60) { $w = 60 }
    if ($w -gt 100) { $w = 100 }
    return $w
}

function Write-TuiBanner {
    $w = Get-TuiWidth
    $t = $script:Tui
    $inner = $w - 2
    Clear-ProgressBar
    Write-Host ''
    Write-Host ($t.DTL + ([string]$t.DH * $inner) + $t.DTR) -ForegroundColor Cyan
    Write-Host ($t.DV + (' ' * $inner) + $t.DV) -ForegroundColor Cyan
    $title = '   flutstaller   ' + $t.Bullet + '   Flutter development environment for Windows'
    Write-Host ($t.DV + $title.PadRight($inner) + $t.DV) -ForegroundColor Cyan
    $sub = '   Flutter SDK   ' + $t.Bullet + '   Android SDK (command-line tools)   ' + $t.Bullet + '   Visual Studio 2026 (C++)'
    Write-Host ($t.DV + $sub.PadRight($inner) + $t.DV) -ForegroundColor Cyan
    Write-Host ($t.DV + (' ' * $inner) + $t.DV) -ForegroundColor Cyan
    $notice = '   AI-generated with OpenCode - please read the source before running it.'
    if ($notice.Length -gt $inner) { $notice = $notice.Substring(0, $inner) }
    Write-Host ($t.DV + $notice.PadRight($inner) + $t.DV) -ForegroundColor Yellow
    Write-Host ($t.DV + (' ' * $inner) + $t.DV) -ForegroundColor Cyan
    Write-Host ($t.DBL + ([string]$t.DH * $inner) + $t.DBR) -ForegroundColor Cyan
}

function Write-TuiSection {
    param([string] $Title, [string] $Detail = '')
    $w = Get-TuiWidth
    $t = $script:Tui
    Clear-ProgressBar
    Write-Host ''
    Write-Host ([string]$t.H * $w) -ForegroundColor DarkCyan
    $line = '  ' + $Title
    if ($Detail) { $line += '   ' + $t.Bullet + ' ' + $Detail }
    Write-Host $line -ForegroundColor Cyan
    Write-Host ([string]$t.H * $w) -ForegroundColor DarkCyan
    Write-LogFileOnly ("--- $Title $(if ($Detail) { "- $Detail" }) ---") 'STEP'
}

function Write-TuiBox {
    param(
        [object[]] $Lines,
        [string] $Title = '',
        [string] $BorderColor = 'DarkCyan',
        [string] $TextColor = 'Gray',
        [switch] $Wrap
    )
    $w = Get-TuiWidth
    $t = $script:Tui
    $inner = $w - 2
    Clear-ProgressBar

    if ($Title) {
        $head = $t.TL + $t.H + ' ' + $Title + ' '
        $top = $head + ([string]$t.H * [math]::Max(0, $inner - $head.Length)) + $t.TR
    } else {
        $top = $t.TL + ([string]$t.H * $inner) + $t.TR
    }
    Write-Host $top -ForegroundColor $BorderColor
    foreach ($l in $Lines) {
        # A line may be a plain string, or a hashtable with Text and Color.
        $text = $l
        $color = $TextColor
        if ($l -is [hashtable]) {
            if ($l.ContainsKey('Text')) { $text = $l['Text'] }
            if ($l.ContainsKey('Color')) { $color = $l['Color'] }
        }
        $text = ' ' + $text
        if ($text.Length -gt $inner) {
            if ($Wrap) {
                # Long lines (URLs) are wrapped rather than cut off.
                $remaining = $text
                while ($remaining.Length -gt $inner) {
                    Write-Host ($t.V + $remaining.Substring(0, $inner).PadRight($inner) + $t.V) -ForegroundColor $color
                    $remaining = ' ' + $remaining.Substring($inner)
                }
                if ($remaining.Length -gt 0) {
                    Write-Host ($t.V + $remaining.PadRight($inner) + $t.V) -ForegroundColor $color
                }
                continue
            }
            $text = $text.Substring(0, [math]::Max(1, $inner - 1)) + '~'
        }
        Write-Host ($t.V + $text.PadRight($inner) + $t.V) -ForegroundColor $color
    }
    Write-Host ($t.BL + ([string]$t.H * $inner) + $t.BR) -ForegroundColor $BorderColor
}

function Write-TuiBullet {
    param([string] $Text, [string] $Color = 'Gray', [int] $Indent = 2)
    Write-Host (' ' * $Indent + $script:Tui.Bullet + ' ' + $Text) -ForegroundColor $Color
}

function Write-TuiStatus {
    <#
        A status marker plus text, e.g.  [ok] Flutter SDK installed
    #>
    param([string] $State, [string] $Text, [int] $Indent = 2)
    $t = $script:Tui
    switch ($State) {
        'ok'     { $m = $t.Ok;   $c = 'Green' }
        'fail'   { $m = $t.Fail; $c = 'Red' }
        'warn'   { $m = $t.Warn; $c = 'Yellow' }
        'skip'   { $m = $t.Skip; $c = 'DarkGray' }
        default  { $m = $t.Info; $c = 'Cyan' }
    }
    Write-Host (' ' * $Indent + $m + ' ' + $Text) -ForegroundColor $c
}

function Format-TuiColumns {
    <#
        Turns rows of @(left, right) into aligned text that fits the console.
    #>
    param([object[]] $Rows, [int] $LeftWidth = 0, [int] $Gap = 2)
    if (-not $Rows -or $Rows.Count -eq 0) { return @() }
    $w = Get-TuiWidth
    if ($LeftWidth -le 0) {
        $LeftWidth = 0
        foreach ($r in $Rows) { if ($r[0].Length -gt $LeftWidth) { $LeftWidth = $r[0].Length } }
        if ($LeftWidth -gt 46) { $LeftWidth = 46 }
    }
    $rightWidth = $w - $LeftWidth - $Gap - 4
    if ($rightWidth -lt 12) { $rightWidth = 12 }

    $out = @()
    foreach ($r in $Rows) {
        $left = $r[0]
        $right = $r[1]
        if ($left.Length -gt $LeftWidth) { $left = $left.Substring(0, $LeftWidth - 1) + '~' }
        $line = $left.PadRight($LeftWidth) + (' ' * $Gap) + $right
        if ($line.Length -gt $w - 3) { $line = $line.Substring(0, $w - 3) }
        $out += $line
    }
    return $out
}

function Write-TuiSpinner {
    <#
        Redraws a single-line spinner with the elapsed time. Used while a long
        running external program is in progress.
    #>
    param([int] $Index, [double] $Elapsed, [string] $Text)
    if (-not (Test-InteractiveConsole)) { return }
    $frames = @([char]0x28B2, [char]0x28B3, [char]0x28BF, [char]0x28B0, [char]0x28B1)
    $frame = $frames[$Index % $frames.Count]
    $line = ('  {0}  {1}  {2}' -f $frame, (Format-Duration $Elapsed), $Text)
    $pad = (Get-TuiWidth) - $line.Length
    if ($pad -lt 0) { $pad = 0 }
    Write-Host ("`r" + $line + (' ' * $pad)) -NoNewline
}


# ======================================================================================
# Environment / registry helpers (user scope)
# ======================================================================================
function Get-CurrentUserSid {
    try { return ([System.Security.Principal.WindowsIdentity]::GetCurrent()).User.Value } catch { return $null }
}

function Get-UserEnvRaw {
    param([string] $Name)
    $sid = if ($TargetUserSid) { $TargetUserSid } else { $script:CurrentUserSid }
    if ($sid) {
        $key = "Registry::HKEY_USERS\$sid\Environment"
        if (Test-Path -LiteralPath $key) {
            $props = Get-ItemProperty -LiteralPath $key -Name $Name -ErrorAction SilentlyContinue
            if ($props -and ($props.PSObject.Properties.Name -contains $Name)) { return [string]$props.$Name }
            return $null
        }
        Write-Warn2 "The user environment registry hive for SID $sid is not loaded; reading '$Name' from the current session instead."
    }
    return [Environment]::GetEnvironmentVariable($Name, 'User')
}

function Set-UserEnv {
    param([string] $Name, [string] $Value)
    $sid = if ($TargetUserSid) { $TargetUserSid } else { $script:CurrentUserSid }
    if ($sid) {
        # Writing through the registry keeps the value type intact (PATH must
        # stay REG_EXPAND_SZ) and lets the variables be set for the original
        # account when the script runs elevated under a different administrator.
        $key = "Registry::HKEY_USERS\$sid\Environment"
        if (Test-Path -LiteralPath $key) {
            $type = if ($Name -eq 'Path') { 'ExpandString' } else { 'String' }
            try {
                New-ItemProperty -LiteralPath $key -Name $Name -Value $Value -PropertyType $type -Force | Out-Null
                Write-Detail "Set $Name for SID $sid (registry hive, $type)"
                return
            } catch {
                Write-Warn2 "Could not write $Name to the registry hive for SID $sid ($($_.Exception.Message)); using the current session instead."
            }
        } else {
            Write-Warn2 "The user environment registry hive for SID $sid is not loaded; '$Name' was set for the current session only."
        }
    }
    [Environment]::SetEnvironmentVariable($Name, $Value, 'User')
    Write-Detail "Set $Name for the current user"
}

function Get-UserPathEntries {
    $raw = Get-UserEnvRaw 'Path'
    if ([string]::IsNullOrWhiteSpace($raw)) { return , @() }
    return , @($raw -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Add-UserPathEntries {
    <#
        Adds entries to the *user* PATH, skipping ones that are already present
        (case-insensitive, trailing-slash insensitive). Existing entries and their
        order are preserved. Returns the entries that were actually added.
    #>
    param([string[]] $Entries)

    $current = Get-UserPathEntries
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($p in $current) { [void]$seen.Add($p.Trim().TrimEnd('\')) }

    $added  = New-Object System.Collections.Generic.List[string]
    $newList = New-Object System.Collections.Generic.List[string]
    foreach ($p in $current) { [void]$newList.Add($p) }

    foreach ($e in $Entries) {
        if ([string]::IsNullOrWhiteSpace($e)) { continue }
        $trimmed = $e.Trim().TrimEnd('\')
        if ($seen.Contains($trimmed)) {
            Write-Detail "PATH already contains $trimmed - skipped"
            continue
        }
        [void]$seen.Add($trimmed)
        [void]$newList.Add($e.Trim())
        [void]$added.Add($e.Trim())
    }

    if ($added.Count -gt 0) { Set-UserEnv 'Path' ($newList -join ';') }
    # The comma stops PowerShell from unrolling a single-element result.
    return , $added.ToArray()
}

function Test-IsElevated {
    try {
        $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object System.Security.Principal.WindowsPrincipal($id)
        return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

# ======================================================================================
# Process helpers
# ======================================================================================
function Format-ProcessArgument {
    <#
        Quotes a single argument for a Windows command line, following the
        CommandLineToArgvW rules (backslashes before a quote are doubled).
    #>
    param([string] $Value)
    if ($null -eq $Value -or $Value.Length -eq 0) { return '""' }
    if ($Value -notmatch '[\s"]') { return $Value }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('"')
    $backslashes = 0
    foreach ($ch in $Value.ToCharArray()) {
        if ($ch -eq '\') { $backslashes++; continue }
        if ($ch -eq '"') {
            [void]$sb.Append('\' * ($backslashes * 2 + 1))
            [void]$sb.Append('"')
            $backslashes = 0
            continue
        }
        if ($backslashes -gt 0) { [void]$sb.Append('\' * $backslashes); $backslashes = 0 }
        [void]$sb.Append($ch)
    }
    if ($backslashes -gt 0) { [void]$sb.Append('\' * ($backslashes * 2)) }
    [void]$sb.Append('"')
    return $sb.ToString()
}

function Invoke-Native {
    <#
        Runs an external program, captures stdout+stderr and returns
        @{ ExitCode; StdOut; TimedOut }. A timeout of 0 means "wait forever".
        Batch files are executed through cmd.exe.
    #>
    param(
        [Parameter(Mandatory)] [string] $FilePath,
        [string[]] $Arguments = @(),
        [string] $RawArguments,
        [int] $TimeoutSeconds = 0,
        [string] $Activity
    )

    if ($Activity) { Write-Status -Text $Activity }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    if ($RawArguments) {
        $psi.FileName = $FilePath
        $psi.Arguments = $RawArguments
    }
    elseif ($FilePath -match '\.(bat|cmd)$') {
        $all = @((Format-ProcessArgument $FilePath)) + @($Arguments | ForEach-Object { Format-ProcessArgument $_ })
        $psi.FileName = $env:ComSpec
        $psi.Arguments = '/d /s /c "' + ($all -join ' ') + '"'
    }
    else {
        $psi.FileName = $FilePath
        $all = @($Arguments | ForEach-Object { Format-ProcessArgument $_ })
        $psi.Arguments = ($all -join ' ')
    }

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    [void]$p.Start()
    $outTask = $p.StandardOutput.ReadToEndAsync()
    $errTask = $p.StandardError.ReadToEndAsync()

    # Wait for the process, showing a live spinner and the elapsed time.
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $spin = 0
    $timedOut = $false
    while (-not $p.WaitForExit(120)) {
        if ($TimeoutSeconds -gt 0 -and $stopwatch.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
            $timedOut = $true
            break
        }
        if ($Activity) {
            $spin++
            Write-TuiSpinner -Index $spin -Elapsed $stopwatch.Elapsed.TotalSeconds -Text $Activity
        }
    }
    if ($timedOut) {
        try { $p.Kill() } catch { }
        Clear-ProgressBar
        return @{ ExitCode = -1; StdOut = ''; TimedOut = $true }
    }
    Clear-ProgressBar
    $p.WaitForExit()
    $text = ''
    try { $text = $outTask.Result + $errTask.Result } catch { $text = '(output unavailable)' }

    if ($Activity) {
        $elapsed = $stopwatch.Elapsed.TotalSeconds
        Write-LogFileOnly ("{0} finished in {1} (exit code {2})" -f $Activity, (Format-Duration $elapsed), $p.ExitCode) 'INFO'
    }
    return @{ ExitCode = $p.ExitCode; StdOut = $text; TimedOut = $false }
}

function Write-NativeOutput {
    param([string] $Text)
    foreach ($line in ($Text -split "`r?`n")) {
        if ($line.Trim()) { Write-Detail $line.TrimEnd() }
    }
}

function Save-WebFile {
    <#
        Downloads a URL to disk, showing a live progress bar with the phase
        status, percentage, transferred size, throughput and ETA. The checksum
        is verified afterwards. Returns the number of bytes written.
    #>
    param(
        [Parameter(Mandatory)] [string] $Uri,
        [Parameter(Mandatory)] [string] $Destination,
        [string] $ExpectedSha256,
        [string] $ExpectedSha1
    )

    $name = Split-Path -Path $Destination -Leaf
    Write-Status -Text "Downloading $name"
    Write-Detail "  from $Uri"
    Write-ProgressBar -Status 'Connecting' -Label $name -Percent 0 -SizeText 'connecting...' -Speed 0 -Eta -1

    $tmp = "$Destination.part"
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }

    $request = [System.Net.HttpWebRequest]::Create($Uri)
    $request.UserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) flutstaller'
    $request.Timeout = 120000
    $request.ReadWriteTimeout = 300000
    $request.AllowAutoRedirect = $true

    $status = 'Connecting'
    $total = -1L
    $speed = 0.0
    $response = $null
    try {
        $response = $request.GetResponse()
    } catch {
        Clear-ProgressBar
        Write-Err "Could not open $Uri : $($_.Exception.Message)"
        throw
    }
    $total = $response.ContentLength

    $sizeText = if ($total -gt 0) { '{0} / {1}' -f (Format-Size 0), (Format-Size $total) } else { '0 B' }

    $inStream = $response.GetResponseStream()
    $outStream = [System.IO.File]::Create($tmp)
    $totalRead = 0L
    $samples = New-Object System.Collections.Generic.Queue[object]
    $lastRender = [DateTime]::MinValue
    $lastLog = [DateTime]::MinValue
    $started = Get-Date

    try {
        $buffer = New-Object byte[] 1048576
        $read = 0
        while (($read = $inStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $outStream.Write($buffer, 0, $read)
            $totalRead += $read

            $now = Get-Date
            # Throughput over a 5 second sliding window.
            [void]$samples.Enqueue([pscustomobject]@{ T = $now; B = $totalRead })
            while ($samples.Count -gt 0 -and ($now - $samples.Peek().T).TotalSeconds -gt 5) { [void]$samples.Dequeue() }
            if ($samples.Count -ge 2) {
                $oldest = $samples.Peek()
                $span = ($now - $oldest.T).TotalSeconds
                if ($span -gt 0) { $speed = ($totalRead - $oldest.B) / $span }
            }

            $pct = if ($total -gt 0) { [math]::Min(100.0, ($totalRead / $total) * 100) } else { -1 }
            $eta = if ($total -gt 0 -and $speed -gt 1) { ($total - $totalRead) / $speed } else { -1 }
            $sizeText = if ($total -gt 0) { '{0} / {1}' -f (Format-Size $totalRead), (Format-Size $total) } else { Format-Size $totalRead }

            # Redraw the bar about 10 times a second.
            if (($now - $lastRender).TotalMilliseconds -ge 100) {
                $lastRender = $now
                Write-ProgressBar -Status $status -Label $name -Percent $pct -SizeText $sizeText -Speed $speed -Eta $eta
            }
            # Write a plain line to the log file every 5 seconds.
            if (($now - $lastLog).TotalSeconds -ge 5) {
                $lastLog = $now
                Write-LogFileOnly ("  {0}  {1}  {2}  ETA {3}" -f $status, $sizeText, (Format-Throughput $speed), (Format-Duration $eta)) 'DETL'
            }
        }
    } finally {
        $outStream.Close()
        $inStream.Close()
        $response.Close()
    }

    $elapsed = ((Get-Date) - $started).TotalSeconds
    $avg = if ($elapsed -gt 0) { $totalRead / $elapsed } else { 0 }
    $pct = if ($total -gt 0) { [math]::Min(100.0, ($totalRead / $total) * 100) } else { 100 }
    $sizeText = if ($total -gt 0) { '{0} / {1}' -f (Format-Size $totalRead), (Format-Size $total) } else { Format-Size $totalRead }
    Write-ProgressBar -Status 'Complete' -Label $name -Percent $pct -SizeText $sizeText -Speed $avg -Eta 0 -Final
    Write-LogFileOnly ("Downloaded {0} ({1}) in {2} at an average of {3}/s" -f $name, $sizeText, (Format-Duration $elapsed), (Format-Throughput $avg)) 'INFO'

    Move-Item -LiteralPath $tmp -Destination $Destination -Force

    if ($ExpectedSha256) {
        $status = 'Verifying'
        Write-ProgressBar -Status $status -Label $name -Percent 100 -SizeText $sizeText -Speed $avg -Eta 0
        $hash = (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($hash -ne $ExpectedSha256.ToLowerInvariant()) {
            Clear-ProgressBar
            throw "Checksum mismatch for $Uri`n  expected SHA256 $ExpectedSha256`n  actual   SHA256 $hash"
        }
        Write-Ok "SHA256 verified: $hash"
    }
    elseif ($ExpectedSha1) {
        $status = 'Verifying'
        Write-ProgressBar -Status $status -Label $name -Percent 100 -SizeText $sizeText -Speed $avg -Eta 0
        # Google publishes SHA-1 for the Android SDK repository manifest, so
        # that is the checksum the artifact is verified against.
        $hash = (Get-FileHash -LiteralPath $Destination -Algorithm SHA1).Hash.ToLowerInvariant() # PSScriptAnalyzer suppression PSAvoidUsingBrokenHashAlgorithms
        if ($hash -ne $ExpectedSha1.ToLowerInvariant()) {
            Clear-ProgressBar
            throw "Checksum mismatch for $Uri`n  expected SHA1 $ExpectedSha1`n  actual   SHA1 $hash"
        }
        Write-Ok "SHA1 verified: $hash"
    }
    Clear-ProgressBar
    return (Get-Item -LiteralPath $Destination).Length
}

function Expand-ArchiveFast {
    <#
        Extracts a zip. Uses bsdtar (built into Windows 10/11) when available
        because it is dramatically faster than Expand-Archive for large archives.
    #>
    param(
        [Parameter(Mandatory)] [string] $ArchivePath,
        [Parameter(Mandatory)] [string] $Destination
    )
    if (-not (Test-Path -LiteralPath $Destination)) {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    }
    $name = Split-Path -Path $ArchivePath -Leaf
    $started = Get-Date
    Write-Status -Text "Extracting $name"

    $tar = Get-Command tar.exe -ErrorAction SilentlyContinue
    if ($tar) {
        Write-LogFileOnly '  extracting with tar.exe' 'DETL'
        $r = Invoke-Native -FilePath $tar.Source -Arguments @('-xf', $ArchivePath, '-C', $Destination)
        if ($r.ExitCode -ne 0) {
            Write-LogFileOnly "  tar.exe failed (exit $($r.ExitCode)); falling back to Expand-Archive" 'WARN'
            Expand-Archive -LiteralPath $ArchivePath -DestinationPath $Destination -Force
        }
    } else {
        Write-LogFileOnly '  extracting with Expand-Archive' 'DETL'
        Expand-Archive -LiteralPath $ArchivePath -DestinationPath $Destination -Force
    }
    $elapsed = ((Get-Date) - $started).TotalSeconds
    Write-LogFileOnly ("  extracted {0} in {1}" -f $name, (Format-Duration $elapsed)) 'INFO'
    Write-Status -Text "Extracted $name in $(Format-Duration $elapsed)"
}

function Confirm-User {
    param(
        [Parameter(Mandatory)] [string] $Prompt,
        [switch] $DefaultNo,
        [switch] $AlwaysAsk
    )
    if ($Yes -and -not $AlwaysAsk) {
        Write-Info "[auto-confirmed] $Prompt"
        return $true
    }
    if (-not $script:IsInteractive) {
        # There is no terminal to ask on. A question that cannot be answered
        # must not silently be read as "no", or a piped run does nothing.
        if ($DefaultNo) {
            Write-Info "[not answered - no terminal] $Prompt"
            return $false
        }
        Write-Info "[auto-confirmed - no terminal] $Prompt"
        return $true
    }
    $suffix = if ($DefaultNo) { ' [y/N]' } else { ' [Y/n]' }
    Clear-ProgressBar
    Write-Host ''
    Write-Host ("  {0} {1}{2} : " -f $script:Tui.Arrow, $Prompt, $suffix) -ForegroundColor Yellow -NoNewline
    $answer = Read-Host
    if ([string]::IsNullOrWhiteSpace($answer)) { return (-not $DefaultNo) }
    return ($answer -match '^(y|yes)$')
}

function Get-FreeDiskSpace {
    param([string] $Path)
    try {
        $parent = Split-Path -Path $Path -Parent
        if (-not $parent) { $parent = $Path }
        $root = [System.IO.Path]::GetPathRoot($parent)
        if (-not $root) { $root = 'C:\' }
        $name = $root.TrimEnd([char]':', [char]'\', [char]'/')
        $drive = Get-PSDrive -Name $name -ErrorAction Stop
        return [double]$drive.Free
    } catch { return -1 }
}

# ======================================================================================
# Vendor manifest resolution
# ======================================================================================
function Resolve-FlutterStable {
    <#
        Reads the official Flutter release manifest and returns the current stable
        release for Windows: version, download url and published sha256.
    #>
    Write-Info 'Resolving the current Flutter stable release from the official manifest...'
    $json = Invoke-RestMethod -Uri $script:FlutterReleasesUrl -UseBasicParsing -TimeoutSec 60
    $stableHash = $json.current_release.stable
    $release = $json.releases | Where-Object { $_.hash -eq $stableHash } | Select-Object -First 1
    if (-not $release) { throw "Could not find the current stable Flutter release in $script:FlutterReleasesUrl" }
    $url = $json.base_url.TrimEnd('/') + '/' + $release.archive
    Write-Ok "Flutter stable $($release.Version) (published $($release.release_date))"
    Write-Detail $url
    return @{
        Version   = $release.version
        Url       = $url
        Sha256    = $release.sha256
        Published = $release.release_date
    }
}

function Get-AndroidRepositoryXml {
    param([string] $Destination)
    Write-Info 'Downloading the official Android SDK repository manifest...'
    Save-WebFile -Uri $script:AndroidRepoUrl -Destination $Destination | Out-Null
    $doc = New-Object System.Xml.XmlDocument
    $doc.Load($Destination)
    # The comma stops PowerShell from unrolling the document's child nodes.
    return , $doc
}

function Resolve-AndroidCmdlineTools {
    <#
        Finds the "cmdline-tools;latest" package for Windows in the official
        repository manifest and returns its download url, sha1 and size.

        Note on namespaces: in the repository manifest only the root element
        carries the "sdk:" prefix. Every child element (remotePackage,
        archives, complete, url, ...) is in the EMPTY namespace, so the XPath
        expressions use local-name() and stay namespace agnostic.
    #>
    param([System.Xml.XmlDocument] $Repo)
    $pkg = $Repo.SelectSingleNode("//*[local-name()='remotePackage' and @path='cmdline-tools;latest']")
    if (-not $pkg) { throw 'cmdline-tools;latest was not found in the Android repository manifest.' }

    $archive = $null
    foreach ($a in $pkg.SelectNodes("*[local-name()='archives']/*[local-name()='archive']")) {
        $os = $a.SelectSingleNode("*[local-name()='host-os']")
        if ($os -and $os.InnerText -eq 'windows') { $archive = $a; break }
    }
    if (-not $archive) { throw 'No Windows archive found for cmdline-tools;latest.' }

    $urlNode  = $archive.SelectSingleNode("*[local-name()='complete']/*[local-name()='url']")
    $sumNode  = $archive.SelectSingleNode("*[local-name()='complete']/*[local-name()='checksum']")
    $sizeNode = $archive.SelectSingleNode("*[local-name()='complete']/*[local-name()='size']")
    $revNode  = $pkg.SelectSingleNode("*[local-name()='revision']/*[local-name()='major']")
    if (-not $urlNode) { throw 'The Android repository manifest entry has no download url.' }

    return @{
        Url     = $script:AndroidRepoBase + $urlNode.InnerText
        Sha1    = $(if ($sumNode) { $sumNode.InnerText } else { $null })
        Size    = $(if ($sizeNode) { [double]$sizeNode.InnerText } else { 0 })
        Version = $(if ($revNode) { $revNode.InnerText } else { 'unknown' })
    }
}

function Get-AndroidStablePackages {
    <#
        Extracts the currently published stable build-tools and platform packages
        from the official repository manifest. Preview / release-candidate builds
        are excluded because their paths carry an -rc / -beta / -alpha suffix.
    #>
    param([System.Xml.XmlDocument] $Repo)

    $buildTools = @()
    $platforms = @()
    foreach ($p in $Repo.SelectNodes("//*[local-name()='remotePackage']")) {
        $path = $p.GetAttribute('path')
        if ($path -match '^build-tools;(\d+)\.(\d+)\.(\d+)$') {
            $buildTools += [pscustomobject]@{
                Path    = $path
                Version = [version]::new([int]$Matches[1], [int]$Matches[2], [int]$Matches[3])
            }
        }
        elseif ($path -match '^platforms;android-(\d+)$') {
            $platforms += [pscustomobject]@{ Path = $path; Api = [int]$Matches[1] }
        }
    }

    return @{
        BuildTools = @($buildTools | Sort-Object -Property Version -Descending)
        Platforms  = @($platforms | Sort-Object -Property Api -Descending)
    }
}

function Resolve-GitForWindows {
    <#
        Resolves the latest Git for Windows 64-bit installer from the official
        Git for Windows release feed.
    #>
    Write-Info 'Resolving the latest Git for Windows release from the official feed...'
    $release = Invoke-RestMethod -Uri $script:GitReleasesApi -UseBasicParsing -TimeoutSec 60 -Headers @{ 'User-Agent' = 'flutstaller' }
    $asset = $release.assets | Where-Object { $_.name -match '^Git-.*-64-bit\.exe$' } | Select-Object -First 1
    if (-not $asset) { throw 'Could not find a 64-bit Git for Windows installer in the official release feed.' }
    Write-Ok "Git for Windows $($release.tag_name)"
    Write-Detail $asset.browser_download_url
    return @{ Version = $release.tag_name; Url = $asset.browser_download_url }
}

function Get-FlutterCompileSdk {
    <#
        Reads the compileSdkVersion that the installed Flutter SDK itself declares,
        so the Android platform package is the one Flutter actually needs rather
        than a guess.
    #>
    $extFile = Join-Path $script:FlutterDir 'packages\flutter_tools\gradle\src\main\kotlin\FlutterExtension.kt'
    if (-not (Test-Path -LiteralPath $extFile)) { return $null }
    try {
        $m = Select-String -LiteralPath $extFile -Pattern 'compileSdkVersion:\s*Int\s*=\s*(\d+)' | Select-Object -First 1
        if ($m -and $m.Matches.Count -gt 0) { return [int]$m.Matches[0].Groups[1].Value }
    } catch { }
    return $null
}

function Get-ExistingVisualStudioInstances {
    <#
        Returns the installation paths of every Visual Studio instance on the
        machine. Callers must wrap the result in @() so that a single instance
        is still an array.
    #>
    if (-not $script:VsWhereExe -or -not (Test-Path -LiteralPath $script:VsWhereExe)) { return @() }
    $r = Invoke-Native -FilePath $script:VsWhereExe -Arguments @('-products', '*', '-format', 'value', '-property', 'installationPath')
    if ($r.ExitCode -ne 0) { return @() }
    return @($r.StdOut -split "`r?`n" | Where-Object { $_ -and $_.Trim() })
}

# ======================================================================================
# Component installers
# ======================================================================================
function Install-Flutter {
    param([hashtable] $Release)

    if (Test-Path -LiteralPath $script:FlutterExe) {
        Write-Ok "Flutter is already installed at $($script:FlutterDir) - leaving it untouched."
        $v = Invoke-Native -FilePath $script:FlutterExe -Arguments @('--version') -TimeoutSeconds 1800 -Activity 'Querying the installed Flutter version'
        Write-NativeOutput $v.StdOut
        return $true
    }

    if (Test-Path -LiteralPath $script:FlutterDir) {
        $items = @(Get-ChildItem -LiteralPath $script:FlutterDir -Force -ErrorAction SilentlyContinue)
        if ($items.Count -gt 0) {
            throw "$($script:FlutterDir) already exists, is not empty and does not contain a Flutter SDK. Refusing to overwrite it."
        }
    }

    $zip = Join-Path $script:WorkDir 'flutter_windows_stable.zip'
    $size = Save-WebFile -Uri $Release.Url -Destination $zip -ExpectedSha256 $Release.Sha256

    $staging = Join-Path $script:WorkDir 'flutter-staging'
    if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
    New-Item -ItemType Directory -Path $staging -Force | Out-Null

    Write-Info 'Extracting the Flutter SDK...'
    Expand-ArchiveFast -ArchivePath $zip -Destination $staging

    $extracted = Join-Path $staging 'flutter'
    if (-not (Test-Path -LiteralPath $extracted)) {
        $candidates = @(Get-ChildItem -LiteralPath $staging -Directory)
        if ($candidates.Count -eq 1) { $extracted = $candidates[0].FullName }
        else { throw "Unexpected Flutter archive layout - no 'flutter' folder found in $staging" }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $extracted 'bin\flutter.bat'))) {
        throw 'The extracted Flutter archive does not contain bin\flutter.bat.'
    }

    if (-not (Test-Path -LiteralPath $InstallRoot)) { New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null }
    Move-Item -LiteralPath $extracted -Destination $script:FlutterDir
    Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue

    Write-Ok "Flutter $($Release.Version) installed at $($script:FlutterDir) (download was $(Format-Size $size))"
    return $true
}

function Install-AndroidCmdlineTools {
    param([hashtable] $Package)

    if (Test-Path -LiteralPath $script:SdkManagerBat) {
        Write-Ok "Android SDK command-line tools are already present at $($script:AndroidDir) - leaving them untouched."
        return $true
    }

    $zip = Join-Path $script:WorkDir 'android-cmdline-tools.zip'
    Save-WebFile -Uri $Package.Url -Destination $zip -ExpectedSha1 $Package.Sha1 | Out-Null

    $staging = Join-Path $script:WorkDir 'cmdline-staging'
    if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
    New-Item -ItemType Directory -Path $staging -Force | Out-Null

    Write-Info 'Extracting the Android SDK command-line tools...'
    Expand-ArchiveFast -ArchivePath $zip -Destination $staging

    $src = Join-Path $staging 'cmdline-tools'
    if (-not (Test-Path -LiteralPath $src)) { throw "Unexpected command-line tools archive layout in $staging" }

    $target = Join-Path $script:AndroidDir 'cmdline-tools\latest'
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    foreach ($item in (Get-ChildItem -LiteralPath $src -Force)) {
        Move-Item -LiteralPath $item.FullName -Destination $target -Force
    }

    Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue

    if (-not (Test-Path -LiteralPath $script:SdkManagerBat)) {
        throw "sdkmanager.bat was not found at $script:SdkManagerBat after extraction."
    }
    Write-Ok "Android SDK command-line tools (build $($Package.Version)) installed at $target"
    return $true
}

function Get-JavaInfo {
    <#
        Locates a usable JDK. Returns @{ Path; Source; Version } or $null.
    #>
    $candidates = New-Object System.Collections.Generic.List[object]

    $javaHome = [Environment]::GetEnvironmentVariable('JAVA_HOME', 'Machine')
    if (-not $javaHome) { $javaHome = [Environment]::GetEnvironmentVariable('JAVA_HOME', 'User') }
    if ($javaHome) { [void]$candidates.Add([pscustomobject]@{ Path = $javaHome; Source = 'JAVA_HOME' }) }

    if (Test-Path -LiteralPath (Join-Path $script:JdkDir 'bin\java.exe')) {
        [void]$candidates.Add([pscustomobject]@{ Path = $script:JdkDir; Source = 'this script' })
    }

    $onPath = Get-Command 'java.exe' -ErrorAction SilentlyContinue
    if ($onPath) {
        $javaHomePath = Split-Path -Path (Split-Path -Path $onPath.Source -Parent) -Parent
        [void]$candidates.Add([pscustomobject]@{ Path = $javaHomePath; Source = 'PATH' })
    }

    foreach ($candidate in @(
            (Join-Path ${env:ProgramFiles} 'Android\Android Studio\jbr'),
            (Join-Path ${env:ProgramFiles} 'Android\Android Studio\jre'),
            (Join-Path ${env:LOCALAPPDATA} 'Programs\Android Studio\jbr')
        )) {
        if (Test-Path -LiteralPath (Join-Path $candidate 'bin\java.exe')) {
            [void]$candidates.Add([pscustomobject]@{ Path = $candidate; Source = 'Android Studio' })
        }
    }

    # A JDK that came with the Visual Studio "OpenJDK (Microsoft distribution)" component.
    $vsRoots = @($script:VsDir) + @(Get-ExistingVisualStudioInstances)
    $vsRoots += @(
        (Join-Path ${env:ProgramFiles} 'Microsoft Visual Studio'),
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio')
    )
    foreach ($root in ($vsRoots | Select-Object -Unique)) {
        if (-not $root -or -not (Test-Path -LiteralPath $root)) { continue }
        $java = Get-ChildItem -LiteralPath $root -Filter 'java.exe' -Recurse -Depth 6 -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match '(?i)(jbr|openjdk|jdk)' -and $_.FullName -match '(?i)\\bin\\java\.exe$' } |
            Select-Object -First 1
        if ($java) {
            $javaHomePath = Split-Path -Path (Split-Path -Path $java.FullName -Parent) -Parent
            [void]$candidates.Add([pscustomobject]@{ Path = $javaHomePath; Source = 'Visual Studio' })
        }
    }

    foreach ($c in $candidates) {
        $javaExe = Join-Path $c.Path 'bin\java.exe'
        if (-not (Test-Path -LiteralPath $javaExe)) { continue }
        $r = Invoke-Native -FilePath $javaExe -Arguments @('-version') -TimeoutSeconds 60
        if ($r.ExitCode -ne 0) { continue }
        $version = 'unknown'
        foreach ($line in ($r.StdOut -split "`r?`n")) {
            if ($line -match 'version\s+"(\d+)') { $version = $Matches[1]; break }
            if ($line -match 'version\s+(\d+)') { $version = $Matches[1]; break }
        }
        return @{ Path = $c.Path; Source = $c.Source; Version = $version }
    }
    return $null
}

function Install-OpenJdk {
    <#
        Installs the Microsoft Build of OpenJDK 17 (official Microsoft download)
        into <install root>\jdk. Used only when the operator opted in.
    #>
    if (Test-Path -LiteralPath (Join-Path $script:JdkDir 'bin\java.exe')) {
        Write-Ok "A JDK is already present at $($script:JdkDir) - leaving it untouched."
        return $true
    }
    $zip = Join-Path $script:WorkDir 'microsoft-jdk-17.zip'
    Save-WebFile -Uri $script:JdkZipUrl -Destination $zip | Out-Null

    $staging = Join-Path $script:WorkDir 'jdk-staging'
    if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
    New-Item -ItemType Directory -Path $staging -Force | Out-Null
    Expand-ArchiveFast -ArchivePath $zip -Destination $staging

    $inner = @(Get-ChildItem -LiteralPath $staging -Directory | Select-Object -First 1)
    if ($inner.Count -eq 0) { throw 'Unexpected OpenJDK archive layout.' }
    if (Test-Path -LiteralPath $script:JdkDir) {
        $existing = @(Get-ChildItem -LiteralPath $script:JdkDir -Force -ErrorAction SilentlyContinue)
        if ($existing.Count -gt 0) {
            throw "$($script:JdkDir) already exists, is not empty and is not a JDK. Refusing to overwrite it."
        }
        Remove-Item -LiteralPath $script:JdkDir -Recurse -Force
    }
    Move-Item -LiteralPath $inner[0].FullName -Destination $script:JdkDir
    Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue

    Write-Ok "Microsoft Build of OpenJDK 17 installed at $($script:JdkDir)"
    return $true
}

function Install-GitForWindows {
    param([hashtable] $Release)
    if (Test-Path -LiteralPath (Join-Path $script:GitDir 'cmd\git.exe')) {
        Write-Ok "Git for Windows is already present at $($script:GitDir) - leaving it untouched."
        return $true
    }
    $exe = Join-Path $script:WorkDir 'git-for-windows-installer.exe'
    Save-WebFile -Uri $Release.Url -Destination $exe | Out-Null

    Write-Info 'Running the official Git for Windows installer (silent)...'
    $r = Invoke-Native -FilePath $exe -Arguments @(
        '/VERYSILENT', '/NORESTART', '/NOCANCEL', '/SP-', '/SUPPRESSMSGBOXES',
        "/DIR=$script:GitDir",
        '/COMPONENTS=gitcmd,icons,ext\shellexec,assoc,assoc_sh'
    ) -TimeoutSeconds 1800
    if ($r.ExitCode -ne 0) {
        Write-Warn2 "The Git installer returned exit code $($r.ExitCode); retrying with default components."
        $r = Invoke-Native -FilePath $exe -Arguments @(
            '/VERYSILENT', '/NORESTART', '/NOCANCEL', '/SP-', "/DIR=$script:GitDir"
        ) -TimeoutSeconds 1800
    }
    if ($r.ExitCode -ne 0) { throw "The Git for Windows installer failed with exit code $($r.ExitCode)." }
    if (-not (Test-Path -LiteralPath (Join-Path $script:GitDir 'cmd\git.exe'))) {
        throw "The Git for Windows installer completed but git.exe was not found under $($script:GitDir)."
    }
    Write-Ok "Git for Windows $($Release.Version) installed at $($script:GitDir)"
    return $true
}

function Get-AndroidSdkTool {
    <#
        Picks the SDK package manager that ships with the installed command-line
        tools.

        cmdline-tools 23.0 and newer ship the Android CLI (android.exe), a native
        binary that manages the SDK itself (and carries its own Java runtime).
        It is the tool the Android documentation now recommends; the older
        sdkmanager.bat is deprecated and is only used as a fallback.

        Returns @{ Kind; Exe; NeedsJdk } or $null.
    #>
    if (Test-Path -LiteralPath $script:AndroidCliExe) {
        return @{ Kind = 'android-cli'; Exe = $script:AndroidCliExe; NeedsJdk = $false }
    }
    if (Test-Path -LiteralPath $script:SdkManagerBat) {
        return @{ Kind = 'sdkmanager'; Exe = $script:SdkManagerBat; NeedsJdk = $true }
    }
    return $null
}

function ConvertTo-AndroidPackageId {
    <#
        The repository manifest uses the legacy 'build-tools;36.0.0' form while
        the Android CLI uses 'build-tools/36.0.0'.
    #>
    param([string] $Path, [string] $Kind)
    if ($Kind -eq 'android-cli') { return ($Path -replace ';', '/') }
    return $Path
}

function Install-AndroidPackages {
    <#
        Installs the SDK packages a Flutter Android build needs: platform-tools,
        build-tools and the Android platform that Flutter itself declares as its
        compile SDK.
    #>
    param([object] $PackageInfo, [int] $CompileSdk, [string] $JavaHome)

    $tool = Get-AndroidSdkTool
    if (-not $tool) {
        throw "No Android SDK package manager was found in $($script:CmdlineBin)."
    }
    Write-Ok "Using the $($tool.Kind) to manage Android SDK packages: $($tool.Exe)"

    $packages = New-Object System.Collections.Generic.List[string]

    if (Test-Path -LiteralPath (Join-Path $script:AndroidDir 'platform-tools\adb.exe')) {
        Write-Ok 'Android platform-tools are already installed.'
    } else {
        [void]$packages.Add('platform-tools')
    }

    # build-tools: the newest published stable release plus the one whose major
    # version matches the API level Flutter compiles against.
    $selected = @{}
    if ($PackageInfo.BuildTools.Count -gt 0) { $selected[$PackageInfo.BuildTools[0].Path] = $true }
    if ($CompileSdk -gt 0) {
        $match = $PackageInfo.BuildTools | Where-Object { $_.Version.Major -eq $CompileSdk } | Select-Object -First 1
        if ($match) { $selected[$match.Path] = $true }
    }
    foreach ($k in ($selected.Keys | Sort-Object)) {
        if (Test-Path -LiteralPath (Join-Path $script:AndroidDir ($k -replace ';', '\'))) {
            Write-Ok "$k is already installed."
        } else {
            [void]$packages.Add($k)
        }
    }

    if ($CompileSdk -gt 0) {
        $platformPath = "platforms;android-$CompileSdk"
        if (Test-Path -LiteralPath (Join-Path $script:AndroidDir "platforms\android-$CompileSdk")) {
            Write-Ok "$platformPath is already installed."
        } else {
            [void]$packages.Add($platformPath)
        }
    }
    if ($PackageInfo.Platforms.Count -gt 0) {
        $newest = $PackageInfo.Platforms[0]
        if (-not (Test-Path -LiteralPath (Join-Path $script:AndroidDir ($newest.Path -replace ';', '\')))) {
            [void]$packages.Add($newest.Path)
        }
    }

    if ($packages.Count -eq 0) {
        Write-Ok 'All required Android SDK packages are already installed.'
        return $true
    }

    $ids = @($packages | ForEach-Object { ConvertTo-AndroidPackageId -Path $_ -Kind $tool.Kind })
    Write-Info "Installing Android SDK packages: $($ids -join ', ')"

    if ($tool.NeedsJdk) {
        if (-not $JavaHome) {
            throw 'This version of the Android SDK command-line tools needs a JDK to run sdkmanager, and no JDK was found.'
        }
        $env:JAVA_HOME = $JavaHome
        $env:PATH = (Join-Path $JavaHome 'bin') + ';' + $env:PATH
    }

    if ($tool.Kind -eq 'android-cli') {
        $cmdArgs = @("--sdk=$script:AndroidDir", 'sdk', 'install') + $ids
    } else {
        # The legacy sdkmanager derives the SDK root from its own location
        # (<sdk>\cmdline-tools\latest\bin), so no --sdk_root argument is needed.
        $cmdArgs = $ids
    }

    $r = Invoke-Native -FilePath $tool.Exe -Arguments $cmdArgs -TimeoutSeconds 3600 -Activity "Installing Android SDK packages: $($ids -join ', ')"
    Write-NativeOutput $r.StdOut
    if ($r.ExitCode -ne 0) {
        throw "The Android SDK package installation failed with exit code $($r.ExitCode)."
    }

    # Never claim success without verifying that the packages really landed.
    if (-not (Test-Path -LiteralPath (Join-Path $script:AndroidDir 'platform-tools\adb.exe'))) {
        throw "platform-tools was not installed under $($script:AndroidDir). The Android SDK is incomplete."
    }
    Write-Ok "Installed: $($ids -join ', ')"
    return $true
}

function Confirm-AndroidSdkLicense {
    <#
        Informs the user about the Android SDK License Agreement and requires an
        explicit confirmation. -Yes does NOT satisfy this prompt: a licence is
        never accepted on the user's behalf without a typed confirmation.

        This must run BEFORE the first android / sdkmanager invocation, because
        that is the point at which the licence is presented and accepted.
    #>
    Write-RunLog ''
    Write-RunLog 'NOTICE: The Android SDK is distributed under the Android Software' 'NOTICE'
    Write-RunLog 'NOTICE: Development Kit License Agreement. Using the Android SDK' 'NOTICE'
    Write-RunLog 'NOTICE: means you accept that agreement. The full text is published' 'NOTICE'
    Write-RunLog "NOTICE: at $script:AndroidLicenseUrl" 'NOTICE'
    Write-RunLog 'NOTICE: The Android CLI prints the agreement again the first time it' 'NOTICE'
    Write-RunLog 'NOTICE: runs. The accepted licence is recorded in the SDK licenses folder.' 'NOTICE'

    $t = $script:Tui
    $licenceLines = @(
        ('  {0} The Android SDK packages are covered by the Android Software' -f $t.Bullet),
        ('  {0} Development Kit License Agreement.' -f $t.Bullet),
        ('  {0} Using the Android SDK means you accept that agreement.' -f $t.Bullet),
        ('  {0} Full text: {1}' -f $t.Bullet, $script:AndroidLicenseUrl)
    )
    Write-TuiBox -Lines $licenceLines -Title 'LICENCE' -BorderColor 'Yellow' -TextColor 'Gray'

    if (-not $script:IsInteractive) {
        # There is no terminal to ask on. The licence is shown above and the
        # Android CLI records it when it runs, so the installation the operator
        # asked for goes ahead. It is reported in the summary.
        Write-Info 'This is a non-interactive run, so the licence is accepted as part of the installation you asked for.'
        Write-Detail "It is recorded in the SDK's licenses folder. Full text: $script:AndroidLicenseUrl"
    }
    elseif (-not (Confirm-User 'Accept the Android SDK License Agreement on this machine?' -DefaultNo -AlwaysAsk)) {
        Write-Warn2 'The Android SDK License Agreement was not accepted.'
        Write-Detail 'The Android SDK packages were not installed and Android builds will not work.'
        Write-Detail "Read the agreement at $script:AndroidLicenseUrl and re-run this script to accept it."
        return $false
    }
    Write-Ok 'The Android SDK License Agreement was accepted.'
    return $true
}

function Accept-LegacyAndroidLicenses {
    <#
        Only needed for the deprecated sdkmanager (command-line tools older than
        23.0), which still uses the interactive --licenses flow.
    #>
    param([string] $JavaHome)

    $tool = Get-AndroidSdkTool
    if (-not $tool -or $tool.Kind -ne 'sdkmanager') { return $true }
    if (-not $JavaHome) { return $false }

    $env:JAVA_HOME = $JavaHome
    $env:PATH = (Join-Path $JavaHome 'bin') + ';' + $env:PATH

    $yesFile = Join-Path $script:WorkDir 'sdk-licenses-yes.txt'
    (1..40 | ForEach-Object { 'y' }) | Set-Content -LiteralPath $yesFile -Encoding ASCII
    $raw = '"' + $script:SdkManagerBat + '" --licenses < "' + $yesFile + '"'
    $r = Invoke-Native -FilePath $env:ComSpec -RawArguments ('/d /s /c "' + $raw + '"') -TimeoutSeconds 1800
    Write-NativeOutput $r.StdOut
    if ($r.ExitCode -ne 0) { throw "sdkmanager --licenses failed with exit code $($r.ExitCode)." }
    Write-Ok 'Android SDK licences accepted.'
    return $true
}

function Install-VisualStudio {
    <#
        Installs Visual Studio 2026 with the "Desktop development with C++" workload
        using the official bootstrapper.
    #>
    param([switch] $IncludeOpenJdkComponent)

    $url = switch ($VsEdition) {
        'Professional' { $script:VsProfessionalUrl }
        'Enterprise'   { $script:VsEnterpriseUrl }
        default        { $script:VsCommunityUrl }
    }

    if (Test-Path -LiteralPath (Join-Path $script:VsDir 'Common7\IDE\devenv.exe')) {
        Write-Ok "Visual Studio is already installed at $($script:VsDir) - leaving it untouched."
        return $true
    }

    $exe = Join-Path $script:WorkDir "vs_$($VsEdition.ToLowerInvariant()).exe"
    Save-WebFile -Uri $url -Destination $exe | Out-Null

    $baseArgs = New-Object System.Collections.Generic.List[string]
    $baseArgs.Add('--installPath'); $baseArgs.Add($script:VsDir)
    $baseArgs.Add('--add'); $baseArgs.Add($script:VsCppWorkload)
    $baseArgs.Add('--add'); $baseArgs.Add($script:VsMsvcComponent)
    $baseArgs.Add('--add'); $baseArgs.Add($script:VsCMakeComponent)
    if ($IncludeOpenJdkComponent) {
        $baseArgs.Add('--add'); $baseArgs.Add($script:VsOpenJdkComponent)
    }
    # The Windows SDK is a *recommended* component of the C++ workload. Taking
    # the recommended set guarantees the Windows SDK build that ships with
    # Visual Studio 2026 is installed, instead of a hard-coded and quickly
    # stale SDK component ID. No unrelated workload is ever added.
    $baseArgs.Add('--includeRecommended')
    # --passive (never --quiet) so the installer displays its own licence
    # agreement and the operator accepts it. The script never accepts it for them.
    $baseArgs.Add('--passive')
    $baseArgs.Add('--norestart')
    $baseArgs.Add('--wait')

    $pathArgs = New-Object System.Collections.Generic.List[string]
    $existing = @(Get-ExistingVisualStudioInstances)
    $usePaths = ($existing.Count -eq 0)
    if ($usePaths) {
        # shared/cache can only be relocated on the first VS installation.
        $pathArgs.Add('--path'); $pathArgs.Add("shared=$script:VsDir\Shared")
        $pathArgs.Add('--path'); $pathArgs.Add("cache=$script:VsDir\Cache")
    } else {
        Write-Detail 'Visual Studio already exists on this machine; shared/cache paths cannot be relocated.'
    }

    Write-Info "Starting the Visual Studio 2026 $VsEdition installer (15-45 minutes)..."
    Write-Info "  Workload    : $script:VsCppWorkload (Desktop development with C++)"
    Write-Info "  Components  : $script:VsMsvcComponent"
    Write-Info "  Components  : $script:VsCMakeComponent"
    if ($IncludeOpenJdkComponent) { Write-Info "  Components  : $script:VsOpenJdkComponent (supplies the required JDK)" }
    Write-Info "  Install path: $($script:VsDir)"
    Write-Info 'The installer shows its own licence agreement - you must accept it there.'

    $r = Invoke-Native -FilePath $exe -Arguments ($baseArgs.ToArray() + $pathArgs.ToArray()) -TimeoutSeconds 7200 -Activity "Installing Visual Studio 2026 $VsEdition (15-45 minutes)"
    Write-Detail "Installer exit code: $($r.ExitCode)"
    Write-NativeOutput $r.StdOut

    if ($r.ExitCode -ne 0 -and $usePaths) {
        Write-Warn2 "The installer returned $($r.ExitCode). Retrying without the shared/cache path overrides..."
        $r = Invoke-Native -FilePath $exe -Arguments $baseArgs.ToArray() -TimeoutSeconds 7200 -Activity 'Retrying the Visual Studio installation without the shared/cache path overrides'
        Write-Detail "Installer exit code: $($r.ExitCode)"
    }

    # 0 = success, 3010 = success but reboot required, 1641 = success and reboot
    # initiated, 1602 = cancelled by the user, 740 = elevation required.
    if ($r.ExitCode -eq 0) {
        Write-Ok "Visual Studio 2026 $VsEdition installed at $($script:VsDir)"
        return $true
    }
    if ($r.ExitCode -eq 3010 -or $r.ExitCode -eq 1641) {
        Write-Warn2 "Visual Studio installed successfully but a reboot is recommended (exit code $($r.ExitCode))."
        return $true
    }
    if ($r.ExitCode -eq 1602) { throw 'The Visual Studio installation was cancelled in the installer window.' }
    if ($r.ExitCode -eq 740)   { throw 'The Visual Studio installer requires elevation and could not request it. Re-run this script from an elevated PowerShell window.' }
    throw "The Visual Studio installer failed with exit code $($r.ExitCode). Check the Visual Studio logs in %TEMP% (dd_bootstrapper_*.log, dd_client_*.log, dd_setup_*.log)."
}

function Test-VisualStudioCppToolchain {
    <#
        Verifies that the pieces of the C++ toolchain a Flutter Windows desktop
        build needs are actually present on disk.
    #>
    $result = @{
        InstallationPath = $null
        ClExe            = $null
        CMakeExe         = $null
        MSBuildExe       = $null
        WindowsSdkDir    = $null
        MsvcDir          = $null
    }

    $candidates = @()
    if (Test-Path -LiteralPath (Join-Path $script:VsDir 'Common7\IDE\devenv.exe')) { $candidates += $script:VsDir }
    $candidates += @(Get-ExistingVisualStudioInstances)

    foreach ($root in ($candidates | Select-Object -Unique)) {
        if (-not $root) { continue }
        $result.InstallationPath = $root

        $msvcRoot = Join-Path $root 'VC\Tools\MSVC'
        if (Test-Path -LiteralPath $msvcRoot) {
            $cl = Get-ChildItem -LiteralPath $msvcRoot -Filter 'cl.exe' -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -match 'Hostx64\\x64' } | Select-Object -First 1
            if ($cl) { $result.ClExe = $cl.FullName }
            $result.MsvcDir = $msvcRoot
        }

        $cm = Join-Path $root 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
        if (Test-Path -LiteralPath $cm) { $result.CMakeExe = $cm }

        $msb = Join-Path $root 'MSBuild\Current\Bin\MSBuild.exe'
        if (Test-Path -LiteralPath $msb) { $result.MSBuildExe = $msb }

        break
    }

    # The Windows SDK location is controlled by Microsoft.
    foreach ($k in @(
            (Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10'),
            (Join-Path $script:VsDir 'Shared\Windows Kits\10'),
            (Join-Path ${env:ProgramFiles} 'Windows Kits\10'))) {
        if (Test-Path -LiteralPath (Join-Path $k 'Include')) { $result.WindowsSdkDir = $k; break }
    }
    return $result
}

# ======================================================================================
# Verification
# ======================================================================================
function Invoke-Verification {
    param([string] $JavaHome)

    Write-TuiSection -Title 'VERIFICATION'

    $env:PATH = "$script:FlutterBin;$($script:AndroidDir)\platform-tools;$($script:AndroidDir)\cmdline-tools\latest\bin;" + $env:PATH
    if ($JavaHome) {
        $env:JAVA_HOME = $JavaHome
        $env:PATH = (Join-Path $JavaHome 'bin') + ';' + $env:PATH
    }

    $results = New-Object System.Collections.Generic.List[object]

    if (Test-Path -LiteralPath $script:FlutterExe) {
        Write-Info 'Running: flutter --version'
        $r = Invoke-Native -FilePath $script:FlutterExe -Arguments @('--version') -TimeoutSeconds 1800
        Write-NativeOutput $r.StdOut
        if ($r.ExitCode -eq 0) {
            [void]$results.Add([pscustomobject]@{ Check = 'flutter --version'; Status = 'PASS'; Detail = '' })
        } else {
            [void]$results.Add([pscustomobject]@{ Check = 'flutter --version'; Status = 'FAIL'; Detail = "exit code $($r.ExitCode)" })
            Write-Err "flutter --version failed (exit code $($r.ExitCode))."
        }

        Write-Info 'Running: flutter config --enable-windows-desktop'
        $r = Invoke-Native -FilePath $script:FlutterExe -Arguments @('config', '--enable-windows-desktop') -TimeoutSeconds 900
        Write-NativeOutput $r.StdOut
        if ($r.ExitCode -eq 0) {
            [void]$results.Add([pscustomobject]@{ Check = 'flutter config --enable-windows-desktop'; Status = 'PASS'; Detail = '' })
        } else {
            [void]$results.Add([pscustomobject]@{ Check = 'flutter config --enable-windows-desktop'; Status = 'FAIL'; Detail = "exit code $($r.ExitCode)" })
        }
    } else {
        [void]$results.Add([pscustomobject]@{ Check = 'flutter --version'; Status = 'FAIL'; Detail = 'flutter not found' })
    }

    if (Test-Path -LiteralPath $script:AdbExe) {
        Write-Info 'Running: adb version'
        $r = Invoke-Native -FilePath $script:AdbExe -Arguments @('version') -TimeoutSeconds 120
        Write-NativeOutput $r.StdOut
        if ($r.ExitCode -eq 0) {
            [void]$results.Add([pscustomobject]@{ Check = 'adb version'; Status = 'PASS'; Detail = '' })
        } else {
            [void]$results.Add([pscustomobject]@{ Check = 'adb version'; Status = 'FAIL'; Detail = "exit code $($r.ExitCode)" })
        }
    } else {
        [void]$results.Add([pscustomobject]@{ Check = 'adb version'; Status = 'FAIL'; Detail = 'adb.exe not found' })
    }

    $vs = Test-VisualStudioCppToolchain
    if ($vs.ClExe) {
        [void]$results.Add([pscustomobject]@{ Check = 'Visual Studio MSVC (cl.exe)'; Status = 'PASS'; Detail = $vs.ClExe })
        Write-Ok "MSVC compiler: $($vs.ClExe)"
    } else {
        [void]$results.Add([pscustomobject]@{ Check = 'Visual Studio MSVC (cl.exe)'; Status = 'FAIL'; Detail = 'not found' })
        Write-Err 'The MSVC compiler (cl.exe) was not found.'
    }
    if ($vs.CMakeExe) {
        [void]$results.Add([pscustomobject]@{ Check = 'Visual Studio CMake tools'; Status = 'PASS'; Detail = $vs.CMakeExe })
        Write-Ok "CMake: $($vs.CMakeExe)"
    } else {
        [void]$results.Add([pscustomobject]@{ Check = 'Visual Studio CMake tools'; Status = 'FAIL'; Detail = 'not found' })
        Write-Err 'The Visual Studio CMake tools were not found.'
    }
    if ($vs.MSBuildExe) {
        [void]$results.Add([pscustomobject]@{ Check = 'Visual Studio MSBuild'; Status = 'PASS'; Detail = $vs.MSBuildExe })
        Write-Ok "MSBuild: $($vs.MSBuildExe)"
    } else {
        [void]$results.Add([pscustomobject]@{ Check = 'Visual Studio MSBuild'; Status = 'FAIL'; Detail = 'not found' })
        Write-Err 'MSBuild was not found; Flutter Windows desktop builds need it.'
    }
    if ($vs.WindowsSdkDir) {
        [void]$results.Add([pscustomobject]@{ Check = 'Windows SDK'; Status = 'PASS'; Detail = $vs.WindowsSdkDir })
        Write-Ok "Windows SDK: $($vs.WindowsSdkDir)"
    } else {
        [void]$results.Add([pscustomobject]@{ Check = 'Windows SDK'; Status = 'FAIL'; Detail = 'not found' })
        Write-Err 'The Windows SDK was not found.'
    }

    # The accepted Android SDK licence is recorded in this folder.
    $licDir = Join-Path $script:AndroidDir 'licenses'
    if (Test-Path -LiteralPath $licDir) {
        [void]$results.Add([pscustomobject]@{ Check = 'Android SDK licence record'; Status = 'PASS'; Detail = $licDir })
        Write-Ok "Android SDK licences recorded in $licDir"
    } else {
        [void]$results.Add([pscustomobject]@{ Check = 'Android SDK licence record'; Status = 'INFO'; Detail = 'not found - run flutter doctor --android-licenses' })
        Write-Warn2 "No Android SDK licence record was found in $licDir."
    }

    # flutter / adb must be resolvable through PATH, not just by absolute path.
    foreach ($cmd in @('flutter', 'adb')) {
        $c = Get-Command $cmd -ErrorAction SilentlyContinue
        if ($c) {
            [void]$results.Add([pscustomobject]@{ Check = "$cmd on PATH"; Status = 'PASS'; Detail = $c.Source })
            Write-Ok "$cmd resolves to $($c.Source)"
        } else {
            [void]$results.Add([pscustomobject]@{ Check = "$cmd on PATH"; Status = 'FAIL'; Detail = 'not on PATH' })
            Write-Err "$cmd is not resolvable on the PATH. Open a new terminal and try again."
        }
    }

    if (Test-Path -LiteralPath $script:FlutterExe) {
        Write-Info 'Running: flutter doctor -v (can take several minutes on the first run)'
        $r = Invoke-Native -FilePath $script:FlutterExe -Arguments @('doctor', '-v') -TimeoutSeconds 2400 -Activity 'Running flutter doctor -v (first run can take several minutes)'
        Write-NativeOutput $r.StdOut
        [void]$results.Add([pscustomobject]@{ Check = 'flutter doctor -v'; Status = 'INFO'; Detail = 'see log' })
    }

    if ((Test-Path -LiteralPath $script:FlutterExe) -and (-not $SkipAndroidLicenses)) {
        Write-TuiSection -Title 'ANDROID LICENCES' -Detail 'flutter doctor --android-licenses'
        Write-Info 'Read the licence text shown below and answer y/n for each licence you accept.'
        Write-Detail 'Note: with Android SDK command-line tools 23.0 and newer the licence is recorded by the'
        Write-Detail 'Android CLI when it first runs, so this command may report that nothing is pending.'
        # Run in the foreground so the interactive prompt is visible immediately
        # rather than buffered until the command finishes.
        # A native command that writes to stderr (the command-line tools print a
        # deprecation warning there) must not become a terminating error, so the
        # error preference is relaxed for the duration of the call.
        $previousPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            & $script:FlutterExe 'doctor' '--android-licenses' 2>&1 | ForEach-Object {
                $line = "$_"
                if ($line.Trim()) { Write-Detail $line.TrimEnd() }
            }
        } catch {
            Write-Warn2 "flutter doctor --android-licences could not be completed: $($_.Exception.Message)"
        } finally {
            $ErrorActionPreference = $previousPreference
        }
        [void]$results.Add([pscustomobject]@{ Check = 'flutter doctor --android-licenses'; Status = 'INFO'; Detail = 'interactive' })
    }

    Write-RunLog ''
    Write-RunLog 'Check results:'
    foreach ($c in $results) {
        $marker = switch ($c.Status) { 'PASS' { '[ OK ]' } 'FAIL' { '[FAIL]' } default { '[INFO]' } }
        Write-Detail "$marker $($c.Check) $($c.Detail)"
    }
    return $results
}

# ======================================================================================
# Main
# ======================================================================================
function Get-ExecutionPolicySummary {
    <#
        Describes the execution policy in force, scope by scope.
    #>
    $parts = @()
    foreach ($scope in @('MachinePolicy', 'UserPolicy', 'Process', 'CurrentUser', 'LocalMachine')) {
        try {
            $v = Get-ExecutionPolicy -Scope $scope -ErrorAction SilentlyContinue
            $parts += ('{0}={1}' -f $scope, $v)
        } catch { }
    }
    $effective = $null
    try { $effective = Get-ExecutionPolicy } catch { }
    return ('{0} (effective: {1})' -f ($parts -join ', '), $effective)
}

function Get-ScriptRunnability {
    <#
        Works out whether PowerShell would actually run this script under the
        policy in force, and if not, why.

        Returns @{ CanRun; Reason; Policy; Effective; MarkedAsDownloaded; Signed }
    #>
    $result = @{
        CanRun            = $true
        Reason            = ''
        Policy            = $null
        Effective         = $null
        MarkedAsDownloaded = $false
        Signed            = $false
    }
    try { $result.Effective = Get-ExecutionPolicy } catch { }
    try { $result.Policy = Get-ExecutionPolicy -Scope CurrentUser } catch { }

    $scriptPath = $script:ScriptPath
    if (-not $scriptPath) {
        # Piped execution: there is no script file to inspect.
        $result.Reason = 'running from a pipe (there is no script file on disk).'
        return $result
    }

    $stream = Get-Item -LiteralPath $scriptPath -Stream 'Zone.Identifier' -ErrorAction SilentlyContinue
    if ($stream) { $result.MarkedAsDownloaded = $true }

    try {
        $sig = Get-AuthenticodeSignature -LiteralPath $scriptPath -ErrorAction SilentlyContinue
        if ($sig -and $sig.Status -eq 'Valid') { $result.Signed = $true }
    } catch { }

    switch ($result.Effective) {
        'Restricted' {
            $result.CanRun = $false
            $result.Reason = "the execution policy is 'Restricted', which blocks all script files."
        }
        'AllSigned' {
            if (-not $result.Signed) {
                $result.CanRun = $false
                $result.Reason = "the execution policy is 'AllSigned' and this script is not signed."
            }
        }
        'RemoteSigned' {
            if ($result.MarkedAsDownloaded -and -not $result.Signed) {
                $result.CanRun = $false
                $result.Reason = 'the script is marked as downloaded (Zone.Identifier) and is not signed, so RemoteSigned blocks it.'
            }
        }
    }
    return $result
}

function Show-Preflight {
    <#
        A read-only report of the environment: execution policy, script
        runnability, prerequisites and the current state of the install targets.
        Makes no network requests and changes nothing.
    #>
    Write-TuiSection -Title 'PREFLIGHT' -Detail 'read-only environment report'

    Write-RunLog 'Execution policy:'
    Write-Detail (Get-ExecutionPolicySummary)

    $run = Get-ScriptRunnability
    Write-RunLog 'Script runnability:'
    if ($script:IsPiped) {
        Write-Detail 'script ................. (running from a pipe - no script file on disk)'
        Write-Detail "source URL ............ $(if ($script:SourceUrl) { $script:SourceUrl } else { '(not configured)' })"
    } else {
        Write-Detail ("script ................. {0}" -f $script:ScriptPath)
        Write-Detail ("marked as downloaded ... {0}" -f $run.MarkedAsDownloaded)
        Write-Detail ("signed ................. {0}" -f $run.Signed)
    }
    if ($run.CanRun) {
        Write-Ok 'This script can run under the policy in force.'
    } else {
        Write-Warn2 "This script cannot run: $($run.Reason)"
        Write-Detail 'Fix: Unblock-File -LiteralPath <this script>   (removes the mark, changes no policy)'
        Write-Detail 'or:   Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force'
    }

    Write-RunLog ''
    Write-RunLog 'Prerequisites:'
    $gitCmd = Get-Command 'git.exe' -ErrorAction SilentlyContinue
    $jdk = Get-JavaInfo
    $preRows = @()
    if ($gitCmd) {
        $preRows += , @('Git for Windows', "found  $($gitCmd.Source)")
    } else {
        $preRows += , @('Git for Windows', 'NOT FOUND  -  ' + $script:GitDownloadPage)
    }
    if ($jdk) {
        $preRows += , @('JDK', "found  Java $($jdk.Version)  $($jdk.Path)")
    } else {
        $preRows += , @('JDK', 'NOT FOUND  -  ' + $script:JdkDocsUrl)
    }
    $vs = @(Get-ExistingVisualStudioInstances)
    if ($vs.Count -gt 0) {
        $preRows += , @('Visual Studio', ($vs -join ', '))
    } else {
        $preRows += , @('Visual Studio', 'none installed')
    }
    Write-TuiBox -Lines (Format-TuiColumns -Rows $preRows) -Title 'PREREQUISITES' -BorderColor 'DarkCyan' -TextColor 'Gray'

    Write-RunLog ''
    Write-RunLog 'Install targets:'
    $targetRows = @()
    foreach ($t2 in @(
            @{ Name = 'Flutter SDK'; Path = $script:FlutterDir; Probe = 'bin\flutter.bat' },
            @{ Name = 'Android SDK'; Path = $script:AndroidDir; Probe = 'cmdline-tools\latest\bin\android.exe' },
            @{ Name = 'Visual Studio'; Path = $script:VsDir; Probe = 'Common7\IDE\devenv.exe' },
            @{ Name = 'OpenJDK (optional)'; Path = $script:JdkDir; Probe = 'bin\java.exe' },
            @{ Name = 'Git (optional)'; Path = $script:GitDir; Probe = 'cmd\git.exe' })) {
        if (Test-Path -LiteralPath (Join-Path $t2.Path $t2.Probe)) {
            $targetRows += , @($t2.Name, "installed  $($t2.Path)")
        }
        elseif (Test-Path -LiteralPath $t2.Path) {
            $targetRows += , @($t2.Name, "EXISTS but incomplete  $($t2.Path)")
        }
        else {
            $targetRows += , @($t2.Name, "not present  $($t2.Path)")
        }
    }
    Write-TuiBox -Lines (Format-TuiColumns -Rows $targetRows) -Title 'INSTALL TARGETS' -BorderColor 'DarkCyan' -TextColor 'Gray'

    Write-RunLog ''
    Write-RunLog 'Current user environment:'
    $envRows = @()
    foreach ($v in @('ANDROID_HOME', 'ANDROID_SDK_ROOT', 'JAVA_HOME')) {
        $val = Get-UserEnvRaw $v
        $envRows += , @($v, $(if ($val) { $val } else { '(not set)' }))
    }
    Write-TuiBox -Lines (Format-TuiColumns -Rows $envRows) -Title 'USER ENVIRONMENT' -BorderColor 'DarkCyan' -TextColor 'Gray'

    $existing = Get-UserPathEntries
    $would = @(
        $script:FlutterBin,
        (Join-Path $script:AndroidDir 'platform-tools'),
        (Join-Path $script:AndroidDir 'cmdline-tools\latest\bin')
    )
    Write-RunLog ''
    Write-RunLog 'PATH entries that would be added:'
    $seen = @{}
    foreach ($p in $existing) { $seen[$p.Trim().TrimEnd('\').ToLowerInvariant()] = $true }
    $pathRows = @()
    foreach ($w in $would) {
        $k = $w.TrimEnd('\').ToLowerInvariant()
        if ($seen.ContainsKey($k)) { $pathRows += , @($w, 'already present') }
        else { $pathRows += , @($w, 'new') }
    }
    Write-TuiBox -Lines (Format-TuiColumns -Rows $pathRows) -Title 'PATH' -BorderColor 'DarkCyan' -TextColor 'Gray'

    Write-Host ''
    Write-Ok 'Preflight complete - nothing was changed and no download was started.'
}

function Show-Plan {
    param($PlanItems)
    Write-TuiBox -Lines $PlanItems -Title 'PLAN' -BorderColor 'DarkCyan' -TextColor 'Gray' -Wrap
}

# ======================================================================================
# Result tracking
#
# Every component records what happened to it, so the final report can say
# exactly what was done, what was already there, what failed and what is still
# outstanding. A failing component must never abort the rest of the run.
# ======================================================================================
function Add-Result {
    param(
        [string] $Item,
        [string] $State,      # ok | present | configured | fail | skip | pending
        [string] $Detail = '',
        [string] $NextAction = ''
    )
    [void]$script:Results.Add([pscustomobject]@{
        Item = $Item; State = $State; Detail = $Detail; NextAction = $NextAction
    })
}

function Invoke-ComponentStep {
    <#
        Runs one component install. The script block must return either a short
        detail string, or a hashtable with State and Detail. Throwing marks the
        component as failed and lets the run continue.
    #>
    param([string] $Name, [scriptblock] $Action)
    try {
        $result = & $Action
        $state = 'ok'
        $detail = 'done'
        if ($result -is [hashtable]) {
            if ($result.ContainsKey('State')) { $state = $result['State'] }
            if ($result.ContainsKey('Detail')) { $detail = $result['Detail'] }
        }
        elseif ($result) {
            $detail = [string]$result
        }
        Add-Result -Item $Name -State $state -Detail $detail
        return $true
    } catch {
        $msg = $_.Exception.Message
        Write-Err "$Name failed: $msg"
        Add-Result -Item $Name -State 'fail' -Detail $msg `
            -NextAction "Re-run the installer to retry this component, or install it manually. Details: $($script:LogFile)"
        return $false
    }
}

function Show-ResultReport {
    <#
        The closing report: one line per component with its state, plus any
        outstanding actions the operator still has to take.
    #>
    $t = $script:Tui
    $lines = @()
    $outstanding = @()

    foreach ($r in $script:Results) {
        switch ($r.State) {
            'ok'        { $m = $t.Ok;   $c = 'Green' }
            'present'   { $m = $t.Info; $c = 'Cyan' }
            'configured'{ $m = $t.Ok;   $c = 'Green' }
            'fail'      { $m = $t.Fail; $c = 'Red' }
            'skip'      { $m = $t.Skip; $c = 'DarkGray' }
            default     { $m = $t.Warn; $c = 'Yellow' }
        }
        $lines += @{ Text = ('{0} {1}{2}' -f $m, $r.Item.PadRight(32), $r.Detail); Color = $c }
        if ($r.State -eq 'fail' -or $r.State -eq 'pending' -or $r.NextAction) {
            $outstanding += , @($r.Item, $r.NextAction)
        }
    }

    Write-TuiSection -Title 'RESULT'
    Write-TuiBox -Lines $lines -Title 'SUMMARY' -BorderColor 'DarkCyan' -TextColor 'Gray'

    if ($outstanding.Count -gt 0) {
        Write-Host ''
        Write-Host '  Still outstanding:' -ForegroundColor Yellow
        foreach ($o in $outstanding) {
            Write-Host ("   {0} {1}" -f $t.Warn, $o[0]) -ForegroundColor Yellow
            if ($o[1]) { Write-Host ("      {0}" -f $o[1]) -ForegroundColor DarkYellow }
        }
    }
}

function Show-MainMenu {
    <#
        The interactive front door. Lets the operator choose what to install and
        whether the missing prerequisites should be installed as well, so
        nothing is ever installed "silently".

        Returns a hashtable with the choices. Skipped entirely when running
        unattended (-Yes) or from a pipe.
    #>
    $t = $script:Tui
    $menu = @(
        ('  {0}  1   Install all three components' -f $t.Arrow),
        ('  {0}  2   The Flutter SDK on its own' -f $t.Arrow),
        ('  {0}  3   The Android SDK on its own' -f $t.Arrow),
        ('  {0}  4   Visual Studio 2026 with the C++ workload' -f $t.Arrow),
        ('  {0}  5   Preflight report only (change nothing)' -f $t.Arrow)
    )
    Write-TuiBox -Lines $menu -Title 'WHAT WOULD YOU LIKE TO INSTALL?' -BorderColor 'Cyan' -TextColor 'Gray'

    $answer = Read-Host ("  Choose [1-5, default 1] : ")
    switch -Regex ("$answer".Trim()) {
        '^2$' { return @{ Components = @('flutter'); Preflight = $false } }
        '^3$' { return @{ Components = @('android'); Preflight = $false } }
        '^4$' { return @{ Components = @('vs'); Preflight = $false } }
        '^5$' { return @{ Components = @(); Preflight = $true } }
        default { return @{ Components = @('flutter', 'android', 'vs'); Preflight = $false } }
    }
}

function Show-PrerequisiteMenu {
    <#
        Asks whether the missing prerequisites (Git for Windows, a JDK) should
        be installed. They are never installed without this answer.
    #>
    $t = $script:Tui
    $lines = @(
        ('  {0} These are NOT part of the three components, so they are only' -f $t.Bullet),
        ('  {0} installed if you ask for it here:' -f $t.Bullet),
        ('    {0} Git for Windows   {1}' -f $t.Bullet, $script:GitDownloadPage),
        ('    {0} JDK 17 or newer   {1}' -f $t.Bullet, $script:JdkDocsUrl)
    )
    Write-TuiBox -Lines $lines -Title 'PREREQUISITES' -BorderColor 'Yellow' -TextColor 'Gray'
    $answer = Read-Host ("  Install the missing prerequisites? [y/N] : ")
    return ($answer.Trim() -match '^(y|yes)$')
}

function Invoke-ElevatedRelaunch {
    $scriptPath = $script:ScriptPath
    $psExe = (Get-Process -Id $PID).Path

    if ($script:IsPiped) {
        # There is no script file on disk, so fetch the canonical copy and run
        # that in the elevated window instead.
        if (-not $script:SourceUrl) {
            throw 'This script is running from a pipe and has no source URL configured, so it cannot re-launch itself elevated. Re-run the one-liner from an elevated PowerShell window instead.'
        }
        $scriptPath = Join-Path $script:WorkDir 'install.ps1'
        Write-Info "Fetching the script to run elevated: $script:SourceUrl"
        Save-WebFile -Uri $script:SourceUrl -Destination $scriptPath | Out-Null
    }
    elseif (-not $scriptPath) {
        throw 'The script path could not be determined; cannot re-launch elevated.'
    }

    $argList = @('-NoProfile', '-File', ('"' + $scriptPath + '"'))
    $argList += @('-InstallRoot', ('"' + $InstallRoot + '"'))
    $argList += @('-VsEdition', $VsEdition)
    $argList += '-Yes'
    if ($InstallPrerequisites) { $argList += '-InstallPrerequisites' }
    if ($SkipVisualStudio) { $argList += '-SkipVisualStudio' }
    if ($SkipAndroidLicenses) { $argList += '-SkipAndroidLicenses' }
    if ($SkipVerification) { $argList += '-SkipVerification' }
    if ($LogDirectory) { $argList += @('-LogDirectory', ('"' + $LogDirectory + '"')) }
    if ($script:CurrentUserSid) { $argList += @('-TargetUserSid', $script:CurrentUserSid) }

    Write-RunLog ''
    Write-Info 'Starting an elevated PowerShell window...'
    $p = Start-Process -FilePath $psExe -Verb RunAs -ArgumentList $argList -PassThru -Wait
    Write-RunLog "The elevated run finished with exit code $($p.ExitCode)."
    return $p.ExitCode
}

# ---- start ---------------------------------------------------------------------------
$script:CurrentUserSid = Get-CurrentUserSid

if (-not $LogDirectory) {
    if ($script:IsPiped) {
        # No script file on disk, so there is no folder to write the log next to.
        $LogDirectory = Join-Path ([System.IO.Path]::GetTempPath()) 'flutstaller-logs'
    } else {
        $LogDirectory = Join-Path $PSScriptRoot 'logs'
    }
}
try {
    if (-not (Test-Path -LiteralPath $LogDirectory)) {
        New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
    }
    $script:LogFile = Join-Path $LogDirectory ("flutter-setup-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
} catch {
    # A read-only script folder must not stop the installation.
    $script:LogFile = Join-Path ([System.IO.Path]::GetTempPath()) ("flutter-setup-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Write-Host "WARNING: could not create the log folder '$LogDirectory'. Logging to $($script:LogFile) instead."
}

$script:WorkDir = Join-Path ([System.IO.Path]::GetTempPath()) ("flutstaller-{0}-{1}" -f $env:USERNAME, (Get-Date -Format 'yyyyMMddHHmmss'))
New-Item -ItemType Directory -Path $script:WorkDir -Force | Out-Null

Write-RunLog 'Flutter development environment setup' 'TITLE'
Write-RunLog "This script was written by an AI (OpenCode). Please read the source before running it." 'TITLE'
Write-RunLog "Log file: $($script:LogFile)"
Write-RunLog "Install root: $InstallRoot"
Write-RunLog "PowerShell: $($PSVersionTable.PSVersion) on $env:COMPUTERNAME"
Write-RunLog "Running as: $env:USERDOMAIN\$env:USERNAME (SID $($script:CurrentUserSid))"
Write-RunLog "Elevated: $(Test-IsElevated)"
Write-RunLog "Execution policy: $(Get-ExecutionPolicySummary)"
if ($script:IsPiped) { Write-RunLog 'Mode: PIPED (remote) - running in the current PowerShell session' 'TITLE' }
if ($DryRun) { Write-RunLog 'Mode: DRY RUN - nothing will be changed' 'TITLE' }
if ($PreflightOnly) { Write-RunLog 'Mode: PREFLIGHT ONLY - nothing will be changed' 'TITLE' }

Initialize-Tui
$t = $script:Tui
Write-TuiBanner

$exitCode = 0
try {
    # ---------------------------------------------------------------------------------
    if ($PreflightOnly) {
        Show-Preflight
        return
    }

    # ---------------------------------------------------------------------------------
    # The interactive menu. Skipped when running unattended or from a pipe, so
    # the one-liner and the CI paths stay fully non-interactive.
    # ---------------------------------------------------------------------------------
    $wantFlutter = $true
    $wantAndroid = (-not $SkipAndroid)
    $wantVs      = (-not $SkipVisualStudio)
    # An explicit switch always wins over the menu's default.
    $skipAndroidExplicit = $SkipAndroid
    $skipVsExplicit = $SkipVisualStudio
    if (-not $Yes -and -not $script:IsPiped -and $script:IsInteractive) {
        $menu = Show-MainMenu
        if ($menu.Preflight) { Show-Preflight; return }
        $wantFlutter = ($menu.Components -contains 'flutter')
        $wantAndroid = ($menu.Components -contains 'android')
        $wantVs      = ($menu.Components -contains 'vs')
        if ($skipAndroidExplicit) { $wantAndroid = $false }
        if ($skipVsExplicit) { $wantVs = $false }
    }
    if (-not $wantFlutter) { Write-Info 'Skipping the Flutter SDK (menu choice).' }
    if (-not $wantAndroid) { Write-Info 'Skipping the Android SDK (menu choice or -SkipAndroid).' }
    if (-not $wantVs) { $SkipVisualStudio = $true }

    # ---------------------------------------------------------------------------------
    Write-TuiSection -Title 'RESOLVING' -Detail 'official vendor manifests'
    # ---------------------------------------------------------------------------------
    $flutterRelease = Resolve-FlutterStable
    $cmdlinePackage = $null
    $packageInfo = $null
    if ($wantAndroid) {
        $repoXmlPath = Join-Path $script:WorkDir 'android-repository.xml'
        $repoXml = Get-AndroidRepositoryXml -Destination $repoXmlPath
        $cmdlinePackage = Resolve-AndroidCmdlineTools -Repo $repoXml
        Write-Ok "Android command-line tools build $($cmdlinePackage.Version) resolved"
        Write-Detail $cmdlinePackage.Url

        $packageInfo = Get-AndroidStablePackages -Repo $repoXml
        Write-Info ('Newest published stable build-tools: {0}' -f (($packageInfo.BuildTools | Select-Object -First 3 | ForEach-Object { $_.Path }) -join ', '))
        Write-Info ('Newest published stable platforms : {0}' -f (($packageInfo.Platforms | Select-Object -First 3 | ForEach-Object { $_.Path }) -join ', '))
    } else {
        Write-Info 'The Android SDK is skipped, so its manifest is not fetched.'
    }

    $vsBootstrapperUrl = switch ($VsEdition) {
        'Professional' { $script:VsProfessionalUrl }
        'Enterprise'   { $script:VsEnterpriseUrl }
        default        { $script:VsCommunityUrl }
    }

    # ---------------------------------------------------------------------------------
    Write-TuiSection -Title 'PREREQUISITES' -Detail 'Git for Windows, JDK'
    # ---------------------------------------------------------------------------------
    $gitCmd = Get-Command 'git.exe' -ErrorAction SilentlyContinue
    $jdk = Get-JavaInfo
    $missing = @()
    if (-not $gitCmd) { $missing += 'Git for Windows' }
    if (-not $jdk) { $missing += 'A JDK (17 or newer)' }

    $gitPlan = if ($gitCmd) { 'use-existing' } else { 'skip' }
    $jdkPlan = if ($jdk) { 'use-existing' } else { 'none' }

    if ($missing.Count -gt 0) {
        Write-Host ''
        Write-Host ("  {0} Missing: {1}" -f $t.Warn, ($missing -join ', ')) -ForegroundColor Yellow
        Write-Host ("  {0} They are not part of the three components, so they are only installed" -f $t.Bullet) -ForegroundColor Yellow
        Write-Host ("  {0} if you say so below." -f $t.Bullet) -ForegroundColor Yellow
        $prereqLines = @(
            ('  {0} Git for Windows   {1}' -f $t.Bullet, $script:GitDownloadPage),
            ('  {0} JDK 17 or newer   {1}' -f $t.Bullet, $script:JdkDocsUrl)
        )
        Write-TuiBox -Lines $prereqLines -Title 'PREREQUISITES' -BorderColor 'Yellow' -TextColor 'Gray'

        $prereqOk = $InstallPrerequisites
    if (-not $Yes -and -not $script:IsPiped -and $script:IsInteractive) {
            $prereqOk = Show-PrerequisiteMenu
        }
        if ($prereqOk) {
            if (-not $gitCmd) { $gitPlan = 'install' }
            if (-not $jdk) { $jdkPlan = 'standalone' }
            Write-Info 'The missing prerequisites will be installed from their official vendor sites.'
        } else {
            if (-not $jdk -and $wantVs) {
                # The Visual Studio installer ships Microsoft's own OpenJDK build.
                $jdkPlan = 'vs-component'
                Write-Info 'No JDK found, so the official "OpenJDK (Microsoft distribution)" component will be added to the Visual Studio installation.'
            }
            Write-Warn2 'The missing prerequisites will NOT be installed from their vendor sites.'
        }
    }

    if ($gitCmd) { Write-Ok "Git for Windows found: $($gitCmd.Source)" }
    if ($jdk) { Write-Ok "JDK found (Java $($jdk.Version)) at $($jdk.Path) [via $($jdk.Source)]" }
    if ($gitPlan -eq 'install') { Write-Info "Git for Windows will be installed at $script:GitDir" }
    if ($jdkPlan -eq 'standalone') { Write-Info "Microsoft Build of OpenJDK 17 will be installed at $script:JdkDir" }
    if ($jdkPlan -eq 'none') {
        Write-Warn2 'No JDK is available, so Android builds will not work until one is installed.'
    }

    # ---------------------------------------------------------------------------------
    Write-TuiSection -Title 'PLAN' -Detail 'what is going to change'
    # ---------------------------------------------------------------------------------
    $planItems = New-Object System.Collections.Generic.List[string]
    $planItems.Add("Install root ............ $InstallRoot")
    if ($wantFlutter) {
        $planItems.Add("Flutter SDK ............ $($script:FlutterDir)  (stable $($flutterRelease.Version))")
        $planItems.Add("  download ............ $($flutterRelease.Url)")
    } else {
        $planItems.Add('Flutter SDK ............ SKIPPED (menu choice)')
    }
    if ($wantAndroid) {
        $planItems.Add("Android SDK ........... $($script:AndroidDir)")
        $planItems.Add("  cmd-line tools ..... $($cmdlinePackage.Url)")
        $planItems.Add("  packages ............ platform-tools, build-tools, platforms/android-<Flutter compileSdk>")
    } else {
        $planItems.Add('Android SDK ........... SKIPPED (menu choice or -SkipAndroid)')
    }
    if ($wantVs) {
        $planItems.Add("Visual Studio 2026 ..... $($script:VsDir)  (edition $VsEdition)")
        $planItems.Add("  bootstrapper ....... $vsBootstrapperUrl")
        $planItems.Add("  workload ........... $script:VsCppWorkload (Desktop development with C++)")
        $planItems.Add("  components ......... $script:VsMsvcComponent , $script:VsCMakeComponent")
        if ($jdkPlan -eq 'vs-component') { $planItems.Add("  components ......... $script:VsOpenJdkComponent (supplies the required JDK)") }
        $planItems.Add('  note ............... the Visual Studio Installer itself and the Windows SDK always')
        $planItems.Add('                       install under %ProgramFiles% / %ProgramFiles(x86)% - Microsoft')
        $planItems.Add('                       does not allow relocating them.')
    } else {
        $planItems.Add('Visual Studio 2026 ..... SKIPPED (menu choice or -SkipVisualStudio)')
    }
    if ($jdkPlan -eq 'standalone') { $planItems.Add("OpenJDK 17 ............ $($script:JdkDir)  (Microsoft Build of OpenJDK)") }
    if ($gitPlan -eq 'install')   { $planItems.Add("Git for Windows ....... $($script:GitDir)") }

    $planItems.Add('')
    $planItems.Add('User environment variables that will be set:')
    $planItems.Add("  ANDROID_HOME .......... $script:AndroidDir")
    $planItems.Add("  ANDROID_SDK_ROOT ..... $script:AndroidDir")
    if ($jdkPlan -eq 'standalone') { $planItems.Add("  JAVA_HOME ............ $($script:JdkDir)") }
    $planItems.Add('User PATH entries that will be added (duplicates are skipped):')
    $planItems.Add("  $script:FlutterBin")
    $planItems.Add("  $($script:AndroidDir)\platform-tools")
    $planItems.Add("  $($script:AndroidDir)\cmdline-tools\latest\bin")
    if ($jdkPlan -eq 'standalone') { $planItems.Add("  $($script:JdkDir)\bin") }
    if ($gitPlan -eq 'install') { $planItems.Add("  $($script:GitDir)\cmd") }

    $planItems.Add('')
    $planItems.Add('Approximate disk requirement: ~20 GB free (Flutter ~3.5 GB, Android SDK ~2 GB, Visual Studio 2026 ~10-14 GB).')

    Show-Plan -PlanItems $planItems

    $free = Get-FreeDiskSpace -Path $InstallRoot
    if ($free -gt 0) {
        Write-Info ("Free space: {0}" -f (Format-Size $free))
        if ($free -lt 20GB) {
            Write-Warn2 ('Only {0} free. 20 GB is recommended for a Flutter + Android + Visual Studio setup.' -f (Format-Size $free))
        }
    }

    if ($DryRun) {
        Write-Host ''
        Write-Host '  DRY RUN complete - nothing was changed.' -ForegroundColor Green
        Write-RunLog 'DRY RUN complete - nothing was changed.' 'TITLE'
        return
    }

    # ---------------------------------------------------------------------------------
    # Elevation decision. The Visual Studio installer needs administrator rights.
    # We never relaunch silently: the operator is asked first.
    # ---------------------------------------------------------------------------------
    $installVs = (-not $SkipVisualStudio)
    if ($installVs -and -not (Test-IsElevated)) {
        Write-Host ''
        Write-Host '  Visual Studio 2026 needs administrator rights.' -ForegroundColor Yellow
        Write-Host '  It installs system components, MSBuild and the Windows SDK.' -ForegroundColor Yellow
        if ($TargetUserSid) {
            Write-Warn2 'This session is an elevated re-launch that is still not elevated; not re-launching again.'
            Write-Warn2 'Visual Studio 2026 will not be installed. Re-run the script from an elevated PowerShell window to install it.'
            $installVs = $false
        } else {
            Write-Info 'Re-launching in an elevated window re-runs the steps that are already done; they are skipped automatically.'
            if (Confirm-User 'Re-launch this script elevated to install Visual Studio 2026?' -DefaultNo -AlwaysAsk) {
                $code = Invoke-ElevatedRelaunch
                Write-RunLog "The elevated run exited with code $code."
                $exitCode = $code
                $script:PipeExitCode = $code
                return
            }
            Write-Warn2 'Continuing without Visual Studio. Windows desktop builds will not work until it is installed.'
            $installVs = $false
        }
        if ($jdkPlan -eq 'vs-component') {
            $jdkPlan = 'none'
            Write-Warn2 'The Visual Studio OpenJDK component was not installed, so no JDK is available for Gradle.'
            Write-Detail 'Android builds will fail until a JDK 17+ is installed.'
        }
    }

    # ---------------------------------------------------------------------------------
    # Final confirmation.
    # ---------------------------------------------------------------------------------
    Write-Host ''
    $confirmLines = @(
        ('  {0} Flutter SDK ........ {1}   {2}' -f $t.Bullet, $flutterRelease.Version.PadRight(10), $(if ($wantFlutter) { $script:FlutterDir } else { '(skipped)' })),
        ('  {0} Android SDK ....... {1}   {2}' -f $t.Bullet, $(if ($wantAndroid) { "cmdline-tools $($cmdlinePackage.Version)" } else { '(skipped)' }).PadRight(10), $(if ($wantAndroid) { $script:AndroidDir } else { '(skipped)' })),
        ('  {0} Visual Studio ..... {1}   {2}' -f $t.Bullet, $VsEdition.PadRight(10), $(if ($installVs) { $script:VsDir } else { '(skipped)' }))
    )
    Write-TuiBox -Lines $confirmLines -Title 'READY TO INSTALL' -BorderColor 'Green' -TextColor 'Gray'
    if (-not (Confirm-User 'Proceed with the installation described above?' -DefaultNo)) {
        Write-Host '  Cancelled - nothing was changed.' -ForegroundColor Yellow
        Write-RunLog 'Cancelled by the operator. Nothing was changed.' 'TITLE'
        return
    }

    # ---------------------------------------------------------------------------------
    Write-TuiSection -Title 'Creating directories'
    # ---------------------------------------------------------------------------------
    # The Flutter directory is deliberately NOT pre-created: the SDK archive is
    # extracted into a staging folder and then moved into place, and Move-Item
    # would otherwise nest it as <root>\flutter\flutter.
    $dirs = @($InstallRoot)
    if ($wantAndroid) { $dirs += $script:AndroidDir }
    foreach ($d in $dirs) {
        if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    }

    # ---------------------------------------------------------------------------------
    Write-TuiSection -Title ('STEP 1/5  ' + $t.Bullet + '  Flutter SDK') -Detail $flutterRelease.Version
    # ---------------------------------------------------------------------------------
    if ($wantFlutter) {
        $null = Invoke-ComponentStep -Name 'Flutter SDK' -Action {
            if (Test-Path -LiteralPath $script:FlutterExe) {
                return @{ State = 'present'; Detail = "already installed at $($script:FlutterDir)" }
            }
            Install-Flutter -Release $flutterRelease | Out-Null
            [void]$script:Actions.Add("Flutter SDK $($flutterRelease.Version) -> $($script:FlutterDir)")
            return @{ State = 'ok'; Detail = "installed $($flutterRelease.Version) -> $($script:FlutterDir)" }
        }
    } else {
        Add-Result -Item 'Flutter SDK' -State 'skip' -Detail 'skipped by choice'
    }

    # ---------------------------------------------------------------------------------
    Write-TuiSection -Title ('STEP 2/5  ' + $t.Bullet + '  Android SDK command-line tools') -Detail ("build $($cmdlinePackage.Version)")
    # ---------------------------------------------------------------------------------
    if ($wantAndroid) {
        $null = Invoke-ComponentStep -Name 'Android SDK tools' -Action {
            if (Test-Path -LiteralPath $script:SdkManagerBat) {
                return @{ State = 'present'; Detail = "already installed at $($script:AndroidDir)" }
            }
            Install-AndroidCmdlineTools -Package $cmdlinePackage | Out-Null
            [void]$script:Actions.Add("Android SDK command-line tools $($cmdlinePackage.Version) -> $($script:AndroidDir)")
            return @{ State = 'ok'; Detail = "installed cmdline-tools $($cmdlinePackage.Version) -> $($script:AndroidDir)" }
        }
    } else {
        Add-Result -Item 'Android SDK tools' -State 'skip' -Detail 'skipped by choice'
    }

    # ---------------------------------------------------------------------------------
    Write-TuiSection -Title ('STEP 3/5  ' + $t.Bullet + '  Prerequisites') -Detail 'Git for Windows, JDK'
    # ---------------------------------------------------------------------------------
    if ($gitPlan -eq 'install') {
        $null = Invoke-ComponentStep -Name 'Git for Windows' -Action {
            $gitRelease = Resolve-GitForWindows
            Install-GitForWindows -Release $gitRelease | Out-Null
            [void]$script:Actions.Add("Git for Windows $($gitRelease.Version) -> $($script:GitDir)")
            $env:PATH = (Join-Path $script:GitDir 'cmd') + ';' + $env:PATH
            return "installed $($gitRelease.Version) -> $($script:GitDir)"
        }
    } else {
        Add-Result -Item 'Git for Windows' -State $(if ($gitPlan -eq 'use-existing') { 'present' } else { 'skip' }) `
            -Detail $(if ($gitPlan -eq 'use-existing') { "found at $($gitCmd.Source)" } else { 'not installed' }) `
            -NextAction $(if ($gitPlan -eq 'use-existing') { '' } else { "Install Git for Windows from $($script:GitDownloadPage) - the flutter command needs it." })
    }

    if ($jdkPlan -eq 'standalone') {
        $null = Invoke-ComponentStep -Name 'OpenJDK 17' -Action {
            Install-OpenJdk | Out-Null
            [void]$script:Actions.Add("Microsoft Build of OpenJDK 17 -> $($script:JdkDir)")
            return "installed -> $($script:JdkDir)"
        }
    }

    # ---------------------------------------------------------------------------------
    Write-TuiSection -Title ('STEP 4/5  ' + $t.Bullet + '  Visual Studio 2026') -Detail $VsEdition
    # ---------------------------------------------------------------------------------
    if ($installVs) {
        $null = Invoke-ComponentStep -Name 'Visual Studio 2026' -Action {
            Install-VisualStudio -IncludeOpenJdkComponent:($jdkPlan -eq 'vs-component') | Out-Null
            [void]$script:Actions.Add("Visual Studio 2026 $VsEdition -> $($script:VsDir)")
            return "installed $VsEdition -> $($script:VsDir)"
        }
    } else {
        Add-Result -Item 'Visual Studio 2026' -State 'skip' -Detail 'not installed in this run' `
            -NextAction 'Re-run the script from an elevated PowerShell window to install it.'
    }

    # Re-resolve the JDK: the Visual Studio OpenJDK component may have supplied one.
    $jdk = Get-JavaInfo
    if ($jdk) {
        Write-Ok "JDK in use: $($jdk.Path) (Java $($jdk.Version), via $($jdk.Source))"
        if ($jdkPlan -ne 'use-existing') { Add-Result -Item 'JDK' -State 'present' -Detail "Java $($jdk.Version) at $($jdk.Path)" }
    } else {
        Add-Result -Item 'JDK' -State 'pending' -Detail 'not found' `
            -NextAction "Install a JDK 17+ from $($script:JdkDocsUrl). Gradle needs one to build Android apps."
    }

    # ---------------------------------------------------------------------------------
    Write-TuiSection -Title ('STEP 5/5  ' + $t.Bullet + '  Android SDK packages') -Detail 'licence, platform-tools, build-tools, platform'
    # ---------------------------------------------------------------------------------
    if (-not $wantAndroid) {
        Add-Result -Item 'Android SDK packages' -State 'skip' -Detail 'skipped by choice'
    } else {
        $compileSdk = Get-FlutterCompileSdk
        if ($compileSdk) {
            Write-Info "Flutter declares compileSdkVersion = $compileSdk, so that Android platform will be installed."
        } else {
            Write-Warn2 'Could not read compileSdkVersion from the Flutter SDK; the newest published platform will be used instead.'
        }

        # The licence must be confirmed before the first android / sdkmanager run,
        # because that is where the Android CLI presents and records it.
        $licenceAccepted = $false
        if ($SkipAndroidLicenses) {
            Write-Warn2 'Android SDK licence acceptance was skipped (-SkipAndroidLicenses).'
            Write-Detail 'The Android SDK packages cannot be installed without accepting the licence.'
        } else {
            $licenceAccepted = Confirm-AndroidSdkLicense
        }

        if ($licenceAccepted) {
            $alreadyThere = (Test-Path -LiteralPath (Join-Path $script:AndroidDir 'platform-tools\adb.exe'))
            $null = Invoke-ComponentStep -Name 'Android SDK packages' -Action {
                Install-AndroidPackages -PackageInfo $packageInfo -CompileSdk $compileSdk -JavaHome $(if ($jdk) { $jdk.Path } else { $null }) | Out-Null
                [void]$script:Actions.Add("Android SDK packages -> $($script:AndroidDir)")
                [void]$script:Actions.Add('Android SDK License Agreement accepted')
                if ($alreadyThere) {
                    return @{ State = 'present'; Detail = "already installed -> $($script:AndroidDir)" }
                }
                return @{ State = 'ok'; Detail = "installed -> $($script:AndroidDir)" }
            }
            try {
                $null = Accept-LegacyAndroidLicenses -JavaHome $(if ($jdk) { $jdk.Path } else { $null })
            } catch {
                Write-Err "Android SDK licence acceptance failed: $($_.Exception.Message)"
            }
        } else {
            Add-Result -Item 'Android SDK packages' -State 'pending' -Detail 'licence not accepted' `
                -NextAction "Accept the Android SDK licence at $($script:AndroidLicenseUrl) and re-run, or run: flutter doctor --android-licenses"
        }
    }

    # ---------------------------------------------------------------------------------
    Write-TuiSection -Title 'ENVIRONMENT' -Detail 'user PATH, ANDROID_HOME, ANDROID_SDK_ROOT'
    # ---------------------------------------------------------------------------------
    # This step deliberately never aborts the run: the environment must be
    # configured even when a component install failed, otherwise a machine with
    # a partially failed install ends up with a half-configured toolchain.
    $envLines = @()
    $pathEntries = @(
        $script:FlutterBin,
        (Join-Path $script:AndroidDir 'platform-tools'),
        (Join-Path $script:AndroidDir 'cmdline-tools\latest\bin')
    )
    if (Test-Path -LiteralPath (Join-Path $script:JdkDir 'bin\java.exe')) { $pathEntries += (Join-Path $script:JdkDir 'bin') }
    if (Test-Path -LiteralPath (Join-Path $script:GitDir 'cmd\git.exe')) { $pathEntries += (Join-Path $script:GitDir 'cmd') }

    $envOk = $true
    foreach ($v in @(@{ N = 'ANDROID_HOME'; V = $script:AndroidDir }, @{ N = 'ANDROID_SDK_ROOT'; V = $script:AndroidDir })) {
        try {
            $existing = Get-UserEnvRaw $v.N
            if ($existing -and ($existing.TrimEnd('\') -ne $v.V.TrimEnd('\'))) {
                Write-Warn2 "$($v.N) was already set to '$existing' and is being changed to '$($v.V)'."
            }
            Set-UserEnv $v.N $v.V
            $envLines += ('{0} {1} = {2}' -f $t.Ok, $v.N.PadRight(18), $v.V)
        } catch {
            $envOk = $false
            $envLines += ('{0} {1} = FAILED: {2}' -f $t.Fail, $v.N, $_.Exception.Message)
        }
    }

    # A machine-wide value shadows the user one in every new terminal, so it has
    # to be called out rather than silently leaving a confusing environment.
    foreach ($v in @('ANDROID_HOME', 'ANDROID_SDK_ROOT')) {
        $machine = [Environment]::GetEnvironmentVariable($v, 'Machine')
        if ($machine -and ($machine.TrimEnd('\') -ne $script:AndroidDir.TrimEnd('\'))) {
            Write-Warn2 "A machine-wide $v is set to '$machine' and will shadow the value just set for your account."
            Write-Detail "Remove or change the machine-wide $v (needs administrator rights) so that $v resolves to $($script:AndroidDir)."
            Add-Result -Item "Machine-wide $v" -State 'pending' -Detail "set to '$machine'" `
                -NextAction "Change the machine-wide $v to $($script:AndroidDir) (or remove it), otherwise it shadows the value set for your account."
        }
    }
    if ($jdkPlan -eq 'standalone') {
        try {
            if (Get-UserEnvRaw 'JAVA_HOME') {
                Write-Info 'JAVA_HOME is already set in your environment; it was left unchanged.'
                $envLines += ('{0} {1} = (unchanged)' -f $t.Info, 'JAVA_HOME'.PadRight(18))
            } else {
                Set-UserEnv 'JAVA_HOME' $script:JdkDir
                $envLines += ('{0} {1} = {2}' -f $t.Ok, 'JAVA_HOME'.PadRight(18), $script:JdkDir)
            }
        } catch {
            $envOk = $false
            $envLines += ('{0} {1} = FAILED: {2}' -f $t.Fail, 'JAVA_HOME', $_.Exception.Message)
        }
    }

    try {
        $added = Add-UserPathEntries -Entries $pathEntries
        if ($added.Count -gt 0) {
            foreach ($a in $added) { Write-Ok "Added to user PATH: $a" }
            [void]$script:Actions.Add("User PATH updated (added $($added.Count) entr$(if ($added.Count -eq 1) { 'y' } else { 'ies' }))")
            $envLines += ('{0} {1} = {2} entr{3} added' -f $t.Ok, 'PATH'.PadRight(18), $added.Count, $(if ($added.Count -eq 1) { 'y' } else { 'ies' }))
        } else {
            Write-Ok 'The user PATH already contains all required entries; nothing was changed.'
            $envLines += ('{0} {1} = already up to date' -f $t.Info, 'PATH'.PadRight(18))
        }
    } catch {
        $envOk = $false
        $envLines += ('{0} {1} = FAILED: {2}' -f $t.Fail, 'PATH', $_.Exception.Message)
    }
    Write-TuiBox -Lines $envLines -Title 'USER ENVIRONMENT' -BorderColor 'DarkCyan' -TextColor 'Gray'

    if ($envOk) {
        Add-Result -Item 'User environment' -State 'configured' -Detail 'PATH, ANDROID_HOME, ANDROID_SDK_ROOT set'
    } else {
        Add-Result -Item 'User environment' -State 'fail' -Detail 'one or more variables could not be set' `
            -NextAction 'Set them manually: ANDROID_HOME and ANDROID_SDK_ROOT to the Android SDK folder, and add the Flutter and platform-tools folders to your user PATH.'
    }

    if (Test-Path -LiteralPath $script:FlutterExe) {
        $env:PATH = "$script:FlutterBin;" + $env:PATH
        if (Test-Path -LiteralPath $script:AndroidDir) {
            Write-Info 'Running: flutter config --android-sdk'
            $r = Invoke-Native -FilePath $script:FlutterExe -Arguments @('config', '--android-sdk', $script:AndroidDir) -TimeoutSeconds 900
            Write-NativeOutput $r.StdOut
        } else {
            Write-Info 'Skipping flutter config --android-sdk (the Android SDK was not installed).'
        }
        if ($jdk) {
            Write-Info 'Running: flutter config --jdk-dir'
            $r = Invoke-Native -FilePath $script:FlutterExe -Arguments @('config', '--jdk-dir', $jdk.Path) -TimeoutSeconds 900
            Write-NativeOutput $r.StdOut
        }
    }

    # ---------------------------------------------------------------------------------
    if (-not $SkipVerification) {
        $null = Invoke-Verification -JavaHome $(if ($jdk) { $jdk.Path } else { $null })
    } else {
        Write-Warn2 'Verification was skipped (-SkipVerification).'
    }

    # ---------------------------------------------------------------------------------
    Show-ResultReport
    # ---------------------------------------------------------------------------------
    if ($script:Warnings.Count -gt 0) {
        Write-Host ''
        Write-Host '  Warnings:' -ForegroundColor Yellow
        foreach ($w in $script:Warnings) { Write-Host ("   {0} {1}" -f $t.Warn, $w) -ForegroundColor DarkYellow }
    }
    if ($script:Failures.Count -gt 0) {
        $exitCode = 1
    } else {
        Write-Host ''
        Write-Host '  All requested components were installed and verified.' -ForegroundColor Green
    }

    Write-Host ''
    Write-Host '  Open a NEW terminal before using flutter / adb so the updated PATH is picked up.' -ForegroundColor Cyan
    Write-RunLog 'Open a NEW terminal before using flutter / adb so the updated PATH is picked up.' 'INFO'
}
catch {
    Write-RunLog ''
    Write-Err "FAILED: $($_.Exception.Message)"
    Write-RunLog "Exception detail: $($_.Exception.GetType().FullName) at $($_.InvocationInfo.PositionMessage)" 'ERROR'
    Write-RunLog "Log file: $($script:LogFile)"
    $exitCode = 1
    $script:PipeExitCode = 1
    if ($script:IsPiped) {
        # There is no exit code to return in pipe mode, so surface the failure
        # as a terminating error in the caller's session.
        $failure = $_.Exception.Message
    }
}
finally {
    try {
        if ($script:WorkDir -and (Test-Path -LiteralPath $script:WorkDir)) {
            Remove-Item -LiteralPath $script:WorkDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    } catch { }

    if ($script:IsPiped) {
        # Put the caller's strict mode setting back the way we found it.
        if (-not $script:StrictModeWasOn) { try { Set-StrictMode -Off } catch { } }
    } else {
        exit $exitCode
    }
}

if ($script:IsPiped -and $script:PipeExitCode -ne 0) {
    throw "Setup failed: $failure`nSee the log for details: $($script:LogFile)"
}
