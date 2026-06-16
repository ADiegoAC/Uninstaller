# 🛠️ Un1nst4ll3r
### 🚀 High-Performance System Analysis & App Decompression Engine  

**Un1nst4ll3r** is a next-generation PowerShell-based maintenance utility designed to hunt down installed applications and their "ghost" traces. Unlike standard uninstallers, it utilizes deep-level heuristics to map the filesystem and registry.

---

## ⚡ Key Features  

*   🔍 **Multi-Source Discovery**: Scans standard Registry (Win32), 64-bit nodes, and modern **AppX/Windows Store** packages.
*   🕵️ **Orphan Detection**: Uses **MuiCache** and Shortcut indexing to find apps that have lost their registry entries but still reside on your disk.
*   📊 **Deep Size Engine**: Bypasses generic registry metadata to calculate real-time folder sizes via safe I/O recursive measurement.
*   🛡️ **Smart Filtering**: Automatically protects critical system paths (WinSxS, System32) from accidental modification.
*   📑 **Structured Logging**: Every operation is logged with high-resolution timestamps and categorized for forensic inspection.
*   🌐 **Multi-Language Support**: Full localized experience for English (US), Portuguese (BR), and Spanish (ES).

---

## 🎮 Graphical Interface Guide  

1.  **[SCAN LIST]** 💾: Instantly loads the last successful scan results from the local JSON cache.
2.  **[NEW SCAN]** 🔄: Triggers the **4-Phase Engine**:
    *   *Phase 1*: Registry & Store interrogation.
    *   *Phase 2*: MuiCache & Orphan discovery.
    *   *Phase 3*: Deep disk size measurement.
    *   *Phase 4*: JSON data export.
3.  **[UNINSTALL]** 🗑️: Launches the targeted removal sequence (Supports MSI, Silent, and AppX modes).
4.  **[VIEW LOG]** 📟: Opens the real-time debug terminal to see exactly how the engine is resolving paths.

---

## ⚙️ Technical Requirements  

*   **OS**: Windows 8.1/10/11
*   **Host**: **PowerShell 5.1** (Core) but 7.x is highly recommended for maximum performance.
*   **Dependency**: Includes an auto-updater that utilizes **Winget** to keep your PowerShell environment up to date.(under maintenance)

---

## 🛠️ Developer Quick Start  

Launch the interface directly via terminal:
```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File Un1nst4ll3r-UI.ps1
```

**Data Export**: All scan results are serialized into `Un1nst4ll3r_ScanResult.json` for easy integration with other automation tools.

---

## 📜 License & Credits
Developed with brain as a high-performance alternative to legacy uninstallers.
*   **Logs**: Stored in `$Global:Un1AnalysisLog`.
*   **Engine**: Modular architecture located in `Un1nst4ll3r.ps1`.

*Contributing? Feel free to open a PR or report orphans that the heuristic engine missed!*
