.PHONY: build

all    :  build;
build  :; ./build.sh
clean  :; dapp clean
test   :; ./test.sh $(match)
deploy :; dapp create Univ2LpOracle
