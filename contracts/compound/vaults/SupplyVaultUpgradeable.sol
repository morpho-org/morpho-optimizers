// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "../interfaces/compound/ICompound.sol";
import "../interfaces/IMorpho.sol";

import "../libraries/CompoundMath.sol";
import "../libraries/Types.sol";

import "@contracts/common/ERC4626Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/// @title SupplyVaultUpgradeable.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice ERC4626-upgradeable tokenized Vault abstract implementation for Morpho-Compound.
abstract contract SupplyVaultUpgradeable is ERC4626Upgradeable, OwnableUpgradeable {
    using SafeTransferLib for ERC20;
    using CompoundMath for uint256;

    /// STORAGE ///

    IMorpho public morpho; // The main Morpho contract.
    ICToken public poolToken; // The pool token corresponding to the market to supply through this vault.

    bool public isEth; // Whether the underlying asset is WETH.
    address public wEth; // The address of WETH token.

    /// UPGRADE ///

    /// @notice Initializes the vault.
    /// @param _morphoAddress The address of the main Morpho contract.
    /// @param _poolTokenAddress The address of the pool token corresponding to the market to supply through this vault.
    /// @param _name The name of the ERC20 token associated to this tokenized vault.
    /// @param _symbol The symbol of the ERC20 token associated to this tokenized vault.
    /// @param _initialDeposit The amount of the initial deposit used to prevent pricePerShare manipulation.
    function __SupplyVault_init(
        address _morphoAddress,
        address _poolTokenAddress,
        string calldata _name,
        string calldata _symbol,
        uint256 _initialDeposit
    ) internal onlyInitializing {
        __SupplyVault_init_unchained(_morphoAddress, _poolTokenAddress);

        __Ownable_init();
        __ERC4626_init(
            ERC20(isEth ? wEth : poolToken.underlying()),
            _name,
            _symbol,
            _initialDeposit
        );
    }

    /// @notice Initializes the vault.
    /// @param _morphoAddress The address of the main Morpho contract.
    /// @param _poolTokenAddress The address of the pool token corresponding to the market to supply through this vault.$
    function __SupplyVault_init_unchained(address _morphoAddress, address _poolTokenAddress)
        internal
        onlyInitializing
    {
        morpho = IMorpho(_morphoAddress);
        poolToken = ICToken(_poolTokenAddress);

        isEth = _poolTokenAddress == morpho.cEth();
        wEth = morpho.wEth();
    }

    /// PUBLIC ///

    function totalAssets() public view override returns (uint256) {
        Types.SupplyBalance memory supplyBalance = morpho.supplyBalanceInOf(
            address(poolToken),
            address(this)
        );

        return
            supplyBalance.onPool.mul(poolToken.exchangeRateStored()) +
            supplyBalance.inP2P.mul(morpho.p2pSupplyIndex(address(poolToken)));
    }

    /// INTERNAL ///

    function _beforeWithdraw(uint256 _amount, uint256) internal override {
        morpho.withdraw(address(poolToken), _amount);
    }

    function _afterDeposit(uint256 _amount, uint256) internal override {
        asset.safeApprove(address(morpho), _amount);
        morpho.supply(address(poolToken), address(this), _amount);
    }
}
