pragma solidity ^0.6.7;

import "ds-test/test.sol";
import "./test/IUniswapV2Router02.sol";
import "./test/IERC20.sol";

import "./Univ2LpOracle.sol";

interface Hevm {
    function warp(uint256) external;
    function roll(uint256) external;
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
    UNIV2LPOracle        ethDaiLPOracle;
    UNIV2LPOracle        ethWbtcLPOracle;
    IUniswapV2Router02   uniswap;

    address constant ETH_DAI_UNI_POOL  = 0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11;
    address constant ETH_ORACLE        = 0x81FE72B5A8d1A857d176C3E7d5Bd2679A9B85763;
    address constant USDC_ORACLE       = 0x77b68899b99b686F415d074278a9a16b336085A0;
    address constant WBTC_ORACLE       = 0xf185d0682d50819263941e5f4EacC763CC5C6C42;
    address constant ETH_WBTC_UNI_POOL = 0xBb2b8038a1640196FbE3e38816F3e67Cba72D940;
    address constant UNISWAP_ROUTER_02 = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address constant DAI               = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant WETH              = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant WBTC              = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;

    bytes32 constant poolNameDAI       = "ETH-DAI-UNIV2-LP";
    bytes32 constant poolNameWBTC      = "ETH-WBTC-UNIV2-LP";

    event Debug(uint256 idx, uint256 val);
    event Debug(uint256 idx, address val);

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(now);

        factory = new UNIV2LPOracleFactory();

        ethDaiLPOracle = UNIV2LPOracle(factory.build(
            ETH_DAI_UNI_POOL,
            poolNameDAI,
            USDC_ORACLE,
            ETH_ORACLE)
        );
        ethWbtcLPOracle = UNIV2LPOracle(factory.build(
            ETH_WBTC_UNI_POOL,
            poolNameWBTC,
            WBTC_ORACLE,
            ETH_ORACLE)
        );

        // Whitelist ethDaiLP on ETH Oracle
        hevm.store(
            address(ETH_ORACLE),
            keccak256(abi.encode(address(ethDaiLPOracle), uint256(5))), // Whitelist oracle
            bytes32(uint256(1))
        );
        // Whitelist ethWbtcLP on ETH Oracle
        hevm.store(
            address(WBTC_ORACLE),
            keccak256(abi.encode(address(ethWbtcLPOracle), uint256(5))), // Whitelist oracle
            bytes32(uint256(1))
        );
        hevm.store(
            address(ETH_ORACLE),
            keccak256(abi.encode(address(ethWbtcLPOracle), uint256(5))),  // Whitelist oracle
            bytes32(uint256(1))
        );

