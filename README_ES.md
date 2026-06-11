# 🛠️ Un1nst4ll3r - Pro Edition v2.2  
### 🚀 Motor de Análisis de Sistema y Descompresión de Apps de Alto Rendimiento  

**Un1nst4ll3r** es una utilidad de mantenimiento de última generación basada en PowerShell, diseñada para rastrear aplicaciones instaladas y sus rastros "fantasmas". A diferencia de los desinstaladores estándar, utiliza heurísticas de nivel profundo para mapear el sistema de archivos y el registro.

---

## ⚡ Características Clave  

*   🔍 **Descubrimiento Multifuente**: Escanea el Registro estándar (Win32), nodos de 64 bits y paquetes modernos de **AppX/Windows Store**.
*   🕵️ **Detección de Huérfanos**: Usa la indexación de **MuiCache** y Accesos Directos para encontrar apps que han perdido sus entradas de registro pero aún residen en tu disco.
*   📊 **Motor de Tamaño Profundo**: Omite los metadados genéricos del registro para calcular el tamaño de las carpetas en tiempo real mediante una medición recursiva de E/S segura.
*   🛡️ **Filtro Inteligente**: Protege automáticamente las rutas críticas del sistema (WinSxS, System32) contra modificaciones accidentales.
*   📑 **Registro Estructurado**: Cada operación se registra con marcas de tiempo de alta resolución y se categoriza para inspección forense.
*   🌐 **Soporte Multilingüe**: Experiencia totalmente localizada para Inglés (US), Portugués (BR) y Español (ES).

---

## 🎮 Guía de la Interfaz Gráfica  

1.  **[LISTAR ESCANEO]** 💾: Carga instantáneamente los resultados del último escaneo exitoso desde la caché JSON local.
2.  **[NUEVO ESCANEO]** 🔄: Activa el **Motor de 4 Fases**:
    *   *Fase 1*: Interrogación de Registro y Store.
    *   *Fase 2*: Descubrimiento de MuiCache y Huérfanos.
    *   *Fase 3*: Medición profunda del tamaño en disco.
    *   *Fase 4*: Exportación de datos JSON.
3.  **[DESINSTALAR]** 🗑️: Lanza la secuencia de eliminación dirigida (Soporta modos MSI, Silencioso y AppX).
4.  **[VER LOG]** 📟: Abre la terminal de depuración en tiempo real para ver exactamente cómo el motor está resolviendo las rutas.

---

## ⚙️ Requisitos Técnicos  

*   **SO**: Windows 8.1/10/11
*   **Host**: **PowerShell 5.1** (Core), pero se recomienda encarecidamente 7.x para un rendimiento máximo.
*   **Dependencia**: Incluye un autoactualizador que utiliza **Winget** para mantener tu entorno PowerShell actualizado.(en mantenimiento)

---

## 🛠️ Inicio Rápido para Desarrolladores  

Inicia la interfaz directamente a través de la terminal:
```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File Un1nst4ll3r-UI.ps1
```

**Exportación de Datos**: Todos los resultados del escaneo se serializan en `Un1nst4ll3r_ScanResult.json` para una fácil integración con otras herramientas de automatización.

---

## 📜 Licencia y Créditos
Desarrollado con inteligencia como una alternativa de alto rendimiento a los desinstaladores heredados.
*   **Logs**: Almacenados en `$Global:Un1AnalysisLog`.
*   **Motor**: Arquitectura modular ubicada en `Un1nst4ll3r.ps1`.

*¿Quieres contribuir? ¡Siéntete libre de abrir un PR o reportar huérfanos que el motor heurístico haya pasado por alto!*