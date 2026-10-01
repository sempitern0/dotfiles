# ~/.config/dotfiles/zsh.zsh
# Additive Zsh layer. Designed to coexist with Kali's /etc/zsh and user .zshrc.

case ":${PATH:-}:" in
    *":$HOME/.local/bin:"*) ;;
    *) export PATH="$HOME/.local/bin:${PATH:-/usr/bin:/bin}" ;;
esac

export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
export PAGER="${PAGER:-less}"
export LESS="${LESS:--FRX}"

if [[ -z "${EDITOR:-}" ]]; then
    if command -v nvim >/dev/null 2>&1; then export EDITOR=nvim
    elif command -v vim >/dev/null 2>&1; then export EDITOR=vim
    else export EDITOR=vi
    fi
fi
export VISUAL="${VISUAL:-$EDITOR}"

HISTFILE="${HISTFILE:-$HOME/.zsh_history}"
HISTSIZE="${HISTSIZE:-10000}"
SAVEHIST="${SAVEHIST:-20000}"
setopt APPEND_HISTORY SHARE_HISTORY HIST_IGNORE_ALL_DUPS HIST_REDUCE_BLANKS
setopt INTERACTIVE_COMMENTS AUTO_CD

# Shared helpers are kept in the historical filenames so Bash remains fully
# compatible and existing muscle-memory/custom sourcing keeps working.
[[ -r "$HOME/.bash.functions" ]] && source "$HOME/.bash.functions"
[[ -r "$HOME/.bash.aliases" ]] && source "$HOME/.bash.aliases"
alias refresh='source ~/.zshrc'

if command -v fzf >/dev/null 2>&1; then
    if fzf --zsh >/dev/null 2>&1; then
        eval "$(fzf --zsh)"
    else
        for _fzf in /usr/share/doc/fzf/examples/key-bindings.zsh /usr/share/fzf/key-bindings.zsh; do
            [[ -r "$_fzf" ]] && { source "$_fzf"; break; }
        done
        for _fzf in /usr/share/doc/fzf/examples/completion.zsh /usr/share/fzf/completion.zsh; do
            [[ -r "$_fzf" ]] && { source "$_fzf"; break; }
        done
        unset _fzf
    fi
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
    eval "$(zoxide init zsh --cmd cd 2>/dev/null)" || true
fi

# Use Zsh's native VCS integration rather than spawning a full prompt framework.
autoload -Uz add-zsh-hook vcs_info
zstyle ':vcs_info:git:*' check-for-changes true
zstyle ':vcs_info:git:*' stagedstr '+'
zstyle ':vcs_info:git:*' unstagedstr '*'
zstyle ':vcs_info:git:*' formats ' (git:%b%c%u)'
zstyle ':vcs_info:git:*' actionformats ' (git:%b|%a%c%u)'
vcs_info_msg_0_=''
__DOT_ZSH_VENV=''
_dotfiles_vcs_precmd() {
    vcs_info 2>/dev/null || vcs_info_msg_0_=''
    if [[ -n "${VIRTUAL_ENV:-}" ]]; then
        __DOT_ZSH_VENV="${VIRTUAL_ENV:t}"
    else
        __DOT_ZSH_VENV=''
    fi
}
add-zsh-hook precmd _dotfiles_vcs_precmd
setopt PROMPT_SUBST

# Preserve the useful Kali-like information density while making the segment
# portable: time, previous status, user@host, path, git branch/dirty state and venv.
PROMPT='%F{8}[%*]%f %(?..%F{red}✘%? %f)%F{blue}%n%f@%F{green}%m%f:%F{cyan}%~%f%F{yellow}${vcs_info_msg_0_}%f${__DOT_ZSH_VENV:+ %F{magenta}[venv:${__DOT_ZSH_VENV}]%f}%(!.#.$) '
