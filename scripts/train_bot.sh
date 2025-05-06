#!/bin/bash
script_name=`basename $0`
pwd
script_dir=$(cd "$(dirname "$0")" && pwd)
echo $(date -u +"%Y-%m-%d %H:%M:%S.%3NZ") - $script_name started
. "$script_dir/constants.ini"

NAMESPACE="$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)"
HELM_REPO_NAME="train"
MODEL_NAME=$(date +'%Y%m%d-%H%M%S')-rasa-model

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
    echo "Notifying ruuter ($(date -u +"%Y-%m-%d %H:%M:%S.%3NZ")) - training state: ${state}"
    curl -X POST "$TRAINING_PUBLIC_RUUTER/rasa/model/state" \
         -H "x-ruuter-nonce: $(get_new_nonce)" \
         -H "Content-Type: application/json" \
         -d "{\"state\": \"${state}\"}"
}

train_bot_job() {
    # Pre-flight Checks
    if [ -z "$NAMESPACE" ]; then
        echo "Error: Failed to retrieve the namespace!" >&2
        exit 1
    elif ! kubectl cluster-info &>/dev/null; then
        echo "Error: No Kubernetes cluster is available!" >&2
        exit 1
    elif helm list -n "$NAMESPACE" | grep -q "train-bot"; then
        echo "Error: The Helm release 'train-bot' already exists in namespace '$NAMESPACE'. Exiting..."
        exit 1
    fi

    echo "Deploying train-bot job..."
    # TODO - docker-compose equivalent job: training-module/docker-compose-bot.yml - train-bot
    # volumes:
    #   - ./DSL/DMapper/training/locations/:/rasa
    # command:
    #   - train
    #   - --data
    #   - /rasa/data
    #   - --config
    #   - /rasa/data/config.yml
    #   - --domain
    #   - /rasa/data/domain.yml
    #   - --out
    #   - /rasa/models
    #   - --fixed-model-name
    #   - ${MODEL_NAME}
    #   - --force
    helm upgrade --install train-bot "$HELM_REPO_NAME/train-bot" --namespace "$NAMESPACE" --set modelName="$MODEL_NAME" --set serviceAccount.name=train-bot-sa --create-namespace

    echo "Waiting for train-bot job to complete..."
    for ((counter=1; counter<=10; counter++)); do
        status=$(kubectl get job train-bot -n "$NAMESPACE" -o jsonpath='{.status.succeeded}')

        if [ "$status" == "1" ]; then
            echo "Train-bot job completed."
        elif [ "$counter" -eq 10 ]; then
            echo "Train-bot job failed."
            notify_ruuter_with_state "ERROR"
            helm uninstall train-bot --namespace "$NAMESPACE"
            exit 1
        fi
        sleep 5
    done
}

processing_res=$(curl -H "x-ruuter-nonce: $(get_new_nonce)" "$TRAINING_PUBLIC_RUUTER/rasa/model/add-new-model-processing")
echo $(date -u +"%Y-%m-%d %H:%M:%S.%3NZ") - $processing_res

train_bot_job

copy_file_body_dto='{"destinationFilePath":"'$MODEL_NAME'","destinationStorageType":"S3","sourceFilePath":"'$MODEL_NAME'","sourceStorageType":"FS"}'
copy_file_response=$(curl -s -w "%{http_code}" -X POST -H "Content-Type: application/json" -d "$copy_file_body_dto" "$S3_FERRY_TRAIN/v1/files/copy")
copy_file_status="${copy_file_response: -3}"
if [ "$copy_file_status" != "201" ]; then
    echo "Copying file from local to remote storage failed with status code $copy_file_status"
    notify_ruuter_with_state "ERROR"
    rm /rasa/models/$MODEL_NAME
    exit 1
fi

add_new_model_body_dto='{"fileName":"'$MODEL_NAME'","testReport":{},"crossValidationReport":{},"trainingDataChecksum":""}'
ready_res=$(curl -X POST -H "x-ruuter-nonce: $(get_new_nonce)" -H "Content-Type: application/json" -d "$add_new_model_body_dto" "$TRAINING_PUBLIC_RUUTER/rasa/model/add-new-model-ready")
echo $(date -u +"%Y-%m-%d %H:%M:%S.%3NZ") - $ready_res

if $test; then
    /app/scripts/test_bot.sh "$MODEL_NAME"
    if [ $? -ne 0 ]; then
        echo "test_bot.sh failed. Stopping execution."
        rm /rasa/models/$MODEL_NAME
        exit 1
    fi

    /app/scripts/cross_validate_bot.sh "$MODEL_NAME"
fi

rm /rasa/models/$MODEL_NAME
echo $(date -u +"%Y-%m-%d %H:%M:%S.%3NZ") - $script_name finished
