# ~/.bashrc - portable interactive Bash defaults for developer/admin workstations.

# Keep ~/.local/bin first without duplicating PATH entries.
case ":${PATH:-}:" in
    *":$HOME/.local/bin:"*) ;;
    *) export PATH="$HOME/.local/bin:${PATH:-/usr/bin:/bin}" ;;
esac

# Nothing below is needed by non-interactive shells.
[[ $- == *i* ]] || return 0

# XDG defaults: only set when the caller did not already choose values.
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"

# Conservative editor selection. A user-provided EDITOR/VISUAL always wins.
if [[ -z "${EDITOR:-}" ]]; then
    if command -v nvim >/dev/null 2>&1; then
        export EDITOR=nvim
    elif command -v vim >/dev/null 2>&1; then
        export EDITOR=vim
    else
        export EDITOR=vi
    fi
fi
export VISUAL="${VISUAL:-$EDITOR}"
export PAGER="${PAGER:-less}"
export LESS="${LESS:--FRX}"

# History: append instead of replacing other terminals' history.
HISTSIZE="${HISTSIZE:-10000}"
HISTFILESIZE="${HISTFILESIZE:-20000}"
HISTCONTROL="${HISTCONTROL:-ignoreboth:erasedups}"
HISTTIMEFORMAT="${HISTTIMEFORMAT:-%F %T }"
shopt -s histappend checkwinsize

# Quality-of-life shell behaviour.
shopt -s globstar 2>/dev/null || true
shopt -s cdspell 2>/dev/null || true

# Terminal-only features must never emit errors in redirected/non-TTY contexts.
if [[ -t 0 ]]; then
    bind 'set bell-style none' 2>/dev/null || true
    stty -ixon 2>/dev/null || true
fi

# GNU dircolors where available; leave BSD/non-GNU hosts alone.
if command -v dircolors >/dev/null 2>&1; then
    if [[ -r "$HOME/.dircolors" ]]; then
        eval "$(dircolors -b "$HOME/.dircolors" 2>/dev/null)" || true
    else
        eval "$(dircolors -b 2>/dev/null)" || true
    fi
fi

# lesspipe is optional and distro-specific.
if command -v lesspipe >/dev/null 2>&1; then
    eval "$(SHELL=/bin/sh lesspipe 2>/dev/null)" || true
fi

# Bash completion locations used by the main distribution families.
if ! shopt -oq posix; then
    for _bc in \
        /usr/share/bash-completion/bash_completion \
        /etc/bash_completion
    do
        if [[ -r "$_bc" ]]; then
            # shellcheck disable=SC1090
            . "$_bc"
            break
        fi
    done
    unset _bc
fi

# Optional fzf integration. Source only existing vendor files.
for _fzf in \
    /usr/share/doc/fzf/examples/key-bindings.bash \
    /usr/share/fzf/key-bindings.bash
do
    [[ -r "$_fzf" ]] && { . "$_fzf"; break; }
done
for _fzf in \
    /usr/share/doc/fzf/examples/completion.bash \
    /usr/share/fzf/completion.bash
do
    [[ -r "$_fzf" ]] && { . "$_fzf"; break; }
done
unset _fzf

# zoxide is additive; normal cd remains available if it is absent.
if command -v zoxide >/dev/null 2>&1; then
    eval "$(zoxide init bash --cmd cd 2>/dev/null)" || true
fi

# Custom user helpers. Syntax errors should be visible but must not terminate the shell.
for _dotfile in "$HOME/.bash.functions" "$HOME/.bash.aliases"; do
    if [[ -r "$_dotfile" ]]; then
        # shellcheck disable=SC1090
        . "$_dotfile" || printf 'Warning: failed to load %s\n' "$_dotfile" >&2
    fi
done
unset _dotfile

# Compact prompt with status, user@host, working directory and current Git branch.
__dotfiles_sanitize_prompt() {
    local s="${1:-}"
    s="$(printf '%s' "$s" | LC_ALL=C tr -d '\000-\037\177' 2>/dev/null)"
    printf '%s' "${s:0:160}"
}

__DOT_STATUS=""
__DOT_PWD=""
__DOT_GIT=""

__dotfiles_prompt_command() {
    local rc=$? branch=""
    (( rc == 0 )) && __DOT_STATUS="" || __DOT_STATUS="✘${rc} "
    __DOT_PWD="$(__dotfiles_sanitize_prompt "$PWD")"

    if command -v git >/dev/null 2>&1; then
        branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null || true)"
    fi
    if [[ -n "$branch" ]]; then
        __DOT_GIT=" git:$(__dotfiles_sanitize_prompt "$branch")"
    else
        __DOT_GIT=""
    fi

    # Merge history written by other active terminals without clearing this shell's list.
    history -a 2>/dev/null || true
    history -n 2>/dev/null || true
    return "$rc"
}

# Avoid adding the hook more than once when ~/.bashrc is re-sourced.
if declare -p PROMPT_COMMAND 2>/dev/null | grep -q 'declare -a'; then
    _dot_pc_found=0
    for _dot_pc in "${PROMPT_COMMAND[@]}"; do
        [[ "$_dot_pc" == "__dotfiles_prompt_command" ]] && _dot_pc_found=1
    done
    (( _dot_pc_found == 1 )) || PROMPT_COMMAND=(__dotfiles_prompt_command "${PROMPT_COMMAND[@]}")
    unset _dot_pc _dot_pc_found
else
    case ";${PROMPT_COMMAND:-};" in
        *';__dotfiles_prompt_command;'*) ;;
        *) PROMPT_COMMAND="__dotfiles_prompt_command${PROMPT_COMMAND:+; $PROMPT_COMMAND}" ;;
    esac
fi

if [[ -n "${NO_COLOR:-}" || "${TERM:-dumb}" == dumb ]]; then
    PS1='[\t] ${__DOT_STATUS}\u@\h:${__DOT_PWD}${__DOT_GIT}\$ '
else
    PS1='\[\e[90m\][\t]\[\e[0m\] \[\e[31m\]${__DOT_STATUS}\[\e[34m\]\u\[\e[0m\]@\[\e[32m\]\h\[\e[0m\]:\[\e[36m\]${__DOT_PWD}\[\e[33m\]${__DOT_GIT}\[\e[0m\]\$ '
fi
