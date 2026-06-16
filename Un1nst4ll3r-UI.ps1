# ======================================================================
#  Un1nst4ll3r - Graphical User Interface
#  Version: 1.5.1
# ======================================================================

# Forces the Windows terminal to use UTF-8 to display accents correctly
#[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
#[Console]::InputEncoding = [System.Text.Encoding]::UTF8
#$OutputEncoding = [System.Text.Encoding]::UTF8

# ==========================================
# 1. DPI Awareness Trick (Prevents blurry UI on high DPI screens)
# ==========================================
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class DpiHelper {
    [DllImport("user32.dll", SetLastError=true)]
    public static extern bool SetProcessDPIAware();
}
'@
[void][DpiHelper]::SetProcessDPIAware()

# ==========================================
# 2. Smart Directory Detection (Fixes PS2EXE %TEMP% issue)
# ==========================================
$exePath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
$exeName = [System.IO.Path]::GetFileNameWithoutExtension($exePath)

if ($exeName -match '^(pwsh|powershell|powershell_ise|WindowsTerminal)$') {
    # Running as a native .ps1 script
    $AppRoot = $PSScriptRoot
} else {
    # Compiled as an EXE (Gets the folder where the .exe is actually located)
    $AppRoot = [System.IO.Path]::GetDirectoryName($exePath)
}

# ==========================================
# 3. Load Required .NET Assemblies
# ==========================================
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ==========================================
# 4. Import the Un1nst4ll3r Engine
# ==========================================
$enginePath = Join-Path $AppRoot "Un1nst4ll3r.ps1"
if (Test-Path $enginePath) {
    . $enginePath
} else {
    [System.Windows.Forms.MessageBox]::Show("Engine Un1nst4ll3r.ps1 not found in $AppRoot!", "Critical Error", "OK", "Error")
    exit
}

# Load Markdown Viewer Library if present
 $markdigDll = Join-Path $AppRoot "Markdig.dll"

if (Test-Path $markdigDll) {
    try {
        Unblock-File -Path $markdigDll -ErrorAction SilentlyContinue
        Add-Type -Path $markdigDll
        Write-Un1Log -Category "INIT" -Message "Markdig library loaded successfully." -Color Green
    } catch {
        Write-Un1Log -Category "INIT" -Message "Markdig library failed to load: $($_.Exception.Message)" -Color Red
    }
} else {
    Write-Un1Log -Category "INIT" -Message "Markdig.dll not found. Help will display raw text." -Color Yellow
}

# ==========================================
# 5. Multi-Language System Setup
# ==========================================
$script:LangFullObject = $langObj 
$script:langPath = Join-Path $AppRoot "Un1nst4ll3r_Lang.json"
$script:CurrentLang = "pt-BR"
$script:LangData = $null

if (Test-Path $script:langPath) {
    try {
        $langRaw = [System.IO.File]::ReadAllText($script:langPath, [System.Text.Encoding]::UTF8)
        $langObj = ConvertFrom-Json -InputObject $langRaw
        $script:LangData = $langObj.$script:CurrentLang
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Error reading language JSON!", "Error", "OK", "Warning")
    }
} else {
    [System.Windows.Forms.MessageBox]::Show("Un1nst4ll3r_Lang.json not found in $AppRoot!", "Error", "OK", "Warning")
}

# Fallback definitions in case the JSON read fails entirely
if ($null -eq $script:LangData) {
    $script:LangData = [PSCustomObject]@{
        Title = "Un1nst4ll3r"; Version = "v2.2"; BtnScanList = "SCAN LIST"; BtnNewScan = "NEW SCAN"
        BtnUninstall = "UNINSTALL"; BtnCleanTraces = "CLEAN TRACES"; BtnViewLog = "VIEW LOG"
        BtnHelp = "HELP"; BtnAbout = "ABOUT"
        ColName = "Nome"; ColVersion = "Versao"; ColManufacturer = "Fabricante"; ColSize = "Tamanho"
        ColType = "Tipo"; ColLocation = "Local"; ColStatus = "Status"
        StatusReady = "Ready."; StatusNoCache = "No cache. Click SCAN LIST."; StatusLoadingCache = "Loading cache..."
        StatusCacheLoaded = "Cache loaded. {0} apps. {1}"; StatusOrphanAlert = "ALERT: {0} orphan(s)!"
        StatusCacheError = "Error reading cache."; StatusCacheParseError = "Parse error: {0}"
        MsgUninstallFuture = "Uninstall coming soon."; MsgCleanFuture = "Clean traces coming soon."
        StatusNoLog = "No log. Run NEW SCAN."; StatusShowingLog = "Showing log."
        StatusReadyClick = "Click SCAN LIST to start."; SplashTitle = "UN1NST4LL3R"
        SplashAnalyze = "Analyzing..."; SplashInit = "Init..."; LogInitText = "Log..."
        Phase1 = "Phase 1..."; Phase2 = "Phase 2..."; Phase3 = "Phase 3..."; PhaseExport = "Exporting..."; PhaseGrid = "Populating..."
    }
}

