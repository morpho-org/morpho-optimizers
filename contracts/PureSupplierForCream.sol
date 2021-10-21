// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "prb-math/contracts/PRBMathUD60x18.sol";

import {ICErc20, IComptroller} from "./interfaces/compound/ICompound.sol";
import "./interfaces/IPositionsManagerForCompLike.sol";
import "./interfaces/IMarketsManagerForCompLike.sol";

/**
 * @title PureSupplierForCream.
 * @dev Smart contract to mutualize small suppliers.
 */
contract PureSupplierForCream is ReentrancyGuard {
    using PRBMathUD60x18 for uint256;
    using SafeERC20 for IERC20;
    using Math for uint256;

    /* Storage */

    mapping(address => uint256) public marketShares; // For a given market, the corresponding supply for the pool.
    mapping(address => mapping(address => uint256)) public shares; // For a given market, the shares balance of user.

    IMarketsManagerForCompLike public marketsManager;
    IPositionsManagerForCompLike public positionsManager;

    /* Events */

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

    /* Constructor */
    constructor(address _morphoPositionsManagerForCream) {
        positionsManager = IPositionsManagerForCompLike(_morphoPositionsManagerForCream);
        marketsManager = IMarketsManagerForCompLike(positionsManager.marketsManagerForCompLike());
    }

    /* External */

    /** @dev Supplies ERC20 tokens in a specific market.
     *  @dev `msg.sender` must have approved this contract to spend the underlying `_amount`.
     *  @dev No need to check isMarketCreated, it is done by positionsManager.supply.
     *  @param _crERC20Address The address of the market the user wants to supply.
     *  @param _amount The amount to supply in ERC20 tokens.
     */
    function supply(address _crERC20Address, uint256 _amount) external nonReentrant {
        require(_amount > 0, "supply:amount=0");
        ICErc20 crERC20Token = ICErc20(_crERC20Address);
        IERC20 erc20Token = IERC20(crERC20Token.underlying());

        erc20Token.safeTransferFrom(msg.sender, address(this), _amount);
        erc20Token.safeApprove(address(positionsManager), _amount);

        _issueSharesForAccount(_crERC20Address, _amount);
        positionsManager.supply(_crERC20Address, _amount);

        emit Supplied(msg.sender, _crERC20Address, _amount);
    }

    /** @dev Withdraws ERC20 tokens from supply.
     *  @dev No need to check isMarketCreated, it is done by positionsManager.withdraw.
     *  @param _crERC20Address The address of the market the user wants to interact with.
     *  @param _shares The amount in shares to withdraw from supply.
     */
    function withdraw(address _crERC20Address, uint256 _shares) external nonReentrant {
        require(_shares > 0, "withdraw:amount=0");
        require(_shares <= shares[_crERC20Address][msg.sender], "withdraw:shares>sender-shares");

        uint256 value = _shareValue(_crERC20Address, _shares);

        marketShares[_crERC20Address] -= _shares;
        shares[_crERC20Address][msg.sender] -= _shares;

        positionsManager.withdraw(_crERC20Address, value);

        ICErc20 crERC20Token = ICErc20(_crERC20Address);
        IERC20 erc20Token = IERC20(crERC20Token.underlying());
        erc20Token.safeTransfer(msg.sender, value);

        emit Withdrawn(msg.sender, _crERC20Address, value);
    }

    /* Internal */

    /** @dev Sets the number of shares for msg.sender, according to the amount and total supply.
     *  @param _crERC20Address The address of the market the user wants to interact with.
     *  @param _amount The amount of ERC20 tokens.
     */
    function _issueSharesForAccount(address _crERC20Address, uint256 _amount) internal {
        uint256 nbShares = 0;
        uint256 totalShares = marketShares[_crERC20Address];

        if (totalShares > 0) {
            nbShares = (_amount * totalShares) / _totalAssetsOnPositionsManager(_crERC20Address);
        } else {
            // No existing shares yet
            nbShares = _amount;
        }

        marketShares[_crERC20Address] = totalShares + nbShares;
        shares[_crERC20Address][msg.sender] += nbShares;
    }

    /** @dev Provides the value of shares for a given market.
     *  @param _crERC20Address The address of the market the user wants to interact with.
     *  @param _shares The amount of shares.
     */
    function _shareValue(address _crERC20Address, uint256 _shares) internal returns (uint256) {
        if (marketShares[_crERC20Address] == 0) {
            return _shares;
        }

        return
            (_shares * _totalAssetsOnPositionsManager(_crERC20Address)) /
            marketShares[_crERC20Address];
    }

    /** @dev Returns the total assets on PositionsManager for the pure supplier for a given market.
     *  @param _crERC20Address The address of the market the user wants to interact with.
     */
    function _totalAssetsOnPositionsManager(address _crERC20Address)
        internal
        returns (uint256 total_)
    {
        // Get balance of the pure supplier on positionsManager
        (uint256 inP2P, uint256 onCream) = positionsManager.supplyBalanceInOf(
            _crERC20Address,
            address(this)
        );

        // Get total + interests
        ICErc20 crERC20Token = ICErc20(_crERC20Address);
        total_ =
            onCream.mul(crERC20Token.exchangeRateCurrent()) +
            inP2P.mul(marketsManager.updateMUnitExchangeRate(_crERC20Address));
    }
}
