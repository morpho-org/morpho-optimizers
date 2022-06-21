// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "../interfaces/compound/ICompound.sol";
import "../interfaces/IMorpho.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

import "../libraries/CompoundMath.sol";
import "../libraries/Types.sol";

import "./SupplyVaultUpgradeable.sol";

/// @title SupplyVault.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice ERC4626-upgradeable tokenized Vault implementation for Morpho-Compound, which can harvest accrued COMP rewards, swap them and re-supply them through Morpho-Compound.
contract SupplyVault is SupplyVaultUpgradeable {
    using SafeTransferLib for ERC20;
    using CompoundMath for uint256;

    /// STORAGE ///

    ERC20 public comp;
    IComptroller public comptroller;

    IComptroller.CompMarketState public localCompRewardsState; // The local rewards state.
    mapping(address => uint256) public userUnclaimedCompRewards; // The unclaimed rewards of the user.
    mapping(address => uint256) public compRewardsIndex; // The comp rewards index of the user.

    /// UPGRADE ///

    /// @notice Initializes the vault.
    /// @param _morphoAddress The address of the main Morpho contract.
    /// @param _poolTokenAddress The address of the pool token corresponding to the market to supply through this vault.
    /// @param _name The name of the ERC20 token associated to this tokenized vault.
    /// @param _symbol The symbol of the ERC20 token associated to this tokenized vault.
    /// @param _initialDeposit The amount of the initial deposit used to prevent pricePerShare manipulation.
    function initialize(
        address _morphoAddress,
        address _poolTokenAddress,
        string calldata _name,
        string calldata _symbol,
        uint256 _initialDeposit
    ) external initializer {
        __SupplyVault_init(_morphoAddress, _poolTokenAddress, _name, _symbol, _initialDeposit);
        comptroller = morpho.comptroller();
        comp = ERC20(comptroller.getCompAddress());
    }

    /// EXTERNAL ///

    /// @notice Returns the local COMP rewards state.
    /// @return The local COMP rewards state.
    function getLocalCompRewardsState()
        external
        view
        returns (IComptroller.CompMarketState memory)
    {
        return localCompRewardsState;
    }

    /// @notice Claims rewards from the underlying pool, swaps them for the underlying asset and supply them through Morpho.
    /// @return rewardsAmount_ The amount of rewards claimed, swapped then supplied through Morpho (in underlying).
    function claimRewards(address _user) external returns (uint256 rewardsAmount_) {
        _accrueUserUnclaimedRewards(_user);

        rewardsAmount_ = userUnclaimedCompRewards[_user];
        if (rewardsAmount_ > 0) {
            userUnclaimedCompRewards[_user] = 0;

            address[] memory poolTokenAddresses = new address[](1);
            poolTokenAddresses[0] = address(poolToken);
            morpho.claimRewards(poolTokenAddresses, false);

            comp.safeTransfer(_user, rewardsAmount_);
        }
    }

    /// INTERNAL ///

    /// @notice Accrues unclaimed COMP rewards for the cToken addresses and returns the total unclaimed COMP rewards.
    /// @param _user The address of the user.
    function _accrueUserUnclaimedRewards(
        address _user // ! Needs to get called everytime a user supplies/withdraws
    ) internal {
        _updateRewardsIndex();
        userUnclaimedCompRewards[_user] += _accrueCompRewards(
            _user,
            morpho.supplyBalanceInOf(address(poolToken), _user).onPool
        );
    }

    /// @notice Updates supplier index and returns the accrued COMP rewards of the supplier since the last update.
    /// @param _user The address of the supplier.
    /// @param _balance The user balance of tokens in the distribution.
    /// @return The accrued COMP rewards.
    function _accrueCompRewards(address _user, uint256 _balance) internal returns (uint256) {
        uint256 rewardsIndex = localCompRewardsState.index;
        uint256 userRewardsIndex = compRewardsIndex[_user];
        compRewardsIndex[_user] = rewardsIndex;

        if (userRewardsIndex == 0) return 0;
        return (_balance * (rewardsIndex - userRewardsIndex)) / 1e36;
    }

    /// @notice Updates the COMP rewards index.
    function _updateRewardsIndex() internal {
        IComptroller.CompMarketState memory _localCompRewardsState = localCompRewardsState;

        if (_localCompRewardsState.block == block.number) return;
        else {
            address _poolTokenAddress = address(poolToken);
            IComptroller.CompMarketState memory supplyState = comptroller.compSupplyState(
                _poolTokenAddress
            );

            uint256 deltaBlocks = block.number - supplyState.block;
            uint256 supplySpeed = comptroller.compSupplySpeeds(_poolTokenAddress);

            uint224 newCompSupplyIndex;
            if (deltaBlocks > 0 && supplySpeed > 0) {
                uint256 supplyTokens = ICToken(_poolTokenAddress).totalSupply();
                uint256 compAccrued = deltaBlocks * supplySpeed;
                uint256 ratio = supplyTokens > 0 ? (compAccrued * 1e36) / supplyTokens : 0;

                newCompSupplyIndex = uint224(supplyState.index + ratio);
            } else newCompSupplyIndex = supplyState.index;

            localCompRewardsState = IComptroller.CompMarketState({
                index: newCompSupplyIndex,
                block: CompoundMath.safe32(block.number)
            });
        }
    }
}
