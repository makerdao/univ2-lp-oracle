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

//Notes
//  - no kLast if fees aren't turned on.
//  - need to add logic for changing token0/token1 oracle
//INVARIANT = SHARE_ETH_BALANCE * SHARE_DAI_BALANCE
//BAL_ETH = SQRT(INVARIANT / ETHUSD)
//BAL_DAI = SQRT(INVARIANT / (1 / ETHUSD))          // (USDETH === 1 / ETHUSD)
//SHARE_VALUE = (BAL_ETH * ETHUSD) + (BAL_DAI * 1)  // Value in USD
//
//Ways to calculate price:
//1. Get balance of token0 and token1 (e.g. ETH & DAI). Then use OSM prices for token0 and token1 to calculates total value of reserves in USD. THen divide by LP token supply to get value of 1 LP token. The downside here is that by using the OSM value, you're using a value that is already 1 hour "stale" which skews the LP token Oracle price which itself doesn't go live until an hour into the future. So by the time the LP token price goes into effect, it's using a 2 hour old ETH price. The other show-stopper
//is that someone can do a big trade, `poke`, and then unwind. This manipulates the component balances (but not the product!).
//
//2. Same as (1) except use the Medianizer price. This solves the stale pricing problem. And since LP token values undergo an OSM delay there's no increased risk of an Oracle gov attack. This still suffers from the trade->poke->unwind exploit.
//
//3. Instead of using 2 Oracles, use the ratio of the reserves to calculate the value of the pool in a single token before
// applying a single Oracle (medianizer) to convert to USD. Then divide by LP token supply.
//
//4. Using the reserves of Uniswap to determine price within a single block is dangerous. Instead one can utilize the property
// of Uniswap using a accumulator to deterine the price between two points in time. This makes it much more expensive for an
// attacker to manipulate the price on Uniswap. By storing the value of price0CumululativeLatest each time `poke` is called we 
// can always have a second reference point for use on subsequent `poke`.
//
//5. 
//
//

pragma solidity ^0.6.7;

import "UQ112x112";

interface UniswapV2PairLike {
    function sync() external;
    function price0CumulativeLast() external view returns (uint256);
    function price1CumulativeLast() external view returns (uint256);
    function getReserves() external view returns (uint112,uint112,uint32);  //reserve0,reserve1,blockTimestampLast
}

interface OSMLike {
    function peek() external view returns (bytes32,bool);
}

contract UNIV2LPOracleFactory {
    
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

    UniswapV2PairLike   public  src;   //price source
	uint32              public  zzz;   //time of last price update
	bytes32             public  wat;   //token whose price is being tracked

     struct Feed {
        uint128 val;    //price
        uint128 has;    //is price valid
    }

    Feed    public  cur;   //curent price
    Feed    public  nxt;   //queued price

    uint256 public  priceCumulativeLast = 0;    //price accumulator for selected price ref
    OSMLike public  tokenOracle;                //Oracle for token0
    bool    public  selector;                   //token0 (false) or token1 (true) to select price ref

    // Whitelisted contracts, set by an auth
    mapping (address => uint256) public bud;

    modifier toll { require(bud[msg.sender] == 1, "UNIV2LPOracle/contract-not-whitelisted"); _; }

    constructor (address _src, bytes32 _wat, bool _selector, address _tokenOracle) public {
        wards[msg.sender] = 1;
        src = UniswapV2PairLike(_src);
        wat = _wat;
        selector = _selector;
        tokenOracle = OSMLike(_tokenOracle);
    }

    function change(address _src) external auth {
        src = UniswapV2PairLike(_src);
    }

    function stop() external auth {
        stopped = 1;
    }
    function start() external auth {
        stopped = 0;
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

    function poke() external {
        src.sync();
        uint _priceCumulativeLast = (selector) ? src.price1CumulativeLast() : src.price0CumulativeLast();
        (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) = src.getReserves();
        if (priceCumulativeLast == 0) {
            priceCumulativeLast = _priceCumulativeLast;
            zzz = _blockTimestampLast;
            return;
        }


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

