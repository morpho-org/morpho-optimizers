// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import {ERC20, SafeTransferLib} from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import "@rari-capital/solmate/src/utils/FixedPointMathLib.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

/// @title ERC4626Upgradeable.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice ERC4626 tokenized Vault abstract upgradeable implementation, heavily inspired by Solmate's non-upgradeable implementation (https://github.com/Rari-Capital/solmate/blob/main/src/mixins/ERC4626.sol)
abstract contract ERC4626Upgradeable is ERC20Upgradeable, OwnableUpgradeable {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    /// EVENTS ///

    event Deposit(
        address indexed caller,
        address indexed owner,
        uint256 underlyingAmount,
        uint256 shares
    );

    event Withdraw(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256 underlyingAmount,
        uint256 shares
    );

    /// ERRORS ///

    error ShareIsZero();

    error AmountIsZero();

    /// STORAGE ///

    ERC20 public asset;

    /// CONSTRUCTOR ///

    constructor() initializer {}

    function __ERC4626_init(
        ERC20 _asset,
        string memory _name,
        string memory _symbol,
        uint256 _initialDeposit
    ) internal onlyInitializing {
        __Ownable_init_unchained();
        __ERC20_init_unchained(_name, _symbol);
        __ERC4626_init_unchained(_asset, _initialDeposit);
    }

    function __ERC4626_init_unchained(ERC20 _asset, uint256 _initialDeposit)
        internal
        onlyInitializing
    {
        asset = _asset;

        // Sacrifice an initial seed of shares to ensure a healthy amount of precision in minting shares.
        // Set to 0 at your own risk.
        // Caller must have approved the asset to this contract's address.
        // See: https://github.com/Rari-Capital/solmate/issues/178
        if (_initialDeposit > 0) deposit(_initialDeposit, address(0));
    }

    /// PUBLIC ///

    function decimals() public view override returns (uint8) {
        return asset.decimals();
    }

    function deposit(uint256 _amount, address _receiver) public virtual returns (uint256 shares_) {
        // Check for rounding error since we round down in previewDeposit.
        if ((shares_ = previewDeposit(_amount)) == 0) revert ShareIsZero();

        // Need to transfer before minting or ERC777s could reenter.
        asset.safeTransferFrom(msg.sender, address(this), _amount);

        _mint(_receiver, shares_);

        emit Deposit(msg.sender, _receiver, _amount, shares_);

        _afterDeposit(_amount, shares_);
    }

    function mint(uint256 _shares, address _receiver) public virtual returns (uint256 amount_) {
        amount_ = previewMint(_shares); // No need to check for rounding error, previewMint rounds up.

        // Need to transfer before minting or ERC777s could reenter.
        asset.safeTransferFrom(msg.sender, address(this), amount_);

        _mint(_receiver, _shares);

        emit Deposit(msg.sender, _receiver, amount_, _shares);

        _afterDeposit(amount_, _shares);
    }

    function withdraw(
        uint256 _amount,
        address _receiver,
        address _owner
    ) public virtual returns (uint256 shares_) {
        shares_ = previewWithdraw(_amount); // No need to check for rounding error, previewWithdraw rounds up.

        if (msg.sender != _owner) _spendAllowance(_owner, msg.sender, shares_);

        _beforeWithdraw(_amount, shares_);

        _burn(_owner, shares_);

        emit Withdraw(msg.sender, _receiver, _owner, _amount, shares_);

        asset.safeTransfer(_receiver, _amount);
    }

    function redeem(
        uint256 _shares,
        address _receiver,
        address _owner
    ) public virtual returns (uint256 amount_) {
        if (msg.sender != _owner) _spendAllowance(_owner, msg.sender, _shares);

        // Check for rounding error since we round down in previewRedeem.
        if ((amount_ = previewRedeem(_shares)) == 0) revert AmountIsZero();

        _beforeWithdraw(amount_, _shares);

        _burn(_owner, _shares);

        emit Withdraw(msg.sender, _receiver, _owner, amount_, _shares);

        asset.safeTransfer(_receiver, amount_);
    }

    function totalAssets() public view virtual returns (uint256);

    function convertToShares(uint256 _amount) public view virtual returns (uint256) {
        uint256 supply = totalSupply(); // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? _amount : _amount.mulDivDown(supply, totalAssets());
    }

    function convertToAssets(uint256 _shares) public view virtual returns (uint256) {
        uint256 supply = totalSupply(); // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? _shares : _shares.mulDivDown(totalAssets(), supply);
    }

    function previewDeposit(uint256 _amount) public view virtual returns (uint256) {
        return convertToShares(_amount);
    }

    function previewMint(uint256 _shares) public view virtual returns (uint256) {
        uint256 supply = totalSupply(); // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? _shares : _shares.mulDivUp(totalAssets(), supply);
    }

    function previewWithdraw(uint256 _amount) public view virtual returns (uint256) {
        uint256 supply = totalSupply(); // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? _amount : _amount.mulDivUp(supply, totalAssets());
    }

    function previewRedeem(uint256 _shares) public view virtual returns (uint256) {
        return convertToAssets(_shares);
    }

    function maxDeposit(address) public view virtual returns (uint256) {
        return type(uint256).max;
    }

    function maxMint(address) public view virtual returns (uint256) {
        return type(uint256).max;
    }

    function maxWithdraw(address _owner) public view virtual returns (uint256) {
        return convertToAssets(balanceOf(_owner));
    }

    function maxRedeem(address _owner) public view virtual returns (uint256) {
        return balanceOf(_owner);
    }

    /// INTERNAL ///

    function _beforeWithdraw(uint256 _amount, uint256 _shares) internal virtual {}

    function _afterDeposit(uint256 _amount, uint256 _shares) internal virtual {}
}