# ======================================================================
#  Un1nst4ll3r-core.ps1 - Motor de Desinstalação e Limpeza (Ação)
#  Versão: 1.0
# ======================================================================

# Inicializa o acumulador global de logs (Independente da UI)
if ($null -eq $Global:Un1AnalysisLog) {
    $Global:Un1AnalysisLog = [System.Collections.ArrayList]::new()
}

# ==========================================
# FUNÇÃO BASE: Log (Independente)
# ==========================================
function Write-Un1Log {
    param (
        [string]$Category = "INFO",
        [string]$Message, 
        [string]$Color = "Gray"
    )
    
    $timestamp = Get-Date -Format "HH:mm:ss.fff"
    $formattedMessage = "$timestamp [$Category] $Message"

    if ($null -ne $Global:Un1AnalysisLog) {
        [void]$Global:Un1AnalysisLog.Add([PSCustomObject]@{
                Timestamp = $timestamp
                Category  = $Category
                Message   = $Message
                Color     = $Color
                Text      = $formattedMessage
            })
    }
    
    # Se a UI estiver rodando, atualiza o Splash Screen. Se não, ignora silenciosamente.
    if ($null -ne $Global:Un1LogAction) { 
        & $Global:Un1LogAction $Message 
    }
}

# ==========================================
# FUNÇÃO BASE: Inicialização de Evidências (Independente)
# ==========================================
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

