# Requisitos — win11-custom.sh

## Dependencias del sistema

| Paquete      | Propósito                                          |
|--------------|----------------------------------------------------|
| `wimlib`     | Montar y modificar archivos WIM (install.wim)      |
| `xorriso`    | Generar la ISO final booteable (BIOS + UEFI)       |
| `fuse`       | Sistema de archivos en espacio de usuario (para wimlib mountrw) |
| `coreutils`  | `du`, `df`, `realpath`, `stat`, `cp`, `rm`, `mkdir` |
| `util-linux` | `mount`, `umount`, `mountpoint`                    |
| `file`       | Detectar tipo de archivo del ISO                   |

---

## Instalación por distribución

### Arch Linux / Manjaro
```bash
sudo pacman -S wimlib xorriso
```

### Ubuntu / Debian / Linux Mint / Pop!_OS
```bash
sudo apt-get update
sudo apt-get install -y wimtools xorriso
```
> En Ubuntu/Debian el binario se llama `wimlib-imagex` igual que en Arch.

### Fedora / RHEL 9+ / AlmaLinux / Rocky Linux
```bash
sudo dnf install -y wimlib xorriso
```

### openSUSE Leap / Tumbleweed
```bash
sudo zypper install wimlib xorriso
```

### CentOS / RHEL 8 (con EPEL)
```bash
sudo dnf install -y epel-release
sudo dnf install -y wimlib xorriso
```

### Gentoo
```bash
sudo emerge app-arch/wimlib dev-libs/xorriso
```

---

## Requisitos de hardware / entorno

| Recurso       | Mínimo recomendado                                             |
|---------------|----------------------------------------------------------------|
| Espacio disco | ~3× el tamaño del ISO origen + 2 GB de margen                 |
|               | (un ISO de Windows 11 ~5 GB → necesitas ~17 GB libres)        |
| RAM           | 2 GB (el proceso de wimlib puede ser intensivo en memoria)    |
| Kernel        | Linux con soporte FUSE (`modprobe fuse`)                      |
| Permisos      | Debe ejecutarse como **root** (`sudo`)                        |

---

## Verificar que FUSE está disponible

```bash
# Verificar si el módulo está cargado
lsmod | grep fuse

# Cargar si no está
sudo modprobe fuse

# Verificar que el dispositivo existe
ls -la /dev/fuse
```

---

## Uso básico

```bash
# Mínimo (usa todos los valores por defecto)
sudo bash win11-custom.sh --iso /ruta/a/Win11_24H2_x64.iso

# Con usuario y nombre de equipo personalizados
sudo bash win11-custom.sh \
    --iso /ruta/a/Win11_24H2_x64.iso \
    --username "Juan" \
    --pc-name "PC-JUAN" \
    --output ~/isos/win11-personalizado.iso

# Especificar edición Pro N (índice 3) con directorio de trabajo personalizado
sudo bash win11-custom.sh \
    --iso /ruta/a/Win11.iso \
    --wim-index 3 \
    --workdir /mnt/datos/win11-trabajo \
    --no-cleanup
```

---

## Índices WIM típicos de Windows 11

| Índice | Edición               |
|--------|-----------------------|
| 1      | Home                  |
| 2      | Home N                |
| 3      | Home Single Language  |
| 4      | Education             |
| 5      | Education N           |
| 6      | Pro *(recomendado)*   |
| 7      | Pro N                 |
| 8      | Pro for Workstations  |

> Los índices pueden variar según la versión del ISO. El script muestra los índices
> disponibles antes de proceder. Usa `--wim-index` para seleccionar la edición deseada.

---

## Localización

Algunos valores de `--locale` y `--ui-lang` comunes:

| Región         | `--locale` | `--ui-lang` | `--timezone`                   |
|----------------|------------|-------------|--------------------------------|
| Chile          | `es-CL`    | `es-MX`     | `Pacific SA Standard Time`     |
| México         | `es-MX`    | `es-MX`     | `Central Standard Time (Mexico)` |
| Argentina      | `es-AR`    | `es-MX`     | `Argentina Standard Time`      |
| España         | `es-ES`    | `es-ES`     | `Romance Standard Time`        |
| Colombia       | `es-CO`    | `es-MX`     | `SA Pacific Standard Time`     |
| Estados Unidos | `en-US`    | `en-US`     | `Eastern Standard Time`        |

---

## Notas

- El ISO original **no se modifica** en ningún momento; el script trabaja sobre una copia.
- El directorio de trabajo temporal se elimina automáticamente al finalizar (a menos que uses `--no-cleanup`).
- Si el script falla a mitad del proceso, los directorios temporales se desmontan y limpian automáticamente mediante el trap de salida.
- Para ISOs con `install.esd` en lugar de `install.wim` (algunos ISOs de Microsoft), debes convertirlo primero:
  ```bash
  wimlib-imagex export sources/install.esd <índice> sources/install.wim
  ```
