pragma solidity ^0.5.12;

import "ds-test/test.sol";

import "./UNIV2LPOracle.sol";

interface Hevm {
    function warp(uint256) external;
    function store(address,bytes32,bytes32) external;
}

interface OSMLike {
    function bud(address) external returns (uint);
}

contract UNIV2LPOracleTest is DSTest {
    Hevm          hevm;
    UNIV2LPOracle oracle;
    
    address constant ETH_DAI_UNI_POOL = 0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11;
    address constant ETH_ORACLE       = 0x81FE72B5A8d1A857d176C3E7d5Bd2679A9B85763;
    address constant USDC_ORACLE      = 0x77b68899b99b686F415d074278a9a16b336085A0; // Using in place for DAI price
    
    bytes32 poolName = "ETH-DAI-UNIV2-LP";

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

        oracle = new UNIV2LPOracle(ETH_DAI_UNI_POOL, poolName, ETH_ORACLE, USDC_ORACLE);

        hevm.store(
            address(ETH_ORACLE),
            keccak256(abi.encode(address(oracle), uint256(5))), // Whitelist oracle
            bytes32(uint256(1))
        );
    }

    // function testFail_basic_sanity() public {
    //     assertTrue(false);
    // }

    // function test_basic_sanity() public {
    //     assertTrue(true);
    // }

    function test_seek() public {
        (uint128 lpTokenPrice, uint32 zzz) = oracle.seek();
        assertEq(uint256(lpTokenPrice), 1);
    }
}
