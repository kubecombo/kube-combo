#!/bin/bash
set -e

# set up complete for bash
cat << EOF >> ~/.bashrc
# kubectl aliases and completion
alias k=kubectl
alias ka="kubectl apply -f "
alias kgp="kubectl get po -A -o wide"
alias kgn="kubectl get node -A -o wide"
source <(kubectl completion bash)
EOF

# show env
echo "###### show env ######"
env

# 1. run script
echo "###### run scripts ######"
SCRIPTS_DIR="/scripts"
if [ -d "$SCRIPTS_DIR" ]; then
  for script in "$SCRIPTS_DIR"/*.sh; do
    if [ -f "$script" ]; then
      echo "Executing script: $script"
      bash "$script"
    else
      echo "No scripts found in $SCRIPTS_DIR"
    fi
  done
else
  echo "Directory $SCRIPTS_DIR does not exist."
fi

# 2. hold the container
echo "###### sleep infinity ######"
sleep infinity
