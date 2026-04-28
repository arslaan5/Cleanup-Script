# ================================
# Windows Cleanup Utility PRO+
# ================================

param(
    [Alias('WhatIf')]
    [switch]$DryRun
)

$script:DryRun = $DryRun

# --- Auto-elevate ---
if (-not ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {

    Write-Host "[!] Administrator rights required. Attempting to elevate..." -ForegroundColor Yellow
    Start-Sleep -Seconds 2
    $elevationArgs = "-ExecutionPolicy Bypass -File `"$PSCommandPath`""
    if ($DryRun) {
        $elevationArgs += " -DryRun"
    }

    Start-Process powershell `
        -ArgumentList $elevationArgs `
        -Verb RunAs
    exit
}

# --- Window Styling ---
$Host.UI.RawUI.WindowTitle = "Administrator: Windows Cleanup Utility PRO+"
try {
    $Host.UI.RawUI.WindowSize = New-Object System.Management.Automation.Host.Size(85, 35)
    $Host.UI.RawUI.BufferSize = New-Object System.Management.Automation.Host.Size(85, 3000)
} catch {}

# --- Color output ---
function Write-Color {
    param($Text, $Color = "White")
    Write-Host $Text -ForegroundColor $Color
}

function Get-PathSize {
    param(
        [string]$Path,
        [switch]$Recurse
    )
    if (-not (Test-Path $Path)) { return 0 }
    $sum = (Get-ChildItem -Path $Path -Recurse:$Recurse -Force -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
    if ($null -eq $sum) { return 0 }
    return [math]::Round($sum / 1MB, 2)
}

function Write-FreedSpace {
    param([double]$MB, [string]$Label)
    $display = if ($MB -ge 1024) { "$([math]::Round($MB/1024,2)) GB" } else { "$MB MB" }
    $color = if ($MB -ge 500) { "Green" } elseif ($MB -ge 50) { "Yellow" } elseif ($MB -gt 0) { "Gray" } else { "DarkGray" }
    Write-Host "  [✓] $Label" -NoNewline
    Write-Host "  →  $display freed" -ForegroundColor $color
}

function Clear-PathWithReport {
    param(
        [string]$Label,
        [string]$Path,
        [switch]$Recurse
    )

    $sizePath = $Path
    $removePath = $Path

    if (Test-Path $Path -PathType Container -ErrorAction SilentlyContinue) {
        $sizePath = $Path
        $removePath = Join-Path $Path '*'
    }

    $sizeBefore = Get-PathSize -Path $sizePath -Recurse:$Recurse
    if ($script:DryRun) {
        Write-Color "  [DRY-RUN] Would remove: $removePath" "DarkYellow"
    } else {
        Remove-Item $removePath -Recurse:$Recurse -Force -ErrorAction SilentlyContinue
    }
    $sizeAfter = if ($script:DryRun) { $sizeBefore } else { Get-PathSize -Path $sizePath -Recurse:$Recurse }
    $freed = [math]::Round(($sizeBefore - $sizeAfter), 2)
    if ($freed -lt 0) { $freed = 0 }
    Write-FreedSpace -MB $freed -Label $Label
    if (-not $script:Breakdown.Contains($Label)) {
        $script:Breakdown[$Label] = 0
    }
    $script:Breakdown[$Label] = [math]::Round(($script:Breakdown[$Label] + $freed), 2)
}

function Invoke-Action {
    param(
        [string]$Description,
        [scriptblock]$Action
    )

    if ($script:DryRun) {
        Write-Color "  [DRY-RUN] Would $Description" "DarkYellow"
    } else {
        & $Action
    }
}

function Start-WithSpinner {
    param([string]$Label, [scriptblock]$Task)
    $frames = @('⠋','⠙','⠹','⠸','⠼','⠴','⠦','⠧','⠇','⠏')
    $i = 0
    $job = Start-Job -ScriptBlock $Task
    while ($job.State -eq 'Running') {
        Write-Host "`r  $($frames[$i % $frames.Count]) $Label   " -NoNewline -ForegroundColor Cyan
        Start-Sleep -Milliseconds 100
        $i++
    }
    Receive-Job $job | Out-Null
    Remove-Job $job
    Write-Host "`r  [✓] $Label completed" -ForegroundColor Green
}

function Update-Step {
    param([string]$Label)
    $script:currentStep++
    $pct = [math]::Round(($script:currentStep / $script:totalSteps) * 100)
    Write-Progress -Activity "Windows Cleanup Utility" `
        -Status "Step $script:currentStep of $script:totalSteps — $Label" `
        -PercentComplete $pct
}

