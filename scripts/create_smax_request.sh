#!/bin/bash
script_name=`basename $0`
pwd
echo $(date -u +"%Y-%m-%d %H:%M:%S.%3NZ") - $script_name started
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../constants.ini"

if [ "$SMAX_INTEGRATION_ENABLED" = "false" ]; then
  echo "$(date -u +"%Y-%m-%d %H:%M:%S.%3NZ") - $script_name exiting: SMAX integration disabled"
  exit 0
fi

get_new_nonce() {
  response=$(curl -s -X POST -H "Content-Type: application/json" "$TRAINING_RESQL/get-new-nonce")
  nonce=$(echo "$response" |grep -Eo "([a-f0-9-]+-){4}[a-f0-9-]+")
  echo "$nonce"
}

sync_res=$(curl -H "x-ruuter-nonce: $(get_new_nonce)" "$CHATBOT_PRIVATE_RUUTER/smax/chats/sync")
echo $(date -u +"%Y-%m-%d %H:%M:%S.%3NZ") - $sync_res

echo $(date -u +"%Y-%m-%d %H:%M:%S.%3NZ") - $script_name finished
