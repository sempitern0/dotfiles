# ~/.bashrc: executed by bash(1) for non-login shells.

# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

iatest=$(expr index "$-" i)

# Disable the bell
if [[ $iatest -gt 0 ]]; then bind "set bell-style none"; fi
setterm --blength 0 > /dev/null 2>&1

# https://unix.stackexchange.com/questions/545045/what-is-the-difference-between-ixon-and-ixoff-tty-attributes
stty -ixon

# Expand the history size
export HISTFILESIZE=10000
export HISTSIZE=500
export HISTTIMEFORMAT="%F %T " # add timestamp to history

# Don't put duplicate lines in the history and do not add lines that start with a space
export HISTCONTROL=erasedups:ignoredups:ignorespace

# Colors for ls and grep
export CLICOLOR=1
export LS_COLORS='no=00:fi=00:di=00;34:ln=01;36:pi=40;33:so=01;35:do=01;35:bd=40;33;01:cd=40;33;01:or=40;31;01:ex=01;32:*.tar=01;31:*.tgz=01;31:*.arj=01;31:*.taz=01;31:*.lzh=01;31:*.zip=01;31:*.z=01;31:*.Z=01;31:*.gz=01;31:*.bz2=01;31:*.deb=01;31:*.rpm=01;31:*.jar=01;31:*.jpg=01;35:*.jpeg=01;35:*.gif=01;35:*.bmp=01;35:*.pbm=01;35:*.pgm=01;35:*.ppm=01;35:*.tga=01;35:*.xbm=01;35:*.xpm=01;35:*.tif=01;35:*.tiff=01;35:*.png=01;35:*.mov=01;35:*.mpg=01;35:*.mpeg=01;35:*.avi=01;35:*.fli=01;35:*.gl=01;35:*.dl=01;35:*.xcf=01;35:*.xwd=01;35:*.ogg=01;35:*.mp3=01;35:*.wav=01;35:*.xml=00;31:'

# Color for manpages
export GROFF_NO_SGR=1
export LESS_TERMCAP_mb=$'\E[01;31m'
export LESS_TERMCAP_md=$'\E[01;31m'
export LESS_TERMCAP_me=$'\E[0m'
export LESS_TERMCAP_se=$'\E[0m'
export LESS_TERMCAP_so=$'\E[01;44;33m'
export LESS_TERMCAP_ue=$'\E[0m'
export LESS_TERMCAP_us=$'\E[01;32m'
export MANPAGER="less -R --use-color -Dd+r -Du+g"
export MAN_KEEP_FORMATTING=1

# User Agents
export CHROME_DESKTOP_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
export EDGE_DESKTOP_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36 Edg/122.0.0.0"
export FIREFOX_DESKTOP_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:123.0) Gecko/20100101 Firefox/123.0"
export ANDROID_MOBILE_AGENT="Mozilla/5.0 (Linux; Android 13; SM-S901B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36"
export IPHONE_MOBILE_AGENT="Mozilla/5.0 (iPhone; CPU iPhone OS 17_3 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.3 Mobile/15E148 Safari/604.1"
export GOOGLE_BOT_DESKTOP_AGENT="Mozilla/5.0 (Linux; Android 6.0.1; Nexus 5X Build/MMB29P) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)"

# Shell Options
shopt -s checkwinsize
shopt -s histappend
shopt -s globstar
shopt -s cdspell

# XDG Base Directory Specification
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_STATE_HOME="$HOME/.local/state"
export XDG_CACHE_HOME="$HOME/.cache"

# If set, the pattern "**" used in a pathname expansion context will
# match all files and zero or more directories and subdirectories.
#shopt -s globstar

# make less more friendly for non-text input files, see lesspipe(1)
if command -v lesspipe >/dev/null 2>&1; then
  eval "$(SHELL=/bin/sh lesspipe)"
fi

# Color support for ls / grep
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls='ls --color=auto'
    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
fi

# Completion features
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi

# Custom sources
if [ -e "$HOME/.bash.aliases" ]; then
    source "$HOME/.bash.aliases"
fi

if [ -e "$HOME/.bash.functions" ]; then
    source "$HOME/.bash.functions"
fi

# FZF key bindings
if [ -f /usr/share/doc/fzf/examples/key-bindings.bash ]; then
    source /usr/share/doc/fzf/examples/key-bindings.bash
fi

# Disabled fastfetch to not start on new terminal sessions
#if command -v fastfetch >/dev/null 2>&1; then
#    fastfetch
#fi


sanitize() {
  local s
  s=$(printf '%s' "$1" | LC_ALL=C tr -d '\000-\037\177')
  printf '%s' "${s:0:128}"
}

__STATUS_SEG=''
__SAFE_PWD=''
__GIT_SEG=''

__update_prompt_vars() {
  local last_status=$?
  
  if [ $last_status -ne 0 ]; then
    __STATUS_SEG='✘ '
  else
    __STATUS_SEG=''
  fi

  __SAFE_PWD=$(sanitize "$PWD")

  local G=/usr/bin/git b
  PATH=/usr/bin:/bin

  if [ -x "$G" ] && b=$("$G" rev-parse --abbrev-ref HEAD 2>/dev/null); then
    b=$(sanitize "$b")
    __GIT_SEG=" (git:$b)"
  else
    __GIT_SEG=''
  fi
}

__sync_history() {
  history -a
  history -c
  history -r
}

if declare -p PROMPT_COMMAND 2>/dev/null | grep -q 'declare \-a'; then
  PROMPT_COMMAND=(__update_prompt_vars __sync_history "${PROMPT_COMMAND[@]}")
else
  PROMPT_COMMAND="__update_prompt_vars; __sync_history; ${PROMPT_COMMAND:-}"
fi

PS1='\[\e[90m\][\t] \[\e[31m\]${__STATUS_SEG}\[\e[34m\]\u\[\e[0m\]@\[\e[32m\]\h\[\e[0m\]:\[\e[36m\]${__SAFE_PWD}\[\e[33m\]${__GIT_SEG}\[\e[0m\]\$ '