#!/bin/bash
set -euo pipefail

currentTimestamp() {
  date -u +"%Y-%m-%dT%H:%M:%S.%3NZ"
}

source ../constants.ini

initial_message=$(cat <<EOF
{
  "message": {
    "content":"Tere",
    "authorTimestamp":"$(currentTimestamp)",
    "authorRole":"end-user"
    },
  "endUserTechnicalData": {
    "endUserUrl":"http://localhost:3003/",
    "endUserOs":"Agent: Firefox (v143.0), OS: Ubuntu (vnone), device: unknown"
    },
  "holidays": [
    "2025-01-01",
    "2025-02-24",
    "2025-04-18",
    "2025-04-20",
    "2025-05-01",
    "2025-06-08",
    "2025-06-23",
    "2025-06-24",
    "2025-08-20",
    "2025-12-24",
    "2025-12-25",
    "2025-12-26"
    ],
  "holidayNames": "2025-01-01-uusaasta,2025-02-24-iseseisvuspäev,2025-04-18-suur reede,2025-04-20-lihavõtted,2025-05-01-kevadpüha,2025-06-08-nelipühade 1. püha,2025-06-23-võidupüha,2025-06-24-jaanipäev,2025-08-20-taasiseseisvumispäev,2025-12-24-jõululaupäev,2025-12-25-esimene jõulupüha,2025-12-26-teine jõulupüha",
  "domain":"none"
}
EOF
)


script_name=`basename $0`
pwd
echo "$(currentTimestamp) - $script_name started"

echo "$(currentTimestamp) - Creating new chat"

response_headers=$(mktemp)
response_body=$(mktemp)

curl -s -D "$response_headers" -o "$response_body" -X POST "$CHATBOT_RUUTER_PUBLIC/backoffice/chats/init" \
  -H "Content-Type: application/json" \
  -d "$initial_message"

chat_id=$(jq -r '.response.id' < "$response_body")

if [[ -z "$chat_id" ]]; then
  echo "Failed to get chat_id from response"
  exit 1
fi

chat_jwt=$(grep -i "^Set-Cookie: chatJwt=" "$response_headers" | sed 's/^Set-Cookie: chatJwt=\([^;]*\).*/\1/')

if [[ -z "$chat_jwt" ]]; then
  echo "Failed to get chatJwt from response headers"
  exit 1
fi

echo "chat_id: $chat_id"
echo "chat_jwt: $chat_jwt"

initialResponse=$(curl -s -X GET "$CHATBOT_RUUTER_PUBLIC/backoffice/chats/get" \
  -H "Cookie: chatJwt=$chat_jwt")

sleep 1.5

lastMessage=$(echo "$initialResponse" | jq -r '.response.lastMessage')
echo "$lastMessage"

second_message=$(cat <<EOF
{
  "message": {
    "chatId":"$chat_id",
    "content":"Virtuaalne vestlusrobot ärkab sõnade kaudu ellu, jäljendades inimlikku rütmi ja tooni. Tehisintellekti loodud vastused voolavad katkestusteta, justkui sulanduksid need päris vestluse öö voogu.",
    "authorTimestamp":"$(currentTimestamp)",
    "authorRole":"end-user"
    },
  "holidays": [
    "2025-01-01",
    "2025-02-24",
    "2025-04-18",
    "2025-04-20",
    "2025-05-01",
    "2025-06-08",
    "2025-06-23",
    "2025-06-24",
    "2025-08-20",
    "2025-12-24",
    "2025-12-25",
    "2025-12-26"
    ],
  "holidayNames":"2025-01-01-uusaasta,2025-02-24-iseseisvuspäev,2025-04-18-suur reede,2025-04-20-lihavõtted,2025-05-01-kevadpüha,2025-06-08-nelipühade 1. püha,2025-06-23-võidupüha,2025-06-24-jaanipäev,2025-08-20-taasiseseisvumispäev,2025-12-24-jõululaupäev,2025-12-25-esimene jõulupüha,2025-12-26-teine jõulupüha",
  "domain":"none"
}
EOF
)

sleep 1.5

response=$(curl -s -X POST "$CHATBOT_RUUTER_PUBLIC/backoffice/chats/messages/add" \
  -H "Content-Type: application/json" \
  -H "Cookie: chatJwt=$chat_jwt" \
  -d "$second_message")

sleep 1.5

bot_response=$(curl -s -X GET "$CHATBOT_RUUTER_PUBLIC/backoffice/chats/get" \
  -H "Cookie: chatJwt=$chat_jwt")

last_response=$(echo "$bot_response" | jq -r '.response.lastMessage')
echo "$last_response"

sleep 1.5

events=(
  "CLIENT_LEFT_FOR_UNKNOWN_REASONS"
  "CLIENT_LEFT_WITH_NO_RESOLUTION"
  "CLIENT_LEFT_WITH_ACCEPTED"
  "RESPONSE_SENT_TO_CLIENT_EMAIL"
  "OTHER"
  "HATE_SPEECH"
  "ACCEPTED"
)

index_file="/tmp/event_index"

if [ ! -f "$index_file" ]; then
  echo 0 > "$index_file"
fi

index=$(cat "$index_file")
event=${events[$index]}
next_index=$(( (index + 1) % ${#events[@]} ))
echo "$next_index" > "$index_file"

terminate_message=$(cat <<EOF
{
  "message": {
    "chatId":"$chat_id",
    "authorTimestamp":"$(currentTimestamp)",
    "authorRole":"end-user",
    "event": "$event"
    },
  "status": "ENDED",
  "domain":"none"
}
EOF
)

terminateChat=$(curl -s -X POST "$CHATBOT_RUUTER_PUBLIC/backoffice/chats/end" \
      -H "Content-Type: application/json" \
      -H "Cookie: chatJwt=$chat_jwt" \
      -d "$terminate_message")

echo "termination response: $terminateChat"

echo "$(currentTimestamp) - $script_name finished, chat with id $chat_id was created and terminated"
