# ======================================================================
# Un1nst4ll3r - Search Traces Engine
#  Version: 0.2.0
# ======================================================================


function Search-AppTraces {
    
    $basePaths = @(
        $env:ProgramFiles,
        ${env:ProgramFiles(x86)},
        $env:LOCALAPPDATA,
        $env:APPDATA
    )

    $basePaths = $basePaths | Where-Object { $_ -and (Test-Path $_) } | Sort-Object -Unique
    $vestigiosEncontrados = @()

    foreach ($basePath in $basePaths) {
        # Pega apenas as pastas no primeiro nível (ex: C:\Program Files\MeuApp)
        $pastasNivel1 = Get-ChildItem -Path $basePath -Directory -ErrorAction SilentlyContinue

        foreach ($pasta in $pastasNivel1) {
            if ($null -eq $pasta) { continue }

            $isTrace = $false
            $statusMsg = "Vestígio"
            
            # 1. Coletamos os arquivos da raiz da pasta
            $arquivosRaiz = Get-ChildItem -Path $pasta.FullName -File -ErrorAction SilentlyContinue
            
            # 2. Procuramos subpastas especiais (bin, ide, enu) e coletamos os arquivos soltos dentro delas
            $subpastasEspeciais = Get-ChildItem -Path $pasta.FullName -Directory -ErrorAction SilentlyContinue | 
            Where-Object { $_.Name -match "(?i)^(bin|ide|enu)$" }
            
            $arquivosDeSubpastas = @()
            foreach ($sub in $subpastasEspeciais) {
                $arquivosDeSubpastas += Get-ChildItem -Path $sub.FullName -File -ErrorAction SilentlyContinue
            }

            # 3. Unificamos todos os arquivos encontrados (Raiz + bin/ide/enu) para avaliar o App como um todo
            $todosOsArquivos = @()
            if ($arquivosRaiz) { $todosOsArquivos += $arquivosRaiz }
            if ($arquivosDeSubpastas) { $todosOsArquivos += $arquivosDeSubpastas }

            # Verifica se a pasta está totalmente vazia (sem arquivos e sem subpastas de qualquer tipo)
            $temSubpastas = Get-ChildItem -Path $pasta.FullName -Directory -ErrorAction SilentlyContinue
            
            # REGRA 1: Pasta totalmente vazia
            if (-not $todosOsArquivos -and -not $temSubpastas) {
                $isTrace = $true
                $statusMsg = "Pasta Vazia"
            }
            elseif ($todosOsArquivos) {
                $hasUnins = $false
                $hasOtherExe = $false
                $hasJunkFile = $false

                foreach ($arquivo in $todosOsArquivos) {
                    if ($null -eq $arquivo) { continue }
                    
                    $ext = $arquivo.Extension.ToLower()
                    $name = $arquivo.Name

                    if ($name -match "(?i)^unins.*") { $hasUnins = $true }
                    if ($ext -eq ".exe" -and $name -notmatch "(?i)^unins.*\.exe$") { $hasOtherExe = $true }
                    if ($ext -in @(".log", ".txt", ".ico", ".lnk")) { $hasJunkFile = $true }
                }

                # REGRA 2: Se tem um exe principal (seja na raiz ou dentro do bin/ide/enu), é um app válido.
                if ($hasOtherExe) {
                    $isTrace = $false
                }
                else {
                    # REGRA 3: Apenas o unins* como exe (em qualquer lugar)
                    if ($hasUnins) {
                        $isTrace = $true
                        $statusMsg = "Apenas Unins*"
                    }
                    
                    # REGRA 4: Tem arquivos de lixo soltos (em qualquer lugar)
                    if ($hasJunkFile) {
                        $isTrace = $true
                        $statusMsg = "Resíduos (Log/Txt/Ico/Lnk)"
                    }
                }
            }

            if ($isTrace) {
                $vestigiosEncontrados += [PSCustomObject]@{
                    Type      = "Pasta"
                    Path      = $pasta.FullName
                    Status    = $statusMsg
                    IconIndex = 0
                }
            }
        }
    }

    return $vestigiosEncontrados
}

function Remove-FoundTraces {
    param (
        [string[]]$Targets
    )

    $cleanedCount = 0

    foreach ($path in $Targets) {
        if ([string]::IsNullOrWhiteSpace($path)) { continue }
        
        # Se a pasta nem existe mais, pula
        if (-not (Test-Path -Path $path -ErrorAction SilentlyContinue)) { 
            $cleanedCount++
            continue 
        }

        $isRemoved = $false
        $accessDenied = $false

        # ==========================================
        # TENTATIVA 1: EXCLUSÃO DIRETA (POWERSHELL)
        # ==========================================
        try {
            # Tenta remover a pasta e todo seu conteúdo de forma forçada
            Remove-Item -Path $path -Recurse -Force -ErrorAction Stop
            $isRemoved = $true
        }
        catch [System.UnauthorizedAccessException], [System.Security.SecurityException] {
            $accessDenied = $true
        }
        catch {
            # Outros erros (ex: arquivo em uso) também podem ser tentados via elevação
            $accessDenied = $true
        }

        # Verifica se a tentativa direta funcionou
        if ($isRemoved -and -not (Test-Path -Path $path -ErrorAction SilentlyContinue)) {
            $cleanedCount++
            continue
        }

        # ==========================================
        # TENTATIVA 4: ELEVAÇÃO DIRECIONADA (A MÁGICA)
        # ==========================================
        if ($accessDenied) {
            Write-Un1Log -Category "CLEANUP" -Message "Access denied detected. Attempting targeted elevation for: $Path" -Color Magenta
            try {
                # O comando rmdir /s /q do CMD força a exclusão recursiva silenciosa
                Start-Process -FilePath "cmd.exe" -ArgumentList "/c rmdir /s /q `"$path`"" -Verb RunAs -Wait -WindowStyle Hidden -ErrorAction Stop
                Start-Sleep -Milliseconds 500

                if (-not (Test-Path -Path $path -ErrorAction SilentlyContinue)) {
                    Write-Un1Log -Category "CLEANUP" -Message "Successfully removed via elevated process: $Path" -Color Green
                    $cleanedCount++
                }
            }
            catch {
                Write-Un1Log -Category "CLEANUP" -Message "Targeted elevation failed or was cancelled by user: $Path" -Color Red
            }
        }
    }

    return $cleanedCount
}