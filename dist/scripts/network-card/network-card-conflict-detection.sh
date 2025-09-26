#!/bin/bash
set -e
set -o pipefail

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../util/log.sh"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../util/util.sh"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../util/network.sh"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../util/curl.sh"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${DIR}" || exit

YAML=$(generate_yaml_detection "network_card_conflict_results")$'\n'
