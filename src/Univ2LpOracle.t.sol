// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.6.11;

import "ds-test/test.sol";
import "./test/IUniswapV2Router02.sol";
import "./test/IERC20.sol";

import "./Univ2LpOracle.sol";

interface Hevm {
    function warp(uint256) external;
    function store(address,bytes32,bytes32) external;
    function load(address, bytes32 slot) external returns (bytes32);
}

interface OSMLike {
    function bud(address) external returns (uint);
    function peek() external returns (bytes32, bool);
}

contract SeekableOracle is UNIV2LPOracle {
    constructor(address _src, bytes32 _wat, address _orb0, address _orb1) public UNIV2LPOracle(_src, _wat, _orb0, _orb1) {}

    function _seek() public returns (uint128 quote, uint32 ts) {
        return seek();
    }
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
    IUniswapV2Router02   uniswap;
    SeekableOracle       seekableOracleDAI;
    SeekableOracle       seekableOracleWBTC;

    address constant DAI_ETH_UNI_POOL  = 0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11;
    address constant WBTC_ETH_UNI_POOL = 0xBb2b8038a1640196FbE3e38816F3e67Cba72D940;
    address constant ETH_ORACLE        = 0x81FE72B5A8d1A857d176C3E7d5Bd2679A9B85763;
    address constant USDC_ORACLE       = 0x77b68899b99b686F415d074278a9a16b336085A0;
    address constant WBTC_ORACLE       = 0xf185d0682d50819263941e5f4EacC763CC5C6C42;
    address constant TUSD_ORACLE       = 0xeE13831ca96d191B688A670D47173694ba98f1e5;
    address constant UNISWAP_ROUTER_02 = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address constant DAI               = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant WETH              = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant WBTC              = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;

    bytes32 constant poolNameDAI       = "DAI-ETH-UNIV2-LP";
    bytes32 constant poolNameWBTC      = "WBTC-ETH-UNIV2-LP";

    uint256 ethMintAmt;
    uint256 wbtcMintAmt;
    uint256 ethPrice;
    uint256 wbtcPrice;

    event Debug(uint256 idx, uint256 val);
    event Debug(uint256 idx, address val);

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);                  // Configure hevm
        hevm.warp(now);                                                           // Set time to latest block

        // Set relevant storage values as they were in block 11461654
        hevm.store(
            DAI_ETH_UNI_POOL,
            0,                                                                    // totalSupply
            bytes32(uint256(1882428696129524169269340))
        );
        hevm.store(
            DAI_ETH_UNI_POOL,
            bytes32(uint256(8)),                                                  // reserve0, reserve1, and blockTimestampLast
            bytes32(uint256(43353987475243871752608912172418385489740068120774565181786433903143712498119))
        );
        hevm.store(
            DAI,
            keccak256(abi.encode(DAI_ETH_UNI_POOL, uint256(2))),                  // DAI balance of DAI_ETH pool
            bytes32(uint(55130522579388813557146055))
        );
        hevm.store(
            WETH,
            keccak256(abi.encode(DAI_ETH_UNI_POOL, uint256(3))),                  // WETH balance of DAI_ETH pool
            bytes32(uint(94328066153704376274664))
        );
        hevm.store(
            WBTC_ETH_UNI_POOL,
            0,                                                                    // totalSupply
            bytes32(uint256(185917965159193313))
        );
        hevm.store(
            WBTC_ETH_UNI_POOL ,
            bytes32(uint256(8)),                                                  // reserve0, reserve1, and blockTimestampLast
            bytes32(uint256(43353988796281258443110612805302462270865328117852610699179961909467622877495))
        );
        hevm.store(
            WETH,
            keccak256(abi.encode(WBTC_ETH_UNI_POOL, uint256(3))),                 // WETH balance of WBTC_ETH pool
            bytes32(uint(117506766732526502569271))
        );
        hevm.store(
            WBTC,
            keccak256(abi.encode(WBTC_ETH_UNI_POOL, uint256(0))),                 // WBTC balance of WBTC_ETH pool
            bytes32(uint(353924491575))
        );
        hevm.store(
            ETH_ORACLE,
            bytes32(uint256(3)),                                                  // cur
            bytes32(uint256(340282366920938464048374607431768211456))
        );
        hevm.store(
            WBTC_ORACLE,
            bytes32(uint256(3)),                                                  // cur
            bytes32(uint256(340282366920938482841324607431768211456))
        );
        hevm.warp(1608088819);  // block.timestamp for block 11461654

        factory = new UNIV2LPOracleFactory();                                     // Instantiate new factory

        daiEthLPOracle = UNIV2LPOracle(factory.build(
            DAI_ETH_UNI_POOL,
            poolNameDAI,
            USDC_ORACLE,
            ETH_ORACLE)
        );                                                                        // Build new DAI-ETH Uniswap LP Oracle
        wbtcEthLPOracle = UNIV2LPOracle(factory.build(
            WBTC_ETH_UNI_POOL,
            poolNameWBTC,
            WBTC_ORACLE,
            ETH_ORACLE)
        );                                                                        // Build new WBTC-ETH Uniswap LP Orace

        seekableOracleDAI = new SeekableOracle(DAI_ETH_UNI_POOL, poolNameDAI, USDC_ORACLE, ETH_ORACLE);
        hevm.store(
            ETH_ORACLE,
            keccak256(abi.encode(address(seekableOracleDAI), uint256(5))),
            bytes32(uint256(1))
        );

        seekableOracleWBTC = new SeekableOracle(WBTC_ETH_UNI_POOL, poolNameWBTC, WBTC_ORACLE, ETH_ORACLE);
        hevm.store(
            ETH_ORACLE,
            keccak256(abi.encode(address(seekableOracleWBTC), uint256(5))),
            bytes32(uint256(1))
        );                                                                        // Whitelist DAI-ETH LP Oracle on seekable ETH Oracle
        hevm.store(
            WBTC_ORACLE,
            keccak256(abi.encode(address(seekableOracleWBTC), uint256(5))),
            bytes32(uint256(1))
        );

        hevm.store(
            ETH_ORACLE,
            keccak256(abi.encode(address(daiEthLPOracle), uint256(5))),
            bytes32(uint256(1))
        );                                                                        // Whitelist DAI-ETH LP Oracle on ETH Oracle
        hevm.store(
            WBTC_ORACLE,
            keccak256(abi.encode(address(wbtcEthLPOracle), uint256(5))),
            bytes32(uint256(1))
        );                                                                        // Whitelist WBTC-ETH LP Oracle on WBTC Oracle
        hevm.store(
            ETH_ORACLE,
            keccak256(abi.encode(address(wbtcEthLPOracle), uint256(5))),
            bytes32(uint256(1))
        );                                                                        // Whitelist WBTC-ETH LP Oracle on ETH Oracle

        uniswap = IUniswapV2Router02(UNISWAP_ROUTER_02);                          // Create handler to interface with Uniswap

        IERC20(WETH).approve(UNISWAP_ROUTER_02, uint(-1));                        // Approve WETH to trade on Uniswap

        hevm.store(
            DAI,
            keccak256(abi.encode(address(this), uint256(2))),
            bytes32(uint(10_000 ether))
        );                                                                        // Mint 10,000 DAI
        IERC20(DAI).approve(UNISWAP_ROUTER_02, uint(-1));                         // Approve DAI to trade on Uniswap

        hevm.store(
            ETH_ORACLE,
            keccak256(abi.encode(address(this), uint256(5))),
            bytes32(uint256(1))
        );                                                                        // Whitelist caller on ETH Oracle
        (bytes32 val, bool has) = OSMLike(ETH_ORACLE).peek();                     // Query ETH/USD price from ETH Oracle
        ethPrice = uint256(val);                                                  // Cast ETH/USD price as uint256

        hevm.store(
            WBTC_ORACLE,
            keccak256(abi.encode(address(this), uint256(5))),
            bytes32(uint256(1))
        );                                                                        // Whitelist caller on WBTC Oracle
        (val, has) = OSMLike(WBTC_ORACLE).peek();                                 // Query WBTC/USD price from WBTC Oracle
        wbtcPrice = uint256(val);                                                 // Cast WBTC/USD price as uint256

        // Mint $10k of WBTC
        wbtcMintAmt = 10_000 ether * 1E8 / wbtcPrice;                             // Calculate amount of WBTC worth $10,000
        hevm.store(
            WBTC,
            keccak256(abi.encode(address(this), uint256(0))),
            bytes32(wbtcMintAmt)
        );                                                                        // Mint $10,000 worth of WBTC
        IERC20(WBTC).approve(UNISWAP_ROUTER_02, uint(-1));                        // Approve WBTC to trade on Uniswap
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

    function testFail_build_invalid_pool() public {
        factory.build(
            address(0),
            poolNameDAI,
            WBTC_ORACLE,
            ETH_ORACLE
        );                                                  // Attempt to deploy new LP oracle
    }

    function testFail_build_invalid_oracle() public {
        factory.build(
            DAI_ETH_UNI_POOL,
            poolNameDAI,
            WBTC_ORACLE,
            address(0)
        );                                                  // Attempt to deploy new LP oracle
    }

    function testFail_build_invalid_oracle2() public {
        factory.build(
            DAI_ETH_UNI_POOL,
            poolNameDAI,
            address(0),
            ETH_ORACLE
        );                                                  // Attempt to deploy new LP oracle
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
        uint256 preGas = gasleft();
        (uint128 lpTokenPrice128, uint32 zzz) = seekableOracleDAI._seek();        // Get new dai-eth lp price from uniswap
        uint256 postGas = gasleft();
        log_named_uint("dai seek gas", preGas - postGas);
        assertTrue(zzz > uint32(0));                                              // Verify timestamp was set
        assertTrue(lpTokenPrice128 > 0);                                          // Verify price was set
        uint256 lpTokenPrice = uint256(lpTokenPrice128);
        uint256 expectedPrice =
            add(mul(ethPrice, IERC20(WETH).balanceOf(DAI_ETH_UNI_POOL)),
                mul(WAD,      IERC20(DAI).balanceOf(DAI_ETH_UNI_POOL)))
            / IERC20(DAI_ETH_UNI_POOL).totalSupply();                             // assumes protocol fee is 0
        uint256 diff =
            lpTokenPrice  > expectedPrice ?
            lpTokenPrice  - expectedPrice :
            expectedPrice - lpTokenPrice;
        assertTrue((WAD * diff) / expectedPrice < WAD / 1000);                    // 0.1% tolerance
    }

    function test_seek_wbtc() public {
        uint256 preGas = gasleft();
        (uint128 lpTokenPrice128, uint32 zzz) = seekableOracleWBTC._seek();       // Get new wbtc-eth lp price from uniswap
        uint256 postGas = gasleft();
        log_named_uint("wbtc seek gas", preGas - postGas);
        assertTrue(zzz > uint32(0));                                              // Verify timestamp was set
        assertTrue(lpTokenPrice128 > 0);                                          // Verify price was set
        uint256 lpTokenPrice = uint256(lpTokenPrice128);
        uint256 expectedPrice =
            add(mul(ethPrice,  IERC20(WETH).balanceOf(WBTC_ETH_UNI_POOL)),
                mul(wbtcPrice, IERC20(WBTC).balanceOf(WBTC_ETH_UNI_POOL) * 10**10))
            / IERC20(WBTC_ETH_UNI_POOL).totalSupply();                             // assumes protocol fee is 0
        uint256 diff =
            lpTokenPrice  > expectedPrice ?
            lpTokenPrice  - expectedPrice :
            expectedPrice - lpTokenPrice;
        assertTrue((WAD * diff) / expectedPrice < WAD / 1000);                    // 0.1% tolerance
    }

    function testFail_seek_zero_LPToken_supply() public {
        hevm.store(
            DAI_ETH_UNI_POOL,
            0,                                                                    // totalSupply
            bytes32(uint256(0))
        );
        seekableOracleDAI._seek();                                                // Get new dai-eth lp price from uniswap
    }

    function test_seek_internals() public {
        ///////////////////////////////////////
        //                                   //
        //        Begin seek() excerpt       //
        //                                   //
        ///////////////////////////////////////
        // This is necessary to test a bunch of the variables in memory
        // slight modifications to seek()

        UniswapV2PairLike(WBTC_ETH_UNI_POOL).sync();                              // Sync WBTC/ETH Uniswap pool
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
        if (ERC20Like(tok0).decimals() < 18) {                                        // Check if token0 has non-standard decimals
            res0 = uint112(res0 * 10 ** (18 - uint256(ERC20Like(tok0).decimals())));  // Adjust reserves of token0
        }
        if (ERC20Like(tok1).decimals() < 18) {                                        // Check if token1 has non-standard decimals
            res1 = uint112(res1 * 10 ** (18 - uint256(ERC20Like(tok1).decimals())));  // Adjust reserves of token1
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

        uint supply = ERC20Like(WBTC_ETH_UNI_POOL).totalSupply();                 // Get LP token supply

        /*** BEGIN TEST 5 ***/
        assertTrue(supply > WAD / 1000);                                          // Verify LP token supply is valid (supply can be less than WAD if price > mkt cap)
        /*** END TEST 5 ***/

        uint128 quote = uint128(                                                  // Calculate LP token price quote
                mul(2 * WAD, sqrt(wmul(k, wmul(val0, val1))))
                    / supply
        );

        /*** BEGIN TEST 6 ***/
        assertTrue(quote > WAD);                                                  // Verify LP token price quote is valid
        /*** END TEST 6 ***/

        ///////////////////////////////////////
        //                                   //
        //         End seek() excerpt        //
        //                                   //
        ///////////////////////////////////////
    }

    function test_poke() public {
        (uint128 curVal, uint128 curHas) = daiEthLPOracle.cur();     // Get current value
        assertEq(uint256(curVal), 0);                                // Verify oracle has no current value
        assertEq(uint256(curHas), 0);                                // Verify oracle has no current value

        (uint128 nxtVal, uint128 nxtHas) = daiEthLPOracle.nxt();     // Get queued value
        assertEq(uint256(nxtVal), 0);                                // Verify oracle has no queued price
        assertEq(uint256(nxtHas), 0);                                // Verify oracle has no queued price

        assertEq(uint256(daiEthLPOracle.zzz()), 0);                  // Verify timestamp is 0

        daiEthLPOracle.poke();                                       // Update oracle

        (curVal, curHas) = daiEthLPOracle.cur();                     // Get current value
        assertEq(uint256(curVal), 0);                                // Verify oracle has no current value
        assertEq(uint256(curHas), 0);                                // Verify oracle has no current value

        (nxtVal, nxtHas) = daiEthLPOracle.nxt();                     // Get queued value
        assertTrue(nxtVal > 0);                                      // Verify oracle has non-zero queued value
        assertEq(uint256(nxtHas), 1);                                // Verify oracle has value

        assertTrue(daiEthLPOracle.zzz() > 0);                        // Verify timestamp is non-zero
    }

    function testFail_double_poke() public {
        daiEthLPOracle.poke();                                       // Poke oracle
        daiEthLPOracle.poke();                                       // Poke oracle again w/o hop time elapsed
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
        assertEq(daiEthLPOracle.src(), DAI_ETH_UNI_POOL);            // Verify source is DAI-ETH pool
        daiEthLPOracle.change(WBTC_ETH_UNI_POOL);                    // Change source to WBTC-ETH pool
        assertEq(daiEthLPOracle.src(), WBTC_ETH_UNI_POOL);           // Verify source is WBTC-ETH pool
    }

    function test_pass() public {
        assertTrue(daiEthLPOracle.pass());                           // Verify time interval `hop`has elapsed
        daiEthLPOracle.poke();                                       // Poke oracle
        hevm.warp(add(daiEthLPOracle.zzz(), daiEthLPOracle.hop()));  // Time travel into the future
        assertTrue(daiEthLPOracle.pass());                           // Verify time interval `hop` has elapsed
    }

    function testFail_pass() public {
        daiEthLPOracle.poke();                                       // Poke oracle
        assertTrue(daiEthLPOracle.pass());                           // Fail pass
    }

    function testFail_whitelist_peep() public {
        daiEthLPOracle.poke();                                       // Poke oracle
        (bytes32 val, bool has) = daiEthLPOracle.peep();             // Peep oracle price without caller being whitelisted
        assertTrue(has);                                             // Verify oracle has value
        assertTrue(val != bytes32(0));                               // Verify peep returned value
    }

    function test_whitelist_peep() public {
        daiEthLPOracle.poke();                                       // Poke oracle
        daiEthLPOracle.kiss(address(this));                          // White caller
        (bytes32 val, bool has) = daiEthLPOracle.peep();             // View queued oracle price
        assertTrue(has);                                             // Verify oracle has value
        assertTrue(val != bytes32(0));                               // Verify peep returned valid value
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
        assertTrue(daiEthLPOracle.bud(address(this)) == 0);         // Verify caller is not whitelisted
        daiEthLPOracle.kiss(address(this));                         // Whitelist caller
        assertTrue(daiEthLPOracle.bud(address(this)) == 1);         // Verify caller is whitelisted
    }

    function testFail_kiss() public {
        daiEthLPOracle.deny(address(this));                         // Remove owner
        daiEthLPOracle.kiss(address(this));                         // Attempt to whitelist caller
    }

    function testFail_kiss2() public {
        daiEthLPOracle.kiss(address(0));                            // Attempt to whitelist 0 address
    }

    function test_diss_single() public {
        daiEthLPOracle.kiss(address(this));                         // Whitelist caller
        assertTrue(daiEthLPOracle.bud(address(this)) == 1);         // Verify caller is whitelisted
        daiEthLPOracle.diss(address(this));                         // Remove caller from whitelist
        assertTrue(daiEthLPOracle.bud(address(this)) == 0);         // Verify caller is not whitelisted
    }

    function testFail_diss() public {
        daiEthLPOracle.deny(address(this));                         // Remove owner
        daiEthLPOracle.diss(address(this));                         // Attempt to remove caller from whitelist
    }

    function test_link() public {
        daiEthLPOracle.link(0, TUSD_ORACLE);                        // Replace DAI-ETH LP Oracle orb0 w/ TUSD Oracle
        assertEq(daiEthLPOracle.orb0(), TUSD_ORACLE);               // Verify that DAI-ETH LP Oracle orb0 is TUSD Oracle
    }

    function test_link_poke() public {
        daiEthLPOracle.poke();                                      // Poke DAI-ETH LP Oracle
        daiEthLPOracle.kiss(address(this));                         // Whitelist caller on DAI-ETH LP Oracle
        (bytes32 val1,) = daiEthLPOracle.peep();                    // Read queued price from DAI-ETH LP Oracle
        daiEthLPOracle.link(0, TUSD_ORACLE);                        // Change DAI-ETH LP Oracle orb0 to TUSD Oracle
        hevm.warp(now + 3600);                                      // Time travel 1 hour into the future
        daiEthLPOracle.poke();                                      // Poke DAI-ETH LP Oracle
        (bytes32 val2,) = daiEthLPOracle.peep();                    // Read new queued price from DAI-ETH LP Oracle
        assertEq(val1, val2);                                       // Verify queued prices are the same before and after Oracle swap
    }

    function testFail_link() public {
        daiEthLPOracle.link(1, address(0));                         // Attempt to change DAI-ETH LP Oracle orb1 to 0 address
    }

    function test_eth_dai_price_change() public {
        daiEthLPOracle.poke();                                      // Poke DAI-ETH LP Oracle
        daiEthLPOracle.kiss(address(this));                         // Whitelist caller on DAI-ETH LP Oracle
        (bytes32 val, bool has) = daiEthLPOracle.peep();            // Query queued price of DAI-ETH LP Oracle
        uint256 firstVal = uint256(val);                            // Cast queued price as uint256

        assertTrue(firstVal < 100 ether && firstVal > 50 ether);    // 57327394135985707908 at time of test
        assertTrue(has);                                            // Verify Oracle has valid value

        assertEq(IERC20(DAI).balanceOf(address(this)), 10_000 ether);   // Verify caller has 10,000 DAI
        address[] memory path = new address[](2);                       // Create path param
        path[0] = DAI;                                                  // Trade from DAI
        path[1] = WETH;                                                 // Trade to WETH
        uint[] memory amounts = uniswap.swapExactTokensForTokens(
            IERC20(DAI).balanceOf(address(this)), 0, path, address(this), now); // Trade 10,000 DAI for WETH
        assertEq(amounts.length, 2);                                    // Verify array has 2 elements
        assertEq(amounts[0], 10_000 ether);                             // Verify caller traded 10,000 DAI
        assertEq(IERC20(DAI).balanceOf(address(this)), 0);              // Verify caller has 0 DAI
        assertEq(IERC20(WETH).balanceOf(address(this)), amounts[1]);    // Verify caller has WETH

        // amounts[1] -> WETH
        uint256 diff =
            amounts[1] > 10_000 ether * WAD / ethPrice ?
            amounts[1] - 10_000 ether * WAD / ethPrice :
            10_000 ether * WAD / ethPrice - amounts[1];                 // Calculate difference between trade and Oracle price
        assertTrue(diff * WAD / amounts[1] < 0.02 ether);               // Verify less than 2% slippage

        hevm.warp(now + 3600);                                          // Time travel 1 hour into the future

        daiEthLPOracle.poke();                                          // Poke DAI-ETH LP Oracle
        (val, has) = daiEthLPOracle.peep();                             // Query queued price of DAI-ETH LP Oracle
        uint256 secondVal = uint256(val);                               // Cast queued price as uint256
        assertTrue(secondVal < 100 ether && secondVal > 50 ether);      // 58502000047042694225 at time of test
        assertTrue(has);                                                // Verify Oracle has valid value

        assertTrue(secondVal > firstVal);                               // Verify DAI-ETH LP Oracle price increased

        /*** Trade $200m ETH for DAI ***/
        uint256 ethBal = IERC20(WETH).balanceOf(address(this));         // Get WETH balance of caller
        path = new address[](2);                                        // Create path param
        path[0] = WETH;                                                 // Trade from WETH
        path[1] = DAI;                                                  // Trade to DAI
        amounts = uniswap.swapExactTokensForTokens(
            IERC20(WETH).balanceOf(address(this)), 0, path, address(this), now);    // Trade WETH to DAI
        assertEq(amounts.length, 2);                                    // Verify array has 2 elements
        assertEq(amounts[0], ethBal);                                   // Verify caller traded X WETH
        assertEq(IERC20(WETH).balanceOf(address(this)), 0);             // Verify caller has 0 WETH
        assertEq(IERC20(DAI).balanceOf(address(this)), amounts[1]);     // Verify caller has DAI

        // amounts[1] -> DAI
        diff = amounts[1] > 10_000 ether ? amounts[1] - 10_000 ether : 10_000 ether - amounts[1];   // Calculate difference between trade and $1 peg
        assertTrue(diff * WAD / amounts[1] < 0.02 ether);               // Verify less than 2% slippage

        hevm.warp(now + 3600);                                          // Time travel 1 hour into the future

        daiEthLPOracle.poke();                                          // Poke DAI-ETH LP Oracle
        (val, has) = daiEthLPOracle.peep();                             // Query queued price of DAI-ETH LP Oracle
        uint256 thirdVal = uint256(val);                                // Cast queued price as uint256
        assertTrue(thirdVal < 100 ether && thirdVal > 50 ether);        // 57327409193126552497 at time of test
        assertTrue(has);                                                // Verify Oracle has valid value

        assertTrue(thirdVal > secondVal);                               // Verify DAI-ETH LP Oracle price increased
                                                                        // B/c 'k' increases due to fees so price increases
    }

    function test_eth_wbtc_price_change() public {
        wbtcEthLPOracle.poke();                                         // Poke WBTC-ETH LP Oracle
        wbtcEthLPOracle.kiss(address(this));                            // Whitelist caller on WBTC-ETH LP Oracle
        (bytes32 val, bool has) = wbtcEthLPOracle.peep();               // Query queued price of WBTC-ETH LP Oracle
        uint256 firstVal = uint256(val);                                // Cast queued price as uint256

        assertTrue(firstVal < 900_000_000 ether && firstVal > 600_000_000 ether);   // 704030123759222892060867448 at time of test
        assertTrue(has);                                                // Verify Oracle has valid value

        /*** Trade $10k WBTC for ETH ***/
        assertEq(IERC20(WBTC).balanceOf(address(this)), wbtcMintAmt);   // Verify caller has $10,000 worth of BTC
        address[] memory path = new address[](2);                       // Create path param
        path[0] = WBTC;                                                 // Trade from WBTC
        path[1] = WETH;                                                 // Trade to WETH
        uint[] memory amounts = uniswap.swapExactTokensForTokens(
            IERC20(WBTC).balanceOf(address(this)), 0, path, address(this), now);    // Trade WBTC to WETH
        assertEq(amounts.length, 2);                                    // Verify array has 2 elements
        assertEq(amounts[0], wbtcMintAmt);                              // Verify caller traded away all WBTC
        assertEq(IERC20(WBTC).balanceOf(address(this)), 0);             // Verify caller has 0 WBTC after trade
        assertEq(IERC20(WETH).balanceOf(address(this)), amounts[1]);    // Verify caller got WETH after trade

        uint256 diff =
            amounts[1] > 10_000 ether * WAD / ethPrice ?
            amounts[1] - 10_000 ether * WAD / ethPrice :
            10_000 ether * WAD / ethPrice - amounts[1];                 // Calculate difference between trade and ETH Oracle
        assertTrue(diff * WAD / amounts[1] < 0.02 ether);               // Verify less than 2% slippage

        hevm.warp(now + 3600);                                          // Time travel 1 hour into the future

        wbtcEthLPOracle.poke();                                         // Poke WBTC-ETH LP Oracle
        (val, has) = wbtcEthLPOracle.peep();                            // Query queued price of WBTC-ETH LP Oracle
        uint256 secondVal = uint256(val);                               // Cast queued price as uint256
        assertTrue(secondVal < 900_000_000 ether && secondVal > 600_000_000 ether);     // 704030254653978027824526079 at time of test
        assertTrue(has);                                                // Verify Oracle has valid price

        assertTrue(secondVal > firstVal);                               // Verify price of WBTC-ETH LP token increased afer trade

        /*** Trade ETH for WBTC ***/
        uint256 ethBal = IERC20(WETH).balanceOf(address(this));         // Get caller WETH balance
        path = new address[](2);                                        // Create path param
        path[0] = WETH;                                                 // Trade from WETH
        path[1] = WBTC;                                                 // Trade to WBTC
        amounts = uniswap.swapExactTokensForTokens(
            IERC20(WETH).balanceOf(address(this)), 0, path, address(this), now);    // Trade WETH to WBTC
        assertEq(amounts.length, 2);                                    // Verify array has 2 elements
        assertEq(amounts[0], ethBal);                                   // Verify traded all WETH
        assertEq(IERC20(WETH).balanceOf(address(this)), 0);             // Verify caller has 0 WETH after trade
        assertEq(IERC20(WBTC).balanceOf(address(this)), amounts[1]);    // Verify caller got WBTC after trade

        diff =
            amounts[1] > 10_000 ether * 1E8 / wbtcPrice ?
            amounts[1] - 10_000 ether * 1E8 / wbtcPrice :
            10_000 ether * 1E8 / wbtcPrice - amounts[1];                // Calculate difference between trade and WBTC Oracle
        assertTrue(diff * WAD / amounts[1] < 0.02 ether);               // Verify less than 2% slippage

        hevm.warp(now + 3600);                                          // Time travel 1 hour into the future

        wbtcEthLPOracle.poke();                                         // Poke WBTC-ETH LP Oracle
        (val, has) = wbtcEthLPOracle.peep();                            // Query queued price of WBTC-ETH LP Oracle
        uint256 thirdVal = uint256(val);                                // Cast queued price as uint256
        assertTrue(thirdVal < 900_000_000 ether && thirdVal > 600_000_000 ether);   // 704030385156122678606782694 at time of test
        assertTrue(has);                                                // Verify Oracle has valid value

        assertTrue(thirdVal > secondVal);                               // Verify price of WBTC0ETH LP token increased after trade
    }

    // This test will fail if the value of `val` at peek does not match memory slot 0x3
    function testCurSlot0x3() public {
        daiEthLPOracle.poke();                                       // Poke oracle
        hevm.warp(add(daiEthLPOracle.zzz(), daiEthLPOracle.hop()));  // Time travel into the future
        daiEthLPOracle.poke();                                       // Poke oracle again
        daiEthLPOracle.kiss(address(this));                          // Whitelist caller
        (bytes32 val, bool has) = daiEthLPOracle.peek();             // Peek oracle price without caller being whitelisted
        assertTrue(has);                                             // Verify oracle has value
        assertTrue(val != bytes32(0));                               // Verify peep returned valid value

        // Load memory slot 0x3
        // Keeps `cur` slot parity with OSMs
        bytes32 curPacked = hevm.load(address(daiEthLPOracle), bytes32(uint256(3)));

        bytes16 memhas;
        bytes16 memcur;
        assembly {
            memhas := curPacked
            memcur := shl(128, curPacked)
        }

        assertTrue(uint256(uint128(memcur)) > 0);          // Assert nxt has value
        assertEq(uint256(val), uint256(uint128(memcur)));  // Assert slot value == cur
        assertEq(uint256(uint128(memhas)), 1);             // Assert slot has == 1
    }

    // This test will fail if the value of `val` at peep does not match memory slot 0x4
    function testNxtSlot0x4() public {
        daiEthLPOracle.poke();                                       // Poke oracle
        hevm.warp(add(daiEthLPOracle.zzz(), daiEthLPOracle.hop()));  // Time travel into the future
        daiEthLPOracle.poke();                                       // Poke oracle again
        daiEthLPOracle.kiss(address(this));                          // Whitelist caller
        (bytes32 val, bool has) = daiEthLPOracle.peep();             // Peep oracle price without caller being whitelisted
        assertTrue(has);                                             // Verify oracle has value
        assertTrue(val != bytes32(0));                               // Verify peep returned valid value

        // Load memory slot 0x4
        // Keeps `nxt` slot parity with OSMs
        bytes32 nxtPacked = hevm.load(address(daiEthLPOracle), bytes32(uint256(4)));

        bytes16 memhas;
        bytes16 memnxt;
        assembly {
            memhas := nxtPacked
            memnxt := shl(128, nxtPacked)
        }

        assertTrue(uint256(uint128(memnxt)) > 0);          // Assert nxt has value
        assertEq(uint256(val), uint256(uint128(memnxt)));  // Assert slot value == nxt
        assertEq(uint256(uint128(memhas)), 1);             // Assert slot has == 1
    }
}
