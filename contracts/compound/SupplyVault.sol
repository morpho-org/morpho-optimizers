// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "./interfaces/compound/ICompound.sol";
import "./interfaces/IMorpho.sol";

import "./libraries/CompoundMath.sol";
import "./libraries/Types.sol";

import "@contracts/common/ERC4626Upgradeable.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

/// @title SupplyVault.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice ERC4626-upgradeable tokenized Vault implementation for Morpho-Compound.
contract SupplyVault is ERC4626Upgradeable {
    using SafeTransferLib for ERC20;
    using CompoundMath for uint256;

    /// EVENTS ///

    event ClaimingFeeSet(uint16 _newClaimingFee);

    /// STORAGE ///

    ISwapRouter public constant SWAP_ROUTER =
        ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    IMorpho public morpho;
    ICToken public poolToken;
    uint16 public claimingFee;
    uint16 public constant MAX_BASIS_POINTS = 10_000; // 100% in basis points.

    function initialize(
        address _morphoAddress,
        address _poolTokenAddress,
        string calldata _name,
        string calldata _symbol,
        uint256 _initialDeposit,
        uint16 _claimingFee
    ) external initializer {
        morpho = IMorpho(_morphoAddress);
        poolToken = ICToken(_poolTokenAddress);
        claimingFee = _claimingFee;

        __ERC4626_init(
            ERC20(_poolTokenAddress == morpho.cEth() ? morpho.wEth() : poolToken.underlying()),
            _name,
            _symbol,
            _initialDeposit
        );
    }

    /// EXTERNAL ///

    function claimRewards(uint16 swapFee)
        external
        returns (uint256 rewardsAmount_, uint256 rewardsFee_)
    {
        address[] memory poolTokenAddresses = new address[](1);
        poolTokenAddresses[0] = address(poolToken);
        morpho.claimRewards(poolTokenAddresses, false);

        ERC20 comp = ERC20(morpho.comptroller().getCompAddress());
        rewardsAmount_ = comp.balanceOf(address(this));

        ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(comp),
            tokenOut: address(asset),
            fee: swapFee,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: rewardsAmount_,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        comp.safeApprove(address(SWAP_ROUTER), rewardsAmount_);
        rewardsAmount_ = SWAP_ROUTER.exactInputSingle(swapParams);

        rewardsFee_ = (rewardsAmount_ * claimingFee) / MAX_BASIS_POINTS;
        rewardsAmount_ -= rewardsFee_;

        asset.safeApprove(address(morpho), rewardsAmount_);
        morpho.supply(address(poolToken), address(this), rewardsAmount_);

        asset.safeTransfer(msg.sender, rewardsFee_);
    }

    function setClaimingFee(uint16 _newClaimingFee) external onlyOwner {
        claimingFee = _newClaimingFee;
        emit ClaimingFeeSet(_newClaimingFee);
    }

    /// PUBLIC ///

    function totalAssets() public view override returns (uint256) {
        Types.SupplyBalance memory supplyBalance = morpho.supplyBalanceInOf(
            address(poolToken),
            address(this)
        );

        return
            supplyBalance.onPool.mul(poolToken.exchangeRateStored()) +
            supplyBalance.inP2P.mul(morpho.p2pSupplyIndex(address(poolToken)));
    }

    function _beforeWithdraw(uint256 _amount, uint256) internal override {
        morpho.withdraw(address(poolToken), _amount);
    }

    function _afterDeposit(uint256 _amount, uint256) internal override {
        asset.safeApprove(address(morpho), _amount);
        morpho.supply(address(poolToken), address(this), _amount);
    }
}
