pragma solidity ^0.6.7;

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

    Hevm                    hevm;
    UNIV2LPOracleFactory    factory;
    UNIV2LPOracle           ethDaiLPOracle;
    UNIV2LPOracle           ethUsdcLPOracle;

    address constant        ETH_DAI_UNI_POOL = 0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11;
    address constant        ETH_ORACLE       = 0x81FE72B5A8d1A857d176C3E7d5Bd2679A9B85763;
    address constant        USDC_ORACLE      = 0x77b68899b99b686F415d074278a9a16b336085A0;
    address constant        ETH_USDC_UNI_POOL = 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc;

    bytes32 constant        poolNameDAI = "ETH-DAI-UNIV2-LP";
    bytes32 constant        poolNameUSDC = "ETH-USDC-UNIV2-LP";

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

        factory = new UNIV2LPOracleFactory();

        ethDaiLPOracle = UNIV2LPOracle(factory.build(
            ETH_DAI_UNI_POOL,
            poolNameDAI,
            USDC_ORACLE,
            ETH_ORACLE)
        );
        ethUsdcLPOracle = UNIV2LPOracle(factory.build(
            ETH_USDC_UNI_POOL,
            poolNameUSDC,
            USDC_ORACLE,
            ETH_ORACLE)
        );

        //whitelist ethDaiLP on ETH Oracle
        hevm.store(
            address(ETH_ORACLE),
            keccak256(abi.encode(address(ethDaiLPOracle), uint256(5))), // Whitelist oracle
            bytes32(uint256(1))
        );
    }

    ///////////////////////////////////////////////////////
    //                                                   //
    //                  Factory tests                    //
    //                                                   //
    ///////////////////////////////////////////////////////

    function test_build() public {
        UNIV2LPOracle oracle = UNIV2LPOracle(factory.build(
            ETH_DAI_UNI_POOL,
            poolNameDAI,
            USDC_ORACLE,
            ETH_ORACLE)
        );                                                      //deploy new LP oracle
        assertTrue(address(ethDaiLPOracle) != address(0));      //verify oracle deployed successfully 
        assertEq(oracle.wards(address(this)), 1);               //verify caller is owner
        assertEq(oracle.src(), ETH_DAI_UNI_POOL);               //verify uni pool is source
        assertEq(oracle.orb0(), USDC_ORACLE);                   //verify oracle configured correctly
        assertEq(oracle.orb1(), ETH_ORACLE);                    //verify oracle configured correctly
        assertEq(oracle.stopped(), 0);                          //verify contract is active
        assertTrue(factory.isOracle(address(oracle)));          //verify factory recorded oracle
    }

    function testFail_build_invalid_pool() public {
        factory.build(
            address(0),
            poolNameDAI,
            USDC_ORACLE,
            ETH_ORACLE
        );                                                      //attempt to deploy new LP oracle
    }

    function testFail_build_invalid_oracle() public {
        factory.build(
            ETH_DAI_UNI_POOL,
            poolNameDAI,
            USDC_ORACLE,
            address(0)
        );                                                      //attempt to deploy new LP oracle
    }

    function testFail_build_invalid_oracle2() public {
        factory.build(
            ETH_DAI_UNI_POOL,
            poolNameDAI,
            address(0),
            ETH_ORACLE
        );                                                      //attempt to deploy new LP oracle
    }

    ///////////////////////////////////////////////////////
    //                                                   //
    //                   Oracle tests                    //
    //                                                   //
    ///////////////////////////////////////////////////////

    function test_oracle_constructor() public {
        assertEq(ethDaiLPOracle.src(), ETH_DAI_UNI_POOL);       //verify source is ETH-DAI pool
        assertEq(ethDaiLPOracle.orb0(), USDC_ORACLE);           //verify token 0 oracle is USDC oracle
        assertEq(ethDaiLPOracle.orb1(), ETH_ORACLE);            //verify token 1 oracle is ETH oracle
        assertEq(ethDaiLPOracle.wards(address(this)), 1);       //verify owner
        assertEq(ethDaiLPOracle.stopped(), 0);                  //verify contract active
    }

    function test_seek_dai() public {
        (uint128 lpTokenPrice, uint32 zzz) = ethDaiLPOracle.seek();         //get new eth-dai lp price from uniswap
        assertTrue(zzz > uint32(0));
        //assertEq(uint256(lpTokenPrice), 1);
    }

    function test_seek_usdc() public {
        hevm.store(
            address(ETH_ORACLE),
            keccak256(abi.encode(address(ethUsdcLPOracle), uint256(5))),    //whitelist oracle
            bytes32(uint256(1))
        );
        (uint128 lpTokenPrice, uint32 zzz) = ethUsdcLPOracle.seek();        //get new eth-usdc lp price from uniswap
        assertTrue(zzz > uint32(0));
        //assertEq(uint256(lpTokenPrice), 1);
    }

    function test_seek_internals() public {
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
        //This is necessary to test a bunch of the variables in memory
        //slight modifications to seek()

        UniswapV2PairLike(ETH_USDC_UNI_POOL).sync();
        (
            uint112 res0,
            uint112 res1,
            uint32 ts
        ) = UniswapV2PairLike(ETH_USDC_UNI_POOL).getReserves();                     //get reserves of token0 and token1 in liquidity pool
        require(ts == block.timestamp);                                             //verify timestamp is current block (due to sync)

        // -- BEGIN TEST 1 -- //
        //Get token addresses of LP contract
        address tok0 = UniswapV2PairLike(ETH_USDC_UNI_POOL).token0();               //get token0 of liquidy pool
        address tok1 = UniswapV2PairLike(ETH_USDC_UNI_POOL).token1();               //get token1 of liquidity pool
        assertEq(res0, ERC20Like(tok0).balanceOf(ETH_USDC_UNI_POOL));               //verify reserve of token0 matches balance of contract
        assertEq(res1, ERC20Like(tok1).balanceOf(ETH_USDC_UNI_POOL));               //verify reserve of token1 matches balances of contract
        //  -- END Test 1 --  //

        // adjust reserves w/ respect to decimals
        if (ethUsdcLPOracle.dec0() != uint8(18)) {                                  //check if token0 has non-standard decimals
            res0 = uint112(res0 * 10 ** sub(18, ethUsdcLPOracle.dec0()));           //adjust reserves of token0
        }
        if (ethUsdcLPOracle.dec1() != uint8(18)) {                                  //check if token1 has non-standard decimals
            res1 = uint112(res1 * 10 ** sub(18, ethUsdcLPOracle.dec1()));           //adjust reserve of token1
        }

        // -- BEGIN TEST 2 -- //
        assertEq(res1, ERC20Like(tok1).balanceOf(ETH_USDC_UNI_POOL));               //verify no adjustment for WETH (18 decimals)
        assertTrue(res0 > ERC20Like(tok0).balanceOf(ETH_USDC_UNI_POOL));            //verify reserve adjustment for  USDC (6 decimals)
        assertEq(res1 / 10 ** 12, ERC20Like(tok0).balanceOf(ETH_USDC_UNI_POOL));    //verify decimal adjustment behaves correctly
        //  -- END Test 2 --  //

        uint k = mul(res0, res1);                               //calculate constant product invariant k (WAD * WAD)

        // -- BEGIN TEST 3 -- //
        assertTrue(k > res0);                                   //verify k is greater than reserve of token0
        assertTrue(k > res1);                                   //verify k is greater than reserve of token1
        assertEq(div(k, res0), res1);                           //verify k calculation behaves correctly
        assertEq(div(k, res1), res0);                           //verify k calculation behaves correctly
        //  -- END Test 3 --  //

        uint val0 = OracleLike(ethUsdcLPOracle.orb0()).read();  //query token0 price from oracle (WAD)
        uint val1 = OracleLike(ethUsdcLPOracle.orb1()).read();  //query token1 price from oracle (WAD)

        // -- BEGIN TEST 4 -- //
        assertTrue(val0 > 0);                                   //verify token0 price is valid
        assertTrue(val1 > 0);                                   //verify token1 price is valid
        //  -- END Test 4 --  //

        uint bal0 = sqrt(wmul(k, wdiv(val1, val0)));            //calculate normalized token0 balance (WAD)
        uint bal1 = wdiv(k, bal0) / WAD;                        //calculate normalized token1 balance

        // -- BEGIN TEST 5 -- //
        //verify normalized reserves are within 1% margin of actual reserves
        //during times of high price volatility this condition may not hold
        assertTrue(bal0 > 0);                                   //verify normalized token0 balance is valid
        assertTrue(bal1 > 0);                                   //verify normalized token1 balance is valid
        assertTrue(mul(uint(res0), 99) < mul(bal0, 100));       //verify normalized token0 balance is within 1% of token0 balance 
        assertTrue(mul(bal0, 100) < mul(uint(res0), 101));      //verify normalized token0 balance is within 1% of token0 balance
        assertTrue(mul(uint(res1), 99) < mul(bal1, 100));       //verify normalized token1 balance is within 1% of token1 balance 
        assertTrue(mul(bal1, 100) < mul(uint(res1), 101));      //verify normalized token1 balance is within 1% of token1 balance
        //  -- END Test 5 --  //

        uint supply = ERC20Like(ETH_USDC_UNI_POOL).totalSupply();   //get LP token supply

        // -- BEGIN TEST 6 -- //
        assertTrue(supply > 0);                                 //verify LP token supply is valid
        //  -- END Test 6 --  //

        uint128 quote = uint128(
            wdiv(
                add(
                    wmul(bal0, val0), // (WAD)
                    wmul(bal1, val1)  // (WAD)
                ),
                supply // (WAD)
            )
        );                                                      //calculate LP token price quote

        // -- BEGIN TEST 7 -- //
        assertTrue(quote > 0);                                  //verify LP token price quote is valid
        //  -- END Test 7 --  //

        ///////////////////////////////////////
        //                                   //
        //         End seek() excerpt        //
        //                                   //
        ///////////////////////////////////////
    }

    function test_poke() public {
        (uint128 curVal, uint128 curHas) = ethDaiLPOracle.cur();    //get current value
        assertEq(uint256(curVal), 0);                           //verify oracle has no current value
        assertEq(uint256(curHas), 0);                           //verify oracle has no current value

        (uint128 nxtVal, uint128 nxtHas) = ethDaiLPOracle.nxt();    //get queued value
        assertEq(uint256(nxtVal), 0);                           //verify oracle has no queued price
        assertEq(uint256(nxtHas), 0);                           //verify oracle has no queued price

        assertEq(uint256(ethDaiLPOracle.zzz()), 0);             //verify timestamp is 0

        ethDaiLPOracle.poke();                                  //update oracle

        (curVal, curHas) = ethDaiLPOracle.cur();                //get current value
        assertEq(uint256(curVal), 0);                           //verify oracle has no current value
        assertEq(uint256(curHas), 0);                           //verify oracle has no current value

        (nxtVal, nxtHas) = ethDaiLPOracle.nxt();                //get queued value
        assertTrue(nxtVal > 0);                                 //verify oracle has non-zero queued value
        assertEq(uint256(nxtHas), 1);                           //verify oracle has value

        assertTrue(ethDaiLPOracle.zzz() > 0);                   //verify timestamp is non-zero
    }

    function testFail_double_poke() public {
        ethDaiLPOracle.poke();                                  //poke oracle
        ethDaiLPOracle.poke();                                  //poke oracle again w/o hop time elapsed
    }

    function test_double_poke() public {
        ethDaiLPOracle.poke();                                  //poke oracle
        (uint128 nxtVal, uint128 nxtHas) = ethDaiLPOracle.nxt();    //get queued oracle value
        assertEq(uint(nxtHas), 1);                              //verify oracle has queued value
        hevm.warp(add(ethDaiLPOracle.zzz(), ethDaiLPOracle.hop())); //time travel into the future
        ethDaiLPOracle.poke();                                  //poke oracle again
        (uint128 curVal, uint128 curHas) = ethDaiLPOracle.cur();    //get current oracle value
        assertEq(uint(curHas), 1);                              //verify oracle has current value
        assertEq(uint(curVal), uint(nxtVal));                   //verify queued value became current value
        (nxtVal, nxtHas) = ethDaiLPOracle.nxt();                //get queued oracle value
        assertEq(uint(nxtHas), 1);                              //verify oracle has queued value
        assertTrue(nxtVal > 0);                                 //verify queued oracle value
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
        assertTrue(has);                                        //verify oracle has value
        assertTrue(val != bytes32(0));                          //verify peep returned value
    }

    function test_whitelist_peep() public {
        ethDaiLPOracle.poke();                                  //poke oracle
        ethDaiLPOracle.kiss(address(this));                     //white caller
        (bytes32 val, bool has) = ethDaiLPOracle.peep();        //view queued oracle price
        assertTrue(has);                                        //verify oracle has value
        assertTrue(val != bytes32(0));                          //verify peep returned valid value
    }

    function testFail_whitelist_peek() public {
        ethDaiLPOracle.poke();                                  //poke oracle
        hevm.warp(add(ethDaiLPOracle.zzz(), ethDaiLPOracle.hop())); //time travel into the future
        ethDaiLPOracle.poke();                                  //poke oracle again
        (bytes32 val, bool has) = ethDaiLPOracle.peek();        //peek oracle price without caller being whitelisted
        assertTrue(has);                                        //verify oracle has value
        assertTrue(val > bytes32(0));                           //verify peek returned value
    }

    function test_whitelist_peek() public {
        ethDaiLPOracle.poke();                                  //poke oracle
        hevm.warp(add(ethDaiLPOracle.zzz(), ethDaiLPOracle.hop())); //time travel into the future
        ethDaiLPOracle.poke();                                  //poke oracle again
        ethDaiLPOracle.kiss(address(this));                     //whitelist caller
        (bytes32 val, bool has) = ethDaiLPOracle.peek();        //peek oracle price without caller being whitelisted
        assertTrue(has);                                        //verify oracle has value
        assertTrue(val != bytes32(0));                          //verify peep returned valid value
    }

    function test_whitelist_read() public {
        ethDaiLPOracle.poke();                                  //poke oracle
        hevm.warp(add(ethDaiLPOracle.zzz(), ethDaiLPOracle.hop())); //time travel into the future
        ethDaiLPOracle.poke();                                  //poke oracle again
        ethDaiLPOracle.kiss(address(this));                     //whitelist caller
        bytes32 val = ethDaiLPOracle.read();                    //read oracle price
        assertTrue(val != bytes32(0));                          //verify read returned valid value
    }

    function testFail_whitelist_read() public {
        ethDaiLPOracle.poke();                                  //poke oracle
        hevm.warp(add(ethDaiLPOracle.zzz(), ethDaiLPOracle.hop())); //time travel into the future
        ethDaiLPOracle.poke();                                  //poke oracle again
        ethDaiLPOracle.read();                                  //attempt to read oracle value
    }

    function test_kiss_single() public {
        assertTrue(ethDaiLPOracle.bud(address(this)) == 0);     //verify caller is not whitelisted
        ethDaiLPOracle.kiss(address(this));                     //whitelist caller
        assertTrue(ethDaiLPOracle.bud(address(this)) == 1);     //verify caller is whitelisted
    }

    function testFail_kiss() public {
        ethDaiLPOracle.deny(address(this));                     //remove owner
        ethDaiLPOracle.kiss(address(this));                     //attempt to whitelist caller
    }

    function testFail_kiss2() public {
        ethDaiLPOracle.kiss(address(0));                        //attempt to whitelist 0 address
    }

    function test_diss_single() public {
        ethDaiLPOracle.kiss(address(this));                     //whitelist caller
        assertTrue(ethDaiLPOracle.bud(address(this)) == 1);     //verify caller is whitelisted
        ethDaiLPOracle.diss(address(this));                     //remove caller from whitelist
        assertTrue(ethDaiLPOracle.bud(address(this)) == 0);     //verify caller is not whitelisted
    }

    function testFail_diss() public {
        ethDaiLPOracle.deny(address(this));                     //remove owner
        ethDaiLPOracle.diss(address(this));                     //attempt to remove caller from whitelist
    }
}
