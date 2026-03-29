#!/usr/bin/env bash
# =============================================================================
# win11-custom.sh — Modificador de ISO Windows 11 (genérico, multi-distro)
# Genera una ISO con: cuenta local, sin telemetría, sin Cortana, sin OneDrive,
# bypass TPM/SecureBoot/RAM e instalación desatendida.
#
# Uso:
#   sudo bash win11-custom.sh --iso /ruta/a/windows11.iso [opciones]
#
# Opciones:
#   --iso        <ruta>   (requerido) Ruta al ISO original de Windows 11
#   --output     <ruta>   ISO de salida (default: <directorio_iso_origen>/windows-custom.iso)
#   --workdir    <ruta>   Directorio de trabajo temporal (default: /tmp/win11mod-$$)
#   --wim-index  <n>      Índice de imagen en install.wim (default: 6 → Pro)
#   --username   <nombre> Nombre de usuario local (default: Usuario)
#   --password   <clave>  Contraseña del usuario  (default: vacía)
#   --pc-name    <nombre> Nombre del equipo       (default: PC-Local)
#   --locale     <locale> Locale del sistema      (default: es-CL)
#   --ui-lang    <lang>   Idioma de la interfaz   (default: es-MX)
#   --timezone   <tz>     Zona horaria Windows    (default: Pacific SA Standard Time)
#   --no-cleanup          No eliminar el workdir al finalizar
#   -h, --help            Mostrar esta ayuda
# =============================================================================

set -euo pipefail

# ─── COLORES ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

log()  { echo -e "${GREEN}[✓]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✗]${NC} $*" >&2; exit 1; }
info() { echo -e "${CYAN}[→]${NC} $*"; }
step() {
    echo -e "\n${BOLD}════════════════════════════════════════${NC}"
    echo -e "${BOLD} $*${NC}"
    echo -e "${BOLD}════════════════════════════════════════${NC}"
}

# ─── VALORES POR DEFECTO ──────────────────────────────────────────────────────
ISO_ORIGEN=""
ISO_DESTINO=""
DIR_BASE=""
WIM_INDEX=6
NOMBRE_USUARIO="Usuario"
PASSWORD_USUARIO=""
NOMBRE_PC="PC-Local"
LOCALE="es-CL"
UI_LANG="es-MX"
TIMEZONE="Pacific SA Standard Time"
DO_CLEANUP=true
WORKDIR_CUSTOM=false

# ─── AYUDA ────────────────────────────────────────────────────────────────────
usage() {
    cat << 'EOF'
Uso: sudo bash win11-custom.sh --iso /ruta/a/windows11.iso [opciones]

Opciones obligatorias:
  --iso <ruta>          Ruta al ISO original de Windows 11

Opciones de rutas:
  --output <ruta>       ISO de salida generada
                        (default: mismo directorio del ISO origen)
  --workdir <ruta>      Directorio de trabajo temporal
                        (default: /tmp/win11mod-PID)

Opciones de imagen WIM:
  --wim-index <n>       Índice de imagen en install.wim
                        Índices típicos: 1=Home, 3=Pro N, 6=Pro, 7=Pro WS
                        (default: 6)

Opciones de cuenta de usuario:
  --username <nombre>   Nombre de usuario local (default: Usuario)
  --password <clave>    Contraseña del usuario  (default: vacía)
  --pc-name  <nombre>   Nombre del equipo       (default: PC-Local)

Opciones de regionalización:
  --locale   <locale>   Locale del sistema Windows (default: es-CL)
  --ui-lang  <lang>     Idioma de la interfaz UI   (default: es-MX)
  --timezone <tz>       Zona horaria Windows
                        (default: "Pacific SA Standard Time")

Otras opciones:
  --no-cleanup          Conservar el directorio de trabajo al finalizar
  -h, --help            Mostrar esta ayuda

Ejemplos:
  sudo bash win11-custom.sh --iso ~/Descargas/Win11_24H2_x64.iso
  sudo bash win11-custom.sh \
      --iso ~/Win11.iso \
      --output ~/isos/win11-custom.iso \
      --username "Juan" \
      --pc-name "PC-JUAN" \
      --wim-index 6
EOF
    exit 0
}

