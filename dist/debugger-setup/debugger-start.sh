#!/bin/bash
set -e
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/runAt/util/log.sh"

# set up complete for bash
cat << EOF >> ~/.bashrc
# kubectl aliases and completion
alias k=kubectl
alias ka="kubectl apply -f "
alias kgp="kubectl get po -A -o wide"
alias kgn="kubectl get node -A -o wide"
alias klogovn='kubectl -n kube-system logs \$(kubectl -n kube-system get lease kube-ovn-controller -o jsonpath='{.spec.holderIdentity}')'
source <(kubectl completion bash)
EOF

# show env
log_info "###### show env ######"
env

# 1. run inspection
log_info "###### run inspection ######"
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
	log_warn "Directory $INSPECTION_DIR does not exist."
fi

# 2. run script
log_info "###### run check list ######"
if [ "$HOST_CHECK_LIST" = "true" ]; then
	log_info "Running host check list..."
	if [ -f /check-list.sh ]; then
		bash /check-list.sh
	else
		log_warn "No check-list.sh found. Skipping host check list."
	fi
else
	log_info "Host check list is disabled. Skipping."
fi

log_info "###### run scripts ######"
SCRIPTS_DIR="/scripts"
if [ -d "$SCRIPTS_DIR" ]; then
	for script in "$SCRIPTS_DIR"/*.sh; do
		if [ -f "$script" ]; then
			log_info "Executing script: $script"
			bash "$script"
		else
			log_warn "No scripts found in $SCRIPTS_DIR"
		fi
	done
else
	log_warn "Directory $SCRIPTS_DIR does not exist."
fi

# 3. hold the container
log_info "###### sleep infinity ######"
sleep infinity
