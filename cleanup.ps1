# ================================
# Windows Cleanup Utility PRO+
# ================================

# --- Auto-elevate ---
if (-not ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {

    Start-Process powershell `
        -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" `
        -Verb RunAs
    exit
}

# --- Color output ---
function Write-Color {
    param($Text, $Color = "White")
    Write-Host $Text -ForegroundColor $Color
}

# --- Drive Selection ---
function Select-Drive {
    Write-Color "`nAvailable Drives:" "Cyan"

    Get-PSDrive -PSProvider FileSystem | ForEach-Object {
        $free = [math]::Round($_.Free / 1GB, 2)
        Write-Color "$($_.Name): ($free GB free)" "White"
    }

    do {
        $inputDrive = Read-Host "`nEnter drive letter (e.g., C)"

        if ([string]::IsNullOrWhiteSpace($inputDrive)) {
            Write-Color "❌ Please enter a drive letter." "Red"
            continue
        }

        $global:SelectedDrive = $inputDrive.ToUpper()
        $exists = Get-PSDrive -Name $SelectedDrive -ErrorAction SilentlyContinue

        if (-not $exists) {
            Write-Color "❌ Invalid drive. Try again." "Red"
        }

    } until ($exists)

    Write-Color "✔ Selected Drive: ${SelectedDrive}:" "Green"
}

# --- Disk Info (MB) ---
function Get-DiskSpace {
    $drive = Get-PSDrive -Name $SelectedDrive
    return [PSCustomObject]@{
        FreeMB  = [math]::Round($drive.Free / 1MB, 2)
        UsedMB  = [math]::Round($drive.Used / 1MB, 2)
        TotalMB = [math]::Round(($drive.Used + $drive.Free) / 1MB, 2)
    }
}

# --- Restore Point ---
function Create-RestorePoint {
    Write-Color "`n📌 Creating Restore Point..." "Cyan"

    try {
        Checkpoint-Computer -Description "Cleanup Restore Point" -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
        Write-Color "✅ Restore point created" "Green"
    } catch {
        Write-Color "⚠️ Restore point skipped (System Protection disabled)" "Yellow"
    }
}

# --- Safe Cleanup ---
function Safe-Cleanup {
    Write-Color "`n🧹 SAFE CLEANUP" "Cyan"

    try {
        Remove-Item "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
        Write-Color "✔ User temp cleaned" "Green"
    } catch {}

    try {
        Remove-Item "C:\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
        Write-Color "✔ Windows temp cleaned" "Green"
    } catch {}

    try {
        $driveTemp = "${SelectedDrive}:\Temp"
        if (Test-Path $driveTemp) {
            Remove-Item "$driveTemp\*" -Recurse -Force -ErrorAction SilentlyContinue
            Write-Color "✔ Drive temp cleaned (${SelectedDrive}:)" "Green"
        }
    } catch {}

    try {
        ipconfig /flushdns | Out-Null
        Write-Color "✔ DNS cache cleared" "Green"
    } catch {}

    try {
        Clear-RecycleBin -DriveLetter $SelectedDrive -Force -ErrorAction SilentlyContinue
        Write-Color "✔ Recycle Bin cleaned (${SelectedDrive}:)" "Green"
    } catch {
        Write-Color "⚠️ Recycle Bin cleanup partial" "Yellow"
    }

    try {
        net stop wuauserv 2>$null | Out-Null
        net stop bits 2>$null | Out-Null
        Remove-Item "C:\Windows\SoftwareDistribution\*" -Recurse -Force -ErrorAction SilentlyContinue
        net start wuauserv 2>$null | Out-Null
        net start bits 2>$null | Out-Null
        Write-Color "✔ Windows Update cache cleared" "Green"
    } catch {
        Write-Color "⚠️ Update cache cleanup partial" "Yellow"
    }
}

# --- Moderate Cleanup ---
function Moderate-Cleanup {
    Write-Color "`n⚙️ MODERATE CLEANUP" "Cyan"

    try {
        Dism.exe /online /Cleanup-Image /StartComponentCleanup | Out-Null
        Write-Color "✔ DISM cleanup done" "Green"
    } catch {}

    try {
        Remove-Item "C:\Windows\Prefetch\*" -Recurse -Force -ErrorAction SilentlyContinue
        Write-Color "✔ Prefetch cleaned" "Green"
    } catch {}

    try {
        Get-ChildItem "C:\Windows\Logs" -Recurse -ErrorAction SilentlyContinue |
        Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
        Write-Color "✔ Logs cleaned" "Green"
    } catch {}
}

# --- Aggressive Cleanup ---
function Aggressive-Cleanup {
    Write-Color "`n🔥 AGGRESSIVE CLEANUP" "Red"

    $confirm = Read-Host "⚠️ This removes update rollback ability. Continue? (y/n)"
    if ($confirm -ne "y") { return }

    try {
        Dism.exe /online /Cleanup-Image /StartComponentCleanup /ResetBase | Out-Null
        Write-Color "✔ ResetBase applied" "Green"
    } catch {}

    try {
        powercfg -h off
        Write-Color "✔ Hibernation disabled" "Green"
    } catch {}

    try {
        wevtutil el | ForEach-Object { wevtutil cl "$_" 2>$null }
        Write-Color "✔ Event logs cleared" "Green"
    } catch {}
}

# --- Run Cleanup ---
function Run-Cleanup {
    param($mode)

    Select-Drive
    Create-RestorePoint

    $before = Get-DiskSpace

    Write-Color "`n📊 BEFORE CLEANUP" "Cyan"
    Write-Color "Drive: ${SelectedDrive}:"
    Write-Color "Free: $($before.FreeMB) MB | Used: $($before.UsedMB) MB"

    Safe-Cleanup

    if ($mode -ge 2) { Moderate-Cleanup }
    if ($mode -ge 3) { Aggressive-Cleanup }

    $after = Get-DiskSpace
    $gain = [math]::Round($after.FreeMB - $before.FreeMB, 2)

    # Prevent negative values
    if ($gain -lt 0) {
        $gain = 0
    }

    Write-Color "`n📊 AFTER CLEANUP" "Cyan"
    Write-Color "Free: $($after.FreeMB) MB | Used: $($after.UsedMB) MB"

    Write-Color "`n💾 SPACE FREED: $gain MB" "Green"

    if ($gain -eq 0) {
        Write-Color "ℹ️ No significant space freed (already clean or minimal temp files)" "Yellow"
    }
}

# --- Menu ---
function Show-Menu {
    Clear-Host
    Write-Color "===============================" "Cyan"
    Write-Color " Windows Cleanup Utility PRO+ " "White"
    Write-Color "===============================" "Cyan"
    Write-Color "1. Safe" "Green"
    Write-Color "2. Moderate" "Yellow"
    Write-Color "3. Aggressive" "Red"
    Write-Color "4. Full" "Magenta"
    Write-Color "5. Exit" "Gray"
}

# --- Main ---
do {
    Show-Menu
    $choice = Read-Host "Select option"

    switch ($choice) {
        "1" { Run-Cleanup 1 }
        "2" { Run-Cleanup 2 }
        "3" { Run-Cleanup 3 }
        "4" { Run-Cleanup 3 }
        "5" { break }
        default { Write-Color "Invalid option" "Red" }
    }

    if ($choice -in @("1","2","3","4")) {
        $restart = Read-Host "`n🔄 Restart now? (y/n)"
        if ($restart -eq "y") { Restart-Computer }
    }

} while ($choice -ne "5")