#!/bin/bash
export CONNECTION_ID=$(cat work_files/connection_id)

curl -d '{ "connectionId": "'${CONNECTION_ID}'"}' \
    -H 'Content-Type: application/json' -X POST http://localhost:8000/api/v1/connections/sync > ./work_files/connections_sync.json