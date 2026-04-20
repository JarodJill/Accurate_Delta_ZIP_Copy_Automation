# =============================================================================
# File    : Tests\Run-Tests.ps1
# Purpose : Automated test suite covering the three core acceptance criteria.
#
#   TC-01  New ZIP     → Status: NEW      | Action: COPY   | File appears in dest
#   TC-02  Changed ZIP → Status: MISMATCH | Action: COPY   | File overwritten
#   TC-03  Unchanged   → Status: MATCH    | Action: SKIP   | No copy performed
#
# Run from project root:
#   .\Tests\Run-Tests.ps1
# =============================================================================
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.IO.Compression.FileSystem

# ── Test counters ─────────────────────────────────────────────────────────────
$Script:Pass = 0
$Script:Fail = 0

# ── Temporary test workspace (wiped after each run) ───────────────────────────
$testRoot = Join-Path $env:TEMP "DeltaZipTest_$(Get-Date -Format 'yyyyMMddHHmmss')"
$srcDir   = Join-Path $testRoot 'Source'
$dstDir   = Join-Path $testRoot 'Destination'
$basDir   = Join-Path $testRoot 'Baseline'
$logDir   = Join-Path $testRoot 'Logs'

@($srcDir, $dstDir, $basDir, $logDir) | ForEach-Object {
    New-Item -ItemType Directory -Path $_ -Force | Out-Null
}

# ── Load project modules ──────────────────────────────────────────────────────
$projectRoot = Split-Path $PSScriptRoot -Parent
. "$projectRoot\Logging.ps1"
. "$projectRoot\Scanning.ps1"
. "$projectRoot\Hashing.ps1"
. "$projectRoot\Comparison.ps1"
. "$projectRoot\CopyPaste.ps1"

Initialize-Log -LogPath (Join-Path $logDir 'test_run.log')

# ── Helper: create a minimal valid ZIP with text content ──────────────────────
function New-TestZip {
    param(
        [string]$ZipPath,
        [string]$Content      # Content written into the single entry inside the ZIP.
    )

    $zipDir = Split-Path $ZipPath -Parent
    if (-not (Test-Path $zipDir)) {
        New-Item -ItemType Directory $zipDir -Force | Out-Null
    }

    if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }

    # Create a temp folder, write one file, zip it, clean up.
    $tmpDir  = Join-Path $env:TEMP "zipbuild_$(New-Guid)"
    New-Item -ItemType Directory $tmpDir -Force | Out-Null
    Set-Content -Path (Join-Path $tmpDir 'content.txt') -Value $Content -Encoding UTF8
    [System.IO.Compression.ZipFile]::CreateFromDirectory($tmpDir, $ZipPath)
    Remove-Item $tmpDir -Recurse -Force
}

# ── Helper: assertion ─────────────────────────────────────────────────────────
function Assert-Equal {
    param(
        [string]$TestName,
        $Expected,
        $Actual
    )

    if ("$Expected" -eq "$Actual") {
        Write-Host "  [PASS] $TestName" -ForegroundColor Green
        $Script:Pass++
    }
    else {
        Write-Host "  [FAIL] $TestName" -ForegroundColor Red
        Write-Host "         Expected : '$Expected'" -ForegroundColor Yellow
        Write-Host "         Actual   : '$Actual'"   -ForegroundColor Yellow
        $Script:Fail++
    }
}

# ── Helper: run the full pipeline and return comparison results ───────────────
function Invoke-Pipeline {
    $files   = Get-SourceZipFiles -SourceFolder $srcDir
    $results = Compare-ZipFiles   -SourceFiles $files -BaselineFolder $basDir
    Invoke-DeltaCopy -ComparisonResults $results `
                     -DestinationFolder $dstDir `
                     -BaselineFolder    $basDir
    return $results
}

# =============================================================================
# TC-01 — NEW ZIP
#   Scenario : File exists in source. No corresponding entry in baseline.
#   Expected : Status=NEW, Action=COPY, file appears in destination and baseline.
# =============================================================================
Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor White
Write-Host " TC-01 : New ZIP Detection" -ForegroundColor White
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor White

