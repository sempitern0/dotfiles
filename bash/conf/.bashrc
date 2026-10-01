# ~/.bashrc - portable interactive Bash defaults for developer/admin workstations.

case ":${PATH:-}:" in
    *":$HOME/.local/bin:"*) ;;
    *) export PATH="$HOME/.local/bin:${PATH:-/usr/bin:/bin}" ;;
esac

[[ $- == *i* ]] || return 0

export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"

if [[ -z "${EDITOR:-}" ]]; then
    if command -v nvim >/dev/null 2>&1; then export EDITOR=nvim
    elif command -v vim >/dev/null 2>&1; then export EDITOR=vim
    else export EDITOR=vi
    fi
fi
export VISUAL="${VISUAL:-$EDITOR}"
export PAGER="${PAGER:-less}"
export LESS="${LESS:--FRX}"

HISTSIZE="${HISTSIZE:-10000}"
HISTFILESIZE="${HISTFILESIZE:-20000}"
HISTCONTROL="${HISTCONTROL:-ignoreboth:erasedups}"
HISTTIMEFORMAT="${HISTTIMEFORMAT:-%F %T }"
shopt -s histappend checkwinsize
shopt -s globstar 2>/dev/null || true
shopt -s cdspell 2>/dev/null || true

if [[ -t 0 ]]; then
    bind 'set bell-style none' 2>/dev/null || true
    stty -ixon 2>/dev/null || true
fi

if command -v dircolors >/dev/null 2>&1; then
    if [[ -r "$HOME/.dircolors" ]]; then
        eval "$(dircolors -b "$HOME/.dircolors" 2>/dev/null)" || true
    else
        eval "$(dircolors -b 2>/dev/null)" || true
    fi
fi

if command -v lesspipe >/dev/null 2>&1; then
    eval "$(SHELL=/bin/sh lesspipe 2>/dev/null)" || true
fi

if ! shopt -oq posix; then
    for _bc in /usr/share/bash-completion/bash_completion /etc/bash_completion; do
        if [[ -r "$_bc" ]]; then . "$_bc"; break; fi
    done
    unset _bc
fi

# Prefer fzf's built-in shell integration when the installed version provides it.
if command -v fzf >/dev/null 2>&1; then
    if fzf --bash >/dev/null 2>&1; then
        eval "$(fzf --bash)"
    else
        for _fzf in /usr/share/doc/fzf/examples/key-bindings.bash /usr/share/fzf/key-bindings.bash; do
            [[ -r "$_fzf" ]] && { . "$_fzf"; break; }
        done
        for _fzf in /usr/share/doc/fzf/examples/completion.bash /usr/share/fzf/completion.bash; do
            [[ -r "$_fzf" ]] && { . "$_fzf"; break; }
        done
        unset _fzf
    fi

    # rg makes Ctrl-T/Alt-C fast even in large repositories. fzf's Ctrl-R keeps
    # its native reverse-history widget.
    if command -v rg >/dev/null 2>&1; then
        export FZF_DEFAULT_COMMAND='rg --files --hidden --follow --glob "!.git/*" 2>/dev/null'
        export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
    fi
    if command -v fd >/dev/null 2>&1; then
        export FZF_ALT_C_COMMAND='fd --type d --hidden --exclude .git . 2>/dev/null'
    elif command -v fdfind >/dev/null 2>&1; then
        export FZF_ALT_C_COMMAND='fdfind --type d --hidden --exclude .git . 2>/dev/null'
    fi
fi

if command -v zoxide >/dev/null 2>&1; then
    eval "$(zoxide init bash --cmd cd 2>/dev/null)" || true
fi

for _dotfile in "$HOME/.bash.functions" "$HOME/.bash.aliases"; do
    if [[ -r "$_dotfile" ]]; then
        . "$_dotfile" || printf 'Warning: failed to load %s\n' "$_dotfile" >&2
    fi
done
unset _dotfile

# Shell-specific refresh semantics. Zsh overrides this in its managed include.
alias refresh='source ~/.bashrc'

__dotfiles_sanitize_prompt() {
    local s="${1:-}"
    s="$(printf '%s' "$s" | LC_ALL=C tr -d '\000-\037\177' 2>/dev/null)"
    printf '%s' "${s:0:160}"
}

__DOT_STATUS=""
__DOT_PWD=""
__DOT_GIT=""
__DOT_VENV=""

__dotfiles_prompt_command() {
    local rc=$? branch="" dirty=""
    (( rc == 0 )) && __DOT_STATUS="" || __DOT_STATUS="✘${rc} "
    __DOT_PWD="$(__dotfiles_sanitize_prompt "$PWD")"

    if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null || true)"
        git diff --quiet --ignore-submodules -- 2>/dev/null || dirty='*'
        git diff --cached --quiet --ignore-submodules -- 2>/dev/null || dirty='*'
    fi
    [[ -n "$branch" ]] && __DOT_GIT=" (git:$(__dotfiles_sanitize_prompt "$branch")${dirty})" || __DOT_GIT=""
    [[ -n "${VIRTUAL_ENV:-}" ]] && __DOT_VENV=" [venv:$(basename "$VIRTUAL_ENV")]" || __DOT_VENV=""

    history -a 2>/dev/null || true
    history -n 2>/dev/null || true
    return "$rc"
}

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
    PS1='[\t] ${__DOT_STATUS}\u@\h:${__DOT_PWD}${__DOT_GIT}${__DOT_VENV}\$ '
else
    PS1='\[\e[90m\][\t]\[\e[0m\] \[\e[31m\]${__DOT_STATUS}\[\e[34m\]\u\[\e[0m\]@\[\e[32m\]\h\[\e[0m\]:\[\e[36m\]${__DOT_PWD}\[\e[33m\]${__DOT_GIT}\[\e[35m\]${__DOT_VENV}\[\e[0m\]\$ '
fi
