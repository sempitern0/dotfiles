# Linux desktop deployment / Preparación del escritorio Linux

[English README](../README.md) · [README español](../README_ES.md)

## English

Run as the desktop user from a reviewed checkout. Bash 4.3+ is required. Use
`bash bash_setup.sh --plan` to inspect package groups without refreshing metadata,
creating backups or installing anything. Then choose:

| Profile | Use |
|---|---|
| `--user-only` | Existing tools, offline configuration, immutable hosts; no package operations |
| `--minimal` | Core distribution packages and managed shell/Git/SSH/commands |
| `--recommended` | Development and diagnostics; clipboard helpers when a desktop is detected |
| `--desktop` | Recommended plus XDG utilities, MIME integration tools and Noto fonts |
| `--full` | Recommended plus pluginless Vim configuration |
| `--status` | Read-only inventory; optional missing tools do not make it fail |

`--desktop` requires a detected graphical host, not a container. It installs helpers;
it does not install a window manager, replace the desktop, change default apps,
configure GPU drivers, enable services or run `xdg-user-dirs-update`. Wayland/X11
clipboard packages are both available; applications still need the correct session
socket/display. A remote SSH shell may not detect an existing graphical session;
run from the desktop terminal. WSL and containers can use `--user-only`; packages
may work in a mutable distribution, but host integration is outside this installer.

### Compatibility and failure handling

| Environment | Behavior / acceptance boundary |
|---|---|
| Debian/Ubuntu derivatives with APT | Official configured repositories; unavailable optional packages are listed |
| Arch derivatives with pacman | Never runs `pacman -Sy`; keep the host fully upgraded before adding packages |
| Fedora/RHEL derivatives with DNF | No automatic COPR/EPEL enablement; optional tools may be absent |
| openSUSE/SLES with Zypper | Uses configured repositories; Tumbleweed upgrade is an explicit separate choice |
| OSTree, NixOS, transactional-update hosts | Package provider disabled; deploy user files with `--user-only` |
| Other Linux distributions | User configuration remains usable with preinstalled dependencies; no package provider |
| No systemd / no graphical session | Shell configuration works; desktop and service policy have separate requirements |

A successful syntax/regression check does not certify installation on all these
systems. Native package, graphical-session and reboot/recovery acceptance must be
performed on disposable target machines. This project does not promise universal
compatibility. Package manager availability is checked before loading a provider.
No automatic package-lock deletion, repository repair or forced package replacement
is attempted. Package operations can prompt through sudo and have no imposed
transaction timeout. All-installed package groups avoid metadata refresh; otherwise
a failed refresh stops the group. Missing optional packages are shown as SKIP.

Profiles attempt remaining tasks after a failure, record FAIL in the summary, and
exit **1** if any task failed. Exit **2** denotes invalid arguments or a missing
interactive terminal. Read `results.tsv` before considering a partially completed
profile successful. Failure to create the evidence directory prevents profile execution.
Backups remain in the path shown by the assistant. User configuration and system
hardening use separate snapshots. A failed hardening copy is never marked complete.

SSH defaults are appended inside a marked `Host *` block, preserving earlier
personal settings. Reapplying migrates the previous exact generated top-level
Include. If you customized that Include, review it manually. Do not edit the marked
block; use personal rules before it. Older Git/OpenSSH versions can reject newer
configuration options: inspect local `git --version`, `ssh -V`, and `ssh -G HOST`
before deployment. Identity, private keys, VPN and corporate DNS stay personal.

