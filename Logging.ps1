# =============================================================================
# File    : Logging.ps1
# Purpose : Initialise the session log file and expose three public functions:
#
#   Initialize-Log   - create the log file and write the session header
#   Write-LogEntry   - append a timestamped entry to the log
#   Write-LogSummary - write the final statistics block
#
# Notes   : Uses Out-File -Append throughout to avoid the PS 5.1
#           Add-Content -Encoding UTF8 stream bug.
# =============================================================================

$Script:LogFilePath  = $null
$Script:CountInfo    = 0
$Script:CountWarning = 0
$Script:CountError   = 0
$Script:StartTime    = $null

# ── Initialize-Log ────────────────────────────────────────────────────────────
function Initialize-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LogPath
    )

    $Script:LogFilePath  = $LogPath
    $Script:CountInfo    = 0
    $Script:CountWarning = 0
    $Script:CountError   = 0
    $Script:StartTime    = Get-Date

    # Ensure the log directory exists
    $logDir = Split-Path -Path $LogPath -Parent
    if (-not (Test-Path -Path $logDir -PathType Container)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }

    $separator = '=' * 80
    $header    = @(
        $separator
        '  Accurate Delta ZIP Copy Automation - Session Log'
        "  Started  : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        "  Host     : $env:COMPUTERNAME"
        "  User     : $env:USERNAME"
        $separator
    )

    # Create/overwrite the log file with the header
    $header | Out-File -FilePath $Script:LogFilePath -Encoding UTF8 -Force

    # Mirror to console
    $header | ForEach-Object { Write-Host $_ -ForegroundColor Cyan }
}

# ── Write-LogEntry ────────────────────────────────────────────────────────────
function Write-LogEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('INFO','WARNING','ERROR','DEBUG')]
        [string]$Level,

        [Parameter(Mandatory)]
        [string]$Message
    )

    switch ($Level) {
        'INFO'    { $Script:CountInfo++    }
        'WARNING' { $Script:CountWarning++ }
        'ERROR'   { $Script:CountError++   }
        'DEBUG'   { $Script:CountInfo++    }
    }

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line      = "[$timestamp] [$Level] $Message"

    $line | Out-File -FilePath $Script:LogFilePath -Append -Encoding UTF8

    $colour = switch ($Level) {
        'INFO'    { 'White'  }
        'WARNING' { 'Yellow' }
        'ERROR'   { 'Red'    }
        'DEBUG'   { 'Gray'   }
    }
    Write-Host $line -ForegroundColor $colour
}

# ── Write-LogSummary ──────────────────────────────────────────────────────────
function Write-LogSummary {
    [CmdletBinding()]
    param()

    $endTime  = Get-Date
    $duration = $endTime - $Script:StartTime

    $separator = '=' * 80
    $summary   = @(
        $separator
        '  Session Summary'
        "  Finished  : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        "  Duration  : $([math]::Round($duration.TotalSeconds, 1)) second(s)"
        "  INFO      : $Script:CountInfo"
        "  WARNING   : $Script:CountWarning"
        "  ERROR     : $Script:CountError"
        $separator
    )

    $summary | Out-File -FilePath $Script:LogFilePath -Append -Encoding UTF8

    $colour = if     ($Script:CountError   -gt 0) { 'Red'    }
              elseif ($Script:CountWarning -gt 0) { 'Yellow' }
              else                                { 'Green'  }

    $summary | ForEach-Object { Write-Host $_ -ForegroundColor $colour }

    Write-Host "`nLog saved to: $Script:LogFilePath" -ForegroundColor Cyan
}