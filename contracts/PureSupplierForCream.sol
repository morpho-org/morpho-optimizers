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

    mapping(address => uint256) public poolSupplies; // For a given market, the corresponding supply for the pool.
    mapping(address => mapping(address => uint256)) public shares; // For a given market, the shares balance of user.

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

        erc20Token.safeTransferFrom(msg.sender, address(this), _amount);
        erc20Token.safeApprove(address(positionsManager), _amount);

        _setSharesForAccount(_crERC20Address, _amount);
        positionsManager.supply(_crERC20Address, _amount);

        emit Supplied(msg.sender, _crERC20Address, _amount);
    }

    function withdraw(address _crERC20Address, uint256 _shares) external nonReentrant {
        require(_shares > 0, "withdraw:amount=0");
        require(_shares <= shares[_crERC20Address][msg.sender], "withdraw:shares");

        uint256 value = _shareValue(_crERC20Address, _shares);

        positionsManager.withdraw(_crERC20Address, value);

        poolSupplies[_crERC20Address] -= _shares;
        shares[_crERC20Address][msg.sender] -= _shares;

        ICErc20 crERC20Token = ICErc20(_crERC20Address);
        IERC20 erc20Token = IERC20(crERC20Token.underlying());
        erc20Token.safeTransfer(msg.sender, value);

        emit Withdrawn(msg.sender, _crERC20Address, value);
    }

    function _setSharesForAccount(address _crERC20Address, uint256 _amount) internal {
        uint256 nbShares = 0;
        uint256 totalSupply = poolSupplies[_crERC20Address];

        if (totalSupply > 0) {
            uint256 interestsEarned = _calculatePoolTotal(_crERC20Address) - totalSupply;
            if (interestsEarned == 0) {
                nbShares = _amount;
            } else {
                nbShares = (_amount * totalSupply) / (totalSupply - interestsEarned);
            }
        } else {
            // No existing shares yet
            nbShares = _amount;
        }

        poolSupplies[_crERC20Address] = totalSupply + nbShares;

        shares[_crERC20Address][msg.sender] += nbShares;
    }

    function _shareValue(address _crERC20Address, uint256 _shares) internal returns (uint256) {
        if (poolSupplies[_crERC20Address] == 0) {
            return _shares;
        }

        return (_shares * _calculatePoolTotal(_crERC20Address)) / poolSupplies[_crERC20Address];
    }

    function _calculatePoolTotal(address _crERC20Address) internal returns (uint256 total_) {
        // Get balance of PureLender on positionsManager
        (uint256 inP2P, uint256 onCream) = positionsManager.supplyBalanceInOf(
            _crERC20Address,
            address(this)
        );

        // Get total + interests
        ICErc20 crERC20Token = ICErc20(_crERC20Address);
        uint256 supplyOnCreamInUnderlying = onCream.mul(crERC20Token.exchangeRateStored());
        total_ =
            supplyOnCreamInUnderlying +
            inP2P.mul(marketsManager.updateMUnitExchangeRate(_crERC20Address));
    }
}