# ─── PARSEO DE ARGUMENTOS ─────────────────────────────────────────────────────
[[ $# -eq 0 ]] && { usage; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --iso)        ISO_ORIGEN="$2";       shift 2 ;;
        --output)     ISO_DESTINO="$2";      shift 2 ;;
        --workdir)    DIR_BASE="$2"; WORKDIR_CUSTOM=true; shift 2 ;;
        --wim-index)  WIM_INDEX="$2";        shift 2 ;;
        --username)   NOMBRE_USUARIO="$2";   shift 2 ;;
        --password)   PASSWORD_USUARIO="$2"; shift 2 ;;
        --pc-name)    NOMBRE_PC="$2";        shift 2 ;;
        --locale)     LOCALE="$2";           shift 2 ;;
        --ui-lang)    UI_LANG="$2";          shift 2 ;;
        --timezone)   TIMEZONE="$2";         shift 2 ;;
        --no-cleanup) DO_CLEANUP=false;      shift ;;
        -h|--help)    usage ;;
        *)            err "Argumento desconocido: $1\n  Usa --help para ver las opciones disponibles." ;;
    esac
done

# ─── DETECTAR GESTOR DE PAQUETES ──────────────────────────────────────────────
detect_pkg_manager() {
    if   command -v pacman  &>/dev/null; then echo "pacman"
    elif command -v apt-get &>/dev/null; then echo "apt"
    elif command -v dnf     &>/dev/null; then echo "dnf"
    elif command -v zypper  &>/dev/null; then echo "zypper"
    elif command -v yum     &>/dev/null; then echo "yum"
    elif command -v emerge  &>/dev/null; then echo "emerge"
    else echo "unknown"
    fi
}

install_hint() {
    local pkg_manager
    pkg_manager=$(detect_pkg_manager)
    case "$pkg_manager" in
        pacman)  echo "sudo pacman -S wimlib xorriso" ;;
        apt)     echo "sudo apt-get install -y wimtools xorriso" ;;
        dnf)     echo "sudo dnf install -y wimlib xorriso" ;;
        zypper)  echo "sudo zypper install wimlib xorriso" ;;
        yum)     echo "sudo yum install wimlib xorriso" ;;
        emerge)  echo "sudo emerge app-arch/wimlib dev-libs/xorriso" ;;
        *)       echo "(instala wimlib y xorriso con tu gestor de paquetes)" ;;
    esac
}

# ─── LIMPIEZA AL SALIR ────────────────────────────────────────────────────────
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        echo -e "\n${RED}[✗]${NC} El script terminó con error (código $exit_code)"
    fi

    # Desmontar WIM si quedó montado
    if mountpoint -q "${DIR_WIM_MOUNT:-}" 2>/dev/null; then
        warn "Desmontando WIM (sin guardar cambios)..."
        wimlib-imagex unmount "${DIR_WIM_MOUNT}" 2>/dev/null || true
    fi

    # Desmontar ISO si quedó montada
    if mountpoint -q "${DIR_ISO_ORIG:-}" 2>/dev/null; then
        warn "Desmontando ISO temporal..."
        umount "${DIR_ISO_ORIG}" 2>/dev/null || true
    fi

    # Limpiar directorio de trabajo si aplica
    if [[ "$DO_CLEANUP" == true && -n "${DIR_BASE:-}" && -d "${DIR_BASE}" ]]; then
        if [[ "$WORKDIR_CUSTOM" == false ]]; then
            info "Eliminando directorio de trabajo temporal: ${DIR_BASE}"
            rm -rf "${DIR_BASE}"
        else
            warn "Workdir personalizado conservado: ${DIR_BASE}"
        fi
    fi
}
trap cleanup EXIT