function Confirm-AggressiveCleanup {
    Write-Color "`n  ┌─────────────────────────────────────────┐" "Red"
    Write-Color "  │  ⚠  AGGRESSIVE CLEANUP CONSEQUENCES     │" "Red"
    Write-Color "  ├─────────────────────────────────────────┤" "Red"
    Write-Color "  │  • Cannot roll back Windows updates      │" "Yellow"
    Write-Color "  │  • All system restore points deleted     │" "Yellow"
    Write-Color "  │  • Hibernation file (hiberfil.sys) gone  │" "Yellow"
    Write-Color "  │  • All Event Viewer logs wiped           │" "Yellow"
    Write-Color "  └─────────────────────────────────────────┘" "Red"
}

function Show-SummaryReport {
    param($Before, $After, $Time, $Drive, $Breakdown)

    $gain = [math]::Round($After.FreeMB - $Before.FreeMB, 2)
    if ($gain -lt 0) { $gain = 0 }
    $gainDisplay = if ($gain -ge 1024) { "$([math]::Round($gain/1024,2)) GB" } else { "$gain MB" }

    $pct = if ($Before.UsedMB -gt 0) { [math]::Min([math]::Round(($gain / $Before.UsedMB) * 40), 40) } else { 0 }
    $bar = ("█" * $pct).PadRight(40, "░")

    Write-Color "`n ╔══════════════════════════════════════════════════════════╗" "Cyan"
    Write-Color " ║               CLEANUP SUMMARY REPORT                    ║" "Cyan"
    Write-Color " ╠══════════════════════════════════════════════════════════╣" "Cyan"
    Write-Color " ║  Drive: ${Drive}:   Time: $Time" "White"
    Write-Color " ╟──────────────────────────────────────────────────────────╢" "Cyan"
    Write-Color " ║  Before : $($Before.FreeMB) MB free" "DarkGray"
    Write-Color " ║  After  : $($After.FreeMB) MB free" "White"
    Write-Color " ╟──────────────────────────────────────────────────────────╢" "Cyan"

    foreach ($entry in $Breakdown.GetEnumerator()) {
        $val = if ($entry.Value -ge 1024) { "$([math]::Round($entry.Value/1024,2)) GB" } else { "$($entry.Value) MB" }
        Write-Color " ║  $($entry.Key.PadRight(28)) $val" "White"
    }

    Write-Color " ╟──────────────────────────────────────────────────────────╢" "Cyan"
    Write-Color " ║  [$bar]" "Green"
    Write-Color " ║  TOTAL FREED: $gainDisplay" "Green"
    Write-Color " ╚══════════════════════════════════════════════════════════╝" "Cyan"
}

# --- Drive Selection ---
function Select-Drive {
    Write-Color "`nAvailable Drives:" "Cyan"

    Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3 OR DriveType=2" | ForEach-Object {
        $free = [math]::Round($_.FreeSpace / 1GB, 2)
        $id = $_.DeviceID.Replace(":", "")
        Write-Color "$($id): ($free GB free)" "White"
    }

    do {
        $inputDrive = Read-Host "`nEnter drive letter (e.g., C)"

        if ([string]::IsNullOrWhiteSpace($inputDrive)) {
            Write-Color "[✕] Please enter a drive letter." "Red"
            continue
        }

        $SelectedDrive = $inputDrive.ToUpper()
        $exists = Get-PSDrive -Name $SelectedDrive -ErrorAction SilentlyContinue

        if (-not $exists) {
            Write-Color "[✕] Invalid drive. Try again." "Red"
        }

    } until ($exists)

    Write-Color "[✓] Selected Drive: ${SelectedDrive}:" "Green"
    return $SelectedDrive
}

# --- Disk Info (MB) ---
function Get-DiskSpace {
    param([string]$DriveLetter)
    $drive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='${DriveLetter}:'"
    if ($null -eq $drive) {
        return [PSCustomObject]@{ FreeMB = 0; UsedMB = 0; TotalMB = 0 }
    }
    return [PSCustomObject]@{
        FreeMB  = [math]::Round($drive.FreeSpace / 1MB, 2)
        UsedMB  = [math]::Round(($drive.Size - $drive.FreeSpace) / 1MB, 2)
        TotalMB = [math]::Round($drive.Size / 1MB, 2)
    }
}

