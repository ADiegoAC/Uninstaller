# ======================================================================
#  Un1nst4ll3r - Motor de Varredura (Módulo)
#  Versão: 4.1 (English Standardized Output)
# ======================================================================

# Força o terminal do Windows a usar UTF-8 para exibir acentos corretamente no console
#[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
#[Console]::InputEncoding = [System.Text.Encoding]::UTF8
 #$OutputEncoding = [System.Text.Encoding]::UTF8

# Compatibilidade PowerShell 7: Carrega o módulo Appx via Windows PowerShell
if ($PSVersionTable.PSVersion.Major -ge 7) {
    try {
        Import-Module Appx -UseWindowsPowerShell -WarningAction SilentlyContinue -ErrorAction Stop
    } catch {
        Write-Warning "Falha ao carregar o módulo Appx via compatibilidade. O scan AppX pode falhar."
    }
}

# Inicializa o acumulador global de logs de depuração
 $Global:Un1AnalysisLog = [System.Text.StringBuilder]::new()

function Write-Un1Log {
    param (
        [string]$Category = "INFO",
        [string]$Message, 
        [string]$Color = "Gray"
    )
    
    $timestamp = Get-Date -Format "HH:mm:ss.fff"
    $formattedMessage = "$timestamp [$Category] $Message"
    
    # Exibe no terminal com cores
    #Write-Host $formattedMessage -ForegroundColor $Color 
    
    # Alimenta a memória para a interface ler
    if ($null -ne $Global:Un1AnalysisLog) {
        [void]$Global:Un1AnalysisLog.AppendLine($formattedMessage)
    }
    
    # Atualiza a SplashScreen da UI automaticamente, se existir
    if ($null -ne $Global:Un1LogAction) { 
        & $Global:Un1LogAction $Message 
    }
}

# ==========================================
# BLOCO AUXILIAR: Cache de Atalhos na Memória
# ==========================================
function Get-Un1nst4ll3rShortcutCache {
    Write-Un1Log -Category "SHORTCUT" -Message "Building rich shortcut cache..." -Color Cyan
    $shortcutCache = [System.Collections.ArrayList]::new()
    $shell = New-Object -ComObject WScript.Shell

    $userShellPaths = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -ErrorAction SilentlyContinue
    $machineShellPaths = Get-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -ErrorAction SilentlyContinue

    $rawPaths = @(
        $userShellPaths.Desktop, 
        $userShellPaths.Programs,
        $userShellPaths.Startup,
        $machineShellPaths.'Common Desktop', 
        $machineShellPaths.'Common Programs',
        $machineShellPaths.'Common Startup'
    )

    $validPaths = $rawPaths | Where-Object { ![string]::IsNullOrWhiteSpace($_) } | 
                              ForEach-Object { [System.Environment]::ExpandEnvironmentVariables($_) } | 
                              Select-Object -Unique

    foreach ($path in $validPaths) {
        if (Test-Path $path) {
            $lnks = Get-ChildItem -Path $path -Filter "*.lnk" -Recurse -ErrorAction SilentlyContinue
            foreach ($lnk in $lnks) {
                try {
                    $shortcut = $shell.CreateShortcut($lnk.FullName)
                    $target = $shortcut.TargetPath
                    if (![string]::IsNullOrWhiteSpace($target)) {
                        $shortcutCache.Add([PSCustomObject]@{
                            LnkName      = $lnk.BaseName
                            Target       = $target
                            WorkingDir   = $shortcut.WorkingDirectory
                            IconLocation = $shortcut.IconLocation
                        }) | Out-Null
                    }
                } catch {}
            }
        }
    }
    
    Write-Un1Log -Category "SHORTCUT" -Message "Cache complete. $($shortcutCache.Count) shortcuts mapped." -Color Green
    return $shortcutCache
}

