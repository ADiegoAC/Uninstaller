# ======================================================================
#  Un1nst4ll3r - Motor de Varredura (Módulo)
#  Versão: 3.1.1
# ======================================================================

# Força o terminal do Windows a usar UTF-8 para exibir acentos corretamente no console
#[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
#[Console]::InputEncoding = [System.Text.Encoding]::UTF8
#$OutputEncoding = [System.Text.Encoding]::UTF8

# Compatibilidade PowerShell 7: Carrega o módulo Appx via Windows PowerShell
if ($PSVersionTable.PSVersion.Major -ge 7) {
    try {
        Import-Module Appx -UseWindowsPowerShell -WarningAction SilentlyContinue -ErrorAction Stop
    }
    catch {
        Write-Warning "Falha ao carregar o módulo Appx via compatibilidade. O scan AppX pode falhar."
    }
}

# Inicializa o acumulador global de logs de depuração (Agora como ArrayList para guardar cores)
$Global:Un1AnalysisLog = [System.Collections.ArrayList]::new()
 
function Write-Un1Log {
    param (
        [string]$Category = "INFO",
        [string]$Message, 
        [string]$Color = "Gray"
    )
    
    $timestamp = Get-Date -Format "HH:mm:ss.fff"
    $formattedMessage = "$timestamp [$Category] $Message"

    # Não imprimir no terminal — somente armazenar no log global
    if ($null -ne $Global:Un1AnalysisLog) {
        [void]$Global:Un1AnalysisLog.Add([PSCustomObject]@{
                Timestamp = $timestamp
                Category  = $Category
                Message   = $Message
                Color     = $Color
                Text      = $formattedMessage
            })
    }
    
    # Atualiza a SplashScreen da UI automaticamente, se existir
    if ($null -ne $Global:Un1LogAction) { 
        & $Global:Un1LogAction $Message 
    }
}

function Initialize-Un1nst4ll3rEvidenceRecord {
    param (
        [Parameter(Mandatory = $true)]
        [PSObject]$App
    )

    $arrayProperties = @(
        'RegistryKeyPaths',
        'CleanupRegistryTargets',
        'ResolvedLocalCandidates',
        'RootPathCandidates',
        'CleanupDirectoryTargets',
        'ExeCandidates',
        'IconCandidates',
        'ShortcutTitles',
        'ShortcutTargets',
        'ShortcutPaths',
        'ShortcutScopes',
        'ShortcutIconLocations',
        'MuiCacheMatches',
        'UninstallCandidates',
        'ResolvedBy'
    )

    foreach ($property in $arrayProperties) {
        if ($App.PSObject.Properties.Name -notcontains $property -or $null -eq $App.$property) {
            Add-Member -InputObject $App -MemberType NoteProperty -Name $property -Value ([System.Collections.ArrayList]::new()) -Force
        }
        elseif ($App.$property -isnot [System.Collections.ArrayList]) {
            $buffer = [System.Collections.ArrayList]::new()
            foreach ($item in @($App.$property)) {
                if ($null -ne $item) { [void]$buffer.Add($item) }
            }
            $App.$property = $buffer
        }
    }

    $scalarDefaults = @{
        RegistryKey           = ""
        SourceRegistryPath    = ""
        InstallLocationRaw    = ""
        DisplayIconRaw        = ""
        RootPath              = ""
        RootSource            = ""
        AppxPackageFamilyName = ""
        AppxInstallLocation   = ""
        ShortcutPath          = ""
        ShortcutScope         = ""
    }

    foreach ($property in $scalarDefaults.Keys) {
        if ($App.PSObject.Properties.Name -notcontains $property -or $null -eq $App.$property) {
            Add-Member -InputObject $App -MemberType NoteProperty -Name $property -Value $scalarDefaults[$property] -Force
        }
    }
}

function Add-Un1nst4ll3rEvidenceValue {
    param (
        [Parameter(Mandatory = $true)]
        [PSObject]$App,
        [Parameter(Mandatory = $true)]
        [string]$Property,
        $Value
    )

    Initialize-Un1nst4ll3rEvidenceRecord -App $App

    if ($null -eq $Value) { return }

    if ($Value -is [string]) {
        $Value = $Value.Trim()
        if ([string]::IsNullOrWhiteSpace($Value)) { return }
    }

    if ($App.PSObject.Properties.Name -notcontains $Property -or $null -eq $App.$Property) {
        Add-Member -InputObject $App -MemberType NoteProperty -Name $Property -Value ([System.Collections.ArrayList]::new()) -Force
    }

    if ($App.$Property -isnot [System.Collections.ArrayList]) {
        $buffer = [System.Collections.ArrayList]::new()
        foreach ($item in @($App.$Property)) {
            if ($null -ne $item) { [void]$buffer.Add($item) }
        }
        $App.$Property = $buffer
    }

    if ($App.$Property -notcontains $Value) {
        [void]$App.$Property.Add($Value)
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

    $shortcutRoots = @(
        [PSCustomObject]@{ Path = $userShellPaths.Desktop; Scope = "Desktop" },
        [PSCustomObject]@{ Path = $userShellPaths.Programs; Scope = "StartMenu" },
        [PSCustomObject]@{ Path = $userShellPaths.Startup; Scope = "Startup" },
        # NOVO: Adicionando a Barra de Tarefas (Taskbar Pinned)
        [PSCustomObject]@{ Path = "$env:APPDATA\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar"; Scope = "Taskbar" },
        [PSCustomObject]@{ Path = $machineShellPaths.'Common Desktop'; Scope = "CommonDesktop" },
        [PSCustomObject]@{ Path = $machineShellPaths.'Common Programs'; Scope = "CommonStartMenu" },
        [PSCustomObject]@{ Path = $machineShellPaths.'Common Startup'; Scope = "CommonStartup" }
    ) | Where-Object { ![string]::IsNullOrWhiteSpace($_.Path) } |
    ForEach-Object { [PSCustomObject]@{ Path = [System.Environment]::ExpandEnvironmentVariables($_.Path); scope = $_.Scope } } |
    Sort-Object Path -Unique

    foreach ($root in $shortcutRoots) {
        $path = $root.Path
        if (Test-Path $path) {
            $lnks = Get-ChildItem -Path $path -Filter "*.lnk" -Recurse -ErrorAction SilentlyContinue
            foreach ($lnk in $lnks) {
                try {
                    $shortcut = $shell.CreateShortcut($lnk.FullName)
                    
                    # NOVO: Expande variáveis de ambiente CRUAS que o COM retorna (ex: %LocalAppData%)
                    $rawTarget = $shortcut.TargetPath
                    $expandedTarget = if (![string]::IsNullOrWhiteSpace($rawTarget)) { [System.Environment]::ExpandEnvironmentVariables($rawTarget) } else { "" }
                    
                    $rawIconLoc = $shortcut.IconLocation
                    $expandedIconLoc = if (![string]::IsNullOrWhiteSpace($rawIconLoc)) { [System.Environment]::ExpandEnvironmentVariables($rawIconLoc) } else { "" }

                    # MUDANÇA DE LÓGICA: Se tem Target, guarda. Se não tem Target, mas TEM IconLocation, guarda também!
                    if (![string]::IsNullOrWhiteSpace($expandedTarget) -or ![string]::IsNullOrWhiteSpace($expandedIconLoc)) {
                        $shortcutCache.Add([PSCustomObject]@{
                                LnkName       = $lnk.BaseName
                                Target        = $expandedTarget
                                Arguments     = $shortcut.Arguments
                                WorkingDir    = if (![string]::IsNullOrWhiteSpace($shortcut.WorkingDirectory)) { [System.Environment]::ExpandEnvironmentVariables($shortcut.WorkingDirectory) } else { "" }
                                IconLocation  = $expandedIconLoc
                                ShortcutPath  = $lnk.FullName
                                ShortcutScope = $root.Scope
                            }) | Out-Null
                    }
                }
                catch {}
            }
        }
    }
    
    Write-Un1Log -Category "SHORTCUT" -Message "Cache complete. $($shortcutCache.Count) shortcuts mapped (including Taskbar)." -Color Green
    return $shortcutCache
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
                        }
                        elseif ($exePath -match 'Program Files' -and $muiCache[$friendlyName] -notmatch 'Program Files') {
                            $muiCache[$friendlyName] = $exePath
                        }
                    }
                }
            }
        }
        catch {}
    }
    
    Write-Un1Log -Category "MUICACHE" -Message "Cache complete. $($muiCache.Count) applications mapped." -Color Green
    return $muiCache
}