# ==========================================
# 6. PowerShell 7 Verification & Auto-Updater
# ==========================================
function Test-AndInstallPowerShell7 {
    # Exit function if already running PS7+
    if ($PSVersionTable.PSVersion.Major -ge 7) { return }

    $L = $script:LangData

    # --- PROMPT DIALOG (Styled Form) ---
    $promptForm = New-Object System.Windows.Forms.Form
    $promptForm.Text = $L.UpdateRequiredTitle
    $promptForm.Size = New-Object System.Drawing.Size(450, 200)
    $promptForm.StartPosition = "CenterScreen"
    $promptForm.FormBorderStyle = "FixedDialog"
    $promptForm.MaximizeBox = $false
    $promptForm.MinimizeBox = $false
    $promptForm.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
    $promptForm.ForeColor = [System.Drawing.Color]::White

    $promptLabel = New-Object System.Windows.Forms.Label
    $promptLabel.Text = $L.UpdateRequiredMsg
    $promptLabel.Font = New-Object System.Drawing.Font("Consolas", 10)
    $promptLabel.ForeColor = [System.Drawing.Color]::White
    $promptLabel.Size = New-Object System.Drawing.Size(400, 60)
    $promptLabel.Location = New-Object System.Drawing.Point(20, 20)

    $btnYes = New-Object System.Windows.Forms.Button
    $btnYes.Text = "OK"
    $btnYes.Font = New-Object System.Drawing.Font("Consolas", 10, [System.Drawing.FontStyle]::Bold)
    $btnYes.BackColor = [System.Drawing.Color]::FromArgb(0, 191, 255)
    $btnYes.ForeColor = [System.Drawing.Color]::Black
    $btnYes.FlatStyle = "Flat"
    $btnYes.Size = New-Object System.Drawing.Size(100, 35)
    $btnYes.Location = New-Object System.Drawing.Point(110, 110)
    $btnYes.DialogResult = [System.Windows.Forms.DialogResult]::Yes

    $btnNo = New-Object System.Windows.Forms.Button
    $btnNo.Text = "CANCEL"
    $btnNo.Font = New-Object System.Drawing.Font("Consolas", 10, [System.Drawing.FontStyle]::Bold)
    $btnNo.BackColor = [System.Drawing.Color]::FromArgb(80, 80, 80)
    $btnNo.ForeColor = [System.Drawing.Color]::White
    $btnNo.FlatStyle = "Flat"
    $btnNo.Size = New-Object System.Drawing.Size(100, 35)
    $btnNo.Location = New-Object System.Drawing.Point(230, 110)
    $btnNo.DialogResult = [System.Windows.Forms.DialogResult]::No

    $promptForm.Controls.AddRange(@($promptLabel, $btnYes, $btnNo))
    $result = $promptForm.ShowDialog()

    if ($result -ne [System.Windows.Forms.DialogResult]::Yes) {
        [System.Windows.Forms.MessageBox]::Show($L.UpdateDeclined, $L.Title, "OK", "Warning")
        exit # Terminate application
    }
    $promptForm.Dispose()

    # --- WINGET EXISTENCE CHECK ---
    $wingetExe = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (!$wingetExe) {
        [System.Windows.Forms.MessageBox]::Show($L.UpdateWingetNotFound, $L.Title, "OK", "Error")
        exit
    }

    # --- INSTALLATION MINI-TERMINAL (Styled UI) ---
    $updateForm = New-Object System.Windows.Forms.Form
    $updateForm.Text = $L.UpdateProgressTitle
    $updateForm.Size = New-Object System.Drawing.Size(600, 350)
    $updateForm.StartPosition = "CenterScreen"
    $updateForm.FormBorderStyle = "FixedDialog"
    $updateForm.MaximizeBox = $false
    $updateForm.MinimizeBox = $false
    $updateForm.BackColor = [System.Drawing.Color]::FromArgb(15, 15, 15)
    $updateForm.ForeColor = [System.Drawing.Color]::White

    $updateTitle = New-Object System.Windows.Forms.Label
    $updateTitle.Text = $L.UpdateProgressTitle
    $updateTitle.Font = New-Object System.Drawing.Font("Consolas", 16, [System.Drawing.FontStyle]::Bold)
    $updateTitle.ForeColor = [System.Drawing.Color]::FromArgb(0, 191, 255)
    $updateTitle.AutoSize = $true
    $updateTitle.Location = New-Object System.Drawing.Point(20, 15)

    $updateSub = New-Object System.Windows.Forms.Label
    $updateSub.Text = $L.UpdateProgressSub
    $updateSub.Font = New-Object System.Drawing.Font("Consolas", 9)
    $updateSub.ForeColor = [System.Drawing.Color]::Gray
    $updateSub.AutoSize = $true
    $updateSub.Location = New-Object System.Drawing.Point(22, 50)

    $terminalBox = New-Object System.Windows.Forms.RichTextBox
    $terminalBox.Multiline = $true
    $terminalBox.ReadOnly = $true
    $terminalBox.BackColor = [System.Drawing.Color]::FromArgb(20, 20, 20)
    $terminalBox.ForeColor = [System.Drawing.Color]::FromArgb(0, 255, 100) # Cyberpunk green terminal text
    $terminalBox.Font = New-Object System.Drawing.Font("Consolas", 8)
    $terminalBox.Size = New-Object System.Drawing.Size(540, 180)
    $terminalBox.Location = New-Object System.Drawing.Point(20, 80)
    $terminalBox.ScrollBars = "Vertical"
    $terminalBox.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    
    # Prevents the annoying "beep" sound when pressing Enter while the terminal is focused
    $terminalBox.Add_KeyDown({ if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Enter) { $_.SuppressKeyPress = $true } })
    
    $updateForm.Controls.AddRange(@($updateTitle, $updateSub, $terminalBox))
    $updateForm.Show()
    [System.Windows.Forms.Application]::DoEvents()

    # --- BACKGROUND INSTALLATION PROCESS ---
    $installSuccess = $false
    try {
        $proc = New-Object System.Diagnostics.Process
        $proc.StartInfo.FileName = $wingetExe.Source
        $proc.StartInfo.Arguments = "install Microsoft.PowerShell --accept-package-agreements --accept-source-agreements --silent"
        $proc.StartInfo.UseShellExecute = $false
        $proc.StartInfo.RedirectStandardOutput = $true
        $proc.StartInfo.RedirectStandardError = $true
        $proc.StartInfo.CreateNoWindow = $true
        
        $proc.Start() | Out-Null

        # Reads standard output stream in real-time without freezing the main UI thread
        while (!$proc.StandardOutput.EndOfStream) {
            $rawLine = $proc.StandardOutput.ReadLine()
            
            # 1. Strip ANSI color codes (e.g., [32m) injected by Winget
            $cleanLine = $rawLine -replace '\x1b\[[0-9;]*[a-zA-Z]', ''
            
            # 2. Handle carriage returns (\r). Winget uses this to overwrite the same line for progress bars
            if ($cleanLine -match '\r') {
                $cleanLine = ($cleanLine -split '\r')[-1]
            }
            
            $line = $cleanLine.TrimEnd()

            # Ignore empty lines after cleanup
            if ([string]::IsNullOrWhiteSpace($line)) { 
                [System.Windows.Forms.Application]::DoEvents()
                continue 
            }

            # 3. Progress detection via Regex (spinners, percentages, unicode blocks, or asterisks)
            $isProgress = $line -match '[-|/\\]\s*$' -or `
                          $line -match '\d+\s*%' -or `
                          $line -match '\[=+[^\]]*\]' -or `
                          $line -match '^\s*\*{2,}'
            
            if ($isProgress) {
                # Overwrite the last line for progress animations
                if ($terminalBox.Text.Length -gt 0) {
                    $lastNewLine = $terminalBox.Text.LastIndexOf("`n")
                    if ($lastNewLine -ge 0) {
                        $terminalBox.Select($lastNewLine + 1, $terminalBox.TextLength - ($lastNewLine + 1))
                    } else {
                        $terminalBox.Select(0, $terminalBox.TextLength)
                    }
                } else {
                    $terminalBox.Select(0, 0)
                }
                $terminalBox.SelectedText = $line
            } else {
                # Normal log line, append with line break
                $terminalBox.AppendText("$line`n")
            }
            
            # Force auto-scroll to the bottom
            $terminalBox.SelectionStart = $terminalBox.TextLength
            $terminalBox.SelectionLength = 0
            $terminalBox.ScrollToCaret()
            
            # Allow the GUI to process events (breathe)
            [System.Windows.Forms.Application]::DoEvents()
        }

        $proc.WaitForExit()
        $installSuccess = ($proc.ExitCode -eq 0)
    }
    catch {
        $terminalBox.AppendText("ERROR: $($_.Exception.Message)`r`n")
        $installSuccess = $false
    }

    if ($installSuccess) {
        $terminalBox.AppendText("`r`n" + $L.UpdateSuccess)
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Seconds 3
        $updateForm.Close()

        # Locate the newly installed pwsh.exe
        # PRIORITY 1: Get-Command (Resolves automatically via Windows PATH)
        $pwshExe = (Get-Command pwsh.exe -ErrorAction SilentlyContinue).Source
        
        # PRIORITY 2: Direct folder fallback (In case PATH hasn't updated in the current session)
        if ([string]::IsNullOrWhiteSpace($pwshExe)) {
            $pwshPaths = @(
                "$env:ProgramFiles\PowerShell\7\pwsh.exe",
                "${env:ProgramFiles(x86)}\PowerShell\7\pwsh.exe",
                [System.IO.Path]::Combine($env:LocalAppData, "Microsoft", "WindowsApps", "pwsh.exe")
            )
            $pwshExe = $pwshPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
        }

        if ($pwshExe) {
            # AUTO-RELAUNCH: The script terminates and restarts itself using the new PowerShell 7 executable
            Start-Process $pwshExe -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`""
            exit
        } else {
            [System.Windows.Forms.MessageBox]::Show($L.UpdateFailed, $L.Title, "OK", "Error")
            exit
        }
    } else {
        [System.Windows.Forms.MessageBox]::Show($L.UpdateFailed, $L.Title, "OK", "Error")
        $updateForm.Close()
        exit
    }
}

# Uncomment the line below to enable auto-update. Keep commented if building with PS2EXE.
#Test-AndInstallPowerShell7

# ==========================================
# 7. Local Cache and System Package Bank Paths
# ==========================================
$script:jsonPath = Join-Path $AppRoot "Un1nst4ll3r_ScanResult.json"
$script:sysBankPath = Join-Path $AppRoot "Un1nst4ll3r_SysPkgBank.json"
$Global:SysPkgBank = @()

if (Test-Path $script:sysBankPath) {
    try {
        $sysBankRaw = [System.IO.File]::ReadAllText($script:sysBankPath, [System.Text.Encoding]::UTF8)
        $Global:SysPkgBank = ConvertFrom-Json -InputObject $sysBankRaw
    } catch {}
} 

# ==========================================
# Helper Function: Extract Application Icon
# ==========================================
function Get-Un1nst4ll3rAppIcon {
    param ([string]$AppName, [string]$IconPath, [string]$ExePath, [string]$InstallLocal, [string]$Chave, [array]$ShortcutIconLocations)

    # Inner helper to safely extract icons from files
    function Test-ExtractIcon {
        param ([string]$FilePath)
        if ([string]::IsNullOrWhiteSpace($FilePath)) { return $null }
        try {
            $cleanPath = [System.Environment]::ExpandEnvironmentVariables($FilePath.Trim())
            # Remove trailing indexes from icon paths (e.g., C:\app.exe,0)
            if ($cleanPath -match '^(.+?),(-?\d+)$') { $cleanPath = $Matches[1] }
            if (Test-Path $cleanPath -ErrorAction SilentlyContinue) {
                if ($cleanPath -match '\.(png|jpe?g|bmp|gif)$') {
                    $sourceImage = [System.Drawing.Image]::FromFile($cleanPath)
                    try {
                        $bitmap = New-Object System.Drawing.Bitmap(32, 32)
                        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
                        try {
                            $graphics.Clear([System.Drawing.Color]::Transparent)
                            $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                            $graphics.DrawImage($sourceImage, 0, 0, 32, 32)
                        } finally {
                            $graphics.Dispose()
                        }
                        return $bitmap
                    } finally {
                        $sourceImage.Dispose()
                    }
                }

                $icon = [System.Drawing.Icon]::ExtractAssociatedIcon($cleanPath)
                if ($null -ne $icon) { return $icon.ToBitmap() }
                
                # Fallback for standard .ico files
                if ($cleanPath -match '\.ico$') {
                    $icon = New-Object System.Drawing.Icon($cleanPath)
                    if ($null -ne $icon) { return $icon.ToBitmap() }
                }
            }
        } catch {}
        return $null
    }

    # Strategy 1: DisplayIcon do Registro ou Ícone dos Atalhos (Ordenado por prioridade)
    if (![string]::IsNullOrWhiteSpace($IconPath)) {
        $bmp = Test-ExtractIcon $IconPath
        if ($bmp) { 
            Write-Un1Log -Category "ICON" -Message "S1 Icon found [DisplayIcon]." -Color Brown
            return $bmp 
        }
    }

    # Strategy 2: Attempt to pull icon from matched memory shortcuts
    if (![string]::IsNullOrWhiteSpace($AppName) -and $null -ne $Global:MemoryShortcuts -and $Global:MemoryShortcuts.Count -gt 0) {
        $safeAppName = $AppName -replace '\(.*\)', '' -replace '\s+\d+.*', '' -replace '[^\w\s\-+]', ''
        $safeAppName = $safeAppName.Trim()
        if (![string]::IsNullOrWhiteSpace($safeAppName)) {
            $lnkMatch = $Global:MemoryShortcuts | Where-Object { 
                ($_.LnkName -like "*$safeAppName*" -or $safeAppName -like "*$($_.LnkName)*" -or $_.LnkName -like "*$AppName*") -and
                $_.Target -notmatch 'uninstall|unins\d+|setup' -and $_.Target -notmatch '\.(url|html?|website)$'
            } | Select-Object -First 1
            
            if ($lnkMatch) {
                # PRIORIDADE A: O atalho tem um ícone customizado definido? (Ex: app.ico,0)
                if (![string]::IsNullOrWhiteSpace($lnkMatch.IconLocation)) {
                    $bmp = Test-ExtractIcon $lnkMatch.IconLocation
                    if ($bmp) { 
                        Write-Un1Log -Category "ICON" -Message "S2 Icon found[Shortcut IconLocation]." -Color Brown
                        return $bmp 
                    }
                }
                
                # PRIORIDADE B: Se não achou no IconLocation, tenta extrair do Target (o .exe)
                if (![string]::IsNullOrWhiteSpace($lnkMatch.Target) -and (Test-Path $lnkMatch.Target -ErrorAction SilentlyContinue)) {
                    $bmp = Test-ExtractIcon $lnkMatch.Target
                    if ($bmp) { 
                        Write-Un1Log -Category "ICON" -Message "S2 Icon found[Shortcut Target]." -Color Brown
                        return $bmp 
                    }
                }
            }
        }
    }

    # Strategy 3: Icon found ShortcutIconLocation.
    if ($null -ne $ShortcutIconLocations -and $ShortcutIconLocations.Count -gt 0) {
        foreach ($scIcon in $ShortcutIconLocations) {
            if (![string]::IsNullOrWhiteSpace($scIcon)) {
                # O Test-ExtractIcon já cuida de limpar o ",0" ou as aspas automaticamente!
                $bmp = Test-ExtractIcon $scIcon
                if ($bmp) { 
                    Write-Un1Log -Category "ICON" -Message "S3 Icon found [ShortcutIconLocation]." -Color Brown
                    return $bmp 
                }
            }
        }
    }

    # Strategy 4: Attempt to resolve icon through the System Package Bank rules
    if (![string]::IsNullOrWhiteSpace($AppName) -and $Global:SysPkgBank.Count -gt 0) {
        foreach ($rule in $Global:SysPkgBank) {
            try {
                if ($AppName -match $rule.Pattern) {
                    $expandedIconPath = [System.Environment]::ExpandEnvironmentVariables($rule.IconPath)
                    $bmp = Test-ExtractIcon $expandedIconPath
                    if ($bmp) { 
                        Write-Un1Log -Category "ICON" -Message "S4 Icon found[Package Bank]. Icon: $($bmp)" -Color Brown
                        return $bmp }
                }
            } catch {}
        }
    }

    # Strategy 5: Windows Installer Cache (GUID folder)
    # Se a Chave for um GUID válido, procuramos na pasta oculta do Windows Installer
    if (![string]::IsNullOrWhiteSpace($Chave) -and $Chave -match '^\{[A-Fa-f0-9\-]+\}$') {
        $installerPath = Join-Path $env:windir "Installer\$Chave"
        
        if (Test-Path $installerPath -PathType Container -ErrorAction SilentlyContinue) {
            # Busca arquivos dentro da pasta do GUID, ignorando patches (.msp) e transforms (.mst)
            $candidateFiles = Get-ChildItem -Path $installerPath -File -ErrorAction SilentlyContinue | Where-Object {
                $_.Extension -notin @('.msp', '.mst', '.dll')
            }
            
            # Prioridade 1: Arquivos que se chamam "icon" ou "ARPPRODUCTICON" (padrão comum do MSI)
            $iconFile = $candidateFiles | Where-Object { $_.Name -like "icon*" -or $_.Name -like "ARPPRODUCTICON*" } | Select-Object -First 1
            
            # Prioridade 2: Qualquer arquivo sem extensão, ou .exe, ou .ico
            if (!$iconFile) {
                $iconFile = $candidateFiles | Where-Object { 
                    [string]::IsNullOrWhiteSpace($_.Extension) -or $_.Extension -in @('.exe', '.ico') 
                } | Select-Object -First 1
            }

            # Se encontramos um candidato na pasta do Installer
            if ($iconFile) {
                # Tenta o método convencional primeiro (funciona se for .exe ou .ico)
                $bmp = Test-ExtractIcon $iconFile.FullName
                if ($bmp) { 
                    Write-Un1Log -Category "ICON" -Message "S5 Icon found[Installer-ext]. Icon: $($bmp)" -Color Brown
                    return $bmp }

                # TRUQUE PARA ARQUIVOS SEM EXTENSÃO:
                # O método ExtractAssociatedIcon falha sem extensão. Se falhou, tentamos 
                # forçar a leitura como um arquivo de ícone raw usando o construtor do Icon.
                try {
                    $rawIcon = New-Object System.Drawing.Icon($iconFile.FullName)
                    $bmp = $rawIcon.ToBitmap()
                    $rawIcon.Dispose()
                    if ($bmp) { 
                    Write-Un1Log -Category "ICON" -Message "S5 Icon found[Installer-noExt]. Icon: $($bmp)" -Color Brown
                        return $bmp }
                } catch {
                    # Se der erro, o arquivo não é um ícone válido, ignoramos.
                }
            }
        }
    }

    # Define a blacklist to avoid grabbing uninstaller/helper icons
    $icoBlacklist = @('^uninstall', '^unins\d+', '^setup', '^remove', '^help', 'update$')
    
    # Strategy 6: Extract from discovered ExePath
    if (![string]::IsNullOrWhiteSpace($ExePath) -and (Test-Path $ExePath -ErrorAction SilentlyContinue)) {
        $exeDir = Split-Path $ExePath
        $isSubprocess = (![string]::IsNullOrWhiteSpace($InstallLocal) -and $exeDir -ne $InstallLocal)
        
        # If the ExePath is in a subdirectory (like /bin), search the root install dir for an .ico first
        if ($isSubprocess -and (Test-Path $InstallLocal -ErrorAction SilentlyContinue)) {
            $rootIcos = @(Get-ChildItem -Path $InstallLocal -Filter "*.ico" -File -ErrorAction SilentlyContinue | Where-Object {
                $bl = $false; foreach ($p in $icoBlacklist) { if ($_.Name -match $p) { $bl = $true; break } }; -not $bl
            })
            if ($rootIcos.Count -gt 0) {
                $safeAppName = $AppName -replace '\(.*\)', '' -replace '\s+\d+.*', '' -replace '[^\w\s\-+]', ''
                $mainIco = $rootIcos | Where-Object { $_.BaseName -like "*$safeAppName*" } | Select-Object -First 1
                if (!$mainIco) { $mainIco = $rootIcos | Select-Object -First 1 }
                $bmp = Test-ExtractIcon $mainIco.FullName
                if ($bmp) { 
                    Write-Un1Log -Category "ICON" -Message "S6 Icon found[ExePath]. Icon: $($bmp)" -Color Brown
                    return $bmp }
            }
        }
        
        # Fallback to extracting straight from the executable
        $bmp = Test-ExtractIcon $ExePath
        if ($bmp) { return $bmp }
    }

    # Strategy 7: Deep search within the Install Location for any valid .ico file
    if (![string]::IsNullOrWhiteSpace($InstallLocal) -and (Test-Path $InstallLocal -ErrorAction SilentlyContinue)) {
        $icoFiles = @(Get-ChildItem -Path $InstallLocal -Filter "*.ico" -File -ErrorAction SilentlyContinue)
        $icoFiles += @(Get-ChildItem -Path "$InstallLocal\*\*.ico" -File -ErrorAction SilentlyContinue)
        
        $validIcos = @($icoFiles | Where-Object {
            $bl = $false; foreach ($p in $icoBlacklist) { if ($_.Name -match $p) { $bl = $true; break } }; -not $bl
        })
        
        if ($validIcos.Count -gt 0) {
            $safeAppName = $AppName -replace '\(.*\)', '' -replace '\s+\d+.*', '' -replace '[^\w\s\-+]', ''
            $mainIco = $validIcos | Where-Object { $_.BaseName -like "*$safeAppName*" } | Select-Object -First 1
            if (!$mainIco) { $mainIco = $validIcos | Select-Object -First 1 }
            $bmp = Test-ExtractIcon $mainIco.FullName
            if ($bmp) { 
                Write-Un1Log -Category "ICON" -Message "S7 Icon found[ICO File]. Icon: $($bmp)" -Color Brown
                return $bmp }
        }
    }
    
    # Return a blank 32x32 bitmap if all icon extraction strategies fail
    return New-Object System.Drawing.Bitmap(32, 32)
}

# ==========================================
# 8. Calculate Responsive Window Dimensions
# ==========================================
$screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$formWidth = [int]($screen.Width * 1)
$formHeight = [int]($screen.Height * 1.01)

# ==========================================
# 9. Main Form Creation
# ==========================================
$form = New-Object System.Windows.Forms.Form
$form.Text = $script:LangData.Title
$form.Size = New-Object System.Drawing.Size($formWidth, $formHeight)
$form.StartPosition = "CenterScreen"
$form.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
$form.ForeColor = [System.Drawing.Color]::White
$form.MinimumSize = New-Object System.Drawing.Size(1000, 400)
$icoFile = Join-Path $AppRoot "icon.ico"
 if (Test-Path $icoFile) {
     try {
         $form.Icon = New-Object System.Drawing.Icon($icoFile)
     } catch {
         $form.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($PSCommandPath)
     }
 } else {
     $form.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($PSCommandPath)
 }


# ==========================================
# 10. Header Panel
# ==========================================
$headerPanel = New-Object System.Windows.Forms.Panel
$headerPanel.Dock = "Top"
$headerPanel.Height = 60
$headerPanel.BackColor = [System.Drawing.Color]::FromArgb(20, 20, 20)
$headerPanel.Padding = New-Object System.Windows.Forms.Padding(15)

# Application Icon
$formIcon = New-Object System.Windows.Forms.PictureBox
$formIcon.Image = [System.Drawing.Image]::FromFile($(Join-Path $AppRoot "icon.ico"))
$formIcon.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::StretchImage
$formIcon.Size = New-Object System.Drawing.Size(32, 32)
$formIcon.Location = New-Object System.Drawing.Point(20, 8)

$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text = $script:LangData.Title
$titleLabel.Font = New-Object System.Drawing.Font("Consolas", 20, [System.Drawing.FontStyle]::Bold)
$titleLabel.ForeColor = [System.Drawing.Color]::FromArgb(0, 191, 255)
$titleLabel.AutoSize = $true
$titleLabel.Location = New-Object System.Drawing.Point(55, 8)

$versionLabel = New-Object System.Windows.Forms.Label
$versionLabel.Text = $script:LangData.Version
$versionLabel.Font = New-Object System.Drawing.Font("Consolas", 9)
$versionLabel.ForeColor = [System.Drawing.Color]::Gray
$versionLabel.AutoSize = $true
$versionLabel.Location = New-Object System.Drawing.Point(20, 44)

# --- Help and About Buttons ---
$btnHelp = New-Object System.Windows.Forms.Button
$btnHelp.Text = $script:LangData.BtnHelp
$btnHelp.Font = New-Object System.Drawing.Font("Consolas", 9, [System.Drawing.FontStyle]::Bold)
$btnHelp.BackColor = [System.Drawing.Color]::FromArgb(60, 60, 60)
$btnHelp.ForeColor = [System.Drawing.Color]::Black
$btnHelp.FlatStyle = "Flat"
$btnHelp.Size = New-Object System.Drawing.Size(55, 20)
$btnHelp.Top = 12

$btnAbout = New-Object System.Windows.Forms.Button
$btnAbout.Text = $script:LangData.BtnAbout
$btnAbout.Font = New-Object System.Drawing.Font("Consolas", 9, [System.Drawing.FontStyle]::Bold)
$btnAbout.BackColor = [System.Drawing.Color]::FromArgb(60, 60, 60)
$btnAbout.ForeColor = [System.Drawing.Color]::Black
$btnAbout.FlatStyle = "Flat"
$btnAbout.Size = New-Object System.Drawing.Size(55, 20)
$btnAbout.Top = 12

$headerPanel.Controls.AddRange(@($titleLabel, $versionLabel, $formIcon, $btnHelp, $btnAbout))

# ==========================================
# 11. Actions Toolbar (Primary Buttons & Languages)
# ==========================================
$actionsPanel = New-Object System.Windows.Forms.Panel
$actionsPanel.Dock = "Top"
$actionsPanel.Height = 65
$actionsPanel.BackColor = [System.Drawing.Color]::FromArgb(10, 20, 30)
$actionsPanel.Padding = New-Object System.Windows.Forms.Padding(10, 5, 10, 5)

# --- Primary Buttons (Blue Gradients, Black Text) ---
$btnScan = New-Object System.Windows.Forms.Button
$btnScan.Text = $script:LangData.BtnScanList
$btnScan.Font = New-Object System.Drawing.Font("Consolas", 10, [System.Drawing.FontStyle]::Bold)
$btnScan.BackColor = [System.Drawing.Color]::FromArgb(15, 50, 120)
$btnScan.ForeColor = [System.Drawing.Color]::Black
$btnScan.FlatStyle = "Flat"
$btnScan.Size = New-Object System.Drawing.Size(100, 35)
$btnScan.Location = New-Object System.Drawing.Point(10,15)

$btnDeepScan = New-Object System.Windows.Forms.Button
$btnDeepScan.Text = $script:LangData.BtnNewScan
$btnDeepScan.Font = New-Object System.Drawing.Font("Consolas", 10, [System.Drawing.FontStyle]::Bold)
$btnDeepScan.BackColor = [System.Drawing.Color]::FromArgb(30, 80, 150)
$btnDeepScan.ForeColor = [System.Drawing.Color]::Black
$btnDeepScan.FlatStyle = "Flat"
$btnDeepScan.Size = New-Object System.Drawing.Size(100, 35)
$btnDeepScan.Location = New-Object System.Drawing.Point(120, 15)

$btnUninstall = New-Object System.Windows.Forms.Button
$btnUninstall.Text = $script:LangData.BtnUninstall
$btnUninstall.Font = New-Object System.Drawing.Font("Consolas", 10, [System.Drawing.FontStyle]::Bold)
$btnUninstall.BackColor = [System.Drawing.Color]::FromArgb(45, 110, 180)
$btnUninstall.ForeColor = [System.Drawing.Color]::Black
$btnUninstall.FlatStyle = "Flat"
$btnUninstall.Size = New-Object System.Drawing.Size(100, 35)
$btnUninstall.Location = New-Object System.Drawing.Point(230, 15)

$btnCleanTraces = New-Object System.Windows.Forms.Button
$btnCleanTraces.Text = $script:LangData.BtnCleanTraces
$btnCleanTraces.Font = New-Object System.Drawing.Font("Consolas", 10, [System.Drawing.FontStyle]::Bold)
$btnCleanTraces.BackColor = [System.Drawing.Color]::FromArgb(60, 140, 210)
$btnCleanTraces.ForeColor = [System.Drawing.Color]::Black
$btnCleanTraces.FlatStyle = "Flat"
$btnCleanTraces.Size = New-Object System.Drawing.Size(100, 35)
$btnCleanTraces.Location = New-Object System.Drawing.Point(340, 15)

$btnViewLog = New-Object System.Windows.Forms.Button
$btnViewLog.Text = $script:LangData.BtnViewLog
$btnViewLog.Font = New-Object System.Drawing.Font("Consolas", 10, [System.Drawing.FontStyle]::Bold)
$btnViewLog.BackColor = [System.Drawing.Color]::FromArgb(80, 170, 235)
$btnViewLog.ForeColor = [System.Drawing.Color]::Black
$btnViewLog.FlatStyle = "Flat"
$btnViewLog.Size = New-Object System.Drawing.Size(100, 35)
$btnViewLog.Location = New-Object System.Drawing.Point(450, 15)

# --- Language Buttons (Positioned dynamically via listener) ---
$btnLangPT = New-Object System.Windows.Forms.Button
$btnLangPT.Text = "POR"
$btnLangPT.Font = New-Object System.Drawing.Font("Consolas", 7, [System.Drawing.FontStyle]::Bold)
$btnLangPT.BackColor = [System.Drawing.Color]::FromArgb(20, 60, 135)
$btnLangPT.ForeColor = [System.Drawing.Color]::Black
$btnLangPT.FlatStyle = "Flat"
$btnLangPT.Size = New-Object System.Drawing.Size(30, 22)
$btnLangPT.Top = 38
$btnLangPT.Left = 0

$btnLangEN = New-Object System.Windows.Forms.Button
$btnLangEN.Text = "ENG"
$btnLangEN.Font = New-Object System.Drawing.Font("Consolas", 7, [System.Drawing.FontStyle]::Bold)
$btnLangEN.BackColor = [System.Drawing.Color]::FromArgb(45, 105, 175)
$btnLangEN.ForeColor = [System.Drawing.Color]::Black
$btnLangEN.FlatStyle = "Flat"
$btnLangEN.Size = New-Object System.Drawing.Size(30, 22)
$btnLangEN.Top = 38
$btnLangEN.Left = 0

$btnLangES = New-Object System.Windows.Forms.Button
$btnLangES.Text = "ESP"
$btnLangES.Font = New-Object System.Drawing.Font("Consolas", 7, [System.Drawing.FontStyle]::Bold)
$btnLangES.BackColor = [System.Drawing.Color]::FromArgb(70, 150, 215)
$btnLangES.ForeColor = [System.Drawing.Color]::Black
$btnLangES.FlatStyle = "Flat"
$btnLangES.Size = New-Object System.Drawing.Size(30, 22)
$btnLangES.Top = 38
$btnLangES.Left = 0

$actionsPanel.Controls.AddRange(@($btnScan, $btnDeepScan, $btnUninstall, $btnCleanTraces, $btnViewLog, $btnLangPT, $btnLangEN, $btnLangES))

# ==========================================
# 12. Main Content Area (Log Text Box)
# ==========================================
$logTextBox = New-Object System.Windows.Forms.RichTextBox
$logTextBox.ReadOnly = $true
$logTextBox.Dock = "Fill"
$logTextBox.BackColor = [System.Drawing.Color]::FromArgb(20, 20, 20)
$logTextBox.Font = New-Object System.Drawing.Font("Consolas", 8)
$logTextBox.ScrollBars = "Vertical"
$logTextBox.WordWrap = $false
$logTextBox.Text = $script:LangData.LogInitText + [Environment]::NewLine
$logTextBox.Visible = $false

# ============================================================================
# DataGridView - Instantiation
# ============================================================================
$dataGridView = New-Object System.Windows.Forms.DataGridView

# ============================================================================
# DataGridView - Appearance and Styling
# ============================================================================
$dataGridView.Dock = "Fill"
$dataGridView.BackgroundColor = [System.Drawing.Color]::FromArgb(20, 20, 20)
$dataGridView.BorderStyle = "None"
$dataGridView.EnableHeadersVisualStyles = $false

$dataGridView.ColumnHeadersDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(40, 40, 40)
$dataGridView.ColumnHeadersDefaultCellStyle.ForeColor = [System.Drawing.Color]::White
$dataGridView.ColumnHeadersDefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(40, 40, 40)
$dataGridView.ColumnHeadersDefaultCellStyle.SelectionForeColor = [System.Drawing.Color]::White
$dataGridView.ColumnHeadersDefaultCellStyle.Font = New-Object System.Drawing.Font("Consolas", 9, [System.Drawing.FontStyle]::Bold)

$dataGridView.DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(20, 20, 20)
$dataGridView.DefaultCellStyle.ForeColor = [System.Drawing.Color]::LightGray
$dataGridView.DefaultCellStyle.Font = New-Object System.Drawing.Font("Consolas", 9)

$dataGridView.GridColor = [System.Drawing.Color]::FromArgb(60, 60, 60)
$dataGridView.CellBorderStyle = "SingleHorizontal"
$dataGridView.RowTemplate.DefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(80, 80, 80)
$dataGridView.RowTemplate.DefaultCellStyle.SelectionForeColor = [System.Drawing.Color]::White   

# ============================================================================
# DataGridView - Behavior Settings
# ============================================================================
$dataGridView.AllowUserToAddRows = $false
$dataGridView.AllowUserToDeleteRows = $false
$dataGridView.AllowUserToResizeRows = $false
$dataGridView.ReadOnly = $true
$dataGridView.RowHeadersVisible = $false
$dataGridView.SelectionMode = "FullRowSelect"
$dataGridView.MultiSelect = $false
$dataGridView.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::AllCells
$dataGridView.RowTemplate.Height = 35

# ============================================================================
# DataGridView Columns - Creation
# Note: Internal column names are kept exactly as "Nome", "Versao", etc. 
# to preserve object property binding with the Engine output.
# ============================================================================
$colIcon = New-Object System.Windows.Forms.DataGridViewImageColumn
$colIcon.Name = "Icone"
$colIcon.HeaderText = ""
$colIcon.ImageLayout = [System.Windows.Forms.DataGridViewImageCellLayout]::Zoom
$colIcon.Width = 45

$dataGridView.Columns.Add($colIcon) | Out-Null
$dataGridView.Columns.Add("Nome", $script:LangData.ColName) | Out-Null
$dataGridView.Columns.Add("Versao", $script:LangData.ColVersion) | Out-Null
$dataGridView.Columns.Add("Fabricante", $script:LangData.ColManufacturer) | Out-Null
$dataGridView.Columns.Add("Tamanho", $script:LangData.ColSize) | Out-Null
$dataGridView.Columns.Add("TamanhoBytes", "Bytes") | Out-Null
$dataGridView.Columns.Add("Tipo", $script:LangData.ColType) | Out-Null
$dataGridView.Columns.Add("Local", $script:LangData.ColLocation) | Out-Null
$dataGridView.Columns.Add("Status", $script:LangData.ColStatus) | Out-Null

# ============================================================================
# DataGridView Columns - Specific Configurations
# ============================================================================
$dataGridView.Columns["TamanhoBytes"].Visible = $false
$dataGridView.Columns["Nome"].AutoSizeMode = [System.Windows.Forms.DataGridViewAutoSizeColumnMode]::Fill
$dataGridView.Columns["Nome"].MinimumWidth = 150

# ============================================================================
# Context Menu and Right-Click Selection
# ============================================================================
$script:contextMenu = New-Object System.Windows.Forms.ContextMenuStrip
$script:menuOpenFolder = New-Object System.Windows.Forms.ToolStripMenuItem
$script:menuOpenFolder.Name = "menuOpenFolder"
$script:menuOpenFolder.Text = $script:LangData.MenuOpenFolder
$script:menuOpenFolder.Add_Click({
    if ($dataGridView.CurrentRow) {
        $path = $dataGridView.CurrentRow.Cells["Local"].Value
        if (![string]::IsNullOrWhiteSpace($path) -and (Test-Path $path)) {
            Start-Process "explorer.exe" -ArgumentList "`"$path`""
        }
    }
})
$script:contextMenu.Items.Add($script:menuOpenFolder) | Out-Null
$dataGridView.ContextMenuStrip = $script:contextMenu

