#!/usr/bin/env bash
set -e

[[ "$ETH_RPC_URL" && "$(seth chain)" == "ethlive"  ]] || { echo "Please set a mainnet ETH_RPC_URL"; exit 1;  }

SOLC_FLAGS="--optimize --optimize-runs 1" dapp --use solc:0.6.7 build

export DAPP_TEST_NUMBER=11367905 # Ensure consistent testing for pricing

# LANG=C.UTF-8 hevm dapp-test --match "quick" --rpc="$ETH_RPC_URL" --json-file=out/dapp.sol.json --dapp-root=. --verbose 1
LANG=C.UTF-8 hevm dapp-test --match seek --rpc="$ETH_RPC_URL" --json-file=out/dapp.sol.json --dapp-root=. --verbose 1
