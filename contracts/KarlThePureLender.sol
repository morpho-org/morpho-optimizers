// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

import "@openzeppelin/contracts/access/Ownable.sol"; // Not sure to be needed
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol"; // Not sure to be needed

import {ICErc20, IComptroller} from "./interfaces/compound/ICompound.sol";
import "./interfaces/IPositionsManagerForCompLike.sol";
import "./interfaces/IMarketsManagerForCompLike.sol";

contract KarlThePureLender is Ownable, ReentrancyGuard {
    mapping(address => mapping(address => uint256)) public supplyBalanceInOf; // For a given market, the supply balance of user.
    IPositionsManagerForCompLike public positionManager;

    /** @dev Emitted when a supply happens.
     *  @param _account The address of the supplier.
     *  @param _crERC20Address The address of the market where assets are supplied into.
     *  @param _amount The amount of assets.
     */
    event Supplied(address indexed _account, address indexed _crERC20Address, uint256 _amount);

    /** @dev Emitted when a withdraw happens.
     *  @param _account The address of the withdrawer.
     *  @param _crERC20Address The address of the market from where assets are withdrawn.
     *  @param _amount The amount of assets.
     */
    event Withdrawn(address indexed _account, address indexed _crERC20Address, uint256 _amount);

    /** @dev Emitted when a staking happens.
     *  @param _account The address of the staker.
     *  @param _cTokenAddress The address of the cToken.
     *  @param _amount The amount of assets.
     */
    event Staked(address indexed _account, address indexed _cTokenAddress, uint256 _amount);

    /** @dev Emitted when a unstaking happens.
     *  @param _account The address of the unstaker.
     *  @param _cTokenAddress The address of the cToken.
     *  @param _amount The amount of assets.
     */
    event Unstaked(address indexed _account, address indexed _cTokenAddress, uint256 _amount);

    /** @dev Prevents a user to access a market not created yet.
     *  @param _crERC20Address The address of the market.
     */
    modifier isMarketCreated(address _crERC20Address) {
        require(
            positionManager.marketsManagerForCompLike.isCreated(_crERC20Address),
            "mkt-not-created"
        );
        _;
    }

    constructor(address _morphoPositionsManagerForCream) {
        positionManager = IPositionsManagerForCompLike(_morphoPositionsManagerForCream);
    }

    function supply(address _crERC20Address, uint256 _amount) external nonReentrant {}

    function withdraw(address _crERC20Address, uint256 _amount) external nonReentrant {}

    function stake(address _cTokenAddress, uint256 _amount) external nonReentrant {}

    function unstake(address _cTokenAddress, uint256 _amount) external nonReentrant {}
}
