.PHONY: build

all    :  build;
build  :; DAPP_BUILD_OPTIMIZE=1 DAPP_BUILD_OPTIMIZE_RUNS=0 dapp --use solc:0.6.12 build
clean  :; dapp clean
test   :; ./test.sh
deploy :; dapp create Univ2LpOracle