# ==========================================
# BLOCO AUXILIAR: Cache do Menu Iniciar (PackageFamilyName -> Friendly Name)
# ==========================================
function Get-Un1nst4ll3rStartAppsCache {
    Write-Un1Log -Category "STARTAPPS" -Message "Building StartApps index..." -Color Cyan
    $startAppsCache = @{}

    try {
        Get-StartApps -ErrorAction Stop | ForEach-Object {
            $entryName = if ($_.Name) { $_.Name.ToString().Trim() } else { "" }
            $appId = if ($_.AppID) { $_.AppID.ToString().Trim() } else { "" }

            if ([string]::IsNullOrWhiteSpace($entryName) -or [string]::IsNullOrWhiteSpace($appId)) { return }
            if ($appId -notmatch '^([^!]+)!.+$') { return }

            $packageFamilyName = $Matches[1]
            if (!$startAppsCache.ContainsKey($packageFamilyName)) {
                $startAppsCache[$packageFamilyName] = $entryName
            }
        }
    }
    catch {
        Write-Un1Log -Category "STARTAPPS" -Message "Get-StartApps is unavailable. AppX display names will use manifest fallbacks." -Color Blue
    }

    Write-Un1Log -Category "STARTAPPS" -Message "Cache complete. $($startAppsCache.Count) AppX names mapped." -Color Green
    return $startAppsCache
}

# ==========================================
# BLOCO AUXILIAR: Resolve Friendly Name de Pacotes AppX
# ==========================================
function Resolve-Un1nst4ll3rAppxDisplayName {
    param (
        [Parameter(Mandatory = $true)]
        $App,
        [Parameter(Mandatory = $true)]
        $Manifest
    )

    if ($null -eq $Global:StartAppsCache) {
        $Global:StartAppsCache = Get-Un1nst4ll3rStartAppsCache
    }

    if ($Global:StartAppsCache.ContainsKey($App.PackageFamilyName)) {
        return $Global:StartAppsCache[$App.PackageFamilyName]
    }

    $nameCandidates = [System.Collections.ArrayList]::new()
    $appNodes = @($Manifest.Package.Applications.Application)

    foreach ($appNode in $appNodes) {
        try {
            if ($appNode.VisualElements -and $appNode.VisualElements.DisplayName) {
                [void]$nameCandidates.Add($appNode.VisualElements.DisplayName)
            }
        }
        catch {}
    }

    if ($Manifest.Package.Properties.DisplayName) {
        [void]$nameCandidates.Add($Manifest.Package.Properties.DisplayName)
    }

    foreach ($candidate in $nameCandidates) {
        $cleanCandidate = if ($candidate) { $candidate.ToString().Trim() } else { "" }
        if (![string]::IsNullOrWhiteSpace($cleanCandidate) -and $cleanCandidate -notlike "ms-resource*") {
            return $cleanCandidate
        }
    }

    return $App.Name
}

# ==========================================
# BLOCO AUXILIAR: Decide se um Pacote AppX deve ser listado
# ==========================================
function Test-Un1nst4ll3rVisibleAppxPackage {
    param (
        [Parameter(Mandatory = $true)]
        $App,
        [Parameter(Mandatory = $true)]
        [string]$DisplayName
    )

    if ($null -eq $Global:StartAppsCache) {
        $Global:StartAppsCache = Get-Un1nst4ll3rStartAppsCache
    }

    $hiddenAppxPackages = @(
        'windows.immersivecontrolpanel',
        'Microsoft.Windows.SecHealthUI',
        'MicrosoftWindows.Client.CBS'
    )
    if ($App.Name -in $hiddenAppxPackages) {
        return $false
    }

    # Pacotes publicados no Menu Iniciar sao tratados como apps reais do usuario.
    if ($Global:StartAppsCache.ContainsKey($App.PackageFamilyName)) {
        return $true
    }

    $cleanDisplayName = if ($DisplayName) { $DisplayName.Trim() } else { "" }
    if ([string]::IsNullOrWhiteSpace($cleanDisplayName)) {
        return $false
    }

    # Se o nome resolvido cai de volta no nome tecnico do pacote e o app nao existe no Start,
    # ele e provavelmente um componente interno do sistema.
    if ($cleanDisplayName -eq $App.Name) {
        return $false
    }

    $publisherText = if ($App.Publisher) { $App.Publisher.ToString() } else { "" }
    $isMicrosoftPackage = (
        $publisherText -match 'CN=Microsoft' -or
        $publisherText -match 'Microsoft Corporation' -or
        $App.Name -like 'Microsoft.*' -or
        $App.Name -like 'windows.*'
    )

    # Apps Microsoft sem entrada de Start costumam ser hosts/componentes do sistema.
    if ($isMicrosoftPackage) {
        return $false
    }

    return $true
}

