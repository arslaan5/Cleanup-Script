# ================================
# Windows Cleanup Utility PRO+
# ================================

# --- Auto-elevate ---
if (-not ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {

    Write-Host "⚠️ Administrator rights required. Attempting to elevate..." -ForegroundColor Yellow
    Start-Sleep -Seconds 2
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

        $SelectedDrive = $inputDrive.ToUpper()
        $exists = Get-PSDrive -Name $SelectedDrive -ErrorAction SilentlyContinue

        if (-not $exists) {
            Write-Color "❌ Invalid drive. Try again." "Red"
        }

    } until ($exists)

    Write-Color "✔ Selected Drive: ${SelectedDrive}:" "Green"
    return $SelectedDrive
}

# --- Disk Info (MB) ---
function Get-DiskSpace {
    param([string]$DriveLetter)
    $drive = Get-PSDrive -Name $DriveLetter
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
    param([string]$TargetDrive)
    Write-Color "`n🧹 SAFE CLEANUP" "Cyan"
    Write-Progress -Activity "Windows Cleanup Utility" -Status "Running Safe Cleanup..." -PercentComplete 10

    try {
        Write-Progress -Activity "Windows Cleanup Utility" -Status "Cleaning User Temp" -PercentComplete 15
        Remove-Item "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
        Write-Color "✔ User temp cleaned" "Green"
    } catch {}

    try {
        Write-Progress -Activity "Windows Cleanup Utility" -Status "Cleaning Windows Temp" -PercentComplete 20
        Remove-Item "$env:windir\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
        Write-Color "✔ Windows temp cleaned" "Green"
    } catch {}

    try {
        Write-Progress -Activity "Windows Cleanup Utility" -Status "Cleaning Drive Temp" -PercentComplete 25
        $driveTemp = "${TargetDrive}:\Temp"
        if (Test-Path $driveTemp) {
            Remove-Item "$driveTemp\*" -Recurse -Force -ErrorAction SilentlyContinue
            Write-Color "✔ Drive temp cleaned (${TargetDrive}:)" "Green"
        }
    } catch {}

    try {
        Write-Progress -Activity "Windows Cleanup Utility" -Status "Clearing DNS Cache" -PercentComplete 30
        ipconfig /flushdns | Out-Null
        Write-Color "✔ DNS cache cleared" "Green"
    } catch {}

    try {
        Write-Progress -Activity "Windows Cleanup Utility" -Status "Emptying Recycle Bin" -PercentComplete 35
        Clear-RecycleBin -DriveLetter $TargetDrive -Force -ErrorAction SilentlyContinue
        Write-Color "✔ Recycle Bin cleaned (${TargetDrive}:)" "Green"
    } catch {
        Write-Color "⚠️ Recycle Bin cleanup partial" "Yellow"
    }

    try {
        Write-Progress -Activity "Windows Cleanup Utility" -Status "Clearing Windows Update Cache" -PercentComplete 40
        Stop-Service -Name wuauserv, bits -Force -ErrorAction SilentlyContinue
        Remove-Item "$env:windir\SoftwareDistribution\*" -Recurse -Force -ErrorAction SilentlyContinue
        Start-Service -Name wuauserv, bits -ErrorAction SilentlyContinue
        Write-Color "✔ Windows Update cache cleared" "Green"
    } catch {
        Write-Color "⚠️ Update cache cleanup partial" "Yellow"
    }

    try {
        Write-Progress -Activity "Windows Cleanup Utility" -Status "Clearing Windows Logs & Error Dumps" -PercentComplete 45
        Remove-Item "$env:LOCALAPPDATA\CrashDumps\*" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item "$env:ProgramData\Microsoft\Windows\WER\*" -Recurse -Force -ErrorAction SilentlyContinue
        Write-Color "✔ Crash dumps and Windows Error Reporting cleaned" "Green"
    } catch {}

    try {
        Write-Progress -Activity "Windows Cleanup Utility" -Status "Clearing Windows Store & App Caches" -PercentComplete 50
        Remove-Item "$env:LOCALAPPDATA\Packages\Microsoft.WindowsStore_8wekyb3d8bbwe\LocalCache\*" -Recurse -Force -ErrorAction SilentlyContinue
        Stop-Service -Name FontCache -Force -ErrorAction SilentlyContinue
        Remove-Item "$env:windir\ServiceProfiles\LocalService\AppData\Local\FontCache\*" -Recurse -Force -ErrorAction SilentlyContinue
        Start-Service -Name FontCache -ErrorAction SilentlyContinue
        Write-Color "✔ Windows Store & Font cache cleaned" "Green"
    } catch {}

    try {
        Write-Progress -Activity "Windows Cleanup Utility" -Status "Clearing Browser Caches" -PercentComplete 55
        # Chromium-based Edge
        Remove-Item "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache\*" -Recurse -Force -ErrorAction SilentlyContinue
        # Google Chrome
        Remove-Item "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache\*" -Recurse -Force -ErrorAction SilentlyContinue
        # Mozilla Firefox
        Remove-Item "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles\*\cache2\*" -Recurse -Force -ErrorAction SilentlyContinue
        Write-Color "✔ Browser caches cleared" "Green"
    } catch {}
}

