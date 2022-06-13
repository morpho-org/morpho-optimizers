// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "@contracts/common/ERC4626Upgradeable.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

import "./libraries/CompoundMath.sol";
import "./interfaces/compound/ICompound.sol";
import "./interfaces/IMorpho.sol";
import "./libraries/Types.sol";

/// @title TokenizedVault.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice ERC4626-upgradeable tokenized Vault implementation for Morpho-Compound.
contract TokenizedVault is ERC4626Upgradeable {
    using SafeTransferLib for ERC20;
    using CompoundMath for uint256;

    /// STORAGE ///

    ISwapRouter public constant SWAP_ROUTER =
        ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    IMorpho public morpho;
    ICToken public poolToken;

    function initialize(
        address _morphoAddress,
        address _poolTokenAddress,
        string calldata _name,
        string calldata _symbol
    ) external initializer {
        morpho = IMorpho(_morphoAddress);
        poolToken = ICToken(_poolTokenAddress);

        __ERC4626_init(
            ERC20(_poolTokenAddress == morpho.cEth() ? morpho.wEth() : poolToken.underlying()),
            _name,
            _symbol
        );
    }

    function totalAssets() public view override returns (uint256) {
        Types.SupplyBalance memory supplyBalance = morpho.supplyBalanceInOf(
            address(poolToken),
            address(this)
        );
        uint256 p2pSupplyIndex = morpho.p2pSupplyIndex(address(poolToken));
        uint256 poolSupplyIndex = poolToken.exchangeRateStored();

        return supplyBalance.onPool.mul(poolSupplyIndex) + supplyBalance.inP2P.mul(p2pSupplyIndex);
    }

    function beforeWithdraw(uint256 _amount, uint256) internal override {
        morpho.withdraw(address(poolToken), _amount);
    }

    function afterDeposit(uint256 _amount, uint256) internal override {
        asset.safeApprove(address(morpho), _amount);
        morpho.supply(address(poolToken), address(this), _amount);
    }

    /// EXTERNAL ///

    function claimRewards(uint24 swapFee) external returns (uint256 rewardsAmount) {
        address[] memory poolTokenAddresses = new address[](1);
        poolTokenAddresses[0] = address(poolToken);
        morpho.claimRewards(poolTokenAddresses, false);

        ERC20 comp = ERC20(morpho.comptroller().getCompAddress());
        rewardsAmount = comp.balanceOf(address(this));

        ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(comp),
            tokenOut: address(asset),
            fee: swapFee,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: rewardsAmount,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        comp.safeApprove(address(SWAP_ROUTER), rewardsAmount);
        rewardsAmount = SWAP_ROUTER.exactInputSingle(swapParams);

        asset.safeApprove(address(morpho), rewardsAmount);
        morpho.supply(address(poolToken), address(this), rewardsAmount);
    }
}
