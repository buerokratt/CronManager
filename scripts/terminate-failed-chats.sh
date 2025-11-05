 #!/bin/bash

script_name=`basename $0`
pwd

currentTimestamp() {
  date -u +"%Y-%m-%dT%H:%M:%S.%3NZ"
}

echo "$(currentTimestamp) - $script_name started"

.. /app/constants.ini

get_new_nonce() {
  response=$(curl -s -X POST -H "Content-Type: application/json" "$TRAINING_RESQL/get-new-nonce")
  nonce=$(echo "$response" |grep -Eo "([a-f0-9-]+-){4}[a-f0-9-]+")
  echo "$nonce"
}

dead_chat_ids=$(curl -s \
  -H "x-ruuter-nonce: $(get_new_nonce)" \
  -H "Content-Type: application/json" \
  "http://component-byk-ruuter-private:8080/backoffice/cron-tasks/end-dead-chats")

echo "$(date -u +"%Y-%m-%d %H:%M:%S.%3NZ") - Raw Response: $dead_chat_ids"

ids=$(echo "$dead_chat_ids" | jq -r '.response' | tr ',' '\n')

if [ -n "$ids" ]; then
  for id in $ids; do
    echo "$(date -u +"%Y-%m-%d %H:%M:%S.%3NZ") - Ending chat $id"
    curl -s -X POST "http://component-byk-ruuter:8080/backoffice/chats/end" \
      -H "Content-Type: application/json" \
      -d "{
        \"message\": {
          \"chatId\": \"$id\",
          \"authorRole\": \"end-user\",
          \"authorTimestamp\": \"$(currentTimestamp)\",
          \"event\": \"CLIENT_LEFT_FOR_UNKNOWN_REASONS\"
        },
        \"status\": \"ENDED\",
        \"domain\":\"none\"
      }"
    echo
  done
else
  echo "$(date -u +"%Y-%m-%d %H:%M:%S.%3NZ") - No dead chats found"
fi

echo $(date -u +"%Y-%m-%d %H:%M:%S.%3NZ") - $script_name finished
