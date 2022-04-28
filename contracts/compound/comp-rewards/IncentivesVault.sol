// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "../interfaces/IOracle.sol";

import "@rari-capital/solmate/src/utils/SafeTransferLib.sol";

import "@openzeppelin/contracts/access/Ownable.sol";

contract IncentivesVault is Ownable {
    using SafeTransferLib for ERC20;

    /// STORAGE ///

    uint256 public constant MAX_BASIS_POINTS = 10_000;
    address public constant COMP = 0xc00e94Cb662C3520282E6f5717214004A7f26888;

    address public immutable positionsManager; // The address of the Positions Manager.
    address public immutable morphoToken; // The address of the MORPHO token.
    address public morphoDao; // The address of the Morpho DAO treasury.
    address public oracle; // Thre oracle used to get the price of the pair MORPHO/COMP 🦋.
    uint256 public bonus; // The bonus of MORPHO tokens to give to the user (in basis point).
    bool public isActive; // Whether the swith of COMP rewards to MORPHO rewards is active or not.

    /// EVENTS ///

    event OracleSet(address _newOracle);
    event MorphoDaoSet(address _newMorphoDao);
    event BonusSet(uint256 _newBonus);
    event ActivationStatusChanged(bool _newStatus);

    /// ERRROS ///

    error OnlyPositionsManager();
    error VaultNotActive();

    /// CONSTRUCTOR ///

    constructor(
        address _positionsManager,
        address _morphoToken,
        address _oracle
    ) {
        positionsManager = _positionsManager;
        morphoToken = _morphoToken;
        oracle = _oracle;
    }

    function setOracle(address _newOracle) external onlyOwner {
        oracle = _newOracle;
        emit OracleSet(_newOracle);
    }

    function setMorphoDao(address _newMorphoDao) external onlyOwner {
        morphoDao = _newMorphoDao;
        emit MorphoDaoSet(_newMorphoDao);
    }

    function setBonus(uint256 _newBonus) external onlyOwner {
        bonus = _newBonus;
        emit BonusSet(_newBonus);
    }

    function toggleActivation() external onlyOwner {
        bool newStatus = !isActive;
        isActive = newStatus;
        emit ActivationStatusChanged(newStatus);
    }

    function transferMorphoTokensToDao(uint256 _amount) external onlyOwner {
        ERC20(morphoToken).transfer(morphoDao, _amount);
    }

    function convertCompToMorphoTokens(address _to, uint256 _amount) external {
        if (msg.sender != positionsManager) revert OnlyPositionsManager();
        if (!isActive) revert VaultNotActive();

        ERC20(COMP).safeTransferFrom(msg.sender, morphoDao, _amount);
        uint256 amountOut = (IOracle(oracle).consult(_amount) * (MAX_BASIS_POINTS + bonus)) /
            MAX_BASIS_POINTS;
        ERC20(morphoToken).transfer(_to, amountOut);
    }
}
