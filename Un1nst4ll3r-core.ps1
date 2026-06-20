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
        [Parameter(Mandatory=$true)]
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
        } elseif ($App.$property -isnot [System.Collections.ArrayList]) {
            $buffer = [System.Collections.ArrayList]::new()
            foreach ($item in @($App.$property)) {
                if ($null -ne $item) { [void]$buffer.Add($item) }
            }
            $App.$property = $buffer
        }
    }

    $scalarDefaults = @{
        RegistryKey         = ""
        SourceRegistryPath  = ""
        InstallLocationRaw  = ""
        DisplayIconRaw      = ""
        RootPath            = ""
        RootSource          = ""
        AppxPackageFamilyName = ""
        AppxInstallLocation = ""
        ShortcutPath        = ""
        ShortcutScope       = ""
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
    } catch {
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
    } catch {}

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
            } catch {
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
            } catch {
                 Write-Un1Log -Category "CLEANUP" -Message "Failed to delete dir: $($dir.FullName) | Reason: $($_.Exception.Message)" -Color DarkYellow
            }
        }
    } catch {}

    # Tentativa 3: Deleta a pasta raiz
    try {
        Remove-Item $Path -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue
    } catch {}

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
        } catch {
            Write-Un1Log -Category "CLEANUP" -Message "Targeted elevation failed or was cancelled by user: $Path" -Color Red
        }
    }

    # Relatório final de falha
    $leftovers = @()
    try {
        $leftovers = @(Get-ChildItem -Path $Path -Force -Recurse -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
    } catch {}

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
        [PSCustomObject]$App
    )

    Initialize-Un1nst4ll3rEvidenceRecord -App $App
    Write-Un1Log -Category "VERIFY" -Message "Verifying uninstall completion for: $($App.Nome)" -Color Yellow

    if ($App.Tipo -eq "AppX") {
        $appxMatch = Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object {
            (![string]::IsNullOrWhiteSpace($App.Chave) -and $_.PackageFullName -eq $App.Chave) -or
            (![string]::IsNullOrWhiteSpace($App.AppxPackageFamilyName) -and $_.PackageFamilyName -eq $App.AppxPackageFamilyName) -or
            (![string]::IsNullOrWhiteSpace($App.Nome) -and $_.Name -eq $App.Nome)
        } | Select-Object -First 1

        if ($appxMatch) {
            Write-Un1Log -Category "VERIFY" -Message "AppX package is still present: $($appxMatch.PackageFullName)" -Color Red
            return $false
        }

        Write-Un1Log -Category "VERIFY" -Message "AppX package is no longer present." -Color Green
        return $true
    }

    $registryTargets = @(
        @($App.CleanupRegistryTargets) +
        @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$($App.Chave)",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\$($App.Chave)",
            "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$($App.Chave)"
        )
    ) | Where-Object { ![string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique

    foreach ($regPath in $registryTargets) {
        if (Test-Path $regPath -ErrorAction SilentlyContinue) {
            Write-Un1Log -Category "VERIFY" -Message "Registry evidence still present: $regPath" -Color Red
            return $false
        }
    }

    $exeCandidates = @(
        @($App.ExeCandidates) +
        @($App.ExePath) +
        @($App.ShortcutTargets)
    ) | Where-Object { ![string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique

    foreach ($exePath in $exeCandidates) {
        if ((Test-Path $exePath -ErrorAction SilentlyContinue) -and $exePath -notmatch 'uninstall|unins\d+|setup') {
            Write-Un1Log -Category "VERIFY" -Message "Executable evidence still present: $exePath" -Color Red
            return $false
        }
    }

    if ($exeCandidates.Count -eq 0 -and ![string]::IsNullOrWhiteSpace($App.Local) -and (Test-Path $App.Local -ErrorAction SilentlyContinue)) {
        $remainingExe = Find-Un1nst4ll3rMainExe -Path $App.Local -AppName $App.Nome
        if (![string]::IsNullOrWhiteSpace($remainingExe) -and (Test-Path $remainingExe -ErrorAction SilentlyContinue)) {
            Write-Un1Log -Category "VERIFY" -Message "Main executable heuristic still found: $remainingExe" -Color Red
            return $false
        }
    }

    Write-Un1Log -Category "VERIFY" -Message "No installation evidence remains for $($App.Nome)." -Color Green
    return $true
}

function Start-Un1nst4ll3rApp {
    param (
        [string]$AppName,
        [string]$UninstallStringValue,
        [string]$QuietUninstallStringValue,
        [string]$ProgramType,
        [string]$AppIdentifier = "" 
    )

    # Fallback de Idioma (Caso o core.ps1 seja executado sem a UI ter carregado o JSON)
    $confirmMsg = if ($null -ne $script:LangData -and $script:LangData.ConfirmUninstallMessage) {
        $script:LangData.ConfirmUninstallMessage -f $AppName
    } else {
        "Deseja desinstalar '$AppName'?"
    }
    $titleStr = if ($null -ne $script:LangData -and $script:LangData.Title) { $script:LangData.Title } else { "Un1nst4ll3r" }

    # Garante que o Assembly do Windows Forms está carregado para usar o MessageBox
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue

    $resultFromUser = [System.Windows.Forms.MessageBox]::Show(
        $confirmMsg, 
        $titleStr, 
        [System.Windows.Forms.MessageBoxButtons]::YesNo, 
        [System.Windows.Forms.MessageBoxIcon]::Question
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

            if ($null -eq $appxPackage) {
                throw "AppX package not found for uninstall."
            }

            Update-Un1nst4ll3rSpinner -Message "Removendo pacote AppX..."
            Remove-AppxPackage -Package $appxPackage.PackageFullName -ErrorAction Stop
            Write-Un1Log -Category "UNINSTALL" -Message "AppX removal successful." -Color Green
            return $true
        }
        
        elseif ($uninstallCmd -match 'msiexec' -and $uninstallCmd -match '\{([A-Fa-f0-9\-]+)\}') {
            Write-Un1Log -Category "UNINSTALL" -Message "Removing via MSI Exec..." -Color Cyan
            $msiGuid = $Matches[0]
            $msiArgs = if ($Silent) { "/x $msiGuid /qn /norestart" } else { "/x $msiGuid /qb+ /norestart" }
            Write-Un1Log -Category "UNINSTALL-DBG" -Message "MSI launch prepared. FilePath=msiexec.exe | Args=$msiArgs | Silent=$Silent" -Color Blue
            Update-Un1nst4ll3rSpinner -Message "Removendo via Windows Installer..."
            $msiProc = Start-Process "MsiExec.exe" -ArgumentList $msiArgs -Wait -PassThru -Verb RunAs
            Write-Un1Log -Category "UNINSTALL-DBG" -Message "MSI launch completed. PID=$($msiProc.Id) | ExitCode=$($msiProc.ExitCode)" -Color Blue
            Write-Un1Log -Category "UNINSTALL" -Message "MSI removal command executed." -Color Green
            return $true
        }

        # ======================================================================
        # INTERCEPTOR: Apps baseados em Rundll32 (ClickOnce e outros)
        # ======================================================================
        elseif ($uninstallCmd -match 'rundll32\.exe') {
            Write-Un1Log -Category "UNINSTALL" -Message "Removing via Rundll32..." -Color Cyan
            Update-Un1nst4ll3rSpinner -Message "Executando desinstalador via Rundll32..."
            
            $isClickOnce = $uninstallCmd -match 'dfshim\.dll'
            $needsElevation = -not $isClickOnce
            
            $rundllArgs = $uninstallCmd -replace '^.*?rundll32\.exe\s*', ''
            
            try {
                $spArgs = @{
                    FilePath = "rundll32.exe"
                    ArgumentList = $rundllArgs
                    Wait = $true
                    PassThru = $true
                }
                
                if ($needsElevation) {
                    $spArgs.Verb = "RunAs"
                    Write-Un1Log -Category "UNINSTALL-DBG" -Message "Rundll32 launch WITH Elevation (System-wide)." -Color Blue
                } else {
                    Write-Un1Log -Category "UNINSTALL-DBG" -Message "Rundll32 launch WITHOUT Elevation (ClickOnce/User-specific)." -Color Blue
                }

                $childProc = Start-Process @spArgs -ErrorAction Stop
                
                Write-Un1Log -Category "UNINSTALL-DBG" -Message "Rundll32 process completed. ExitCode=$($childProc.ExitCode)" -Color Blue
                Write-Un1Log -Category "UNINSTALL" -Message "Rundll32 removal command executed." -Color Green
                return $true

            } catch {
                Write-Un1Log -Category "UNINSTALL" -Message "Rundll32 execution failed: $_" -Color Red
                return $false
            }
        }

        elseif (![string]::IsNullOrWhiteSpace($uninstallCmd)) {

            $logLabel = if ($Silent) { "Silent" } else { "Standard" }
            Write-Un1Log -Category "UNINSTALL" -Message "Removing via $logLabel Uninstall String..." -Color Cyan

            $uninstallCmd = $uninstallCmd -replace '[""]', '"'

            $exe   = ""
            $argms = ""

            if ($uninstallCmd.TrimStart().StartsWith('"')) {
                $parts = $uninstallCmd -split '"'
                $exe   = $parts[1].Trim()
                $argms = if ($parts.Count -gt 2) { $parts[2].Trim() } else { "" }
            } elseif ($uninstallCmd -match '(.*?\.(exe|msi))\s+(.*)') {
                $exe = $Matches[1].Trim()
                $argms = $Matches[3].Trim()
            } else {
                $exe = $uninstallCmd.Trim()
                $argms = ""
            }

            try {
                if ([string]::IsNullOrWhiteSpace($exe)) { throw "Failed to parse executable from uninstall string." }
                
                $exeExists = Test-Path $exe -ErrorAction SilentlyContinue
                Write-Un1Log -Category "UNINSTALL-DBG" -Message "Standard launch prepared. App=$AppName | Silent=$Silent | FilePath=$exe | Exists=$exeExists | Args=$argms | Raw=$uninstallCmd" -Color Blue

                $spArgs = @{ FilePath = $exe; Wait = $true; PassThru = $true; Verb = "RunAs" }
                if (![string]::IsNullOrWhiteSpace($argms)) { $spArgs.ArgumentList = $argms }

                $childProc = Start-Process @spArgs -ErrorAction Stop
                
                Start-Sleep -Milliseconds 500 

                Write-Un1Log -Category "UNINSTALL-DBG" -Message "Standard launch completed. PID=$($childProc.Id) | ExitCode=$($childProc.ExitCode) | HasExited=$($childProc.HasExited)" -Color Blue
                Write-Un1Log -Category "UNINSTALL" -Message "$logLabel removal command executed." -Color Green
                return $true

            } catch {
                Write-Un1Log -Category "UNINSTALL-DBG" -Message "Standard launch failed. FilePath=$exe | Args=$argms | Exists=$(Test-Path $exe -ErrorAction SilentlyContinue) | Error=$_" -Color DarkYellow
                Write-Un1Log -Category "UNINSTALL" -Message "Start-Process failed [$_], falling back to cmd..." -Color Yellow
                try {
                    Write-Un1Log -Category "UNINSTALL-DBG" -Message "CMD fallback prepared. Command=/c `"$uninstallCmd`"" -Color Blue
                    $fallbackProc = Start-Process cmd -ArgumentList "/c `"$uninstallCmd`"" -Wait -Verb RunAs -ErrorAction Stop -PassThru
                    
                    Start-Sleep -Milliseconds 500 

                    Write-Un1Log -Category "UNINSTALL-DBG" -Message "CMD fallback completed. PID=$($fallbackProc.Id) | ExitCode=$($fallbackProc.ExitCode)" -Color Blue
                    Write-Un1Log -Category "UNINSTALL" -Message "cmd fallback executed successfully." -Color Green
                    return $true
                } catch {
                    Write-Un1Log -Category "UNINSTALL-DBG" -Message "CMD fallback failed. Error=$_" -Color DarkYellow
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

    # 1. Registro
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
    # NOVO: 2.5 Busca Profunda no Registro (Sanitizando o Nome)
    # ======================================================================
    $sanitizedApp = Get-Un1nst4ll3rSanitizedName -RawName $App.Nome
    Write-Un1Log -Category "TRACE-FIND" -Message "Sanitized app name for deep search: '$sanitizedApp' (Original: '$($App.Nome)')" -Color Blue
    
    if (![string]::IsNullOrWhiteSpace($sanitizedApp) -and $sanitizedApp.Length -ge 3) {
        # Busca nas hives principais de software
        $deepRegTraces = Find-Un1nst4ll3rDeepRegistryTraces -SearchTerm $sanitizedApp -AppRoot $AppRoot

        # Filtra para não duplicar chaves que já foram mapeadas pelo registro de desinstalação padrão
        $existingRegs = $regPaths | ForEach-Object { $_.TrimEnd('\').ToLower() }
        
        foreach ($trace in $deepRegTraces) {
            $normPath = $trace.Caminho.TrimEnd('\').ToLower()
            
            # Se a chave não estiver já na lista, adiciona como vestígio
            if ($existingRegs -notcontains $normPath) {
                # Evita adicionar a raiz HKLM:\SOFTWARE itself se o sanitized for muito genérico
                if ($trace.Caminho -ne "HKLM:\SOFTWARE" -and $trace.Caminho -ne "HKCU:\SOFTWARE") {
                    & $addTarget "Registro" $trace.Caminho $false "Deep Match ($($trace.Nome))"
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
            $normalizedPath = $path.TrimEnd('\').ToLower()

            foreach ($other in $InstalledApps) {
                if ($other.Nome -eq $App.Nome -and $other.Chave -eq $App.Chave) { continue }
                $otherLocal = $other.Local
                if ([string]::IsNullOrWhiteSpace($otherLocal)) { continue }
                $normalizedOther = $otherLocal.TrimEnd('\').ToLower()

                if ($normalizedOther.StartsWith("$normalizedPath\") -or $normalizedOther -eq $normalizedPath) {
                    $isShared = $true
                    break
                }
            }

            if ($isShared) {
                & $addTarget "Pasta" $path $true "Compartilhado (Outro App)"
            } else {
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
    Update-Un1nst4ll3rSpinner -Message "Removendo vestígios selecionados..."

    foreach ($target in $Targets) {
        # Segurança extra: nunca apaga protegidos
        if ($target.Protected) { continue }

        Write-Un1Log -Category "CLEANUP" -Message "Removing $($target.Type): $($target.Path)" -Color Cyan
        
        if ($target.Type -eq "Registro") {
            Remove-Item $target.Path -Recurse -Force -ErrorAction SilentlyContinue
            $cleanedCount++
        }
        elseif ($target.Type -eq "Atalho") {
            Remove-Item $target.Path -Force -ErrorAction SilentlyContinue
            $cleanedCount++
        }
        elseif ($target.Type -eq "Pasta") {
            $removed = Remove-Un1nst4ll3rCleanupDirectory -Path $target.Path
            if ($removed) { $cleanedCount++ }
        }
    }

    Write-Un1Log -Category "CLEANUP" -Message "Cleanup finished. $cleanedCount trace(s) removed." -Color Green
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
        [Parameter(Mandatory=$true)]
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
    } catch {
        Write-Un1Log -Category "DEEP-REG" -Message "Erro ao ler JSON do RegSearch: $($_.Exception.Message)" -Color Red
        return @()
    }
}

# ==========================================
# FIM DO MÓDULO CORE
# ==========================================
Write-Un1Log -Category "INIT" -Message "Un1nst4ll3r-core.ps1 loaded successfully." -Color DarkGray