# ==========================================
# BLOCO AUXILIAR: Heurística de EXE Principal
# ==========================================
function Find-Un1nst4ll3rMainExe {
    param (
        [string]$Path,
        [string]$AppName = "",
        [string]$UninstallExeName = ""
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or !(Test-Path $Path -PathType Container)) { return "" }

    $blackListPatterns = @('^uninstall', '^unins\d+', '^setup', 'update$', 'helper$', 'crash$', 'config$', 'cert$', 'license$', 'daemon$', '-uninstall\.exe$')
    $utilityBlacklist = @('^7z$', '^7za$', '^7zr$', '^unrar$', '^zip$')

    $safeAppName = $AppName -replace '\(.*\)', '' -replace '\s+\d+.*', '' -replace '[^\w\s\-+]', ''
    $safeAppName = $safeAppName.Trim()
    $genericWords = @("microsoft", "corporation", "inc", "ltda", "the", "launcher", "update", "service", "framework", "runtime", "helper", "media", "player", "professional", "edition", "free", "viewer", "system")
    $appWords = @($safeAppName -split '\s+' | Where-Object { $_ -notin $genericWords -and $_.Length -gt 1 })
    $firstKeyword = if ($appWords.Count -gt 0) { $appWords[0] } else { $safeAppName }

    $folderKeyword = (Split-Path $Path -Leaf) -replace '[\d\.]+', '' -replace '\s+', ''
    
    Write-Un1Log -Category "EXE-FIND" -Message "Keywords: App='$firstKeyword' | Folder='$folderKeyword' | Block='$UninstallExeName'" -Color DarkGray

    $searchPath = Join-Path $Path "*"

    # 1. Procura na Raiz
    $rootExes = Get-ChildItem -Path $searchPath -Filter "*.exe" -File -ErrorAction SilentlyContinue
    if ($rootExes.Count -gt 0) {
        Write-Un1Log -Category "EXE-FIND" -Message "Root search: Found $($rootExes.Count) executables. Filtering..." -Color DarkGray
        
        $validExes = @($rootExes | Where-Object {
            $isBlacklisted = $false
            if (![string]::IsNullOrWhiteSpace($UninstallExeName) -and $_.Name -eq $UninstallExeName) { $isBlacklisted = $true }
            if (!$isBlacklisted) { foreach ($pattern in $blackListPatterns) { if ($_.Name -match $pattern) { $isBlacklisted = $true; break } } }
            if (!$isBlacklisted) { foreach ($pattern in $utilityBlacklist) { if ($_.BaseName -match $pattern) { $isBlacklisted = $true; break } } }
            -not $isBlacklisted
        })

        if ($validExes.Count -eq 0 -and $rootExes.Count -gt 0) {
             $validExes = @($rootExes | Where-Object {
                $isBlacklisted = $false
                if (![string]::IsNullOrWhiteSpace($UninstallExeName) -and $_.Name -eq $UninstallExeName) { $isBlacklisted = $true }
                foreach ($pattern in $utilityBlacklist) { if ($_.BaseName -match $pattern) { $isBlacklisted = $true; break } }
                -not $isBlacklisted
            })
        }

        if ($validExes.Count -gt 0) {
            $mainExe = $null
            if ($AppName -like "*Python*") { $mainExe = $validExes | Where-Object { $_.Name -eq "python.exe" -or $_.Name -eq "pythonw.exe" } | Select-Object -First 1 }
            if (!$mainExe) {
                $mainExe = $validExes | Where-Object { $_.BaseName -eq $firstKeyword } | Select-Object -First 1
                if (!$mainExe) { $mainExe = $validExes | Where-Object { $_.BaseName -like "*$firstKeyword*" } | Select-Object -First 1 }
                if (!$mainExe) { $mainExe = $validExes | Where-Object { $firstKeyword -like "*$($_.BaseName)*" } | Select-Object -First 1 }
                if (!$mainExe -and ![string]::IsNullOrWhiteSpace($folderKeyword)) { $mainExe = $validExes | Where-Object { $_.BaseName -like "*$folderKeyword*" } | Select-Object -First 1 }
                if (!$mainExe) { $mainExe = $validExes | Sort-Object { $_.BaseName.Length } | Select-Object -First 1 }
            }
            Write-Un1Log -Category "EXE-FIND" -Message "Root search: Selected -> $($mainExe.Name)" -Color Green
            return $mainExe.FullName
        }
    }

    # 2. Subpastas
    $subDirs = Get-ChildItem -Path $Path -Directory -ErrorAction SilentlyContinue
    if ($subDirs.Count -eq 0) { return "" }

    $priorityNames = @("bin")
    if (![string]::IsNullOrWhiteSpace($firstKeyword)) { $priorityNames += $firstKeyword.ToLower() }

    $dirsToCheck = @()
    $dirsToCheck += $subDirs | Where-Object { $priorityNames -contains $_.Name.ToLower() }
    $dirsToCheck += $subDirs | Where-Object { $priorityNames -notcontains $_.Name.ToLower() }

    foreach ($dir in $dirsToCheck) {
        $subSearchPath = Join-Path $dir.FullName "*"
        $subExes = Get-ChildItem -Path $subSearchPath -Filter "*.exe" -File -ErrorAction SilentlyContinue
        if ($subExes.Count -gt 0) {
            Write-Un1Log -Category "EXE-FIND" -Message "Subfolder '$($dir.Name)': Found $($subExes.Count) executables. Filtering..." -Color DarkGray
            
            $validSubExes = @($subExes | Where-Object {
                $isBlacklisted = $false
                if (![string]::IsNullOrWhiteSpace($UninstallExeName) -and $_.Name -eq $UninstallExeName) { $isBlacklisted = $true }
                if (!$isBlacklisted) { foreach ($pattern in $blackListPatterns) { if ($_.Name -match $pattern) { $isBlacklisted = $true; break } } }
                if (!$isBlacklisted) { foreach ($pattern in $utilityBlacklist) { if ($_.BaseName -match $pattern) { $isBlacklisted = $true; break } } }
                -not $isBlacklisted
            })

            if ($validSubExes.Count -eq 0 -and $subExes.Count -gt 0) {
                 $validSubExes = @($subExes | Where-Object {
                    $isBlacklisted = $false
                    if (![string]::IsNullOrWhiteSpace($UninstallExeName) -and $_.Name -eq $UninstallExeName) { $isBlacklisted = $true }
                    foreach ($pattern in $utilityBlacklist) { if ($_.BaseName -match $pattern) { $isBlacklisted = $true; break } }
                    -not $isBlacklisted
                })
            }

            if ($validSubExes.Count -gt 0) {
                $mainExe = $null
                if ($AppName -like "*Python*") { $mainExe = $validSubExes | Where-Object { $_.Name -eq "python.exe" -or $_.Name -eq "pythonw.exe" } | Select-Object -First 1 }
                if (!$mainExe) {
                    $mainExe = $validSubExes | Where-Object { $_.BaseName -eq $firstKeyword } | Select-Object -First 1
                    if (!$mainExe) { $mainExe = $validSubExes | Where-Object { $_.BaseName -like "*$firstKeyword*" } | Select-Object -First 1 }
                    if (!$mainExe) { $mainExe = $validSubExes | Where-Object { $firstKeyword -like "*$($_.BaseName)*" } | Select-Object -First 1 }
                    if (!$mainExe -and ![string]::IsNullOrWhiteSpace($folderKeyword)) { $mainExe = $validSubExes | Where-Object { $_.BaseName -like "*$folderKeyword*" } | Select-Object -First 1 }
                    if (!$mainExe) { $mainExe = $validSubExes | Sort-Object { $_.BaseName.Length } | Select-Object -First 1 }
                }
                if ($mainExe) {
                    Write-Un1Log -Category "EXE-FIND" -Message "Subfolder '$($dir.Name)': Selected -> $($mainExe.Name)" -Color Green
                    return $mainExe.FullName
                }
            }
        }
    }
    return ""
}

# ==========================================
# BLOCO AUXILIAR: Cache do MuiCache (FriendlyAppName -> ExePath)
# ==========================================
function Get-Un1nst4ll3rMuiCache {
    Write-Un1Log -Category "MUICACHE" -Message "Building MuiCache index..." -Color Cyan
    $muiCache = @{}
    
    # O MuiCache existe no HKCU e/ou HKCR
    $regPaths = @(
        "Registry::HKEY_CURRENT_USER\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\MuiCache",
        "Registry::HKEY_CLASSES_ROOT\Local Settings\Software\Microsoft\Windows\Shell\MuiCache"
    )

    foreach ($regPath in $regPaths) {
        try {
            if (Test-Path $regPath) {
                $props = Get-ItemProperty $regPath -ErrorAction SilentlyContinue
                $props.PSObject.Properties | Where-Object {
                    $_.Name -match '\.FriendlyAppName$' -and ![string]::IsNullOrWhiteSpace($_.Value) -and $_.Name -notmatch '^PS'
                } | ForEach-Object {
                    $propName = $_.Name
                    $friendlyName = $_.Value.ToString().Trim()
                    
                    # Extrai o caminho do EXE: "C:\Pasta\app.exe.FriendlyAppName" -> "C:\Pasta\app.exe"
                    if ($propName -match '^(.+\.exe)\.FriendlyAppName$') {
                        $exePath = $Matches[1]
                        
                        # Prioriza caminhos do Program Files se houver duplicatas
                        if (!$muiCache.ContainsKey($friendlyName)) {
                            $muiCache[$friendlyName] = $exePath
                        } elseif ($exePath -match 'Program Files' -and $muiCache[$friendlyName] -notmatch 'Program Files') {
                            $muiCache[$friendlyName] = $exePath
                        }
                    }
                }
            }
        } catch {}
    }
    
    Write-Un1Log -Category "MUICACHE" -Message "Cache complete. $($muiCache.Count) applications mapped." -Color Green
    return $muiCache
}

