// SPDX-License-Identifier: GPL-3.0-or-later

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
//    Methodology for Calculating LP Token Price     //
//                                                   //
///////////////////////////////////////////////////////

// Two-asset constant product pools, neglecting fees, satisfy (before and after trades):
//
// r_0 * r_1 = k                (1)
//
// where r_0 and r_1 are the reserves of the two tokens held by the pool.
// The price of LP tokens (i.e. pool shares) needs to be evaluated based on 
// reserve values r_0 and r_1 that cannot be arbitraged, i.e. values that
// give the two halves of the pool equal economic value:
//
// r_0 * p_0 = r_1 * p_1        (2)
// 
// (p_i is the price of pool asset i in some reference unit of account).
// Using (1) and (2) we can compute the arbitrage-free reserve values in a manner
// that depends only on k (which can be derived from the current reserve balances,
// even if they are far from equilibrium) and market prices p_i obtained from a trusted source:
//
// r_0 = sqrt(k * p_1 / p_0)    (3)
//   and
// r_1 = sqrt(k * p_0 / p_1)    (4)
//
// The value of an LP token is then, combining (3) and (4):
//
// (p_0 * r_0 + p_1 * r_1) / LP_supply = 2 * sqrt(k * p_0 * p_1) / LP_supply

pragma solidity ^0.6.11;

interface ERC20Like {
    function decimals()         external view returns (uint8);
    function balanceOf(address) external view returns (uint256);
    function totalSupply()      external view returns (uint256);
}

interface UniswapV2PairLike {
    function sync()        external;
    function token0()      external view returns (address);
    function token1()      external view returns (address);
    function getReserves() external view returns (uint112,uint112,uint32);  // reserve0, reserve1, blockTimestampLast
}

interface OracleLike {
    function read() external view returns (uint256);
    function peek() external view returns (uint256,bool);
}

// Factory for creating Uniswap V2 LP Token Oracle instances
contract UNIV2LPOracleFactory {

    mapping(address => bool) public isOracle;

    event Created(address sender, address orcl, bytes32 wat, address tok0, address tok1, address orb0, address orb1);

    // Create new Uniswap V2 LP Token Oracle instance
    function build(address _src, bytes32 _wat, address _orb0, address _orb1) public returns (address orcl) {
        address tok0 = UniswapV2PairLike(_src).token0();
        address tok1 = UniswapV2PairLike(_src).token1();
        orcl = address(new UNIV2LPOracle(_src, _wat, _orb0, _orb1));
        UNIV2LPOracle(orcl).rely(msg.sender);
        isOracle[orcl] = true;
        emit Created(msg.sender, orcl, _wat, tok0, tok1, _orb0, _orb1);
    }
}

