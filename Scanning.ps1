# =============================================================================
# File    : Scanning.ps1
# Purpose : Recursively crawl the source folder and build a structured list
#           of every .zip file found.
#
#           Each list entry carries enough metadata (relative path, size, etc.)
#           for every downstream module to work without re-querying the disk.
#
# Exports : Get-SourceZipFiles
# =============================================================================

# ------------------------------------------------------------------------------
# Get-SourceZipFiles
#   Returns [PSCustomObject[]] — one object per ZIP found.
#
#   Object properties
#   ─────────────────
#   .FullPath      Absolute path            C:\Source\SubA\Report_20260420.zip
#   .RelativePath  Path relative to root    SubA\Report_20260420.zip
#   .FileName      Bare filename            Report_20260420.zip
#   .RelativeDir   Relative directory only  SubA   (empty string if at root)
#   .SizeBytes     File size in bytes
#   .LastWriteUtc  Last-write time (UTC)
# ------------------------------------------------------------------------------
function Get-SourceZipFiles {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        # Root of the source tree to scan — must be an existing directory.
        [Parameter(Mandatory = $true)]
        [string]$SourceFolder
    )

    # ── Guard ─────────────────────────────────────────────────────────────────
    if (-not (Test-Path -Path $SourceFolder -PathType Container)) {
        Write-LogEntry -Level 'ERROR' `
            -Message "Source folder does not exist. Scanning aborted." `
            -FilePath $SourceFolder
        return @()
    }

    Write-LogEntry -Level 'INFO' `
        -Message "Scanning source folder recursively: $SourceFolder"

    # ── Recursive crawl ───────────────────────────────────────────────────────
    # -ErrorAction SilentlyContinue skips folders that cannot be read
    # (e.g. access-denied subdirectories) without stopping the whole scan.
    $zipFiles = Get-ChildItem `
                    -Path        $SourceFolder `
                    -Filter      '*.zip' `
                    -Recurse `
                    -File `
                    -ErrorAction SilentlyContinue

    if ($null -eq $zipFiles -or $zipFiles.Count -eq 0) {
        Write-LogEntry -Level 'INFO' `
            -Message "No .zip files found in source folder."
        return @()
    }

    # ── Build structured result list ──────────────────────────────────────────
    $results = foreach ($file in $zipFiles) {

        # Strip the source root prefix to obtain a portable relative path.
        # TrimStart('\') removes any leading-backslash artifact.
        $relativePath = $file.FullName.Substring($SourceFolder.Length).TrimStart('\')
        $relativeDir  = Split-Path -Path $relativePath -Parent

        [PSCustomObject]@{
            FullPath     = $file.FullName
            RelativePath = $relativePath
            FileName     = $file.Name
            RelativeDir  = $relativeDir      # Empty string when file sits at root.
            SizeBytes    = $file.Length
            LastWriteUtc = $file.LastWriteTimeUtc
        }

        Write-LogEntry -Level 'DEBUG' `
            -Message "Found: $relativePath ($([math]::Round($file.Length / 1MB, 2)) MB)"
    }

    Write-LogEntry -Level 'INFO' `
        -Message "Scan complete. Total ZIP files found: $($results.Count)"

    return $results
}