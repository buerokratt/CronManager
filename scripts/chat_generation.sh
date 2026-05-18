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

  if [[ -n "$body" && -n "$cookie" ]]; then
    status=$(curl -sS -w "%{http_code}" -D "$headers_file" -o "$body_file" \
      -X "$method" "$url" \
      -H "Content-Type: application/json" \
      -H "Cookie: $cookie" \
      -d "$body")
  elif [[ -n "$body" ]]; then
    status=$(curl -sS -w "%{http_code}" -D "$headers_file" -o "$body_file" \
      -X "$method" "$url" \
      -H "Content-Type: application/json" \
      -d "$body")
  elif [[ -n "$cookie" ]]; then
    status=$(curl -sS -w "%{http_code}" -D "$headers_file" -o "$body_file" \
      -X "$method" "$url" \
      -H "Cookie: $cookie")
  else
    status=$(curl -sS -w "%{http_code}" -D "$headers_file" -o "$body_file" \
      -X "$method" "$url")
  fi

  [[ "$status" =~ ^2 ]] || fail "$method $url failed with HTTP $status: $(cat "$body_file")"
}

response_value() {
  local body_file="$1"
  local jq_filter="$2"

  jq -er "$jq_filter" < "$body_file"
}

random_uuid() {
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen | tr '[:upper:]' '[:lower:]'
  else
    printf 'test-%s-%s' "$(date +%s)" "$RANDOM"
  fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CONSTANTS_FILE="${SCRIPT_DIR}/../constants.ini"
while IFS='=' read -r key value; do
  [[ -n "${key:-}" ]] || continue
  [[ "$key" =~ ^[[:space:]]*# ]] && continue
  [[ "$key" =~ ^[[:space:]]*\[ ]] && continue

  case "$key" in
    CHATBOT_RUUTER_PUBLIC|CHATBOT_RUUTER_PRIVATE|DOMAIN|CHAT_GENERATION_CSA_ID|CHAT_GENERATION_CSA_PASSWORD)
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

PUBLIC_URL="$CHATBOT_RUUTER_PUBLIC"
PRIVATE_URL="$CHATBOT_RUUTER_PRIVATE"
DOMAIN="$DOMAIN"

: "${CHAT_GENERATION_CSA_ID:?CHAT_GENERATION_CSA_ID must be set in $CONSTANTS_FILE}"
: "${CHAT_GENERATION_CSA_PASSWORD?CHAT_GENERATION_CSA_PASSWORD must be set in $CONSTANTS_FILE}"
CSA_ID="$CHAT_GENERATION_CSA_ID"
CSA_PASSWORD="$CHAT_GENERATION_CSA_PASSWORD"
CSA_DISPLAY_NAME="${CHAT_GENERATION_CSA_DISPLAY_NAME:-Automation CSA}"
CSA_TITLE="${CHAT_GENERATION_CSA_TITLE:-Nõustaja}"
CSA_AUTHORITIES="${CHAT_GENERATION_CSA_AUTHORITIES:-ROLE_CUSTOMER_SUPPORT_AGENT}"

END_USER_ID="${CHAT_GENERATION_END_USER_ID:-EE60001019906}"
END_USER_FIRST_NAME="${CHAT_GENERATION_END_USER_FIRST_NAME:-Mari}"
END_USER_LAST_NAME="${CHAT_GENERATION_END_USER_LAST_NAME:-Maasikas}"
END_USER_EMAIL="${CHAT_GENERATION_END_USER_EMAIL:-mari@maasikas.com}"
END_USER_MESSAGE="${CHAT_GENERATION_END_USER_MESSAGE:-Virtuaalne vestlusrobot ärkab sõnade kaudu ellu, jäljendades inimlikku rütmi ja tooni. Tehisintellekti loodud vastused voolavad katkestusteta, justkui sulanduksid need päris vestluse öö voogu.}"

HOLIDAYS='["2025-01-01","2025-02-24","2025-04-18","2025-04-20","2025-05-01","2025-06-08","2025-06-23","2025-06-24","2025-08-20","2025-12-24","2025-12-25","2025-12-26"]'
HOLIDAY_NAMES='2025-01-01-uusaasta,2025-02-24-iseseisvuspäev,2025-04-18-suur reede,2025-04-20-lihavõtted,2025-05-01-kevadpüha,2025-06-08-nelipühade 1. püha,2025-06-23-võidupüha,2025-06-24-jaanipäev,2025-08-20-taasiseseisvumispäev,2025-12-24-jõululaupäev,2025-12-25-esimene jõulupüha,2025-12-26-teine jõulupüha'

script_name=$(basename "$0")
echo "$(currentTimestamp) - $script_name started"

headers=$(mktemp)
body=$(mktemp)
trap 'rm -f "$headers" "$body"' EXIT

echo "$(currentTimestamp) - Activating CSA $CSA_ID"
csa_login_payload=$(jq -n \
  --arg login "$CSA_ID" \
  --arg password "$CSA_PASSWORD" \
  '{login: $login, password: $password}')
# Logs in the CSA account and stores the returned customJwtCookie for private backoffice requests.
request POST "$PUBLIC_URL/auth/login" "$csa_login_payload" "" "$headers" "$body"
csa_jwt=$(extract_cookie customJwtCookie "$headers")
[[ -n "$csa_jwt" ]] || fail "Failed to extract customJwtCookie from CSA login"

csa_activity_payload=$(jq -n \
  --arg id "$CSA_ID" \
  '{customerSupportActive: true, customerSupportStatus: "online", statusComment: "", userIdCode: $id}')
# Marks the CSA as online so the chat can be assigned to this support agent.
request POST "$PRIVATE_URL/accounts/customer-support-activity" "$csa_activity_payload" "customJwtCookie=$csa_jwt" "$headers" "$body"

echo "$(currentTimestamp) - Opening chat"
initial_message=$(jq -n \
  --arg ts "$(currentTimestamp)" \
  --arg domain "$DOMAIN" \
  --argjson holidays "$HOLIDAYS" \
  --arg holidayNames "$HOLIDAY_NAMES" \
  '{
    message: {
      content: "Tere",
      authorTimestamp: $ts,
      authorRole: "end-user"
    },
    endUserTechnicalData: {
      endUserUrl: $domain,
      endUserOs: "Agent: Firefox (v143.0), OS: Ubuntu (vnone), device: unknown"
    },
    holidays: $holidays,
    holidayNames: $holidayNames,
    domain: $domain
  }')
# Starts a public chat as an anonymous end-user and receives the chat id and chatJwt.
request POST "$PUBLIC_URL/chats/init" "$initial_message" "" "$headers" "$body"

chat_id=$(response_value "$body" '.response.id // .id')
chat_jwt=$(extract_cookie chatJwt "$headers")
[[ -n "$chat_id" ]] || fail "Failed to get chat id"
[[ -n "$chat_jwt" ]] || fail "Failed to extract chatJwt"
echo "$(currentTimestamp) - chat-id: $chat_id"

echo "$(currentTimestamp) - End-user sends message"
end_user_message_payload=$(jq -n \
  --arg chatId "$chat_id" \
  --arg content "$END_USER_MESSAGE" \
  --arg ts "$(currentTimestamp)" \
  --argjson holidays "$HOLIDAYS" \
  --arg holidayNames "$HOLIDAY_NAMES" \
  --arg domain "$DOMAIN" \
  '{
    message: {
      chatId: $chatId,
      content: $content,
      authorTimestamp: $ts,
      authorRole: "end-user"
    },
    holidays: $holidays,
    holidayNames: $holidayNames,
    domain: $domain
  }')
# Adds the configured end-user message to the newly opened chat.
request POST "$PUBLIC_URL/chats/messages/add" "$end_user_message_payload" "chatJwt=$chat_jwt" "$headers" "$body"

echo "$(currentTimestamp) - Transferring chat to CSA queue"
forward_payload=$(jq -n \
  --arg chatId "$chat_id" \
  --arg messageId "$(random_uuid)" \
  --arg ts "$(currentTimestamp)" \
  --argjson holidays "$HOLIDAYS" \
  --arg holidayNames "$HOLIDAY_NAMES" \
  '{
    message: {
      chatId: $chatId,
      id: $messageId,
      authorTimestamp: $ts,
      event: "forwarded_to_backoffice",
      authorRole: "buerokratt"
    },
    holidays: $holidays,
    holidayNames: $holidayNames
  }')
# Forwards the public chat into the backoffice queue for CSA handling.
request POST "$PUBLIC_URL/chats/forwards/forward-to-backoffice" "$forward_payload" "chatJwt=$chat_jwt" "$headers" "$body"

echo "$(currentTimestamp) - Assigning chat to CSA"
assign_payload=$(jq -n \
  --arg chatId "$chat_id" \
  --arg csaId "$CSA_ID" \
  --arg displayName "$CSA_DISPLAY_NAME" \
  --arg title "$CSA_TITLE" \
  '{id: $chatId, customerSupportId: $csaId, customerSupportDisplayName: $displayName, csaTitle: $title}')
# Assigns the queued chat to the logged-in CSA.
request POST "$PRIVATE_URL/chats/claim" "$assign_payload" "customJwtCookie=$csa_jwt" "$headers" "$body"

echo "$(currentTimestamp) - CSA asks end-user to authenticate"
csa_message_payload=$(jq -n \
  --arg chatId "$chat_id" \
  --arg csaId "$CSA_ID" \
  --arg displayName "$CSA_DISPLAY_NAME" \
  --arg ts "$(currentTimestamp)" \
  '{
    chatId: $chatId,
    authorId: $csaId,
    authorFirstName: $displayName,
    authorRole: "backoffice-user",
    authorTimestamp: $ts,
    content: "Palun autentige ennast, et saaksime vestlusega jätkata.",
    event: "requested-authentication"
  }')
# Inserts the CSA authentication request message into the chat.
request POST "$PRIVATE_URL/agents/chats/messages/insert" "$csa_message_payload" "customJwtCookie=$csa_jwt" "$headers" "$body"

echo "$(currentTimestamp) - Mock end-user authenticates"
tara_payload=$(jq -n \
  --arg idCode "$END_USER_ID" \
  --arg displayName "$END_USER_FIRST_NAME $END_USER_LAST_NAME" \
  --arg firstName "$END_USER_FIRST_NAME" \
  --arg lastName "$END_USER_LAST_NAME" \
  --arg email "$END_USER_EMAIL" \
  --arg fullName "$END_USER_FIRST_NAME $END_USER_LAST_NAME" \
  '{
    idCode: $idCode,
    displayName: $displayName,
    firstName: $firstName,
    lastName: $lastName,
    csaEmail: $email,
    csaTitle: "",
    authorities: "ROLE_END_USER",
    authMethod: "id-card",
    fullName: $fullName
  }')
# Mocks TARA authentication for the end-user and stores the returned JWTTOKEN.
request POST "$PUBLIC_URL/auth/tara/login" "$tara_payload" "" "$headers" "$body"
tara_jwt=$(extract_cookie JWTTOKEN "$headers")
[[ -n "$tara_jwt" ]] || fail "Failed to extract JWTTOKEN"
# Resolves the authenticated end-user name and refreshes the userJwt cookie used by later chat requests.
request GET "$PUBLIC_URL/chats/users/name" "" "chatJwt=$chat_jwt; JWTTOKEN=$tara_jwt" "$headers" "$body"
user_jwt=$(extract_cookie userJwt "$headers")

# Note: to support both ranges 1-10 and 1-5
ratings=(1 2 3 4 5)
rating="${ratings[$RANDOM % ${#ratings[@]}]}"
echo "$(currentTimestamp) - End-user selects feedback rating $rating"
rating_payload=$(jq -n \
  --arg chatId "$chat_id" \
  --argjson rating "$rating" \
  '{chatId: $chatId, feedbackRating: $rating}')
# Saves a random feedback rating for the authenticated chat.
request POST "$PUBLIC_URL/chats/feedbacks/rating" "$rating_payload" "chatJwt=$chat_jwt${user_jwt:+; userJwt=$user_jwt}" "$headers" "$body"

events=(
  "CLIENT_LEFT_WITH_ACCEPTED"
  "CLIENT_LEFT_WITH_NO_RESOLUTION"
  "CLIENT_LEFT_FOR_UNKNOWN_REASONS"
  "ACCEPTED"
  "HATE_SPEECH"
  "OTHER"
  "RESPONSE_SENT_TO_CLIENT_EMAIL"
)

event_index_file="${CHAT_GENERATION_EVENT_INDEX_FILE:-/tmp/authenticated_chat_event_index}"
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
# Ends the chat with the rotating closure event and marks it as ENDED.
request POST "$PUBLIC_URL/chats/end" "$terminate_payload" "chatJwt=$chat_jwt${user_jwt:+; userJwt=$user_jwt}" "$headers" "$body"

echo "$(currentTimestamp) - $script_name finished; authenticated chat $chat_id ended with $event and feedback $rating"