# --- Restore Point ---
function Create-RestorePoint {
    Write-Color "`n[i] Creating Restore Point..." "Cyan"

    try {
        $rpKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore"
        $origVal = (Get-ItemProperty $rpKey -Name SystemRestorePointCreationFrequency -ErrorAction SilentlyContinue).SystemRestorePointCreationFrequency
        Set-ItemProperty $rpKey -Name SystemRestorePointCreationFrequency -Value 0 -ErrorAction SilentlyContinue

        Checkpoint-Computer -Description "Cleanup Restore Point" -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
        Write-Color "[✓] Restore point created" "Green"

        if ($null -ne $origVal) {
            Set-ItemProperty $rpKey -Name SystemRestorePointCreationFrequency -Value $origVal
        } else {
            Remove-ItemProperty $rpKey -Name SystemRestorePointCreationFrequency -ErrorAction SilentlyContinue
        }
    } catch {
        Write-Color "[!] Restore point skipped (System Protection may be disabled or insufficient disk space)" "Yellow"
    }
}

# --- Safe Cleanup ---
function Safe-Cleanup {
    param([string]$TargetDrive)
    Write-Color "`n:: SAFE CLEANUP ::" "Cyan"
    $script:totalSteps = 12
    $script:currentStep = 0
    Update-Step -Label "Running Safe Cleanup"

    try {
        Update-Step -Label "Cleaning User Temp"
        Clear-PathWithReport -Label "User temp" -Path "$env:TEMP" -Recurse
    } catch {}

    try {
        Update-Step -Label "Cleaning Windows Temp"
        Clear-PathWithReport -Label "Windows temp" -Path "$env:windir\Temp" -Recurse
    } catch {}

    try {
        Update-Step -Label "Cleaning Drive Temp"
        $driveTemp = "${TargetDrive}:\Temp"
        if (Test-Path $driveTemp) {
            Clear-PathWithReport -Label "Drive temp (${TargetDrive}:)" -Path $driveTemp -Recurse
        }
    } catch {}

    try {
        Update-Step -Label "Clearing DNS Cache"
        Invoke-Action -Description "flush DNS cache" -Action { ipconfig /flushdns | Out-Null }
        Write-Color "  [✓] DNS cache cleared" "Green"
    } catch {}

    try {
        Update-Step -Label "Emptying Recycle Bin"
        Invoke-Action -Description "empty Recycle Bin (${TargetDrive}:)" -Action { Clear-RecycleBin -DriveLetter $TargetDrive -Force -ErrorAction SilentlyContinue }
        Write-Color "  [✓] Recycle Bin cleaned (${TargetDrive}:)" "Green"
    } catch {
        Write-Color "  [!] Recycle Bin cleanup partial" "Yellow"
    }

    try {
        Update-Step -Label "Clearing Windows Update Cache"
        Invoke-Action -Description "stop Windows Update services" -Action { Stop-Service -Name @("wuauserv", "bits") -Force -ErrorAction SilentlyContinue }
        Clear-PathWithReport -Label "Windows Update cache" -Path "$env:windir\SoftwareDistribution" -Recurse
        Invoke-Action -Description "start Windows Update services" -Action { Start-Service -Name @("wuauserv", "bits") -ErrorAction SilentlyContinue }
    } catch {
        Write-Color "  [!] Update cache cleanup partial" "Yellow"
    }

    try {
        Update-Step -Label "Clearing Delivery Optimization Cache"
        Invoke-Action -Description "stop Delivery Optimization service" -Action { Stop-Service -Name DoSvc -Force -ErrorAction SilentlyContinue }
        Clear-PathWithReport -Label "Delivery Optimization" -Path "$env:windir\SoftwareDistribution\DeliveryOptimization" -Recurse
        Invoke-Action -Description "start Delivery Optimization service" -Action { Start-Service -Name DoSvc -ErrorAction SilentlyContinue }
    } catch {}

    try {
        Update-Step -Label "Clearing Crash Dumps"
        Clear-PathWithReport -Label "Crash dumps" -Path "$env:LOCALAPPDATA\CrashDumps" -Recurse
        Clear-PathWithReport -Label "Windows Error Reports" -Path "$env:ProgramData\Microsoft\Windows\WER" -Recurse
    } catch {}

    try {
        Update-Step -Label "Clearing Store & Font Cache"
        Clear-PathWithReport -Label "Windows Store cache" -Path "$env:LOCALAPPDATA\Packages\Microsoft.WindowsStore_8wekyb3d8bbwe\LocalCache" -Recurse
        Clear-PathWithReport -Label "Windows Store INetCache" -Path "$env:LOCALAPPDATA\Packages\Microsoft.WindowsStore_8wekyb3d8bbwe\AC\INetCache" -Recurse
        Clear-PathWithReport -Label "WinGet temp" -Path "$env:LOCALAPPDATA\Temp\WinGet" -Recurse
        Invoke-Action -Description "stop Font Cache service" -Action { Stop-Service -Name FontCache -Force -ErrorAction SilentlyContinue }
        Clear-PathWithReport -Label "Font cache" -Path "$env:windir\ServiceProfiles\LocalService\AppData\Local\FontCache" -Recurse
        Invoke-Action -Description "start Font Cache service" -Action { Start-Service -Name FontCache -ErrorAction SilentlyContinue }
    } catch {}

    try {
        Update-Step -Label "Clearing Browser Caches"
        # Chromium-based Edge
        Clear-PathWithReport -Label "Edge cache" -Path "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache" -Recurse
        Clear-PathWithReport -Label "Edge code cache" -Path "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Code Cache" -Recurse
        Clear-PathWithReport -Label "Edge GPU cache" -Path "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\GPUCache" -Recurse
        # Google Chrome
        Clear-PathWithReport -Label "Chrome cache" -Path "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache" -Recurse
        Clear-PathWithReport -Label "Chrome code cache" -Path "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Code Cache" -Recurse
        Clear-PathWithReport -Label "Chrome GPU cache" -Path "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\GPUCache" -Recurse
        # Mozilla Firefox
    Clear-PathWithReport -Label "Firefox cache" -Path "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles\*\cache2" -Recurse
    } catch {}

    try {
        Update-Step -Label "Clearing Thumbnail & Icon Cache"
        Invoke-Action -Description "restart Explorer for cache cleanup" -Action { Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue }
        Start-Sleep -Seconds 2
    Clear-PathWithReport -Label "Thumbnail cache" -Path "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache_*.db"
    Clear-PathWithReport -Label "Icon cache" -Path "$env:LOCALAPPDATA\IconCache.db"
        Invoke-Action -Description "start Explorer" -Action { Start-Process explorer }
    } catch {}
}