References: [OpenSSH first-value configuration rules](https://man.openbsd.org/ssh_config),
[Arch full-upgrade policy](https://wiki.archlinux.org/title/System_maintenance#Partial_upgrades_are_unsupported).

## Español

Ejecuta desde una copia revisada como usuario del escritorio. Se necesita Bash 4.3+.
`bash bash_setup.sh --plan` muestra los grupos de paquetes sin actualizar metadatos,
crear copias ni instalar nada.

| Perfil | Uso |
|---|---|
| `--user-only` | Configuración sin instalar paquetes: equipos preparados, offline o inmutables |
| `--minimal` | Paquetes básicos y configuración de shell/Git/SSH/comandos |
| `--recommended` | Desarrollo y diagnóstico; portapapeles si detecta escritorio |
| `--desktop` | Recommended más herramientas XDG/MIME y fuentes Noto |
| `--full` | Recommended más configuración de Vim sin plugins |
| `--status` | Inventario de solo lectura; las herramientas opcionales ausentes no provocan fallo |

`--desktop` requiere un equipo con entorno gráfico detectado y rechaza contenedores.
Instala utilidades; no instala un gestor de ventanas, sustituye el escritorio,
cambia aplicaciones predeterminadas, configura drivers, activa servicios ni ejecuta
`xdg-user-dirs-update`. Se ofrecen herramientas para Wayland y X11; cada aplicación
necesita su sesión gráfica. SSH puede no detectar el escritorio: utiliza su terminal.
En WSL y contenedores puedes usar `--user-only`; la integración con el host queda
fuera del instalador.

### Compatibilidad y errores

| Entorno | Comportamiento y límites |
|---|---|
| Debian/Ubuntu y derivados APT | Repositorios configurados; informa de paquetes opcionales ausentes |
| Arch y derivados pacman | Nunca ejecuta `pacman -Sy`; actualiza completamente el equipo antes de añadir paquetes |
| Fedora/RHEL y derivados DNF | No activa COPR/EPEL; algunas herramientas pueden faltar |
| openSUSE/SLES Zypper | Repositorios configurados; actualizar Tumbleweed es una decisión separada |
| OSTree, NixOS o transactional-update | Paquetes deshabilitados; usa `--user-only` para archivos del usuario |
| Otras distribuciones Linux | Configuración con dependencias ya instaladas; sin proveedor de paquetes |
| Sin systemd o sin sesión gráfica | La shell funciona; el escritorio y las políticas de servicios tienen requisitos propios |

Las pruebas de sintaxis y regresión no certifican instalaciones en todos estos
entornos. Valida paquetes, sesión gráfica, reinicio y recuperación en máquinas
desechables de destino. No se promete compatibilidad universal. Se comprueba el
gestor antes de cargar su proveedor. Nunca se borran bloqueos del gestor ni se
fuerzan reparaciones de repositorios. Las transacciones no tienen un timeout
impuesto y sudo puede solicitar credenciales. Si todo el grupo está instalado, no
actualiza metadatos; en otro caso un fallo al actualizarlos detiene ese grupo.
Los paquetes opcionales ausentes aparecen como SKIP.

Los perfiles continúan las tareas restantes, registran FAIL y devuelven **1** si
alguna falla. **2** indica argumentos inválidos o falta de terminal interactivo.
Consulta `results.tsv` antes de dar por terminado un despliegue parcial. Si no puede
crear evidencias, no ejecuta el perfil. Las copias de usuario y las del hardening
son independientes. Una copia de hardening fallida nunca se marca como completada.

Los valores SSH se añaden en un bloque marcado `Host *`, después de las reglas
personales. Se migra el Include exacto generado por la versión anterior; si lo
modificaste, revísalo manualmente. Mantén tus reglas fuera y antes del bloque.
Versiones antiguas de Git/OpenSSH pueden rechazar opciones nuevas: revisa
`git --version`, `ssh -V` y `ssh -G HOST`. Identidad, claves, VPN y DNS corporativo
siguen siendo configuración personal.

Referencias: [reglas de prioridad SSH](https://man.openbsd.org/ssh_config),
[actualización completa en Arch](https://wiki.archlinux.org/title/System_maintenance#Partial_upgrades_are_unsupported).

## Recovery acceptance / Aceptación de recuperación

Recovery verifies existing regular-file checksums and checks payload availability
before changing any paths. An interrupted snapshot without hashes produces an
integrity warning and still requires literal RESTORE confirmation. File/directory
payloads are staged before replacement; a failed rename attempts local rollback.
A failed rollback retains the previous path in staging and reports its location.
Network/service/kernel failures produce nonzero status. Recovery is per-path;
an error on a later path does not undo earlier successful restorations.

La recuperación verifica los hashes existentes de archivos regulares y la presencia
de los datos antes de cambiar rutas. Un snapshot interrumpido sin hashes muestra
un aviso y exige escribir RESTORE. Prepara copias antes de sustituir archivos o
directorios; si falla el cambio de nombre, intenta recuperar el destino anterior.
Si ese rollback falla, conserva el destino anterior en staging e indica la ubicación.
Los fallos de red/servicios/kernel devuelven error. La recuperación actúa por ruta:
un fallo posterior no revierte las rutas ya restauradas.
