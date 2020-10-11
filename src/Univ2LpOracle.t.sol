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
        assertEq(ethDaiLPOracle.src(), ETH_DAI_UNI_POOL);                   //verify source is ETH-DAI pool
        assertEq(ethDaiLPOracle.token0Oracle(), USDC_ORACLE);               //verify token 0 oracle is USDC oracle
        assertEq(ethDaiLPOracle.token1Oracle(), ETH_ORACLE);                //verify token 1 oracle is ETH oracle
        assertEq(ethDaiLPOracle.wards(address(this)), 1);                   //verify owner
        assertEq(ethDaiLPOracle.stopped(), 0);                              //verify contract active
    }

    function test_seek_dai() public {
        (uint128 lpTokenPrice, uint32 zzz) = ethDaiLPOracle.seek();         //get new eth-dai lp price from uniswap
        //assertEq(uint256(lpTokenPrice), 1);
    }

    function test_seek_usdc() public {
        hevm.store(
            address(ETH_ORACLE),
            keccak256(abi.encode(address(ethUsdcLPOracle), uint256(5))),    //whitelist oracle
            bytes32(uint256(1))
        );
        (uint128 lpTokenPrice, uint32 zzz) = ethUsdcLPOracle.seek();        //get new eth-usdc lp price from uniswap
        //assertEq(uint256(lpTokenPrice), 1);
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

        // -- BEGIN TEST 5 -- //
        assertTrue(token0Price > 0);
        assertTrue(token1Price > 0);
        //  -- END Test 5 --  //

        uint normReserve0 = sqrt(wmul(k, wdiv(token1Price, token0Price)));      // Get token0 balance (WAD)
        uint normReserve1 = wdiv(k, normReserve0) / WAD;                        // Get token1 balance; gas-savings

        // -- BEGIN TEST 6 -- //
        //verify normalized reserve are within 1% margin of actual reserves
        //during times of high price volatility this condition may not hold
        assertTrue(normReserve0 > 0);
        assertTrue(normReserve1 > 0);
        assertTrue(mul(uint(_reserve0), 99) < mul(normReserve0, 100));
        assertTrue(mul(normReserve0, 100) < mul(uint(_reserve0), 101));
        //  -- END Test 6 --  //

        uint lpTokenSupply = ERC20Like(ETH_USDC_UNI_POOL).totalSupply();        // Get LP token supply

        // -- BEGIN TEST 7 -- //
        assertTrue(lpTokenSupply > 0);
        //  -- END Test 7 --  //

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

        // -- BEGIN TEST 8 -- //
        assertTrue(zzz > 0);
        //  -- END Test 8 --  //

        ///////////////////////////////////////
        //                                   //
        //         End seek() excerpt        //
        //                                   //
        ///////////////////////////////////////
    }

    function test_poke() public {
        //check that current and next price are 0
        (uint128 curVal, uint128 curHas) = ethDaiLPOracle.cur();
        assertEq(uint256(curVal), 0);
        assertEq(uint256(curHas), 0);
        (uint128 nxtVal, uint128 nxtHas) = ethDaiLPOracle.nxt();
        assertEq(uint256(nxtVal), 0);
        assertEq(uint256(nxtHas), 0);

        //check timestamp is 0
        assertEq(uint256(ethDaiLPOracle.zzz()), 0);

        //execute poke
        ethDaiLPOracle.poke();

        //verify that cur has not been set
        (curVal, curHas) = ethDaiLPOracle.cur();
        assertEq(uint256(curVal), 0);
        assertEq(uint256(curHas), 0);

        //verify that nxt has been set
        (nxtVal, nxtHas) = ethDaiLPOracle.nxt();
        assertTrue(nxtVal > 0);
        assertEq(uint256(nxtHas), 1);

        //verify timestamp set
        assertTrue(ethDaiLPOracle.zzz() > 0);
    }

    function testFail_double_poke() public {
        ethDaiLPOracle.poke();                                  //poke oracle
        ethDaiLPOracle.poke();                                  //poke oracle again w/o hop time elapsed
        (uint128 curVal, uint128 curHas) = ethDaiLPOracle.cur();    //get current oracle value
        assertEq(uint256(curHas), 1);                           //verify oracle has current value
        assertTrue(uint256(curVal) > 0);                        //verify oracle has valid current value
    }

    function test_double_poke() public {
        ethDaiLPOracle.poke();                                  //poke oracle
        //hevm.store(
        //    address(ethDaiLPOracle),
        //    bytes32(uint256(0x90)),
        //    bytes32(uint256(sub(ethDaiLPOracle.zzz(), ethDaiLPOracle.hop())))
        //);
        hevm.warp(add(ethDaiLPOracle.zzz(), ethDaiLPOracle.hop())); //time travel into the future
        ethDaiLPOracle.poke();                                  //poke oracle again

    }

    function test_change() public {
        assertEq(ethDaiLPOracle.src(), ETH_DAI_UNI_POOL);       //verify source is ETH-DAI pool
        ethDaiLPOracle.change(ETH_USDC_UNI_POOL);               //change source to ETH-USDC pool
        assertEq(ethDaiLPOracle.src(), ETH_USDC_UNI_POOL);      //verify source is ETH-USDC pool
    }

    function test_pass() public {
        assertTrue(ethDaiLPOracle.pass());                      //verify time interval `hop`has elapsed
        ethDaiLPOracle.poke();                                  //poke oracle
        hevm.warp(add(ethDaiLPOracle.zzz(), ethDaiLPOracle.hop())); //time travel into the future
        assertTrue(ethDaiLPOracle.pass());                      //verify time interval `hop` has elapsed
    }

    function testFail_pass() public {
        ethDaiLPOracle.poke();                                  //poke oracle
        assertTrue(ethDaiLPOracle.pass());                      //fail pass
    }

    function testFail_whitelist_peep() public {
        ethDaiLPOracle.poke();                                  //poke oracle
        (bytes32 val, bool has) = ethDaiLPOracle.peep();        //peep oracle price without caller being whitelisted
    }

    function test_whitelist_peep() public {
        ethDaiLPOracle.poke();                                  //poke oracle
        ethDaiLPOracle.kiss(address(this));                     //white caller
        (bytes32 val, bool has) = ethDaiLPOracle.peep();        //view queued oracle price
        assertTrue(has);                                        //verify oracle has value
        assertTrue(val != bytes32(0));                          //verify people returned valid value
    }

    function test_kiss_single() public {
        assertTrue(ethDaiLPOracle.bud(address(this)) == 0);     //verify caller is not whitelisted
        ethDaiLPOracle.kiss(address(this));                     //whitelist caller
        assertTrue(ethDaiLPOracle.bud(address(this)) == 1);     //verify caller is whitelisted
    }

    function test_diss_single() public {
        ethDaiLPOracle.kiss(address(this));                     //whitelist caller
        assertTrue(ethDaiLPOracle.bud(address(this)) == 1);     //verify caller is whitelisted
        ethDaiLPOracle.diss(address(this));                     //remove caller from whitelist
        assertTrue(ethDaiLPOracle.bud(address(this)) == 0);     //verify caller is not whitelisted
    }
}
