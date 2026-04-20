# Accurate Delta ZIP Copy Automation

A PowerShell-based automation tool that detects and copies **only changed ZIP
files** from a source folder to a shared destination — using **SHA-256 content
hashing**, not file timestamps.

---

## Table of Contents

1. [Overview](#overview)
2. [How It Works](#how-it-works)
3. [Project Structure](#project-structure)
4. [Prerequisites](#prerequisites)
5. [Setup](#setup)
6. [Configuration](#configuration)
7. [How to Run](#how-to-run)
8. [Parameter Reference](#parameter-reference)
9. [The Clean Name Concept](#the-clean-name-concept)
10. [Hashing Modes](#hashing-modes)
11. [Example Log Output](#example-log-output)
12. [Test Cases](#test-cases)
13. [Scheduling via Task Scheduler](#scheduling-via-task-scheduler)
14. [Error Handling](#error-handling)
15. [Troubleshooting](#troubleshooting)

---

## Overview

Traditional file-sync tools rely on **timestamps** to detect changes.
This is unreliable — a file can be re-copied, re-zipped, or touched without
its content actually changing, causing unnecessary overwrites.

This tool solves that by computing a **SHA-256 hash fingerprint** of every
ZIP file. Only files whose fingerprint has genuinely changed since the last
run are copied to the destination.

### What it does

| Scenario | Detection | Result |
|---|---|---|
| ZIP file is brand new | Not found in baseline | **COPY** |
| ZIP file content has changed | Hash mismatch with baseline | **COPY** |
| ZIP file is identical to last run | Hash matches baseline | **SKIP** |

---

## How It Works

The tool runs a five-stage pipeline on every execution:

```
┌─────────────────────────────────────────────────────────────────┐
│                     FIVE-STAGE PIPELINE                         │
├──────────┬──────────────────────────────────────────────────────┤
│ Stage 1  │  SCANNING     Recursively find all .zip files        │
│          │               in the source folder                    │
├──────────┼──────────────────────────────────────────────────────┤
│ Stage 2  │  HASHING      Compute SHA-256 fingerprint for        │
│          │               each source ZIP (streaming — safe      │
│          │               for large files)                        │
├──────────┼──────────────────────────────────────────────────────┤
│ Stage 3  │  COMPARISON   Match source against baseline.         │
│          │               Assign status: NEW / MATCH / MISMATCH  │
├──────────┼──────────────────────────────────────────────────────┤
│ Stage 4  │  DELTA COPY   Copy only NEW and MISMATCH files       │
│          │               to destination and update baseline     │
├──────────┼──────────────────────────────────────────────────────┤
│ Stage 5  │  LOGGING      Write timestamped summary log          │
│          │               with counts and any errors             │
└──────────┴──────────────────────────────────────────────────────┘
```

### Folder roles

```
Source      →  Where incoming ZIP files land (read-only access needed)
Destination →  Where changed ZIPs are delivered  (original dated filenames)
Baseline    →  Internal reference store           (clean filenames, no dates)
Logs        →  Session log files
```

The **Baseline** is the key to accurate delta detection. It stores the last
known good copy of every file using a clean (date-stripped) name. On each run,
the source is compared against baseline — not against destination — so dated
filenames never cause false "new file" detections.

---

## Project Structure

```
ACCURATE_DELTA_ZIP_COPY_A/
│
├── DeltaChanges.ps1       ← Entry point / orchestrator  (run this)
├── Comparison.ps1         ← Stage 3: hash comparison logic
├── CopyPaste.ps1          ← Stage 4: file copy operations
├── Hashing.ps1            ← Stage 2: SHA-256 hashing engine
├── Logging.ps1            ← Stage 5: logging engine
├── Scanning.ps1           ← Stage 1: recursive ZIP discovery
│
├── config.json            ← Default configuration (edit before first run)
├── README.md              ← This file
│
├── Baseline\              ← Auto-created on first run
├── Logs\                  ← Auto-created on first run
│
└── Tests\
    └── Run-Tests.ps1      ← Automated test suite
```

---

## Prerequisites

| Requirement | Minimum Version | Notes |
|---|---|---|
| Operating System | Windows Server 2019 | Also works on Windows 10/11 |
| PowerShell | 5.1 | Pre-installed on Windows Server 2019 |
| .NET Framework | 4.5+ | Required for ZIP assembly |
| Permissions | Read on Source | Write on Destination, Baseline, Logs |

### Verify your PowerShell version

```powershell
$PSVersionTable.PSVersion
```

---

## Setup

**Step 1 — Clone or copy the project folder to your machine.**

```
C:\ACCURATE_DELTA_ZIP_COPY_A\
```

**Step 2 — Open `config.json` and set your folder paths.**

```json
{
    "SourceFolder"      : "C:\\Incoming\\ZipFiles",
    "DestinationFolder" : "\\\\SERVER01\\SharedDrive\\Delivered",
    "BaselineFolder"    : "C:\\ACCURATE_DELTA_ZIP_COPY_A\\Baseline",
    "LogFolder"         : "C:\\ACCURATE_DELTA_ZIP_COPY_A\\Logs",
    "ContentMode"       : false
}
```

**Step 3 — Set PowerShell execution policy if needed (run as Administrator).**

```powershell
Set-ExecutionPolicy RemoteSigned -Scope LocalMachine
```

**Step 4 — Run the script.**

```powershell
cd C:\ACCURATE_DELTA_ZIP_COPY_A
.\DeltaChanges.ps1
```

---

## Configuration

All settings can be provided via `config.json`, via command-line parameters,
or a mix of both. **Command-line parameters always override `config.json`.**

### config.json fields

| Field | Required | Description |
|---|---|---|
| `SourceFolder` | **Yes** | Root folder containing incoming ZIP files |
| `DestinationFolder` | **Yes** | Target share or folder where ZIPs are delivered |
| `BaselineFolder` | No | Reference store. Default: `.\Baseline` |
| `LogFolder` | No | Log output folder. Default: `.\Logs` |
| `ContentMode` | No | `true` = hash ZIP entries individually. Default: `false` |

---

## How to Run

### Option 1 — Use config.json (recommended for scheduled tasks)

```powershell
.\DeltaChanges.ps1
```

### Option 2 — Pass all parameters explicitly

```powershell
.\DeltaChanges.ps1 `
    -SourceFolder      "C:\Incoming\ZipFiles" `
    -DestinationFolder "\\SERVER01\SharedDrive\Delivered" `
    -BaselineFolder    "C:\Baseline" `
    -LogFolder         "C:\Logs"
```

### Option 3 — Override a single config.json value

```powershell
# Use everything from config.json but override the source folder
.\DeltaChanges.ps1 -SourceFolder "D:\NewSource"
```

### Option 4 — Use a custom config file

```powershell
.\DeltaChanges.ps1 -ConfigFile "D:\MyCustomConfig.json"
```

### Option 5 — Enable content-mode hashing

```powershell
.\DeltaChanges.ps1 -ContentMode
```

> Use content mode only when ZIP archives are re-compressed with different
> tools or settings. It is slower but ignores ZIP metadata differences.

### Option 6 — Run the test suite

```powershell
.\Tests\Run-Tests.ps1
```

---

## Parameter Reference

| Parameter | Type | Required | Default | Description |
|---|---|---|---|---|
| `-SourceFolder` | String | Yes* | config.json | Root folder to scan for ZIP files |
| `-DestinationFolder` | String | Yes* | config.json | Folder where changed ZIPs are delivered |
| `-BaselineFolder` | String | No | `.\Baseline` | Internal reference store for hashes |
| `-LogFolder` | String | No | `.\Logs` | Where `.log` files are written |
| `-ContentMode` | Switch | No | `false` | Hash ZIP entries instead of raw binary |
| `-ConfigFile` | String | No | `.\config.json` | Path to an alternative config file |

\* Required unless defined in `config.json`.

---

## The Clean Name Concept

Source files often carry **date or version stamps** in their filenames:

```
ProductA_20260420.zip
ProductA_20260421.zip   ← same product, next day delivery
```

Without clean names, the system would treat these as two completely different
files — both marked NEW — and copy both even if the content never changed.

The tool strips known suffix patterns to derive a **canonical clean name**
used only inside the Baseline folder for comparison:

| Source Filename | Clean Baseline Name |
|---|---|
| `ProductA_20260420.zip` | `ProductA.zip` |
| `Report_2026-04-20.zip` | `Report.zip` |
| `Build_20260420143000.zip` | `Build.zip` |
| `Library_v2.3.zip` | `Library.zip` |
| `Export_202604.zip` | `Export.zip` |

**Patterns stripped:**

```
_YYYYMMDD          →  _20260420
_YYYY-MM-DD        →  _2026-04-20
_YYYYMMDDHHmmss    →  _20260420143000
_YYYY-MM-DDTHHmmss →  _2026-04-20T143000
_YYYYMM            →  _202604
_vN / _vN.N        →  _v1  _v2.3  _v1.0.0
```

The **destination** always receives the original dated filename (audit trail).
The **baseline** stores only the clean name (comparison reference).

---

## Hashing Modes

### Whole-File Mode (default)

Reads the raw binary bytes of the ZIP file and computes one SHA-256 hash.

- **Fast** — handles multi-GB files via streaming (no full RAM load)
- **Recommended** for most use cases
- Sensitive to ZIP metadata changes (re-compression changes the hash)

### Content Mode (`-ContentMode`)

Opens the ZIP archive, iterates every internal entry in sorted order, and
hashes the **logical content** of each entry together with its name.

- **Slower** — reads every file inside every ZIP
- **Metadata-independent** — same logical content always produces the same hash
  even if the ZIP was rebuilt with a different tool or compression level
- Use when the same data is regularly re-zipped by different systems

---

## Example Log Output

```
================================================================================
  Accurate Delta ZIP Copy Automation - Session Log
  Started  : 2026-04-20 09:15:01
  Host     : WINSERVER01
  User     : svc_automation
================================================================================
[2026-04-20 09:15:01] [INFO] Source Folder      : C:\Incoming\ZipFiles
[2026-04-20 09:15:01] [INFO] Destination Folder : \\SERVER01\SharedDrive\Delivered
[2026-04-20 09:15:01] [INFO] Baseline Folder    : C:\Baseline
[2026-04-20 09:15:01] [INFO] Log File           : C:\Logs\DeltaZipCopy_20260420_091501.log
[2026-04-20 09:15:01] [INFO] Content Mode       : False
[2026-04-20 09:15:01] [INFO] ===== STAGE 1: SCANNING =====
[2026-04-20 09:15:01] [INFO] Scanning source folder recursively: C:\Incoming\ZipFiles
[2026-04-20 09:15:01] [DEBUG] Found: ProductA_20260420.zip (12.4 MB)
[2026-04-20 09:15:01] [DEBUG] Found: ProductB_20260420.zip (8.1 MB)
[2026-04-20 09:15:01] [DEBUG] Found: SubFolder\ReportC_20260420.zip (2.3 MB)
[2026-04-20 09:15:01] [INFO] Scan complete. Total ZIP files found: 3
[2026-04-20 09:15:01] [INFO] ===== STAGE 2+3: HASHING & COMPARISON =====
[2026-04-20 09:15:01] [INFO] Comparison starting. Baseline root: C:\Baseline
[2026-04-20 09:15:01] [INFO] Evaluating: ProductA_20260420.zip
[2026-04-20 09:15:02] [DEBUG] Whole-file hash computed: 3A7F91BC...
[2026-04-20 09:15:02] [INFO] Status: NEW — no baseline entry found. Action: COPY
            Path: C:\Baseline\ProductA.zip
[2026-04-20 09:15:02] [INFO] Evaluating: ProductB_20260420.zip
[2026-04-20 09:15:03] [DEBUG] Whole-file hash computed: D84E22FA...
[2026-04-20 09:15:03] [INFO] Status: MISMATCH — content changed. Action: COPY
            Path: C:\Incoming\ZipFiles\ProductB_20260420.zip
[2026-04-20 09:15:03] [INFO] Evaluating: SubFolder\ReportC_20260420.zip
[2026-04-20 09:15:03] [DEBUG] Whole-file hash computed: 9C1B44DE...
[2026-04-20 09:15:03] [SKIP] Status: MATCH — hashes identical. Action: SKIP
            Path: C:\Incoming\ZipFiles\SubFolder\ReportC_20260420.zip
[2026-04-20 09:15:03] [INFO] Comparison complete. To copy: 2 | To skip: 1
[2026-04-20 09:15:03] [INFO] ===== STAGE 4: DELTA COPY =====
[2026-04-20 09:15:03] [INFO] Delta copy starting. Files queued: 2
[2026-04-20 09:15:03] [INFO] Created destination directory: \\SERVER01\SharedDrive\Delivered
[2026-04-20 09:15:04] [COPY] Delivered to destination [NEW]
            Path: \\SERVER01\SharedDrive\Delivered\ProductA_20260420.zip
[2026-04-20 09:15:04] [INFO] Baseline updated: ProductA.zip
            Path: C:\Baseline\ProductA.zip
[2026-04-20 09:15:05] [COPY] Delivered to destination [MISMATCH]
            Path: \\SERVER01\SharedDrive\Delivered\ProductB_20260420.zip
[2026-04-20 09:15:05] [INFO] Baseline updated: ProductB.zip
            Path: C:\Baseline\ProductB.zip
[2026-04-20 09:15:05] [INFO] Delta copy phase complete.
[2026-04-20 09:15:05] [INFO] ===== STAGE 5: SUMMARY =====

================================================================================
  SESSION SUMMARY
  Finished  : 2026-04-20 09:15:05
  -----------------------------------------------------------
  Files Copied  (NEW / MISMATCH) : 2
  Files Skipped (MATCH)          : 1
  Errors Encountered             : 0
================================================================================
```

---

## Test Cases

Run the automated test suite to verify everything works on your machine:

```powershell
.\Tests\Run-Tests.ps1
```

### TC-01 — New ZIP Detected

**Setup:**
- `Source\ProductA_20260420.zip` exists
- Baseline is empty (first run)

**Expected result:**

```
[PASS] TC-01: Status is NEW
[PASS] TC-01: Action is COPY
[PASS] TC-01: File delivered to destination
[PASS] TC-01: Baseline created (clean name)
```

**What happens:**
The comparison module finds no matching entry in the baseline folder.
Status is set to `NEW`. The file is copied to destination with its original
name, and a clean-named copy is written to baseline for future comparisons.

---

### TC-02 — Changed ZIP Detected

**Setup:**
- `Source\ProductA_20260420.zip` contains new content
- `Baseline\ProductA.zip` contains old content from a previous run

**Expected result:**

```
[PASS] TC-02: Status is MISMATCH
[PASS] TC-02: Action is COPY
[PASS] TC-02: Destination updated
[PASS] TC-02: Baseline updated
[PASS] TC-02: Baseline hash matches source hash
```

**What happens:**
The hashes differ between source and baseline. Status is set to `MISMATCH`.
The file is overwritten in destination and baseline is updated so the next
run sees the latest version as the reference.

---

### TC-03 — Unchanged ZIP Skipped

**Setup:**
- `Source\ProductA_20260420.zip` content is identical to `Baseline\ProductA.zip`

**Expected result:**

```
[PASS] TC-03: Status is MATCH
[PASS] TC-03: Action is SKIP
[PASS] TC-03: Destination NOT touched
```

**What happens:**
The hashes are identical. Status is set to `MATCH`. No copy is performed.
The destination file is not modified. The baseline is not modified.
The log records one SKIP entry.

---

### Expected test suite output

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 TC-01 : New ZIP Detection
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  [PASS] TC-01: Status is NEW
  [PASS] TC-01: Action is COPY
  [PASS] TC-01: File delivered to destination
  [PASS] TC-01: Baseline created (clean name)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 TC-02 : Changed ZIP Detection
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  [PASS] TC-02: Status is MISMATCH
  [PASS] TC-02: Action is COPY
  [PASS] TC-02: Destination updated
  [PASS] TC-02: Baseline updated
  [PASS] TC-02: Baseline hash matches source hash

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 TC-03 : Unchanged ZIP Skip
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  [PASS] TC-03: Status is MATCH
  [PASS] TC-03: Action is SKIP
  [PASS] TC-03: Destination NOT touched

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 TEST RESULTS
 PASSED : 11
 FAILED : 0
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## Scheduling via Task Scheduler

Run the tool automatically on a daily schedule (run as Administrator):

```powershell$action = New-ScheduledTaskAction `
    -Execute  'powershell.exe' `
    -Argument '-NonInteractive -ExecutionPolicy Bypass -File "C:\ACCURATE_DELTA_ZIP_COPY_A\DeltaChanges.ps1"'

$trigger = New-ScheduledTaskTrigger -Daily -At '02:00AM'$settings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit (New-TimeSpan -Hours 2) `
    -RestartCount 1 `
    -RestartInterval (New-TimeSpan -Minutes 30)

Register-ScheduledTask `
    -TaskName 'DeltaZipCopy_Daily' `
    -Action   $action `
    -Trigger  $trigger `
    -Settings $settings `
    -RunLevel Highest `
    -Description 'Daily delta ZIP copy automation'
```

---

## Error Handling

| Error Type | How It Is Handled |
|---|---|
| Source folder missing | Logged as ERROR, pipeline exits cleanly |
| File locked by another process | Logged as ERROR, script continues with next file |
| Access denied on destination | Logged as ERROR, script continues with next file |
| ZIP file corrupt / unreadable | Hash returns null, file logged as ERROR and skipped |
| config.json missing or malformed | Warning shown, CLI parameters used instead |
| Destination folder missing | Auto-created before copy |
| Baseline folder missing | Auto-created before first baseline write |
| Unhandled pipeline exception | Caught in `finally` block — summary log always written |

---

## Troubleshooting

**Script does not run — execution policy error**

```powershell
Set-ExecutionPolicy RemoteSigned -Scope LocalMachine
```

**All files are showing as NEW on every run**

The Baseline folder may have been deleted or is pointing to the wrong path.
Check `BaselineFolder` in `config.json`. The baseline must persist between runs.

**Files with the same content but different names keep being copied**

This is expected if the clean-name stripping does not match your filename
pattern. Open `Comparison.ps1` and add your custom suffix pattern to the
`$patterns` array inside `Get-CleanZipName`.

**Large ZIPs are very slow in ContentMode**

Switch back to whole-file mode (`"ContentMode": false` in config.json).
Content mode reads every file inside every ZIP — it is significantly slower
for large or deeply nested archives.

**Log files are growing too large**

Each run creates a new timestamped log file. Set up a separate scheduled task
or add a cleanup step to delete logs older than 30 days:

```powershell
Get-ChildItem -Path "C:\Logs" -Filter "*.log" |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } |
    Remove-Item -Force
```

---

## Module Quick Reference

| File | Purpose | Key Function |
|---|---|---|
| `DeltaChanges.ps1` | Entry point / pipeline orchestrator | — |
| `Logging.ps1` | Write timestamped log entries | `Initialize-Log` `Write-LogEntry` `Write-LogSummary` |
| `Scanning.ps1` | Recursive ZIP file discovery | `Get-SourceZipFiles` |
| `Hashing.ps1` | SHA-256 fingerprinting | `Get-ZipFileHash` |
| `Comparison.ps1` | Baseline comparison, status assignment | `Compare-ZipFiles` `Get-CleanZipName` |
| `CopyPaste.ps1` | Physical file copy to destination + baseline | `Invoke-DeltaCopy` |

---

*Accurate Delta ZIP Copy Automation — built for Windows Server 2019, PowerShell 5.1+*