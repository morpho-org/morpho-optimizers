// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "prb-math/contracts/PRBMathUD60x18.sol";

import {ICErc20, IComptroller} from "./interfaces/compound/ICompound.sol";
import "./interfaces/IPositionsManagerForCompLike.sol";
import "./interfaces/IMarketsManagerForCompLike.sol";

contract PureSupplierForCream is ReentrancyGuard {
    using PRBMathUD60x18 for uint256;
    using SafeERC20 for IERC20;
    using Math for uint256;

    mapping(address => PoolInfo) public pools; // For a given market, the corresponding pool.
    mapping(address => mapping(address => Supplier)) public suppliers; // For a given market, the supply balance of user.

    IMarketsManagerForCompLike public marketsManager;
    IPositionsManagerForCompLike public positionsManager;

    // Info of each pool.
    struct PoolInfo {
        uint256 amount;
        uint256 lastBlock;
        uint256 score;
    }

    struct Supplier {
        uint256 amount;
        uint256 depositedBlock;
    }

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

    function updatePoolScore(PoolInfo storage _pool) internal {
        _pool.score = _pool.score + _pool.amount * (block.number - _pool.lastBlock);
        _pool.lastBlock = block.number;
    }

    // User must approve _amount for contract
    // No need to check isMarketCreated, done by supply
    function supply(address _crERC20Address, uint256 _amount) external nonReentrant {
        require(_amount > 0, "supply:amount=0");
        ICErc20 crERC20Token = ICErc20(_crERC20Address);
        IERC20 erc20Token = IERC20(crERC20Token.underlying());

        erc20Token.safeTransferFrom(msg.sender, address(this), _amount);
        erc20Token.safeApprove(address(positionsManager), _amount); // TODO global infinite approve ?
        positionsManager.supply(_crERC20Address, _amount);

        PoolInfo storage pool = pools[_crERC20Address];
        updatePoolScore(pool);
        pool.amount += _amount;

        // TODO update for user who have already supply
        suppliers[_crERC20Address][msg.sender].amount = _amount;
        suppliers[_crERC20Address][msg.sender].depositedBlock = block.number;

        emit Supplied(msg.sender, _crERC20Address, _amount);
    }

    function withdraw(address _crERC20Address, uint256 _amount) external nonReentrant {
        require(_amount > 0, "withdraw:amount=0");

        Supplier storage supplier = suppliers[_crERC20Address][msg.sender];
        require(_amount <= supplier.amount, "withdraw:toomuch");

        PoolInfo storage pool = pools[_crERC20Address];
        updatePoolScore(pool);

        uint256 supplierScore = _amount * (block.number - supplier.depositedBlock);

        ICErc20 crERC20Token = ICErc20(_crERC20Address);
        uint256 totalValueOfPureLender = _calculatePoolTotal(crERC20Token);

        uint256 toRepay = suppliers[_crERC20Address][msg.sender].amount +
            (totalValueOfPureLender - pool.amount).mul(supplierScore.div(pool.score));

        pool.amount -= _amount;
        pool.score -= supplierScore;

        supplier.amount -= _amount;
        supplier.depositedBlock = block.number;

        positionsManager.withdraw(_crERC20Address, toRepay);

        IERC20 erc20Token = IERC20(crERC20Token.underlying());
        erc20Token.safeTransfer(msg.sender, toRepay);

        emit Withdrawn(msg.sender, _crERC20Address, _amount);
    }

    function _calculatePoolTotal(ICErc20 _crERC20Token) internal returns (uint256 total_) {
        // Get balance of PureLender on positionsManager
        (uint256 inP2P, uint256 onCream) = positionsManager.supplyBalanceInOf(
            address(_crERC20Token),
            address(this)
        );

        // Get total + interests
        uint256 collateralOnCreamInUnderlying = onCream.mul(_crERC20Token.exchangeRateStored());
        total_ =
            collateralOnCreamInUnderlying +
            inP2P.mul(marketsManager.updateMUnitExchangeRate(address(_crERC20Token)));
    }
}
