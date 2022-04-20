// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./interfaces/compound/ICompound.sol";

import "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import "./libraries/LibRewardsManager.sol";
import "./libraries/LibStorage.sol";

/// @title RewardsManagerForCompound.
/// @notice This contract is used to manage the COMP rewards from the Compound protocol.
contract RewardsManagerForCompound is WithStorageAndModifiers {
    using SafeTransferLib for ERC20;

    /// EVENTS ///

    /// @notice Emitted when a user claims rewards.
    /// @param _user The address of the claimer.
    /// @param _amountClaimed The amount of reward token claimed.
    event RewardsClaimed(address indexed _user, uint256 _amountClaimed);

    /// @notice Emitted when a user claims rewards and converts them to Morpho tokens.
    /// @param _user The address of the claimer.
    /// @param _amountSent The amount of reward token sent to the vault.
    event RewardsClaimedAndConverted(address indexed _user, uint256 _amountSent);

    /// ERRORS ///

    /// @notice Thrown when the amount is equal to 0.
    error AmountIsZero();

    /// EXTERNAL ///

    /// @notice Claims rewards for the given assets and the unclaimed rewards.
    /// @param _claimMorphoToken Whether or not to claim Morpho tokens instead of token reward.
    function claimRewards(address[] calldata _cTokenAddresses, bool _claimMorphoToken)
        external
        nonReentrant
    {
        RewardsStorage storage r = rs();
        uint256 amountOfRewards = LibRewardsManager.accrueUserUnclaimedRewards(
            _cTokenAddresses,
            msg.sender
        );
        if (amountOfRewards > 0) r.userUnclaimedCompRewards[msg.sender] = 0;
        else revert AmountIsZero();

        PositionsStorage storage p = ps();
        p.comptroller.claimComp(address(this), _cTokenAddresses);
        ERC20 comp = ERC20(p.comptroller.getCompAddress());

        if (_claimMorphoToken) {
            comp.safeApprove(address(p.incentivesVault), amountOfRewards);
            p.incentivesVault.convertCompToMorphoTokens(msg.sender, amountOfRewards);
            emit RewardsClaimedAndConverted(msg.sender, amountOfRewards);
        } else {
            comp.safeTransfer(msg.sender, amountOfRewards);
            emit RewardsClaimed(msg.sender, amountOfRewards);
        }
    }

    /// @notice Accrues unclaimed COMP rewards for the cToken addresses and returns the total unclaimed COMP rewards.
    /// @param _cTokenAddresses The cToken addresses for which to accrue rewards.
    /// @param _user The address of the user.
    /// @return unclaimedRewards The user unclaimed rewards.
    function accrueUserUnclaimedRewards(address[] calldata _cTokenAddresses, address _user)
        external
        returns (uint256 unclaimedRewards)
    {
        return LibRewardsManager.accrueUserUnclaimedRewards(_cTokenAddresses, _user);
    }

    /// GETTERS ///

    /// @notice Returns the unclaimed COMP rewards for the given cToken addresses.
    /// @param _cTokenAddresses The cToken addresses for which to compute the rewards.
    /// @param _user The address of the user.
    function getUserUnclaimedRewards(address[] calldata _cTokenAddresses, address _user)
        external
        view
        returns (uint256 unclaimedRewards)
    {
        return LibRewardsManager.getUserUnclaimedRewards(_cTokenAddresses, _user);
    }

    /// @notice Returns the local COMP supply state.
    /// @param _cTokenAddress The cToken address.
    /// @return The local COMP supply state.
    function getLocalCompSupplyState(address _cTokenAddress)
        external
        view
        returns (IComptroller.CompMarketState memory)
    {
        return rs().localCompSupplyState[_cTokenAddress];
    }

    /// @notice Returns the local COMP borrow state.
    /// @param _cTokenAddress The cToken address.
    /// @return The local COMP borrow state.
    function getLocalCompBorrowState(address _cTokenAddress)
        external
        view
        returns (IComptroller.CompMarketState memory)
    {
        return rs().localCompBorrowState[_cTokenAddress];
    }

    /// @notice Returns the accrued COMP rewards of a user since the last update.
    /// @param _supplier The address of the supplier.
    /// @param _cTokenAddress The cToken address.
    /// @param _balance The user balance of tokens in the distribution.
    /// @return The accrued COMP rewards.
    function getAccruedSupplierComp(
        address _supplier,
        address _cTokenAddress,
        uint256 _balance
    ) external view returns (uint256) {
        return LibRewardsManager.getAccruedSupplierComp(_supplier, _cTokenAddress, _balance);
    }

    /// @notice Returns the accrued COMP rewards of a user since the last update.
    /// @param _borrower The address of the borrower.
    /// @param _cTokenAddress The cToken address.
    /// @param _balance The user balance of tokens in the distribution.
    /// @return The accrued COMP rewards.
    function getAccruedBorrowerComp(
        address _borrower,
        address _cTokenAddress,
        uint256 _balance
    ) external view returns (uint256) {
        return LibRewardsManager.getAccruedBorrowerComp(_borrower, _cTokenAddress, _balance);
    }

    /// @notice Returns the udpated COMP supply index.
    /// @param _cTokenAddress The cToken address.
    /// @return The updated COMP supply index.
    function getUpdatedSupplyIndex(address _cTokenAddress) external view returns (uint256) {
        return LibRewardsManager.getUpdatedSupplyIndex(_cTokenAddress);
    }

    /// @notice Returns the udpated COMP borrow index.
    /// @param _cTokenAddress The cToken address.
    /// @return The updated COMP borrow index.
    function getUpdatedBorrowIndex(address _cTokenAddress) external view returns (uint256) {
        return LibRewardsManager.getUpdatedBorrowIndex(_cTokenAddress);
    }

    function compSupplierIndex(address _cTokenAddress, address _user)
        external
        view
        returns (uint256)
    {
        return rs().compSupplierIndex[_cTokenAddress][_user];
    }

    function compBorrowerIndex(address _cTokenAddress, address _user)
        external
        view
        returns (uint256)
    {
        return rs().compBorrowerIndex[_cTokenAddress][_user];
    }
}
