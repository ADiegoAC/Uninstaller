# ==========================================
# Un1nst4ll3r - Motor de Busca
# Versão: 0.9 (Fallback de Fabricante via Metadado)
# ==========================================

Write-Host "===========================================" -ForegroundColor Cyan
Write-Host "       Un1nst4ll3r - Instalados Scan        " -ForegroundColor Cyan
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host "Iniciando varredura..." -ForegroundColor Yellow

 $installedPrograms = @()
 $orphanCount = 0

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
                
                $isOrphan = $false
                $installDir = $item.InstallLocation
                if ($installDir -and !(Test-Path $installDir)) {
                    $isOrphan = $true
                    $orphanCount++
                }

                # Lógica inteligente de Fabricante
                $publisher = $item.Publisher
                if ([string]::IsNullOrWhiteSpace($publisher)) {
                    # Se o registro não tem, tenta ler os metadados do executável
                    $iconPath = $item.DisplayIcon
                    if (![string]::IsNullOrWhiteSpace($iconPath)) {
                        # Limpa o caminho do ícone (remove aspas e índices como ",0")
                        $iconPath = $iconPath -replace '\"', '' -replace ',\d+$', ''
                        if (Test-Path $iconPath -ErrorAction SilentlyContinue) {
                            try {
                                $fileInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($iconPath)
                                if (![string]::IsNullOrWhiteSpace($fileInfo.CompanyName)) {
                                    $publisher = $fileInfo.CompanyName
                                }
                            } catch {
                                # Ignora se o arquivo estiver bloqueado ou inacessível
                            }
                        }
                    }
                }

                $installedPrograms += [PSCustomObject]@{
                    Nome        = $item.DisplayName
                    Versao      = $item.DisplayVersion
                    Fabricante  = if ($publisher) { $publisher } else { "N/A" }
                    Chave       = $item.PSChildName
                    Tipo        = "Win32"
                    Status      = if ($isOrphan) { "Órfão" } else { "OK" }
                }
            }
        }
    }
}

# 2. Varredura de aplicativos da Microsoft Store (AppX)
 $appxPackages = Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object {
    $_.IsFramework -eq $false -and $_.SignatureKind -ne "None"
}

foreach ($app in $appxPackages) {
    if ($app.Name -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}') { continue }

    try {
        $manifest = $app | Get-AppxPackageManifest -ErrorAction Stop
        
        $appListEntry = $manifest.Package.Applications.Application.AppListEntry
        $isHidden = (-not $appListEntry -or $appListEntry -eq "none")
        $isMicrosoft = $app.Publisher -match "Microsoft"
        
        if ($isHidden -and $isMicrosoft) { continue }
        if ($app.Publisher -match "Microsoft Windows") { continue }

        $displayName = $app.Name
        $xmlDisplayName = $manifest.Package.Properties.DisplayName
        if ($xmlDisplayName -and $xmlDisplayName -notlike "ms-resource*") {
            $displayName = $xmlDisplayName
        }

        $cleanPublisher = $app.Publisher
        $xmlPublisher = $manifest.Package.Properties.PublisherDisplayName
        
        if ($xmlPublisher -and $xmlPublisher -notlike "ms-resource*") {
            $cleanPublisher = $xmlPublisher
        } elseif ($cleanPublisher -match 'CN=([^,]+)') {
            $cleanPublisher = $matches[1]
        } elseif ($cleanPublisher -match '^[0-9a-fA-F]{8}-') {
            $cleanPublisher = "N/A"
        }

        $installedPrograms += [PSCustomObject]@{
            Nome        = $displayName
            Versao      = $app.Version
            Fabricante  = $cleanPublisher
            Chave       = $app.PackageFullName
            Tipo        = "AppX"
            Status      = "OK"
        }
    }
    catch {}
}

 $programasUnicos = $installedPrograms | Sort-Object Status, Nome -Unique

Write-Host "`nForam encontrados $($programasUnicos.Count) programas instalados." -ForegroundColor Green
if ($orphanCount -gt 0) {
    Write-Host "ALERTA: $orphanCount programa(s) com vestígios órfãos encontrados!" -ForegroundColor Red
}

 $programasUnicos | Format-Table -Property Nome, Versao, Fabricante, Tipo, Status -AutoSize

Write-Host "===========================================" -ForegroundColor Cyan
Write-Host "Varredura concluída!" -ForegroundColor Green