# ==========================================
# BLOCO LIMPEZA: Proteção de Diretórios do Sistema (100% Independente)
# ==========================================
function Test-Un1nst4ll3rProtectedCleanupDirectory {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return $true }

    try {
        $resolvedPath = [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
    }
    catch {
        return $true
    }

    $protectedRoots = @(
        [Environment]::GetFolderPath('UserProfile'),
        [Environment]::GetFolderPath('Desktop'),
        [Environment]::GetFolderPath('MyDocuments'),
        [Environment]::GetFolderPath('MyPictures'),
        [Environment]::GetFolderPath('MyMusic'),
        [Environment]::GetFolderPath('MyVideos'),
        [Environment]::GetFolderPath('ApplicationData'),
        [Environment]::GetFolderPath('LocalApplicationData'),
        [Environment]::GetFolderPath('CommonApplicationData'),
        [Environment]::GetFolderPath('Programs'),
        [Environment]::GetFolderPath('Startup'),
        [Environment]::GetFolderPath('CommonPrograms'),
        [Environment]::GetFolderPath('CommonStartup'),
        [Environment]::GetFolderPath('ProgramFiles'),
        [Environment]::GetFolderPath('ProgramFilesX86'),
        $env:PUBLIC,
        (Join-Path $env:USERPROFILE 'Downloads')
    ) | Where-Object { ![string]::IsNullOrWhiteSpace($_) } |
    ForEach-Object {
        try { [System.IO.Path]::GetFullPath($_).TrimEnd('\') } catch { $null }
    } |
    Where-Object { ![string]::IsNullOrWhiteSpace($_) } |
    Sort-Object -Unique

    if ($protectedRoots -contains $resolvedPath) {
        return $true
    }

    if ($resolvedPath -match '^[A-Za-z]:$') {
        return $true
    }

    return $false
}

# ==========================================
# BLOCO LIMPEZA: Exclusão Robusta de Diretório (100% Independente)
# ==========================================
function Remove-Un1nst4ll3rCleanupDirectory {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or !(Test-Path $Path -ErrorAction SilentlyContinue)) {
        return $false
    }

    # Tentativa 1: Modo rápido nativo (como usuário normal)
    try {
        Remove-Item $Path -Recurse -Force -Confirm:$false -ErrorAction Stop
    }
    catch {}

    if (!(Test-Path $Path -ErrorAction SilentlyContinue)) {
        return $true
    }

    # Tentativa 2: Exclusão explícita Bottom-Up (Arquivos primeiro, pastas depois)
    $removedChild = $false
    $accessDenied = $false
    try {
        $files = @(Get-ChildItem -Path $Path -Force -File -Recurse -ErrorAction SilentlyContinue)
        foreach ($file in $files) {
            try {
                Remove-Item $file.FullName -Force -ErrorAction Stop
                if (!(Test-Path $file.FullName -ErrorAction SilentlyContinue)) {
                    $removedChild = $true
                }
            }
            catch {
                # Se der acesso negado, marca a flag
                if ($_.Exception.Message -match 'Acesso negado|Access is denied|requer elevação') {
                    $accessDenied = $true
                }
                Write-Un1Log -Category "CLEANUP" -Message "Failed to delete file: $($file.FullName) | Reason: $($_.Exception.Message)" -Color DarkYellow
            }
        }
        
        $dirs = @(Get-ChildItem -Path $Path -Force -Directory -Recurse -ErrorAction SilentlyContinue | Sort-Object { $_.FullName.Length } -Descending)
        foreach ($dir in $dirs) {
            try {
                Remove-Item $dir.FullName -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue
                if (!(Test-Path $dir.FullName -ErrorAction SilentlyContinue)) {
                    $removedChild = $true
                }
            }
            catch {
                Write-Un1Log -Category "CLEANUP" -Message "Failed to delete dir: $($dir.FullName) | Reason: $($_.Exception.Message)" -Color DarkYellow
            }
        }
    }
    catch {}

    # Tentativa 3: Deleta a pasta raiz
    try {
        Remove-Item $Path -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue
    }
    catch {}

    if (!(Test-Path $Path -ErrorAction SilentlyContinue)) {
        return $true
    }

    # ==========================================
    # TENTATIVA 4: ELEVAÇÃO DIRECIONADA (A MÁGICA)
    # ==========================================
    if ($accessDenied) {
        Write-Un1Log -Category "CLEANUP" -Message "Access denied detected. Attempting targeted elevation for: $Path" -Color Magenta
        try {
            Start-Process -FilePath "cmd.exe" -ArgumentList "/c rmdir /s /q `"$Path`"" -Verb RunAs -Wait -WindowStyle Hidden -ErrorAction Stop
            Start-Sleep -Milliseconds 500

            if (!(Test-Path $Path -ErrorAction SilentlyContinue)) {
                Write-Un1Log -Category "CLEANUP" -Message "Successfully removed via elevated process: $Path" -Color Green
                return $true
            }
        }
        catch {
            Write-Un1Log -Category "CLEANUP" -Message "Targeted elevation failed or was cancelled by user: $Path" -Color Red
        }
    }

    # Relatório final de falha
    $leftovers = @()
    try {
        $leftovers = @(Get-ChildItem -Path $Path -Force -Recurse -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
    }
    catch {}

    $leftoverText = if ($leftovers.Count -gt 0) { $leftovers -join '; ' } else { 'Unknown residual content' }
    Write-Un1Log -Category "CLEANUP" -Message "Directory cleanup incomplete: $Path | Remaining=$leftoverText" -Color DarkYellow
    return $removedChild
}


# ==========================================
# FUNÇÃO AUXILIAR: Heurística de EXE Principal (Trazida do Motor de Busca)
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
    $searchPath = Join-Path $Path "*"

    # 1. Procura na Raiz
    $rootExes = Get-ChildItem -Path $searchPath -Filter "*.exe" -File -ErrorAction SilentlyContinue
    if ($rootExes.Count -gt 0) {
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
            if ($mainExe) { return $mainExe.FullName }
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
                if ($mainExe) { return $mainExe.FullName }
            }
        }
    }
    return ""
}

# ==========================================
# BLOCO 5: Motor de Desinstalação
# ==========================================
function Test-Un1nst4ll3rUninstallCompleted {
    param (
        [PSCustomObject]$App,
        [switch]$Quiet
    )

    Initialize-Un1nst4ll3rEvidenceRecord -App $App
    if (-not $Quiet) { Write-Un1Log -Category "VERIFY" -Message "Verifying uninstall completion for: $($App.Nome)" -Color Yellow }

    if ($App.Tipo -eq "AppX") {
        $appxMatch = Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object {
            (![string]::IsNullOrWhiteSpace($App.Chave) -and $_.PackageFullName -eq $App.Chave) -or
            (![string]::IsNullOrWhiteSpace($App.AppxPackageFamilyName) -and $_.PackageFamilyName -eq $App.AppxPackageFamilyName) -or
            (![string]::IsNullOrWhiteSpace($App.Nome) -and $_.Name -eq $App.Nome)
        } | Select-Object -First 1

        if ($appxMatch) {
            if (-not $Quiet) { Write-Un1Log -Category "VERIFY" -Message "AppX package is still present: $($appxMatch.PackageFullName)" -Color Red }
            return $false
        }

        if (-not $Quiet) { Write-Un1Log -Category "VERIFY" -Message "AppX package is no longer present." -Color Green }
        return $true
    }

    $registryTargets = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$($App.Chave)",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\$($App.Chave)",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$($App.Chave)"
    ) | Where-Object { ![string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique

    foreach ($regPath in $registryTargets) {
        # Ignora a chave sintética de órfãos
        if ($regPath -like "*\Un1nst4ll3r_Orphan_*") { continue }

        if (Test-Path $regPath -ErrorAction SilentlyContinue) {
            
            # VERIFICA SE A CHAVE ESTÁ VAZIA (VESTÍGIO FANTASMA)
            $regKey = Get-Item -Path $regPath -ErrorAction SilentlyContinue
            $hasValidData = $false
            
            if ($null -ne $regKey) {
                # Conta quantas propriedades reais existem na chave
                $properties = $regKey.Property | Where-Object { $_ -notmatch '^PS' }
                
                if ($properties.Count -gt 0) {
                    # Se tem propriedades, verifica se pelo menos uma tem valor
                    foreach ($prop in $properties) {
                        $val = (Get-ItemProperty -Path $regPath -Name $prop -ErrorAction SilentlyContinue).$prop
                        if (-not [string]::IsNullOrWhiteSpace($val)) {
                            $hasValidData = $true
                            break
                        }
                    }
                }
            }

            # Se a chave tem dados reais, o app realmente ainda está instalado. Aborta!
            if ($hasValidData) {
                if (-not $Quiet) { Write-Un1Log -Category "VERIFY" -Message "Registry evidence still present: $regPath" -Color Red }
                return $false
            }
            else {
                # Se a chave está VAZIA, é um fantasma! Não aborta, deixa a limpeza tratar.
                if (-not $Quiet) { Write-Un1Log -Category "VERIFY" -Message "Empty registry ghost key found: $regPath. Ignoring for verification." -Color DarkYellow }
            }
        }
    }

    # Supondo que você tenha a lista completa dos apps escaneados disponível.
    # Se não tiver, precisará passá-la como parâmetro para a função de verificação.
    # Ex: $Global:InstalledPrograms

    # 1. Constrói uma lista de Exes "Protegidos" (pertencem a OUTROS apps instalados)
    $sharedExes = @()
    foreach ($otherApp in $Global:InstalledPrograms) {
        # Ignora o próprio app que estamos verificando (usa Chave ou Nome para comparar)
        if ($otherApp.Chave -ne $App.Chave -and $otherApp.Nome -ne $App.Nome) {
            $sharedExes += @($otherApp.ExePath) +
                        @($otherApp.ExeCandidates) +
                        @($otherApp.ShortcutTargets)
        }
    }
    # NORMALIZAÇÃO CRÍTICA: Converte tudo para Minúsculas e troca '/' por '\' para a comparação funcionar
    $sharedExes = $sharedExes | Where-Object { ![string]::IsNullOrWhiteSpace($_) } | 
                  ForEach-Object { $_.Trim().Replace('/', '\').ToLower() } | 
                  Sort-Object -Unique

    # 2. Sua lógica original de coleta de candidatos
    $exeCandidates = @(
        @($App.ExeCandidates) +
        @($App.ExePath) +
        @($App.ShortcutTargets)
    ) | Where-Object { ![string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique

    # 3. Verificação com a nova regra de compartilhamento
    foreach ($exePath in $exeCandidates) {
        
        # NORMALIZAÇÃO CRÍTICA: Aplica a mesma regra no caminho que estamos testando
        $normalizedExePath = $exePath.Trim().Replace('/', '\').ToLower()

        # NOVA REGRA: Se o EXE é usado por outro app instalado, não consideramos como "evidência de falha"
        if ($sharedExes -contains $normalizedExePath) {
            if (-not $Quiet) { Write-Un1Log -Category "VERIFY" -Message "Shared executable ignored (belongs to another installed app): $exePath" -Color Yellow }
            continue # Pula para o próximo executável
        }

        # Regra normal: Se não é compartilhado e ainda existe, aí sim a desinstalação falhou
        if ((Test-Path $exePath -ErrorAction SilentlyContinue) -and $exePath -notmatch 'uninstall|unins\d+|setup') {
            if (-not $Quiet) { Write-Un1Log -Category "VERIFY" -Message "Executable evidence still present: $exePath" -Color Red }
            return $false
        }
    }

    if ($exeCandidates.Count -eq 0 -and ![string]::IsNullOrWhiteSpace($App.Local) -and (Test-Path $App.Local -ErrorAction SilentlyContinue)) {
        $remainingExe = Find-Un1nst4ll3rMainExe -Path $App.Local -AppName $App.Nome
        if (![string]::IsNullOrWhiteSpace($remainingExe) -and (Test-Path $remainingExe -ErrorAction SilentlyContinue)) {
            if (-not $Quiet) { Write-Un1Log -Category "VERIFY" -Message "Main executable heuristic still found: $remainingExe" -Color Red }
            return $false
        }
    }

    if (-not $Quiet) { Write-Un1Log -Category "VERIFY" -Message "No installation evidence remains for $($App.Nome)." -Color Green }
    return $true
}

# ======================================================================
# BLOCO 5.5: Verificadores Específicos para Plataformas de Jogos (Steam, Epic, EA, GOG)
# ======================================================================
function Get-Un1nst4ll3rSteamAcfPath {
    param ([PSCustomObject]$App)
    
    # 1. Tenta extrair o AppID do jogo
    $appId = $null
    if ($App.UninstallString -match 'steam://uninstall/(?<id>\d+)') {
        $appId = $Matches['id']
    }
    elseif ($App.Chave -match '^Steam App (?<id>\d+)$') {
        $appId = $Matches['id']
    }
    
    if ([string]::IsNullOrWhiteSpace($appId)) { return $null }
    
    # 2. Tenta derivar do InstallLocation (Pasta de instalação do jogo)
    if (![string]::IsNullOrWhiteSpace($App.Local) -and (Test-Path $App.Local -ErrorAction SilentlyContinue)) {
        $parent = Split-Path $App.Local -Parent
        if (![string]::IsNullOrWhiteSpace($parent)) {
            $grandParent = Split-Path $parent -Parent
            if (![string]::IsNullOrWhiteSpace($grandParent) -and (Split-Path $parent -Leaf) -eq "common") {
                $acfPath = Join-Path $grandParent "appmanifest_$appId.acf"
                if (Test-Path $acfPath -ErrorAction SilentlyContinue) { return $acfPath }
            }
            $acfPath = Join-Path $parent "appmanifest_$appId.acf"
            if (Test-Path $acfPath -ErrorAction SilentlyContinue) { return $acfPath }
        }
    }
    
    # 3. Tenta o caminho padrão da Steam no Windows e bibliotecas extras (libraryfolders.vdf)
    $steamPath = $null
    $steamReg = Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam" -ErrorAction SilentlyContinue
    if ($null -ne $steamReg -and $steamReg.InstallPath) {
        $steamPath = $steamReg.InstallPath
    }
    else {
        $steamRegCU = Get-ItemProperty "HKCU:\SOFTWARE\Valve\Steam" -ErrorAction SilentlyContinue
        if ($null -ne $steamRegCU -and $steamRegCU.SteamPath) {
            $steamPath = $steamRegCU.SteamPath -replace '/', '\'
        }
    }
    
    if (![string]::IsNullOrWhiteSpace($steamPath)) {
        $defaultSteamApps = Join-Path $steamPath "steamapps"
        
        # Verifica na pasta padrão
        $acfPath = Join-Path $defaultSteamApps "appmanifest_$appId.acf"
        if (Test-Path $acfPath -ErrorAction SilentlyContinue) { return $acfPath }
        
        # Procura em outras bibliotecas (Ex: D:\SteamLibrary)
        $vdfPath = Join-Path $defaultSteamApps "libraryfolders.vdf"
        if (Test-Path $vdfPath) {
            $vdfContent = Get-Content $vdfPath -Raw -ErrorAction SilentlyContinue
            $libraryPaths = [regex]::Matches($vdfContent, '"path"\s+"([^"]+)"')
            foreach ($match in $libraryPaths) {
                $libPath = $match.Groups[1].Value -replace '\\\\', '\'
                $libSteamApps = Join-Path $libPath "steamapps"
                if (Test-Path $libSteamApps) {
                    $acfPath = Join-Path $libSteamApps "appmanifest_$appId.acf"
                    if (Test-Path $acfPath -ErrorAction SilentlyContinue) { return $acfPath }
                }
            }
        }
    }
    
    return $null
}

function Wait-Un1nst4ll3rUninstallCompleted {
    param (
        [PSCustomObject]$App,
        [int]$TimeoutSeconds = 60
    )

    Initialize-Un1nst4ll3rEvidenceRecord -App $App
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
    
    $isSteam = $false
    $isEpic = $false
    $isEa = $false
    $isGog = $false
    
    # 1. IDENTIFICAÇÃO DA PLATAFORMA E EXTRAÇÃO DE IDs
    if ($App.UninstallString -match 'steam://uninstall/(?<id>\d+)' -or $App.Chave -match '^Steam App (?<id>\d+)$') {
        $isSteam = $true
    }
    elseif ($App.UninstallString -match 'com\.epicgames\.launcher://' -or $App.UninstallString -match 'EpicGamesLauncher') {
        $isEpic = $true
    }
    elseif ($App.UninstallString -match 'origin://' -or $App.UninstallString -match 'eadesktop://' -or $App.UninstallString -match 'EA Desktop') {
        $isEa = $true
    }
    elseif ($App.UninstallString -match 'goggalaxy://' -or $App.UninstallString -match 'GalaxyClient') {
        $isGog = $true
        # GOG usa o ID na URL de desinstalação: /gameId=1234567890
        if ($App.UninstallString -match '/gameId=(?<id>\d+)') {
            $gogId = $Matches['id']
        }
        elseif ($App.Chave -match '^GOG(?<id>\d+)$') {
            $gogId = $Matches['id']
        }
    }
    
    $isGamePlatform = ($isSteam -or $isEpic -or $isEa -or $isGog)
    
    if (-not $isGamePlatform) {
        return (Test-Un1nst4ll3rUninstallCompleted -App $App)
    }
    
    $platformName = if ($isSteam) { "Steam" } elseif ($isEpic) { "Epic Games" } elseif ($isEa) { "EA App" } else { "GOG Galaxy" }
    Write-Un1Log -Category "VERIFY" -Message "Plataforma de jogo detectada: $platformName. Mapeando manifesto de instalação..." -Color Yellow
    
    # 2. MAPEAMENTO DO MANIFESTO (Source of Truth)
    $manifestPath = $null
    $registryManifestPath = $null
    $gameFolder = $App.Local
    
    if ($isSteam) {
        $manifestPath = Get-Un1nst4ll3rSteamAcfPath -App $App
    }
    elseif ($isEpic) {
        # Epic guarda os manifestos em %ProgramData%\Epic\EpicGamesLauncher\Data\Manifests\*.item
        $epicManifestsDir = Join-Path $env:ProgramData "Epic\EpicGamesLauncher\Data\Manifests"
        if (Test-Path $epicManifestsDir) {
            $manifests = Get-ChildItem -Path $epicManifestsDir -Filter "*.item" -ErrorAction SilentlyContinue
            foreach ($manifest in $manifests) {
                try {
                    $json = Get-Content $manifest.FullName -Raw | ConvertFrom-Json
                    # Compara o local de instalação do manifesto com o local do registro do Windows
                    if (![string]::IsNullOrWhiteSpace($json.InstallLocation) -and $json.InstallLocation.TrimEnd('\') -ieq $gameFolder.TrimEnd('\')) {
                        $manifestPath = $manifest.FullName
                        break
                    }
                }
                catch {}
            }
        }
    }
    elseif ($isGog) {
        # GOG usa o Registro do Windows
        if (![string]::IsNullOrWhiteSpace($gogId)) {
            $reg1 = "HKLM:\SOFTWARE\WOW6432Node\GOG.com\Games\$gogId"
            $reg2 = "HKLM:\SOFTWARE\GOG.com\Games\$gogId"
            if (Test-Path $reg1) { $registryManifestPath = $reg1 }
            elseif (Test-Path $reg2) { $registryManifestPath = $reg2 }
        }
    }
    elseif ($isEa) {
        # EA App usa o Registro do Windows com o Nome do Jogo
        $reg1 = "HKLM:\SOFTWARE\WOW6432Node\EA Games\$($App.Nome)"
        $reg2 = "HKLM:\SOFTWARE\EA Games\$($App.Nome)"
        if (Test-Path $reg1) { $registryManifestPath = $reg1 }
        elseif (Test-Path $reg2) { $registryManifestPath = $reg2 }
    }
    
    # 3. ESTADO INICIAL
    $initialManifestExists = if ($manifestPath) { Test-Path $manifestPath } else { $false }
    $initialRegManifestExists = if ($registryManifestPath) { Test-Path $registryManifestPath } else { $false }
    
    $initialFolderHasData = $false
    if (![string]::IsNullOrWhiteSpace($gameFolder) -and (Test-Path $gameFolder -ErrorAction SilentlyContinue)) {
        $filesInFolder = @(Get-ChildItem -Path $gameFolder -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1)
        if ($filesInFolder.Count -gt 0) { $initialFolderHasData = $true }
    }
    
    $canAutoConfirm = ($initialManifestExists -or $initialRegManifestExists -or $initialFolderHasData)

    # Segurança: Se não temos NADA para monitorar
    if (-not $canAutoConfirm) {
        Stop-Un1nst4ll3rSpinner
        [void][System.Windows.Forms.MessageBox]::Show("O Un1nst4ll3r não conseguiu mapear os arquivos deste jogo na $platformName para verificar a desinstalação.`n`nPor segurança, a verificação automática foi abortada. Tente usar o botão FORCE UNINSTALL.", "Aviso de Monitoramento", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        return $false
    }

    $elapsed = 0
    $interval = 2
    $uninstalled = $false

    # Helper para verificar pasta (fallback)
    $checkFolderHasData = {
        if ([string]::IsNullOrWhiteSpace($gameFolder) -or !(Test-Path $gameFolder -ErrorAction SilentlyContinue)) { return $false }
        $files = @(Get-ChildItem -Path $gameFolder -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1)
        return ($files.Count -gt 0)
    }

    # 4. LOOP DE MONITORAMENTO
    while ($elapsed -lt $TimeoutSeconds) {
        $remainingTime = $TimeoutSeconds - $elapsed
        Update-Un1nst4ll3rSpinner -Message "Aguardando desinstalação na $platformName ($($remainingTime)s)..."
        
        if (("System.Windows.Forms.Application" -as [type]) -and [System.Threading.Thread]::CurrentThread.GetApartmentState() -eq [System.Threading.ApartmentState]::STA) {
            [System.Windows.Forms.Application]::DoEvents()
        }
        
        $manifestGone = $true
        if ($initialManifestExists) { $manifestGone = -not (Test-Path $manifestPath -ErrorAction SilentlyContinue) }
        
        $regManifestGone = $true
        if ($initialRegManifestExists) { $regManifestGone = -not (Test-Path $registryManifestPath -ErrorAction SilentlyContinue) }
        
        $currentFolderHasData = & $checkFolderHasData
        $folderGone = if ($initialFolderHasData) { -not $currentFolderHasData } else { $true }

        # REGRA DE SUCESSO: O manifesto sumiu? E a pasta está vazia?
        # Se a pasta não estiver vazia, mas o manifesto sumiu, consideramos desinstalado (saves deixados para trás)
        if (($manifestGone -and $regManifestGone) -and ($folderGone -or $manifestGone -or $regManifestGone)) {
            $uninstalled = $true
        }
        
        if ($uninstalled) {
            Write-Un1Log -Category "VERIFY" -Message "Desinstalação confirmada após $elapsed segundos. (Manifesto/Registro removido)." -Color Green
            return $true
        }
        
        Start-Sleep -Seconds $interval
        $elapsed += $interval
    }
    
    # 5. TEMPO ESTOUROU (DOUBLE-CHECK DO USUÁRIO)
    Write-Un1Log -Category "VERIFY" -Message "Tempo limite atingido ($TimeoutSeconds s). Verificando ação do usuário..." -Color DarkYellow
    Stop-Un1nst4ll3rSpinner

    $promptMsg = "O tempo limite atingiu 60 segundos.`n`nVocê confirmou e executou o desinstalador dentro do cliente da $platformName?"
    $promptResult = [System.Windows.Forms.MessageBox]::Show($promptMsg, "Verificação Necessária - $platformName", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
    
    if ($promptResult -eq [System.Windows.Forms.DialogResult]::Yes) {
        Start-Sleep -Seconds 2 
        
        $manifestGone = $true
        if ($initialManifestExists) { $manifestGone = -not (Test-Path $manifestPath -ErrorAction SilentlyContinue) }
        
        $regManifestGone = $true
        if ($initialRegManifestExists) { $regManifestGone = -not (Test-Path $registryManifestPath -ErrorAction SilentlyContinue) }
        
        $currentFolderHasData = & $checkFolderHasData
        $folderGone = if ($initialFolderHasData) { -not $currentFolderHasData } else { $true }

        # Double-check: Se o usuário disse que desinstalou, o manifesto TEM que ter sumido.
        if (($manifestGone -and $regManifestGone) -and ($folderGone -or $manifestGone -or $regManifestGone)) {
            Write-Un1Log -Category "VERIFY" -Message "Double-check confirmado. Manifesto/Registro removido. Seguindo para rastros." -Color Green
            return $true
        }
        else {
            [void][System.Windows.Forms.MessageBox]::Show("Houve um problema na desinstalação. O manifesto do jogo ainda existe no sistema, o desinstalador pode ter sido cancelado.", "Erro de Desinstalação", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            Write-Un1Log -Category "VERIFY" -Message "Double-check falhou. Manifesto/Registro ainda existem. Vestígios bloqueados." -Color Red
            return $false
        }
    }
    else {
        [void][System.Windows.Forms.MessageBox]::Show("Desinstalação cancelada pelo usuário.", "Cancelado", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        Write-Un1Log -Category "VERIFY" -Message "Usuário informou que o desinstalador não foi executado. Operação cancelada. Vestígios bloqueados." -Color Yellow
        return $false
    }
}

function Start-Un1nst4ll3rApp {
    param (
        [string]$AppName,
        [string]$UninstallStringValue,
        [string]$QuietUninstallStringValue,
        [string]$ProgramType,
        [string]$AppIdentifier = "" 
    )

    # Fallback de Idioma
    $confirmMsg = if ($null -ne $script:LangData -and $script:LangData.ConfirmUninstallMessage) {
        $script:LangData.ConfirmUninstallMessage -f $AppName
    }
    else {
        "Deseja desinstalar '$AppName'?"
    }
    $titleStr = if ($null -ne $script:LangData -and $script:LangData.Title) { $script:LangData.Title } else { "Un1nst4ll3r" }

    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue

    $resultFromUser = [System.Windows.Forms.MessageBox]::Show(
        $confirmMsg, $titleStr, [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question
    )
    if ($resultFromUser -ne [System.Windows.Forms.DialogResult]::Yes) {
        Write-Un1Log -Category "UNINSTALL" -Message "User cancelled uninstall for '$AppName'." -Color Yellow
        return $false
    }    

    Write-Un1Log -Category "UNINSTALL" -Message "Attempting to uninstall: $($AppName)" -Color Yellow
    Update-Un1nst4ll3rSpinner -Message "Executando desinstalador de $($AppName)..."

    $uninstallCmd = $UninstallStringValue
    $Silent = $false

    if ($QuietUninstallStringValue -ne "") {
        $uninstallCmd = $QuietUninstallStringValue
        $Silent = $true
        Write-Un1Log -Category "UNINSTALL" -Message "Quiet mode detected. Running silently." -Color Magenta        
    }

    try {
        if ($ProgramType -eq "AppX") {
            Write-Un1Log -Category "UNINSTALL" -Message "Removing AppX package..." -Color Cyan
            $appxPackage = Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object {
                (![string]::IsNullOrWhiteSpace($AppIdentifier) -and ($_.PackageFullName -eq $AppIdentifier -or $_.PackageFamilyName -eq $AppIdentifier -or $_.Name -eq $AppIdentifier)) -or
                (![string]::IsNullOrWhiteSpace($AppName) -and $_.Name -eq $AppName)
            } | Select-Object -First 1

            if ($null -eq $appxPackage) { throw "AppX package not found for uninstall." }

            Update-Un1nst4ll3rSpinner -Message "Removendo pacote AppX..."
            Remove-AppxPackage -Package $appxPackage.PackageFullName -ErrorAction Stop
            Write-Un1Log -Category "UNINSTALL" -Message "AppX removal successful." -Color Green
            return $true
        }
        elseif ($uninstallCmd -match 'msiexec' -and $uninstallCmd -match '\{([A-Fa-f0-9\-]+)\}') {
            Write-Un1Log -Category "UNINSTALL" -Message "Removing via MSI Exec..." -Color Cyan
            $msiGuid = $Matches[0]
            $msiArgs = if ($Silent) { "/x $msiGuid /qn /norestart" } else { "/x $msiGuid /qb+ /norestart" }
            Update-Un1nst4ll3rSpinner -Message "Removendo via Windows Installer..."
            $msiProc = Start-Process "MsiExec.exe" -ArgumentList $msiArgs -Wait -PassThru -Verb RunAs
            Write-Un1Log -Category "UNINSTALL" -Message "MSI removal command executed." -Color Green
            return $true
        }
        elseif ($uninstallCmd -match 'rundll32\.exe') {
            Write-Un1Log -Category "UNINSTALL" -Message "Removing via Rundll32..." -Color Cyan
            Update-Un1nst4ll3rSpinner -Message "Executando desinstalador via Rundll32..."
            
            $isClickOnce = $uninstallCmd -match 'dfshim\.dll'
            $needsElevation = -not $isClickOnce
            $rundllArgs = $uninstallCmd -replace '^.*?rundll32\.exe\s*', ''
            
            try {
                $spArgs = @{ FilePath = "rundll32.exe"; ArgumentList = $rundllArgs; Wait = $true; PassThru = $true }
                if ($needsElevation) { $spArgs.Verb = "RunAs" }
                $childProc = Start-Process @spArgs -ErrorAction Stop
                Write-Un1Log -Category "UNINSTALL" -Message "Rundll32 removal command executed." -Color Green
                return $true
            }
            catch {
                Write-Un1Log -Category "UNINSTALL" -Message "Rundll32 execution failed: $_" -Color Red
                return $false
            }
        }
        elseif (![string]::IsNullOrWhiteSpace($uninstallCmd)) {
            $logLabel = if ($Silent) { "Silent" } else { "Standard" }
            Write-Un1Log -Category "UNINSTALL" -Message "Removing via $logLabel Uninstall String..." -Color Cyan

            $uninstallCmd = $uninstallCmd -replace '[""]', '"'
            $exe = ""
            $argms = ""

            if ($uninstallCmd.TrimStart().StartsWith('"')) {
                $parts = $uninstallCmd -split '"'
                $exe = $parts[1].Trim()
                $argms = if ($parts.Count -gt 2) { $parts[2].Trim() } else { "" }
            }
            elseif ($uninstallCmd -match '(.*?\.(exe|msi))\s+(.*)') {
                $exe = $Matches[1].Trim()
                $argms = $Matches[3].Trim()
            }
            else {
                $exe = $uninstallCmd.Trim()
                $argms = ""
            }

            try {
                if ([string]::IsNullOrWhiteSpace($exe)) { throw "Failed to parse executable." }
                
                $isProtocol = ($uninstallCmd -match '(steam|com\.epicgames\.launcher|origin|eadesktop|goggalaxy)://')
                
                if ($isProtocol) {
                    # SOLUÇÃO DEFINITIVA PARA PROTOCOLOS: cmd /c start não trava a thread do PowerShell
                    $cmdArgs = '/c start "" "' + $exe + '"'
                    if (![string]::IsNullOrWhiteSpace($argms)) { $cmdArgs = '/c start "" "' + $exe + '" "' + $argms + '"' }
                    
                    Start-Process -FilePath "cmd.exe" -ArgumentList $cmdArgs -WindowStyle Hidden -ErrorAction Stop | Out-Null
                    
                    Write-Un1Log -Category "UNINSTALL" -Message "Protocolo URI lançado com sucesso (Assíncrono via cmd)." -Color Green
                    return $true
                }
                else {
                    # Apps normais continuam usando Start-Process com Wait
                    $spArgs = @{ FilePath = $exe; Wait = $true; PassThru = $true; Verb = "RunAs" }
                    if (![string]::IsNullOrWhiteSpace($argms)) { $spArgs.ArgumentList = $argms }
                    $childProc = Start-Process @spArgs -ErrorAction Stop
                    Start-Sleep -Milliseconds 500 
                    Write-Un1Log -Category "UNINSTALL" -Message "$logLabel removal command executed." -Color Green
                    return $true
                }
            }
            catch {
                Write-Un1Log -Category "UNINSTALL" -Message "Start-Process failed [$_], falling back to cmd..." -Color Yellow
                try {
                    $isProtocol = ($uninstallCmd -match '(steam|com\.epicgames\.launcher|origin|eadesktop|goggalaxy)://')
                    if ($isProtocol) {
                        $cmdArgs = @{ FilePath = "cmd"; ArgumentList = "/c start `"`" `"$uninstallCmd`""; PassThru = $true; ErrorAction = "Stop" }
                        $fallbackProc = Start-Process @cmdArgs
                    }
                    else {
                        $cmdArgs = @{ FilePath = "cmd"; ArgumentList = "/c `"$uninstallCmd`""; Wait = $true; Verb = "RunAs"; PassThru = $true; ErrorAction = "Stop" }
                        $fallbackProc = Start-Process @cmdArgs
                    }
                    Start-Sleep -Milliseconds 500 
                    Write-Un1Log -Category "UNINSTALL" -Message "cmd fallback executed successfully." -Color Green
                    return $true
                }
                catch {
                    Write-Un1Log -Category "UNINSTALL" -Message "cmd fallback also failed: $_" -Color Red
                }
            }
        }
    }
    catch {
        Write-Un1Log -Category "UNINSTALL" -Message "ERROR uninstalling $($AppName): $($_.Exception.Message)" -Color Red
        return $false
    }
    return $false
}

# ==========================================
# BLOCO 6.A: Motor de Descoberta de Vestígios (Apenas lista, não apaga)
# ==========================================
function Get-Un1nst4ll3rTraceTargets {
    param (
        [PSCustomObject]$App,
        [Array]$InstalledApps = @(),
        [string]$AppRoot # NOVO PARÂMETRO
    )

    Initialize-Un1nst4ll3rEvidenceRecord -App $App
    Write-Un1Log -Category "TRACE-FIND" -Message "Scanning for residual traces: $($App.Nome)" -Color Yellow
    
    $targets = [System.Collections.ArrayList]::new()

    # Helper para adicionar alvos
    $addTarget = {
        param([string]$Type, [string]$Path, [bool]$Protected, [string]$Reason)
        [void]$targets.Add([PSCustomObject]@{
                Type      = $Type
                Path      = $Path
                Protected = $Protected
                Reason    = $Reason
                Selected  = -not $Protected # Marcado por padrão se não for protegido
            })
    }

    # 1. Registro Padrão (Chave de desinstalação)
    $regPaths = @(
        @($App.CleanupRegistryTargets) +
        @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$($App.Chave)",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\$($App.Chave)",
            "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$($App.Chave)"
        )
    ) | Where-Object { ![string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique

    foreach ($reg in $regPaths) {
        if (Test-Path $reg) {
            & $addTarget "Registro" $reg $false "OK"
        }
    }

    # 2. Atalhos
    $shortcutPaths = @($App.ShortcutPaths) | Where-Object { ![string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique
    foreach ($shortcutPath in $shortcutPaths) {
        if ($shortcutPath -match '\.lnk$' -and (Test-Path $shortcutPath -ErrorAction SilentlyContinue)) {
            & $addTarget "Atalho" $shortcutPath $false "OK"
        }
    }

    # ======================================================================
    # 2.5 Busca Profunda no Registro (Sanitizando o Nome E Protegendo Outros Apps)
    # ======================================================================
    $sanitizedApp = Get-Un1nst4ll3rSanitizedName -RawName $App.Nome
    Write-Un1Log -Category "TRACE-FIND" -Message "Sanitized app name for deep search: '$sanitizedApp' (Original: '$($App.Nome)')" -Color Blue
    
    if (![string]::IsNullOrWhiteSpace($sanitizedApp) -and $sanitizedApp.Length -ge 3) {
        # Busca nas hives principais de software
        $deepRegTraces = Find-Un1nst4ll3rDeepRegistryTraces -SearchTerm $sanitizedApp -AppRoot $AppRoot

        # Filtra para não duplicar chaves que já foram mapeadas pelo registro de desinstalação padrão
        $existingRegs = $regPaths | ForEach-Object { 
            $p = $_ -replace '^Microsoft\.PowerShell\.Core\\Registry::HKEY_LOCAL_MACHINE', 'HKLM:' `
                -replace '^Microsoft\.PowerShell\.Core\\Registry::HKEY_CURRENT_USER', 'HKCU:'
            $p.TrimEnd('\').ToLower() 
        }
        
        foreach ($trace in $deepRegTraces) {
            # Normaliza o caminho do Deep Search para o padrão do PowerShell (HKLM:\)
            $normPath = $trace.Caminho -replace 'Microsoft\.PowerShell\.Core\\Registry::HKEY_LOCAL_MACHINE', 'HKLM:' `
                -replace 'Microsoft\.PowerShell\.Core\\Registry::HKEY_CURRENT_USER', 'HKCU:'
            
            $cleanNormPath = $normPath.TrimEnd('\').ToLower()
            
            # Se a chave não estiver já na lista, avalia se é compartilhada
            if ($existingRegs -notcontains $cleanNormPath) {
                if ($normPath -ne "HKLM:\SOFTWARE" -and $normPath -ne "HKCU:\SOFTWARE") {
                    
                    $isSharedReg = $false
                    
                    # NOVA PROTEÇÃO: Verifica se o vestígio pertence a OUTRO app instalado
                    foreach ($other in $InstalledApps) {
                        if ($other.Nome -eq $App.Nome -and $other.Chave -eq $App.Chave) { continue }
                        
                        # Sanitiza o nome do outro app
                        $otherSanitized = Get-Un1nst4ll3rSanitizedName -RawName $other.Nome
                        if (![string]::IsNullOrWhiteSpace($otherSanitized) -and $otherSanitized.Length -ge 3) {
                            # Se o caminho do registro conter o nome do outro app (ex: "Antigravity IDE"), protege!
                            if ($normPath -match [regex]::Escape($otherSanitized)) {
                                $isSharedReg = $true
                                break
                            }
                        }
                        
                        # Protege também a chave de desinstalação do outro app
                        if (![string]::IsNullOrWhiteSpace($other.Chave) -and $normPath -match [regex]::Escape($other.Chave)) {
                            $isSharedReg = $true
                            break
                        }
                    }

                    if ($isSharedReg) {
                        Write-Un1Log -Category "TRACE-FIND" -Message "Registro compartilhado detectado (Deep Search): $normPath" -Color Yellow
                        & $addTarget "Registro" $normPath $true "Compartilhado (Outro App)"
                    } else {
                        & $addTarget "Registro" $normPath $false "Deep Match ($($trace.Nome))"
                    }
                }
            }
        }
    }
    
    # 3. Diretórios (com AppData Guessing e proteção de compartilhados)
    $safeAppName = $App.Nome -replace '\(.*\)', '' -replace '\s+\d+.*', '' -replace '[^\w\s\-+]', ''
    $appWords = @($safeAppName -split '\s+' | Where-Object { $_.Length -gt 2 })
    $firstKeyword = if ($appWords.Count -gt 0) { $appWords[0] } else { $safeAppName }
    $genericPublishers = @("microsoft", "windows", "adobe", "oracle", "google", "mozilla", "apple", "intel", "nvidia", "amd", "realtek", "dell", "hp", "lenovo", "framework", "runtime", "visual", "c++", "redistributable")
    
    $residualPaths = @()
    if (![string]::IsNullOrWhiteSpace($firstKeyword) -and $genericPublishers -notcontains $firstKeyword.ToLower()) {
        $residualPaths = @(
            "$env:APPDATA\$firstKeyword",
            "$env:LOCALAPPDATA\$firstKeyword",
            "$env:PROGRAMDATA\$firstKeyword",
            "$env:LOCALAPPDATA\Programs\$firstKeyword"
        )
    }

    $directoryTargets = @(
        @($App.CleanupDirectoryTargets) +
        @($App.Local) +
        $residualPaths
    ) | Where-Object { ![string]::IsNullOrWhiteSpace($_) } | Sort-Object { $_.Length } -Descending | Select-Object -Unique
    
    foreach ($path in $directoryTargets) {
        if (Test-Un1nst4ll3rProtectedCleanupDirectory -Path $path) {
            & $addTarget "Pasta" $path $true "Protegido (Sistema)"
            continue
        }

        if (Test-Path $path) {
            $isShared = $false
            $normalizedPath = $path.TrimEnd('\/').Replace('/', '\').ToLower()

            foreach ($other in $InstalledApps) {
                if ($other.Nome -eq $App.Nome -and $other.Chave -eq $App.Chave) { continue }
                $otherLocal = $other.Local
                if ([string]::IsNullOrWhiteSpace($otherLocal)) { continue }
                
                $normalizedOther = $otherLocal.TrimEnd('\/').Replace('/', '\').ToLower()

                # VERIFICAÇÃO DE SOBREPOSIÇÃO BIDIRECIONAL
                if ($normalizedOther.StartsWith("$normalizedPath\") -or $normalizedPath.StartsWith("$normalizedOther\") -or $normalizedOther -eq $normalizedPath) {
                    $isShared = $true
                    Write-Un1Log -Category "TRACE-FIND" -Message "Diretório compartilhado detectado: $path (Conflita com: $($other.Nome))" -Color Yellow
                    break
                }
            }

            if ($isShared) {
                & $addTarget "Pasta" $path $true "Compartilhado (Outro App)"
            }
            else {
                & $addTarget "Pasta" $path $false "OK"
            }
        }
    }

    Write-Un1Log -Category "TRACE-FIND" -Message "Found $($targets.Count) residual traces." -Color Green
    return $targets
}

# ==========================================
# BLOCO 6.B: Motor de Exclusão de Vestígios (Apaga a lista passada)
# ==========================================
function Remove-Un1nst4ll3rTraces {
    param (
        [Array]$Targets
    )

    $cleanedCount = 0
    $failedCount = 0
    Update-Un1nst4ll3rSpinner -Message "Removendo vestígios selecionados..."

    foreach ($target in $Targets) {
        # Segurança extra: nunca apaga protegidos
        if ($target.Protected) { continue }

        Write-Un1Log -Category "CLEANUP" -Message "Removing $($target.Type): $($target.Path)" -Color Cyan
        
        $success = $false

        if ($target.Type -eq "Registro") {
            # Normaliza o caminho para o formato do reg.exe (ex: HKEY_LOCAL_MACHINE\...)
            $regPathNormalized = $target.Path -replace '^Microsoft\.PowerShell\.Core\\Registry::HKEY_LOCAL_MACHINE', 'HKEY_LOCAL_MACHINE' `
                -replace '^Microsoft\.PowerShell\.Core\\Registry::HKEY_CURRENT_USER', 'HKEY_CURRENT_USER' `
                -replace '^Microsoft\.PowerShell\.Core\\Registry::HKEY_CLASSES_ROOT', 'HKEY_CLASSES_ROOT' `
                -replace '^HKLM:', 'HKEY_LOCAL_MACHINE' `
                -replace '^HKCU:', 'HKEY_CURRENT_USER' `
                -replace '^HKCR:', 'HKEY_CLASSES_ROOT'

            # Tentativa 1: Modo nativo PowerShell
            Remove-Item $target.Path -Recurse -Force -ErrorAction SilentlyContinue
            
            # Double-check: A chave realmente sumiu?
            if (!(Test-Path $target.Path -ErrorAction SilentlyContinue)) {
                $success = $true
            }
            else {
                # Tentativa 2: Elevação direcionada com reg.exe (A MÁGICA)
                Write-Un1Log -Category "CLEANUP" -Message "Falha de acesso ao registro. Tentando elevação: $regPathNormalized" -Color Magenta
                try {
                    Start-Process -FilePath "reg.exe" -ArgumentList "delete `"$regPathNormalized`" /f" -Verb RunAs -Wait -WindowStyle Hidden -ErrorAction Stop | Out-Null
                    Start-Sleep -Milliseconds 300
                    
                    # Double-check pós-elevação
                    if (!(Test-Path $target.Path -ErrorAction SilentlyContinue)) {
                        Write-Un1Log -Category "CLEANUP" -Message "Registro removido com sucesso via elevação." -Color Green
                        $success = $true
                    }
                }
                catch {
                    Write-Un1Log -Category "CLEANUP" -Message "Elevação falhou ou foi cancelada para: $regPathNormalized" -Color Red
                }
            }
        }
        elseif ($target.Type -eq "Atalho") {
            Remove-Item $target.Path -Force -ErrorAction SilentlyContinue
            if (!(Test-Path $target.Path -ErrorAction SilentlyContinue)) {
                $success = $true
            }
            else {
                # Atalhos em C:\ProgramData\... exigem admin
                Write-Un1Log -Category "CLEANUP" -Message "Falha ao apagar atalho. Tentando elevação: $($target.Path)" -Color Magenta
                try {
                    Start-Process -FilePath "cmd.exe" -ArgumentList "/c del /f /q `"$($target.Path)`"" -Verb RunAs -Wait -WindowStyle Hidden -ErrorAction Stop | Out-Null
                    Start-Sleep -Milliseconds 300
                    if (!(Test-Path $target.Path -ErrorAction SilentlyContinue)) {
                        $success = $true
                    }
                }
                catch {
                    Write-Un1Log -Category "CLEANUP" -Message "Elevação falhou para atalho: $($target.Path)" -Color Red
                }
            }
        }
        elseif ($target.Type -eq "Pasta") {
            # A função de pasta já tem elevação embutida
            $success = Remove-Un1nst4ll3rCleanupDirectory -Path $target.Path
        }

        if ($success) {
            $cleanedCount++
        }
        else {
            $failedCount++
        }
    }

    $finalColor = if ($failedCount -gt 0) { "Yellow" } else { "Green" }
    Write-Un1Log -Category "CLEANUP" -Message "Cleanup finished. $cleanedCount trace(s) removed. $failedCount failed." -Color $finalColor
    return $cleanedCount
}

# ==========================================
# FUNÇÃO AUXILIAR: Limpar Nome do App (Remover Versão/Edição)
# ==========================================
function Get-Un1nst4ll3rSanitizedName {
    param ([string]$RawName)

    if ([string]::IsNullOrWhiteSpace($RawName)) { return "" }

    # 1. Remove conteúdo entre parênteses (ex: "MyApp (x64)" -> "MyApp")
    # 2. Remove números de versão no final (ex: "MyApp 2.0.1" -> "MyApp")
    # 3. Remove palavras de edição com Regex (Pro, Lite, Free, Version, x86, x64, etc)
    $cleanName = $RawName -replace '\(.*?\)', '' `
        -replace '\s+v?\d+(\.\d+)*.*$', '' `
        -replace '(?i)\b(pro|lite|free|premium|ultimate|professional|enterprise|trial|version|installer|setup|build|x86|x64|32-bit|64-bit)\b', '' `
        -replace '[^\w\s\-+]', '' # Remove caracteres especiais
    
    return $cleanName.Trim()
}

# ==========================================
# FUNÇÃO AUXILIAR: Busca Profunda no Registro (Via Processo Isolado)
# ==========================================
function Find-Un1nst4ll3rDeepRegistryTraces {
    param (
        [Parameter(Mandatory = $true)]
        [string]$SearchTerm,
        [string]$AppRoot # O Core precisa saber onde está a pasta do App
    )

    $regSearchScript = Join-Path $AppRoot "RegSearch.ps1"
    if (!(Test-Path $regSearchScript)) {
        Write-Un1Log -Category "DEEP-REG" -Message "RegSearch.ps1 não encontrado em $AppRoot" -Color Red
        return @()
    }

    Write-Un1Log -Category "DEEP-REG" -Message "Iniciando busca isolada por: '$SearchTerm'" -Color Cyan

    # Configura o processo isolado
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe" # ou "pwsh.exe" se estiver no PS7
    # Sem o parâmetro -Hives, o RegSearch.ps1 usa o padrão (HKLM:\ e HKCU:\) que se mostrou mais rápido
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$regSearchScript`" -s `"$SearchTerm`" -ExportJson"
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi

    # Inicia o processo
    [void]$process.Start()

    # LÊ A SAÍDA (BUFFERIZA): O script fica parado aqui esperando o RegSearch terminar e cuspir o JSON
    $outputJson = $process.StandardOutput.ReadToEnd()
    $process.WaitForExit()

    if ([string]::IsNullOrWhiteSpace($outputJson)) {
        Write-Un1Log -Category "DEEP-REG" -Message "Nenhum vestígio profundo encontrado." -Color Blue
        return @()
    }

    try {
        $traces = ConvertFrom-Json -InputObject $outputJson
        Write-Un1Log -Category "DEEP-REG" -Message "Busca isolada concluída. $($traces.Count) vestígios retornados." -Color Green
        return $traces
    }
    catch {
        Write-Un1Log -Category "DEEP-REG" -Message "Erro ao ler JSON do RegSearch: $($_.Exception.Message)" -Color Red
        return @()
    }
}

# ==========================================
# FIM DO MÓDULO CORE
# ==========================================
Write-Un1Log -Category "INIT" -Message "Un1nst4ll3r-core.ps1 loaded successfully." -Color DarkGray