        uniswap = IUniswapV2Router02(UNISWAP_ROUTER_02);
        // Add some Dai
        hevm.store(
            address(DAI),
            keccak256(abi.encode(address(this), uint256(2))),
            bytes32(uint(200_000_000 ether))
        );
        IERC20(DAI).approve(UNISWAP_ROUTER_02, uint(-1));
    }

    ///////////////////////////////////////////////////////
    //                                                   //
    //                  Factory Tests                    //
    //                                                   //
    ///////////////////////////////////////////////////////

    function test_build() public {
        UNIV2LPOracle oracle = UNIV2LPOracle(factory.build(
            ETH_DAI_UNI_POOL,
            poolNameDAI,
            WBTC_ORACLE,
            ETH_ORACLE)
        );                                                  // Deploy new LP oracle
        assertTrue(address(ethDaiLPOracle) != address(0));  // Verify oracle deployed successfully
        assertEq(oracle.wards(address(this)), 1);           // Verify caller is owner
        assertEq(oracle.src(), ETH_DAI_UNI_POOL);           // Verify uni pool is source
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
            ETH_DAI_UNI_POOL,
            poolNameDAI,
            WBTC_ORACLE,
            address(0)
        );
    }
    // Attempt to deploy new LP oracle
    function testFail_build_invalid_oracle2() public {
        factory.build(
            ETH_DAI_UNI_POOL,
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
        assertEq(ethDaiLPOracle.src(), ETH_DAI_UNI_POOL);  // Verify source is ETH-DAI pool
        assertEq(ethDaiLPOracle.orb0(), USDC_ORACLE);      // Verify token 0 oracle is USDC oracle
        assertEq(ethDaiLPOracle.orb1(), ETH_ORACLE);       // Verify token 1 oracle is ETH oracle
        assertEq(ethDaiLPOracle.wards(address(this)), 1);  // Verify owner
        assertEq(ethDaiLPOracle.stopped(), 0);             // Verify contract active
    }

    function test_seek_dai() public {
        (uint128 lpTokenPrice, uint32 zzz) = ethDaiLPOracle.seek();         //get new eth-dai lp price from uniswap
        assertTrue(zzz > uint32(0));
        assertTrue(uint256(lpTokenPrice) > WAD);
    }

    function test_seek_wbtc() public {
        (uint128 lpTokenPrice, uint32 zzz) = ethWbtcLPOracle.seek();         //get new eth-dai lp price from uniswap
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

        UniswapV2PairLike(ETH_WBTC_UNI_POOL).sync();
        (
            uint112 res0,
            uint112 res1,
            uint32 ts
        ) = UniswapV2PairLike(ETH_WBTC_UNI_POOL).getReserves();                   // Get reserves of token0 and token1 in liquidity pool
        require(ts == block.timestamp);                                           // Verify timestamp is current block (due to sync)

        /*** BEGIN TEST 1 ***/
        // Get token addresses of LP contract
        address tok0 = UniswapV2PairLike(ETH_WBTC_UNI_POOL).token0();             // Get token0 of liquidity pool
        address tok1 = UniswapV2PairLike(ETH_WBTC_UNI_POOL).token1();             // Get token1 of liquidity pool
        assertEq(res0, ERC20Like(tok0).balanceOf(ETH_WBTC_UNI_POOL));             // Verify reserve of token0 matches balance of contract
        assertEq(res1, ERC20Like(tok1).balanceOf(ETH_WBTC_UNI_POOL));             // Verify reserve of token1 matches balance of contract
        /*** END TEST 1 ***/

        // Adjust reserves w/ respect to decimals
        if (ethWbtcLPOracle.dec0() != uint8(18)) {                                // Check if token0 has non-standard decimals
            res0 = uint112(res0 * 10 ** sub(18, ethWbtcLPOracle.dec0()));         // Adjust reserves of token0
        }
        if (ethWbtcLPOracle.dec1() != uint8(18)) {                                // Check if token1 has non-standard decimals
            res1 = uint112(res1 * 10 ** sub(18, ethWbtcLPOracle.dec1()));         // Adjust reserve of token1
        }
        /*** BEGIN TEST 2 ***/
        assertEq(res1, ERC20Like(tok1).balanceOf(ETH_WBTC_UNI_POOL));             // Verify no adjustment for WETH (18 decimals)
        assertTrue(res0 > ERC20Like(tok0).balanceOf(ETH_WBTC_UNI_POOL));          // Verify reserve adjustment for  WBTC (6 decimals)
        assertEq(res0 / 10 ** 10, ERC20Like(tok0).balanceOf(ETH_WBTC_UNI_POOL));  // Verify decimal adjustment behaves correctly
        /*** END TEST 2 ***/

        uint k = mul(res0, res1);                                                 // Calculate constant product invariant k (WAD * WAD)

        /*** BEGIN TEST 3 ***/
        assertTrue(k > res0);                                                     // Verify k is greater than reserve of token0
        assertTrue(k > res1);                                                     // Verify k is greater than reserve of token1
        assertEq(div(k, res0), res1);                                             // Verify k calculation behaves correctly
        assertEq(div(k, res1), res0);                                             // Verify k calculation behaves correctly
        /*** END TEST 3 ***/

        uint val0 = OracleLike(ethWbtcLPOracle.orb0()).read();                    // Query token0 price from oracle (WAD)
        uint val1 = OracleLike(ethWbtcLPOracle.orb1()).read();                    // Query token1 price from oracle (WAD)

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

        uint supply = ERC20Like(ETH_WBTC_UNI_POOL).totalSupply();                 // Get LP token supply

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
        (uint128 curVal, uint128 curHas) = ethDaiLPOracle.cur();  // Get current value
        assertEq(uint256(curVal), 0);                             // Verify oracle has no current value
        assertEq(uint256(curHas), 0);                             // Verify oracle has no current value

        (uint128 nxtVal, uint128 nxtHas) = ethDaiLPOracle.nxt();  // Get queued value
        assertEq(uint256(nxtVal), 0);                             // Verify oracle has no queued price
        assertEq(uint256(nxtHas), 0);                             // Verify oracle has no queued price

        assertEq(uint256(ethDaiLPOracle.zzz()), 0);               // Verify timestamp is 0

        ethDaiLPOracle.poke();                                    // Update oracle

        (curVal, curHas) = ethDaiLPOracle.cur();                  // Get current value
        assertEq(uint256(curVal), 0);                             // Verify oracle has no current value
        assertEq(uint256(curHas), 0);                             // Verify oracle has no current value

        (nxtVal, nxtHas) = ethDaiLPOracle.nxt();                  // Get queued value
        assertTrue(nxtVal > 0);                                   // Verify oracle has non-zero queued value
        assertEq(uint256(nxtHas), 1);                             // Verify oracle has value

        assertTrue(ethDaiLPOracle.zzz() > 0);                     // Verify timestamp is non-zero
    }

    function testFail_double_poke() public {
        ethDaiLPOracle.poke();  // Poke oracle
        ethDaiLPOracle.poke();  // Poke oracle again w/o hop time elapsed
    }

    function test_double_poke() public {
        ethDaiLPOracle.poke();                                       // Poke oracle
        (uint128 nxtVal, uint128 nxtHas) = ethDaiLPOracle.nxt();     // Get queued oracle value
        assertEq(uint(nxtHas), 1);                                   // Verify oracle has queued value
        hevm.warp(add(ethDaiLPOracle.zzz(), ethDaiLPOracle.hop()));  // Time travel into the future
        ethDaiLPOracle.poke();                                       // Poke oracle again
        (uint128 curVal, uint128 curHas) = ethDaiLPOracle.cur();     // Get current oracle value
        assertEq(uint(curHas), 1);                                   // Verify oracle has current value
        assertEq(uint(curVal), uint(nxtVal));                        // Verify queued value became current value
        (nxtVal, nxtHas) = ethDaiLPOracle.nxt();                     // Get queued oracle value
        assertEq(uint(nxtHas), 1);                                   // Verify oracle has queued value
        assertTrue(nxtVal > 0);                                      // Verify queued oracle value
    }

    function test_change() public {
        assertEq(ethDaiLPOracle.src(), ETH_DAI_UNI_POOL);  // Verify source is ETH-DAI pool
        ethDaiLPOracle.change(ETH_WBTC_UNI_POOL);          // Change source to ETH-WBTC pool
        assertEq(ethDaiLPOracle.src(), ETH_WBTC_UNI_POOL); // Verify source is ETH-WBTC pool
    }

    function test_pass() public {
        assertTrue(ethDaiLPOracle.pass());                           // Verify time interval `hop`has elapsed
        ethDaiLPOracle.poke();                                       // Poke oracle
        hevm.warp(add(ethDaiLPOracle.zzz(), ethDaiLPOracle.hop()));  // Time travel into the future
        assertTrue(ethDaiLPOracle.pass());                           // Verify time interval `hop` has elapsed
    }

    function testFail_pass() public {
        ethDaiLPOracle.poke();              // Poke oracle
        assertTrue(ethDaiLPOracle.pass());  // Fail pass
    }

    function testFail_whitelist_peep() public {
        ethDaiLPOracle.poke();                            // Poke oracle
        (bytes32 val, bool has) = ethDaiLPOracle.peep();  // Peep oracle price without caller being whitelisted
        assertTrue(has);                                  // Verify oracle has value
        assertTrue(val != bytes32(0));                    // Verify peep returned value
    }

    function test_whitelist_peep() public {
        ethDaiLPOracle.poke();                            // Poke oracle
        ethDaiLPOracle.kiss(address(this));               // White caller
        (bytes32 val, bool has) = ethDaiLPOracle.peep();  // View queued oracle price
        assertTrue(has);                                  // Verify oracle has value
        assertTrue(val != bytes32(0));                    // Verify peep returned valid value
    }

    function testFail_whitelist_peek() public {
        ethDaiLPOracle.poke();                                       // Poke oracle
        hevm.warp(add(ethDaiLPOracle.zzz(), ethDaiLPOracle.hop()));  // Time travel into the future
        ethDaiLPOracle.poke();                                       // Poke oracle again
        (bytes32 val, bool has) = ethDaiLPOracle.peek();             // Peek oracle price without caller being whitelisted
        assertTrue(has);                                             // Verify oracle has value
        assertTrue(val > bytes32(0));                                // Verify peek returned value
    }

    function test_whitelist_peek() public {
        ethDaiLPOracle.poke();                                       // Poke oracle
        hevm.warp(add(ethDaiLPOracle.zzz(), ethDaiLPOracle.hop()));  // Time travel into the future
        ethDaiLPOracle.poke();                                       // Poke oracle again
        ethDaiLPOracle.kiss(address(this));                          // Whitelist caller
        (bytes32 val, bool has) = ethDaiLPOracle.peek();             // Peek oracle price without caller being whitelisted
        assertTrue(has);                                             // Verify oracle has value
        assertTrue(val != bytes32(0));                               // Verify peep returned valid value
    }

    function test_whitelist_read() public {
        ethDaiLPOracle.poke();                                       // Poke oracle
        hevm.warp(add(ethDaiLPOracle.zzz(), ethDaiLPOracle.hop()));  // Time travel into the future
        ethDaiLPOracle.poke();                                       // Poke oracle again
        ethDaiLPOracle.kiss(address(this));                          // Whitelist caller
        bytes32 val = ethDaiLPOracle.read();                         // Read oracle price
        assertTrue(val != bytes32(0));                               // Verify read returned valid value
    }

    function testFail_whitelist_read() public {
        ethDaiLPOracle.poke();                                       // Poke oracle
        hevm.warp(add(ethDaiLPOracle.zzz(), ethDaiLPOracle.hop()));  // Time travel into the future
        ethDaiLPOracle.poke();                                       // Poke oracle again
        ethDaiLPOracle.read();                                       // Attempt to read oracle value
    }

    function test_kiss_single() public {
        assertTrue(ethDaiLPOracle.bud(address(this)) == 0);  // Verify caller is not whitelisted
        ethDaiLPOracle.kiss(address(this));                  // Whitelist caller
        assertTrue(ethDaiLPOracle.bud(address(this)) == 1);  // Verify caller is whitelisted
    }

    function testFail_kiss() public {
        ethDaiLPOracle.deny(address(this));  // Remove owner
        ethDaiLPOracle.kiss(address(this));  // Attempt to whitelist caller
    }

    function testFail_kiss2() public {
        ethDaiLPOracle.kiss(address(0));  // Attempt to whitelist 0 address
    }

    function test_diss_single() public {
        ethDaiLPOracle.kiss(address(this));                  // Whitelist caller
        assertTrue(ethDaiLPOracle.bud(address(this)) == 1);  // Verify caller is whitelisted
        ethDaiLPOracle.diss(address(this));                  // Remove caller from whitelist
        assertTrue(ethDaiLPOracle.bud(address(this)) == 0);  // Verify caller is not whitelisted
    }

    function testFail_diss() public {
        ethDaiLPOracle.deny(address(this));  // Remove owner
        ethDaiLPOracle.diss(address(this));  // Attempt to remove caller from whitelist
    }

    function test_price_change() public {
        ethDaiLPOracle.poke();                            // Poke oracle
        ethDaiLPOracle.kiss(address(this));
        (bytes32 val, bool has) = ethDaiLPOracle.peep();  // Peep oracle price without caller being whitelisted
        uint256 firstVal = uint256(val);

        assertTrue(firstVal < 100 ether && firstVal > 50 ether); // 58502000047042694225 at time of test
        assertTrue(has);

        assertEq(IERC20(DAI).balanceOf(address(this)), 200_000_000 ether);
        address[] memory path = new address[](2);
        path[0] = DAI;
        path[1] = WETH;
        uint[] memory amounts = uniswap.swapExactTokensForTokens(
            IERC20(DAI).balanceOf(address(this)), 0, path, msg.sender, now);
        assertEq(amounts.length, 2);
        assertEq(amounts[0], 200_000_000 ether);
        assertTrue(amounts[1] < 100_000 ether); // 79411165606915395083828 at time of test
        hevm.warp(now + 3600);

        ethDaiLPOracle.poke();
        (val, has) = ethDaiLPOracle.peep();
        uint256 secondVal = uint256(val);
        assertTrue(secondVal < 100 ether && secondVal > 50 ether); // 58502000047042694225 at time of test
        assertTrue(has);

        // Ensure the price changed after the oracle update
        assertTrue(firstVal != secondVal);
        assertEq(firstVal, 1);
        assertEq(secondVal, 2);
    }
}
