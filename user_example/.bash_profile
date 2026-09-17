export FLYCTL_INSTALL="/home/rickduggan/.fly"
export PATH="$FLYCTL_INSTALL/bin:$PATH"
## [Completion]
## Completion scripts setup. Remove the following line to uninstall
[ -f /home/rickduggan/.dart-cli-completion/bash-config.bash ] && . /home/rickduggan/.dart-cli-completion/bash-config.bash || true
## [/Completion]
if [ -f ~/.bashrc ]; then
    source ~/.bashrc
fi
