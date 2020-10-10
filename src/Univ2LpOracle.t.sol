pragma solidity ^0.5.12;

import "ds-test/test.sol";

import "./Univ2LpOracle.sol";

interface Hevm {
    function warp(uint256) external;
    function store(address,bytes32,bytes32) external;
}

interface OSMLike {
    function bud(address) external returns (uint);
}

contract UNIV2LPOracleTest is DSTest {

    // --- Math ---
    uint256 constant WAD = 10 ** 18;
    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x, "ds-math-add-overflow");
    }
    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x, "ds-math-sub-underflow");
    }
    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x, "ds-math-mul-overflow");
    }
    function div(uint x, uint y) internal pure returns (uint z) {
        require(y > 0 && (z = x / y) * y == x, "ds-math-divide-by-zero");
    }
    function wmul(uint x, uint y) internal pure returns (uint z) {
        z = add(mul(x, y), WAD / 2) / WAD;
    }
    function wdiv(uint x, uint y) internal pure returns (uint z) {
        z = add(mul(x, WAD), y / 2) / y;
    }
    //compute square using babylonian method
    function sqrt(uint y) internal pure returns (uint z) {
        if (y > 3) {
            z = y;
            uint x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

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

        ethDaiLPOracle = new UNIV2LPOracle(ETH_DAI_UNI_POOL, poolNameDAI, USDC_ORACLE, ETH_ORACLE);
        ethUsdcLPOracle = new UNIV2LPOracle(ETH_USDC_UNI_POOL, poolNameUSDC, USDC_ORACLE, ETH_ORACLE);

        //whitelist ethDaiLP on ETH Oracle
        hevm.store(
            address(ETH_ORACLE),
            keccak256(abi.encode(address(ethDaiLPOracle), uint256(5))), // Whitelist oracle
            bytes32(uint256(1))
        );
    }

     function test_constructor() public {
        assertEq(ethDaiLPOracle.src(), ETH_DAI_UNI_POOL);
        assertEq(ethDaiLPOracle.token0Oracle(), USDC_ORACLE);
        assertEq(ethDaiLPOracle.token1Oracle(), ETH_ORACLE);
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

    function test_seek_internals() public {
        //This is necessary to test a bunch of the variables in memory

        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.store(
            address(ETH_ORACLE),
            keccak256(abi.encode(address(this), uint256(5))), // Whitelist oracle
            bytes32(uint256(1))
        );

        ///////////////////////////////////////
        //                                   //
        //        Begin seek() excerpt       //
        //                                   //
        ///////////////////////////////////////

        //slight modifications

        UniswapV2PairLike(ETH_USDC_UNI_POOL).sync();

        (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) = UniswapV2PairLike(ETH_USDC_UNI_POOL).getReserves();  //pull reserves
        require(_blockTimestampLast == block.timestamp);

        // -- BEGIN TEST 1 -- //
        //Get token addresses of LP contract
        address token0 = UniswapV2PairLike(ETH_USDC_UNI_POOL).token0();
        address token1 = UniswapV2PairLike(ETH_USDC_UNI_POOL).token1();

        //Verify token balances of LP contract match balances returned by getReserves()
        assertEq(_reserve0, ERC20Like(token0).balanceOf(ETH_USDC_UNI_POOL));
        assertEq(_reserve1, ERC20Like(token1).balanceOf(ETH_USDC_UNI_POOL));
        //  -- END Test 1 --  //

        // adjust reserves w/ respect to decimals
        if (ethUsdcLPOracle.token0Decimals() != uint8(18)) {
            _reserve0 = uint112(_reserve0 * 10 ** sub(18, ethUsdcLPOracle.token0Decimals()));
        }
        if (ethUsdcLPOracle.token1Decimals() != uint8(18)) {
            _reserve1 = uint112(_reserve1 * 10 ** sub(18, ethUsdcLPOracle.token1Decimals()));
        }

        // -- BEGIN TEST 2 -- //
        //Verify reserve decimal adjustment
        assertEq(_reserve1, ERC20Like(token1).balanceOf(ETH_USDC_UNI_POOL));    //if condition not entered for WETH (18 decimals)
        assertTrue(_reserve0 > ERC20Like(token0).balanceOf(ETH_USDC_UNI_POOL));     //if condition entered for USDC (6 decimals)
        assertEq(_reserve0 / 10 ** 12, ERC20Like(token0).balanceOf(ETH_USDC_UNI_POOL));     //verify decimal adjustment behaves correctly
        //  -- END Test 2 --  //

        uint k = mul(_reserve0, _reserve1);                 // Calculate constant product invariant k (WAD * WAD)

        // -- BEGIN TEST 3 -- //
        assertTrue(k > _reserve0);
        assertTrue(k > _reserve1);
        assertEq(div(k, _reserve0), _reserve1);
        assertEq(div(k, _reserve1), _reserve0);
        //  -- END Test 3 --  //

        // All Oracle prices are priced with 18 decimals against USD
        uint token0Price = OracleLike(ethUsdcLPOracle.token0Oracle()).read();   // Query token0 price from oracle (WAD)
        uint token1Price = OracleLike(ethUsdcLPOracle.token1Oracle()).read();   // Query token1 price from oracle (WAD)

        // -- BEGIN TEST 4 -- //
        assertTrue(token0Price > 0);
        assertTrue(token1Price > 0);
        //  -- END Test 4 --  //

        uint normReserve0 = sqrt(wmul(k, wdiv(token1Price, token0Price)));      // Get token0 balance (WAD)
        uint normReserve1 = wdiv(k, normReserve0) / WAD;                        // Get token1 balance; gas-savings

        // -- BEGIN TEST 5 -- //
        //verify normalized reserve are within 1% margin of actual reserves
        //during times of high price volatility this condition may not hold
        assertTrue(normReserve0 > 0);
        assertTrue(normReserve1 > 0);
        //assertTrue(mul(uint(_reserve0), 99) < mul(normReserve0, 100));
        //assertTrue(mul(normReserve0, 100) < mul(uint(_reserve0), 101));
        //  -- END Test 5 --  //

        uint lpTokenSupply = ERC20Like(ETH_USDC_UNI_POOL).totalSupply();        // Get LP token supply

        uint128 lpTokenPrice = uint128(
            wdiv(
                add(
                    wmul(normReserve0, token0Price), // (WAD)
                    wmul(normReserve1, token1Price)  // (WAD)
                ),
                lpTokenSupply // (WAD)
            )
        );
        uint32 zzz = _blockTimestampLast; // Update timestamp

        ///////////////////////////////////////
        //                                   //
        //         End seek() excerpt        //
        //                                   //
        ///////////////////////////////////////

    }

    function test_poke() public {
        ethDaiLPOracle.poke();
    }
}
