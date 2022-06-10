// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "@contracts/common/ERC4626.sol";
import "./interfaces/compound/ICompound.sol";

/// @title Karl.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice ERC4626 tokenized Vault implementation for Morpho-Compound.
contract Karl is ERC4626 {
    /// STORAGE ///

    IMorpho public immutable morpho;
    ICToken public immutable poolToken;

    constructor(
        IMorpho _morpho,
        ICToken _poolToken,
        string memory _name,
        string memory _symbol
    ) ERC4626(_poolToken.underlying(), _name, _symbol) {
        morpho = _morpho;
    }

    function beforeWithdraw(uint256 _amount, uint256 _shares) internal override {
        morpho.withdraw(address(poolToken), _amount);
    }

    function afterDeposit(uint256 _amount, uint256 _shares) internal override {
        underlyingToken.safeApprove(address(morpho), _amount);
        morpho.supply(address(poolToken), address(this), _amount);
    }
}
