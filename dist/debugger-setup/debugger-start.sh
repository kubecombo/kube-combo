#!/bin/bash
# This script is used to hold the debugger container.

cat << EOF >> ~/.bashrc
# kubectl aliases and completion
alias k=kubectl
alias ka="kubectl apply -f "
alias kgp="kubectl get po -A -o wide"
alias kgn="kubectl get node -A -o wide"
source <(kubectl completion bash)
EOF

env
sleep infinity

## 1. debug