curl -s http://localhost:26657/status | jq .result.sync_info

echo "--------------------------------";

curl -s http://localhost:26657/status | jq .result.sync_info.catching_up

echo "--------------------------------";

curl -s http://localhost:26657/status | jq .result.sync_info.latest_block_height

echo "--------------------------------";

curl -s http://localhost:26657/status | jq .result.sync_info.latest_block_time

echo "--------------------------------";

curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' \
  http://localhost:8545 | jq