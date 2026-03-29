# win11-custom

Utilidad de línea de comandos para generar una ISO de Windows 11 modificada,
orientada a instalaciones **ligeras y directas** en **equipos de bajos recursos
y máquinas virtuales**.

El objetivo es eliminar todo lo que no aporta al uso cotidiano: telemetría,
asistentes en la nube, bloatware y restricciones de hardware artificiales,
dejando una instalación funcional desde el primer arranque sin necesidad de
configuración manual post-instalación.

---

## ¿Qué hace?

A partir de un ISO oficial de Windows 11, genera uno nuevo con las siguientes
modificaciones aplicadas:

**Privacidad y servicios**
- **Cuenta local preconfigurada** — sin necesidad de cuenta Microsoft
- **OOBE omitido** — la instalación no pide Wi-Fi, cuenta online ni telemetría
- **Telemetría deshabilitada** — servicios `DiagTrack` y `dmwappushservice`
  desactivados por política de grupo
- **Cortana deshabilitada** — sin búsqueda en la nube
- **OneDrive eliminado** — binarios removidos del WIM, paquete provisionado
  desinstalado y política de bloqueo aplicada en el primer arranque
- **Copilot deshabilitado** — por política de grupo y botón de barra eliminado

**Rendimiento y UI**
- **Animaciones desactivadas** — sin efectos visuales innecesarios
- **Transparencias desactivadas** — interfaz sólida, menor consumo de GPU
- **Widgets eliminados** — sin panel de noticias ni botón en la barra de tareas
- **Búsqueda de la barra de tareas oculta** — icono eliminado de la taskbar
- **Task View oculto** — botón eliminado de la barra de tareas
- **Menú Inicio alineado a la izquierda** — disposición clásica
- **Sugerencias del menú Inicio desactivadas** — sin apps recomendadas

**Compatibilidad**
- **Bypass de requisitos de hardware** — TPM 2.0, Secure Boot, RAM mínima,
  CPU y almacenamiento ignorados por el instalador (`labconfig.ini`)
- **Instalación desatendida** — `autounattend.xml` generado con nombre de
  equipo, zona horaria y locale configurados

---

## Requisitos

- Linux (cualquier distribución)
- `wimlib` + `xorriso`
- FUSE disponible en el kernel
- Ejecutar como root (`sudo`)
- ~17 GB de espacio libre (3× el tamaño del ISO)

Consulta [requirements.md](requirements.md) para los comandos de instalación
por distribución y más detalles.

---

## Uso

```bash
sudo bash win11-custom.sh --iso /ruta/a/Win11_24H2_x64.iso
```

Con opciones:

```bash
sudo bash win11-custom.sh \
    --iso      /ruta/a/Win11_24H2_x64.iso \
    --output   ~/isos/win11-lite.iso \
    --username "Usuario" \
    --pc-name  "PC-VM" \
    --wim-index 6
```

```
Opciones disponibles:

  --iso        <ruta>    (requerido) ISO original de Windows 11
  --output     <ruta>    Ruta de la ISO generada
  --workdir    <ruta>    Directorio de trabajo temporal
  --wim-index  <n>       Edición a modificar (default: 6 = Pro)
  --username   <nombre>  Usuario local (default: Usuario)
  --password   <clave>   Contraseña    (default: vacía)
  --pc-name    <nombre>  Nombre del equipo (default: PC-Local)
  --locale     <locale>  Locale del sistema (default: es-CL)
  --ui-lang    <lang>    Idioma de la UI   (default: es-MX)
  --timezone   <tz>      Zona horaria      (default: Pacific SA Standard Time)
  --no-cleanup           Conservar el directorio de trabajo al finalizar
  -h, --help             Mostrar ayuda
```

---

## Casos de uso típicos

**Máquina virtual (VirtualBox / VMware / QEMU)**
Sin TPM virtual, sin requisitos de Secure Boot, sin cuenta Microsoft.
Arranca directo al escritorio con el usuario configurado.

**Equipo con hardware antiguo**
Instala en equipos que el instalador oficial rechaza por no cumplir los
requisitos de TPM 2.0 o CPU no soportada.

**Despliegue rápido / laboratorio**
Genera una ISO con usuario, nombre de equipo y locale predefinidos para
tener el sistema listo sin intervención manual.

---

## Flujo del script

```
ISO original
    │
    ▼
Montar ISO (loop, ro) → Copiar contenido
    │
    ▼
Montar install.wim (wimlib, FUSE)
    ├── Eliminar OneDriveSetup.exe (System32 + SysWOW64)
    ├── Escribir no-telemetry.reg  (telemetría, OneDrive, Widgets, Copilot)
    └── Escribir SetupComplete.cmd (desinstalación AppX, tweaks UI, perfil default)
    │
    ▼
Desmontar WIM y guardar cambios
    │
    ├── Escribir sources/labconfig.ini  (bypass hardware)
    └── Escribir autounattend.xml       (instalación desatendida)
    │
    ▼
xorriso → ISO final (BIOS + UEFI)
```

---

## Notas

- El ISO original nunca se modifica; el script trabaja sobre una copia.
- Si el proceso falla, los montajes se deshacen y el workdir se limpia automáticamente.
- Compatible con [Ventoy](https://www.ventoy.net): copia la ISO generada
  directamente al pendrive Ventoy.
