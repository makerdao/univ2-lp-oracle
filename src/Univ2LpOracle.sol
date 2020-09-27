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

//How to Calculate LP Token Price:
//
// INVARIANT k = reserve0 [num token0] * reserve1 [num token1] //need to take into account decimals of LP component tokens
//
// k = r_x * r_y
// r_y = k / r_x
//
// 50-50- pools try to stay balanced in dollar terms
// r_x * p_x = r_y * p_y    //the proportion of r_x and r_y can be manipulated so need to calc them
//
// r_x * p_x = p_y (k / r_x)
// r_x^2 = k * p_y / p_x
// r_x = sqrt(k * p_y / p_x) & r_y = sqrt(k * p_x / p_y)
// ^^^whats cool about this equation is that we can get the price ratio of p_y / p_x through priceCumulativeList
// (this is essentially Uniswap's Oracle)
// price0CumulativeLast is the price of token x denominated in token y
// price1CumulativeLast is the price of token y denominated in token x
// to convert price#CumulativeLast into a usable number we need to take 2 reference points at different times.
// p_x / p_y = (price0CumulativeLatest_2 - price0CumulativeLatest_1) / (t2 - t1)
// 
// now that we've calculated normalized values of r_x and r_y that are not prone to manipulation by an attacker,
// we can calculate the price of an lp token using the following formula. 
//
// p_lp = (r_x * p_x + r_y * p_y) / supply_lp
//
//
// Alternatively this is what someone on the Maker Forum came up with for V1 which looks very similar.
//  BAL_ETH = SQRT( k / ETHUSD)
//  BAL_DAI = SQRT( k / (1 / ETHUSD))          // (USDETH === 1 / ETHUSD)
//  LP Share (USD) = (BAL_ETH * ETHUSD) + (BAL_DAI * 1)
//  LP Price (USD) = LP Share / LP Token Supply

pragma solidity ^0.6.7;

import "UQ112x112/UQ112x112.sol";

interface ERC20Like {
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint256);   
}

interface UniswapV2PairLike {
    function sync() external;
    function token0() external view returns (address);
    function token1() external view returns (address);
    function price0CumulativeLast() external view returns (uint256);
    function price1CumulativeLast() external view returns (uint256);
    function getReserves() external view returns (uint112,uint112,uint32);  //reserve0,reserve1,blockTimestampLast
}

interface OracleLike {
    function read() external view returns (uint256);
    function peek() external view returns (uint256,bool);
}

//Factory for producting UNIVLPOracle instances
contract UNIV2LPOracleFactory {
    //TODO
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
    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x, "ds-math-mul-overflow");
    }
    function div(uint x, uint y) internal pure returns (uint z) {
        require(y > 0 && (z = x / y) * y == x, "ds-math-divide-by-zero");
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

    uint8      public  token0Decimals;  //decimals of token0
    uint8      public  token1Decimals;  //decimals of token1

     struct Feed {
        uint128 val;    //price
        uint128 has;    //is price valid
    }

    Feed    public  cur;   //curent price
    Feed    public  nxt;   //queued price

    address public  token0Oracle;       //Oracle for token0, ideally a Medianizer
    address public  token1Oracle;       //Oracle for token1, ideally a Medianizer

    // Whitelisted contracts, set by an auth
    mapping (address => uint256) public bud;

    modifier toll { require(bud[msg.sender] == 1, "UNIV2LPOracle/contract-not-whitelisted"); _; }

    event LogValue(uint128 val);

    constructor (address _src, bytes32 _wat, address _token0Oracle, address _token1Oracle) public {
        wards[msg.sender] = 1;
        src = _src;
        zzz = 0;
        wat = _wat;
        token0Decimals = ERC20Like(UniswapV2PairLike(_src).token0).decimals;    //get decimals of token0
        token1Decimals = ERC20Like(UniswapV2PairLike(_src).token1).decimals;     //get decimals of token1
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

        uint k = mul(_reserve0, _reserve1);                 //calculate constant product invariant k

        //all Oracle prices are priced with 18 decimals against USD
        uint token0Price = OracleLike(token0Oracle).read(); //query token0 price from oracle
        uint token1Price = OracleLike(token1Oracle).read(); //query token1 price from oracle

        //todo - use priceCumulativeLast in place of p_y / p_x from external oracles for better accuracy when calculating balances
        // formula: (py / px) = (priceCumulativeLast2 - priceCumulativeLast1) / (t2 - t1)
        //^^^ this requires we track priceCumulativeLast in storage for future ref point
        uint balToken0 = sqrt(mul(k, div(token1Price, token0Price)));   //get token0 balance
        uint balToken1 = div(k, balToken0);                             //get token1 balance; gas-savings

        uint lpTokenSupply = ERC20Like(src).totalSupply();      //get LP token supply

        lpTokenPrice_ = div(add(mul(balToken0,token0Price),mul(balToken1,token1Price)),lpTokenSupply);   //calculate LP token price

        zzz_ = _blockTimestampLast;                         //update timestamp
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

