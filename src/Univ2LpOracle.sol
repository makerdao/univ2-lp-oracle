/// UNIV2LPOracle.sol

// Copyright (C) 2017-2020 Maker Ecosystem Growth Holdings, INC.

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

///////////////////////////////////////////////////////
//                                                   //
//    Methodology for caclulating LP Token Price     //
//                                                   //
///////////////////////////////////////////////////////

// INVARIANT k = reserve0 [num token0] * reserve1 [num token1] //need to take into account decimals of LP component tokens
//
// k = r_x * r_y
// r_y = k / r_x
//
// 50-50- pools try to stay balanced in dollar terms
// r_x * p_x = r_y * p_y    //the proportion of r_x and r_y can be manipulated so need to normalize them
//
// r_x * p_x = p_y (k / r_x)
// r_x^2 = k * p_y / p_x
// r_x = sqrt(k * p_y / p_x) & r_y = sqrt(k * p_x / p_y)
//
// now that we've calculated normalized values of r_x and r_y that are not prone to manipulation by an attacker,
// we can calculate the price of an lp token using the following formula. 
//
// p_lp = (r_x * p_x + r_y * p_y) / supply_lp
//
// [OPTIONAL] Maker Oracles vs Uniswap Oracles
// Note the Uniswap Oracle price is the TWAP over the interval t2 - t1 (in our case 1 hour)
// This means when the price volatility > 2% the calculated price could be quite inaccurate.
// It is better to use the MakerDAO Medianizer price as it updates on a 0.5%/1% spread
// It's "safe" to use the Medianizer value because the `cur` price undergoes the OSM delay `hop`
// Nonetheless for completeness below is a manner of utilizing the Uniswap Oracle.
//
// whats cool about the equation r_x = sqrt(k * p_y / p_x)  & r_y = sqrt(k * p_x / p_y)
// is that we can get the price ratio of p_y / p_x and p_x / p_y through priceCumulativeList
// (this is essentially Uniswap's Oracle)
// price0CumulativeLast is the price of token x denominated in token y
// price1CumulativeLast is the price of token y denominated in token x
// to convert price#CumulativeLast into a usable number we need to take 2 reference points at different times.
// p_x / p_y = (priceXCumulativeLatest_2 - priceXCumulativeLatest_1) / (t2 - t1)
// this ratio can then be used to calculate the normalized reserves
// ultimately for pools where neither component is pegged to USD a single external Oracle would still be necessary

pragma solidity ^0.5.12;

import "./UQ112x112.sol";

interface ERC20Like {
    function decimals() external view returns (uint8);
    function balanceOf(address) external view returns (uint256);
    function totalSupply() external view returns (uint256);   
}

interface UniswapV2PairLike {    function sync() external;
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112,uint112,uint32);  //reserve0,reserve1,blockTimestampLast

}

interface OracleLike {
    function read() external view returns (uint256);
    function peek() external view returns (uint256,bool);
}

//Factory for creating UNIV2LPOracle instances
contract UNIV2LPOracleFactory {

    // --- Auth ---
    mapping (address => uint) public wards;                         //addresses with admin authority
    function rely(address usr) external auth { wards[usr] = 1; }    //add admin
    function deny(address usr) external auth { wards[usr] = 0; }    //remove admin
    modifier auth {
        require(wards[msg.sender] == 1, "UNIV2LPOracle/not-authorized");
        _;
    }

    mapping(address=>bool) public isOracle;
    mapping(address=>mapping(address=>address)) public register;

    event Created(address sender, address oracle, address token0, address token1, bytes32 name);

    function build(address UNIV2LP, bytes32 wat, address token0Oracle, address token1Oracle) public returns (address oracle) {
        address token0 = UniswapV2PairLike(UNIV2LP).token0();
        address token1 = UniswapV2PairLike(UNIV2LP).token1();
        require(register[token0][token1] == address(0), "UNIV2LPOracleFactory/oracle-already-exists");
        oracle = address(new UNIV2LPOracle(UNIV2LP, wat, token0Oracle, token1Oracle));
        register[token0][token1] = oracle;
        isOracle[oracle] = true;
        emit Created(msg.sender, oracle, token0, token1, wat);
    }

    function delist(address oracle) public auth {
        require(isOracle[oracle], "UNIVPLPOracleFactory/not-an-oracle");
        address src = UNIV2LPOracle(oracle).src();
        address token0 = UniswapV2PairLike(src).token0();
        address token1 = UniswapV2PairLike(src).token1();
        isOracle[oracle] = false;
        register[token0][token1] = address(0);
    }
}