# ─── PASO 0 — VERIFICACIONES INICIALES ───────────────────────────────────────
step "PASO 0 — Verificaciones previas"

# Verificar root
[[ "$EUID" -ne 0 ]] && err "Este script requiere privilegios de root.\n  Ejecuta: sudo bash $0 --iso <ruta_iso>"

# Verificar argumento obligatorio
[[ -z "$ISO_ORIGEN" ]] && err "Debes indicar la ruta del ISO con --iso\n  Ejemplo: sudo bash $0 --iso /ruta/windows11.iso"

# Resolver path absoluto del ISO
ISO_ORIGEN=$(realpath "$ISO_ORIGEN" 2>/dev/null) || err "No se puede resolver la ruta del ISO: $ISO_ORIGEN"

# Verificar que el ISO existe y es un archivo regular
[[ ! -f "$ISO_ORIGEN" ]] && err "ISO no encontrada en: $ISO_ORIGEN"

# Verificar que el archivo parece un ISO (magic bytes)
FILE_TYPE=$(file -b "$ISO_ORIGEN" 2>/dev/null | head -1)
if ! echo "$FILE_TYPE" | grep -qiE "ISO 9660|UDF|CD-ROM"; then
    warn "El archivo no parece un ISO estándar: $FILE_TYPE"
    warn "Continuando de todas formas..."
fi

# Verificar dependencias
MISSING_DEPS=()
for cmd in wimlib-imagex xorriso mount umount file du df realpath; do
    command -v "$cmd" &>/dev/null || MISSING_DEPS+=("$cmd")
done

