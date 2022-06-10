// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import "@rari-capital/solmate/src/utils/FixedPointMathLib.sol";

/// @title ERC4626.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice ERC4626 tokenized Vault abstract implementation, heavily inspired by Solmate's implementation (https://github.com/Rari-Capital/solmate/blob/main/src/mixins/ERC4626.sol)
abstract contract ERC4626 is ERC20 {
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

    ERC20 public immutable underlyingToken;

    constructor(
        ERC20 _underlyingToken,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol, _underlyingToken.decimals()) {
        underlyingToken = _underlyingToken;
    }

    /// ERRORS ///

    error ShareIsZero();

    error AmountIsZero();

    /// EXTERNAL ///

    function deposit(uint256 _amount, address _receiver) external virtual returns (uint256 shares) {
        // Check for rounding error since we round down in previewDeposit.
        require((shares = previewDeposit(_amount)) != 0, ShareIsZero());

        // Need to transfer before minting or ERC777s could reenter.
        underlyingToken.safeTransferFrom(msg.sender, address(this), _amount);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, _amount, shares);

        afterDeposit(_amount, shares);
    }

    function mint(uint256 _shares, address _receiver) external virtual returns (uint256 _amount) {
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
    ) external virtual returns (uint256 shares) {
        shares = previewWithdraw(_amount); // No need to check for rounding error, previewWithdraw rounds up.

        if (msg.sender != _owner) {
            uint256 allowed = allowance[_owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) allowance[_owner][msg.sender] = allowed - shares;
        }

        beforeWithdraw(_amount, shares);

        _burn(_owner, shares);

        emit Withdraw(msg.sender, _receiver, _owner, _amount, shares);

        underlyingToken.safeTransfer(_receiver, _amount);
    }

    function redeem(
        uint256 _shares,
        address _receiver,
        address _owner
    ) external virtual returns (uint256 _amount) {
        if (msg.sender != _owner) {
            uint256 allowed = allowance[_owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) allowance[_owner][msg.sender] = allowed - _shares;
        }

        // Check for rounding error since we round down in previewRedeem.
        require((_amount = previewRedeem(_shares)) != 0, AmountIsZero());

        beforeWithdraw(_amount, _shares);

        _burn(_owner, _shares);

        emit Withdraw(msg.sender, _receiver, _owner, _amount, _shares);

        underlyingToken.safeTransfer(_receiver, _amount);
    }

    function totalAssets() public view virtual returns (uint256);

    function convertToShares(uint256 _amount) public view virtual returns (uint256) {
        uint256 supply = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? _amount : _amount.mulDivDown(supply, totalAssets());
    }

    function convertToAssets(uint256 _shares) public view virtual returns (uint256) {
        uint256 supply = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? _shares : _shares.mulDivDown(totalAssets(), supply);
    }

    function previewDeposit(uint256 _amount) public view virtual returns (uint256) {
        return convertToShares(_amount);
    }

    function previewMint(uint256 _shares) public view virtual returns (uint256) {
        uint256 supply = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? _shares : _shares.mulDivUp(totalAssets(), supply);
    }

    function previewWithdraw(uint256 _amount) public view virtual returns (uint256) {
        uint256 supply = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.

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
        return convertToAssets(balanceOf[_owner]);
    }

    function maxRedeem(address _owner) public view virtual returns (uint256) {
        return balanceOf[_owner];
    }

    /// INTERNAL ///

    function beforeWithdraw(uint256 _amount, uint256 _shares) internal virtual {}

    function afterDeposit(uint256 _amount, uint256 _shares) internal virtual {}
}
