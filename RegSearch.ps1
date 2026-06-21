<#
.SYNOPSIS
    Varre o registro do Windows e retorna chaves/valores que contenham o termo informado.

.PARAMETER s
    Termo de busca (literal por padrão).

.PARAMETER Hives
    Caminhos de registro a varrer. Padrão: HKLM:\, HKCU:\
    Aceita caminhos parciais, ex: "HKLM:\SOFTWARE\Microsoft"

.PARAMETER Skip
    Nomes de subchaves a ignorar completamente (case-insensitive).
    Padrão: Classes, WOW6432Node  (as duas maiores/mais irrelevantes para apps)
    Use -Skip @() para desativar o filtro.

.PARAMETER IncludeData
    Inclui busca dentro dos dados dos valores, não só nos nomes.

.PARAMETER Regex
    Trata o termo -s como expressão regular.

.PARAMETER CaseSensitive
    Diferencia maiúsculas de minúsculas na busca.

.PARAMETER TimerPerHive
    Exibe tempo gasto em cada hive raiz (útil para diagnóstico de performance).

.PARAMETER ExportJson
    Exporta os resultados em JSON comprimido para integração com outras aplicações.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0, HelpMessage = 'Termo de busca')]
    [string] $s,

    [string[]] $Hives = @('HKLM:\', 'HKCU:\'),

    [string[]] $Skip = @('Classes', 'WOW6432Node'),

    [switch] $IncludeData,

    [switch] $Regex,

    [switch] $CaseSensitive,

    [switch] $TimerPerHive,

    [switch] $ExportJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

# BLOQUEIA A BARRA DE PROGRESSO E OUTRAS SAÍDAS VISUAIS SE FOR PARA EXPORTAR JSON
if ($ExportJson) {
    $ProgressPreference = 'SilentlyContinue'
}

# --- Prepara o padrão de busca ---
$pattern = if ($Regex) { $s } else { [regex]::Escape($s) }

function Test-Match([string] $text) {
    if ($CaseSensitive) { $text -cmatch $pattern }
    else { $text -imatch $pattern }
}

# Conjunto de nomes a pular (lookup O(1))
$skipSet = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::OrdinalIgnoreCase
)
foreach ($sk in $Skip) { [void]$skipSet.Add($sk) }

# --- Coleção de resultados ---
$results = [System.Collections.Generic.List[PSCustomObject]]::new()
$scanned = 0
$skipped = 0

function Search-RegistryKey {
    param([string] $Path)

    $key = try { Get-Item -LiteralPath $Path -ErrorAction Stop } catch { return }
    $script:scanned++

    if (-not $ExportJson -and $script:scanned % 500 -eq 0) {
        Write-Progress -Activity "Varrendo registro" `
            -Status "$script:scanned chaves | $($results.Count) resultados | $script:skipped puladas" `
            -CurrentOperation $Path
    }

    # ── Testa o NOME da chave ──────────────────────────────────────────────────
    if (Test-Match $key.PSChildName) {
        $results.Add([PSCustomObject]@{
                Tipo    = 'Chave'
                Caminho = $Path
                Nome    = $key.PSChildName
                Dados   = ''
            })
    }

    # ── Testa os VALORES da chave ──────────────────────────────────────────────
    foreach ($valueName in $key.GetValueNames()) {
        $displayName = if ($valueName -eq '') { '(Padrao)' } else { $valueName }
        $hit = Test-Match $displayName

        $rawData = ''
        if ($IncludeData -or $hit) {
            $rawData = try { "$($key.GetValue($valueName))" } catch { '<ilegivel>' }
        }

        if (-not $hit -and $IncludeData) {
            $hit = Test-Match $rawData
        }

        if ($hit) {
            $displayData = if ($rawData.Length -gt 80) { $rawData.Substring(0, 77) + '...' } else { $rawData }

            $results.Add([PSCustomObject]@{
                    Tipo    = 'Valor'
                    Caminho = $Path
                    Nome    = $displayName
                    Dados   = $displayData
                })
        }
    }

    # ── Recursão nas subchaves ─────────────────────────────────────────────────
    $subKeys = try { Get-ChildItem -LiteralPath $Path -ErrorAction Stop } catch { return }
    foreach ($sub in $subKeys) {
        if ($skipSet.Count -gt 0 -and $skipSet.Contains($sub.PSChildName)) {
            $script:skipped++
            continue
        }
        Search-RegistryKey -Path $sub.PSPath
    }
}

