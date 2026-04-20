# =============================================================================
# File    : CopyPaste.ps1
# Purpose : Execute the physical file copy for every result where Action=COPY.
#
#   For each eligible file this module:
#     1. Ensures the destination subfolder exists    (creates it if missing).
#     2. Copies the source ZIP to destination        (original dated filename).
#     3. Ensures the baseline subfolder exists       (creates it if missing).
#     4. Copies the source ZIP to baseline           (clean undated filename).
#
#   Destination keeps original filenames (audit trail).
#   Baseline keeps clean names (future comparison reference).
#
# Exports : Invoke-DeltaCopy
# =============================================================================

function Invoke-DeltaCopy {
    [CmdletBinding()]
    param(
        # Full results array produced by Compare-ZipFiles.
        # Uses [object[]] instead of [PSCustomObject[]] to prevent
        # silent coercion failures on single-element collections in PS 5.1.
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$ComparisonResults,

        # Root folder where changed ZIPs are delivered (original filenames).
        [Parameter(Mandatory = $true)]
        [string]$DestinationFolder,

        # Root baseline folder updated after every successful copy.
        [Parameter(Mandatory = $true)]
        [string]$BaselineFolder
    )

    # Wrap in @() so .Count is always safe regardless of 0, 1, or N results
    $filesToCopy = @($ComparisonResults | Where-Object { $_.Action -eq 'COPY' })

    if ($filesToCopy.Count -eq 0) {
        Write-LogEntry -Level 'INFO' -Message "Nothing to copy - all files are up-to-date."
        return
    }

    Write-LogEntry -Level 'INFO' -Message "Delta copy starting. Files queued: $($filesToCopy.Count)"

    foreach ($item in $filesToCopy) {

        # ── Read properties directly from the comparison result object ─────────
        # Compare-ZipFiles returns: FileName, FullPath, RelativePath, Action, Reason
        $fileName       = $item.FileName
        $sourceFullPath = $item.FullPath
        $relativePath   = $item.RelativePath
        $reason         = $item.Reason

        # ── Derive subfolder structure from the relative path ─────────────────
        $relativeDir = Split-Path -Path $relativePath -Parent

        # ── Derive the clean (undated) filename for baseline storage ──────────
        # Strips _YYYYMMDD or -YYYYMMDD suffix from the stem before extension
        $stem      = [System.IO.Path]::GetFileNameWithoutExtension($fileName) `
                         -replace '[_-]\d{8}$', ''
        $ext       = [System.IO.Path]::GetExtension($fileName)
        $cleanName = "$stem$ext"

        # ── Build destination path (keeps original dated filename) ────────────
        $destDir  = if ($relativeDir) {
                        Join-Path $DestinationFolder $relativeDir
                    } else {
                        $DestinationFolder
                    }
        $destPath = Join-Path $destDir $fileName

        # ── Build baseline path (uses clean undated filename) ─────────────────
        $baseDir      = if ($relativeDir) {
                            Join-Path $BaselineFolder $relativeDir
                        } else {
                            $BaselineFolder
                        }
        $baselinePath = Join-Path $baseDir $cleanName

        try {
            # ── Ensure destination directory exists ───────────────────────────
            if (-not (Test-Path -Path $destDir -PathType Container)) {
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
                Write-LogEntry -Level 'INFO' -Message "Created destination directory: $destDir"
            }

            # ── Copy to destination ───────────────────────────────────────────
            Copy-Item -Path $sourceFullPath -Destination $destPath -Force -ErrorAction Stop
            Write-LogEntry -Level 'INFO' -Message "Delivered [$reason] $fileName"
            Write-LogEntry -Level 'INFO' -Message "  Destination : $destPath"

            # ── Ensure baseline directory exists ──────────────────────────────
            if (-not (Test-Path -Path $baseDir -PathType Container)) {
                New-Item -ItemType Directory -Path $baseDir -Force | Out-Null
                Write-LogEntry -Level 'INFO' -Message "Created baseline directory: $baseDir"
            }

            # ── Update baseline with clean-named copy ─────────────────────────
            Copy-Item -Path $sourceFullPath -Destination $baselinePath -Force -ErrorAction Stop
            Write-LogEntry -Level 'INFO' -Message "  Baseline    : $baselinePath"
        }
        catch [System.IO.IOException] {
            $ioMsg = "IO error on '$fileName' (file may be locked): $_"
            Write-LogEntry -Level 'ERROR' -Message $ioMsg
        }
        catch [UnauthorizedAccessException] {
            $authMsg = "Access denied on '$fileName' - check folder permissions: $_"
            Write-LogEntry -Level 'ERROR' -Message $authMsg
        }
        catch {
            $genMsg = "Unexpected error on '$fileName': $_"
            Write-LogEntry -Level 'ERROR' -Message $genMsg
        }
    }

    Write-LogEntry -Level 'INFO' -Message "Delta copy phase complete."
}