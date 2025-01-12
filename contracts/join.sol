// SPDX-License-Identifier: AGPL-3.0-or-later

/// join.sol -- Basic token adapters

// Copyright (C) 2018 Rain <rainbreak@riseup.net>
//
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

pragma solidity ^0.8.10;

import "./interfaces/GemJoinLike.sol";
import "./interfaces/SikkaJoinLike.sol";
import "./interfaces/GemLike.sol";
import "./interfaces/VatLike.sol";
import "./interfaces/ISikka.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
// FIXME: This contract was altered compared to the production version.
// It doesn't use LibNote anymore.
// New deployments of this contract will need to include custom events (TO DO).

/*
    Here we provide *adapters* to connect the Vat to arbitrary external
    token implementations, creating a bounded context for the Vat. The
    adapters here are provided as working examples:
      - `GemJoin`: For well behaved ERC20 tokens, with simple transfer
                   semantics.
      - `ETHJoin`: For native Ether.
      - `SikkaJoin`: For connecting internal Sikka balances to an external
                   `DSToken` implementation.
    In practice, adapter implementations will be varied and specific to
    individual collateral types, accounting for different transfer
    semantics and token standards.
    Adapters need to implement two basic methods:
      - `join`: enter collateral into the system
      - `exit`: remove collateral from the system
*/

contract GemJoin is Initializable, GemJoinLike {
    // --- Auth ---
    mapping (address => uint) public wards;
    function rely(address usr) external auth {
        wards[usr] = 1;
        emit Rely(usr);
    }
    function deny(address usr) external auth {
        wards[usr] = 0;
        emit Deny(usr);
    }
    modifier auth {
        require(wards[msg.sender] == 1, "GemJoin/not-authorized");
        _;
    }

    VatLike public vat;   // CDP Engine
    bytes32 public ilk;   // Collateral Type
    GemLike public gem;
    uint    public dec;
    uint    public live;  // Active Flag

    // Events
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event Join(address indexed usr, uint256 wad);
    event Exit(address indexed usr, uint256 wad);
    event Cage();

    // --- Init ---
    function initialize(address vat_, bytes32 ilk_, address gem_) public initializer {
        wards[msg.sender] = 1;
        live = 1;
        vat = VatLike(vat_);
        ilk = ilk_;
        gem = GemLike(gem_);
        dec = gem.decimals();
        emit Rely(msg.sender);
    }
    function cage() external auth {
        live = 0;
        emit Cage();
    }
    function join(address usr, uint wad) external auth {
        require(live == 1, "GemJoin/not-live");
        require(int(wad) >= 0, "GemJoin/overflow");
        vat.slip(ilk, usr, int(wad));
        require(gem.transferFrom(msg.sender, address(this), wad), "GemJoin/failed-transfer");
        emit Join(usr, wad);
    }
    function exit(address usr, uint wad) external auth {
        require(wad <= (2 ** 255) - 1, "GemJoin/overflow");
        vat.slip(ilk, msg.sender, -int(wad));
        require(gem.transfer(usr, wad), "GemJoin/failed-transfer");
        emit Exit(usr, wad);
    }
}

contract SikkaJoin is Initializable, SikkaJoinLike {
    // --- Auth ---
    mapping (address => uint) public wards;
    function rely(address usr) external auth {
        wards[usr] = 1;
        emit Rely(usr);
    }
    function deny(address usr) external auth {
        wards[usr] = 0;
        emit Deny(usr);
    }
    modifier auth {
        require(wards[msg.sender] == 1, "SikkaJoin/not-authorized");
        _;
    }

    VatLike public vat;      // CDP Engine
    ISikka public sikka;  // Stablecoin Token
    uint    public live;     // Active Flag

    // Events
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event Join(address indexed usr, uint256 wad);
    event Exit(address indexed usr, uint256 wad);
    event Cage();

    // --- Init ---
    function initialize(address vat_, address sikka_) public initializer {
        wards[msg.sender] = 1;
        live = 1;
        vat = VatLike(vat_);
        sikka = ISikka(sikka_);
    }
    function cage() external auth {
        live = 0;
        emit Cage();
    }
    uint constant ONE = 10 ** 27;
    function mul(uint x, uint y) internal pure returns (uint z) {
        unchecked {
            require(y == 0 || (z = x * y) / y == x);
        }
    }
    function join(address usr, uint wad) external auth {
        vat.move(address(this), usr, mul(ONE, wad));
        sikka.burn(msg.sender, wad);
        emit Join(usr, wad);
    }
    function exit(address usr, uint wad) external auth {
        require(live == 1, "SikkaJoin/not-live");
        vat.move(msg.sender, address(this), mul(ONE, wad));
        sikka.mint(usr, wad);
        emit Exit(usr, wad);
    }
}