# --- Cabeçalho (Só imprime se não for ExportJson) ---
if (-not $ExportJson) {
    $skipLabel = if ($skipSet.Count -gt 0) { $Skip -join ', ' } else { '(nenhuma)' }

    Write-Host ''
    Write-Host '  RegSearch' -ForegroundColor Cyan -NoNewline
    Write-Host ' -- busca no registro do Windows' -ForegroundColor Gray
    Write-Host "  Termo   : $s"                                                -ForegroundColor White
    Write-Host "  Modo    : $(if ($Regex) { 'Regex' } else { 'Literal' })"    -ForegroundColor Gray
    Write-Host "  Case    : $(if ($CaseSensitive) { 'Sensivel' } else { 'Insensivel' })" -ForegroundColor Gray
    Write-Host "  Dados   : $(if ($IncludeData) { 'Incluidos' } else { 'Excluidos' })"  -ForegroundColor Gray
    Write-Host "  Pulando : $skipLabel"                                        -ForegroundColor DarkYellow
    Write-Host "  Hives   : $($Hives -join ' | ')"                            -ForegroundColor Gray
    Write-Host ''
}

# --- Execução ---
$swTotal = [System.Diagnostics.Stopwatch]::StartNew()

foreach ($hive in $Hives) {
    if ($TimerPerHive -and -not $ExportJson) {
        $swHive = [System.Diagnostics.Stopwatch]::StartNew()
        $beforeCount = $scanned
        $beforeSkip = $skipped
        $beforeResults = $results.Count
    }

    Search-RegistryKey -Path $hive

    if ($TimerPerHive -and -not $ExportJson) {
        $swHive.Stop()
        $elapsed = [math]::Round($swHive.Elapsed.TotalSeconds, 2)
        $delta = $scanned - $beforeCount
        $dSkip = $skipped - $beforeSkip
        $dRes = $results.Count - $beforeResults
        Write-Host "  [hive] $hive" -ForegroundColor DarkGray -NoNewline
        Write-Host "  ${elapsed}s" -ForegroundColor Yellow -NoNewline
        Write-Host "  |  ${delta} chaves  |  ${dSkip} puladas  |  ${dRes} resultados" -ForegroundColor DarkGray
    }
}

$swTotal.Stop()
Write-Progress -Activity "Varrendo registro" -Completed

# =======================================================
# BLOCO DE EXPORTAÇÃO PARA O APP (JSON PURO)
# =======================================================
if ($ExportJson) {
    if ($results.Count -gt 0) {
        @($results | Select-Object Tipo, Caminho, Nome) | ConvertTo-Json -Compress
    }
    exit 0
}

# =======================================================
# SAÍDA NORMAL NO TERMINAL (SÓ RODA SE NÃO FOR -ExportJson)
# =======================================================
Write-Host ''
Write-Host "  $scanned chave(s) varrida(s) em $([math]::Round($swTotal.Elapsed.TotalSeconds, 1))s  |  $skipped subarvore(s) pulada(s)" -ForegroundColor DarkGray

if ($results.Count -eq 0) {
    Write-Host "  Nenhum resultado para [$s]." -ForegroundColor Yellow
    Write-Host ''
    exit 0
}

Write-Host "  $($results.Count) resultado(s) encontrado(s) para [$s]" -ForegroundColor Green
Write-Host ''

$results | Format-Table -Property Tipo, Nome, Dados, Caminho -AutoSize -Wrap

Write-Host ''