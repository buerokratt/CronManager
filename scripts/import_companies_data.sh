#!/bin/bash
script_name=`basename $0`
pwd

echo $(date -u +"%Y-%m-%d %H:%M:%S.%3NZ") - $script_name started

service="companies"
unprocessed_dir="/app/services/${service}/unprocessed"
processed_dir="/app/services/${service}/processed"

. constants.ini

mkdir -p "$processed_dir"

find_result=$(find "$unprocessed_dir" -type f -name "*.csv")

if [ -z "$find_result" ]; then
    echo "No CSV files found in $unprocessed_dir"
    exit 0
fi

echo "$find_result" | while read -r file; do
    filename=$(basename "$file")
    dirpath=$(dirname "$file")
    subfolder=$(basename "$dirpath")

    read_csv_response=$(curl -X POST -H "Content-Type: application/json" -d  '{"file_path":"/OpenSearch/services/'$service/unprocessed/$filename'","csv_type":"'$service'"}' "$TRAINING_DMAPPER/parse-csv-to-opensearch-data")

    if [ -n "$read_csv_response" ]; then
        # Split the response into 10,000 line parts because OpenSearch doesn't handle big csv files
        echo "$read_csv_response" | split -l 10000 - $unprocessed_dir/output_part

        for file in $unprocessed_dir/output_part*; do
            echo "Processing $file"
            curl -X POST -H "Content-Type: application/x-ndjson" --data-binary "@$file" "$TRAINING_OPENSEARCH/$service/_bulk"
            rm "$file"
        done
    else
        echo "Error: No data received from OpenSearch."
        exit 1
    fi

    echo "Moving "$unprocessed_dir/$filename" to $processed_dir/$filename"
    mv "$unprocessed_dir/$filename" "$processed_dir/$filename"
done

echo $(date -u +"%Y-%m-%d %H:%M:%S.%3NZ") - $script_name finished