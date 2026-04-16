# Windows Cleanup Utility PRO+ 🧹

A powerful, interactive, and professional Windows cleanup script designed to reclaim gigabytes of lost disk space safely.

## 🚀 Features

- **Interactive UI:** Navigate the beautiful console GUI using arrow keys.
- **Safe Mode:** Clears user temp, Windows temp, DNS cache, recycle bin, and browser caches. No risk to OS stability.
- **Moderate Mode:** Automates Windows native `cleanmgr`, triggers DISM component cleanup, and deletes stale developer caches (npm, pip, NuGet, Cargo).
- **Aggressive Mode:** Performs a DISM '/ResetBase', deletes hidden volume shadow copies, and disables hibernation for massive space recovery. (Use with caution).
- **Summary Report:** Displays a comprehensive execution time and space recovered receipt upon completion.

## 🛠️ Usage

1. Download or clone this repository.
2. Double-click the **`Run-Cleanup.bat`** file.
3. Approve the UAC prompt (Administrator privileges are required to clean system files).
4. Select your desired cleanup mode using your Up/Down arrow keys.

_Alternatively, run `cleanup.ps1` from an elevated PowerShell prompt._

## ⚠️ Disclaimer

This utility modifies system files and deletes caches. While "Safe" and "Moderate" modes are generally risk-free, **Aggressive** mode removes your ability to uninstall current Windows Updates out of the box. Use at your own risk. The authors are not responsible for any data loss or system instability.

---

**License:** See `LICENSE` file for details.
