// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "./interfaces/IIncentivesVault.sol";
import "./interfaces/IOracle.sol";
import "./interfaces/IMorpho.sol";

import "@rari-capital/solmate/src/utils/SafeTransferLib.sol";

import "@openzeppelin/contracts/access/Ownable.sol";

/// @title IncentivesVault.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice Contract handling Morpho incentives.
contract IncentivesVault is IIncentivesVault, Ownable {
    using SafeTransferLib for ERC20;

    /// STORAGE ///

    uint256 public constant MAX_BASIS_POINTS = 10_000;

    IMorpho public immutable morpho; // The address of the main Morpho contract.
    ERC20 public immutable morphoToken; // The MORPHO token.

    IOracle public oracle; // The oracle used to get the price of MORPHO tokens against token reward tokens.
    address public morphoDao; // The address of the Morpho DAO treasury.
    uint256 public bonus; // The bonus percentage of MORPHO tokens to give to the user.
    bool public isPaused; // Whether the trade of token rewards for MORPHO rewards is paused or not.

    /// EVENTS ///

    /// @notice Emitted when the oracle is set.
    /// @param newOracle The new oracle set.
    event OracleSet(address newOracle);

    /// @notice Emitted when the Morpho DAO is set.
    /// @param newMorphoDao The address of the Morpho DAO.
    event MorphoDaoSet(address newMorphoDao);

    /// @notice Emitted when the reward bonus is set.
    /// @param newBonus The new bonus set.
    event BonusSet(uint256 newBonus);

    /// @notice Emitted when the pause status is changed.
    /// @param newStatus The new newStatus set.
    event PauseStatusSet(bool newStatus);

    /// @notice Emitted when tokens are transferred to the DAO.
    /// @param token The address of the token transferred.
    /// @param amount The amount of token transferred to the DAO.
    event TokensTransferred(address indexed token, uint256 amount);

    /// @notice Emitted when reward tokens are traded for MORPHO tokens.
    /// @param receiver The address of the receiver.
    /// @param morphoAmount The amount of MORPHO sent.
    event RewardTokensTraded(address indexed receiver, uint256 morphoAmount);

    /// ERRORS ///

    /// @notice Thrown when an other address than Morpho triggers the function.
    error OnlyMorpho();

    /// @notice Thrown when the vault is paused.
    error VaultIsPaused();

    /// CONSTRUCTOR ///

    /// @notice Constructs the IncentivesVault contract.
    /// @param _morpho The main Morpho contract.
    /// @param _morphoToken The MORPHO token.
    /// @param _morphoDao The address of the Morpho DAO.
    /// @param _oracle The oracle.
    constructor(
        IMorpho _morpho,
        ERC20 _morphoToken,
        address _morphoDao,
        IOracle _oracle
    ) {
        morpho = _morpho;
        morphoToken = _morphoToken;
        morphoDao = _morphoDao;
        oracle = _oracle;
    }

    /// EXTERNAL ///

    /// @notice Sets the oracle.
    /// @param _newOracle The address of the new oracle.
    function setOracle(IOracle _newOracle) external onlyOwner {
        oracle = _newOracle;
        emit OracleSet(address(_newOracle));
    }

    /// @notice Sets the morpho DAO.
    /// @param _newMorphoDao The address of the Morpho DAO.
    function setMorphoDao(address _newMorphoDao) external onlyOwner {
        morphoDao = _newMorphoDao;
        emit MorphoDaoSet(_newMorphoDao);
    }

    /// @notice Sets the reward bonus.
    /// @param _newBonus The new reward bonus.
    function setBonus(uint256 _newBonus) external onlyOwner {
        bonus = _newBonus;
        emit BonusSet(_newBonus);
    }

    /// @notice Sets the pause status.
    /// @param _newStatus The new pause status.
    function setPauseStatus(bool _newStatus) external onlyOwner {
        isPaused = _newStatus;
        emit PauseStatusSet(_newStatus);
    }

    /// @notice Transfers the specified token to the DAO.
    /// @param _token The address of the token to transfer.
    /// @param _amount The amount of token to transfer to the DAO.
    function transferTokensToDao(address _token, uint256 _amount) external onlyOwner {
        ERC20(_token).safeTransfer(morphoDao, _amount);
        emit TokensTransferred(_token, _amount);
    }

    /// @notice Trades reward tokens for MORPHO tokens and sends them to the receiver.
    /// @param _receiver The address of the receiver.
    /// @param _rewardsList The list of reward tokens.
    /// @param _claimedAmounts The list of unclaimed reward amounts.
    function tradeRewardTokensForMorphoTokens(
        address _receiver,
        address[] memory _rewardsList,
        uint256[] memory _claimedAmounts
    ) external {
        if (msg.sender != address(morpho)) revert OnlyMorpho();
        if (isPaused) revert VaultIsPaused();

        uint256 rewardsListLength = _rewardsList.length;
        uint256 amountOut;

        for (uint256 i; i < rewardsListLength; ) {
            address reward = _rewardsList[i];
            uint256 claimedAmount = _claimedAmounts[i];

            if (claimedAmount > 0) {
                // Transfer reward tokens to the DAO.
                ERC20(reward).safeTransferFrom(msg.sender, morphoDao, claimedAmount);

                // Add a bonus on MORPHO rewards.
                amountOut += ((oracle.consult(claimedAmount, reward) * (MAX_BASIS_POINTS + bonus)) /
                    MAX_BASIS_POINTS);
            }

            unchecked {
                ++i;
            }
        }

        morphoToken.safeTransfer(_receiver, amountOut);
        emit RewardTokensTraded(_receiver, amountOut);
    }
}
