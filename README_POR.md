# 🛠️ Un1nst4ll3r - Pro Edition v2.2  
### 🚀 Motor de Análise de Sistema e Descompressão de Apps de Alta Performance  

**Un1nst4ll3r** é um utilitário de manutenção de última geração baseado em PowerShell, projetado para rastrear aplicativos instalados e seus rastros "fantasmas". Ao contrário dos desinstaladores padrão, ele utiliza heurísticas de nível profundo para mapear o sistema de arquivos e o registro.

---

## ⚡ Recursos Principais  

*   🔍 **Descoberta Multisource**: Escaneia o Registro padrão (Win32), nós de 64 bits e pacotes modernos de **AppX/Windows Store**.
*   🕵️ **Detecção de Órfãos**: Usa indexação de **MuiCache** e Atalhos para encontrar apps que perderam suas entradas de registro, mas ainda residem no seu disco.
*   📊 **Motor de Tamanho Profundo**: Ignora os metadados genéricos do registro para calcular o tamanho das pastas em tempo real via medição recursiva de I/O segura.
*   🛡️ **Filtro Inteligente**: Protege automaticamente caminhos críticos do sistema (WinSxS, System32) contra modificações acidentais.
*   📑 **Log Estruturado**: Cada operação é registrada com carimbos de data/hora de alta resolução e categorizada para inspeção forense.
*   🌐 **Suporte Multi-Idiomas**: Experiência totalmente localizada para Inglês (US), Português (BR) e Espanhol (ES).

---

## 🎮 Guia da Interface Gráfica  

1.  **[LISTAR SCAN]** 💾: Carrega instantaneamente os resultados da última verificação bem-sucedida do cache JSON local.
2.  **[NOVO SCAN]** 🔄: Aciona o **Motor de 4 Fases**:
    *   *Fase 1*: Interrogação de Registro e Store.
    *   *Fase 2*: Descoberta de MuiCache e Órfãos.
    *   *Fase 3*: Medição profunda do tamanho no disco.
    *   *Fase 4*: Exportação de dados JSON.
3.  **[DESINSTALAR]** 🗑️: Inicia a sequência de remoção direcionada (Suporta modos MSI, Silencioso e AppX).
4.  **[VER LOG]** 📟: Abre o terminal de depuração em tempo real para ver exatamente como o motor está resolvendo os caminhos.

---

## ⚙️ Requisitos Técnicos  

*   **SO**: Windows 8.1/10/11
*   **Host**: **PowerShell 5.1** (Core), mas 7.x é altamente recomendado para desempenho máximo.
*   **Dependência**: Inclui um auto-atualizador que utiliza o **Winget** para manter seu ambiente PowerShell atualizado.(em manutenção)

---

## 🛠️ Início Rápido para Desenvolvedores  

Inicie a interface diretamente via terminal:
```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File Un1nst4ll3r-UI.ps1
```

**Exportação de Dados**: Todos os resultados da verificação são serializados em `Un1nst4ll3r_ScanResult.json` para fácil integração com outras ferramentas de automação.

---

## 📜 Licença e Créditos
Desenvolvido com inteligência como uma alternativa de alta performance aos desinstaladores legados.
*   **Logs**: Armazenados em `$Global:Un1AnalysisLog`.
*   **Motor**: Arquitetura modular localizada em `Un1nst4ll3r.ps1`.

*Quer contribuir? Fique à vontade para abrir um PR ou relatar órfãos que o motor heurístico não encontrou!*