# ==========================================
# BLOCO AUXILIAR: Resolve Caminho Real do Asset AppX
# ==========================================
function Find-Un1nst4ll3rAppxAssetPath {
    param (
        [string]$InstallLocation,
        [string]$RelativePath
    )

    if ([string]::IsNullOrWhiteSpace($InstallLocation) -or [string]::IsNullOrWhiteSpace($RelativePath)) { return "" }
    if (!(Test-Path $InstallLocation -PathType Container -ErrorAction SilentlyContinue)) { return "" }

    $normalizedRelativePath = $RelativePath.Trim() -replace '/', '\'
    $baseAssetPath = Join-Path $InstallLocation $normalizedRelativePath
    if (Test-Path $baseAssetPath -PathType Leaf -ErrorAction SilentlyContinue) { return $baseAssetPath }

    $assetDirectory = Split-Path $baseAssetPath -Parent
    if (!(Test-Path $assetDirectory -PathType Container -ErrorAction SilentlyContinue)) { return "" }

    $assetName = [System.IO.Path]::GetFileNameWithoutExtension($baseAssetPath)
    $assetExtension = [System.IO.Path]::GetExtension($baseAssetPath)
    if ([string]::IsNullOrWhiteSpace($assetName) -or [string]::IsNullOrWhiteSpace($assetExtension)) { return "" }

    $candidates = @(Get-ChildItem -Path $assetDirectory -Filter "$assetName*$assetExtension" -File -ErrorAction SilentlyContinue)
    if ($candidates.Count -eq 0) { return "" }

    $bestAsset = $candidates |
    Sort-Object `
    @{ Expression = {
            $score = 500
            if ($_.Name -match 'targetsize-48') { $score = 0 }
            elseif ($_.Name -match 'targetsize-44') { $score = 5 }
            elseif ($_.Name -match 'targetsize-40') { $score = 10 }
            elseif ($_.Name -match 'targetsize-32') { $score = 15 }
            elseif ($_.Name -match 'targetsize-64') { $score = 20 }
            elseif ($_.Name -match 'scale-200') { $score = 25 }
            elseif ($_.Name -match 'scale-150') { $score = 30 }
            elseif ($_.Name -match 'scale-100') { $score = 35 }
            elseif ($_.Name -ieq [System.IO.Path]::GetFileName($baseAssetPath)) { $score = 40 }
            if ($_.Name -match 'altform-unplated') { $score += 100 }
            elseif ($_.Name -match 'lightunplated') { $score += 110 }
            elseif ($_.Name -match 'theme-') { $score += 120 }
            $score
        } 
    },
    @{ Expression = { $_.Name.Length } } |
    Select-Object -First 1

    if ($bestAsset) { return $bestAsset.FullName }
    return ""
}

# ==========================================
# BLOCO AUXILIAR: Resolve Icone de Pacotes AppX
# ==========================================
function Resolve-Un1nst4ll3rAppxLogoPath {
    param (
        [Parameter(Mandatory = $true)]
        $App,
        [Parameter(Mandatory = $true)]
        $Manifest
    )

    if ([string]::IsNullOrWhiteSpace($App.InstallLocation)) { return "" }

    $logoCandidates = [System.Collections.ArrayList]::new()
    $appNodes = @($Manifest.Package.Applications.Application)

    foreach ($appNode in $appNodes) {
        try {
            $visual = $appNode.VisualElements
            if ($visual) {
                foreach ($candidate in @(
                        $visual.Square44x44Logo,
                        $visual.SmallLogo,
                        $visual.Logo,
                        $visual.Square150x150Logo,
                        $visual.DefaultTile.Square71x71Logo,
                        $visual.DefaultTile.Square150x150Logo
                    )) {
                    if (![string]::IsNullOrWhiteSpace($candidate)) {
                        [void]$logoCandidates.Add($candidate)
                    }
                }
            }
        }
        catch {}
    }

    if ($Manifest.Package.Properties.Logo) {
        [void]$logoCandidates.Add($Manifest.Package.Properties.Logo)
    }

    foreach ($logoCandidate in ($logoCandidates | Select-Object -Unique)) {
        $resolvedAsset = Find-Un1nst4ll3rAppxAssetPath -InstallLocation $App.InstallLocation -RelativePath $logoCandidate
        if (![string]::IsNullOrWhiteSpace($resolvedAsset)) {
            return $resolvedAsset
        }
    }

    return ""
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

    # Blacklist de pastas nativas do Windows (Recursos)
    $windowsNativePaths = @(
        "$env:windir\",
        "$env:ProgramFiles\Windows NT\",
        "$env:ProgramFiles\Windows Media Player\",
        "$env:ProgramFiles\Windows Photo Viewer\",
        "$env:ProgramFiles (x86)\Windows NT\",
        "$env:ProgramFiles (x86)\Windows Media Player\",
        "$env:ProgramFiles (x86)\Windows Photo Viewer\",
        "$env:ProgramFiles\Windows Defender\",
        "$env:ProgramFiles\Windows Mail\"
    )

    foreach ($muiName in $Global:MemoryMuiCache.Keys) {
        $muiData = $Global:MemoryMuiCache[$muiName]
        
        # CORREÇÃO: Desempacota o objeto se ele vier com ExePath e RegKeyName
        if ($muiData -is [PSCustomObject] -and $muiData.PSObject.Properties.Name -contains 'ExePath') {
            $exePath = $muiData.ExePath
        }
        else {
            $exePath = $muiData # Fallback de compatibilidade se for string
        }
        
        # Validação básica de existência
        if ([string]::IsNullOrWhiteSpace($exePath) -or !(Test-Path $exePath)) { 
            Write-Un1Log -Category "ORPHAN" -Message "Skipped (ExePath missing or invalid): $muiName" -Color DarkGray
            continue 
        }
        
        # ======================================================================
        # FILTRO 1: O EXE é um Setup/Instalador/Desinstalador? (Rejeita na raiz)
        # ======================================================================
        $muiExeName = Split-Path $exePath -Leaf
        $setupBlacklist = @('setup', 'install', 'uninstall', 'unins\d+', '-setup\.exe$', '-install\.exe$')
        $isSetupFile = $false
        foreach ($pattern in $setupBlacklist) {
            if ($muiExeName -match $pattern) { $isSetupFile = $true; break }
        }
        if ($isSetupFile) {
            Write-Un1Log -Category "ORPHAN" -Message "Skipped (Setup/Installer file): $muiExeName" -Color DarkGray
            continue
        }

        # ======================================================================
        # FILTRO 2: O CAMINHO é de Download/Temporário?
        # ======================================================================
        if ($exePath -match '(\\Downloads\\|\\Desktop\\|\\Temp\\|\\\$Recycle.Bin\\)') {
            Write-Un1Log -Category "ORPHAN" -Message "Skipped (Invalid path): $exePath" -Color DarkGray
            continue
        }
        
        $installDir = Split-Path $exePath
        
        # DEDUPLICAÇÃO POR NOME (VALIDAÇÃO FUZZY)
        $isAlreadyMappedByName = $false
        foreach ($known in $knownNames) {
            if ([string]::IsNullOrWhiteSpace($known)) { continue }
            # Se um nome contém o outro (ex: "Notepad++" está dentro de "Notepad++ a free..."), pula!
            if ($muiName -like "*$known*" -or $known -like "*$muiName*") {
                $isAlreadyMappedByName = $true
                break
            }
        }
        if ($isAlreadyMappedByName) { 
            Write-Un1Log -Category "ORPHAN" -Message "Skipped (Name already in Registry - Fuzzy Match): $muiName" -Color DarkGray
            continue 
        }
        
        # BLACKLIST DE RECURSOS DO WINDOWS (LOG ADICIONADO)
        $isWindowsFeature = $false
        foreach ($winPath in $windowsNativePaths) {
            if ($installDir.StartsWith($winPath, [System.StringComparison]::OrdinalIgnoreCase)) { $isWindowsFeature = $true; break }
        }
        if ($isWindowsFeature) { 
            Write-Un1Log -Category "ORPHAN" -Message "Skipped (Windows native feature): $muiName" -Color DarkGray
            continue 
        }

        # DEDUPLICAÇÃO HIERÁRQUICA POR PASTA (LOG ADICIONADO)
        $isAlreadyMapped = $false
        $normCurrent = $installDir.TrimEnd('\').ToLower()
        foreach ($knownDir in $knownLocals) {
            $normKnown = $knownDir.TrimEnd('\').ToLower()
            if ($normCurrent -eq $normKnown -or $normCurrent.StartsWith($normKnown + "\") -or $normKnown.StartsWith($normCurrent + "\")) {
                $isAlreadyMapped = $true
                break
            }
        }
        if ($isAlreadyMapped) { 
            Write-Un1Log -Category "ORPHAN" -Message "Skipped (Folder already mapped by another app): $muiName ($installDir)" -Color DarkGray
            continue 
        }
        
        # ======================================================================
        # VERIFICAÇÃO FINAL: Tem Uninstaller?
        # ======================================================================
        $uninstallString = ""
        
        # TENTATIVA 1: Procura no Disco (Raiz + 1 nível)
        $diskUninstallers = Get-ChildItem -Path $installDir -Filter "*.exe" -File -Recurse -Depth 1 -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -match '^uninstall|^unins\d+'
        } | Select-Object -First 1
        
        if ($diskUninstallers) {
            $uninstallString = "`"$($diskUninstallers.FullName)`""
            Write-Un1Log -Category "ORPHAN" -Message "Uninstaller found via Disk Heuristic: $($diskUninstallers.FullName)" -Color Cyan
        }
        
        # TENTATIVA 2: Atalhos
        if (!$uninstallString -and $Global:MemoryShortcuts.Count -gt 0) {
            $lnkUninstaller = $Global:MemoryShortcuts | Where-Object { 
                $_.Target -like "$installDir*" -and $_.Target -match 'uninstall|unins\d+' -and $_.Target -match '\.exe$'
            } | Select-Object -First 1
            
            if ($lnkUninstaller -and (Test-Path $lnkUninstaller.Target)) {
                $uninstallString = "`"$($lnkUninstaller.Target)`""
                Write-Un1Log -Category "ORPHAN" -Message "Uninstaller found via Shortcut: $($lnkUninstaller.Target)" -Color Cyan
            }
        }
        
        # Se passou por tudo, mas não tem uninstall, rejeita como sem desinstalador
        if ([string]::IsNullOrWhiteSpace($uninstallString)) {
            Write-Un1Log -Category "ORPHAN" -Message "Skipped (No valid uninstaller): $muiName" -Color DarkGray
            continue
        }

        Write-Un1Log -Category "ORPHAN" -Message "Unregistered app mapped: $muiName (Dir: $installDir)" -Color Green
        
        $orphanRecord = [PSCustomObject]@{
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
            DisplayIcon          = "$exePath"
            ExePath              = $exePath 
            ShortcutTitle        = "" 
            ShortcutTarget       = "" 
        }

        Initialize-Un1nst4ll3rEvidenceRecord -App $orphanRecord
        $orphanRecord.RootPath = $installDir
        $orphanRecord.RootSource = "OrphanDiscovery"
        Add-Un1nst4ll3rEvidenceValue -App $orphanRecord -Property "ResolvedLocalCandidates" -Value $installDir
        Add-Un1nst4ll3rEvidenceValue -App $orphanRecord -Property "RootPathCandidates" -Value $installDir
        Add-Un1nst4ll3rEvidenceValue -App $orphanRecord -Property "CleanupDirectoryTargets" -Value $installDir
        Add-Un1nst4ll3rEvidenceValue -App $orphanRecord -Property "ExeCandidates" -Value $exePath
        Add-Un1nst4ll3rEvidenceValue -App $orphanRecord -Property "UninstallCandidates" -Value $uninstallString
        Add-Un1nst4ll3rEvidenceValue -App $orphanRecord -Property "MuiCacheMatches" -Value $muiName
        Add-Un1nst4ll3rEvidenceValue -App $orphanRecord -Property "ResolvedBy" -Value "OrphanDiscovery"

        # ==========================================
        # CHAMADA DA NOVA FUNÇÃO AQUI
        # ==========================================
        Register-Un1nst4ll3rOrphanToRegistry -App $orphanRecord

        $orphans.Add($orphanRecord) | Out-Null    
    }
    
    Write-Un1Log -Category "ORPHAN" -Message "Orphan discovery complete. $($orphans.Count) unregistered apps found." -Color Magenta
    return $orphans
}

# ==========================================
# BLOCO AUXILIAR: Injeta Órfãos no Registro do Windows
# ==========================================
function Register-Un1nst4ll3rOrphanToRegistry {
    param (
        [Parameter(Mandatory = $true)]
        [PSObject]$App
    )

    $safeName = ($App.Nome -replace '[^\w\s\-]', '').Trim() -replace '\s+', '_'
    $regKeyName = "Un1nst4ll3r_Orphan_$safeName"
    
    $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\$regKeyName"
    $regPathNormalized = "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Uninstall\$regKeyName"

    try {
        if (!(Test-Path $regPath)) {
            New-Item -Path $regPath -Force -ErrorAction Stop | Out-Null
            Write-Un1Log -Category "ORPHAN" -Message "Injecting synthetic registry entry for orphan: $regKeyName" -Color Cyan
        }

        $publisher = "Unknown (Mapped by Un1nst4ll3r)"
        try {
            if (![string]::IsNullOrWhiteSpace($App.ExePath) -and (Test-Path $App.ExePath)) {
                $fileInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($App.ExePath)
                if (![string]::IsNullOrWhiteSpace($fileInfo.CompanyName)) { $publisher = $fileInfo.CompanyName }
            }
        }
        catch {}

        # Grava APENAS os dados originais validados no Scan. Sem gambiarras.
        $regProperties = @{
            DisplayName     = $App.Nome
            InstallLocation = $App.Local
            UninstallString = $App.UninstallString
            DisplayIcon     = $App.ExePath
            PSChildName     = $regKeyName
            NoModify        = 1
            NoRepair        = 1
            SystemComponent = 0
        }

        $nativeFailed = $false
        foreach ($prop in $regProperties.Keys) {
            try {
                Set-ItemProperty -Path $regPath -Name $prop -Value $regProperties[$prop] -ErrorAction Stop
            }
            catch {
                $nativeFailed = $true
                break
            }
        }

        if ($nativeFailed) {
            Write-Un1Log -Category "ORPHAN" -Message "Falha de acesso ao registro. Tentando elevação: $regPathNormalized" -Color Magenta
            
            $cmd = "reg add `"$regPathNormalized`" /f"
            $cmd += " & reg add `"$regPathNormalized`" /v `"DisplayName`" /t REG_SZ /d `"$($App.Nome)`" /f"
            $cmd += " & reg add `"$regPathNormalized`" /v `"InstallLocation`" /t REG_SZ /d `"$($App.Local)`" /f"
            $cmd += " & reg add `"$regPathNormalized`" /v `"UninstallString`" /t REG_SZ /d `"$($App.UninstallString)`" /f"
            $cmd += " & reg add `"$regPathNormalized`" /v `"DisplayIcon`" /t REG_SZ /d `"$($App.ExePath)`" /f"
            $cmd += " & reg add `"$regPathNormalized`" /v `"Publisher`" /t REG_SZ /d `"$publisher`" /f"
            $cmd += " & reg add `"$regPathNormalized`" /v `"NoModify`" /t REG_DWORD /d 1 /f"
            $cmd += " & reg add `"$regPathNormalized`" /v `"NoRepair`" /t REG_DWORD /d 1 /f"
            $cmd += " & reg add `"$regPathNormalized`" /v `"SystemComponent`" /t REG_DWORD /d 0 /f"

            Start-Process -FilePath "cmd.exe" -ArgumentList "/c $cmd" -Verb RunAs -Wait -WindowStyle Hidden -ErrorAction Stop | Out-Null
        }

        # Atualiza o objeto em memória para o JSON
        $App.Chave = $regKeyName
        $App.RegistryKey = $regKeyName
        $App.SourceRegistryPath = $regPath
        Add-Un1nst4ll3rEvidenceValue -App $App -Property "RegistryKeyPaths" -Value $regPath
        Add-Un1nst4ll3rEvidenceValue -App $App -Property "CleanupRegistryTargets" -Value $regPath
        Add-Un1nst4ll3rEvidenceValue -App $App -Property "ResolvedBy" -Value "OrphanRegistryInjection"
        
        Write-Un1Log -Category "ORPHAN" -Message "Synthetic registry entry successfully updated for: $($App.Nome)" -Color Green

    }
    catch {
        Write-Un1Log -Category "ORPHAN" -Message "Failed to inject registry entry for $($App.Nome): $_" -Color DarkRed
    }
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
                    Write-Un1Log -Category "SCAN" -Message "Registry found: $($item.DisplayName)" -Color Orange
                    
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

                    $displayIconValue = if ($item.DisplayIcon) { ($item.DisplayIcon -replace '\"', '' -replace ',\d+$', '').Trim() } else { "" }
                    $installLocationValue = if ($installDir) { $installDir.TrimEnd('\') } else { "" }
                    $registryRecord = [PSCustomObject]@{
                        Nome                 = $item.DisplayName
                        Versao               = $item.DisplayVersion
                        Fabricante           = if ($publisher) { $publisher } else { "N/A" }
                        Tamanho              = $sizeBytes
                        Local                = $installLocationValue
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
                        DisplayIcon          = $displayIconValue
                        ExePath              = ""
                        ShortcutTitle        = "" 
                        ShortcutTarget       = "" 
                    }

                    Initialize-Un1nst4ll3rEvidenceRecord -App $registryRecord
                    $registryRecord.RegistryKey = $item.PSChildName
                    $registryRecord.SourceRegistryPath = if ($item.PSPath) { $item.PSPath } else { "" }
                    $registryRecord.InstallLocationRaw = if ($item.InstallLocation) { $item.InstallLocation.ToString().Trim() } else { "" }
                    $registryRecord.DisplayIconRaw = if ($item.DisplayIcon) { $item.DisplayIcon.ToString().Trim() } else { "" }
                    $registryRecord.RootPath = $installLocationValue
                    $registryRecord.RootSource = if ($installLocationValue) { "Registry.InstallLocation" } else { "" }
                    Add-Un1nst4ll3rEvidenceValue -App $registryRecord -Property "RegistryKeyPaths" -Value $item.PSPath
                    Add-Un1nst4ll3rEvidenceValue -App $registryRecord -Property "CleanupRegistryTargets" -Value $item.PSPath
                    Add-Un1nst4ll3rEvidenceValue -App $registryRecord -Property "ResolvedLocalCandidates" -Value $installLocationValue
                    Add-Un1nst4ll3rEvidenceValue -App $registryRecord -Property "RootPathCandidates" -Value $installLocationValue
                    Add-Un1nst4ll3rEvidenceValue -App $registryRecord -Property "CleanupDirectoryTargets" -Value $installLocationValue
                    Add-Un1nst4ll3rEvidenceValue -App $registryRecord -Property "IconCandidates" -Value $displayIconValue
                    Add-Un1nst4ll3rEvidenceValue -App $registryRecord -Property "UninstallCandidates" -Value $registryRecord.UninstallString
                    Add-Un1nst4ll3rEvidenceValue -App $registryRecord -Property "ResolvedBy" -Value "Registry.Uninstall"

                    $installedPrograms.Add($registryRecord) | Out-Null
                }
            }
        }
    }
    #--- Desboberta de Apps Modernos (AppX) ---
    if ($null -eq $Global:StartAppsCache) { $Global:StartAppsCache = Get-Un1nst4ll3rStartAppsCache }
    $appxPackages = Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { $_.IsFramework -eq $false -and $_.SignatureKind -ne "None" }
    foreach ($app in $appxPackages) {
        if ($app.Name -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}') { continue }
        try {
            $manifest = $app | Get-AppxPackageManifest -ErrorAction Stop
            #$isHidden = (-not $manifest.Package.Applications.Application.AppListEntry -or $manifest.Package.Applications.Application.AppListEntry -eq "none")
            #if ($isHidden -and $app.Publisher -match "Microsoft") { continue }
            #if ($app.Publisher -match "Microsoft Windows") { continue }

            Write-Un1Log -Category "SCAN" -Message "AppX found: $($app.Name)" -Color Orange
            
            $displayName = Resolve-Un1nst4ll3rAppxDisplayName -App $app -Manifest $manifest
            if (!(Test-Un1nst4ll3rVisibleAppxPackage -App $app -DisplayName $displayName)) {
                Write-Un1Log -Category "SCAN" -Message "AppX skipped (hidden/system component): $($app.Name)" -Color Blue
                continue
            }
            $displayIcon = Resolve-Un1nst4ll3rAppxLogoPath -App $app -Manifest $manifest
            $cleanPublisher = $app.Publisher; $xmlP = $manifest.Package.Properties.PublisherDisplayName; if ($xmlP -and $xmlP -notlike "ms-resource*") { $cleanPublisher = $xmlP } elseif ($cleanPublisher -match 'CN=([^,]+)') { $cleanPublisher = $matches[1] } elseif ($cleanPublisher -match '^[0-9a-fA-F]{8}-') { $cleanPublisher = "N/A" }

            $appxRecord = [PSCustomObject]@{
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
                DisplayIcon          = $displayIcon
                NoRemove             = $false
                NoModify             = $true
                NoRepair             = $true
                ShortcutTitle        = ""
                ShortcutTarget       = ""
            }

            Initialize-Un1nst4ll3rEvidenceRecord -App $appxRecord
            $appxRecord.AppxPackageFamilyName = $app.PackageFamilyName
            $appxRecord.AppxInstallLocation = if ($app.InstallLocation) { $app.InstallLocation.TrimEnd('\') } else { "" }
            $appxRecord.InstallLocationRaw = if ($app.InstallLocation) { $app.InstallLocation.ToString().Trim() } else { "" }
            $appxRecord.DisplayIconRaw = $displayIcon
            $appxRecord.RootPath = $appxRecord.Local
            $appxRecord.RootSource = if ($appxRecord.Local) { "Appx.InstallLocation" } else { "" }
            Add-Un1nst4ll3rEvidenceValue -App $appxRecord -Property "ResolvedLocalCandidates" -Value $appxRecord.Local
            Add-Un1nst4ll3rEvidenceValue -App $appxRecord -Property "RootPathCandidates" -Value $appxRecord.Local
            Add-Un1nst4ll3rEvidenceValue -App $appxRecord -Property "CleanupDirectoryTargets" -Value $appxRecord.Local
            Add-Un1nst4ll3rEvidenceValue -App $appxRecord -Property "IconCandidates" -Value $displayIcon
            Add-Un1nst4ll3rEvidenceValue -App $appxRecord -Property "ResolvedBy" -Value "Appx.Manifest"

            $installedPrograms.Add($appxRecord) | Out-Null
        }
        catch {}
    }
    
    # ==========================================
    # BLOCO 1.5: Descoberta de Apps sem Registro (Orphans)
    # ==========================================
    # O uso do @() garante que mesmo se houver só 1 órfão, ele venha como Array
    $orphanApps = @(Find-Un1nst4ll3rOrphans -ResolvedPrograms $installedPrograms)
    
    if ($orphanApps.Count -gt 0) {
        foreach ($orphan in $orphanApps) {
            $installedPrograms.Add($orphan) | Out-Null
        }
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
        [Parameter(Mandatory = $true)]
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
    $genericFolderNames = @("support", "system", "bin", "helper", "config", "resources", "data", "common", "lib", "tools", "files", "uninstall", "drivers", "plugins", "extensions", "modules", "games", "redist")
    $invalidHeuristicRoots = @("microsoft", "windows apps", "common files", "dotnet", "reference assemblies")

    foreach ($prog in $ProgramList) {
        Write-Un1Log -Category "LOCATE" -Message "Processing: $($prog.Nome) ---" -Color Cyan
        Initialize-Un1nst4ll3rEvidenceRecord -App $prog
        Add-Un1nst4ll3rEvidenceValue -App $prog -Property "ResolvedLocalCandidates" -Value $prog.Local
        Add-Un1nst4ll3rEvidenceValue -App $prog -Property "RootPathCandidates" -Value $prog.Local
        Add-Un1nst4ll3rEvidenceValue -App $prog -Property "CleanupDirectoryTargets" -Value $prog.Local
        Add-Un1nst4ll3rEvidenceValue -App $prog -Property "ExeCandidates" -Value $prog.ExePath
        Add-Un1nst4ll3rEvidenceValue -App $prog -Property "IconCandidates" -Value $prog.DisplayIcon
        Add-Un1nst4ll3rEvidenceValue -App $prog -Property "UninstallCandidates" -Value $prog.UninstallString
        Add-Un1nst4ll3rEvidenceValue -App $prog -Property "ShortcutTitles" -Value $prog.ShortcutTitle
        Add-Un1nst4ll3rEvidenceValue -App $prog -Property "ShortcutTargets" -Value $prog.ShortcutTarget
        Add-Un1nst4ll3rEvidenceValue -App $prog -Property "ShortcutPaths" -Value $(if ($prog.PSObject.Properties.Name -contains 'ShortcutPath') { $prog.ShortcutPath } else { "" })
        Add-Un1nst4ll3rEvidenceValue -App $prog -Property "ShortcutScopes" -Value $(if ($prog.PSObject.Properties.Name -contains 'ShortcutScope') { $prog.ShortcutScope } else { "" })

        # ======================================================================
        # SHORT-CIRCUIT: Se o Registro já deu tudo, pula heurísticas complexas
        # Aplica a regra: "Registro é Rei, se deu as pistas pula tudo".
        # Resolve 90% dos apps (incluindo todo o Office) em 1 milissegundo.
        # ======================================================================
        if (![string]::IsNullOrWhiteSpace($prog.Local) -and (Test-Path $prog.Local -ErrorAction SilentlyContinue) -and ![string]::IsNullOrWhiteSpace($prog.DisplayIcon)) {
            $cleanIconEarly = $prog.DisplayIcon -replace '\"', '' -replace ',\d+$', ''
            
            # Valida se o ícone do registro é um arquivo real e não é um recurso do Windows
            if ((Test-Path $cleanIconEarly -ErrorAction SilentlyContinue) -and $cleanIconEarly -notmatch 'shell32|imageres|Windows\\SysWOW64|Windows\\System32') {
                $prog.Local = $prog.Local.TrimEnd('\')
                $prog.RootPath = $prog.Local
                $prog.RootSource = "Registry.Full"
                
                # Se o ícone do registro aponta para um .exe, esse É o app principal.
                if ($cleanIconEarly -match '\.exe$') { 
                    $prog.ExePath = $cleanIconEarly 
                }
                
                Add-Un1nst4ll3rEvidenceValue -App $prog -Property "ResolvedBy" -Value "Registry.Full"
                Write-Un1Log -Category "LOCATE" -Message "Perfect registry data. Skipping heavy heuristics." -Color Green

                # ======================================================================
                # FIX: Coleta Rápida de Atalhos APENAS PARA LIMPEZA (Desktop/Taskbar)
                # O Registro já nos deu o Local, ExePath e DisplayIcon perfeitos.
                # Não queremos sobrescrever NADA, só mapear os arquivos .lnk para deletar.
                # ======================================================================
                if (![string]::IsNullOrWhiteSpace($prog.Nome) -and $null -ne $Global:MemoryShortcuts -and $Global:MemoryShortcuts.Count -gt 0) {
                    $safeAppNameSC = $prog.Nome -replace '\(.*\)', '' -replace '\s+\d+.*', '' -replace '[^\w\s\-+]', ''
                    $lnkMatches = $Global:MemoryShortcuts | Where-Object { 
                        $_.LnkName -ieq $prog.Nome -or $_.LnkName -like "*$safeAppNameSC*"
                    }
                    foreach ($lnk in $lnkMatches) {
                        # Registramos APENAS o caminho do atalho para a limpeza futura
                        Add-Un1nst4ll3rEvidenceValue -App $prog -Property "ShortcutPaths" -Value $lnk.ShortcutPath
                        Add-Un1nst4ll3rEvidenceValue -App $prog -Property "ShortcutScopes" -Value $lnk.ShortcutScope
                        
                        # NÃO coletamos IconLocation, Target ou WorkingDir aqui.
                        # O Registro já nos deu as informações confiáveis (Rei).
                    }
                }

                $updatedList.Add($prog) | Out-Null
                continue # Pula para o próximo app imediatamente

            }
        }

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
            $muiEntry = $Global:MemoryMuiCache[$prog.Nome]
            
            # Se não achou exato, tenta casar pelo nome limpo (sem versão)
            if (!$muiEntry) {
                $safeAppName = $prog.Nome -replace '\(.*\)', '' -replace '\s+\d+.*', '' -replace '[^\w\s\-+]', ''
                $safeAppName = $safeAppName.Trim()
                if (![string]::IsNullOrWhiteSpace($safeAppName)) {
                    $matchKey = $Global:MemoryMuiCache.Keys | Where-Object { $_ -like "*$safeAppName*" -or $safeAppName -like "*$_*" } | Select-Object -First 1
                    if ($matchKey) { $muiEntry = $Global:MemoryMuiCache[$matchKey] }
                }
            }

            # CORREÇÃO: Desempacota o objeto se ele vier com ExePath e RegKeyName
            $muiExe = $null
            if ($muiEntry -is [PSCustomObject] -and $muiEntry.PSObject.Properties.Name -contains 'ExePath') {
                $muiExe = $muiEntry.ExePath
            }
            else {
                $muiExe = $muiEntry # Fallback de compatibilidade se for string
            }
            Add-Un1nst4ll3rEvidenceValue -App $prog -Property "MuiCacheMatches" -Value $(if ($matchKey) { $matchKey } else { $prog.Nome })
            Add-Un1nst4ll3rEvidenceValue -App $prog -Property "ExeCandidates" -Value $muiExe

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
                    $prog.RootSource = "MuiCache"
                    Add-Un1nst4ll3rEvidenceValue -App $prog -Property "ResolvedBy" -Value "MuiCache"
                    Write-Un1Log -Category "LOCATE" -Message "GOT via MuiCache! Exe=$muiExe | Dir=$dir (Skipped Disk Scan & Exe Heuristic)" -Color Green
                }
            }
            elseif ($muiExe -and !$isValidMuiExe) {
                # Log avisando que o MuiCache tentou nos enganar, mas falhou!
                Write-Un1Log -Category "LOCATE" -Message "MuiCache rejected (Setup/Invalid path): $muiExe" -Color Blue
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
            
            # NOVA LÓGICA: Classificar por NÍVEL DE CONFIANÇA para evitar falsos positivos
            $exactMatch = @($lnkFiles | Where-Object { $_.LnkName -ieq $prog.Nome })
            $startsWithMatch = @($lnkFiles | Where-Object { $_.LnkName -ilike "$($prog.Nome)*" -and $_.LnkName -ine $prog.Nome })
            $containsMatch = @($lnkFiles | Where-Object { $_.LnkName -ilike "*$($prog.Nome)*" -and $_.LnkName -inotlike "$($prog.Nome)*" })

            $prioritizedLnks = @($exactMatch) + @($startsWithMatch) + @($containsMatch)

            foreach ($lnk in $prioritizedLnks) {
                $target = $lnk.Target
                $startIn = $lnk.WorkingDir
                
                # ======================================================================
                # PASSO 1: SEMPRE registra a evidência do ÍCONE e Metadados para TODOS os atalhos!
                # Isso garante que atalhos na Desktop/Taskbar serão mapeados para limpeza.
                # ======================================================================
                if (![string]::IsNullOrWhiteSpace($lnk.IconLocation)) {
                    Add-Un1nst4ll3rEvidenceValue -App $prog -Property "ShortcutIconLocations" -Value $lnk.IconLocation
                }
                Add-Un1nst4ll3rEvidenceValue -App $prog -Property "ShortcutTitles" -Value $lnk.LnkName
                Add-Un1nst4ll3rEvidenceValue -App $prog -Property "ShortcutPaths" -Value $lnk.ShortcutPath
                Add-Un1nst4ll3rEvidenceValue -App $prog -Property "ShortcutScopes" -Value $lnk.ShortcutScope

                # ======================================================================
                # PASSO 2: Validação do TARGET para achar a pasta de instalação (guessedPath)
                # SÓ atualiza o guessedPath se ainda não o encontramos (!guessedPath)
                # ======================================================================
                if (!$guessedPath -and ![string]::IsNullOrWhiteSpace($target) -and (Test-Path $target -ErrorAction SilentlyContinue) -and $target -match '\.exe$' -and $target -notmatch 'Windows\\System') {
                    if ($target -notmatch 'uninstall|unins\d+|setup') {
                        $exeFromShortcut = $target
                        $prog.ShortcutTitle = $lnk.LnkName
                        $prog.ShortcutTarget = $target
                        $prog.ShortcutPath = $lnk.ShortcutPath
                        $prog.ShortcutScope = $lnk.ShortcutScope
                        
                        Add-Un1nst4ll3rEvidenceValue -App $prog -Property "ShortcutTargets" -Value $target
                        Add-Un1nst4ll3rEvidenceValue -App $prog -Property "ExeCandidates" -Value $target
                        
                        $dir = if (![string]::IsNullOrWhiteSpace($startIn) -and (Test-Path $startIn)) { $startIn } else { Split-Path $target }
                        if ($dir -and (Test-Path $dir)) { 
                            $guessedPath = $dir
                            $prog.RootSource = "Shortcut.Target"
                            Add-Un1nst4ll3rEvidenceValue -App $prog -Property "ResolvedBy" -Value "Shortcut.Target"
                            Write-Un1Log -Category "LOCATE" -Message "Exe & Local found via Shortcut: Exe=$target | Dir=$dir" -Color Green
                            # NÃO DAMOS BREAK AQUI! O loop continua para coletar os outros .lnk
                        }
                    }
                } 
                # ======================================================================
                # BÔNUS: E se o Target for ruim, mas o ÍCONE aponta pra pasta do app?
                # ======================================================================
                elseif (!$guessedPath -and ![string]::IsNullOrWhiteSpace($lnk.IconLocation)) {
                    $cleanIconPath = $lnk.IconLocation -replace ',\d+$', '' -replace '"', ''
                    $iconDir = Split-Path $cleanIconPath -ErrorAction SilentlyContinue
                    
                    if (![string]::IsNullOrWhiteSpace($iconDir) -and (Test-Path $iconDir -ErrorAction SilentlyContinue) -and $iconDir -notmatch 'Windows\\System') {
                        $guessedPath = $iconDir
                        $prog.RootSource = "Shortcut.IconLocation"
                        Add-Un1nst4ll3rEvidenceValue -App $prog -Property "ResolvedBy" -Value "Shortcut.IconLocation"
                        Write-Un1Log -Category "LOCATE" -Message "Local found via Shortcut IconLocation: Dir=$iconDir" -Color Green
                    }
                }
            }
        }

        # ── PRIORIDADE 4: Shortcut Cache (DisplayIcon from Reg -> ExePath) ──
        if (!$guessedPath -and !$exeFromShortcut -and ![string]::IsNullOrWhiteSpace($prog.DisplayIcon)) {
            $cleanIcon = $prog.DisplayIcon -replace '\"', '' -replace ',\d+$', ''
            Add-Un1nst4ll3rEvidenceValue -App $prog -Property "IconCandidates" -Value $cleanIcon
            if ((Test-Path $cleanIcon -ErrorAction SilentlyContinue) -and $cleanIcon -notmatch 'Package Cache|Windows\\Installer|shell32|imageres|Windows\\SysWOW64|Windows\\System32') {
                $dir = Split-Path -Path $cleanIcon -ErrorAction SilentlyContinue
                if ($dir -and (Test-Path $dir -ErrorAction SilentlyContinue)) {
                    $guessedPath = $dir
                    $prog.RootSource = "Registry.DisplayIcon"
                    Add-Un1nst4ll3rEvidenceValue -App $prog -Property "ResolvedBy" -Value "Registry.DisplayIcon"
                    # Corrige o vírus: Se o MuiCache achou um exe errado antes, o DisplayIcon sobrescreve agora.
                    if ($cleanIcon -match '\.exe$') { $exeFromShortcut = $cleanIcon }
                    Write-Un1Log -Category "LOCATE" -Message "Local found via DisplayIcon: $guessedPath" -Color Green
                }
            }
        }

        if (!$guessedPath -and ![string]::IsNullOrWhiteSpace($prog.Local) -and (Test-Path $prog.Local)) {
            $guessedPath = $prog.Local
            if ([string]::IsNullOrWhiteSpace($prog.RootSource)) { $prog.RootSource = "Registry.InstallLocation" }
            Add-Un1nst4ll3rEvidenceValue -App $prog -Property "ResolvedBy" -Value "Registry.InstallLocation"
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
                    if ($guessedPath) {
                        $prog.RootSource = "MSI.ProductInfo"
                        Add-Un1nst4ll3rEvidenceValue -App $prog -Property "ResolvedBy" -Value "MSI.ProductInfo"
                        Write-Un1Log -Category "LOCATE" -Message "Local found via MSI COM: $guessedPath" -Color Green
                    }
                }
                catch {}
            }
            if (!$guessedPath -and $prog.UninstallString -notmatch "msiexec") {
                $dir = $null
                if ($prog.UninstallString -match '-f\s*"?([^"]+\.isu|[^\s,]+\.isu)') { $isuPath = $Matches[1]; if (Test-Path $isuPath -ErrorAction SilentlyContinue) { $dir = Split-Path -Path $isuPath -ErrorAction SilentlyContinue } }
                if (!$dir) { $cleanStr = $prog.UninstallString.Trim('"').Trim("'"); $exePath = ($cleanStr -split ' /')[0].Trim(); $dir = Split-Path -Path $exePath -ErrorAction SilentlyContinue }
                if ($dir -and (Test-Path $dir -ErrorAction SilentlyContinue) -and $dir -notmatch 'Package Cache|Windows\\Installer') { 
                    $guessedPath = $dir 
                    Add-Un1nst4ll3rEvidenceValue -App $prog -Property "ExeCandidates" -Value $exePath
                    $prog.RootSource = "UninstallString"
                    Add-Un1nst4ll3rEvidenceValue -App $prog -Property "ResolvedBy" -Value "UninstallString"
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
                                        Add-Un1nst4ll3rEvidenceValue -App $prog -Property "RegistryKeyPaths" -Value $exeKey
                                        Add-Un1nst4ll3rEvidenceValue -App $prog -Property "ExeCandidates" -Value $exePathExpanded
                                        $prog.RootSource = "Registry.AppPaths"
                                        Add-Un1nst4ll3rEvidenceValue -App $prog -Property "ResolvedBy" -Value "Registry.AppPaths"
                                        Write-Un1Log -Category "LOCATE" -Message "Location found via App Paths Registry: $guessedPath (Keyword: $kw)" -Color Green
                                        break
                                    }
                                }
                            }
                        }
                        catch {}
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

            $firstKeyword = if ($appWords.Count -gt 0) { $appWords[0] } else { "" }

            # NOVA SEGURANÇA: Palavras com menos de 4 letras geram muito falso positivo no Disk Scan.
            # É melhor ter "NoLocation" do que apontar para a pasta errada.
            if ($firstKeyword.Length -lt 4) {
                Write-Un1Log -Category "LOCATE" -Message "Disk Heuristic skipped: Keyword '$firstKeyword' is too short (high false-positive risk)." -Color Blue
            }
            elseif ([string]::IsNullOrWhiteSpace($firstKeyword) -and ![string]::IsNullOrWhiteSpace($cacheKeyword)) { 
                $firstKeyword = $cacheKeyword 
            }

            if ([string]::IsNullOrWhiteSpace($firstKeyword) -and ![string]::IsNullOrWhiteSpace($cacheKeyword)) { 
                $firstKeyword = $cacheKeyword 
            }

            if (![string]::IsNullOrWhiteSpace($firstKeyword) -and $firstKeyword.Length -ge 4) {
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
                            Write-Un1Log -Category "LOCATE" -Message "Heuristic rejected: '$($foundDir.Name)' is a generic root." -Color Blue
                            continue
                        }
                        $guessedPath = $foundDir.FullName
                        $prog.RootSource = "Disk.Heuristic"
                        Add-Un1nst4ll3rEvidenceValue -App $prog -Property "ResolvedBy" -Value "Disk.Heuristic"
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
            $prog.RootPath = $guessedPath
            Add-Un1nst4ll3rEvidenceValue -App $prog -Property "ResolvedLocalCandidates" -Value $guessedPath
            Add-Un1nst4ll3rEvidenceValue -App $prog -Property "RootPathCandidates" -Value $guessedPath
            Add-Un1nst4ll3rEvidenceValue -App $prog -Property "CleanupDirectoryTargets" -Value $guessedPath
            if ($prog.Status -eq "NoLocation") { $prog.Status = "OK" } 
            
            # ======================================================================
            # LÓGICA INTELIGENTE DE EXEPATH: Rejeita Updaters e força Heurística
            # ======================================================================
            $updaterPatterns = @('^Update\.exe$', '^Updater\.exe$', '^UpdateHelper\.exe$', '^ChromiumUpdater\.exe$')
            $isUpdater = $false
            
            # Checa se o atalho OU o ExePath pré-existente é um updater
            $candidateExe = if (![string]::IsNullOrWhiteSpace($exeFromShortcut)) { $exeFromShortcut } else { $prog.ExePath }
            if (![string]::IsNullOrWhiteSpace($candidateExe)) {
                $currentExeName = Split-Path $candidateExe -Leaf
                foreach ($pattern in $updaterPatterns) { if ($currentExeName -match $pattern) { $isUpdater = $true; break } }
            }
            
            # Se achamos um exe, mas ele é um Updater, NÃO o aceite. Force a heurística a rodar.
            if (![string]::IsNullOrWhiteSpace($exeFromShortcut) -and !$isUpdater) {
                $prog.ExePath = $exeFromShortcut
                Add-Un1nst4ll3rEvidenceValue -App $prog -Property "ExeCandidates" -Value $exeFromShortcut
                Write-Un1Log -Category "LOCATE" -Message "ExePath confirmed via Shortcut/MuiCache: $exeFromShortcut" -Color Green
            }
            elseif (![string]::IsNullOrWhiteSpace($prog.ExePath) -and !$isUpdater) {
                # Já temos um ExePath pré-preenchido e não é updater
                Add-Un1nst4ll3rEvidenceValue -App $prog -Property "ExeCandidates" -Value $prog.ExePath
                Write-Un1Log -Category "LOCATE" -Message "ExePath already resolved (pre-filled): $($prog.ExePath)" -Color DarkGray
            }
            else {
                # Roda a heurística pesada se não temos NADA, OU se o que achamos era um Updater
                $uninstallExeName = if ($prog.UninstallString -match '\\([^\\]+\.exe)') { $Matches[1] } else { "" }
                
                # Se caiu aqui porque era um Updater, bota o updater na blacklist da heurística
                if ($isUpdater) {
                    $uninstallExeName = (Split-Path $exeFromShortcut -Leaf)
                    Write-Un1Log -Category "LOCATE" -Message "Target is an Updater ($uninstallExeName). Forcing Exe Heuristic to find the real app." -Color Yellow
                }

                $foundExe = Find-Un1nst4ll3rMainExe -Path $guessedPath -AppName $prog.Nome -UninstallExeName $uninstallExeName
                
                if (![string]::IsNullOrWhiteSpace($foundExe)) {
                    $prog.ExePath = $foundExe
                    Add-Un1nst4ll3rEvidenceValue -App $prog -Property "ExeCandidates" -Value $foundExe
                    Add-Un1nst4ll3rEvidenceValue -App $prog -Property "ResolvedBy" -Value "Exe.Heuristic.Override"
                }
                elseif ($isUpdater) {
                    # Heurística falhou em achar o app real (pasta estranha?), fallback para o Updater
                    $prog.ExePath = $exeFromShortcut
                    Add-Un1nst4ll3rEvidenceValue -App $prog -Property "ExeCandidates" -Value $exeFromShortcut
                }
                else {
                    $prog.ExePath = $foundExe
                    Add-Un1nst4ll3rEvidenceValue -App $prog -Property "ExeCandidates" -Value $foundExe
                    if (![string]::IsNullOrWhiteSpace($foundExe)) {
                        Add-Un1nst4ll3rEvidenceValue -App $prog -Property "ResolvedBy" -Value "Exe.Heuristic"
                    }
                }
            }
        } 
        else {
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
                Initialize-Un1nst4ll3rEvidenceRecord -App $Prog
                
                $expandedPath = [System.Environment]::ExpandEnvironmentVariables($rule.CheckPath)
                
                $pathExists = $false
                if ($expandedPath -match '\.\w{3}$') {
                    $pathExists = Test-Path $expandedPath -ErrorAction SilentlyContinue
                }
                else {
                    $pathExists = !([string]::IsNullOrWhiteSpace((Get-Item $expandedPath* -ErrorAction SilentlyContinue | Select-Object -First 1)))
                }

                if ($pathExists) {
                    $resolvedPath = if (![string]::IsNullOrWhiteSpace($rule.LocalPath)) { $rule.LocalPath } else { if ($expandedCheckPath -match '^(.*\\)([^\\]+\.\w{3})$') { $Matches[1] } else { $expandedCheckPath } }
                    $Prog.Local = [System.Environment]::ExpandEnvironmentVariables($resolvedPath).TrimEnd('\')
                    $Prog.RootPath = $Prog.Local
                    $Prog.RootSource = "SysPkgBank"
                    $Prog.Tamanho = 0
                    $Prog.Status = if ($rule.IsSystem -eq $true) { "System" } else { "OK" }
                    $Prog.ExePath = ""
                    Add-Un1nst4ll3rEvidenceValue -App $Prog -Property "ResolvedLocalCandidates" -Value $Prog.Local
                    Add-Un1nst4ll3rEvidenceValue -App $Prog -Property "RootPathCandidates" -Value $Prog.Local
                    Add-Un1nst4ll3rEvidenceValue -App $Prog -Property "CleanupDirectoryTargets" -Value $Prog.Local
                    Add-Un1nst4ll3rEvidenceValue -App $Prog -Property "ResolvedBy" -Value "SysPkgBank"
                    
                    Write-Un1Log -Category "MS-PKG" -Message "Location confirmed via JSON: $($Prog.Local)" -Color Cyan
                    return $true
                }
                else {
                    Write-Un1Log -Category "MS-PKG" -Message "Rule matched, but path missing: $expandedPath" -Color Blue
                }
            }
        }
        catch {
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
        [Parameter(Mandatory = $true)]
        [Array]$ProgramList
    )

    Write-Un1Log -Category "SIZE" -Message "Starting Size Calculation Engine..." -Color Cyan
    $updatedList = [System.Collections.ArrayList]::new()

    Write-Un1Log -Category "SIZE" -Message "Building MSI Installer UserData cache..." -Color Blue
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

    Write-Un1Log -Category "SIZE" -Message "Querying WMI InstalledWin32Program cache..." -Color Blue
    $wmiCache = @{}
    try {
        Get-CimInstance Win32_InstalledWin32Program -ErrorAction Stop | Where-Object { $_.Name -and $_.Size -gt 0 } | ForEach-Object {
            if (!$wmiCache.ContainsKey($_.Name)) {
                $wmiCache[$_.Name] = [long]$_.Size
            }
        }
    }
    catch {
        Write-Un1Log -Category "SIZE" -Message "WMI Win32_InstalledWin32Program not available." -Color Blue
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
                    Write-Un1Log -Category "SIZE" -Message "Measuring disk size (Safe I/O): $($prog.Local)" -Color Blue
                    $bytes = (Get-ChildItem -Path $prog.Local -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                    if ($bytes -gt 0) { 
                        $prog.Tamanho = [long]$bytes 
                        $sizeFriendly = if ($prog.Tamanho -ge 1GB) { "{0:N2} GB" -f ($prog.Tamanho / 1GB) } else { "{0:N2} MB" -f ($prog.Tamanho / 1MB) }
                        Write-Un1Log -Category "SIZE" -Message "Disk size calculated: $sizeFriendly for $($prog.Nome)" -Color Green
                    }
                }
                catch {
                    Write-Un1Log -Category "SIZE" -Message "I/O Error measuring: $($prog.Local)" -Color DarkRed
                }
            }
            else {
                Write-Un1Log -Category "SIZE" -Message "Disk I/O blocked (System protected path): $($prog.Local)" -Color Magenta
            }
        }

        $updatedList.Add($prog) | Out-Null
    }

    Write-Un1Log -Category "SIZE" -Message "Size calculation engine complete." -Color Green
    return $updatedList
}

