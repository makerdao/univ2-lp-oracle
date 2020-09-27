pragma solidity ^0.6.7;

import "ds-test/test.sol";

import "./UNIV2LPOracle.sol";

contract UNIV2LPOracleTest is DSTest {
    UNIV2LPOracle oracle;
    address uniswapPool;
    bytes32 poolName = "ETH-USDC-UNIV2-LP";
    address token0Oracle;
    address token1Oracle;

    function setUp() public {
        oracle = new UNIV2LPOracle(uniswapPool, poolName, token0Oracle, token1Oracle);
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }
}
