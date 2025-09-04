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

# 1. run inspection
echo "###### run inspection ######"
INSPECTION_DIR="/tasks"
if [ -d "$INSPECTION_DIR" ]; then
  files=()
  while IFS= read -r f; do
    files+=("$(basename "$f")")
  done < <(find "$INSPECTION_DIR" -type f)

  for file in "${files[@]}"; do
    /debugger --task="$file"
  done
else
  echo "Directory $INSPECTION_DIR does not exist."
fi

# 2. run script
echo "###### run check list ######"
if [ "$HOST_CHECK_LIST" = "true" ]; then
  echo "Running host check list..."
  if [ -f /check-list.sh ]; then
    bash /check-list.sh
  else
    echo "No check-list.sh found. Skipping host check list."
  fi
else
  echo "Host check list is disabled. Skipping."
fi

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

# 3. hold the container
echo "###### sleep infinity ######"
sleep infinity