# ==========================================
# BLOCO AUXILIAR: Descoberta de Apps sem Registro (Orphans via MuiCache)
# ==========================================
function Find-Un1nst4ll3rOrphans {
    param ([Array]$ResolvedPrograms)
    
    Write-Un1Log -Category "ORPHAN" -Message "Searching for unregistered apps with uninstallers..." -Color Magenta
    $orphans = [System.Collections.ArrayList]::new()
    
    # 1. Coleta os Locais e Nomes JÁ RESOLVIDOS pelo DeepSize
    $knownLocals = @($ResolvedPrograms | Where-Object { ![string]::IsNullOrWhiteSpace($_.Local) } | Select-Object -ExpandProperty Local)
    $knownNames = @($ResolvedPrograms.Nome)

    # Garante os caches
    if ($null -eq $Global:MemoryMuiCache -or $Global:MemoryMuiCache.Count -eq 0) { $Global:MemoryMuiCache = Get-Un1nst4ll3rMuiCache }
    if ($null -eq $Global:MemoryShortcuts -or $Global:MemoryShortcuts.Count -eq 0) { $Global:MemoryShortcuts = Get-Un1nst4ll3rShortcutCache }

    # Blacklist de pastas nativas do Windows (Recursos, não desinstaláveis via UI normal)
    $windowsNativePaths = @(
        "$env:windir\",
        "$env:ProgramFiles\Windows NT\",
        "$env:ProgramFiles\Windows Media Player\",
        "$env:ProgramFiles\Windows Photo Viewer\",
        "$env:ProgramFiles (x86)\Windows NT\",
        "$env:ProgramFiles (x86)\Windows Media Player\",
        "$env:ProgramFiles\Internet Explorer\"

    )

    foreach ($muiName in $Global:MemoryMuiCache.Keys) {
        $exePath = $Global:MemoryMuiCache[$muiName]
        
        if ([string]::IsNullOrWhiteSpace($exePath) -or !(Test-Path $exePath)) { continue }
        if ($exePath -match '(\\Downloads\\|\\Desktop\\|\\Temp\\|\\\$Recycle.Bin\\)') { continue }
        
        $installDir = Split-Path $exePath
        
        # DEDUPLICAÇÃO POR NOME
        if ($knownNames -contains $muiName) { continue }

        # BLACKLIST DE RECURSOS DO WINDOWS
        $isWindowsFeature = $false
        foreach ($winPath in $windowsNativePaths) {
            if ($installDir.StartsWith($winPath, [System.StringComparison]::OrdinalIgnoreCase)) { $isWindowsFeature = $true; break }
        }
        if ($isWindowsFeature) { continue }

        # DEDUPLICAÇÃO HIERÁRQUICA POR PASTA:
        # Se o MuiCache aponta pra C:\Office\Root\Office16 e o Registro mapeou C:\Office\Root, é o mesmo app.
        $isAlreadyMapped = $false
        $normCurrent = $installDir.TrimEnd('\').ToLower()
        foreach ($knownDir in $knownLocals) {
            $normKnown = $knownDir.TrimEnd('\').ToLower()
            # Match exato OU um é subpasta do outro
            if ($normCurrent -eq $normKnown -or $normCurrent.StartsWith($normKnown + "\") -or $normKnown.StartsWith($normCurrent + "\")) {
                $isAlreadyMapped = $true
                break
            }
        }
        if ($isAlreadyMapped) { continue }
        
        # BUSCA DE UNINSTALLER (Agora mais profunda: Raiz + 1º nível de subpastas)
        $uninstallString = ""
        
        $diskUninstallers = Get-ChildItem -Path $installDir -Filter "*.exe" -File -Recurse -Depth 1 -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -match '^uninstall|^unins\d+'
        } | Select-Object -First 1
        
        if ($diskUninstallers) {
            $uninstallString = "`"$($diskUninstallers.FullName)`""
            Write-Un1Log -Category "ORPHAN" -Message "Uninstaller found via Disk Heuristic: $($diskUninstallers.FullName)" -Color Cyan
        }
        
        # Fallback: Atalhos
        if (!$uninstallString -and $Global:MemoryShortcuts.Count -gt 0) {
            $lnkUninstaller = $Global:MemoryShortcuts | Where-Object { 
                $_.Target -like "$installDir*" -and $_.Target -match 'uninstall|unins\d+' -and $_.Target -match '\.exe$'
            } | Select-Object -First 1
            
            if ($lnkUninstaller -and (Test-Path $lnkUninstaller.Target)) {
                $uninstallString = "`"$($lnkUninstaller.Target)`""
                Write-Un1Log -Category "ORPHAN" -Message "Uninstaller found via Shortcut: $($lnkUninstaller.Target)" -Color Cyan
            }
        }
        
        # REGRA FINAL: Sem uninstaller = não lista
        if ([string]::IsNullOrWhiteSpace($uninstallString)) {
            Write-Un1Log -Category "ORPHAN" -Message "Skipped (No valid uninstaller): $muiName" -Color DarkGray
            continue
        }

        Write-Un1Log -Category "ORPHAN" -Message "Unregistered app mapped: $muiName (Dir: $installDir)" -Color Green
        
        $orphans.Add([PSCustomObject]@{
            Nome                 = $muiName
            Versao               = ""
            Fabricante           = ""
            Tamanho              = 0
            Local                = $installDir
            Chave                = ""
            Tipo                 = "Win32"
            Status               = "OK"
            InstallDate          = ""
            HelpLink             = ""
            UninstallString      = $uninstallString
            QuietUninstallString = ""
            ProductCode          = ""
            UpgradeCode          = ""
            NoRemove             = $false
            NoModify             = $false
            NoRepair             = $false
            ModifyPath           = ""
            IsMsi                = $false
            DisplayIcon          = ""
            ExePath              = $exePath 
            ShortcutTitle        = "" 
            ShortcutTarget       = "" 
        }) | Out-Null
    }
    
    Write-Un1Log -Category "ORPHAN" -Message "Orphan discovery complete. $($orphans.Count) unregistered apps found." -Color Magenta
    return $orphans
}

# ==========================================
# BLOCO 1: Raw Registry & AppX Scan
# ==========================================
function Get-Un1nst4ll3rScan {
    Write-Un1Log -Category "SCAN" -Message "Starting Raw Registry & AppX Scan..." -Color Cyan
    $installedPrograms = [System.Collections.ArrayList]::new()

    $registryPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    #--- Desboberta via registrorística tradicional (Win32) ---
    foreach ($path in $registryPaths) {
        if (Test-Path $path) {
            $items = Get-ItemProperty $path -ErrorAction SilentlyContinue
            foreach ($item in $items) {
                if ($item.DisplayName -and !$item.SystemComponent -and !$item.ParentKeyName) {
                    Write-Un1Log -Category "SCAN" -Message "Registry found: $($item.DisplayName)" -Color White
                    
                    $installDir = $item.InstallLocation
                    $status = "NoLocation" 
                    if (![string]::IsNullOrWhiteSpace($installDir)) { if (!(Test-Path $installDir)) { $status = "Orphan" } else { $status = "OK" } }

                    $sizeBytes = [long]0
                    if ($item.EstimatedSize) { try { $sizeBytes = [long]::Parse($item.EstimatedSize.ToString()) * 1024 } catch {} }

                    $publisher = $item.Publisher
                    if ([string]::IsNullOrWhiteSpace($publisher) -and ![string]::IsNullOrWhiteSpace($item.DisplayIcon)) {
                        $iconPath = $item.DisplayIcon -replace '\"', '' -replace ',\d+$', ''
                        if (Test-Path $iconPath -ErrorAction SilentlyContinue) { try { $publisher = ([System.Diagnostics.FileVersionInfo]::GetVersionInfo($iconPath)).CompanyName } catch {} }
                    }

                    $installedPrograms.Add([PSCustomObject]@{
                        Nome                 = $item.DisplayName
                        Versao               = $item.DisplayVersion
                        Fabricante           = if ($publisher) { $publisher } else { "N/A" }
                        Tamanho              = $sizeBytes
                        Local                = if ($installDir) { $installDir.TrimEnd('\') } else { "" }
                        Chave                = $item.PSChildName
                        Tipo                 = "Win32"
                        Status               = $status
                        InstallDate          = $item.InstallDate
                        HelpLink             = $item.HelpLink
                        UninstallString      = if ($item.UninstallString) { $item.UninstallString.Trim() } else { "" }
                        QuietUninstallString = if ($item.QuietUninstallString) { $item.QuietUninstallString.Trim() } else { "" }
                        ProductCode          = if ($item.WindowsInstaller -eq 1) { $item.PSChildName } else { "" }
                        UpgradeCode          = if ($item.UpgradeCode) { $item.UpgradeCode.Trim() } else { "" }
                        NoRemove             = [bool]$item.NoRemove
                        NoModify             = [bool]$item.NoModify
                        NoRepair             = [bool]$item.NoRepair
                        ModifyPath           = if ($item.ModifyPath) { ($item.ModifyPath -replace '\"', '' -replace ',\d+$', '').Trim() } else { "" }
                        IsMsi                = [bool]($item.WindowsInstaller -eq 1)
                        DisplayIcon          = if ($item.DisplayIcon) { ($item.DisplayIcon -replace '\"', '' -replace ',\d+$', '').Trim() } else { "" }
                        ExePath              = ""
                        ShortcutTitle        = "" 
                        ShortcutTarget       = "" 
                    }) | Out-Null
                }
            }
        }
    }
    #--- Desboberta de Apps Modernos (AppX) ---
    $appxPackages = Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { $_.IsFramework -eq $false -and $_.SignatureKind -ne "None" }
    foreach ($app in $appxPackages) {
        if ($app.Name -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}') { continue }
        try {
            $manifest = $app | Get-AppxPackageManifest -ErrorAction Stop
            $isHidden = (-not $manifest.Package.Applications.Application.AppListEntry -or $manifest.Package.Applications.Application.AppListEntry -eq "none")
            if ($isHidden -and $app.Publisher -match "Microsoft") { continue }
            if ($app.Publisher -match "Microsoft Windows") { continue }

            Write-Un1Log -Category "SCAN" -Message "AppX found: $($app.Name)" -Color White
            
            $displayName = $app.Name; $xmlDN = $manifest.Package.Properties.DisplayName; if ($xmlDN -and $xmlDN -notlike "ms-resource*") { $displayName = $xmlDN }
            $cleanPublisher = $app.Publisher; $xmlP = $manifest.Package.Properties.PublisherDisplayName; if ($xmlP -and $xmlP -notlike "ms-resource*") { $cleanPublisher = $xmlP } elseif ($cleanPublisher -match 'CN=([^,]+)') { $cleanPublisher = $matches[1] } elseif ($cleanPublisher -match '^[0-9a-fA-F]{8}-') { $cleanPublisher = "N/A" }

            $installedPrograms.Add([PSCustomObject]@{
                Nome                 = $displayName
                Versao               = $app.Version
                Fabricante           = $cleanPublisher
                Tamanho              = if ($app.Size -gt 0) { [long]$app.Size } else { [long]0 }
                Local                = if ($app.InstallLocation) { $app.InstallLocation.TrimEnd('\') } else { "" }
                Chave                = $app.PackageFullName
                Tipo                 = "AppX"
                Status               = "OK"
                UninstallString      = ""
                QuietUninstallString = ""
                ProductCode          = ""
                UpgradeCode          = ""
                ExePath              = ""
                ModifyPath           = ""
                IsMsi                = $false
                DisplayIcon          = ""
                NoRemove             = $false
                NoModify             = $true
                NoRepair             = $true
                ShortcutTitle        = ""
                ShortcutTarget       = ""
            }) | Out-Null
        } catch {}
    }

    
    $resultList = $installedPrograms | Sort-Object Status, Nome -Unique
    Write-Un1Log -Category "SCAN" -Message "Scan complete. $($resultList.Count) valid applications found." -Color Green
    return $resultList
}

# ==========================================
# BLOCO 2: Local Discovery (Com Interceptador)
# ==========================================
function Get-Un1nst4ll3rDeepSize {
    param (
        [Parameter(Mandatory=$true)]
        [Array]$ProgramList
    )
    
    Write-Un1Log -Category "LOCATE" -Message "Starting Deep Location & ExePath Discovery..." -Color Cyan

    # Só constrói os caches se ainda não existirem (o scanner de órfãos pode tê-los construído)
    if ($null -eq $Global:MemoryShortcuts -or $Global:MemoryShortcuts.Count -eq 0) {
        $Global:MemoryShortcuts = Get-Un1nst4ll3rShortcutCache
    }
    if ($null -eq $Global:MemoryMuiCache -or $Global:MemoryMuiCache.Count -eq 0) {
        $Global:MemoryMuiCache = Get-Un1nst4ll3rMuiCache
    }

    $updatedList = [System.Collections.ArrayList]::new()
    $genericFolderNames = @("support", "system", "bin", "helper", "config", "resources", "data", "common", "lib", "tools", "files", "uninstall")
    $invalidHeuristicRoots = @("microsoft", "windows apps", "common files", "dotnet", "reference assemblies")

    foreach ($prog in $ProgramList) {
        Write-Un1Log -Category "LOCATE" -Message "--- Processing: $($prog.Nome) ---" -Color Cyan

        # ── PRIORIDADE 1: Json Pacotes Microsoft ──
        if ([string]::IsNullOrWhiteSpace($prog.Local)) {
            $intercepted = Resolve-Un1nst4ll3rMicrosoftPackage -Prog $prog
            if ($intercepted) {
                $updatedList.Add($prog) | Out-Null
                continue 
            }
        }

        $guessedPath = $null
        $exeFromShortcut = $null

        # ── PRIORIDADE 2: MuiCache (FriendlyAppName -> ExePath) ──
        # O Windows mapeia o nome do app para o EXE que já rodou. Fonte muito rica, mas requer validação.
        if (!$guessedPath -and !$exeFromShortcut -and ![string]::IsNullOrWhiteSpace($prog.Nome) -and $Global:MemoryMuiCache.Count -gt 0) {
            
            # Tenta casar primeiro o nome exato
            $muiExe = $Global:MemoryMuiCache[$prog.Nome]
            
            # Se não achou exato, tenta casar pelo nome limpo (sem versão)
            if (!$muiExe) {
                $safeAppName = $prog.Nome -replace '\(.*\)', '' -replace '\s+\d+.*', '' -replace '[^\w\s\-+]', ''
                $safeAppName = $safeAppName.Trim()
                if (![string]::IsNullOrWhiteSpace($safeAppName)) {
                    $matchKey = $Global:MemoryMuiCache.Keys | Where-Object { $_ -like "*$safeAppName*" -or $safeAppName -like "*$_*" } | Select-Object -First 1
                    if ($matchKey) { $muiExe = $Global:MemoryMuiCache[$matchKey] }
                }
            }

            # Validação Crucial: Rejeita instaladores, desinstaladores e pastas temporárias
            $isValidMuiExe = $true
            if ($muiExe) {
                $muiExeName = Split-Path $muiExe -Leaf
                
                # 1. Rejeita se o NOME do arquivo for de setup/uninstall
                $setupBlacklist = @('setup', 'install', 'uninstall', 'unins\d+', '-setup\.exe$', '-install\.exe$')
                foreach ($pattern in $setupBlacklist) {
                    if ($muiExeName -match $pattern) { $isValidMuiExe = $false; break }
                }
                
                # 2. Rejeita se o CAMINHO for de download, desktop ou temporário
                if ($isValidMuiExe -and $muiExe -match '(\\Downloads\\|\\Desktop\\|\\Temp\\|\\\$Recycle.Bin\\)') {
                    $isValidMuiExe = $false
                }
            }

            # Se passou na validação e existe no disco, temos a localização perfeita!
            if ($isValidMuiExe -and $muiExe -and (Test-Path $muiExe -ErrorAction SilentlyContinue) -and $muiExe -notmatch 'Windows\\System') {
                $exeFromShortcut = $muiExe # Trata o EXE do MuiCache como um atalho perfeito
                $dir = Split-Path $muiExe
                if ($dir -and (Test-Path $dir)) { 
                    $guessedPath = $dir
                    Write-Un1Log -Category "LOCATE" -Message "GOT via MuiCache! Exe=$muiExe | Dir=$dir (Skipped Disk Scan & Exe Heuristic)" -Color Green
                }
            } elseif ($muiExe -and !$isValidMuiExe) {
                 # Log avisando que o MuiCache tentou nos enganar, mas falhou!
                 Write-Un1Log -Category "LOCATE" -Message "MuiCache rejected (Setup/Invalid path): $muiExe" -Color DarkGray
            }
        }

        # ── PRIORIDADE 3: Shortcut Cache (Program icon -> ExePath) ──
        if (![string]::IsNullOrWhiteSpace($prog.Nome)) {
            $safeAppName = $prog.Nome -replace '\(.*\)', '' -replace '\s+\d+.*', '' -replace '[^\w\s\-+]', ''
            $lnkFiles = $Global:MemoryShortcuts | Where-Object { 
                $_.LnkName -like "*$($prog.Nome)*" -or 
                $prog.Nome -like "*$($_.LnkName)*" -or 
                $_.LnkName -like "*$safeAppName*" 
            }
            
            foreach ($lnk in $lnkFiles) {
                $target = $lnk.Target
                $startIn = $lnk.WorkingDir
                
                if (![string]::IsNullOrWhiteSpace($target) -and (Test-Path $target -ErrorAction SilentlyContinue) -and $target -match '\.exe$' -and $target -notmatch 'Windows\\System') {
                    if ($target -notmatch 'uninstall|unins\d+|setup') {
                        $exeFromShortcut = $target
                        $prog.ShortcutTitle = $lnk.LnkName
                        $prog.ShortcutTarget = $target
                        
                        $dir = if (![string]::IsNullOrWhiteSpace($startIn) -and (Test-Path $startIn)) { $startIn } else { Split-Path $target }
                        if ($dir -and (Test-Path $dir)) { 
                            $guessedPath = $dir
                            Write-Un1Log -Category "LOCATE" -Message "Exe & Local found via Shortcut: Exe=$target | Dir=$dir" -Color Green
                        }
                        break
                    }
                }
            }
        }

        # ── PRIORIDADE 4: Shortcut Cache (DisplayIcon from Reg -> ExePath) ──
        if (!$guessedPath -and !$exeFromShortcut -and ![string]::IsNullOrWhiteSpace($prog.DisplayIcon)) {
            $cleanIcon = $prog.DisplayIcon -replace '\"', '' -replace ',\d+$', ''
            if ((Test-Path $cleanIcon -ErrorAction SilentlyContinue) -and $cleanIcon -notmatch 'Package Cache|Windows\\Installer|shell32|imageres|Windows\\SysWOW64|Windows\\System32') {
                $dir = Split-Path -Path $cleanIcon -ErrorAction SilentlyContinue
                if ($dir -and (Test-Path $dir -ErrorAction SilentlyContinue)) {
                    $guessedPath = $dir
                    Write-Un1Log -Category "LOCATE" -Message "Local found via DisplayIcon: $guessedPath" -Color Green
                }
            }
        }

        if (!$guessedPath -and ![string]::IsNullOrWhiteSpace($prog.Local) -and (Test-Path $prog.Local)) {
            $guessedPath = $prog.Local
            Write-Un1Log -Category "LOCATE" -Message "Local already provided by Registry: $guessedPath" -Color Green
        }

        # ── PRIORIDADE 5: UnistallString from Reg -> ExePath ──
        if (!$guessedPath -and ![string]::IsNullOrWhiteSpace($prog.UninstallString)) {
            $cacheKeyword = $null
            if ($prog.UninstallString -match 'Package Cache\\.*\\(.+?)\.exe') { $cacheKeyword = ($Matches[1] -split '-')[0] }
            if ($prog.UninstallString -match "msiexec" -and $prog.UninstallString -match '\{([A-Fa-f0-9\-]+)\}') {
                $msiGuid = $Matches[1]
                try {
                    $installer = New-Object -ComObject WindowsInstaller.Installer
                    $msiLocation = $installer.ProductInfo("{$msiGuid}", "InstallLocation")
                    if (![string]::IsNullOrWhiteSpace($msiLocation) -and (Test-Path $msiLocation) -and $msiLocation -notmatch 'Package Cache|Windows\\TEMP|IXP') { $guessedPath = $msiLocation.TrimEnd('\') }
                    if (!$guessedPath) {
                        $msiSource = $installer.ProductInfo("{$msiGuid}", "InstallSource")
                        if (![string]::IsNullOrWhiteSpace($msiSource) -and (Test-Path $msiSource) -and $msiSource -notmatch 'Package Cache|Windows\\TEMP|IXP|[0-9a-f]{8,}') { $guessedPath = $msiSource.TrimEnd('\') }
                    }
                    if ($guessedPath) { Write-Un1Log -Category "LOCATE" -Message "Local found via MSI COM: $guessedPath" -Color Green }
                } catch {}
            }
            if (!$guessedPath -and $prog.UninstallString -notmatch "msiexec") {
                $dir = $null
                if ($prog.UninstallString -match '-f\s*"?([^"]+\.isu|[^\s,]+\.isu)') { $isuPath = $Matches[1]; if (Test-Path $isuPath -ErrorAction SilentlyContinue) { $dir = Split-Path -Path $isuPath -ErrorAction SilentlyContinue } }
                if (!$dir) { $cleanStr = $prog.UninstallString.Trim('"').Trim("'"); $exePath = ($cleanStr -split ' /')[0].Trim(); $dir = Split-Path -Path $exePath -ErrorAction SilentlyContinue }
                if ($dir -and (Test-Path $dir -ErrorAction SilentlyContinue) -and $dir -notmatch 'Package Cache|Windows\\Installer') { 
                    $guessedPath = $dir 
                    Write-Un1Log -Category "LOCATE" -Message "Local found via UninstallString: $guessedPath" -Color Green
                }
            }
        }
        # ── PRIORIDADE 6: App Paths (AppName -> ExePath) ──

            if (!$guessedPath -and ![string]::IsNullOrWhiteSpace($prog.Nome)) {
                $safeAppName = $prog.Nome -replace '\(.*\)', '' -replace '\s+\d+.*', '' -replace '[^\w\s\-+]', ''
                $appWords = @($safeAppName -split '\s+' | Where-Object { $_ -notin $genericWords -and $_.Length -gt 1 })
                
                $keywordsToTry = @($safeAppName) + $appWords | Select-Object -Unique
                
                $appPathRegRoots = @(
                    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths",
                    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths"
                )
                
                foreach ($kw in $keywordsToTry) {
                    if ($guessedPath) { break }
                    foreach ($regRoot in $appPathRegRoots) {
                        $exeKey = Join-Path $regRoot "$kw.exe"
                        if (Test-Path $exeKey -ErrorAction SilentlyContinue) {
                            try {
                                $defaultVal = (Get-ItemProperty -Path $exeKey -ErrorAction SilentlyContinue).'(default)'
                                if (![string]::IsNullOrWhiteSpace($defaultVal)) {
                                    $exePathExpanded = [System.Environment]::ExpandEnvironmentVariables($defaultVal)
                                    if (Test-Path $exePathExpanded -ErrorAction SilentlyContinue) {
                                        $dir = Split-Path $exePathExpanded
                                        if ($dir -and (Test-Path $dir)) {
                                            $guessedPath = $dir
                                            Write-Un1Log -Category "LOCATE" -Message "Location found via App Paths Registry: $guessedPath (Keyword: $kw)" -Color Green
                                            break
                                        }
                                    }
                                }
                            } catch {}
                        }
                    }
                }
            }

        # ── PRIORIDADE 7: Disk Scan (AppName -> FolderName -> ExePath) ──
        if (!$guessedPath -and ![string]::IsNullOrWhiteSpace($prog.Nome)) {
            $commonPaths = @(
                [System.Environment]::GetFolderPath('ProgramFiles'), 
                [System.Environment]::GetFolderPath('ProgramFilesX86'), 
                [System.Environment]::GetFolderPath('LocalApplicationData'), 
                "$([System.Environment]::GetFolderPath('LocalApplicationData'))\Programs", 
                [System.Environment]::GetFolderPath('ApplicationData'), 
                [System.Environment]::GetFolderPath('CommonApplicationData')
            ) | Select-Object -Unique
            
            $safeAppName = $prog.Nome -replace '\(.*\)', '' -replace '\s+\d+.*', '' -replace '[^\w\s\-+]', ''
            $genericWords = @("microsoft", "corporation", "inc", "ltda", "the", "launcher", "update", "service", "framework", "runtime", "helper", "system", "visual", "net", "windows", "driver", "redistributable", "c++")
            $appWords = @($safeAppName -split '\s+' | Where-Object { $_ -notin $genericWords -and $_.Length -gt 1 })
            $firstKeyword = if ($appWords.Count -gt 0) { $appWords[0] } else { "" }

            if ([string]::IsNullOrWhiteSpace($firstKeyword) -and ![string]::IsNullOrWhiteSpace($cacheKeyword)) { $firstKeyword = $cacheKeyword }

            if (![string]::IsNullOrWhiteSpace($firstKeyword)) {
                foreach ($basePath in $commonPaths) {
                    if (!(Test-Path $basePath)) { continue }
                    $foundDir = Get-ChildItem -Path $basePath -Directory -ErrorAction SilentlyContinue | Where-Object { 
                        $fName = $_.Name
                        $fNameNorm = $fName -replace '[\s\-\._]', ''
                        $keyNorm = $firstKeyword -replace '[\s\-\._]', ''
                        
                        $matchDirect = $fName -like "*$firstKeyword*" -or $fName -like "*$safeAppName*" -or $safeAppName -like "*$fName*"
                        $matchNorm = $fNameNorm -like "*$keyNorm*" -or $keyNorm -like "*$fNameNorm*"
                        
                        $matchWords = $false
                        if ($appWords.Count -gt 0) { foreach ($word in $appWords) { if ($word.Length -gt 2 -and $fName -like "*$word*") { $matchWords = $true; break } } }

                        $matchDirect -or $matchNorm -or $matchWords
                    } | Select-Object -First 1
                    
                    if ($foundDir) {
                        $leafNorm = $foundDir.Name.ToLower().Replace(" ", "")
                        if ($invalidHeuristicRoots -contains $leafNorm) {
                            Write-Un1Log -Category "LOCATE" -Message "Heuristic rejected: '$($foundDir.Name)' is a generic root." -Color DarkGray
                            continue
                        }
                        $guessedPath = $foundDir.FullName
                        Write-Un1Log -Category "LOCATE" -Message "Local found via Disk Heuristic: $guessedPath (Keyword: $firstKeyword)" -Color Green
                        break 
                    }
                }
            }
        }

        if (![string]::IsNullOrWhiteSpace($guessedPath)) {
            $leafFolder = (Split-Path $guessedPath -Leaf).ToLower()
            if ($leafFolder -in $genericFolderNames) {
                $parentDir = Split-Path $guessedPath -Parent
                if ($parentDir -and (Test-Path $parentDir)) {
                    Write-Un1Log -Category "LOCATE" -Message "Parent adjustment: Generic folder '$leafFolder' detected. Moving up to: $parentDir" -Color Yellow
                    $guessedPath = $parentDir
                }
            }
        }

        if ($guessedPath) { 
            $prog.Local = $guessedPath
            if ($prog.Status -eq "NoLocation") { $prog.Status = "OK" } 
            
            if (![string]::IsNullOrWhiteSpace($exeFromShortcut)) {
                $prog.ExePath = $exeFromShortcut
                Write-Un1Log -Category "LOCATE" -Message "ExePath confirmed via Shortcut/MuiCache: $exeFromShortcut" -Color Green
            } elseif (![string]::IsNullOrWhiteSpace($prog.ExePath)) {
                # Já temos um ExePath (provavelmente do Orphan Finder), mantemos ele
                Write-Un1Log -Category "LOCATE" -Message "ExePath already resolved (pre-filled): $($prog.ExePath)" -Color DarkGray
            } else {
                # Roda a heurística pesada só se não tiver NADA
                $uninstallExeName = if ($prog.UninstallString -match '\\([^\\]+\.exe)') { $Matches[1] } else { "" }
                $foundExe = Find-Un1nst4ll3rMainExe -Path $guessedPath -AppName $prog.Nome -UninstallExeName $uninstallExeName
                # ... resto do código do running process ...
                $prog.ExePath = $foundExe
            }
        } else {
            $prog.Status = "NoLocation"
            Write-Un1Log -Category "LOCATE" -Message "Location not found for $($prog.Nome)." -Color Red
        }

        $updatedList.Add($prog) | Out-Null
    }

    Write-Un1Log -Category "LOCATE" -Message "Deep location discovery complete." -Color Green
    return $updatedList
}

# ==========================================
# BLOCO 3: Interceptador de Pacotes Microsoft
# ==========================================
function Resolve-Un1nst4ll3rMicrosoftPackage {
    param (
        [PSCustomObject]$Prog
    )

    if ($null -eq $Global:SysPkgBank -or $Global:SysPkgBank.Count -eq 0) { return $false }

    foreach ($rule in $Global:SysPkgBank) {
        try {
            if ($Prog.Nome -match $rule.Pattern) {
                Write-Un1Log -Category "MS-PKG" -Message "System package detected: $($Prog.Nome). Checking JSON rule..." -Color Magenta
                
                $expandedPath = [System.Environment]::ExpandEnvironmentVariables($rule.CheckPath)
                
                $pathExists = $false
                if ($expandedPath -match '\.\w{3}$') {
                    $pathExists = Test-Path $expandedPath -ErrorAction SilentlyContinue
                } else {
                    $pathExists = !([string]::IsNullOrWhiteSpace((Get-Item $expandedPath* -ErrorAction SilentlyContinue | Select-Object -First 1)))
                }

                if ($pathExists) {
                    $resolvedPath = if (![string]::IsNullOrWhiteSpace($rule.LocalPath)) { $rule.LocalPath } else { if ($expandedCheckPath -match '^(.*\\)([^\\]+\.\w{3})$') { $Matches[1] } else { $expandedCheckPath } }
                    $Prog.Local = [System.Environment]::ExpandEnvironmentVariables($resolvedPath).TrimEnd('\')
                    $Prog.Tamanho = 0
                    $Prog.Status = if ($rule.IsSystem -eq $true) { "System" } else { "OK" }
                    $Prog.ExePath = ""
                    
                    Write-Un1Log -Category "MS-PKG" -Message "Location confirmed via JSON: $($Prog.Local)" -Color Cyan
                    return $true
                } else {
                    Write-Un1Log -Category "MS-PKG" -Message "Rule matched, but path missing: $expandedPath" -Color DarkGray
                }
            }
        } catch {
             Write-Un1Log -Category "MS-PKG" -Message "Invalid regex in SysPkgBank: '$($rule.Pattern)'" -Color DarkRed
        }
    }

    return $false
}

# ==========================================
# BLOCO 4: Motor de Medição de Tamanho
# ==========================================
function Get-Un1nst4ll3rSizeEngine {
    param (
        [Parameter(Mandatory=$true)]
        [Array]$ProgramList
    )

    Write-Un1Log -Category "SIZE" -Message "Starting Size Calculation Engine..." -Color Cyan
    $updatedList = [System.Collections.ArrayList]::new()

    Write-Un1Log -Category "SIZE" -Message "Building MSI Installer UserData cache..." -Color DarkGray
    $msiCache = @{}
    $msiRegPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Products\*\InstallProperties",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Products\*\InstallProperties"
    )
    foreach ($msiPath in $msiRegPaths) {
        Get-ItemProperty $msiPath -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -and $_.EstimatedSize } | ForEach-Object {
            $name = $_.DisplayName
            if (![string]::IsNullOrWhiteSpace($name) -and !$msiCache.ContainsKey($name)) {
                $msiCache[$name] = [long]$_.EstimatedSize * 1024
            }
        }
    }

    Write-Un1Log -Category "SIZE" -Message "Querying WMI InstalledWin32Program cache..." -Color DarkGray
    $wmiCache = @{}
    try {
        Get-CimInstance Win32_InstalledWin32Program -ErrorAction Stop | Where-Object { $_.Name -and $_.Size -gt 0 } | ForEach-Object {
            if (!$wmiCache.ContainsKey($_.Name)) {
                $wmiCache[$_.Name] = [long]$_.Size
            }
        }
    } catch {
        Write-Un1Log -Category "SIZE" -Message "WMI Win32_InstalledWin32Program not available." -Color DarkGray
    }

    foreach ($prog in $ProgramList) {
        if ($Global:Un1LogAction) { & $Global:Un1LogAction "Calculating size: $($prog.Nome)" }

        if ($null -ne $prog.Tamanho -and $prog.Tamanho -gt 0) {
            $sizeFriendly = if ($prog.Tamanho -ge 1GB) { "{0:N2} GB" -f ($prog.Tamanho / 1GB) } else { "{0:N2} MB" -f ($prog.Tamanho / 1MB) }
            Write-Un1Log -Category "SIZE" -Message "Registry size accepted: $sizeFriendly for $($prog.Nome)" -Color Green
            $updatedList.Add($prog) | Out-Null
            continue
        }

        if ($msiCache.ContainsKey($prog.Nome)) {
            $prog.Tamanho = $msiCache[$prog.Nome]
            $sizeFriendly = if ($prog.Tamanho -ge 1GB) { "{0:N2} GB" -f ($prog.Tamanho / 1GB) } else { "{0:N2} MB" -f ($prog.Tamanho / 1MB) }
            Write-Un1Log -Category "SIZE" -Message "Size rescued via MSI UserData: $sizeFriendly for $($prog.Nome)" -Color Cyan
            $updatedList.Add($prog) | Out-Null
            continue
        }

        if ($wmiCache.ContainsKey($prog.Nome)) {
            $prog.Tamanho = $wmiCache[$prog.Nome]
            $sizeFriendly = if ($prog.Tamanho -ge 1GB) { "{0:N2} GB" -f ($prog.Tamanho / 1GB) } else { "{0:N2} MB" -f ($prog.Tamanho / 1MB) }
            Write-Un1Log -Category "SIZE" -Message "Size rescued via WMI: $sizeFriendly for $($prog.Nome)" -Color Cyan
            $updatedList.Add($prog) | Out-Null
            continue
        }

        if (![string]::IsNullOrWhiteSpace($prog.Local) -and (Test-Path $prog.Local -ErrorAction SilentlyContinue)) {
            
            $isSafeToMeasure = $true
            $dangerPaths = @('Windows\\System32', 'Windows\\SysWOW64', 'Windows\\WinSxS', 'Windows\\Installer', 'Windows\\Microsoft.NET', 'Package Cache', 'ProgramData\\Package Cache')
            foreach ($danger in $dangerPaths) {
                if ($prog.Local -match $danger) { $isSafeToMeasure = $false; break }
            }

            if ($isSafeToMeasure) {
                try {
                    Write-Un1Log -Category "SIZE" -Message "Measuring disk size (Safe I/O): $($prog.Local)" -Color DarkGray
                    $bytes = (Get-ChildItem -Path $prog.Local -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                    if ($bytes -gt 0) { 
                        $prog.Tamanho = [long]$bytes 
                        $sizeFriendly = if ($prog.Tamanho -ge 1GB) { "{0:N2} GB" -f ($prog.Tamanho / 1GB) } else { "{0:N2} MB" -f ($prog.Tamanho / 1MB) }
                        Write-Un1Log -Category "SIZE" -Message "Disk size calculated: $sizeFriendly for $($prog.Nome)" -Color Green
                    }
                } catch {
                    Write-Un1Log -Category "SIZE" -Message "I/O Error measuring: $($prog.Local)" -Color DarkRed
                }
            } else {
                Write-Un1Log -Category "SIZE" -Message "Disk I/O blocked (System protected path): $($prog.Local)" -Color Magenta
            }
        }

        $updatedList.Add($prog) | Out-Null
    }

    Write-Un1Log -Category "SIZE" -Message "Size calculation engine complete." -Color Green
    return $updatedList
}


# ==========================================
# BLOCO 5: Motor de Desinstalação
# ==========================================
function Start-Un1nst4ll3rApp {
    param (
        [string]$AppName,
        [string]$UninstallStringValue,
        [string]$QuietUninstallStringValue, # Ajustado para Quiet (correção de digitação)
        [string]$ProgramType,
        [string]$AppIdentifier = "" # Usado para AppX (PackageFullName) e futuras limpezas de registro
    )

    $L = $script:LangData
    
    # Usa o formato dinâmico do JSON, substituindo o {0} pelo nome do App
    $confirmMsg = $L.ConfirmUninstallMessage -f $AppName

    $resultFromUser = [System.Windows.Forms.MessageBox]::Show(
        $confirmMsg, 
        $L.Title, 
        [System.Windows.Forms.MessageBoxButtons]::YesNo, 
        [System.Windows.Forms.MessageBoxIcon]::Question
    )
    if ($resultFromUser -ne [System.Windows.Forms.DialogResult]::Yes) {
        Write-Un1Log -Category "UNINSTALL" -Message "User cancelled uninstall for '$AppName'." -Color Yellow
        return $false
    }    

    Write-Un1Log -Category "UNINSTALL" -Message "Attempting to uninstall: $($AppName)" -Color Yellow

    # Variáveis de controle
    $uninstallCmd = $UninstallStringValue
    $Silent = $false

    # 1. Verifica o modo Quiet
    if ($QuietUninstallStringValue -ne "") {
        $uninstallCmd = $QuietUninstallStringValue
        $Silent = $true
        Write-Un1Log -Category "UNINSTALL" -Message "Quiet mode detected. Running silently." -Color Magenta        
    }

    try {
        # 2. Desinstalação AppX
        if ($ProgramType -eq "AppX") {
            Write-Un1Log -Category "UNINSTALL" -Message "Removing AppX package..." -Color Cyan
            # Usa o AppIdentifier se fornecido, senão tenta pelo AppName
            $appxFilter = if (![string]::IsNullOrWhiteSpace($AppIdentifier)) { $AppIdentifier } else { $AppName }
            Get-AppxPackage -Name $appxFilter | Remove-AppxPackage -ErrorAction Stop
            Write-Un1Log -Category "UNINSTALL" -Message "AppX removal successful." -Color Green
            return $true
        }
        
        # 3. Desinstalação MSI (Detectada automaticamente pela string MsiExec)
        elseif ($uninstallCmd -match 'msiexec' -and $uninstallCmd -match '\{([A-Fa-f0-9\-]+)\}') {
            Write-Un1Log -Category "UNINSTALL" -Message "Removing via MSI Exec..." -Color Cyan
            $msiGuid = $Matches[0] # Pega o {GUID}
            # Se for discreet, roda silencioso (/qn), senão roda normal (/qb+)
            $msiArgs = if ($Silent) { "/x $msiGuid /qn /norestart" } else { "/x $msiGuid /qb+ /norestart" }
            Start-Process "msiexec.exe" -ArgumentList $msiArgs -Wait -NoNewWindow
            Write-Un1Log -Category "UNINSTALL" -Message "MSI removal command executed." -Color Green
            return $true
        }

        # 4+5. Desinstalação (Silent ou Padrão)
        elseif (![string]::IsNullOrWhiteSpace($uninstallCmd)) {

            $logLabel = if ($Silent) { "Silent" } else { "Standard" }
            Write-Un1Log -Category "UNINSTALL" -Message "Removing via $logLabel Uninstall String..." -Color Cyan

            # Normaliza aspas inteligentes
            $uninstallCmd = $uninstallCmd -replace '[""]', '"'

            $exe   = ""
            $argms = ""

            if ($uninstallCmd.TrimStart().StartsWith('"')) {
                $parts = $uninstallCmd -split '"'
                $exe   = $parts[1].Trim()
                $argms = if ($parts.Count -gt 2) { $parts[2].Trim() } else { "" }
            } else {
                $firstSpace = $uninstallCmd.IndexOf(' ')
                if ($firstSpace -gt 0) {
                    $exe   = $uninstallCmd.Substring(0, $firstSpace).Trim()
                    $argms = $uninstallCmd.Substring($firstSpace + 1).Trim()
                } else {
                    $exe   = $uninstallCmd
                    $argms = ""
                }
            }

            try {
                if ([string]::IsNullOrWhiteSpace($exe)) { throw "Failed to parse executable from uninstall string." }

                $spArgs = @{ FilePath = $exe; Wait = $true}
                if (![string]::IsNullOrWhiteSpace($argms)) { $spArgs.ArgumentList = $argms }
                if (!$Silent) { $spArgs.NoNewWindow = $false }   # interativo: janela visível
                else          { $spArgs.NoNewWindow = $true  }   # silencioso: sem janela

                Start-Process @spArgs -ErrorAction Stop
                Write-Un1Log -Category "UNINSTALL" -Message "$logLabel removal command executed." -Color Green
                return $true

            } catch {
                Write-Un1Log -Category "UNINSTALL" -Message "Start-Process failed [$_], falling back to cmd..." -Color Yellow
                try {
                    # ADICIONADO -ErrorAction Stop AQUI TAMBÉM
                    Start-Process cmd -ArgumentList "/c `"$uninstallCmd`"" -Wait -NoNewWindow -ErrorAction Stop
                    Write-Un1Log -Category "UNINSTALL" -Message "cmd fallback executed successfully." -Color Green
                    return $true
                } catch {
                    Write-Un1Log -Category "UNINSTALL" -Message "cmd fallback also failed: $_" -Color Red
                }
            }
        }
        
        else {
            Write-Un1Log -Category "UNINSTALL" -Message "No valid uninstall method found for $($AppName)." -Color Red
        }
    } catch {
        Write-Un1Log -Category "UNINSTALL" -Message "ERROR uninstalling $($AppName): $($_.Exception.Message)" -Color Red
        return $false
    }
    return $false
}


# ==========================================
# BLOCO 6: Motor de Limpeza de Vestígios
# ==========================================
function Remove-Un1nst4ll3rTraces {
    param (
        [PSCustomObject]$App
    )

    Write-Un1Log -Category "CLEANUP" -Message "Starting trace cleanup for: $($App.Nome)" -Color Yellow
    $cleanedCount = 0

    $regPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$($App.Chave)",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\$($App.Chave)",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$($App.Chave)"
    )

    foreach ($reg in $regPaths) {
        if (Test-Path $reg) {
            Write-Un1Log -Category "CLEANUP" -Message "Removing orphaned registry key: $reg" -Color Cyan
            Remove-Item $reg -Recurse -Force -ErrorAction SilentlyContinue
            $cleanedCount++
        }
    }

    if (![string]::IsNullOrWhiteSpace($App.Local) -and (Test-Path $App.Local)) {
        Write-Un1Log -Category "CLEANUP" -Message "Removing orphaned installation folder: $($App.Local)" -Color Cyan
        Remove-Item $App.Local -Recurse -Force -ErrorAction SilentlyContinue
        $cleanedCount++
    }

    $safeAppName = $App.Nome -replace '\(.*\)', '' -replace '\s+\d+.*', '' -replace '[^\w\s\-+]', ''
    $appWords = @($safeAppName -split '\s+' | Where-Object { $_.Length -gt 2 })
    $firstKeyword = if ($appWords.Count -gt 0) { $appWords[0] } else { $safeAppName }

    $residualPaths = @(
        "$env:APPDATA\$firstKeyword",
        "$env:LOCALAPPDATA\$firstKeyword",
        "$env:PROGRAMDATA\$firstKeyword",
        "$env:LOCALAPPDATA\Programs\$firstKeyword"
    )

    foreach ($path in $residualPaths) {
        if (Test-Path $path) {
            Write-Un1Log -Category "CLEANUP" -Message "Removing residual data folder: $path" -Color Cyan
            Remove-Item $path -Recurse -Force -ErrorAction SilentlyContinue
            $cleanedCount++
        }
    }

    Write-Un1Log -Category "CLEANUP" -Message "Cleanup finished. $cleanedCount trace(s) removed." -Color Green
    return $cleanedCount
}