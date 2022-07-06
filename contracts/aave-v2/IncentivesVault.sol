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
    ERC20 public immutable rewardToken; // The reward token.
    ERC20 public immutable morphoToken; // The MORPHO token.

    IOracle public oracle; // The oracle used to get the price of MORPHO tokens against token reward tokens.
    address public morphoDao; // The address of the Morpho DAO treasury.
    uint256 public bonus; // The bonus percentage of MORPHO tokens to give to the user.
    bool public isPaused; // Whether the trade of token rewards for MORPHO rewards is paused or not.

    /// EVENTS ///

    /// @notice Emitted when the oracle is set.
    event OracleSet(address _newOracle);

    /// @notice Emitted when the Morpho DAO is set.
    event MorphoDaoSet(address _newMorphoDao);

    /// @notice Emitted when the reward bonus is set.
    event BonusSet(uint256 _newBonus);

    /// @notice Emitted when the pause status is changed.
    event PauseStatusSet(bool _newStatus);

    /// @notice Emitted when tokens are transfered to the DAO.
    event TokensTransfered(uint256 _amount);

    /// @notice Emitted when reward tokens are traded for MORPHO tokens.
    /// @param _receiver The address of the receiver.
    /// @param _rewardAmount The amount of reward token traded.
    /// @param _morphoAmount The amount of MORPHO sent.
    event RewardTokensTraded(
        address indexed _receiver,
        uint256 _rewardAmount,
        uint256 _morphoAmount
    );

    /// ERRORS ///

    /// @notice Thrown when an other address than Morpho triggers the function.
    error OnlyMorpho();

    /// @notice Thrown when the vault is paused.
    error VaultIsPaused();

    /// CONSTRUCTOR ///

    /// @notice Constructs the IncentivesVault contract.
    /// @param _morpho The main Morpho contract.
    /// @param _morphoToken The MORPHO token.
    /// @param _rewardToken The reward token.
    /// @param _morphoDao The address of the Morpho DAO.
    /// @param _oracle The oracle.
    constructor(
        IMorpho _morpho,
        ERC20 _morphoToken,
        ERC20 _rewardToken,
        address _morphoDao,
        IOracle _oracle
    ) {
        morpho = _morpho;
        morphoToken = _morphoToken;
        rewardToken = _rewardToken;
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
        emit TokensTransfered(_amount);
    }

    /// @notice Trades COMP tokens for MORPHO tokens and sends them to the receiver.
    /// @dev The amount of rewards to trade for MORPHO tokens is supposed to have been transferred to this contract before calling the function.
    /// @param _receiver The address of the receiver.
    /// @param _amount The amount to transfer to the receiver.
    function tradeRewardTokensForMorphoTokens(address _receiver, uint256 _amount) external {
        if (msg.sender != address(morpho)) revert OnlyMorpho();
        if (isPaused) revert VaultIsPaused();

        // Add a bonus on MORPHO rewards.
        uint256 amountOut = (oracle.consult(_amount) * (MAX_BASIS_POINTS + bonus)) /
            MAX_BASIS_POINTS;
        morphoToken.transfer(_receiver, amountOut);

        emit RewardTokensTraded(_receiver, _amount, amountOut);
    }
}