contract UNIV2LPOracle {

    using UQ112x112 for uint224;

	// --- Auth ---
    mapping (address => uint) public wards;                         //addresses with admin authority
    function rely(address usr) external auth { wards[usr] = 1; }    //add admin
    function deny(address usr) external auth { wards[usr] = 0; }    //remove admin
    modifier auth {
        require(wards[msg.sender] == 1, "UNIV2LPOracle/not-authorized");
        _;
    }

    // --- Stop ---
    uint256 public stopped;     //stop/start ability to read
    modifier stoppable { require(stopped == 0, "UNIV2LPOracle/is-stopped"); _; }

    // --- Math ---
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

    address    public  src;   //price source
    uint32     public  zzz;   //time of last price update
    bytes32    public  wat;   //token whose price is being tracked

    uint16     constant ONE_HOUR = uint16(3600);
    uint16     public  hop = ONE_HOUR;  //minimum time inbetween price updates

    uint8      public  token0Decimals = uint8(1);  //decimals of token0
    uint8      public  token1Decimals = uint8(1);  //decimals of token1

     struct Feed {
        uint128 val;    //price
        uint128 has;    //is price valid
    }

    Feed    public  cur;   //curent price
    Feed    public  nxt;   //queued price

    address public  token0Oracle;       //Oracle for token0, ideally a Medianizer
    address public  token1Oracle;       //Oracle for token1, ideally a Medianizer

    uint256 constant WAD = 10 ** 18;

    // Whitelisted contracts, set by an auth
    mapping (address => uint256) public bud;

    modifier toll { require(bud[msg.sender] == 1, "UNIV2LPOracle/contract-not-whitelisted"); _; }

    event LogValue(uint128 val);
    event Debug(uint i, uint val);

    constructor (address _src, bytes32 _wat, address _token0Oracle, address _token1Oracle) public {
        wards[msg.sender] = 1;
        src = _src;
        zzz = 0;
        wat = _wat;
        token0Decimals = uint8(ERC20Like(UniswapV2PairLike(_src).token0()).decimals());     //get decimals of token0
        token1Decimals = uint8(ERC20Like(UniswapV2PairLike(_src).token1()).decimals());     //get decimals of token1
        token0Oracle = _token0Oracle;
        token1Oracle = _token1Oracle;
    }

    function change(address _src) external auth {
        src = _src;
    }

    function stop() external auth {
        stopped = 1;
    }
    function start() external auth {
        stopped = 0;
    }

    function pass() public view returns (bool ok) {
        return block.timestamp >= add(zzz, hop);
    }

    function seek() public returns (uint128 lpTokenPrice_, uint32 zzz_) {
        UniswapV2PairLike(src).sync();

        (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) = UniswapV2PairLike(src).getReserves();  //pull reserves
        require(_blockTimestampLast == block.timestamp);
        emit Debug(0, _reserve0);
        emit Debug(1, _reserve1);

        // adjust reserves w/ respect to decimals 
        if (token0Decimals != uint8(18)) {
            _reserve0 = uint112(_reserve0 * 10 ** sub(18, token0Decimals));
        }
        if (token1Decimals != uint8(18)) {
            _reserve1 = uint112(_reserve1 * 10 ** sub(18, token1Decimals));
        }
        
        emit Debug(10, _reserve0);
        emit Debug(11, _reserve1);

        uint k = mul(_reserve0, _reserve1);                 // Calculate constant product invariant k (WAD * WAD)
        emit Debug(2, k);

        // All Oracle prices are priced with 18 decimals against USD
        uint token0Price = OracleLike(token0Oracle).read(); // Query token0 price from oracle (WAD)
        emit Debug(3, token0Price);
        uint token1Price = OracleLike(token1Oracle).read(); // Query token1 price from oracle (WAD)
        emit Debug(4, token1Price);

        uint normReserve0 = sqrt(wmul(k, wdiv(token1Price, token0Price)));  // Get token0 balance (WAD)
        emit Debug(20, normReserve0);
        uint normReserve1 = wdiv(k, normReserve0) / WAD;                    // Get token1 balance; gas-savings
        emit Debug(21, normReserve1);

        uint lpTokenSupply = ERC20Like(src).totalSupply();                  // Get LP token supply
        emit Debug(5, lpTokenSupply);

        lpTokenPrice_ = uint128(
            wdiv(
                add(
                    wmul(normReserve0, token0Price), // (WAD)
                    wmul(normReserve1, token1Price)  // (WAD)
                ), 
                lpTokenSupply // (WAD)
            )
        );
        emit Debug(6, lpTokenPrice_);   
        zzz_ = _blockTimestampLast; // Update timestamp
    }

    function poke() external stoppable {
        require(pass(), "UNIV2LPOracle/not-passed");
        (uint _val, uint32 _zzz) = seek();
        require(_val != 0, "UNIV2LPOracle/invalid-price");
        cur = nxt;
        nxt = Feed(uint128(_val), 1);
        zzz = _zzz;
        emit LogValue(cur.val);
    }

    function peek() external view toll returns (bytes32,bool) {
        return (bytes32(uint(cur.val)), cur.has == 1);
    }

    function peep() external view toll returns (bytes32,bool) {
        return (bytes32(uint(nxt.val)), nxt.has == 1);
    }

    function read() external view toll returns (bytes32) {
        require(cur.has == 1, "UNIV2LPOracle/no-current-value");
        return (bytes32(uint(cur.val)));
    }

    function kiss(address a) external auth {
        require(a != address(0), "UNIV2LPOracle/no-contract-0");
        bud[a] = 1;
    }

    function diss(address a) external auth {
        bud[a] = 0;
    }

    function kiss(address[] calldata a) external auth {
        for(uint i = 0; i < a.length; i++) {
            require(a[i] != address(0), "UNIV2LPOracle/no-contract-0");
            bud[a[i]] = 1;
        }
    }

    function diss(address[] calldata a) external auth {
        for(uint i = 0; i < a.length; i++) {
            bud[a[i]] = 0;
        }
    }
}