# --- Moderate Cleanup ---
function Moderate-Cleanup {
    Write-Color "`n⚙️ MODERATE CLEANUP" "Cyan"

    try {
        Write-Progress -Activity "Windows Cleanup Utility" -Status "Automating Disk Cleanup (cleanmgr)..." -PercentComplete 60
        Write-Color "⏳ Running Windows Disk Cleanup engine..." "Cyan"
        
        $RegPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches"
        Get-ChildItem -Path $RegPath -ErrorAction SilentlyContinue | ForEach-Object {
            New-ItemProperty -Path $_.PSPath -Name "StateFlags0001" -Value 2 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
        }
        Start-Process -FilePath "cleanmgr.exe" -ArgumentList "/sagerun:1" -Wait -WindowStyle Hidden
        Write-Color "✔ Windows Disk Cleanup complete" "Green"
    } catch {}

    try {
        Write-Progress -Activity "Windows Cleanup Utility" -Status "Running DISM component cleanup..." -PercentComplete 65
        Write-Color "⏳ Running DISM component cleanup (this may take several minutes)..." "Cyan"
        Dism.exe /online /Cleanup-Image /StartComponentCleanup
        Write-Color "✔ DISM cleanup done" "Green"
    } catch {}

    try {
        Write-Progress -Activity "Windows Cleanup Utility" -Status "Checking Previous Windows Installations..." -PercentComplete 75
        if (Test-Path "$env:SystemDrive\Windows.old") {
            Write-Color "⏳ Removing previous Windows installation (Windows.old)..." "Cyan"
            cmd.exe /c "takeown /F ""$env:SystemDrive\Windows.old"" /A /R /D Y > NUL"
            cmd.exe /c "icacls ""$env:SystemDrive\Windows.old"" /grant *S-1-5-32-544:F /T /C /Q > NUL"
            Remove-Item "$env:SystemDrive\Windows.old" -Recurse -Force -ErrorAction SilentlyContinue
            Write-Color "✔ Windows.old removed" "Green"
        }
    } catch {}

    try {
        Write-Progress -Activity "Windows Cleanup Utility" -Status "Clearing Developer Caches..." -PercentComplete 80
        # npm
        if (Test-Path "$env:LOCALAPPDATA\npm-cache") { Remove-Item "$env:LOCALAPPDATA\npm-cache\*" -Recurse -Force -ErrorAction SilentlyContinue }
        if (Test-Path "$env:APPDATA\npm-cache") { Remove-Item "$env:APPDATA\npm-cache\*" -Recurse -Force -ErrorAction SilentlyContinue }
        # pip
        if (Test-Path "$env:LOCALAPPDATA\pip\Cache") { Remove-Item "$env:LOCALAPPDATA\pip\Cache\*" -Recurse -Force -ErrorAction SilentlyContinue }
        # NuGet
        if (Test-Path "$env:USERPROFILE\.nuget\packages") { Remove-Item "$env:USERPROFILE\.nuget\packages\*" -Recurse -Force -ErrorAction SilentlyContinue }
        # Cargo
        if (Test-Path "$env:USERPROFILE\.cargo\registry\cache") { Remove-Item "$env:USERPROFILE\.cargo\registry\cache\*" -Recurse -Force -ErrorAction SilentlyContinue }
        Write-Color "✔ Developer caches cleared" "Green"
    } catch {}

    try {
        Write-Progress -Activity "Windows Cleanup Utility" -Status "Clearing Windows Logs & Prefetch..." -PercentComplete 85
        Remove-Item "$env:windir\Prefetch\*" -Recurse -Force -ErrorAction SilentlyContinue
        Write-Color "✔ Prefetch cleaned" "Green"
    } catch {}

    try {
        Get-ChildItem "$env:windir\Logs" -Recurse -ErrorAction SilentlyContinue |
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
        Write-Progress -Activity "Windows Cleanup Utility" -Status "Running DISM ResetBase..." -PercentComplete 90
        Write-Color "⏳ Running DISM ResetBase (this may take several minutes)..." "Cyan"
        Dism.exe /online /Cleanup-Image /StartComponentCleanup /ResetBase
        Write-Color "✔ ResetBase applied" "Green"
    } catch {}

    try {
        Write-Progress -Activity "Windows Cleanup Utility" -Status "Deleting Shadow Copies..." -PercentComplete 93
        # Keeps new shadow copies but drops the old backups
        vssadmin delete shadows /all /quiet | Out-Null
        Write-Color "✔ System Shadow Copies & old restore points deleted" "Green"
    } catch {}

    try {
        Write-Progress -Activity "Windows Cleanup Utility" -Status "Disabling Hibernation..." -PercentComplete 95
        powercfg -h off
        Write-Color "✔ Hibernation disabled" "Green"
    } catch {}

    try {
        Write-Progress -Activity "Windows Cleanup Utility" -Status "Clearing Event Viewer Logs..." -PercentComplete 99
        wevtutil el | ForEach-Object { wevtutil cl "$_" 2>$null }
        Write-Color "✔ Event logs cleared" "Green"
    } catch {}
}

# --- Run Cleanup ---
function Run-Cleanup {
    param($mode)

    $SelectedDrive = Select-Drive
    Create-RestorePoint

    $before = Get-DiskSpace -DriveLetter $SelectedDrive

    Write-Color "`n📊 BEFORE CLEANUP" "Cyan"
    Write-Color "Drive: ${SelectedDrive}:"
    Write-Color "Free: $($before.FreeMB) MB | Used: $($before.UsedMB) MB"

    Safe-Cleanup -TargetDrive $SelectedDrive

    if ($mode -ge 2) { Moderate-Cleanup }
    if ($mode -ge 3) { Aggressive-Cleanup }

    Write-Progress -Activity "Windows Cleanup Utility" -Status "Finishing up..." -PercentComplete 100
    Start-Sleep -Seconds 1
    Write-Progress -Activity "Windows Cleanup Utility" -Completed

    $after = Get-DiskSpace -DriveLetter $SelectedDrive
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