$dataGridView.Add_CellMouseDown({
    param($sender, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Right) {
        if ($e.RowIndex -ge 0 -and $e.ColumnIndex -ge 0) {
            $dataGridView.CurrentCell = $dataGridView.Rows[$e.RowIndex].Cells[$e.ColumnIndex]
        }
    }
})

# ============================================================================
# Sorting State Tracking Variables
# ============================================================================
$script:lastSortedColumn = $null
$script:lastSortDirection = "Ascending"

# ============================================================================
# DataGridView - Sort Click Event Handling
# ============================================================================
$dataGridView.Add_ColumnHeaderMouseClick({

    $clickedCol = $dataGridView.Columns[$_.ColumnIndex]

    # Map the formatted Size column directly to the hidden Raw Bytes column for correct numeric sorting
    $sortCol =
        if ($clickedCol.Name -eq "Tamanho") {
            $dataGridView.Columns["TamanhoBytes"]
        }
        else {
            $clickedCol
        }

    # Toggle ascending/descending
    if ($script:lastSortedColumn -eq $sortCol) {
        $script:lastSortDirection =
            if ($script:lastSortDirection -eq "Ascending") {
                "Descending"
            }
            else {
                "Ascending"
            }
    }
    else {
        $script:lastSortedColumn = $sortCol
        $script:lastSortDirection = "Ascending"
    }

    # Apply the sort execution
    if ($script:lastSortDirection -eq "Ascending") {
        $dataGridView.Sort($sortCol, [System.ComponentModel.ListSortDirection]::Ascending)
    }
    else {
        $dataGridView.Sort($sortCol, [System.ComponentModel.ListSortDirection]::Descending)
    }
})

