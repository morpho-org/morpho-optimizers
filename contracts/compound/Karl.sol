// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "@contracts/common/ERC4626.sol";

import "./libraries/CompoundMath.sol";
import "./interfaces/compound/ICompound.sol";
import "./interfaces/IMorpho.sol";
import "./libraries/Types.sol";

/// @title Karl.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice ERC4626 tokenized Vault implementation for Morpho-Compound.
contract Karl is ERC4626 {
    using SafeTransferLib for ERC20;
    using CompoundMath for uint256;

    /// STORAGE ///

    IMorpho public immutable morpho;
    ICToken public immutable poolToken;

    constructor(
        IMorpho _morpho,
        ICToken _poolToken,
        string memory _name,
        string memory _symbol
    ) ERC4626(ERC20(_poolToken.underlying()), _name, _symbol) {
        morpho = _morpho;
        poolToken = _poolToken;
    }

    function totalAssets() public view override returns (uint256) {
        Types.SupplyBalance memory supplyBalance = morpho.supplyBalanceInOf(
            address(poolToken),
            address(this)
        );
        uint256 p2pSupplyIndex = morpho.p2pSupplyIndex(address(poolToken));
        uint256 poolSupplyIndex = poolToken.exchangeRateStored();

        return supplyBalance.onPool.mul(poolSupplyIndex) + supplyBalance.inP2P.mul(p2pSupplyIndex);
    }

    function beforeWithdraw(uint256 _amount, uint256) internal override {
        morpho.withdraw(address(poolToken), _amount);
    }

    function afterDeposit(uint256 _amount, uint256) internal override {
        underlyingToken.safeApprove(address(morpho), _amount);
        morpho.supply(address(poolToken), address(this), _amount);
    }
}
