#!/bin/bash
set -euo pipefail

currentTimestamp() {
  if command -v perl >/dev/null 2>&1; then
    perl -MTime::HiRes=time -MPOSIX=strftime -e 'my $t = time; my $ms = int(($t - int($t)) * 1000); print strftime("%Y-%m-%dT%H:%M:%S", gmtime($t)); printf ".%03dZ\n", $ms;'
  else
    date -u +"%Y-%m-%dT%H:%M:%S.000Z"
  fi
}

fail() {
  echo "$(currentTimestamp) - ERROR: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

extract_cookie() {
  local cookie_name="$1"
  local headers_file="$2"

  grep -i "^Set-Cookie: ${cookie_name}=" "$headers_file" \
    | tail -n 1 \
    | sed "s/^Set-Cookie: ${cookie_name}=\([^;]*\).*/\1/I" \
    || true
}

request() {
  local method="$1"
  local url="$2"
  local body="${3:-}"
  local cookie="${4:-}"
  local headers_file="$5"
  local body_file="$6"
  local status
  local nonce

  nonce="$(get_new_nonce)"
  if [[ -n "$body" && -n "$cookie" ]]; then
    status=$(curl -sS -w "%{http_code}" -D "$headers_file" -o "$body_file" \
      -X "$method" "$url" \
      -H "Content-Type: application/json" \
      -H "Cookie: $cookie" \
      -H "x-ruuter-nonce: $nonce" \
      -d "$body")
  elif [[ -n "$body" ]]; then
    status=$(curl -sS -w "%{http_code}" -D "$headers_file" -o "$body_file" \
      -X "$method" "$url" \
      -H "Content-Type: application/json" \
      -H "x-ruuter-nonce: $nonce" \
      -d "$body")
  elif [[ -n "$cookie" ]]; then
    status=$(curl -sS -w "%{http_code}" -D "$headers_file" -o "$body_file" \
      -X "$method" "$url" \
      -H "Cookie: $cookie" \
      -H "x-ruuter-nonce: $nonce")
  else
    status=$(curl -sS -w "%{http_code}" -D "$headers_file" -o "$body_file" \
      -X "$method" "$url" \
      -H "x-ruuter-nonce: $nonce")
  fi

  [[ "$status" =~ ^2 ]] || fail "$method $url failed with HTTP $status: $(cat "$body_file")"
}

response_value() {
  local body_file="$1"
  local jq_filter="$2"

  jq -er "$jq_filter" < "$body_file"
}

pick_feedback_rating() {
  local is_five_rating_scale="$1"
  local ratings

  if [[ "$is_five_rating_scale" == "true" ]]; then
    ratings=(1 2 3 4 5)
  else
    ratings=(0 1 2 3 4 5 6 7 8 9 10)
  fi

  echo "${ratings[$RANDOM % ${#ratings[@]}]}"
}

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  return 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CONSTANTS_FILE="${SCRIPT_DIR}/../constants.ini"
while IFS='=' read -r key value; do
  [[ -n "${key:-}" ]] || continue
  [[ "$key" =~ ^[[:space:]]*# ]] && continue
  [[ "$key" =~ ^[[:space:]]*\[ ]] && continue

  case "$key" in
    CHATBOT_RUUTER_PUBLIC|CHATBOT_RUUTER_PRIVATE|CHATBOT_TRAINING_RESQL|TRAINING_RESQL|DOMAIN|CHAT_GENERATION|CHAT_GENERATION_CSA_ID)
      printf -v "$key" '%s' "$value"
      ;;
  esac
done < "$CONSTANTS_FILE"

require_command curl
require_command jq

CHAT_GENERATION="${CHAT_GENERATION:-True}"

if [[ "$CHAT_GENERATION" != "True" && "$CHAT_GENERATION" != "true" ]]; then
  echo "$(currentTimestamp) - CHAT_GENERATION is set false"
  exit 0
fi

isAuthenticated="${1:-${isAuthenticated:-false}}"
isAuthenticated="$(printf '%s' "$isAuthenticated" | tr '[:upper:]' '[:lower:]')"

case "$isAuthenticated" in
  true|false)
    ;;
  *)
    fail "isAuthenticated must be true or false"
    ;;
esac

PUBLIC_URL="$CHATBOT_RUUTER_PUBLIC"
PRIVATE_URL="$CHATBOT_RUUTER_PRIVATE"
NONCE_RESQL="${CHATBOT_TRAINING_RESQL:-$TRAINING_RESQL}"
DOMAIN="$DOMAIN"

: "${PUBLIC_URL:?CHATBOT_RUUTER_PUBLIC must be set in $CONSTANTS_FILE}"
: "${PRIVATE_URL:?CHATBOT_RUUTER_PRIVATE must be set in $CONSTANTS_FILE}"
: "${NONCE_RESQL:?TRAINING_RESQL or CHATBOT_TRAINING_RESQL must be set in $CONSTANTS_FILE}"
: "${DOMAIN:?DOMAIN must be set in $CONSTANTS_FILE}"

END_USER_MESSAGE="${CHAT_GENERATION_END_USER_MESSAGE:-Virtuaalne vestlusrobot ärkab sõnade kaudu ellu, jäljendades inimlikku rütmi ja tooni. Tehisintellekti loodud vastused voolavad katkestusteta, justkui sulanduksid need päris vestluse öö voogu.}"
MOCK_END_USER_ID="${CHAT_GENERATION_END_USER_ID:-EE60001019906}"
MOCK_END_USER_FIRST_NAME="${CHAT_GENERATION_END_USER_FIRST_NAME:-Mari}"
MOCK_END_USER_LAST_NAME="${CHAT_GENERATION_END_USER_LAST_NAME:-Maasikas}"
MOCK_CSA_ID="${CHAT_GENERATION_CSA_ID:-EE30303039914}"
MOCK_CSA_FIRST_NAME="${CHAT_GENERATION_CSA_FIRST_NAME:-Automation}"
MOCK_CSA_LAST_NAME="${CHAT_GENERATION_CSA_LAST_NAME:-CSA}"

HOLIDAYS='["2025-01-01","2025-02-24","2025-04-18","2025-04-20","2025-05-01","2025-06-08","2025-06-23","2025-06-24","2025-08-20","2025-12-24","2025-12-25","2025-12-26"]'
HOLIDAY_NAMES='2025-01-01-uusaasta,2025-02-24-iseseisvuspäev,2025-04-18-suur reede,2025-04-20-lihavõtted,2025-05-01-kevadpüha,2025-06-08-nelipühade 1. püha,2025-06-23-võidupüha,2025-06-24-jaanipäev,2025-08-20-taasiseseisvumispäev,2025-12-24-jõululaupäev,2025-12-25-esimene jõulupüha,2025-12-26-teine jõulupüha'
END_USER_OS='Agent: Firefox (v143.0), OS: Ubuntu (vnone), device: unknown'
script_name=$(basename "$0")
echo "$(currentTimestamp) - $script_name started"

headers=$(mktemp)
body=$(mktemp)
trap 'rm -f "$headers" "$body"' EXIT

get_new_nonce() {
  local response
  local nonce

  response=$(curl -s -X POST -H "Content-Type: application/json" "$NONCE_RESQL/get-new-nonce")
  nonce=$(echo "$response" | grep -Eo "([a-f0-9-]+-){4}[a-f0-9-]+")

  [[ -n "$nonce" ]] || fail "Failed to get nonce"
  echo "$nonce"
}

mock_chat_message() {
  local author_role="$1"
  local content="$2"
  local event="${3:-}"
  local silent="${4:-true}"
  local author_id="${5:-}"
  local author_first_name="${6:-}"
  local author_last_name="${7:-}"
  local rating="${8:-}"
  local payload

  payload=$(jq -n \
    --arg content "$content" \
    --arg event "$event" \
    --arg authorRole "$author_role" \
    --arg authorId "$author_id" \
    --arg authorFirstName "$author_first_name" \
    --arg authorLastName "$author_last_name" \
    --arg rating "$rating" \
    --arg ts "$(currentTimestamp)" \
    --argjson holidays "$HOLIDAYS" \
    --arg holidayNames "$HOLIDAY_NAMES" \
    --arg domain "$DOMAIN" \
    --argjson silent "$silent" \
    '{
      message: {
        content: $content,
        authorTimestamp: $ts,
        authorId: $authorId,
        authorFirstName: $authorFirstName,
        authorLastName: $authorLastName,
        authorRole: $authorRole,
        event: $event,
        rating: $rating
      },
      holidays: $holidays,
      holidayNames: $holidayNames,
      domain: $domain,
      silent: $silent
    }')

  request POST "$PRIVATE_URL/cron-tasks/chat-generation/message" "$payload" "chatJwt=$chat_jwt" "$headers" "$body"
}

echo "$(currentTimestamp) - Opening chat"
initial_message=$(jq -n \
  --arg ts "$(currentTimestamp)" \
  --arg domain "$DOMAIN" \
  --argjson holidays "$HOLIDAYS" \
  --arg holidayNames "$HOLIDAY_NAMES" \
  --arg endUserOs "$END_USER_OS" \
  '{
    message: {
      content: "Tere",
      authorTimestamp: $ts,
      authorRole: "end-user"
    },
    endUserTechnicalData: {
      endUserUrl: $domain,
      endUserOs: $endUserOs
    },
    holidays: $holidays,
    holidayNames: $holidayNames,
    domain: $domain
  }')
request POST "$PUBLIC_URL/chats/init" "$initial_message" "" "$headers" "$body"

chat_id=$(response_value "$body" '.response.id // .id')
chat_jwt=$(extract_cookie chatJwt "$headers")
[[ -n "$chat_id" ]] || fail "Failed to get chat id"
[[ -n "$chat_jwt" ]] || fail "Failed to extract chatJwt"
echo "$(currentTimestamp) - chat-id: $chat_id"

echo "$(currentTimestamp) - Mocking conversation state with messages/mock"
mock_chat_message "end-user" "$END_USER_MESSAGE" "" true

if [[ "$isAuthenticated" == "true" ]]; then
  echo "$(currentTimestamp) - Mocking transfer to CSA queue"
  mock_chat_message "buerokratt" "" "forwarded_to_backoffice" true
  
  echo "$(currentTimestamp) - Mocking CSA takeover"
  mock_chat_message "buerokratt" "" "taken-over" true
  echo "$(currentTimestamp) - Mocking CSA authentication request"
  mock_chat_message "backoffice-user" "Palun autentige ennast, et saaksime vestlusega jätkata." "requested-authentication" true "$MOCK_CSA_ID"
  echo "$(currentTimestamp) - Mocking end-user authentication success"
  mock_chat_message "end-user" "" "user-authenticated" true "$MOCK_END_USER_ID" "$MOCK_END_USER_FIRST_NAME" "$MOCK_END_USER_LAST_NAME"
  
  echo "$(currentTimestamp) - Inserting chat base data to database"
  # Inserts dummy rows to database
  # End goal is to create realistic test data for analytics and reporting, where chat base data is required,
  # but without relying on actual chat creation flows which may have side effects or require complex setup
  payload=$(jq -n \
      --arg chatBaseId "$chat_id" \
      --arg customerSupportId "$MOCK_CSA_ID" \
      --arg domain "$DOMAIN" \
      --arg endUserOs "$END_USER_OS" \
      '{
        id: $chatBaseId,
        customerSupportId: $customerSupportId,
        customerSupportDisplayName: "Automation CSA",
        csaTitle: "Customer Support Agent Automation",
        endUserUrl: $domain,
        endUserOs: $endUserOs
      }')
  request POST "$PRIVATE_URL/cron-tasks/chat-generation/insert-chat" "$payload" "chatJwt=$chat_jwt" "$headers" "$body"
  
  payload=$(jq -n \
      --arg chatBaseId "$chat_id" \
      --arg customerSupportId "$MOCK_CSA_ID" \
      --arg domain "$DOMAIN" \
      --arg endUserOs "$END_USER_OS" \
      '{
        id: $chatBaseId,
        customerSupportId: $customerSupportId,
        customerSupportDisplayName: "Automation CSA",
        csaTitle: "Customer Support Agent Automation",
        endUserUrl: $domain,
        endUserOs: $endUserOs,
        endUserFirstName: "Mari",
        endUserLastName: "Maasikas",
        endUserId: "EE60001019906"
      }')
  request POST "$PRIVATE_URL/cron-tasks/chat-generation/insert-chat" "$payload" "chatJwt=$chat_jwt" "$headers" "$body"
  
  
  echo "$(currentTimestamp) - Fetching feedback scale configuration"
  feedback_config_payload=$(jq -n --arg domain "$DOMAIN" '{domain: $domain}')
  request POST "$PRIVATE_URL/cron-tasks/chat-generation/feedback-config" "$feedback_config_payload" "chatJwt=$chat_jwt" "$headers" "$body"
  is_five_rating_scale=$(response_value "$body" '.response.isFiveRatingScale // .isFiveRatingScale')
  [[ -n "$is_five_rating_scale" ]] || fail "Failed to determine feedback scale"

  rating="$(pick_feedback_rating "$is_five_rating_scale")"
  echo "$(currentTimestamp) - End-user selects feedback rating $rating (scale: $([[ "$is_five_rating_scale" == "true" ]] && echo "5-point" || echo "10-point"))"
  rating_payload=$(jq -n \
    --arg chatId "$chat_id" \
    --argjson rating "$rating" \
    '{chatId: $chatId, feedbackRating: $rating}')
  request POST "$PUBLIC_URL/chats/feedbacks/rating" "$rating_payload" "chatJwt=$chat_jwt" "$headers" "$body"
fi 
events=(
  "CLIENT_LEFT_WITH_ACCEPTED"
  "CLIENT_LEFT_WITH_NO_RESOLUTION"
  "CLIENT_LEFT_FOR_UNKNOWN_REASONS"
  "ACCEPTED"
  "HATE_SPEECH"
  "OTHER"
  "RESPONSE_SENT_TO_CLIENT_EMAIL"
)

event_index_file="${CHAT_GENERATION_EVENT_INDEX_FILE:-/tmp/new_chat_generation1_event_index}"
if [[ ! -f "$event_index_file" ]]; then
  echo 0 > "$event_index_file"
fi

index=$(cat "$event_index_file")
[[ "$index" =~ ^[0-9]+$ ]] || index=0
event=${events[$((index % ${#events[@]}))]}
next_index=$(((index + 1) % ${#events[@]}))
echo "$next_index" > "$event_index_file"

echo "$(currentTimestamp) - End-user closes widget from X with status $event"
terminate_payload=$(jq -n \
  --arg chatId "$chat_id" \
  --arg event "$event" \
  --arg ts "$(currentTimestamp)" \
  '{
    message: {
      chatId: $chatId,
      authorTimestamp: $ts,
      authorRole: "end-user",
      event: $event
    },
    status: "ENDED"
  }')
request POST "$PUBLIC_URL/chats/end" "$terminate_payload" "chatJwt=$chat_jwt" "$headers" "$body"

if [[ "$isAuthenticated" == "true" ]]; then
  echo "$(currentTimestamp) - $script_name finished; authenticated chat $chat_id ended with $event and feedback $rating"
else
  echo "$(currentTimestamp) - $script_name finished; anonymous chat $chat_id ended with $event"
fi
