// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

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
    IComptroller public immutable comptroller; // Compound's comptroller proxy.
    ERC20 public immutable morphoToken; // The MORPHO token.

    IOracle public oracle; // The oracle used to get the price of MORPHO tokens against COMP tokens.
    address public morphoDao; // The address of the Morpho DAO treasury.
    uint256 public bonus; // The bonus percentage of MORPHO tokens to give to the user.
    bool public isPaused; // Whether the trade of COMP rewards for MORPHO rewards is paused or not.

    /// EVENTS ///

    /// @notice Emitted when the oracle is set.
    event OracleSet(address _newOracle);

    /// @notice Emitted when the Morpho DAO is set.
    event MorphoDaoSet(address _newMorphoDao);

    /// @notice Emitted when the reward bonus is set.
    event BonusSet(uint256 _newBonus);

    /// @notice Emitted when the pause status is changed.
    event PauseStatusSet(bool _newStatus);

    /// @notice Emitted when MORPHO tokens are transferred to the DAO.
    event MorphoTokensTransferred(uint256 _amount);

    /// @notice Emitted when COMP tokens are traded for MORPHO tokens.
    /// @param _receiver The address of the receiver.
    /// @param _compAmount The amount of COMP traded.
    /// @param _morphoAmount The amount of MORPHO sent.
    event CompTokensTraded(address indexed _receiver, uint256 _compAmount, uint256 _morphoAmount);

    /// ERRORS ///

    /// @notice Thrown when an other address than Morpho triggers the function.
    error OnlyMorpho();

    /// @notice Thrown when the vault is paused.
    error VaultIsPaused();

    /// CONSTRUCTOR ///

    /// @notice Constructs the IncentivesVault contract.
    /// @param _comptroller The Compound comptroller.
    /// @param _morpho The main Morpho contract.
    /// @param _morphoToken The MORPHO token.
    /// @param _morphoDao The address of the Morpho DAO.
    /// @param _oracle The oracle.
    constructor(
        IComptroller _comptroller,
        IMorpho _morpho,
        ERC20 _morphoToken,
        address _morphoDao,
        IOracle _oracle
    ) {
        morpho = _morpho;
        comptroller = _comptroller;
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

    /// @notice Transfers the MORPHO tokens to the DAO.
    /// @param _amount The amount of MORPHO tokens to transfer to the DAO.
    function transferMorphoTokensToDao(uint256 _amount) external onlyOwner {
        morphoToken.safeTransfer(morphoDao, _amount);
        emit MorphoTokensTransferred(_amount);
    }

    /// @notice Trades COMP tokens for MORPHO tokens and sends them to the receiver.
    /// @param _receiver The address of the receiver.
    /// @param _amount The amount to transfer to the receiver.
    function tradeCompForMorphoTokens(address _receiver, uint256 _amount) external {
        if (msg.sender != address(morpho)) revert("OnlyMorpho()");
        if (isPaused) revert("VaultIsPaused()");
        // Transfer COMP to the DAO.
        ERC20(comptroller.getCompAddress()).safeTransferFrom(msg.sender, morphoDao, _amount);

        // Add a bonus on MORPHO rewards.
        uint256 amountOut = (oracle.consult(_amount) * (MAX_BASIS_POINTS + bonus)) /
            MAX_BASIS_POINTS;
        morphoToken.transfer(_receiver, amountOut);

        emit CompTokensTraded(_receiver, _amount, amountOut);
    }
}
