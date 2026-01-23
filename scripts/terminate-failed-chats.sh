#!/bin/bash

script_name=`basename $0`
pwd

currentTimestamp() {
  date -u +"%Y-%m-%dT%H:%M:%S.%3NZ"
}

echo "$(currentTimestamp) - $script_name started"

source ../constants.ini

get_new_nonce() {
  response=$(curl -s -X POST -H "Content-Type: application/json" "$TRAINING_RESQL/get-new-nonce")
  nonce=$(echo "$response" |grep -Eo "([a-f0-9-]+-){4}[a-f0-9-]+")
  echo "$nonce"
}

dead_chat_res=$(curl -s \
  -H "x-ruuter-nonce: $(get_new_nonce)" \
  -H "Content-Type: application/json" \
  -X POST \
  -d "{\"inactivityTime\": ${INACTIVITY_TIME}}" \
  "$CHATBOT_RUUTER_PRIVATE/cron-tasks/end-dead-chats")

echo "$(date -u +"%Y-%m-%d %H:%M:%S.%3NZ") - Raw Response: $dead_chat_res"

dead_chats=$(echo "$dead_chat_res" | jq -r '.response')
chat_count=$(echo "$dead_chats" | jq 'length')

echo "$(date -u +"%Y-%m-%d %H:%M:%S.%3NZ") - Found $chat_count dead chats"

if [ "$chat_count" -gt 0 ]; then
  echo "$dead_chats" | jq -c '.[]' | while read -r chat; do
    id=$(echo "$chat" | jq -r '.base_id')
    ended_time=$(echo "$chat" | jq -r '.ended_time')
    
    echo "$(date -u +"%Y-%m-%d %H:%M:%S.%3NZ") - Ending chat $id with ended time: $ended_time"
    curl -s -X POST "$CHATBOT_RUUTER_PUBLIC/chats/end" \
      -H "Content-Type: application/json" \
      -d "{
        \"message\": {
          \"chatId\": \"$id\",
          \"authorRole\": \"end-user\",
          \"authorTimestamp\": \"$ended_time\",
          \"event\": \"CLIENT_LEFT_FOR_UNKNOWN_REASONS\"
        },
        \"status\": \"ENDED\",
        \"domain\":\"none\",
        \"ended\": \"$ended_time\"
      }"
    echo
  done
fi

echo "$(date -u +"%Y-%m-%d %H:%M:%S.%3NZ") - $script_name finished"