if [[ ${#MISSING_DEPS[@]} -gt 0 ]]; then
    echo -e "${RED}[✗]${NC} Dependencias faltantes: ${MISSING_DEPS[*]}"
    echo -e ""
    echo -e "  Instala los paquetes necesarios:"
    echo -e "  ${CYAN}$(install_hint)${NC}"
    echo -e ""
    echo -e "  Consulta requirements.md para más detalles por distro."
    exit 1
fi

# Verificar que fuse está disponible (necesario para wimlib mountrw)
if ! grep -q fuse /proc/filesystems 2>/dev/null && ! modinfo fuse &>/dev/null 2>&1; then
    warn "El módulo FUSE puede no estar disponible. wimlib mount requiere FUSE."
    warn "Si el montaje falla, ejecuta: sudo modprobe fuse"
fi

log "Dependencias OK"
log "ISO origen: $ISO_ORIGEN"

# ─── CONFIGURAR RUTAS ─────────────────────────────────────────────────────────
ISO_ORIGEN_DIR=$(dirname "$ISO_ORIGEN")

# Workdir: /tmp/win11mod-PID si no se especificó
if [[ -z "$DIR_BASE" ]]; then
    DIR_BASE="/tmp/win11mod-$$"
fi

# ISO destino: mismo directorio del ISO origen
if [[ -z "$ISO_DESTINO" ]]; then
    ISO_DESTINO="${ISO_ORIGEN_DIR}/windows-custom.iso"
fi

DIR_ISO_ORIG="${DIR_BASE}/iso-orig"
DIR_ISO_MOD="${DIR_BASE}/iso-mod"
DIR_WIM_MOUNT="${DIR_BASE}/wim-mount"

# Verificar que el directorio padre del ISO destino existe y es escribible
ISO_DESTINO_DIR=$(dirname "$ISO_DESTINO")
[[ ! -d "$ISO_DESTINO_DIR" ]] && err "El directorio de salida no existe: $ISO_DESTINO_DIR"
[[ ! -w "$ISO_DESTINO_DIR" ]] && err "Sin permisos de escritura en: $ISO_DESTINO_DIR"

# ─── VERIFICAR ESPACIO EN DISCO ───────────────────────────────────────────────
ISO_SIZE_BYTES=$(stat -c%s "$ISO_ORIGEN" 2>/dev/null || stat -f%z "$ISO_ORIGEN")
ISO_SIZE_GB=$(( ISO_SIZE_BYTES / 1024 / 1024 / 1024 ))
REQUIRED_GB=$(( ISO_SIZE_GB * 3 + 2 ))   # ~3x el ISO + margen

WORKDIR_FS=$(df -BG "$DIR_BASE" 2>/dev/null | tail -1 | awk '{print $4}' | tr -d 'G' || echo 0)
# Si DIR_BASE no existe aún, verificar el parent
if [[ ! -d "$DIR_BASE" ]]; then
    PARENT_DIR=$(dirname "$DIR_BASE")
    [[ ! -d "$PARENT_DIR" ]] && PARENT_DIR="/"
    WORKDIR_FS=$(df -BG "$PARENT_DIR" 2>/dev/null | tail -1 | awk '{print $4}' | tr -d 'G' || echo 0)
fi

if [[ -n "$WORKDIR_FS" && "$WORKDIR_FS" -gt 0 ]] 2>/dev/null; then
    if [[ "$WORKDIR_FS" -lt "$REQUIRED_GB" ]]; then
        err "Espacio insuficiente en $(dirname "$DIR_BASE"): ${WORKDIR_FS}GB disponibles, se requieren ~${REQUIRED_GB}GB\n  Usa --workdir para apuntar a una partición con más espacio."
    fi
    log "Espacio en disco OK (${WORKDIR_FS}GB disponibles, se usarán ~${REQUIRED_GB}GB)"
fi

# Validar WIM_INDEX como número
if ! [[ "$WIM_INDEX" =~ ^[0-9]+$ ]] || [[ "$WIM_INDEX" -lt 1 ]]; then
    err "--wim-index debe ser un número entero positivo (recibido: '$WIM_INDEX')"
fi

# Mostrar configuración
echo -e ""
echo -e "  ${CYAN}ISO origen  :${NC} $ISO_ORIGEN"
echo -e "  ${CYAN}ISO destino :${NC} $ISO_DESTINO"
echo -e "  ${CYAN}Workdir     :${NC} $DIR_BASE"
echo -e "  ${CYAN}WIM índice  :${NC} $WIM_INDEX"
echo -e "  ${CYAN}Usuario     :${NC} $NOMBRE_USUARIO"
echo -e "  ${CYAN}PC nombre   :${NC} $NOMBRE_PC"
echo -e "  ${CYAN}Locale      :${NC} $LOCALE / $UI_LANG"
echo -e "  ${CYAN}Timezone    :${NC} $TIMEZONE"
echo -e ""

# ─── PASO 1 — LIMPIEZA Y PREPARACIÓN ─────────────────────────────────────────
step "PASO 1 — Preparación de directorios de trabajo"

# Desmontar WIM si quedó de ejecución anterior
if mountpoint -q "$DIR_WIM_MOUNT" 2>/dev/null; then
    warn "WIM anterior aún montado — desmontando..."
    wimlib-imagex unmount "$DIR_WIM_MOUNT" 2>/dev/null || true
    sleep 1
fi

# Desmontar ISO si quedó montada
if mountpoint -q "$DIR_ISO_ORIG" 2>/dev/null; then
    warn "ISO anterior aún montada — desmontando..."
    umount "$DIR_ISO_ORIG" 2>/dev/null || true
    sleep 1
fi

# Limpiar y recrear directorios
rm -rf "$DIR_ISO_ORIG" "$DIR_ISO_MOD" "$DIR_WIM_MOUNT"
mkdir -p "$DIR_ISO_ORIG" "$DIR_ISO_MOD" "$DIR_WIM_MOUNT"

# Eliminar ISO destino anterior si existe
if [[ -f "$ISO_DESTINO" ]]; then
    warn "ISO de salida anterior encontrada — eliminando: $ISO_DESTINO"
    rm -f "$ISO_DESTINO"
fi

log "Directorios listos: $DIR_BASE"

# ─── PASO 2 — MONTAR ISO Y COPIAR CONTENIDO ──────────────────────────────────
step "PASO 2 — Montar ISO y copiar contenido"

info "Montando ISO (solo lectura)..."
mount -o loop,ro "$ISO_ORIGEN" "$DIR_ISO_ORIG" || err "No se pudo montar la ISO. Verifica que el archivo sea válido y que tengas permisos."

# Verificar estructura mínima esperada de un ISO de Windows
for path_check in "sources" "boot"; do
    if [[ ! -d "${DIR_ISO_ORIG}/${path_check}" ]]; then
        umount "$DIR_ISO_ORIG" 2>/dev/null || true
        err "El ISO no parece ser de Windows 11: falta la carpeta '${path_check}'"
    fi
done

# Verificar que existe install.wim o install.esd
if [[ ! -f "${DIR_ISO_ORIG}/sources/install.wim" && ! -f "${DIR_ISO_ORIG}/sources/install.esd" ]]; then
    umount "$DIR_ISO_ORIG" 2>/dev/null || true
    err "No se encontró sources/install.wim ni sources/install.esd en el ISO.\n  Este script solo soporta ISOs con install.wim (no install.esd)."
fi

if [[ ! -f "${DIR_ISO_ORIG}/sources/install.wim" ]]; then
    umount "$DIR_ISO_ORIG" 2>/dev/null || true
    err "Se encontró install.esd pero este script requiere install.wim.\n  Convierte el ESD a WIM antes de continuar:\n  wimlib-imagex export sources/install.esd <índice> sources/install.wim"
fi

info "Copiando contenido del ISO al directorio de trabajo (puede tardar varios minutos)..."
cp -r "${DIR_ISO_ORIG}/." "${DIR_ISO_MOD}/"
chmod -R u+w "${DIR_ISO_MOD}/"
umount "$DIR_ISO_ORIG"

log "Contenido copiado correctamente"

# ─── PASO 3 — VERIFICAR ÍNDICES WIM ──────────────────────────────────────────
step "PASO 3 — Ediciones disponibles en el WIM"

WIM_FILE="${DIR_ISO_MOD}/sources/install.wim"

info "Índices disponibles en install.wim:"
wimlib-imagex info "$WIM_FILE" | grep -E "^(Index|Name|Description):" || true
echo -e ""

# Validar que el índice solicitado existe
MAX_INDEX=$(wimlib-imagex info "$WIM_FILE" | grep "^Image Count:" | awk '{print $3}')
if [[ -n "$MAX_INDEX" && "$WIM_INDEX" -gt "$MAX_INDEX" ]]; then
    err "El índice ${WIM_INDEX} no existe en este WIM (máximo: ${MAX_INDEX}).\n  Usa --wim-index con un valor entre 1 y ${MAX_INDEX}."
fi

log "Usando índice WIM: ${WIM_INDEX}"

# ─── PASO 4 — MONTAR WIM EN MODO ESCRITURA ───────────────────────────────────
step "PASO 4 — Montar WIM en modo escritura"

info "Montando install.wim (índice ${WIM_INDEX})..."
wimlib-imagex mountrw "$WIM_FILE" "$WIM_INDEX" "$DIR_WIM_MOUNT" \
    || err "No se pudo montar el WIM. Verifica que FUSE esté disponible:\n  sudo modprobe fuse"

log "WIM montado en ${DIR_WIM_MOUNT}"

# ─── PASO 5 — MODIFICACIONES DENTRO DEL WIM ──────────────────────────────────
step "PASO 5 — Aplicar modificaciones al WIM"

mkdir -p "${DIR_WIM_MOUNT}/Windows/Setup/Scripts"

## 5a — Eliminar OneDrive
info "Eliminando instaladores de OneDrive..."
if rm -f "${DIR_WIM_MOUNT}/Windows/System32/OneDriveSetup.exe" 2>/dev/null; then
    log "OneDrive System32 eliminado"
else
    warn "OneDriveSetup.exe en System32 no encontrado (puede ser normal)"
fi
if rm -f "${DIR_WIM_MOUNT}/Windows/SysWOW64/OneDriveSetup.exe" 2>/dev/null; then
    log "OneDrive SysWOW64 eliminado"
else
    warn "OneDriveSetup.exe en SysWOW64 no encontrado (puede ser normal)"
fi

## 5b — Registro: deshabilitar telemetría, Cortana, OneDrive
info "Creando archivo de registro anti-telemetría..."
cat > "${DIR_WIM_MOUNT}/Windows/Setup/Scripts/no-telemetry.reg" << 'REGEOF'
Windows Registry Editor Version 5.00

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\DataCollection]
"AllowTelemetry"=dword:00000000
"DoNotShowFeedbackNotifications"=dword:00000001

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection]
"AllowTelemetry"=dword:00000000

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\DiagTrack]
"Start"=dword:00000004

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\dmwappushservice]
"Start"=dword:00000004

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\Windows Search]
"AllowCortana"=dword:00000000

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\OneDrive]
"DisableFileSyncNGSC"=dword:00000001
"DisableLibrariesDefaultSaveToOneDrive"=dword:00000001

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo]
"DisabledByGroupPolicy"=dword:00000001

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows NT\CurrentVersion\Software Protection Platform]
"NoGenTicket"=dword:00000001
REGEOF

