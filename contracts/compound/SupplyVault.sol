// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "./interfaces/compound/ICompound.sol";
import "./interfaces/IMorpho.sol";

import "./libraries/CompoundMath.sol";
import "./libraries/Types.sol";

import "@contracts/common/ERC4626Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

/// @title SupplyVault.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice ERC4626-upgradeable tokenized Vault implementation for Morpho-Compound.
contract SupplyVault is ERC4626Upgradeable, OwnableUpgradeable {
    using SafeTransferLib for ERC20;
    using CompoundMath for uint256;

    /// EVENTS ///

    /// @notice Emitted when the fee for harvesting is set.
    /// @param newHarvestingFee The new harvesting fee.
    event HarvestingFeeSet(uint16 newHarvestingFee);

    /// @notice Emitted when the fee for swapping comp for WETH is set.
    /// @param newCompSwapFee The new comp swap fee (in UniswapV3 fee unit).
    event CompSwapFeeSet(uint16 newCompSwapFee);

    /// @notice Emitted when the fee for swapping WETH for the underlying asset is set.
    /// @param newAssetSwapFee The new asset swap fee (in UniswapV3 fee unit).
    event AssetSwapFeeSet(uint16 newAssetSwapFee);

    /// @notice Emitted when the maximum slippage for harvesting is set.
    /// @param newMaxHarvestingSlippage The new maximum slippage allowed when swapping rewards for the underlying token (in bps).
    event MaxHarvestingSlippageSet(uint16 newMaxHarvestingSlippage);

    /// STORAGE ///

    ISwapRouter public constant SWAP_ROUTER =
        ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564); // The address of UniswapV3SwapRouter.

    IMorpho public morpho; // The main Morpho contract.
    ICToken public poolToken; // The pool token corresponding to the market to supply through this vault.

    address public wEth; // The address of WETH token.
    address public cComp; // The address of cCOMP token.

    bool public isEth; // Whether the underlying asset is WETH.
    uint24 public compSwapFee; // The fee taken by the UniswapV3Pool for swapping COMP rewards for WETH (in UniswapV3 fee unit).
    uint24 public assetSwapFee; // The fee taken by the UniswapV3Pool for swapping WETH for the underlying asset (in UniswapV3 fee unit).
    uint16 public harvestingFee; // The fee taken by the claimer when harvesting the vault (in bps).
    uint16 public maxHarvestingSlippage; // The maximum slippage allowed when swapping rewards for the underlying asset (in bps).
    uint16 public constant MAX_BASIS_POINTS = 10_000; // 100% in basis points.

    /// UPGRADE ///

    /// @notice Initializes the vault.
    /// @param _morphoAddress The address of the main Morpho contract.
    /// @param _poolTokenAddress The address of the pool token corresponding to the market to supply through this vault.
    /// @param _name The name of the ERC20 token associated to this tokenized vault.
    /// @param _symbol The symbol of the ERC20 token associated to this tokenized vault.
    /// @param _initialDeposit The amount of the initial deposit used to prevent pricePerShare manipulation.
    /// @param _compSwapFee The fee taken by the UniswapV3Pool for swapping COMP rewards for WETH (in UniswapV3 fee unit).
    /// @param _assetSwapFee The fee taken by the UniswapV3Pool for swapping WETH for the underlying asset (in UniswapV3 fee unit).
    /// @param _harvestingFee The fee taken by the claimer when harvesting the vault (in bps).
    /// @param _maxHarvestingSlippage The maximum slippage allowed when swapping rewards for the underlying asset (in bps).
    function initialize(
        address _morphoAddress,
        address _poolTokenAddress,
        string calldata _name,
        string calldata _symbol,
        uint256 _initialDeposit,
        uint24 _compSwapFee,
        uint24 _assetSwapFee,
        uint16 _harvestingFee,
        uint16 _maxHarvestingSlippage,
        address _cComp
    ) external initializer {
        morpho = IMorpho(_morphoAddress);
        poolToken = ICToken(_poolTokenAddress);
        compSwapFee = _compSwapFee;
        assetSwapFee = _assetSwapFee;
        harvestingFee = _harvestingFee;
        maxHarvestingSlippage = _maxHarvestingSlippage;

        isEth = _poolTokenAddress == morpho.cEth();
        wEth = morpho.wEth();
        cComp = _cComp;

        __Ownable_init();
        __ERC4626_init(
            ERC20(isEth ? wEth : poolToken.underlying()),
            _name,
            _symbol,
            _initialDeposit
        );
    }

    /// EXTERNAL ///

    /// @notice Harvests the vault: claims rewards from the underlying pool, swaps them for the underlying asset and supply them through Morpho.
    /// @param _maxSlippage The maximum slippage allowed for the swap (in bps).
    /// @return rewardsAmount_ The amount of rewards claimed, swapped then supplied through Morpho (in underlying).
    /// @return rewardsFee_ The amount of fees taken by the claimer (in underlying).
    function harvest(uint16 _maxSlippage)
        external
        returns (uint256 rewardsAmount_, uint256 rewardsFee_)
    {
        address poolTokenAddress = address(poolToken);

        {
            address[] memory poolTokenAddresses = new address[](1);
            poolTokenAddresses[0] = poolTokenAddress;
            morpho.claimRewards(poolTokenAddresses, false);
        }

        ERC20 comp;
        uint256 amountOutMinimum;
        {
            IComptroller comptroller = morpho.comptroller();
            comp = ERC20(comptroller.getCompAddress());
            rewardsAmount_ = comp.balanceOf(address(this));

            ICompoundOracle oracle = ICompoundOracle(comptroller.oracle());
            amountOutMinimum = rewardsAmount_
            .mul(oracle.getUnderlyingPrice(cComp))
            .div(oracle.getUnderlyingPrice(poolTokenAddress))
            .mul(MAX_BASIS_POINTS - CompoundMath.min(_maxSlippage, maxHarvestingSlippage))
            .div(MAX_BASIS_POINTS);
        }

        comp.safeApprove(address(SWAP_ROUTER), rewardsAmount_);
        rewardsAmount_ = SWAP_ROUTER.exactInput(
            ISwapRouter.ExactInputParams({
                path: isEth
                    ? abi.encodePacked(address(comp), compSwapFee, wEth)
                    : abi.encodePacked(
                        address(comp),
                        compSwapFee,
                        wEth,
                        assetSwapFee,
                        address(asset)
                    ),
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: rewardsAmount_,
                amountOutMinimum: amountOutMinimum
            })
        );

        rewardsFee_ = (rewardsAmount_ * harvestingFee) / MAX_BASIS_POINTS;
        rewardsAmount_ -= rewardsFee_;

        asset.safeApprove(address(morpho), rewardsAmount_);
        morpho.supply(poolTokenAddress, address(this), rewardsAmount_);

        asset.safeTransfer(msg.sender, rewardsFee_);
    }

    /// @notice Sets the fee taken by the UniswapV3Pool for swapping COMP rewards for WETH.
    /// @param _newCompSwapFee The new comp swap fee (in UniswapV3 fee unit).
    function setCompSwapFee(uint16 _newCompSwapFee) external onlyOwner {
        compSwapFee = _newCompSwapFee;
        emit CompSwapFeeSet(_newCompSwapFee);
    }

    /// @notice Sets the fee taken by the UniswapV3Pool for swapping WETH for the underlying asset.
    /// @param _newAssetSwapFee The new asset swap fee (in UniswapV3 fee unit).
    function setAssetSwapFee(uint16 _newAssetSwapFee) external onlyOwner {
        assetSwapFee = _newAssetSwapFee;
        emit AssetSwapFeeSet(_newAssetSwapFee);
    }

    /// @notice Sets the fee taken by the claimer from the total amount of COMP rewards when harvesting the vault.
    /// @param _newHarvestingFee The new harvesting fee (in bps).
    function setHarvestingFee(uint16 _newHarvestingFee) external onlyOwner {
        harvestingFee = _newHarvestingFee;
        emit HarvestingFeeSet(_newHarvestingFee);
    }

    /// @notice Sets the maximum slippage allowed when swapping rewards for the underlying token.
    /// @param _newMaxHarvestingSlippage The new maximum slippage allowed when swapping rewards for the underlying token (in bps).
    function setMaxHarvestingSlippage(uint16 _newMaxHarvestingSlippage) external onlyOwner {
        maxHarvestingSlippage = _newMaxHarvestingSlippage;
        emit MaxHarvestingSlippageSet(_newMaxHarvestingSlippage);
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

    /// INTERNAL ///

    function _beforeWithdraw(uint256 _amount, uint256) internal override {
        morpho.withdraw(address(poolToken), _amount);
    }

    function _afterDeposit(uint256 _amount, uint256) internal override {
        asset.safeApprove(address(morpho), _amount);
        morpho.supply(address(poolToken), address(this), _amount);
    }
}
