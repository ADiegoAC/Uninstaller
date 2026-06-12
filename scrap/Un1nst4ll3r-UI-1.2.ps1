# ==========================================
# Un1nst4ll3r - Interface (Capítulo 2)
# Versão: 1.2 (Integração Deep Size)
# ==========================================

# 1. Truque de DPI Awareness (Evita embaçamento no zoom do Windows)
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class DpiHelper {
    [DllImport("user32.dll", SetLastError=true)]
    public static extern bool SetProcessDPIAware();
}
'@
[DpiHelper]::SetProcessDPIAware()

# 2. Carregar Assemblies do Windows Forms
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# 3. Importar o Motor (Un1nst4ll3r.ps1 deve estar na mesma pasta)
 $enginePath = Join-Path $PSScriptRoot "Un1nst4ll3r.ps1"
if (Test-Path $enginePath) {
    . $enginePath
} else {
    [System.Windows.Forms.MessageBox]::Show("O motor Un1nst4ll3r.ps1 não foi encontrado na mesma pasta da interface!", "Erro Critico", "OK", "Error")
    exit
}

# 4. Calcular tamanho da janela baseado na tela (70% da resolução)
 $screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
 $formWidth = [int]($screen.Width * 0.70)
 $formHeight = [int]($screen.Height * 0.70)

# ==========================================
# 5. Criação da Janela Principal (Form)
# ==========================================
 $form = New-Object System.Windows.Forms.Form
 $form.Text = "Un1nst4ll3r"
 $form.Size = New-Object System.Drawing.Size($formWidth, $formHeight)
 $form.StartPosition = "CenterScreen"
 $form.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
 $form.ForeColor = [System.Drawing.Color]::White
 $form.MinimumSize = New-Object System.Drawing.Size(600, 400)

# ==========================================
# 6. Cabeçalho (Top Bar)
# ==========================================
 $headerPanel = New-Object System.Windows.Forms.Panel
 $headerPanel.Dock = "Top"
 $headerPanel.Height = 60
 $headerPanel.BackColor = [System.Drawing.Color]::FromArgb(20, 20, 20)
 $headerPanel.Padding = New-Object System.Windows.Forms.Padding(15)

 $titleLabel = New-Object System.Windows.Forms.Label
 $titleLabel.Text = "Un1nst4ll3r"
 $titleLabel.Font = New-Object System.Drawing.Font("Consolas", 20, [System.Drawing.FontStyle]::Bold)
 $titleLabel.ForeColor = [System.Drawing.Color]::FromArgb(0, 191, 255)
 $titleLabel.AutoSize = $true
 $titleLabel.Location = New-Object System.Drawing.Point(15, 8)

 $versionLabel = New-Object System.Windows.Forms.Label
 $versionLabel.Text = "v1.2 | Installed Programs Scanner"
 $versionLabel.Font = New-Object System.Drawing.Font("Consolas", 9)
 $versionLabel.ForeColor = [System.Drawing.Color]::Gray
 $versionLabel.AutoSize = $true
 $versionLabel.Location = New-Object System.Drawing.Point(18, 44)

 $headerPanel.Controls.AddRange(@($titleLabel, $versionLabel))

# ==========================================
# 7. Barra de Ações (Buttons)
# ==========================================
 $actionsPanel = New-Object System.Windows.Forms.Panel
 $actionsPanel.Dock = "Top"
 $actionsPanel.Height = 50
 $actionsPanel.BackColor = [System.Drawing.Color]::FromArgb(40, 40, 40)
 $actionsPanel.Padding = New-Object System.Windows.Forms.Padding(10, 5, 10, 5)

 $btnScan = New-Object System.Windows.Forms.Button
 $btnScan.Text = "SCAN SYSTEM"
 $btnScan.Font = New-Object System.Drawing.Font("Consolas", 10, [System.Drawing.FontStyle]::Bold)
 $btnScan.BackColor = [System.Drawing.Color]::FromArgb(0, 191, 255)
 $btnScan.ForeColor = [System.Drawing.Color]::Black
 $btnScan.FlatStyle = "Flat"
 $btnScan.Size = New-Object System.Drawing.Size(150, 35)
 $btnScan.Location = New-Object System.Drawing.Point(10, 7)

 $actionsPanel.Controls.Add($btnScan)

