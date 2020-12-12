// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.6.11;

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
    uint256 constant RAY = 10 ** 27;
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
    // Compute square using babylonian method
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

    Hevm                 hevm;
    UNIV2LPOracleFactory factory;
    UNIV2LPOracle        daiEthLPOracle;
    UNIV2LPOracle        wbtcEthLPOracle;

    address constant DAI_ETH_UNI_POOL  = 0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11;
    address constant ETH_ORACLE        = 0x81FE72B5A8d1A857d176C3E7d5Bd2679A9B85763;
    address constant USDC_ORACLE       = 0x77b68899b99b686F415d074278a9a16b336085A0;
    address constant WBTC_ORACLE       = 0xf185d0682d50819263941e5f4EacC763CC5C6C42;
    address constant WBTC_ETH_UNI_POOL = 0xBb2b8038a1640196FbE3e38816F3e67Cba72D940;

    bytes32 constant poolNameDAI       = "DAI-ETH-UNIV2-LP";
    bytes32 constant poolNameWBTC      = "WBTC-ETH-UNIV2-LP";

    event Debug(uint256 idx, uint256 val);
    event Debug(uint256 idx, address val);

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(now);

        factory = new UNIV2LPOracleFactory();

        daiEthLPOracle = UNIV2LPOracle(factory.build(
            DAI_ETH_UNI_POOL,
            poolNameDAI,
            USDC_ORACLE,
            ETH_ORACLE)
        );
        wbtcEthLPOracle = UNIV2LPOracle(factory.build(
            WBTC_ETH_UNI_POOL,
            poolNameWBTC,
            WBTC_ORACLE,
            ETH_ORACLE)
        );

        // Whitelist daiEthLP on ETH Oracle
        hevm.store(
            address(ETH_ORACLE),
            keccak256(abi.encode(address(daiEthLPOracle), uint256(5))), // Whitelist oracle
            bytes32(uint256(1))
        );
        // Whitelist wbtcEthLP on WBTC Oracle
        hevm.store(
            address(WBTC_ORACLE),
            keccak256(abi.encode(address(wbtcEthLPOracle), uint256(5))), // Whitelist oracle
            bytes32(uint256(1))
        );
        // Whitelist wbtcEthLP on ETH Oracle
        hevm.store(
            address(ETH_ORACLE),
            keccak256(abi.encode(address(wbtcEthLPOracle), uint256(5))),  // Whitelist oracle
            bytes32(uint256(1))
        );
    }

    ///////////////////////////////////////////////////////
    //                                                   //
    //                  Factory Tests                    //
    //                                                   //
    ///////////////////////////////////////////////////////

    function test_build() public {
        UNIV2LPOracle oracle = UNIV2LPOracle(factory.build(
            DAI_ETH_UNI_POOL,
            poolNameDAI,
            WBTC_ORACLE,
            ETH_ORACLE)
        );                                                  // Deploy new LP oracle
        assertTrue(address(daiEthLPOracle) != address(0));  // Verify oracle deployed successfully
        assertEq(oracle.wards(address(this)), 1);           // Verify caller is owner
        assertEq(oracle.src(), DAI_ETH_UNI_POOL);           // Verify uni pool is source
        assertEq(oracle.orb0(), WBTC_ORACLE);               // Verify oracle configured correctly
        assertEq(oracle.orb1(), ETH_ORACLE);                // Verify oracle configured correctly
        assertEq(oracle.stopped(), 0);                      // Verify contract is active
        assertTrue(factory.isOracle(address(oracle)));      // Verify factory recorded oracle
    }

    // Attempt to deploy new LP oracle
    function testFail_build_invalid_pool() public {
        factory.build(
            address(0),
            poolNameDAI,
            WBTC_ORACLE,
            ETH_ORACLE
        );
    }
    // Attempt to deploy new LP oracle
    function testFail_build_invalid_oracle() public {
        factory.build(
            DAI_ETH_UNI_POOL,
            poolNameDAI,
            WBTC_ORACLE,
            address(0)
        );
    }
    // Attempt to deploy new LP oracle
    function testFail_build_invalid_oracle2() public {
        factory.build(
            DAI_ETH_UNI_POOL,
            poolNameDAI,
            address(0),
            ETH_ORACLE
        );
    }

    ///////////////////////////////////////////////////////
    //                                                   //
    //                   Oracle Tests                    //
    //                                                   //
    ///////////////////////////////////////////////////////

    function test_oracle_constructor() public {
        assertEq(daiEthLPOracle.src(), DAI_ETH_UNI_POOL);  // Verify source is DAI-ETH pool
        assertEq(daiEthLPOracle.orb0(), USDC_ORACLE);      // Verify token 0 oracle is USDC oracle
        assertEq(daiEthLPOracle.orb1(), ETH_ORACLE);       // Verify token 1 oracle is ETH oracle
        assertEq(daiEthLPOracle.wards(address(this)), 1);  // Verify owner
        assertEq(daiEthLPOracle.stopped(), 0);             // Verify contract active
    }

    function test_seek_dai() public {
        (uint128 lpTokenPrice, uint32 zzz) = daiEthLPOracle.seek();         //get new dai-eth lp price from uniswap
        assertTrue(zzz > uint32(0));
        assertTrue(uint256(lpTokenPrice) > WAD);
    }

    function test_seek_wbtc() public {
        (uint128 lpTokenPrice, uint32 zzz) = wbtcEthLPOracle.seek();         //get new wbtc-eth lp price from uniswap
        assertTrue(zzz > uint32(0));
        assertTrue(uint256(lpTokenPrice) > WAD);
    }

    function test_seek_internals() public {
        hevm.store(
            address(ETH_ORACLE),
            keccak256(abi.encode(address(this), uint256(5))), // Whitelist oracle
            bytes32(uint256(1))
        );
        hevm.store(
            address(WBTC_ORACLE),
            keccak256(abi.encode(address(this), uint256(5))), // Whitelist oracle
            bytes32(uint256(1))
        );

        ///////////////////////////////////////
        //                                   //
        //        Begin seek() excerpt       //
        //                                   //
        ///////////////////////////////////////
        // This is necessary to test a bunch of the variables in memory
        // slight modifications to seek()

        UniswapV2PairLike(WBTC_ETH_UNI_POOL).sync();
        (
            uint112 res0,
            uint112 res1,
            uint32 ts
        ) = UniswapV2PairLike(WBTC_ETH_UNI_POOL).getReserves();                   // Get reserves of token0 and token1 in liquidity pool
        require(ts == block.timestamp);                                           // Verify timestamp is current block (due to sync)

        /*** BEGIN TEST 1 ***/
        // Get token addresses of LP contract
        address tok0 = UniswapV2PairLike(WBTC_ETH_UNI_POOL).token0();             // Get token0 of liquidity pool
        address tok1 = UniswapV2PairLike(WBTC_ETH_UNI_POOL).token1();             // Get token1 of liquidity pool
        assertEq(res0, ERC20Like(tok0).balanceOf(WBTC_ETH_UNI_POOL));             // Verify reserve of token0 matches balance of contract
        assertEq(res1, ERC20Like(tok1).balanceOf(WBTC_ETH_UNI_POOL));             // Verify reserve of token1 matches balance of contract
        /*** END TEST 1 ***/

        // Adjust reserves w/ respect to decimals
        if (wbtcEthLPOracle.dec0() != uint8(18)) {                                // Check if token0 has non-standard decimals
            res0 = uint112(res0 * 10 ** sub(18, wbtcEthLPOracle.dec0()));         // Adjust reserves of token0
        }
        if (wbtcEthLPOracle.dec1() != uint8(18)) {                                // Check if token1 has non-standard decimals
            res1 = uint112(res1 * 10 ** sub(18, wbtcEthLPOracle.dec1()));         // Adjust reserve of token1
        }
        /*** BEGIN TEST 2 ***/
        assertEq(res1, ERC20Like(tok1).balanceOf(WBTC_ETH_UNI_POOL));             // Verify no adjustment for WETH (18 decimals)
        assertTrue(res0 > ERC20Like(tok0).balanceOf(WBTC_ETH_UNI_POOL));          // Verify reserve adjustment for  WBTC (6 decimals)
        assertEq(res0 / 10 ** 10, ERC20Like(tok0).balanceOf(WBTC_ETH_UNI_POOL));  // Verify decimal adjustment behaves correctly
        /*** END TEST 2 ***/

        uint k = mul(res0, res1);                                                 // Calculate constant product invariant k (WAD * WAD)

        /*** BEGIN TEST 3 ***/
        assertTrue(k > res0);                                                     // Verify k is greater than reserve of token0
        assertTrue(k > res1);                                                     // Verify k is greater than reserve of token1
        assertEq(div(k, res0), res1);                                             // Verify k calculation behaves correctly
        assertEq(div(k, res1), res0);                                             // Verify k calculation behaves correctly
        /*** END TEST 3 ***/

        uint val0 = OracleLike(wbtcEthLPOracle.orb0()).read();                    // Query token0 price from oracle (WAD)
        uint val1 = OracleLike(wbtcEthLPOracle.orb1()).read();                    // Query token1 price from oracle (WAD)

        /*** BEGIN TEST 4 ***/
        assertTrue(val0 > 0);                                                     // Verify token0 price is valid
        assertTrue(val1 > 0);                                                     // Verify token1 price is valid
        /*** END TEST 4 ***/

        uint bal0 = sqrt(wmul(k, wdiv(val1, val0)));                              // Calculate normalized token0 balance (WAD)
        uint bal1 = wdiv(k, bal0) / WAD;                                          // Calculate normalized token1 balance

        /*** BEGIN TEST 5 ***/
        // Verify normalized reserves are within 1.3% margin of actual reserves
        // During times of high price volatility this condition may not hold
        assertTrue(bal0 > 0);                                                     // Verify normalized token0 balance is valid
        assertTrue(bal1 > 0);                                                     // Verify normalized token1 balance is valid
        uint diff0 = uint(res0) > bal0 ? uint(res0) - bal0 : bal0 - uint(res0);
        uint diff1 = uint(res1) > bal1 ? uint(res1) - bal1 : bal1 - uint(res1);
        assertTrue(diff0 * RAY / bal0 < 1 * RAY / 100);                           // Verify normalized token0 balance is within 1.3% of token0 balance
        assertTrue(diff1 * RAY / bal1 < 1 * RAY / 100);                           // Verify normalized token1 balance is within 1.3% of token0 balance
        /*** END TEST 5 ***/

        uint supply = ERC20Like(WBTC_ETH_UNI_POOL).totalSupply();                 // Get LP token supply

        /*** BEGIN TEST 6 ***/
        assertTrue(supply > WAD / 1000);                                          // Verify LP token supply is valid (supply can be less than WAD if price > mkt cap)
        /*** END TEST 6 ***/

        uint128 quote = uint128(                                                  // Calculate LP token price quote
            wdiv(
                add(
                    wmul(bal0, val0), // (WAD)
                    wmul(bal1, val1)  // (WAD)
                ),
                supply // (WAD)
            )
        );

        /*** BEGIN TEST 7 ***/
        assertTrue(quote > WAD);                                                    // Verify LP token price quote is valid
        /*** END TEST 7 ***/

        ///////////////////////////////////////
        //                                   //
        //         End seek() excerpt        //
        //                                   //
        ///////////////////////////////////////
    }

    function test_poke() public {
        (uint128 curVal, uint128 curHas) = daiEthLPOracle.cur();  // Get current value
        assertEq(uint256(curVal), 0);                             // Verify oracle has no current value
        assertEq(uint256(curHas), 0);                             // Verify oracle has no current value

        (uint128 nxtVal, uint128 nxtHas) = daiEthLPOracle.nxt();  // Get queued value
        assertEq(uint256(nxtVal), 0);                             // Verify oracle has no queued price
        assertEq(uint256(nxtHas), 0);                             // Verify oracle has no queued price

        assertEq(uint256(daiEthLPOracle.zzz()), 0);               // Verify timestamp is 0

        daiEthLPOracle.poke();                                    // Update oracle

        (curVal, curHas) = daiEthLPOracle.cur();                  // Get current value
        assertEq(uint256(curVal), 0);                             // Verify oracle has no current value
        assertEq(uint256(curHas), 0);                             // Verify oracle has no current value

        (nxtVal, nxtHas) = daiEthLPOracle.nxt();                  // Get queued value
        assertTrue(nxtVal > 0);                                   // Verify oracle has non-zero queued value
        assertEq(uint256(nxtHas), 1);                             // Verify oracle has value

        assertTrue(daiEthLPOracle.zzz() > 0);                     // Verify timestamp is non-zero
    }

    function testFail_double_poke() public {
        daiEthLPOracle.poke();  // Poke oracle
        daiEthLPOracle.poke();  // Poke oracle again w/o hop time elapsed
    }

    function test_double_poke() public {
        daiEthLPOracle.poke();                                       // Poke oracle
        (uint128 nxtVal, uint128 nxtHas) = daiEthLPOracle.nxt();     // Get queued oracle value
        assertEq(uint(nxtHas), 1);                                   // Verify oracle has queued value
        hevm.warp(add(daiEthLPOracle.zzz(), daiEthLPOracle.hop()));  // Time travel into the future
        daiEthLPOracle.poke();                                       // Poke oracle again
        (uint128 curVal, uint128 curHas) = daiEthLPOracle.cur();     // Get current oracle value
        assertEq(uint(curHas), 1);                                   // Verify oracle has current value
        assertEq(uint(curVal), uint(nxtVal));                        // Verify queued value became current value
        (nxtVal, nxtHas) = daiEthLPOracle.nxt();                     // Get queued oracle value
        assertEq(uint(nxtHas), 1);                                   // Verify oracle has queued value
        assertTrue(nxtVal > 0);                                      // Verify queued oracle value
    }

    function test_change() public {
        assertEq(daiEthLPOracle.src(), DAI_ETH_UNI_POOL);  // Verify source is DAI-ETH pool
        daiEthLPOracle.change(WBTC_ETH_UNI_POOL);          // Change source to WBTC-ETH pool
        assertEq(daiEthLPOracle.src(), WBTC_ETH_UNI_POOL); // Verify source is WBTC-ETH pool
    }

    function test_pass() public {
        assertTrue(daiEthLPOracle.pass());                           // Verify time interval `hop`has elapsed
        daiEthLPOracle.poke();                                       // Poke oracle
        hevm.warp(add(daiEthLPOracle.zzz(), daiEthLPOracle.hop()));  // Time travel into the future
        assertTrue(daiEthLPOracle.pass());                           // Verify time interval `hop` has elapsed
    }

    function testFail_pass() public {
        daiEthLPOracle.poke();              // Poke oracle
        assertTrue(daiEthLPOracle.pass());  // Fail pass
    }

    function testFail_whitelist_peep() public {
        daiEthLPOracle.poke();                            // Poke oracle
        (bytes32 val, bool has) = daiEthLPOracle.peep();  // Peep oracle price without caller being whitelisted
        assertTrue(has);                                  // Verify oracle has value
        assertTrue(val != bytes32(0));                    // Verify peep returned value
    }

    function test_whitelist_peep() public {
        daiEthLPOracle.poke();                            // Poke oracle
        daiEthLPOracle.kiss(address(this));               // White caller
        (bytes32 val, bool has) = daiEthLPOracle.peep();  // View queued oracle price
        assertTrue(has);                                  // Verify oracle has value
        assertTrue(val != bytes32(0));                    // Verify peep returned valid value
    }

    function testFail_whitelist_peek() public {
        daiEthLPOracle.poke();                                       // Poke oracle
        hevm.warp(add(daiEthLPOracle.zzz(), daiEthLPOracle.hop()));  // Time travel into the future
        daiEthLPOracle.poke();                                       // Poke oracle again
        (bytes32 val, bool has) = daiEthLPOracle.peek();             // Peek oracle price without caller being whitelisted
        assertTrue(has);                                             // Verify oracle has value
        assertTrue(val > bytes32(0));                                // Verify peek returned value
    }

    function test_whitelist_peek() public {
        daiEthLPOracle.poke();                                       // Poke oracle
        hevm.warp(add(daiEthLPOracle.zzz(), daiEthLPOracle.hop()));  // Time travel into the future
        daiEthLPOracle.poke();                                       // Poke oracle again
        daiEthLPOracle.kiss(address(this));                          // Whitelist caller
        (bytes32 val, bool has) = daiEthLPOracle.peek();             // Peek oracle price without caller being whitelisted
        assertTrue(has);                                             // Verify oracle has value
        assertTrue(val != bytes32(0));                               // Verify peep returned valid value
    }

    function test_whitelist_read() public {
        daiEthLPOracle.poke();                                       // Poke oracle
        hevm.warp(add(daiEthLPOracle.zzz(), daiEthLPOracle.hop()));  // Time travel into the future
        daiEthLPOracle.poke();                                       // Poke oracle again
        daiEthLPOracle.kiss(address(this));                          // Whitelist caller
        bytes32 val = daiEthLPOracle.read();                         // Read oracle price
        assertTrue(val != bytes32(0));                               // Verify read returned valid value
    }

    function testFail_whitelist_read() public {
        daiEthLPOracle.poke();                                       // Poke oracle
        hevm.warp(add(daiEthLPOracle.zzz(), daiEthLPOracle.hop()));  // Time travel into the future
        daiEthLPOracle.poke();                                       // Poke oracle again
        daiEthLPOracle.read();                                       // Attempt to read oracle value
    }

    function test_kiss_single() public {
        assertTrue(daiEthLPOracle.bud(address(this)) == 0);  // Verify caller is not whitelisted
        daiEthLPOracle.kiss(address(this));                  // Whitelist caller
        assertTrue(daiEthLPOracle.bud(address(this)) == 1);  // Verify caller is whitelisted
    }

    function testFail_kiss() public {
        daiEthLPOracle.deny(address(this));  // Remove owner
        daiEthLPOracle.kiss(address(this));  // Attempt to whitelist caller
    }

    function testFail_kiss2() public {
        daiEthLPOracle.kiss(address(0));  // Attempt to whitelist 0 address
    }

    function test_diss_single() public {
        daiEthLPOracle.kiss(address(this));                  // Whitelist caller
        assertTrue(daiEthLPOracle.bud(address(this)) == 1);  // Verify caller is whitelisted
        daiEthLPOracle.diss(address(this));                  // Remove caller from whitelist
        assertTrue(daiEthLPOracle.bud(address(this)) == 0);  // Verify caller is not whitelisted
    }

    function testFail_diss() public {
        daiEthLPOracle.deny(address(this));  // Remove owner
        daiEthLPOracle.diss(address(this));  // Attempt to remove caller from whitelist
    }

    function test_link() public {
        address TUSD_ORACLE = 0xeE13831ca96d191B688A670D47173694ba98f1e5;
        daiEthLPOracle.link(0, TUSD_ORACLE);
        assertEq(daiEthLPOracle.orb0(), TUSD_ORACLE);
    }

    function test_link_poke() public {
        address TUSD_ORACLE = 0xeE13831ca96d191B688A670D47173694ba98f1e5;
        daiEthLPOracle.poke();
        daiEthLPOracle.kiss(address(this));
        (bytes32 val1,) = daiEthLPOracle.peep();
        daiEthLPOracle.link(0, TUSD_ORACLE);
        (bytes32 val2,) = daiEthLPOracle.peep();
        assertEq(val1, val2);
    }

    function testFail_link() public {
        daiEthLPOracle.link(1, address(0));
    }
}
