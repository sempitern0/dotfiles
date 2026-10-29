# dotfiles

Prepara tu escritorio Linux personal: Bash/Zsh, Git, cliente SSH, comandos útiles
y Vim opcional. Utiliza paquetes de los repositorios configurados en tu distribución.

[English](README.md) · **Español** · [Referencia completa](docs/REFERENCE.md)

[Perfiles de escritorio, compatibilidad y errores](docs/DESKTOP.md#español) · [Validación](docs/MAINTENANCE.md)

## Primer uso

Requisitos: Linux, Bash 4.3+, Git y una cuenta existente. Familias compatibles:
APT, pacman, DNF y Zypper. Ejecuta desde tu usuario; los paquetes solicitan `sudo`
cuando corresponde.

```bash
git clone https://github.com/sempitern0/dotfiles.git
cd dotfiles
./bash_setup.sh --plan
./bash_setup.sh --status
./bash_setup.sh --desktop     # desde la terminal del escritorio gráfico
```

Abre una terminal nueva al terminar. Para elegir módulos, usa `./bash_setup.sh`.
Bash recibe los archivos gestionados tras respaldar los existentes; Zsh conserva
su `.zshrc` y añade una línea de carga de la configuración compartida.

## Elige qué aplicar

| Comando | Alcance |
|---|---|
| `./bash_setup.sh --plan` | Ver grupos de paquetes y despliegue sin cambios |
| `./bash_setup.sh --user-only` | Desplegar archivos con herramientas existentes, sin instalar paquetes |
| `./bash_setup.sh --desktop` | Recommended más utilidades XDG/MIME y fuentes en equipos gráficos |
| `./bash_setup.sh --status` | Diagnóstico sin instalación |
| `./bash_setup.sh --minimal` | Paquetes básicos, shell, Git/SSH y utilidades |
| `./bash_setup.sh --recommended` | Lo anterior + desarrollo, diagnóstico y productividad |
| `./bash_setup.sh --full` | Perfil completo, incluido Vim sin plugins |
| `./bash_setup.sh --user alice --recommended` | Seleccionar explícitamente la cuenta destino |
| `sudo ./hardening_setup.sh --audit` | Revisar la postura de seguridad |
| `sudo ./hardening_setup.sh --recommended` | Aplicar el baseline de hardening por separado |

El perfil de escritorio conserva tu entorno gráfico, aplicaciones predeterminadas y drivers.
En sistemas inmutables/transaccionales usa `--user-only` y el gestor nativo del sistema.
Los perfiles continúan tras un fallo, lo muestran y devuelven código de salida 1.

Vim y hardening son decisiones independientes. El hardening recomendado excluye
Quad9, USBGuard, SSH solo con claves y las restricciones estrictas de `/dev/shm`
y módulos del kernel. No añade AUR, PPAs ni instaladores remotos automáticamente.

## Personalización

| Configuración | Fuente que debes editar | Destino |
|---|---|---|
| Bash, alias y funciones | `bash/conf/` | `~/.bashrc`, `~/.bash.aliases`, `~/.bash.functions` |
| Integración Zsh | `zsh/conf/dotfiles.zsh` | `~/.config/dotfiles/zsh.zsh` |
| Git | `git/.gitconfig` | `~/.config/git/dotfiles.gitconfig` |
| SSH | `git/ssh/config` | `~/.ssh/conf.d/90-dotfiles.conf` |
| Vim | `vim/.vimrc` | `~/.vimrc` |
| Comandos | `bash/bin/` | `~/.local/bin/` |

Mantén identidad Git y claves privadas fuera del repositorio público. Personaliza
las fuentes antes de aplicar el perfil: una siguiente ejecución puede reemplazar
cambios hechos solo en los archivos instalados. Los comandos se copian y siguen
funcionando aunque muevas el checkout.

## Uso diario y recuperación

- Navegar/buscar: `mkcd`, `up`, `gitroot`, `fcd`, `ftext`.
- Archivos/proyectos: `pretty`, `extract`, `backup`, `mkvenv`, `retry`, `serve`.
- Conectividad: `portcheck`, `monitorport`, `httpcheck`, `sslcheck`, `dominfo`.
- Vim opcional: Espacio es el líder; `Space f` busca archivos, `Space g` texto y `Space w` guarda.

Los respaldos de usuario están en `~/.local/state/dotfiles/backups/<run-id>/`
(o el directorio XDG configurado), reproduciendo debajo la ruta absoluta original.
Repetir un módulo conserva la primera copia de la sesión. Si falla el respaldo,
se detiene la sustitución del archivo.

Para recuperar un archivo, revisa la copia y restáurala a su ruta original.
El hardening tiene su propio menú **Recovery** y snapshots en
`/var/backups/dotfiles-hardening/`; restaurar configuración no desinstala paquetes.
Antes de actualizar, revisa el diff y ejecuta `--status`. En equipos remotos,
conserva acceso alternativo antes de cambiar SSH, firewall o DNS.

## Comprobar cambios

```bash
python3 tools/verify.py
# CI exige el analizador estático:
python3 tools/verify.py --require-shellcheck
```

La regresión solo usa archivos temporales. Valida instalaciones y hardening en
máquinas desechables de cada distribución. Consulta la [referencia](docs/REFERENCE.md)
para firewall, DNS, SSH, perfiles y atajos Vim completos.

[Licencia MIT](LICENSE).