# ==========================================
# 13. Footer Panel
# ==========================================
$footerPanel = New-Object System.Windows.Forms.Panel
$footerPanel.Dock = "Bottom"
$footerPanel.Height = 30
$footerPanel.BackColor = [System.Drawing.Color]::FromArgb(20, 20, 20)
$footerPanel.Padding = New-Object System.Windows.Forms.Padding(10, 0, 10, 0)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = $script:LangData.StatusReady
$statusLabel.Font = New-Object System.Drawing.Font("Consolas", 9)
$statusLabel.ForeColor = [System.Drawing.Color]::Gray
$statusLabel.AutoSize = $false
$statusLabel.Dock = "Fill"
$statusLabel.TextAlign = "MiddleLeft"

$footerPanel.Controls.Add($statusLabel)

# ==========================================
# 14. Splash Screen Initialization
# ==========================================
$splashForm = New-Object System.Windows.Forms.Form
$splashForm.FormBorderStyle = "None"
$splashForm.StartPosition = "CenterScreen"
$splashForm.BackColor = [System.Drawing.Color]::FromArgb(15, 15, 15)
$splashForm.Size = New-Object System.Drawing.Size(500, 200)
$splashForm.TopMost = $true
$splashForm.ShowInTaskbar = $false

# Application Icon
$splashIcon = New-Object System.Windows.Forms.PictureBox
$splashIcon.Image = [System.Drawing.Image]::FromFile($(Join-Path $AppRoot "icon.ico"))
$splashIcon.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::StretchImage
$splashIcon.Size = New-Object System.Drawing.Size(48, 48)
$splashIcon.Location = New-Object System.Drawing.Point(30, 35)

