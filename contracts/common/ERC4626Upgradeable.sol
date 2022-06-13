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
        address indexed _caller,
        address indexed _owner,
        uint256 _underlyingAmount,
        uint256 _shares
    );

    event Withdraw(
        address indexed _caller,
        address indexed _receiver,
        address indexed _owner,
        uint256 _underlyingAmount,
        uint256 _shares
    );

    /// STORAGE ///

    ERC20 public underlyingToken;

    constructor() initializer {}

    function __ERC4626_init(
        ERC20 _underlyingToken,
        string memory _name,
        string memory _symbol
    ) internal onlyInitializing {
        __Context_init();
        __Ownable_init();
        __ERC20_init(_name, _symbol);
        underlyingToken = _underlyingToken;
    }

    /// ERRORS ///

    error ShareIsZero();

    error AmountIsZero();

    /// PUBLIC ///

    function decimals() public view override returns (uint8) {
        return underlyingToken.decimals();
    }

    function deposit(uint256 _amount, address _receiver) public virtual returns (uint256 shares) {
        // Check for rounding error since we round down in previewDeposit.
        if ((shares = previewDeposit(_amount)) == 0) revert ShareIsZero();

        // Need to transfer before minting or ERC777s could reenter.
        underlyingToken.safeTransferFrom(msg.sender, address(this), _amount);

        _mint(_receiver, shares);

        emit Deposit(msg.sender, _receiver, _amount, shares);

        afterDeposit(_amount, shares);
    }

    function mint(uint256 _shares, address _receiver) public virtual returns (uint256 _amount) {
        _amount = previewMint(_shares); // No need to check for rounding error, previewMint rounds up.

        // Need to transfer before minting or ERC777s could reenter.
        underlyingToken.safeTransferFrom(msg.sender, address(this), _amount);

        _mint(_receiver, _shares);

        emit Deposit(msg.sender, _receiver, _amount, _shares);

        afterDeposit(_amount, _shares);
    }

    function withdraw(
        uint256 _amount,
        address _receiver,
        address _owner
    ) public virtual returns (uint256 shares) {
        shares = previewWithdraw(_amount); // No need to check for rounding error, previewWithdraw rounds up.

        if (msg.sender != _owner) _spendAllowance(_owner, msg.sender, shares);

        beforeWithdraw(_amount, shares);

        _burn(_owner, shares);

        emit Withdraw(msg.sender, _receiver, _owner, _amount, shares);

        underlyingToken.safeTransfer(_receiver, _amount);
    }

    function redeem(
        uint256 _shares,
        address _receiver,
        address _owner
    ) public virtual returns (uint256 amount) {
        if (msg.sender != _owner) _spendAllowance(_owner, msg.sender, _shares);

        // Check for rounding error since we round down in previewRedeem.
        if ((amount = previewRedeem(_shares)) == 0) revert AmountIsZero();

        beforeWithdraw(amount, _shares);

        _burn(_owner, _shares);

        emit Withdraw(msg.sender, _receiver, _owner, amount, _shares);

        underlyingToken.safeTransfer(_receiver, amount);
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

    function beforeWithdraw(uint256 _amount, uint256 _shares) internal virtual {}

    function afterDeposit(uint256 _amount, uint256 _shares) internal virtual {}
}
