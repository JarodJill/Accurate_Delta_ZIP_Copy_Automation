# =============================================================================
# File    : DeltaChanges.ps1
# Purpose : Entry point. Loads all modules and drives the five-stage pipeline.
#
#   Stage 1  Scanning.ps1    - discover ZIP files in source
#   Stage 2  Hashing.ps1     - compute SHA-256 fingerprints
#   Stage 3  Comparison.ps1  - determine NEW / MATCH / MISMATCH
#   Stage 4  CopyPaste.ps1   - copy only changed files
#   Stage 5  Logging.ps1     - write summary and close log
#
# Compatible : PowerShell 5.1+
#
# Usage
# -----
#   Minimal (reads paths from config.json):
#       .\DeltaChanges.ps1
#
#   All parameters explicit:
#       .\DeltaChanges.ps1 `
#           -SourceFolder      "C:\Source" `
#           -DestinationFolder "\\SERVER01\Share\Dest" `
#           -BaselineFolder    "C:\Baseline" `
#           -LogFolder         "C:\Logs"
#
#   Content-mode hashing:
#       .\DeltaChanges.ps1 -ContentMode
#
#   Custom config file:
#       .\DeltaChanges.ps1 -ConfigFile "D:\MyConfig.json"
# =============================================================================
[CmdletBinding()]
param(
    [string]$SourceFolder,
    [string]$DestinationFolder,
    [string]$BaselineFolder,
    [string]$LogFolder,
    [switch]$ContentMode,
    [string]$ConfigFile = "$PSScriptRoot\config.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Load all modules ──────────────────────────────────────────────────────────
. "$PSScriptRoot\Logging.ps1"
. "$PSScriptRoot\Scanning.ps1"
. "$PSScriptRoot\Hashing.ps1"
. "$PSScriptRoot\Comparison.ps1"
. "$PSScriptRoot\CopyPaste.ps1"

# PS 5.1 safe - uses Get-Member NoteProperty instead of PSObject.Properties
$config = @{}

if (Test-Path -Path $ConfigFile -PathType Leaf) {
    try {
        $jsonObject = Get-Content -Path $ConfigFile -Raw | ConvertFrom-Json

        # Get-Member -MemberType NoteProperty is the correct PS 5.1 way
        # to enumerate properties returned by ConvertFrom-Json
        $jsonObject |
            Get-Member -MemberType NoteProperty |
            ForEach-Object {
                $config[$_.Name] = $jsonObject.($_.Name)
            }

        Write-Host "Config loaded: $($config.Keys.Count) setting(s) found." `
            -ForegroundColor Green
    }
    catch {
        Write-Warning "Could not parse config file '$ConfigFile': $($_.Exception.Message)"
        $config = @{}
    }
}

# ── Merge config with CLI parameters (CLI always wins) ────────────────────────
function Resolve-Setting {
    param(
        [string]$CliValue,
        [string]$ConfigKey,
        [string]$Default = ''
    )
    if ($CliValue)                               { return $CliValue }
    if ($config.ContainsKey($ConfigKey) `
        -and $config[$ConfigKey])                { return $config[$ConfigKey] }
    return $Default
}

$SourceFolder      = Resolve-Setting $SourceFolder      'SourceFolder'
$DestinationFolder = Resolve-Setting $DestinationFolder 'DestinationFolder'
$BaselineFolder    = Resolve-Setting $BaselineFolder    'BaselineFolder' `
                         (Join-Path $PSScriptRoot 'Baseline')
$LogFolder         = Resolve-Setting $LogFolder         'LogFolder' `
                         (Join-Path $PSScriptRoot 'Logs')

# Resolve ContentMode — CLI switch takes priority, then config.json value
$useContentMode = $ContentMode.IsPresent
if (-not $useContentMode -and $config.ContainsKey('ContentMode')) {
    $useContentMode = ($config['ContentMode'] -eq $true)
}

# ── Validate mandatory parameters ─────────────────────────────────────────────
$missing = @()
if (-not $SourceFolder)      { $missing += 'SourceFolder' }
if (-not $DestinationFolder) { $missing += 'DestinationFolder' }

if ($missing.Count -gt 0) {
    throw ("Missing mandatory setting(s): {0}. " +
           "Provide via CLI parameter or config.json.") -f ($missing -join ', ')
}

# ── Initialise the logger ─────────────────────────────────────────────────────
$logFileName = "DeltaZipCopy_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$logFilePath = Join-Path $LogFolder $logFileName

Initialize-Log -LogPath $logFilePath

# ── Log resolved configuration ────────────────────────────────────────────────
Write-LogEntry -Level 'INFO' -Message "PowerShell Version : $($PSVersionTable.PSVersion)"
Write-LogEntry -Level 'INFO' -Message "Source Folder      : $SourceFolder"
Write-LogEntry -Level 'INFO' -Message "Destination Folder : $DestinationFolder"
Write-LogEntry -Level 'INFO' -Message "Baseline Folder    : $BaselineFolder"
Write-LogEntry -Level 'INFO' -Message "Log File           : $logFilePath"
Write-LogEntry -Level 'INFO' -Message "Content Mode       : $useContentMode"
Write-LogEntry -Level 'INFO' -Message "Config File        : $ConfigFile"

# ── Five-stage pipeline ───────────────────────────────────────────────────────
try {

    # ------------------------------------------------------------------
    # STAGE 1 - SCANNING
    # ------------------------------------------------------------------
    Write-LogEntry -Level 'INFO' -Message "===== STAGE 1: SCANNING ====="

    $sourceFiles = Get-SourceZipFiles -SourceFolder $SourceFolder

    if ($sourceFiles.Count -eq 0) {
        Write-LogEntry -Level 'INFO' `
            -Message "No ZIP files found. Nothing to process. Exiting."
        Write-LogSummary
        exit 0
    }

    # ------------------------------------------------------------------
    # STAGE 2 + 3 - HASHING AND COMPARISON
    # ------------------------------------------------------------------
    Write-LogEntry -Level 'INFO' -Message "===== STAGE 2+3: HASHING & COMPARISON ====="

    $comparisonResults = Compare-ZipFiles `
                             -SourceFiles    $sourceFiles `
                             -BaselineFolder $BaselineFolder `
                             -ContentMode    $useContentMode

    # ------------------------------------------------------------------
    # STAGE 4 - DELTA COPY
    # ------------------------------------------------------------------
    Write-LogEntry -Level 'INFO' -Message "===== STAGE 4: DELTA COPY ====="

    Invoke-DeltaCopy `
        -ComparisonResults $comparisonResults `
        -DestinationFolder $DestinationFolder `
        -BaselineFolder    $BaselineFolder

}
catch {
    Write-LogEntry -Level 'ERROR' `
        -Message "Unhandled pipeline error: $_"
}
finally {
    # Always runs — even if an unhandled error occurs above
    Write-LogEntry -Level 'INFO' -Message "===== STAGE 5: SUMMARY ====="
    Write-LogSummary
}