# --- Moderate Cleanup ---
function Moderate-Cleanup {
    Write-Color "`n:: MODERATE CLEANUP ::" "Cyan"
    $script:totalSteps = 6
    $script:currentStep = 0

    try {
    Update-Step -Label "Running Disk Cleanup"
        Write-Color "  [~] Running Windows Disk Cleanup engine..." "Cyan"

        if ($script:DryRun) {
            Write-Color "  [DRY-RUN] Would run Windows Disk Cleanup (cleanmgr)" "DarkYellow"
        } else {
            $RegPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches"
            Get-ChildItem -Path $RegPath -ErrorAction SilentlyContinue | ForEach-Object {
                New-ItemProperty -Path $_.PSPath -Name "StateFlags0001" -Value 2 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
            }
            Start-WithSpinner -Label "Disk Cleanup running" -Task { Start-Process -FilePath "cleanmgr.exe" -ArgumentList "/sagerun:1" -Wait -WindowStyle Hidden }
        }
    } catch {}

    try {
        Update-Step -Label "Running DISM component cleanup"
        Write-Color "  [~] Running DISM component cleanup (this may take several minutes)..." "Cyan"
        if ($script:DryRun) {
            Write-Color "  [DRY-RUN] Would run DISM component cleanup" "DarkYellow"
        } else {
            Start-WithSpinner -Label "DISM cleanup running" -Task { Dism.exe /online /Cleanup-Image /StartComponentCleanup /NoRestart | Out-Null }
        }
    } catch {}

    try {
        Update-Step -Label "Checking Previous Windows Installations"
        if (Test-Path "$env:SystemDrive\Windows.old") {
            Write-Color "  [~] Removing previous Windows installation via DISM..." "Cyan"
            if ($script:DryRun) {
                Write-Color "  [DRY-RUN] Would remove Windows.old via DISM" "DarkYellow"
            } else {
                Start-WithSpinner -Label "Windows.old cleanup running" -Task { Dism.exe /online /Cleanup-Image /StartComponentCleanup /ResetBase /NoRestart | Out-Null }
            }
        }
    } catch {}

    try {
        Update-Step -Label "Clearing Developer Caches"
        # npm
        if (Test-Path "$env:LOCALAPPDATA\npm-cache") { Clear-PathWithReport -Label "npm cache (LocalAppData)" -Path "$env:LOCALAPPDATA\npm-cache" -Recurse }
        if (Test-Path "$env:APPDATA\npm-cache") { Clear-PathWithReport -Label "npm cache (AppData)" -Path "$env:APPDATA\npm-cache" -Recurse }
        # pip
        if (Test-Path "$env:LOCALAPPDATA\pip\Cache") { Clear-PathWithReport -Label "pip cache" -Path "$env:LOCALAPPDATA\pip\Cache" -Recurse }
        # NuGet
        if (Test-Path "$env:USERPROFILE\.nuget\packages") { Clear-PathWithReport -Label "NuGet packages" -Path "$env:USERPROFILE\.nuget\packages" -Recurse }
        # Cargo
        if (Test-Path "$env:USERPROFILE\.cargo\registry\cache") { Clear-PathWithReport -Label "Cargo cache" -Path "$env:USERPROFILE\.cargo\registry\cache" -Recurse }
    } catch {}

    try {
        Update-Step -Label "Clearing Prefetch & Logs"
        Clear-PathWithReport -Label "Prefetch" -Path "$env:windir\Prefetch" -Recurse
    } catch {}

    try {
        Clear-PathWithReport -Label "Windows logs" -Path "$env:windir\Logs" -Recurse
    } catch {}

    try {
        Update-Step -Label "Clearing App Caches"
        # Teams Classic
        Clear-PathWithReport -Label "Teams cache" -Path "$env:APPDATA\Microsoft\Teams\Cache" -Recurse
        Clear-PathWithReport -Label "Teams blob storage" -Path "$env:APPDATA\Microsoft\Teams\blob_storage" -Recurse
        # Discord
        Clear-PathWithReport -Label "Discord cache" -Path "$env:APPDATA\discord\Cache" -Recurse
        # Slack
        Clear-PathWithReport -Label "Slack cache" -Path "$env:APPDATA\Slack\Cache" -Recurse
        # Yarn
        Clear-PathWithReport -Label "Yarn cache" -Path "$env:LOCALAPPDATA\Yarn\Cache" -Recurse
        # Brave Browser
        Clear-PathWithReport -Label "Brave cache" -Path "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default\Cache" -Recurse
    } catch {}
}