log "Archivo .reg creado"

## 5c — SetupComplete.cmd
info "Creando SetupComplete.cmd..."
cat > "${DIR_WIM_MOUNT}/Windows/Setup/Scripts/SetupComplete.cmd" << 'CMDEOF'
@echo off

:: Aplicar registro de telemetría/privacidad
regedit /s C:\Windows\Setup\Scripts\no-telemetry.reg

:: Deshabilitar servicios de telemetría
sc config DiagTrack start= disabled
sc stop DiagTrack
sc config dmwappushservice start= disabled
sc stop dmwappushservice

:: Deshabilitar búsqueda de Cortana
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search" /v AllowCortana /t REG_DWORD /d 0 /f

:: Deshabilitar OneDrive
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\OneDrive" /v DisableFileSyncNGSC /t REG_DWORD /d 1 /f

:: Desinstalar OneDrive si se instaló igual
%SystemRoot%\System32\OneDriveSetup.exe /uninstall 2>nul
%SystemRoot%\SysWOW64\OneDriveSetup.exe /uninstall 2>nul

:: Deshabilitar telemetría vía GPO
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" /v AllowTelemetry /t REG_DWORD /d 0 /f

:: Deshabilitar publicidad personalizada
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo" /v DisabledByGroupPolicy /t REG_DWORD /d 1 /f

