# Un1nst4ll3r  

* Description: Un1nst4ll3r is a PowerShell-based Windows uninstaller and system scanner that discovers installed apps and uninstallers using registry, AppX, shortcut and file heuristics. It provides a lightweight GUI splash and a structured analysis log for automation and inspection.
* Features: fast multi-source scanning, heuristic EXE detection, shortcut & MuiCache indexing, optional GUI (Un1nst4ll3r-UI.ps1), and structured logs for downstream processing.
* Quick Start: ` run the CLI scanner with powershell -NoProfile -ExecutionPolicy Bypass -File Un1nst4ll3r.ps1 or launch the GUI with powershell -NoProfile -ExecutionPolicy Bypass -File Un1nst4ll3r-UI.ps1. `
* Logs: runtime entries are stored in $Global:Un1AnalysisLog (structured objects with Timestamp, Category, Message, Color, Text) and can be viewed from the UI View Log panel.
* License: see the repository LICENSE file for terms.
* Contributing: open an issue or PR with repro steps; tests and small, focused patches are welcome..

