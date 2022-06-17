// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import {ERC20, SafeTransferLib} from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import "@rari-capital/solmate/src/utils/FixedPointMathLib.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

/// @title ERC4626Upgradeable.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice ERC4626 tokenized Vault abstract upgradeable implementation, heavily inspired by Solmate's non-upgradeable implementation (https://github.com/Rari-Capital/solmate/blob/main/src/mixins/ERC4626.sol)
abstract contract ERC4626Upgradeable is ERC20Upgradeable {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    /// EVENTS ///

    /// @notice Emitted when the successful supply through Morpho is made.
    /// @param caller The caller funding the deposit.
    /// @param owner The owner of the shares minted.
    /// @param assets The amount of assets deposited to the vault (in underlying).
    /// @param shares The amount of shares minted for `owner`.
    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);

    /// @notice Emitted when the successful supply through Morpho is made.
    /// @param caller The caller burning the shares.
    /// @param receiver The receiver of the underlying amount.
    /// @param owner The owner of the shares burned.
    /// @param assets The amount of assets withdrawn from the vault (in underlying).
    /// @param shares The amount of shares burned on behalf of `owner`.
    event Withdraw(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    /// ERRORS ///

    /// @notice Thrown when the share of the vault corresponding to a given amount is zero (too small compared to the value of existing shares).
    error ShareIsZero();

    /// @notice Thrown when the amount of assets corresponding to a given amount of shares is zero (too small).
    error AmountIsZero();

    /// STORAGE ///

    ERC20 public asset; // The underlying asset used to supply through Morpho.

    /// CONSTRUCTOR ///

    /// @notice Constructs the contract.
    /// @dev The contract is automatically marked as initialized when deployed so that nobody can highjack the implementation contract.
    constructor() initializer {}

    /// UPGRADE ///

    function __ERC4626_init(
        ERC20 _asset,
        string memory _name,
        string memory _symbol,
        uint256 _initialDeposit
    ) internal onlyInitializing {
        __ERC20_init(_name, _symbol);
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

    /// @notice Returns the number of decimals of the vault's shares.
    /// @return The number of decimals of the ERC20 token associated to the vault.
    function decimals() public view override returns (uint8) {
        return asset.decimals();
    }

    /// @notice Deposits a given amount of the underlying asset to the vault, minting shares for the receiver.
    /// @param _amount The amount of underlying asset to deposit.
    /// @param _receiver The address of the owner of the shares minted.
    /// @return shares_ The number of shares minted, associated to the deposit.
    function deposit(uint256 _amount, address _receiver) public virtual returns (uint256 shares_) {
        // Check for rounding error since we round down in previewDeposit.
        if ((shares_ = previewDeposit(_amount)) == 0) revert ShareIsZero();

        // Need to transfer before minting or ERC777s could reenter.
        asset.safeTransferFrom(msg.sender, address(this), _amount);

        _mint(_receiver, shares_);

        emit Deposit(msg.sender, _receiver, _amount, shares_);

        _afterDeposit(_amount, shares_);
    }

    /// @notice Mints a given amount of shares to the receiver, computing the associated required amount of the underlying asset.
    /// @param _shares The amount of shares to mint.
    /// @param _receiver The address of the owner of the shares minted.
    /// @return amount_ The amount of the underlying asset deposited.
    function mint(uint256 _shares, address _receiver) public virtual returns (uint256 amount_) {
        amount_ = previewMint(_shares); // No need to check for rounding error, previewMint rounds up.

        // Need to transfer before minting or ERC777s could reenter.
        asset.safeTransferFrom(msg.sender, address(this), amount_);

        _mint(_receiver, _shares);

        emit Deposit(msg.sender, _receiver, amount_, _shares);

        _afterDeposit(amount_, _shares);
    }

    /// @notice Withdraws a given amount of the underlying asset from the vault, burning shares of the owner.
    /// @param _amount The amount of the underlying asset to withdraw.
    /// @param _receiver The address of the receiver of the funds.
    /// @param _owner The address of the owner of the shares redeemed.
    /// @return shares_ The number of shares burned.
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

    /// @notice Burns a given amount of shares of the owner, computing the associated amount of the underlying asset to withdraw.
    /// @param _shares The amount of shares to redeem.
    /// @param _receiver The address of the receiver of the funds.
    /// @param _owner The address of the owner of the shares redeemed.
    /// @return amount_ The amount of the underlying asset withdrawn.
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

    /// @notice Returns the total amount of the underlying asset deposited through the vault.
    /// @return The total amount of the underlying asset deposited through the vault.
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