# Title
$splashTitle = New-Object System.Windows.Forms.Label
$splashTitle.Text = $script:LangData.SplashTitle
$splashTitle.Font = New-Object System.Drawing.Font("Consolas", 24, [System.Drawing.FontStyle]::Bold)
$splashTitle.ForeColor = [System.Drawing.Color]::FromArgb(0, 191, 255)
$splashTitle.AutoSize = $true
$splashTitle.Location = New-Object System.Drawing.Point(90, 40)

# Subtitle
$splashSubTitle = New-Object System.Windows.Forms.Label
$splashSubTitle.Text = $script:LangData.SplashAnalyze
$splashSubTitle.Font = New-Object System.Drawing.Font("Consolas", 10)
$splashSubTitle.ForeColor = [System.Drawing.Color]::Gray
$splashSubTitle.AutoSize = $true
$splashSubTitle.Location = New-Object System.Drawing.Point(32, 95)

# Status Log
$splashLogLabel = New-Object System.Windows.Forms.Label
$splashLogLabel.Text = $script:LangData.SplashInit
$splashLogLabel.Font = New-Object System.Drawing.Font("Consolas", 8)
$splashLogLabel.ForeColor = [System.Drawing.Color]::DimGray
$splashLogLabel.AutoSize = $false
$splashLogLabel.Size = New-Object System.Drawing.Size(440, 25)
$splashLogLabel.Location = New-Object System.Drawing.Point(30, 140)

