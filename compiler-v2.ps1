# compile.ps1 - Build Un1nst4ll3r (Bundle Base64 → %TEMP%)

$filesToEmbed = @(
    ".\Un1nst4ll3r-UI.ps1",
    ".\Un1nst4ll3r.ps1",
    ".\Un1nst4ll3r-core.ps1",
    ".\Un1nst4ll3r-searchTraces.ps1",
    ".\RegSearch.ps1",
    ".\Un1nst4ll3r_Lang.json",
    ".\Un1nst4ll3r_SysPkgBank.json",
    ".\icon.ico",
    ".\busy.gif",
    ".\README.md",
    ".\README_POR.md",
    ".\README_ES.md",
    ".\LICENSE",
    ".\CHANGELOG.md"
)

# ── 1. Serializa cada arquivo como Base64 ──────────────────────────────────────
$dictLines = [System.Collections.Generic.List[string]]::new()
$dictLines.Add('$_B = @{')

foreach ($file in $filesToEmbed) {
    if (Test-Path $file) {
        $bytes = [System.IO.File]::ReadAllBytes((Resolve-Path $file).Path)
        $b64   = [Convert]::ToBase64String($bytes)
        $name  = Split-Path $file -Leaf
        $dictLines.Add("  '$name'='$b64'")
    } else {
        Write-Warning "Não encontrado: $file"
    }
}
$dictLines.Add('}')

# ── 2. Monta o script bundle ───────────────────────────────────────────────────
# Cabeçalho: cria/recria pasta temp limpa a cada execução
$header = @'
$_T = Join-Path $env:TEMP 'Un1nst4ll3r'
if (Test-Path $_T) { Remove-Item $_T -Recurse -Force -ErrorAction SilentlyContinue }
$null = New-Item -ItemType Directory -Path $_T -Force
'@

# Rodapé: extrai todos os arquivos e dispara a UI
$footer = @'
foreach ($n in $_B.Keys) {
    [IO.File]::WriteAllBytes((Join-Path $_T $n), [Convert]::FromBase64String($_B[$n]))
}
& (Join-Path $_T 'Un1nst4ll3r-UI.ps1')
'@

$bundlePath = ".\Un1nst4ll3r-bundle.ps1"
($header + "`n" + ($dictLines -join "`n") + "`n" + $footer) |
    Set-Content $bundlePath -Encoding UTF8

Write-Host "Bundle gerado." -ForegroundColor DarkCyan

# ── 3. Compila o bundle (sem embedFiles) ──────────────────────────────────────
$compileArgs = @{
    InputFile    = $bundlePath
    OutputFile   = ".\Un1nst4ll3r.exe"
    noConsole    = $true
    title        = "Un1nst4ll3r"
    requireAdmin = $false
    iconFile     = ".\icon.ico"
}

Write-Host "Compilando Un1nst4ll3r.exe..." -ForegroundColor Cyan
Invoke-PS2EXE @compileArgs

if (Test-Path ".\Un1nst4ll3r.exe") {
    Write-Host "Build concluído! Un1nst4ll3r.exe gerado." -ForegroundColor Green
    Remove-Item $bundlePath -ErrorAction SilentlyContinue
} else {
    Write-Host "Falha na compilação." -ForegroundColor Red
}