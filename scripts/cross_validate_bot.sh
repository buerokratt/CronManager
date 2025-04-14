#!/bin/bash
script_name=`basename $0`
pwd
echo $(date -u +"%Y-%m-%d %H:%M:%S.%3NZ") - $script_name started
. constants.ini

NAMESPACE="a1"
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
    echo "Notifying ruuter ($(date -u +"%Y-%m-%d %H:%M:%S.%3NZ")) - cross validate state: ${state}"
    curl -X POST "$TRAINING_PUBLIC_RUUTER/rasa/model/state" \
         -H "x-ruuter-nonce: $(get_new_nonce)" \
         -H "Content-Type: application/json" \
         -d "{\"state\": \"${state}\"}"
}

cross_validate_bot_job() {
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
    elif helm list -n "$NAMESPACE" | grep -q "cross-validate-bot"; then
        echo "Error: The Helm release 'cross-validate-bot' already exists in namespace '$NAMESPACE'. Exiting..."
        exit 1
    fi

    echo "Deploying cross-validate-bot job..."
    # TODO - docker-compose equivalent job: training-module/docker-compose-bot.yml - test-bot-cv
    # volumes:
    #   - ./DSL/DMapper/training/locations/:/rasa
    # command:
    #   - test
    #   - --nlu 
    #   - /rasa/data/nlu
    #   - --config
    #   - /rasa/data/config.yml
    #   - --domain
    #   - /rasa/data/domain.yml
    #   - --model
    #   - /rasa/models/${MODEL_NAME}.tar.gz
    #   - --cross-validation
    #   - --folds
    #   - "2"
    #   - --out
    #   - /rasa/results/${MODEL_NAME}/cross-validation/
    helm upgrade --install cross-validate-bot "$HELM_REPO_NAME/cross-validate-bot" --namespace "$NAMESPACE" --set serviceAccount.name=cross-validate-bot-sa --create-namespace

    echo "Waiting for cross-validate-bot job to complete..."
    for ((counter=1; counter<=10; counter++)); do
        status=$(kubectl get job cross-validate-bot -n "$NAMESPACE" -o jsonpath='{.status.succeeded}')

        if [ "$status" == "1" ]; then
            echo "Cross-validate-bot job completed."

            cross_validate_report=$(cat /rasa/results/${MODEL_NAME}/cross-validation/intent_report.json)
            MODEL_BODY_PATH="/rasa/results/${MODEL_NAME}/cross-validation/modelBody"
            echo '{
                "filename": "'"$MODEL_NAME"'",
                "testReport": {},
                "crossValidationReport": {
                    "intent_evaluation": {
                        "report": '"$cross_validate_report"'
                    }
                },
                "trainingDataChecksum": ""
            }' > "$MODEL_BODY_PATH" || echo "Failed to create modelBody file"

            curl -X POST -H "x-ruuter-nonce: $(get_new_nonce)" -H "Content-Type: application/json" --data-binary @"$MODEL_BODY_PATH" "$TRAINING_PUBLIC_RUUTER/rasa/model/add-new-model-ready"
            rm -rf /rasa/results/${MODEL_NAME}
        elif [ "$counter" -eq 10 ]; then
            echo "Cross-validate-bot job failed."
            notify_ruuter_with_state "ERROR"
            rm -rf /rasa/results/${MODEL_NAME}
            helm uninstall cross-validate-bot --namespace "$NAMESPACE"
            exit 1
        fi
        sleep 5
    done
}

notify_ruuter_with_state "CROSS_VALIDATING"

cross_validate_bot_job

echo $(date -u +"%Y-%m-%d %H:%M:%S.%3NZ") - $script_name finished
