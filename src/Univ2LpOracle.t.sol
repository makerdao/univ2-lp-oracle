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
    UNIV2LPOracle ethDaiLPOracle;
    UNIV2LPOracle ethUsdcLPOracle;
    
    address constant ETH_DAI_UNI_POOL = 0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11;
    address constant ETH_ORACLE       = 0x81FE72B5A8d1A857d176C3E7d5Bd2679A9B85763;
    address constant USDC_ORACLE      = 0x77b68899b99b686F415d074278a9a16b336085A0; // Using in place for DAI price

    address constant ETH_USDC_UNI_POOL = 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc;
    
    bytes32 poolNameDAI = "ETH-DAI-UNIV2-LP";
    bytes32 poolNameUSDC = "ETH-USDC-UNIV2-LP";

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

        ethDaiLPOracle = new UNIV2LPOracle(ETH_DAI_UNI_POOL, poolNameDAI, ETH_ORACLE, USDC_ORACLE);
        ethUsdcLPOracle = new UNIV2LPOracle(ETH_USDC_UNI_POOL, poolNameUSDC, ETH_ORACLE, USDC_ORACLE);

        //whitelist ethDaiLP on ETH Oracle
        hevm.store(
            address(ETH_ORACLE),
            keccak256(abi.encode(address(ethDaiLPOracle), uint256(5))), // Whitelist oracle
            bytes32(uint256(1))
        );
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }

     function test_constructor() public {
        assertEq(ethDaiLPOracle.src(), ETH_DAI_UNI_POOL);
        assertEq(ethDaiLPOracle.token0Oracle(), ETH_ORACLE);
        assertEq(ethDaiLPOracle.token1Oracle(), USDC_ORACLE);
        assertEq(ethDaiLPOracle.wards(address(this)), 1);
        assertEq(ethDaiLPOracle.stopped(), 0);
    }

    function test_seek_dai() public {
        (uint128 lpTokenPrice, uint32 zzz) = ethDaiLPOracle.seek();
        assertEq(uint256(lpTokenPrice), 1);
    }

    function test_seek_usdc() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.store(
            address(ETH_ORACLE),
            keccak256(abi.encode(address(ethUsdcLPOracle), uint256(5))), // Whitelist oracle
            bytes32(uint256(1))
        );

        (uint128 lpTokenPrice, uint32 zzz) = ethUsdcLPOracle.seek();
        assertEq(uint256(lpTokenPrice), 1);
    }

    function test_poke() public { 
        ethDaiLPOracle.poke();
    }
}
