# =============================================================================
# File    : Comparison.ps1
# Purpose : For every ZIP found in the source scan, locate its baseline
#           counterpart, compare hashes, and return a result object per file.
#
#   Action values returned
#       COPY  - file is new or has changed  (send to destination)
#       SKIP  - file is identical to baseline (do nothing)
# =============================================================================

function Compare-ZipFiles {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject[]]$SourceFiles,

        [Parameter(Mandatory)]
        [string]$BaselineFolder,

        [Parameter(Mandatory)]
        [bool]$ContentMode
    )

    foreach ($file in $SourceFiles) {

        Write-LogEntry -Level 'INFO' -Message "Evaluating: $($file.FileName)"

        # ── Locate baseline directory for this file ───────────────────────────
        $relativeDir = Split-Path -Path $file.RelativePath -Parent

        $baselineDir = if ($relativeDir) {
            Join-Path -Path $BaselineFolder -ChildPath $relativeDir
        }
        else {
            $BaselineFolder
        }

        # ── Guard: baseline directory does not exist ──────────────────────────
        if (-not (Test-Path -Path $baselineDir -PathType Container)) {
            Write-LogEntry -Level 'INFO' `
                -Message "  -> COPY  [NEW - no baseline directory found]"

            [PSCustomObject]@{
                FileName     = $file.FileName
                FullPath     = $file.FullPath
                RelativePath = $file.RelativePath
                Action       = 'COPY'
                Reason       = 'NEW_NO_BASELINE_DIR'
            }
            continue
        }

        # ── Derive the base product name (strip trailing date stamp) ──────────
        # Handles both _YYYYMMDD and -YYYYMMDD suffixes before the extension
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($file.FileName) `
                        -replace '[_-]\d{8}$', ''

        # ── Find the baseline ZIP whose stem matches the base product name ─────
        $baselineZip = Get-ChildItem `
                            -Path    $baselineDir `
                            -Filter  '*.zip' `
                            -File `
                            -ErrorAction SilentlyContinue |
                       Where-Object {
                           ($([System.IO.Path]::GetFileNameWithoutExtension($_.Name)) `
                               -replace '[_-]\d{8}$', '') -eq $baseName
                       } |
                       Select-Object -First 1

        # ── Guard: no matching baseline ZIP ───────────────────────────────────
        if ($null -eq $baselineZip) {
            Write-LogEntry -Level 'INFO' `
                -Message "  -> COPY  [NEW - no baseline ZIP matched '$baseName']"

            [PSCustomObject]@{
                FileName     = $file.FileName
                FullPath     = $file.FullPath
                RelativePath = $file.RelativePath
                Action       = 'COPY'
                Reason       = 'NEW_NO_BASELINE_ZIP'
            }
            continue
        }

        Write-LogEntry -Level 'DEBUG' `
            -Message "  Baseline : $($baselineZip.FullName)"

        # ── Hash both files ───────────────────────────────────────────────────
        Write-LogEntry -Level 'DEBUG' -Message "  Hashing source   ..."
        $sourceHash = Get-ZipFileHash -ZipPath $file.FullPath -ContentMode $ContentMode

        Write-LogEntry -Level 'DEBUG' -Message "  Hashing baseline ..."
        $baselineHash = Get-ZipFileHash -ZipPath $baselineZip.FullName -ContentMode $ContentMode

        # ── Guard: hash computation failed ────────────────────────────────────
        if ($null -eq $sourceHash -or $null -eq $baselineHash) {
            Write-LogEntry -Level 'WARNING' `
                -Message "  -> COPY  [HASH FAILED - treating as changed]"

            [PSCustomObject]@{
                FileName     = $file.FileName
                FullPath     = $file.FullPath
                RelativePath = $file.RelativePath
                Action       = 'COPY'
                Reason       = 'HASH_FAILED'
            }
            continue
        }

        # ── Compare ───────────────────────────────────────────────────────────
        if ($sourceHash -eq $baselineHash) {
            Write-LogEntry -Level 'INFO' -Message "  -> SKIP  [IDENTICAL]"

            [PSCustomObject]@{
                FileName     = $file.FileName
                FullPath     = $file.FullPath
                RelativePath = $file.RelativePath
                Action       = 'SKIP'
                Reason       = 'IDENTICAL'
            }
        }
        else {
            Write-LogEntry -Level 'INFO' -Message "  -> COPY  [CHANGED]"

            [PSCustomObject]@{
                FileName     = $file.FileName
                FullPath     = $file.FullPath
                RelativePath = $file.RelativePath
                Action       = 'COPY'
                Reason       = 'CHANGED'
            }
        }
    }
}