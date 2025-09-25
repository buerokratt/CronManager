 #!/bin/bash

script_name=`basename $0`
pwd
echo $(date -u +"%Y-%m-%d %H:%M:%S.%3NZ") - $script_name started
. constants.ini

get_new_nonce() {
  response=$(curl -s -X POST -H "Content-Type: application/json" "$TRAINING_RESQL/get-new-nonce")
  nonce=$(echo "$response" |grep -Eo "([a-f0-9-]+-){4}[a-f0-9-]+")
  echo "$nonce"
}

dead_chat_ids=$(curl -s \
  -H "x-ruuter-nonce: $(get_new_nonce)" \
  -H "Content-Type: application/json" \
  "$CHATBOT_RUUTER_PRIVATE/cron-tasks/end-dead-chats")

echo "$(date -u +"%Y-%m-%d %H:%M:%S.%3NZ") - Raw Response: $dead_chat_ids"

inner=$(echo "$dead_chat_ids" | jq -r '.response[0]')

ids=$(echo "$dead_chat_ids" | jq -r '.response.keys' | tr ',' '\n')

if [ -n "$ids" ]; then
  for id in $ids; do
    echo "$(date -u +"%Y-%m-%d %H:%M:%S.%3NZ") - Ending chat $id"
    curl -s -X POST "$CHATBOT_RUUTER_PUBLIC/chats/end" \
      -H "Content-Type: application/json" \
      -d "{
        \"message\": {
          \"chatId\": \"$id\",
          \"authorRole\": \"end-user\",
          \"authorTimestamp\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\",
          \"event\": \"client_left_for_unknown_reasons\"
        },
        \"status\": \"ENDED\"
      }"
    echo
  done
else
  echo "$(date -u +"%Y-%m-%d %H:%M:%S.%3NZ") - No dead chats found"
fi

echo $(date -u +"%Y-%m-%d %H:%M:%S.%3NZ") - $script_name finished