$splashForm.Controls.AddRange(@($splashIcon, $splashTitle, $splashSubTitle, $splashLogLabel))

# Global function mapping to update Splash Screen dynamically from the Engine
$Global:Un1LogAction = {
    param($message)
    $splashLogLabel.Text = $message
    $splashForm.Refresh()
    [System.Windows.Forms.Application]::DoEvents()
}

# ==========================================
# 15. Dynamic Language Update Implementation
# ==========================================
function Update-UILanguage {
    $L = $script:LangData
    
    $form.Text = $L.Title
    $titleLabel.Text = $L.Title
    $versionLabel.Text = $L.Version
    
    $btnScan.Text = $L.BtnScanList
    $btnDeepScan.Text = $L.BtnNewScan
    $btnUninstall.Text = $L.BtnUninstall
    $btnCleanTraces.Text = $L.BtnCleanTraces
    $btnViewLog.Text = $L.BtnViewLog
    $btnHelp.Text = $L.BtnHelp
    $btnAbout.Text = $L.BtnAbout
    
    $dataGridView.Columns["Nome"].HeaderText = $L.ColName
    $dataGridView.Columns["Versao"].HeaderText = $L.ColVersion
    $dataGridView.Columns["Fabricante"].HeaderText = $L.ColManufacturer
    $dataGridView.Columns["Tamanho"].HeaderText = $L.ColSize
    $dataGridView.Columns["Tipo"].HeaderText = $L.ColType
    $dataGridView.Columns["Local"].HeaderText = $L.ColLocation
    $dataGridView.Columns["Status"].HeaderText = $L.ColStatus
    
    if ($null -ne $script:menuOpenFolder) {
        $script:menuOpenFolder.Text = $L.MenuOpenFolder
    }

    $splashTitle.Text = $L.SplashTitle
    $splashSubTitle.Text = $L.SplashAnalyze
    $splashLogLabel.Text = $L.SplashInit
    
    $statusLabel.Text = $L.StatusReady
    $form.Refresh()
}

# ==========================================
# 16. Core Scan Execution Logic
# ==========================================
function Update-Grid {
    $L = $script:LangData
    $splashForm.Show()
    $splashForm.Refresh()
    [System.Windows.Forms.Application]::DoEvents()
    
    try {
        & $Global:Un1LogAction $L.Phase1
        $scanResult = Get-Un1nst4ll3rScan
        
        & $Global:Un1LogAction $L.Phase2
        $deepResult = Get-Un1nst4ll3rDeepSize -ProgramList $scanResult
        
        # Finally, measure size for EVERY mapped item (Registry + Orphans)
        & $Global:Un1LogAction $L.Phase3
        $deepResult = Get-Un1nst4ll3rSizeEngine -ProgramList $deepResult
        
        & $Global:Un1LogAction $L.PhaseExport
        $deepResult | ConvertTo-Json -Depth 8 | Out-File -FilePath $script:jsonPath -Encoding UTF8        
        
        & $Global:Un1LogAction $L.PhaseGrid
        Load-GridFromJson -Path $script:jsonPath
    }    
    catch {
        $statusLabel.Text = "Error during scan."
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Error", "OK", "Error")
    }
    finally {
        $splashForm.Hide()
    }
}

# ==========================================
# 17. JSON Data Loader Logic
# ==========================================
function Load-GridFromJson{
    param([string]$Path)
    $L = $script:LangData
    
    if (!(Test-Path $Path)) {
        $statusLabel.Text = $L.StatusNoCache
        return $false
    }

    # Ensure memory shortcuts are loaded prior to rendering icons
    if ($null -eq $Global:MemoryShortcuts -or $Global:MemoryShortcuts.Count -eq 0) {
        $Global:MemoryShortcuts = Get-Un1nst4ll3rShortcutCache
    }

    try {
        $statusLabel.Text = $L.StatusLoadingCache
        $form.Refresh()

        $jsonRaw = Get-Content -Path $Path -Raw -Encoding UTF8
        $data = ConvertFrom-Json -InputObject $jsonRaw

        foreach ($row in $dataGridView.Rows) {
            if ($null -ne $row.Cells["Icone"].Value -and $row.Cells["Icone"].Value -is [System.Drawing.Image]) {
                $row.Cells["Icone"].Value.Dispose()
            }
        }

        $dataGridView.Rows.Clear()
        $orphanCount = 0

        foreach ($app in $data) {
            $rowIndex = $dataGridView.Rows.Add()
            $row = $dataGridView.Rows[$rowIndex]
            
            # Garante que se a propriedade não existir no JSON velho, vire um array vazio em vez de null
            $scIcons = @($app.ShortcutIconLocations)

            $appIcon = Get-Un1nst4ll3rAppIcon -AppName $app.Nome -IconPath $app.DisplayIcon -ExePath $app.ExePath -InstallLocal $app.Local -Chave $app.Chave -ShortcutIconLocations $scIcons
            $row.Cells["Icone"].Value = $appIcon           
            $row.Cells["Nome"].Value = $app.Nome
            $row.Cells["Versao"].Value = $app.Versao
            $row.Cells["Fabricante"].Value = $app.Fabricante

            # Formatting raw bytes into readable capacities (GB/MB/KB)
            $bytes = $app.Tamanho
            if ($null -ne $bytes -and $bytes -gt 0) {
                $row.Cells["TamanhoBytes"].Value = [long]$bytes
                if ($bytes -ge 1GB) { $sizeStr = "{0:N2} GB" -f ($bytes / 1GB) }
                elseif ($bytes -ge 1MB) { $sizeStr = "{0:N2} MB" -f ($bytes / 1MB) }
                elseif ($bytes -ge 1KB) { $sizeStr = "{0:N2} KB" -f ($bytes / 1KB) }
                else { $sizeStr = "$bytes Bytes" }
                $row.Cells["Tamanho"].Value = $sizeStr
            } else {
                $row.Cells["TamanhoBytes"].Value = [long]0
                $row.Cells["Tamanho"].Value = $script:LangData.SizeNA
            }

            $row.Cells["Tipo"].Value = $app.Tipo
            $row.Cells["Local"].Value = $app.Local
            
            # Map technical statuses to Language File equivalents
            $translatedStatus = $app.Status
            if ($app.Status -eq "Orphan") { $translatedStatus = $script:LangData.StatusOrphan }
            elseif ($app.Status -eq "NoLocation") { $translatedStatus = $script:LangData.StatusNoLocation }
            elseif ($app.Status -eq "System") { $translatedStatus = $script:LangData.StatusSystem }

            $row.Cells["Status"].Value = $translatedStatus
            
            # Highlight orphans with red text
            if ($app.Status -eq "Orphan") {
                $row.DefaultCellStyle.ForeColor = [System.Drawing.Color]::FromArgb(255, 80, 80)
                $orphanCount++
            }       
         }
        
        # Pre-Sort Default Setup (Ascending by Name)
        $script:lastSortedColumn = $dataGridView.Columns["Nome"]
        $script:lastSortDirection = "Ascending"
        $dataGridView.Sort($script:lastSortedColumn, [System.ComponentModel.ListSortDirection]::Ascending)

        $orphanStr = if($orphanCount -gt 0){ $L.StatusOrphanAlert -f $orphanCount } else { "" }
        $statusLabel.Text = $L.StatusCacheLoaded -f $data.Count, $orphanStr
        return $true
    }
    catch {
        $statusLabel.Text = $L.StatusCacheError
        [System.Windows.Forms.MessageBox]::Show(($L.StatusCacheParseError -f $_.Exception.Message), "Error", "OK", "Error")
        return $false
    }
}

