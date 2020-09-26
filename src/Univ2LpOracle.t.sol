pragma solidity ^0.6.7;

import "ds-test/test.sol";

import "./Univ2LpOracle.sol";

contract Univ2LpOracleTest is DSTest {
    Univ2LpOracle oracle;

    function setUp() public {
        oracle = new Univ2LpOracle();
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }
}