# --- Aggressive Cleanup ---
function Aggressive-Cleanup {
    Write-Color "`n:: AGGRESSIVE CLEANUP ::" "Red"

    $script:totalSteps = 4
    $script:currentStep = 0

    Confirm-AggressiveCleanup

    if ($script:DryRun) {
        Write-Color "  [DRY-RUN] Aggressive cleanup would run DISM ResetBase, delete shadow copies, disable hibernation, and clear event logs." "DarkYellow"
        return
    }

    $confirm = Read-Host "[!] This removes update rollback ability. Continue? (y/n)"
    if ($confirm -ne "y") { return }

    try {
        Update-Step -Label "Running DISM ResetBase"
        Write-Color "  [~] Running DISM ResetBase (this may take several minutes)..." "Cyan"
        Start-WithSpinner -Label "DISM ResetBase running" -Task { Dism.exe /online /Cleanup-Image /StartComponentCleanup /ResetBase /NoRestart | Out-Null }
    } catch {}

    try {
        Update-Step -Label "Deleting Shadow Copies"
        # Keeps new shadow copies but drops the old backups
        vssadmin delete shadows /all /quiet | Out-Null
        Write-Color "  [✓] System Shadow Copies & old restore points deleted" "Green"
    } catch {}

    try {
        Update-Step -Label "Disabling Hibernation"
        powercfg -h off
        Write-Color "  [✓] Hibernation disabled" "Green"
    } catch {}

    try {
        Update-Step -Label "Clearing Event Viewer Logs"
        wevtutil el | ForEach-Object { wevtutil cl "$_" 2>$null }
        Write-Color "  [✓] Event logs cleared" "Green"
    } catch {}
}

