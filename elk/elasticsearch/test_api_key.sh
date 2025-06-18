#!/usr/bin/env bash

set -euo pipefail

# Set your API key here
# 從 apikey.txt 讀取 API key
if [ ! -f "./apikey.txt" ]; then
  echo "❌ apikey.txt 不存在，請先執行 create_api_key.sh"
  exit 1
fi

ES_APIKEY=$(cat ./apikey.txt)
ES_URL="https://localhost:9200"

# Example: Query cluster health using API key
curl -k -H "Authorization: ApiKey $ES_APIKEY" \
     "$ES_URL/_cluster/health?pretty"
echo
