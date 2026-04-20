# =============================================================================
# File    : Hashing.ps1
# Purpose : Compute a deterministic hash for a ZIP file.
#
#   ContentMode = $false  ->  Hash the ZIP container file directly (fast)
#   ContentMode = $true   ->  Hash every file INSIDE the ZIP, then hash
#                             the combined manifest (content-aware, slower)
# =============================================================================

Add-Type -AssemblyName 'System.IO.Compression.FileSystem'

function Get-ZipFileHash {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$ZipPath,

        [Parameter(Mandatory)]
        [bool]$ContentMode
    )

    if (-not (Test-Path -Path $ZipPath -PathType Leaf)) {
        Write-LogEntry -Level 'WARNING' -Message "Hash skipped - file not found: $ZipPath"
        return $null
    }

    try {
        if (-not $ContentMode) {

            # Fast mode: hash the ZIP container as a binary blob
            $result = Get-FileHash -Path $ZipPath -Algorithm SHA256
            return $result.Hash

        } else {

            # Content mode: hash individual entries inside the ZIP
            $archive = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)

            try {
                # Sort entries so the manifest is deterministic regardless of
                # the order files were added to the ZIP
                $entries = $archive.Entries |
                           Where-Object { $_.Length -gt 0 } |
                           Sort-Object { $_.FullName }

                $sha          = [System.Security.Cryptography.SHA256]::Create()
                $manifestLines = [System.Collections.Generic.List[string]]::new()

                foreach ($entry in $entries) {
                    $stream     = $entry.Open()
                    $entryBytes = $sha.ComputeHash($stream)
                    $stream.Dispose()
                    $entryHex   = [BitConverter]::ToString($entryBytes) -replace '-', ''
                    $manifestLines.Add("$entryHex  $($entry.FullName)")
                }

                $sha.Dispose()

                # Hash the text manifest itself to produce a single digest
                $manifestText  = $manifestLines -join "`n"
                $manifestBytes = [System.Text.Encoding]::UTF8.GetBytes($manifestText)
                $finalSha      = [System.Security.Cryptography.SHA256]::Create()
                $finalBytes    = $finalSha.ComputeHash($manifestBytes)
                $finalSha.Dispose()

                return ([BitConverter]::ToString($finalBytes) -replace '-', '')

            } finally {
                $archive.Dispose()
            }
        }
    }
    catch {
        $errMsg = "Hash computation failed for '$ZipPath': $($_.Exception.Message)"
        Write-LogEntry -Level 'WARNING' -Message $errMsg
        return $null
    }
}