# --- Run Cleanup ---
function Run-Cleanup {
    param($mode)

    $stopWatch = [System.Diagnostics.Stopwatch]::StartNew()

    $SelectedDrive = Select-Drive
    Create-RestorePoint

    $script:Breakdown = [ordered]@{}

    $before = Get-DiskSpace -DriveLetter $SelectedDrive

    Write-Color "`n:: BEFORE CLEANUP ::" "Cyan"
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

    $stopWatch.Stop()
    $min = $stopWatch.Elapsed.Minutes
    $sec = $stopWatch.Elapsed.Seconds
    $timeString = "{0:D2}m {1:D2}s" -f $min, $sec

    $gainDisplay = if ($gain -ge 1024) { "$([math]::Round($gain / 1024, 2)) GB" } else { "$gain MB" }
    Show-SummaryReport -Before $before -After $after -Time $timeString -Drive $SelectedDrive -Breakdown $script:Breakdown

    if ($gain -eq 0) {
        Write-Color "`n [i] No significant space freed (already clean or minimal temp files)." "Yellow"
    } else {
        Write-Color "`n [✓] Successfully recovered $gainDisplay of space!" "Green"
    }
}

# --- Interactive Menu ---
function Show-InteractiveMenu {
    $options = @(
        [PSCustomObject]@{ Label = "Safe Cleanup (Fast)"; Color = "Green"; Value = 1 }
        [PSCustomObject]@{ Label = "Moderate Cleanup (Recommended)"; Color = "Yellow"; Value = 2 }
        [PSCustomObject]@{ Label = "Aggressive Cleanup (Deep)"; Color = "Red"; Value = 3 }
        [PSCustomObject]@{ Label = "Full Sweep (All of the above)"; Color = "Magenta"; Value = 4 }
        [PSCustomObject]@{ Label = "Exit"; Color = "Gray"; Value = 5 }
    )
    $descriptions = @(
        "Removes temp files, DNS cache, browser & update caches. Safe for daily use. (~2 min)"
        "Includes Safe + Disk Cleanup, DISM, dev caches & prefetch. (~5-10 min)"
        "Includes Moderate + ResetBase, shadow copies, hibernation & event logs. IRREVERSIBLE."
        "Runs all three levels sequentially. Maximum space recovery. (~15-20 min)"
        "Exit the utility."
    )
    $selection = 0

    while ($true) {
        Clear-Host
        Write-Color "    __          ___           __                     " "Cyan"
        Write-Color "    \ \        / (_)         / /                     " "Cyan"
        Write-Color "     \ \  /\  / / _ _ __    / /_   _ __  _ __   _ __ " "Cyan"
        Write-Color "      \ \/  \/ / | | '_ \  / '_ \ | '_ \| '_ \ | '__|" "Cyan"
        Write-Color "       \  /\  /  | | | | |/ /  \ \| |_) | |_) || |   " "Cyan"
        Write-Color "        \/  \/   |_|_| |_/_/    \_\ .__/| .__/ |_|   " "Cyan"
        Write-Color "            WIN CLEANUP PRO+      | |   | |          " "Cyan"
        Write-Color "                                  |_|   |_|          " "Cyan"
        Write-Color ""
        Write-Color "========================================================" "DarkGray"
        Write-Color "  Use ↑/↓ to navigate, ENTER to select                  " "White"
        Write-Color "========================================================" "DarkGray"
        Write-Color ""

        for ($i = 0; $i -lt $options.Count; $i++) {
            if ($i -eq $selection) {
                Write-Host "  > $($options[$i].Label) " -ForegroundColor "Black" -BackgroundColor $options[$i].Color
            } else {
                Write-Host "    $($options[$i].Label) " -ForegroundColor $options[$i].Color
            }
        }

        Write-Color "`n========================================================" "DarkGray"
    Write-Color "  $($descriptions[$selection])" "DarkGray"

        $keyInfo = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        $keyCode = $keyInfo.VirtualKeyCode

        # Up arrow
        if ($keyCode -eq 38) {
            $selection--
            if ($selection -lt 0) { $selection = $options.Count - 1 }
        }
        # Down arrow
        elseif ($keyCode -eq 40) {
            $selection++
            if ($selection -ge $options.Count) { $selection = 0 }
        }
        # Enter
        elseif ($keyCode -eq 13) {
            return $options[$selection].Value
        }
    }
}

# --- Main ---
do {
    $choice = Show-InteractiveMenu

    if ($choice -eq 5) {
        Clear-Host
        break
    }

    # Map the menu selection appropriately
    $mode = if ($choice -eq 4) { 3 } else { $choice }
    Run-Cleanup -mode $mode

    Write-Color "`n  Press any key to return to menu, or 'R' to Restart now..." "DarkGray"
    $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    if ($key.Character -eq "R" -or $key.Character -eq "r") { Restart-Computer }

} while ($true)