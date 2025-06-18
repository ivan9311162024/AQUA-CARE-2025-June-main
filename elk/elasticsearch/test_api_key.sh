#!/usr/bin/env bash

set -euo pipefail

# Set your API key here
ES_APIKEY=$(bash create_api_key.sh)
ES_URL="https://localhost:9200"

# Example: Query cluster health using API key
curl -k -H "Authorization: ApiKey $ES_APIKEY" \
     "$ES_URL/_cluster/health?pretty"
echo
