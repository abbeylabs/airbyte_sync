#!/bin/bash

# Check that config file exists
CONFIG_FILE=$1
if [ ! -f "${CONFIG_FILE}" ]
then
    echo 'Config file is required. Usage:'
    echo '    bash ./configure_connection.sh <path to config.yml>'
    echo 'See sample_config.yml'
    exit 1
else
    echo "Config file: ${CONFIG_FILE}"
fi

# Let's check first that required variables with secrets are set
if [ -z "${GITHUB_PERSONAL_ACCESS_TOKEN}" ]
then
    echo 'GITHUB_PERSONAL_ACCESS_TOKEN env variable is not set. Set it to personal access token created on Github'
    exit 1
fi

if [ -z "${GCP_CREDENTIALS_JSON}" ]
then
    echo 'GCP_CREDENTIALS_JSON env variable is not set. Set it to json authentication file for GCP system account with write access to BigQuery'
    exit 1
fi

# ensure we have correct structure for configuration
mkdir work_files
mkdir work_files/config
mkdir -p work_files/config/sources/github_custom
mkdir -p work_files/config/destinations/bigquery
mkdir -p work_files/config/connections/github_to_bigquery

# Install jq and yq
function jq() {
    docker run --rm -i stedolan/jq $@
}
function yq() {
  docker run --rm -i -v "${PWD}":/workdir mikefarah/yq "$@"
}

echo "Testing jq:"
cat ./work_files/create_source_definition.json | jq '.sourceDefinitionId'
echo "Testing yq:"
cat ./docker-compose.yml | yq '.version'

# Configure octavia
echo "OCTAVIA_ENABLE_TELEMETRY=False" > ~/.octavia

# First, we need to get the id of source definition
if [ ! -f ./work_files/source_definition_id ]
then
    echo "Creating github_custom source definition"
    curl -d '{ "name": "github_custom", "dockerRepository": "dkishylau/source-github", "dockerImageTag": "0.2.34", "documentationUrl": "http://example.com"}' \
        -H 'Content-Type: application/json' \
        -X POST \
        http://localhost:8000/api/v1/source_definitions/create > ./work_files/create_source_definition.json
    if [ $? -ne 0 ]
    then
        echo "Failed to create github_custom source definition"
        exit 1
    fi
    cat ./work_files/create_source_definition.json | jq '.sourceDefinitionId' > ./work_files/source_definition_id
else
    echo "Using existing github_custom source definition"
fi

export SOURCE_DEFINITION_ID=$(cat ./work_files/source_definition_id)
export GITHUB_REPOSITORY=$(cat "${CONFIG_FILE}" | yq ".github.repository_filter")
export GITHUB_START_DATE=$(cat "${CONFIG_FILE}" | yq ".github.start_date")
export BIGQUERY_DATASET_ID=$(cat "${CONFIG_FILE}" | yq ".bigquery.dataset_id")
export BIGQUERY_PROJECT_ID=$(cat "${CONFIG_FILE}" | yq ".bigquery.project_id")

# Generate source and destination configs
cat templates/source.yaml.templ | envsubst '$SOURCE_DEFINITION_ID $GITHUB_REPOSITORY $GITHUB_START_DATE $GITHUB_PERSONAL_ACCESS_TOKEN' > ./work_files/config/sources/github_custom/configuration.yaml
cat templates/destination.yaml.templ | envsubst '$BIGQUERY_DATASET_ID $BIGQUERY_PROJECT_ID $GCP_CREDENTIALS_JSON' > ./work_files/config/destinations/bigquery/configuration.yaml

echo 'Running Octavia'
function octavia() {
    docker run -i --rm -v $(pwd)/work_files/config:/home/octavia-project --network host --env-file ~/.octavia --user $(id -u):$(id -g) airbyte/octavia-cli:0.36.4-alpha $@
}
# Now we need to run octavia and create/update source and destination
octavia apply --force --file ./sources/github_custom/configuration.yaml
if [ $? -ne 0 ]
then
    echo "Failed to create source"
    exit 1
fi

octavia apply --force --file ./destinations/bigquery/configuration.yaml
if [ $? -ne 0 ]
then
    echo "Failed to create destination"
    exit 1
fi
# Delete config files, because of secrets in them
rm ./work_files/config/sources/github_custom/configuration.yaml
rm ./work_files/config/destinations/bigquery/configuration.yaml

# Extract source and destination identifiers so that we can use them in the connection file
export SOURCE_ID=$(cat ./work_files/config/sources/github_custom/state.yaml | yq ".resource_id")
export DESTINATION_ID=$(cat ./work_files/config/destinations/bigquery/state.yaml | yq ".resource_id")

# We also need to create an operation for connection
# First, get workspace id
export WORKSPACE_ID=$(curl -H 'Content-Type: application/json' -X POST http://localhost:8000/api/v1/workspaces/list | jq ".workspaces[0].workspaceId")
if [ $? -ne 0 ]
then
    echo "Failed to get active workspace"
    exit 1
fi

# Create an operation
if [ ! -f ./work_files/operation_id ]
then
    echo "Creating normalization operation"
    curl -d '{ "workspaceId": '${WORKSPACE_ID}', "name": "Normalization", "operatorConfiguration": {"operatorType": "normalization", "normalization": { "option": "basic"},"dbt": null}}' \
        -H 'Content-Type: application/json' -X POST http://localhost:8000/api/v1/operations/create > ./work_files/operation_create.json
    if [ $? -ne 0 ]
    then
        echo "Failed to create normalization operation"
        exit 1
    fi

    cat ./work_files/operation_create.json | jq ".operationId" > ./work_files/operation_id
else
    echo "Using existing operation id"
fi

export OPERATION_ID=$(cat ./work_files/operation_id)

cat templates/connection.yaml.templ | envsubst '$SOURCE_ID $DESTINATION_ID $OPERATION_ID' > ./work_files/config/connections/github_to_bigquery/configuration.yaml

octavia apply --force --file ./connections/github_to_bigquery/configuration.yaml

if [ $? -ne 0 ]
then
    echo "Failed to create connection configuration"
    exit 1
fi
# Save connection id in a file, so that we can use it
cat ./work_files/config/connections/github_to_bigquery/state.yaml | yq ".resource_id" > ./work_files/connection_id