function Get-Un1nst4ll3rJsonCacheData {
    if (!(Test-Path $script:jsonPath)) { return @() }

    $jsonRaw = Get-Content -Path $script:jsonPath -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($jsonRaw)) { return @() }

    return @((ConvertFrom-Json -InputObject $jsonRaw))
}

function Save-Un1nst4ll3rJsonCacheData {
    param([array]$Data)

    ConvertTo-Json -InputObject @($Data) -Depth 8 | Out-File -FilePath $script:jsonPath -Encoding UTF8
}

function Find-Un1nst4ll3rJsonAppRecord {
    param(
        [array]$CacheData,
        [System.Windows.Forms.DataGridViewRow]$GridRow
    )

    if ($null -eq $GridRow) { return $null }

    $selectedName = [string]$GridRow.Cells["Nome"].Value
    $selectedType = [string]$GridRow.Cells["Tipo"].Value
    $selectedLocal = [string]$GridRow.Cells["Local"].Value

    $matches = @($CacheData | Where-Object { $_.Nome -eq $selectedName })
    if ($matches.Count -gt 1 -and ![string]::IsNullOrWhiteSpace($selectedType)) {
        $typedMatches = @($matches | Where-Object { $_.Tipo -eq $selectedType })
        if ($typedMatches.Count -gt 0) { $matches = $typedMatches }
    }
    if ($matches.Count -gt 1 -and ![string]::IsNullOrWhiteSpace($selectedLocal)) {
        $localMatches = @($matches | Where-Object { $_.Local -eq $selectedLocal })
        if ($localMatches.Count -gt 0) { $matches = $localMatches }
    }

    return ($matches | Select-Object -First 1)
}

function Remove-Un1nst4ll3rJsonAppRecord {
    param(
        [array]$CacheData,
        [System.Windows.Forms.DataGridViewRow]$GridRow
    )

    if ($null -eq $GridRow) { return @($CacheData) }

    $selectedName = [string]$GridRow.Cells["Nome"].Value
    $selectedType = [string]$GridRow.Cells["Tipo"].Value
    $selectedLocal = [string]$GridRow.Cells["Local"].Value
    $removed = $false
    $remaining = [System.Collections.ArrayList]::new()

    foreach ($item in @($CacheData)) {
        $sameName = ($item.Nome -eq $selectedName)
        $sameType = ([string]::IsNullOrWhiteSpace($selectedType) -or $item.Tipo -eq $selectedType)
        $sameLocal = ([string]::IsNullOrWhiteSpace($selectedLocal) -or $item.Local -eq $selectedLocal)

        if (!$removed -and $sameName -and $sameType -and $sameLocal) {
            $removed = $true
            continue
        }

        [void]$remaining.Add($item)
    }

    return @($remaining.ToArray())
}

# ==========================================
# 18. Interface Event Bindings
# ==========================================
$btnScan.Add_Click({
    $logTextBox.Visible = $false
    $dataGridView.Visible = $true
})

$btnDeepScan.Add_Click({
    Update-Grid
})

 $btnUninstall.Add_Click({
    if ($null -eq $dataGridView.CurrentRow) { return }

    $cacheData = Get-Un1nst4ll3rJsonCacheData
    $AppData = Find-Un1nst4ll3rJsonAppRecord -CacheData $cacheData -GridRow $dataGridView.CurrentRow
    if ($null -eq $AppData) {
        $statusLabel.Text = $script:LangData.StatusCacheError
        return
    }

    # Calcula a posição: Canto inferior DIREITO do form principal
    # Largura do form menos a largura da janelinha do spinner (360) e uma margem (10)
    $spinnerPosX = $form.Location.X + $form.Width - 380 - 10
    $spinnerPosY = $form.Location.Y + $form.Height - 100 - 20 
    $spinnerPos = New-Object System.Drawing.Point($spinnerPosX, $spinnerPosY)

    # Inicia o Spinner
    Start-Un1nst4ll3rSpinner -InitialMessage "Preparando desinstalação..." -Location $spinnerPos

    try {
        Update-Un1nst4ll3rSpinner -Message "Desinstalando $($AppData.Nome)..."
        
        $params = @{
            AppName                   = $AppData.Nome
            UninstallStringValue      = $AppData.UninstallString
            QuietUninstallStringValue = $AppData.QuietUninstallString
            ProgramType               = $AppData.Tipo
            AppIdentifier             = $AppData.Chave
        }
        $UninstallResult = Start-Un1nst4ll3rApp @params

        if (!$UninstallResult) {
            $statusLabel.Text = $script:LangData.UninstallCancelled
            return # O Finally abaixo vai fechar o Spinner
        }

        Update-Un1nst4ll3rSpinner -Message "Verificando vestígios..."
        $uninstallCompleted = Test-Un1nst4ll3rUninstallCompleted -App $AppData
        if (!$uninstallCompleted) {
            $statusLabel.Text = $script:LangData.StatusReady
            [System.Windows.Forms.MessageBox]::Show(($script:LangData.MsgUninstallNotCompleted -f $AppData.Nome), $script:LangData.Title, "OK", "Warning")
            return
        }

        Update-Un1nst4ll3rSpinner -Message "Limpando vestígios e registros..."
        # Passa o cache completo para o motor verificar pastas compartilhadas (Shared Roots)
        $cleanedCount = Remove-Un1nst4ll3rTraces -App $AppData -InstalledApps $cacheData
        
        Update-Un1nst4ll3rSpinner -Message "Atualizando lista de aplicativos..."
        $statusLabel.Text = $script:LangData.StatusRefreshingCache
        $updatedCache = Remove-Un1nst4ll3rJsonAppRecord -CacheData $cacheData -GridRow $dataGridView.CurrentRow
        Save-Un1nst4ll3rJsonCacheData -Data $updatedCache
        Load-GridFromJson -Path $script:jsonPath | Out-Null
        
        $statusLabel.Text = $script:LangData.StatusUninstallComplete -f $AppData.Nome, $cleanedCount

    } finally {
        # Garante que o spinner feche, mesmo se der erro no meio
        Stop-Un1nst4ll3rSpinner
    }
})

$btnCleanTraces.Add_Click({
    [System.Windows.Forms.MessageBox]::Show($script:LangData.MsgCleanFuture, "CLEAN TRACES", "OK", "Information")
})

$btnViewLog.Add_Click({
    if ($null -ne $Global:Un1AnalysisLog -and $Global:Un1AnalysisLog.Count -gt 0) {
        
        $logTextBox.SuspendLayout() # Pause rendering to prevent flickering
        $logTextBox.Clear()
        
        foreach ($entry in $Global:Un1AnalysisLog) {
            # Focus on the end of the current block
            $logTextBox.SelectionStart = $logTextBox.TextLength
            $logTextBox.SelectionLength = 0

            # Retro-compatibility checks for older log array structure
            $ts = if ($entry.PSObject.Properties.Name -contains 'Timestamp') { $entry.Timestamp } else { ($entry.Text -split ' ')[0] }
            $cat = if ($entry.PSObject.Properties.Name -contains 'Category') { $entry.Category } else { ($entry.Text -split ' ')[1] }
            $msg = if ($entry.PSObject.Properties.Name -contains 'Message') { $entry.Message } else { $entry.Text }

            # Convert string color name (e.g. "Cyan") into .NET Drawing Color
            $drawColor = [System.Drawing.Color]::FromName($entry.Color)
            if ($drawColor.IsEmpty) { $drawColor = [System.Drawing.Color]::LightGray }

            # Inject timestamps and brackets in neutral colors
            $logTextBox.SelectionColor = [System.Drawing.Color]::WhiteSmoke
            $logTextBox.AppendText("$ts ")
            $logTextBox.AppendText("[$cat] ")

            # Inject the actual message text mapped to the determined color
            $logTextBox.SelectionColor = $drawColor
            $logTextBox.AppendText("$msg`r`n")
        }
        
        $logTextBox.ResumeLayout()
        
        # Scroll down automatically
        $logTextBox.SelectionStart = $logTextBox.Text.Length
        $logTextBox.ScrollToCaret()
    } else {
        $logTextBox.Text = $script:LangData.StatusNoLog
    }
    
    # Toggle View Layer: Hide DataGrid, Reveal RichTextBox Log
    $dataGridView.Visible = $false
    $logTextBox.Visible = $true
    $statusLabel.Text = $script:LangData.StatusShowingLog
}) 

# --- Language Swap Triggers ---
$btnLangPT.Add_Click({
    $script:CurrentLang = "pt-BR"
    $script:LangData = $script:LangFullObject.$script:CurrentLang
    Update-UILanguage
})

$btnLangEN.Add_Click({
    $script:CurrentLang = "en-US"
    $script:LangData = $langObj.$script:CurrentLang
    Update-UILanguage
})

$btnLangES.Add_Click({
    $script:CurrentLang = "es-ES"
    $script:LangData = $langObj.$script:CurrentLang
    Update-UILanguage
})