# ==========================================
# 8. Área de Conteúdo (O Grid)
# ==========================================
 $dataGridView = New-Object System.Windows.Forms.DataGridView
 $dataGridView.Dock = "Fill"
 $dataGridView.BackgroundColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
 $dataGridView.BorderStyle = "None"
 $dataGridView.EnableHeadersVisualStyles = $false
 $dataGridView.ColumnHeadersDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(20, 20, 20)
 $dataGridView.ColumnHeadersDefaultCellStyle.ForeColor = [System.Drawing.Color]::White
 $dataGridView.ColumnHeadersDefaultCellStyle.Font = New-Object System.Drawing.Font("Consolas", 9, [System.Drawing.FontStyle]::Bold)
 $dataGridView.DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(40, 40, 40)
 $dataGridView.DefaultCellStyle.ForeColor = [System.Drawing.Color]::LightGray
 $dataGridView.DefaultCellStyle.Font = New-Object System.Drawing.Font("Consolas", 9)
 $dataGridView.GridColor = [System.Drawing.Color]::FromArgb(60, 60, 60)
 $dataGridView.AllowUserToAddRows = $false
 $dataGridView.AllowUserToDeleteRows = $false
 $dataGridView.ReadOnly = $true
 $dataGridView.SelectionMode = "FullRowSelect"
 $dataGridView.AutoSizeColumnsMode = "AllCells"

# Colunas Atualizadas
 $dataGridView.Columns.Add("Nome", "Nome") | Out-Null
 $dataGridView.Columns.Add("Versao", "Versao") | Out-Null
 $dataGridView.Columns.Add("Fabricante", "Fabricante") | Out-Null
 $dataGridView.Columns.Add("Tamanho", "Tamanho") | Out-Null
 $dataGridView.Columns.Add("Tipo", "Tipo") | Out-Null
 $dataGridView.Columns.Add("Local", "Local") | Out-Null # Adicionado para o Deep Size, se quiserem ver
 $dataGridView.Columns.Add("Status", "Status") | Out-Null

# ==========================================
# 9. Rodapé (Status Bar)
# ==========================================
 $footerPanel = New-Object System.Windows.Forms.Panel
 $footerPanel.Dock = "Bottom"
 $footerPanel.Height = 30
 $footerPanel.BackColor = [System.Drawing.Color]::FromArgb(20, 20, 20)
 $footerPanel.Padding = New-Object System.Windows.Forms.Padding(10, 0, 10, 0)

 $statusLabel = New-Object System.Windows.Forms.Label
 $statusLabel.Text = "Ready."
 $statusLabel.Font = New-Object System.Drawing.Font("Consolas", 9)
 $statusLabel.ForeColor = [System.Drawing.Color]::Gray
 $statusLabel.AutoSize = $false
 $statusLabel.Dock = "Fill"
 $statusLabel.TextAlign = "MiddleLeft"

 $footerPanel.Controls.Add($statusLabel)

# ==========================================
# 10. Lógica de Integração (Motor -> UI)
# ==========================================
function Update-Grid {
    $statusLabel.Text = "Phase 1: Scanning registry and store..."
    $form.Refresh() # Força a UI a desenhar o status

    try {
        # FASE 1: Scan Rapido
        $scanResult = Get-Un1nst4ll3rScan
        
        $statusLabel.Text = "Phase 2: Calculating deep sizes... Please wait."
        $form.Refresh() # Avisa o usuario que vai calcular os tamanhos

        # FASE 2: Deep Size
        $deepResult = Get-Un1nst4ll3rDeepSize -ProgramList $scanResult
        
        $dataGridView.Rows.Clear()
        $orphanCount = 0

        foreach ($app in $deepResult) {
            $rowIndex = $dataGridView.Rows.Add()
            $row = $dataGridView.Rows[$rowIndex]
            
            $row.Cells["Nome"].Value = $app.Nome
            $row.Cells["Versao"].Value = $app.Versao
            $row.Cells["Fabricante"].Value = $app.Fabricante
            $row.Cells["Tamanho"].Value = $app.Tamanho
            $row.Cells["Tipo"].Value = $app.Tipo
            $row.Cells["Local"].Value = $app.Local
            $row.Cells["Status"].Value = $app.Status

            if ($app.Status -eq "Orfao") {
                $row.DefaultCellStyle.ForeColor = [System.Drawing.Color]::FromArgb(255, 80, 80) # Vermelho
                $orphanCount++
            }
        }

        $statusLabel.Text = "Scan complete. $($deepResult.Count) programs found. $(if($orphanCount -gt 0){\"ALERT: $orphanCount orphan(s) found!\"})"
    }
    catch {
        $statusLabel.Text = "Error during scan."
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Error", "OK", "Error")
    }
}

# Evento: Clicar no botão Scan
 $btnScan.Add_Click({
    Update-Grid
})

# Evento: Abrir o App (Auto-Scan)
 $form.Add_Shown({
    Update-Grid
})

# ==========================================
# 11. Montagem Final e Show
# ==========================================
 $form.Controls.Add($dataGridView)
 $form.Controls.Add($actionsPanel)
 $form.Controls.Add($headerPanel)
 $form.Controls.Add($footerPanel)

[void]$form.ShowDialog()