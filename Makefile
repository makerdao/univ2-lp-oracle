all    :; dapp --use solc:0.6.11 build
clean  :; dapp clean
test   :; ./test.sh
deploy :; dapp create Univ2LpOracle
