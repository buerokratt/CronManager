#!/bin/bash
script_name=`basename $0`
pwd
echo $(date -u +"%Y-%m-%d %H:%M:%S.%3NZ") - $script_name started
. constants.ini

NAMESPACE="$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)"
HELM_REPO_NAME="train"
MODEL_NAME="$1"

get_new_nonce() {
  response=$(curl -s -X POST -H "Content-Type: application/json" "$TRAINING_RESQL/get-new-nonce")
  nonce=$(echo "$response" | grep -Eo "([a-f0-9-]+-){4}[a-f0-9-]+")
  if [[ -z "$nonce" ]]; then
    echo "Failed to retrieve nonce!" >&2
    exit 1
  fi
  echo "$nonce"
}

notify_ruuter_with_state() {
    local state="$1"
    echo "Notifying ruuter ($(date -u +"%Y-%m-%d %H:%M:%S.%3NZ")) - testing state: ${state}"
    curl -X POST "$TRAINING_PUBLIC_RUUTER/rasa/model/state" \
         -H "x-ruuter-nonce: $(get_new_nonce)" \
         -H "Content-Type: application/json" \
         -d "{\"state\": \"${state}\"}"
}

test_bot_job() {
    # Pre-flight Checks
    if [ -z "$NAMESPACE" ]; then
        echo "Error: Failed to retrieve the namespace!" >&2
        exit 1
    elif [ -z "$MODEL_NAME" ]; then
        echo "Error: Failed to retrieve the model name!"
        exit 1
    elif ! kubectl cluster-info &>/dev/null; then
        echo "Error: No Kubernetes cluster is available!" >&2
        exit 1
    elif helm list -n "$NAMESPACE" | grep -q "test-bot"; then
        echo "Error: The Helm release 'test-bot' already exists in namespace '$NAMESPACE'. Exiting..."
        exit 1
    fi

    echo "Deploying test-bot job..."
    # TODO - docker-compose equivalent job: training-module/docker-compose-bot.yml - test-bot
    # volumes:
    #   - ./DSL/DMapper/training/locations/:/rasa
    # command:
    #   - test
    #   - --nlu
    #   - /rasa/tests
    #   - --model
    #   - /rasa/models/${MODEL_NAME}.tar.gz
    #   - --out
    #   - /rasa/results/${MODEL_NAME}/test/
    helm upgrade --install test-bot "$HELM_REPO_NAME/test-bot" --namespace "$NAMESPACE" --set serviceAccount.name=test-bot-sa --create-namespace

    echo "Waiting for test-bot job to complete..."
    for ((counter=1; counter<=10; counter++)); do
        status=$(kubectl get job test-bot -n "$NAMESPACE" -o jsonpath='{.status.succeeded}')

        if [ "$status" == "1" ]; then
            echo "Test-bot job completed."

            test_report=$(cat /rasa/results/${MODEL_NAME}/test/intent_report.json)
            MODEL_BODY_PATH="/rasa/results/${MODEL_NAME}/test/modelBody"
            echo '{
                "filename": "'"$MODEL_NAME"'",
                "testReport": '"$test_report"',
                "crossValidationReport": {},
                "trainingDataChecksum": ""
            }' > "$MODEL_BODY_PATH" || echo "Failed to create modelBody file"

            curl -X POST -H "x-ruuter-nonce: $(get_new_nonce)" -H "Content-Type: application/json" --data-binary @"$MODEL_BODY_PATH" "$TRAINING_PUBLIC_RUUTER/rasa/model/add-new-model-ready"
            rm -rf /rasa/results/${MODEL_NAME}
        elif [ "$counter" -eq 10 ]; then
            echo "Test-bot job failed."
            notify_ruuter_with_state "ERROR"
            rm -rf /rasa/results/${MODEL_NAME}
            helm uninstall test-bot --namespace "$NAMESPACE"
            exit 1
        fi
        sleep 5
    done
}

notify_ruuter_with_state "TESTING"

test_bot_job

echo $(date -u +"%Y-%m-%d %H:%M:%S.%3NZ") - $script_name finished