echo [win11-custom] SetupComplete finalizado >> C:\Windows\Temp\setup-custom.log
CMDEOF

log "SetupComplete.cmd creado"

# ─── PASO 6 — GUARDAR CAMBIOS EN WIM ─────────────────────────────────────────
step "PASO 6 — Guardar cambios en WIM"

info "Desmontando y confirmando cambios (puede tardar varios minutos)..."
wimlib-imagex unmount "$DIR_WIM_MOUNT" --commit \
    || err "Error al guardar cambios en el WIM."

log "WIM actualizado correctamente"

# ─── PASO 7 — BYPASS TPM / SECUREBOOT / RAM ──────────────────────────────────
step "PASO 7 — Crear labconfig.ini (bypass de requisitos de hardware)"

cat > "${DIR_ISO_MOD}/sources/labconfig.ini" << 'LABEOF'
[LabConfig]
BypassTPMCheck=1
BypassSecureBootCheck=1
BypassRAMCheck=1
BypassStorageCheck=1
BypassCPUCheck=1
LABEOF

log "labconfig.ini creado — instalador ignorará TPM, SecureBoot, RAM, CPU y almacenamiento"

# ─── PASO 8 — CREAR autounattend.xml ─────────────────────────────────────────
step "PASO 8 — Crear autounattend.xml (instalación desatendida)"