# Prepare: one ZIP in source, baseline is empty.
New-TestZip -ZipPath (Join-Path $srcDir 'ProductA_20260420.zip') `
            -Content 'TC-01 initial content'

$results  = Invoke-Pipeline
$tc01     = $results | Where-Object { $_.SourceFile.FileName -eq 'ProductA_20260420.zip' }

Assert-Equal 'TC-01: Status is NEW'                 'NEW'  $tc01.Status
Assert-Equal 'TC-01: Action is COPY'                'COPY' $tc01.Action
Assert-Equal 'TC-01: File delivered to destination' $true  (Test-Path (Join-Path $dstDir 'ProductA_20260420.zip'))
Assert-Equal 'TC-01: Baseline created (clean name)' $true  (Test-Path (Join-Path $basDir 'ProductA.zip'))

# =============================================================================
# TC-02 — CHANGED ZIP
#   Scenario : Source file content has changed since the last run (baseline
#              holds the old version).
#   Expected : Status=MISMATCH, Action=COPY, destination and baseline updated.
# =============================================================================
Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor White
Write-Host " TC-02 : Changed ZIP Detection" -ForegroundColor White
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor White

# Simulate a prior run: baseline has OLD content.
New-TestZip -ZipPath (Join-Path $basDir 'ProductA.zip') `
            -Content 'TC-02 OLD content in baseline'

# Source now has NEW content.
New-TestZip -ZipPath (Join-Path $srcDir 'ProductA_20260420.zip') `
            -Content 'TC-02 NEW content in source'

$results = Invoke-Pipeline
$tc02    = $results | Where-Object { $_.SourceFile.FileName -eq 'ProductA_20260420.zip' }

Assert-Equal 'TC-02: Status is MISMATCH'    'MISMATCH' $tc02.Status
Assert-Equal 'TC-02: Action is COPY'        'COPY'     $tc02.Action
Assert-Equal 'TC-02: Destination updated'   $true      (Test-Path (Join-Path $dstDir 'ProductA_20260420.zip'))
Assert-Equal 'TC-02: Baseline updated'      $true      (Test-Path (Join-Path $basDir 'ProductA.zip'))

# Verify baseline was actually updated (its hash must now match source).
$srcHash  = Get-ZipFileHash -ZipPath (Join-Path $srcDir 'ProductA_20260420.zip')
$baseHash = Get-ZipFileHash -ZipPath (Join-Path $basDir 'ProductA.zip')
Assert-Equal 'TC-02: Baseline hash matches source hash' $srcHash $baseHash

# =============================================================================
# TC-03 — UNCHANGED ZIP
#   Scenario : Source content is identical to the baseline.
#   Expected : Status=MATCH, Action=SKIP, no copy performed.
# =============================================================================
Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor White
Write-Host " TC-03 : Unchanged ZIP Skip" -ForegroundColor White
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor White

# Sync baseline to exactly match source (simulates a fully up-to-date baseline).
Copy-Item -Path (Join-Path $srcDir 'ProductA_20260420.zip') `
          -Destination (Join-Path $basDir 'ProductA.zip') -Force

# Remove destination copy so we can confirm it was NOT re-created.
$destFile = Join-Path $dstDir 'ProductA_20260420.zip'
if (Test-Path $destFile) { Remove-Item $destFile -Force }

$results = Invoke-Pipeline
$tc03    = $results | Where-Object { $_.SourceFile.FileName -eq 'ProductA_20260420.zip' }

Assert-Equal 'TC-03: Status is MATCH'          'MATCH' $tc03.Status
Assert-Equal 'TC-03: Action is SKIP'           'SKIP'  $tc03.Action
Assert-Equal 'TC-03: Destination NOT touched'  $false  (Test-Path $destFile)

# ── Cleanup & final report ────────────────────────────────────────────────────
Remove-Item -Path $testRoot -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor White
Write-Host " TEST RESULTS" -ForegroundColor White
Write-Host " PASSED : $($Script:Pass)" -ForegroundColor Green
Write-Host " FAILED : $($Script:Fail)" -ForegroundColor $(if ($Script:Fail -eq 0) {'Green'} else {'Red'})
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n" -ForegroundColor White

exit $Script:Fail   # 0 = all passed. Non-zero = something failed (useful for CI).