# --- Help Button Click Event ---
 $btnHelp.Add_Click({
    $readmeFile = switch ($script:CurrentLang) {
        "pt-BR" { "README_POR.md" }
        "es-ES" { "README_ES.md" }
        default { "README.md" }
    }
    $readmePath = Join-Path $AppRoot $readmeFile
    if (!(Test-Path $readmePath)) {
        [System.Windows.Forms.MessageBox]::Show("README not found in $AppRoot", "Error", "OK", "Error")
        return
    }

    $helpForm = New-Object System.Windows.Forms.Form
    $helpForm.Text = "Un1nst4ll3r - Documentation"
    $helpForm.Size = New-Object System.Drawing.Size(800, 600)
    $helpForm.StartPosition = "CenterParent"
    $helpForm.BackColor = [System.Drawing.Color]::FromArgb(18, 18, 18)
    $helpForm.Icon = $form.Icon

    # Lê o Markdown como texto puro
    $mdText = Get-Content -Path $readmePath -Raw -Encoding UTF8
    $htmlBody = ""

    # Verifica se o Markdig (que já carregou na Seção 4) está disponível
    $markdigAssembly = [AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.FullName -match "Markdig" } | Select-Object -First 1
    
    if ($markdigAssembly) {
        try {
            # Converte Markdown para HTML usando o Markdig
            $markdownType = $markdigAssembly.GetType("Markdig.Markdown")
            $htmlBody = $markdownType::ToHtml($mdText)
        } catch {
            # Fallback caso o Markdig falhe
            $htmlBody = "<pre style='white-space: pre-wrap;'>$mdText</pre>"
        }
    } else {
        # Fallback se o Markdig não tiver carregado
        $htmlBody = "<pre style='white-space: pre-wrap;'>$mdText</pre>"
    }

    # Cria o WebBrowser para exibir o HTML
    $contentBox = New-Object System.Windows.Forms.WebBrowser
    $contentBox.Dock = "Fill"
    
    # HTML com CSS ajustado para Emojis Coloridos e Fonte de Leitura
    $styledHtml = @"
<!DOCTYPE html>
<html>
<head>
<meta http-equiv="X-UA-Compatible" content="IE=edge">
<style>
  body { 
    background-color: #1E1E1E; 
    color: #D4D4D4; 
    font-family: Consolas, 'Segoe UI Emoji', Tahoma, sans-serif;
    padding: 20px; 
    margin: 0; 
  }
  a { color: #569CD6; }
  code { 
    background-color: #2D2D2D; 
    padding: 2px 5px; 
    border-radius: 3px; 
    font-family: Consolas, monospace; /* Códigos continuam com fonte de terminal */
  }
  pre { 
    background-color: #2D2D2D; 
    padding: 10px; 
    border-radius: 5px; 
    overflow-x: auto; 
  }
  pre code { 
    background-color: transparent; 
    padding: 0; 
    font-family: Consolas, monospace;
  }
  h1, h2, h3 { color: #00BFFF; border-bottom: 1px solid #333; padding-bottom: 5px; }
  blockquote { border-left: 4px solid #569CD6; padding-left: 10px; color: #9CDCFE; margin-left: 0; }
  table { border-collapse: collapse; width: 100%; }
  th, td { border: 1px solid #444; padding: 8px; text-align: left; }
  th { background-color: #2D2D2D; }
  img { max-width: 100%; height: auto; }
</style>
</head>
<body>
 $htmlBody
</body>
</html>
"@

    $contentBox.DocumentText = $styledHtml

    $helpForm.Controls.Add($contentBox)
    $helpForm.ShowDialog()
})

# --- About Button Click Event ---
$btnAbout.Add_Click({
    $aboutForm = New-Object System.Windows.Forms.Form
    $aboutForm.Text = $script:LangData.BtnAbout
    $aboutForm.Size = New-Object System.Drawing.Size(420, 280)
    $aboutForm.StartPosition = "CenterParent"
    $aboutForm.FormBorderStyle = "FixedDialog"
    $aboutForm.MaximizeBox = $false
    $aboutForm.MinimizeBox = $false
    $aboutForm.BackColor = [System.Drawing.Color]::FromArgb(25, 25, 25)
    $aboutForm.ForeColor = [System.Drawing.Color]::White
    $aboutForm.Icon = $form.Icon
    $aboutForm.Opacity = 1

    # Gradient Background Drawing
    $aboutForm.Add_Paint({
        param($sender, $e)
        $rect = $sender.ClientRectangle
        $color1 = [System.Drawing.Color]::FromArgb(25, 25, 25)
        $color2 = [System.Drawing.Color]::FromArgb(45, 55, 65) # Subtle deep blue-gray fade
        $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, $color1, $color2, [System.Drawing.Drawing2D.LinearGradientMode]::Vertical)
        $e.Graphics.FillRectangle($brush, $rect)
        $brush.Dispose()
    })

    $logo = New-Object System.Windows.Forms.PictureBox
    $logo.Image = [System.Drawing.Image]::FromFile($(Join-Path $AppRoot "icon.ico"))
    $logo.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::StretchImage
    $logo.Size = New-Object System.Drawing.Size(64, 64)
    $logo.Location = New-Object System.Drawing.Point(30, 30)
    $logo.BackColor = [System.Drawing.Color]::Transparent

    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = $script:LangData.Title
    $lblTitle.Font = New-Object System.Drawing.Font("Consolas", 18, [System.Drawing.FontStyle]::Bold)
    $lblTitle.ForeColor = [System.Drawing.Color]::FromArgb(0, 191, 255)
    $lblTitle.Location = New-Object System.Drawing.Point(110, 35)
    $lblTitle.AutoSize = $true
    $lblTitle.BackColor = [System.Drawing.Color]::Transparent

    $lblVer = New-Object System.Windows.Forms.Label
    $lblVer.Text = $script:LangData.Version
    $lblVer.Font = New-Object System.Drawing.Font("Consolas", 9)
    $lblVer.ForeColor = [System.Drawing.Color]::Gray
    $lblVer.Location = New-Object System.Drawing.Point(112, 70)
    $lblVer.AutoSize = $true
    $lblVer.BackColor = [System.Drawing.Color]::Transparent

    $lblInfo = New-Object System.Windows.Forms.Label
    $lblInfo.Text = "A high-performance system scanner and uninstaller.`nDeep discovery of orphans and legacy traces."
    $lblInfo.Font = New-Object System.Drawing.Font("Consolas", 9)
    $lblInfo.ForeColor = [System.Drawing.Color]::LightGray
    $lblInfo.Location = New-Object System.Drawing.Point(30, 115)
    $lblInfo.Size = New-Object System.Drawing.Size(360, 50)
    $lblInfo.TextAlign = "MiddleCenter"
    $lblInfo.BackColor = [System.Drawing.Color]::Transparent

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = "CLOSE"
    $btnClose.FlatStyle = "Flat"
    $btnClose.BackColor = [System.Drawing.Color]::FromArgb(40, 40, 40)
    $btnClose.ForeColor = [System.Drawing.Color]::White
    $btnClose.Size = New-Object System.Drawing.Size(100, 35)
    $btnClose.Location = New-Object System.Drawing.Point(160, 190)
    $btnClose.DialogResult = [System.Windows.Forms.DialogResult]::OK

    $aboutForm.Controls.AddRange(@($logo, $lblTitle, $lblVer, $lblInfo, $btnClose))
    $aboutForm.ShowDialog($form)
})


# ==========================================
# 19. Form Boot Sequence
# ==========================================
$form.Add_Shown({
    $form.WindowState = [System.Windows.Forms.FormWindowState]::Minimized
    Update-Grid
    $statusLabel.Text = $script:LangData.StatusReadyClick
    $form.WindowState = [System.Windows.Forms.FormWindowState]::Maximized
})

# ==========================================
# 20. Layer Assembly and Render Preparation
# ==========================================
$form.Controls.Add($logTextBox)
$form.Controls.Add($dataGridView)
$form.Controls.Add($actionsPanel)
$form.Controls.Add($headerPanel)
$form.Controls.Add($footerPanel)

# ==========================================
# 21. Resize Listener (Manual Right-Docking)
# ==========================================
$repositionButtons = {
    $marginRight = 10
    $btnGap = 5
    
    # 1. Reposition Language Buttons (Actions Panel)
    $actWidth = $actionsPanel.ClientSize.Width
    $langWidth = 30
    
    $btnLangES.Left = $actWidth - $langWidth - $marginRight
    $btnLangEN.Left = $btnLangES.Left - $langWidth - $btnGap
    $btnLangPT.Left = $btnLangEN.Left - $langWidth - $btnGap

    # 2. Reposition Help/About Buttons (Header Panel)
    # Fixed: Use headerPanel width instead of actionsPanel width
    $headWidth = $headerPanel.ClientSize.Width
    $headBtnWidth = 55
    
    $btnAbout.Left = $headWidth - $headBtnWidth - $marginRight
    $btnHelp.Left  = $btnAbout.Left - $headBtnWidth - $btnGap
}

# Attach to the resize event handlers of both relevant panels
$actionsPanel.Add_Resize($repositionButtons)
$headerPanel.Add_Resize($repositionButtons)

# Force a pre-calculation call before displaying the GUI
& $repositionButtons

# ==========================================
# 22. Launch Application
# ==========================================
[void]$form.ShowDialog()