info "Generando autounattend.xml..."
cat > "${DIR_ISO_MOD}/autounattend.xml" << XMLEOF
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">

  <!-- ═══ FASE windowsPE: idioma del instalador ═══ -->
  <settings pass="windowsPE">
    <component name="Microsoft-Windows-International-Core-WinPE"
               processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35"
               language="neutral" versionScope="nonSxS"
               xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
      <SetupUILanguage>
        <UILanguage>${UI_LANG}</UILanguage>
      </SetupUILanguage>
      <InputLocale>${LOCALE}</InputLocale>
      <SystemLocale>${LOCALE}</SystemLocale>
      <UILanguage>${UI_LANG}</UILanguage>
      <UserLocale>${LOCALE}</UserLocale>
    </component>

    <component name="Microsoft-Windows-Setup"
               processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35"
               language="neutral" versionScope="nonSxS"
               xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
      <UserData>
        <AcceptEula>true</AcceptEula>
      </UserData>
    </component>
  </settings>

  <!-- ═══ FASE specialize: nombre de equipo y zona horaria ═══ -->
  <settings pass="specialize">
    <component name="Microsoft-Windows-Shell-Setup"
               processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35"
               language="neutral" versionScope="nonSxS"
               xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
      <ComputerName>${NOMBRE_PC}</ComputerName>
      <TimeZone>${TIMEZONE}</TimeZone>
    </component>

    <component name="Microsoft-Windows-International-Core"
               processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35"
               language="neutral" versionScope="nonSxS"
               xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
      <InputLocale>${LOCALE}</InputLocale>
      <SystemLocale>${LOCALE}</SystemLocale>
      <UILanguage>${UI_LANG}</UILanguage>
      <UserLocale>${LOCALE}</UserLocale>
    </component>
  </settings>

  <!-- ═══ FASE oobeSystem: cuenta local, sin OOBE de Microsoft ═══ -->
  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-Shell-Setup"
               processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35"
               language="neutral" versionScope="nonSxS"
               xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">

      <UserAccounts>
        <LocalAccounts>
          <LocalAccount wcm:action="add">
            <Name>${NOMBRE_USUARIO}</Name>
            <Group>Administrators</Group>
            <Password>
              <Value>${PASSWORD_USUARIO}</Value>
              <PlainText>true</PlainText>
            </Password>
          </LocalAccount>
        </LocalAccounts>
      </UserAccounts>

      <OOBE>
        <HideEULAPage>true</HideEULAPage>
        <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>
        <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
        <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
        <NetworkLocation>Home</NetworkLocation>
        <SkipMachineOOBE>true</SkipMachineOOBE>
        <SkipUserOOBE>true</SkipUserOOBE>
        <ProtectYourPC>3</ProtectYourPC>
      </OOBE>

      <TimeZone>${TIMEZONE}</TimeZone>

    </component>

    <component name="Microsoft-Windows-International-Core"
               processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35"
               language="neutral" versionScope="nonSxS"
               xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
      <InputLocale>${LOCALE}</InputLocale>
      <SystemLocale>${LOCALE}</SystemLocale>
      <UILanguage>${UI_LANG}</UILanguage>
      <UserLocale>${LOCALE}</UserLocale>
    </component>
  </settings>

</unattend>
XMLEOF

log "autounattend.xml generado"

# ─── PASO 9 — VERIFICAR ARCHIVOS DE BOOT ─────────────────────────────────────
step "PASO 9 — Verificar archivos de arranque"

BOOT_ETFS="${DIR_ISO_MOD}/boot/etfsboot.com"
BOOT_EFI="${DIR_ISO_MOD}/efi/microsoft/boot/efisys.bin"

