# ==========================================
# Un1nst4ll3r - Módulo de Scan Cirúrgico
# Versão: 0.3
# ==========================================

Write-Host "===========================================" -ForegroundColor Cyan
Write-Host "       Un1nst4ll3r - Instalados Scan        " -ForegroundColor Cyan
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host "Iniciando varredura (Filtrando lixo do sistema)..." -ForegroundColor Yellow

 $installedPrograms = @()

# 1. Varredura de programas Win32 (Registro)
 $registryPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKCU:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
)

foreach ($path in $registryPaths) {
    if (Test-Path $path) {
        $items = Get-ItemProperty $path -ErrorAction SilentlyContinue
        foreach ($item in $items) {
            if ($item.DisplayName -and !$item.SystemComponent -and !$item.ParentKeyName) {
                $installedPrograms += [PSCustomObject]@{
                    Nome        = $item.DisplayName
                    Versao      = $item.DisplayVersion
                    Fabricante  = $item.Publisher
                    DataInst    = if ($item.InstallDate) { $item.InstallDate } else { "N/A" }
                    Chave       = $item.PSChildName
                    Tipo        = "Win32"
                }
            }
        }
    }
}

# 2. Varredura de aplicativos da Microsoft Store (AppX) - FILTRO AVANÇADO
 $appxPackages = Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object {
    $_.IsFramework -eq $false -and $_.SignatureKind -ne "None"
}

foreach ($app in $appxPackages) {
    try {
        # Tenta ler o manifesto. Se der erro (fantasma), pula pro próximo
        $manifest = $app | Get-AppxPackageManifest -ErrorAction Stop
        
        # Checa se o aplicativo é visível no Painel de Controle/Menu Iniciar
        $appListEntry = $manifest.Package.Applications.Application.AppListEntry
        
        # Se for "none" ou vazio, o Windows esconde. Nós também vamos esconder.
        if (-not $appListEntry -or $appListEntry -eq "none") {
            continue
        }

        # Tenta pegar o nome amigável
        $displayName = $app.Name
        $xmlDisplayName = $manifest.Package.Properties.DisplayName
        if ($xmlDisplayName -and $xmlDisplayName -notlike "ms-resource*") {
            $displayName = $xmlDisplayName
        }

        $installedPrograms += [PSCustomObject]@{
            Nome        = $displayName
            Versao      = $app.Version
            Fabricante  = $app.Publisher
            DataInst    = "N/A"
            Chave       = $app.PackageFullName
            Tipo        = "AppX"
        }
    }
    catch {
        # Ignora silenciosamente os pacotes quebrados/fantasmas que causam o erro 0x80070002
    }
}

# Remove duplicatas e ordena por nome
 $programasUnicos = $installedPrograms | Sort-Object Nome -Unique

# Exibe os resultados
Write-Host "`nForam encontrados $($programasUnicos.Count) programas instalados:`n" -ForegroundColor Green
 $programasUnicos | Format-Table -Property Nome, Versao, Fabricante, Tipo -AutoSize

Write-Host "===========================================" -ForegroundColor Cyan
Write-Host "Varredura concluída!" -ForegroundColor Green