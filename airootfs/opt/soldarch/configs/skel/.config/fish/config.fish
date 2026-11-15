if status is-interactive
    set -g fish_greeting ""
end

set -gx EDITOR nano
set -gx VISUAL nano

alias ls='ls --color=auto'
alias ll='ls -lah'
alias grep='grep --color=auto'