[[ ! -f "$BOOT_ETFS" ]] && err "Falta archivo de boot BIOS: boot/etfsboot.com\n  El ISO puede estar corrupto o no ser de Windows."
[[ ! -f "$BOOT_EFI"  ]] && err "Falta archivo de boot EFI: efi/microsoft/boot/efisys.bin\n  El ISO puede estar corrupto o no ser de Windows."

log "Archivos de arranque BIOS y EFI presentes"

# ─── PASO 10 — GENERAR ISO FINAL ─────────────────────────────────────────────
step "PASO 10 — Generar ISO final (puede tardar 5-15 minutos)"

# Verificar espacio en destino
ISO_DEST_DIR=$(dirname "$ISO_DESTINO")
DEST_FREE_GB=$(df -BG "$ISO_DEST_DIR" | tail -1 | awk '{print $4}' | tr -d 'G')
ISO_MOD_GB=$(du -s -BG "$DIR_ISO_MOD" | awk '{print $1}' | tr -d 'G')

if [[ -n "$DEST_FREE_GB" && -n "$ISO_MOD_GB" ]] 2>/dev/null; then
    if [[ "$DEST_FREE_GB" -lt "$ISO_MOD_GB" ]]; then
        err "Espacio insuficiente en $(dirname "$ISO_DESTINO"): ${DEST_FREE_GB}GB disponibles, se necesitan ~${ISO_MOD_GB}GB\n  Usa --output para apuntar a otra ruta."
    fi
fi

info "Ejecutando xorriso..."
xorriso -as mkisofs \
    -iso-level 3 \
    -full-iso9660-filenames \
    -joliet \
    -joliet-long \
    -rational-rock \
    -volid "WIN11_CUSTOM" \
    -eltorito-boot boot/etfsboot.com \
    -eltorito-catalog boot/boot.cat \
    -no-emul-boot \
    -boot-load-size 8 \
    -eltorito-alt-boot \
    -e efi/microsoft/boot/efisys.bin \
    -no-emul-boot \
    -append_partition 2 0xef "${BOOT_EFI}" \
    -o "$ISO_DESTINO" \
    "$DIR_ISO_MOD" \
    || err "xorriso falló al generar la ISO."

# ─── RESULTADO FINAL ──────────────────────────────────────────────────────────
step "COMPLETADO"

ISO_SIZE=$(du -h "$ISO_DESTINO" | cut -f1)
ISO_ORIG_SIZE=$(du -h "$ISO_ORIGEN" | cut -f1)

echo -e ""
log "ISO generada exitosamente"
echo -e "  ${CYAN}Original :${NC} ${ISO_ORIG_SIZE}  →  ${ISO_ORIGEN}"
echo -e "  ${CYAN}Custom   :${NC} ${ISO_SIZE}  →  ${ISO_DESTINO}"
echo -e ""
echo -e "  ${CYAN}Modificaciones aplicadas:${NC}"
echo -e "    • Cuenta local: ${NOMBRE_USUARIO} (grupo Administradores)"
echo -e "    • Nombre de equipo: ${NOMBRE_PC}"
echo -e "    • Telemetría y DiagTrack deshabilitados"
echo -e "    • Cortana deshabilitada"
echo -e "    • OneDrive eliminado/deshabilitado"
echo -e "    • OOBE y EULA omitidos"
echo -e "    • Bypass TPM 2.0, SecureBoot, RAM, CPU, almacenamiento"
echo -e ""
if [[ -z "$PASSWORD_USUARIO" ]]; then
    warn "El usuario '${NOMBRE_USUARIO}' no tiene contraseña. Establece una en el primer login."
else
    warn "Cambia la contraseña de '${NOMBRE_USUARIO}' en el primer login."
fi
echo -e ""
info "Para usar con Ventoy, copia la ISO al directorio de Ventoy:"
echo -e "  cp \"${ISO_DESTINO}\" /ruta/a/ventoy/"
echo -e ""
