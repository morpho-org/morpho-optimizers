// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.10;

import "./MorphoStorage.sol";

contract ERC721POC is MorphoStorage {
    address immutable poolToken;
    address immutable underlyingToken;

    constructor(address _poolToken) {
        poolToken = _poolToken;
        underlyingToken = IAToken(_poolToken).UNDERLYING_TOKEN_ADDRESS();
    }

    function balanceOf(address _owner) external view returns (uint256) {
        return uint256(isSupplying(_owner));
    }

    function safeTransferFrom(
        address _from,
        address _to,
        uint256 _id
    ) external {
        // ...

        // Issue here because you can end up with multiple NFTs in your wallet for the same market.
        // So perhaps a transfer should either:
        //  - Transfer the NFT as usual if _to has no NFT.
        //  - Burn this NFT and increase _to's balance if it already has a balance.
        // Perhaps it does not break the standard.

        // Check: that the account without this position is above water.
        if (!isLiquidatable(_from, _poolToken)) {
            _balanceOf[from]--;
            _balanceOf[to]++;
        }

        // ...
    }

    function supplyScaledBalances(address _owner) external returns (Types.SupplyBalance) {
        return supplyBalanceInOf[poolToken][_owner];
    }

    function borrowScaledBalances(address _owner) external returns (Types.BorrowBalance) {
        return borrowBalanceInOf[poolToken][_owner];
    }
}