# ==========================================
# UI: Motor do Spinner Global
# ==========================================
$script:SpinnerSync = $null
$script:SpinnerPS = $null
$script:SpinnerRunspace = $null

function Start-Un1nst4ll3rSpinner {
    param([string]$InitialMessage = "Iniciando...", [System.Drawing.Point]$Location)

    Stop-Un1nst4ll3rSpinner # Garante que nenhum outro esteja rodando

    $script:SpinnerSync = [hashtable]::Synchronized(@{})
    $script:SpinnerSync.Stop = $false
    $script:SpinnerSync.Message = $InitialMessage
    $script:SpinnerSync.PosX = $Location.X
    $script:SpinnerSync.PosY = $Location.Y
    $script:SpinnerSync.AppRoot = $AppRoot 

    $script:SpinnerRunspace = [runspacefactory]::CreateRunspace()
    $script:SpinnerRunspace.ApartmentState = "STA"
    $script:SpinnerRunspace.ThreadOptions = "ReuseThread"
    $script:SpinnerRunspace.Open()
    $script:SpinnerRunspace.SessionStateProxy.SetVariable("sync", $script:SpinnerSync)

    $script:SpinnerPS = [powershell]::Create()
    $script:SpinnerPS.Runspace = $script:SpinnerRunspace

    $script:SpinnerPS.AddScript({
            Add-Type -AssemblyName System.Windows.Forms
            Add-Type -Assembly.Drawing

            $form = New-Object System.Windows.Forms.Form
            $form.Text = "Un1nst4ll3r"
            $form.Size = New-Object System.Drawing.Size(380, 100)
            $form.StartPosition = "Manual"
            $form.Location = New-Object System.Drawing.Point($sync.PosX, $sync.PosY)
            $form.FormBorderStyle = "FixedSingle"
            $form.ControlBox = $false
            $form.TopMost = $true
            $form.BackColor = [System.Drawing.Color]::White

            # ====================================================
            # CONFIGURAÇÃO DE TAMANHO INDEPENDENTE DA IMAGEM
            # ====================================================
            $ImageWidth = 45   # <- Defina aqui a largura exata da imagem
            $ImageHeight = 45  # <- Defina aqui a altura exata da imagem
        
            # A coluna do painel será um pouco maior que a imagem para criar uma "margem" visual
            $ColumnWidth = $ImageWidth + 10 # 48 + 20 = 68px de largura de coluna
            # ====================================================

            $panel = New-Object System.Windows.Forms.TableLayoutPanel
            $panel.Dock = "Fill"
            $panel.ColumnCount = 2
            $panel.RowCount = 1
            $panel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, $ColumnWidth))) | Out-Null
            $panel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100))) | Out-Null

            $imgPath = Join-Path $sync.AppRoot "busy.gif" 
            $picBox = $null
            if (Test-Path $imgPath -ErrorAction SilentlyContinue) {
                $picBox = New-Object System.Windows.Forms.PictureBox
            
                # Define o tamanho exato do PictureBox, independente do painel
                $picBox.Width = $ImageWidth
                $picBox.Height = $ImageHeight
            
                # Zoom para preencher o tamanho exato definido acima (sem distorcer se a imagem não for quadrada)
                $picBox.SizeMode = "StretchImage" 
            
                # Ancoragem: Amarra nos 4 lados. Como o PictureBox é menor que a célula do painel, 
                # isso fará com que ele fique perfeitamente centralizado dentro do espaço da coluna
                $picBox.Anchor = "Left"
            
                $picBox.Image = [System.Drawing.Image]::FromFile($imgPath)
                $panel.Controls.Add($picBox, 0, 0) | Out-Null
            }
            else {
                $lblFallback = New-Object System.Windows.Forms.Label
                $lblFallback.Text = "⏳"
                $lblFallback.Dock = "Fill"
                $lblFallback.TextAlign = "MiddleCenter"
                $lblFallback.Font = New-Object System.Drawing.Font("Segoe UI", 18)
                $panel.Controls.Add($lblFallback, 0, 0) | Out-Null
            }

            $lbl = New-Object System.Windows.Forms.Label
            $lbl.Dock = "Fill"
            $lbl.TextAlign = "MiddleLeft"
            $lbl.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Regular)
            $lbl.Margin = New-Object System.Windows.Forms.Padding(5, 0, 5, 0)
            $lbl.Text = $sync.Message
            $panel.Controls.Add($lbl, 1, 0) | Out-Null

            $form.Controls.Add($panel)

            $timer = New-Object System.Windows.Forms.Timer
            $timer.Interval = 100
            $timer.Add_Tick({
                    if ($sync.Stop) {
                        $timer.Stop()
                        $form.Close()
                    }
                    else {
                        $lbl.Text = $sync.Message
                    }
                })
            $timer.Start()

            [void]$form.ShowDialog()
        
            if ($null -ne $picBox -and $null -ne $picBox.Image) {
                $picBox.Image.Dispose()
            }
            $timer.Dispose()
            $form.Dispose()
        }) | Out-Null

    $script:SpinnerPS.BeginInvoke() | Out-Null
}

function Update-Un1nst4ll3rSpinner {
    param([string]$Message)
    if ($null -ne $script:SpinnerSync) {
        $script:SpinnerSync.Message = $Message
    }
}

function Stop-Un1nst4ll3rSpinner {
    if ($null -ne $script:SpinnerSync) {
        $script:SpinnerSync.Stop = $true
        Start-Sleep -Milliseconds 200 # Dá tempo da UI fechar
    }
    if ($null -ne $script:SpinnerRunspace) {
        $script:SpinnerRunspace.Close()
    }
    if ($null -ne $script:SpinnerPS) {
        $script:SpinnerPS.Dispose()
    }
    $script:SpinnerSync = $null
    $script:SpinnerPS = $null
    $script:SpinnerRunspace = $null
}