contract UNIV2LPOracle {

    // --- Auth ---
    mapping (address => uint) public wards;                                       // Addresses with admin authority
    function rely(address usr) external auth { wards[usr] = 1; emit Rely(usr); }  // Add admin
    function deny(address usr) external auth { wards[usr] = 0; emit Deny(usr); }  // Remove admin
    modifier auth {
        require(wards[msg.sender] == 1, "UNIV2LPOracle/not-authorized");
        _;
    }

    address public src;             // Price source
    uint16  public hop = 1 hours;   // Minimum time inbetween price updates
    uint64  public zzz;             // Time of last price update
    bytes32 public immutable wat;   // Token whose price is being tracked

    // --- Whitelisting ---
    mapping (address => uint256) public bud;
    modifier toll { require(bud[msg.sender] == 1, "UNIV2LPOracle/contract-not-whitelisted"); _; }

    struct Feed {
        uint128 val;  // Price
        uint128 has;  // Is price valid
    }

    Feed    internal cur;  // Current price  (mem slot 0x3)
    Feed    internal nxt;  // Queued price   (mem slot 0x4)

    // --- Stop ---
    uint256 public stopped;  // Stop/start ability to read
    modifier stoppable { require(stopped == 0, "UNIV2LPOracle/is-stopped"); _; }

    // --- Data ---
    uint256 private immutable normalizer0;  // Multiplicative factor that normalizes a token0 balance to a WAD; 10^(18 - dec)
    uint256 private immutable normalizer1;  // Multiplicative factor that normalizes a token1 balance to a WAD; 10^(18 - dec)

    address public            orb0;  // Oracle for token0, ideally a Medianizer
    address public            orb1;  // Oracle for token1, ideally a Medianizer

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
    // Compute the square root using the Babylonian method.
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

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event Change(address indexed src);
    event Step(uint256 hop);
    event Stop();
    event Start();
    event Value(uint128 curVal, uint128 nxtVal);
    event Link(uint256 id, address orb);
    event Kiss(address a);
    event Diss(address a);

    // --- Init ---
    constructor (address _src, bytes32 _wat, address _orb0, address _orb1) public {
        require(_src  != address(0),                        "UNIV2LPOracle/invalid-src-address");
        require(_orb0 != address(0) && _orb1 != address(0), "UNIV2LPOracle/invalid-oracle-address");
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
        src  = _src;
        wat  = _wat;
        normalizer0 = 10 ** sub(18, uint256(ERC20Like(UniswapV2PairLike(_src).token0()).decimals()));  // Calculate normalization factor of token0
        normalizer1 = 10 ** sub(18, uint256(ERC20Like(UniswapV2PairLike(_src).token1()).decimals()));  // Calculate normalization factor of token1
        orb0 = _orb0;
        orb1 = _orb1;
    }

    function stop() external auth {
        stopped = 1;
        delete cur;
        delete nxt;
        zzz = 0;
        emit Stop();
    }

    function start() external auth {
        stopped = 0;
        emit Start();
    }

    function change(address _src) external auth {
        src = _src;
        emit Change(src);
    }

    function step(uint256 _hop) external auth {
        require(_hop <= uint16(-1), "UNIV2LPOracle/invalid-hop");
        hop = uint16(_hop);
        emit Step(hop);
    }

    function link(uint256 id, address orb) external auth {
        require(orb != address(0), "UNIV2LPOracle/no-contract-0");
        if(id == 0) {
            orb0 = orb;
        } else if (id == 1) {
            orb1 = orb;
        }
        emit Link(id, orb);
    }

    function pass() public view returns (bool ok) {
        return block.timestamp >= add(zzz, hop);
    }

    function seek() internal returns (uint128 quote, uint32 ts) {
        // Sync up reserves of uniswap liquidity pool
        UniswapV2PairLike(src).sync();

        // Get reserves of uniswap liquidity pool
        (uint112 res0, uint112 res1, uint32 _ts) = UniswapV2PairLike(src).getReserves();
        require(res0 > 0 && res1 > 0, "UNIV2LPOracle/invalid-reserves");
        ts = _ts;
        require(ts == block.timestamp);

        // Adjust reserves w/ respect to decimals
        // TODO: is the risk of overflow here worth mitigating? (consider an attacker who can mint a token at will)
        if (normalizer0 > 1) res0 = uint112(res0 * normalizer0);
        if (normalizer1 > 1) res1 = uint112(res1 * normalizer1);

        // Calculate constant product invariant k (WAD * WAD)
        uint256 k = mul(res0, res1);

        // All Oracle prices are priced with 18 decimals against USD
        uint256 val0 = OracleLike(orb0).read();  // Query token0 price from oracle (WAD)
        uint256 val1 = OracleLike(orb1).read();  // Query token1 price from oracle (WAD)
        require(val0 != 0, "UNIV2LPOracle/invalid-oracle-0-price");
        require(val1 != 0, "UNIV2LPOracle/invalid-oracle-1-price");

        // Get LP token supply
        uint256 supply = ERC20Like(src).totalSupply();

        // No need to check that the supply is nonzero, Solidity reverts on division by zero.
        quote = uint128(
                mul(2 * WAD, sqrt(wmul(k, wmul(val0, val1))))
                    / supply
        );
    }

    function poke() external stoppable {
        require(pass(), "UNIV2LPOracle/not-passed");
        (uint val, uint32 ts) = seek();
        require(val != 0, "UNIV2LPOracle/invalid-price");
        cur = nxt;
        nxt = Feed(uint128(val), 1);
        zzz = ts;
        emit Value(cur.val, nxt.val);
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
        emit Kiss(a);
    }

    function kiss(address[] calldata a) external auth {
        for(uint i = 0; i < a.length; i++) {
            require(a[i] != address(0), "UNIV2LPOracle/no-contract-0");
            bud[a[i]] = 1;
            emit Kiss(a[i]);
        }
    }

    function diss(address a) external auth {
        bud[a] = 0;
        emit Diss(a);
    }

    function diss(address[] calldata a) external auth {
        for(uint i = 0; i < a.length; i++) {
            bud[a[i]] = 0;
            emit Diss(a[i]);
        }
    }
}
