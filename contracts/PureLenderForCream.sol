// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol"; // TODO Not sure to be needed
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol"; // TODO Not sure to be needed

import {ICErc20, IComptroller} from "./interfaces/compound/ICompound.sol";
import "./interfaces/IPositionsManagerForCompLike.sol";
import "./interfaces/IMarketsManagerForCompLike.sol";

contract PureLenderForCream is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    mapping(address => mapping(address => uint256)) public supplyBalanceInOf; // For a given market, the supply balance of user.

    IMarketsManagerForCompLike public marketsManager;
    IPositionsManagerForCompLike public positionsManager;

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

    // TODO staking mechanism of Ctokens

    // /** @dev Emitted when a staking happens.
    //  *  @param _account The address of the staker.
    //  *  @param _cTokenAddress The address of the cToken.
    //  *  @param _amount The amount of assets.
    //  */
    // event Staked(address indexed _account, address indexed _cTokenAddress, uint256 _amount);

    // /** @dev Emitted when a unstaking happens.
    //  *  @param _account The address of the unstaker.
    //  *  @param _cTokenAddress The address of the cToken.
    //  *  @param _amount The amount of assets.
    //  */
    // event Unstaked(address indexed _account, address indexed _cTokenAddress, uint256 _amount);

    /** @dev Prevents a user to access a market not created yet.
     *  @param _crERC20Address The address of the market.
     */
    modifier isMarketCreated(address _crERC20Address) {
        require(marketsManager.isCreated(_crERC20Address), "mkt-not-created");
        _;
    }

    constructor(address _morphoPositionsManagerForCream) {
        positionsManager = IPositionsManagerForCompLike(_morphoPositionsManagerForCream);
        marketsManager = IMarketsManagerForCompLike(positionsManager.marketsManagerForCompLike());
    }

    // User must approve _amount for contract
    // No need to check isMarketCreated, done by supply
    function supply(address _crERC20Address, uint256 _amount) external nonReentrant {
        require(_amount > 0, "supply:amount=0");
        ICErc20 crERC20Token = ICErc20(_crERC20Address);
        IERC20 erc20Token = IERC20(crERC20Token.underlying());
        erc20Token.safeApprove(address(this), _amount);

        positionsManager.supply(_crERC20Address, _amount); // TODO supply must be called with crToken address !!!!!

        supplyBalanceInOf[_crERC20Address][msg.sender] += _amount;

        emit Supplied(msg.sender, _crERC20Address, _amount);
    }

    function withdraw(address _crERC20Address, uint256 _amount) external nonReentrant {
        require(_amount > 0, "withdraw:amount=0");
        require(
            _amount <= supplyBalanceInOf[_crERC20Address][msg.sender],
            "withdraw:amount>balance"
        );

        ICErc20 crERC20Token = ICErc20(_crERC20Address);
        IERC20 erc20Token = IERC20(crERC20Token.underlying());
        positionsManager.withdraw(_crERC20Address, _amount); // TODO withdraw must be called with crToken address !!!!!

        supplyBalanceInOf[_crERC20Address][msg.sender] -= _amount;
        erc20Token.safeTransfer(msg.sender, _amount);

        emit Withdrawn(msg.sender, _crERC20Address, _amount);
    }

    // TODO staking mechanism of Ctokens

    // // User must approve _amount for contract
    // function stake(address _crERC20Address, uint256 _amount) external nonReentrant {
    //     require(_amount > 0, "stake:amount=0");

    //     ICErc20 crERC20Token = ICErc20(_crERC20Address);
    //     crERC20Token.safeTransferFrom(msg.sender, address(this), _amount);

    //     IERC20 erc20Token = IERC20(crERC20Token.underlying());

    //     // TODO remove from cream and supply ?
    // }

    // function unstake(address _crERC20Address, uint256 _amount) external nonReentrant {}
}
