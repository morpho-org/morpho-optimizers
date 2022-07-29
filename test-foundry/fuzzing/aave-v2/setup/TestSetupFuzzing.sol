// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "@contracts/aave-v2/interfaces/aave/IAaveIncentivesController.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@contracts/aave-v2/interfaces/aave/IPriceOracleGetter.sol";
import "@contracts/aave-v2/interfaces/aave/IVariableDebtToken.sol";
import "@contracts/aave-v2/interfaces/IInterestRatesManager.sol";
import "@contracts/aave-v2/interfaces/aave/ILendingPool.sol";
import "@contracts/aave-v2/interfaces/IRewardsManager.sol";
import "@contracts/aave-v2/interfaces/aave/IAToken.sol";
import "@contracts/aave-v2/interfaces/IMorpho.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import "@morpho-labs/morpho-utils/math/WadRayMath.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@contracts/aave-v2/libraries/Types.sol";

import {RewardsManagerOnMainnetAndAvalanche} from "@contracts/aave-v2/rewards-managers/RewardsManagerOnMainnetAndAvalanche.sol";
import {RewardsManagerOnPolygon} from "@contracts/aave-v2/rewards-managers/RewardsManagerOnPolygon.sol";
import {InterestRatesManager} from "@contracts/aave-v2/InterestRatesManager.sol";
import {IncentivesVault} from "@contracts/aave-v2/IncentivesVault.sol";
import {MatchingEngine} from "@contracts/aave-v2/MatchingEngine.sol";
import {EntryPositionsManager} from "@contracts/aave-v2/EntryPositionsManager.sol";
import {ExitPositionsManager} from "@contracts/aave-v2/ExitPositionsManager.sol";
import {Lens} from "@contracts/aave-v2/Lens.sol";
import "@contracts/aave-v2/Morpho.sol";

import "../../../common/helpers/MorphoToken.sol";
import "../../../aave-v2/helpers/SimplePriceOracle.sol";
import {DumbOracle} from "../../../aave-v2/helpers/DumbOracle.sol";
import "../../../common/helpers/Chains.sol";
import {User} from "../../../aave-v2/helpers/User.sol";
import {Utils} from "../../../aave-v2/setup/Utils.sol";
import "@forge-std/stdlib.sol";
import "@forge-std/console.sol";
import "@config/Config.sol";

contract TestSetupFuzzing is Config, Utils, stdCheats {
    Vm public hevm = Vm(HEVM_ADDRESS);

    uint256 public constant MAX_BASIS_POINTS = 10_000;
    uint256 public constant INITIAL_BALANCE = 15_000_000_000;

    ProxyAdmin public proxyAdmin;
    TransparentUpgradeableProxy public morphoProxy;
    Morpho public morphoImplV1;
    Morpho public morpho;
    IInterestRatesManager public interestRatesManager;
    TransparentUpgradeableProxy internal rewardsManagerProxy;
    IRewardsManager internal rewardsManagerImplV1;
    IRewardsManager public rewardsManager;
    IEntryPositionsManager public entryManager;
    IExitPositionsManager public exitManager;
    Lens public lens;
    MorphoToken public morphoToken;
    address public REWARD_TOKEN =
        IAaveIncentivesController(aaveIncentivesControllerAddress).REWARD_TOKEN();

    IncentivesVault public incentivesVault;
    DumbOracle internal dumbOracle;
    ILendingPoolAddressesProvider public lendingPoolAddressesProvider;
    IPriceOracleGetter public oracle;
    ILendingPool public lendingPool;

    User public supplier1;
    User public supplier2;
    User public supplier3;
    User[] public suppliers;
    User public borrower1;
    User public borrower2;
    User public borrower3;
    User[] public borrowers;
    User public treasuryVault;

    address[] public pools;

    function setUp() public {
        initContracts();
        setContractsLabels();
        initUsers();
    }

    function initContracts() internal {
        Types.MaxGasForMatching memory defaultMaxGasForMatching = Types.MaxGasForMatching({
            supply: 3e6,
            borrow: 3e6,
            withdraw: 3e6,
            repay: 3e6
        });

        lendingPoolAddressesProvider = ILendingPoolAddressesProvider(poolAddressesProviderAddress);
        lendingPool = ILendingPool(lendingPoolAddressesProvider.getLendingPool());
        entryManager = new EntryPositionsManager();
        exitManager = new ExitPositionsManager();

        /// Deploy proxies ///

        proxyAdmin = new ProxyAdmin();
        interestRatesManager = new InterestRatesManager();

        morphoImplV1 = new Morpho();
        morphoProxy = new TransparentUpgradeableProxy(address(morphoImplV1), address(this), "");

        morphoProxy.changeAdmin(address(proxyAdmin));
        morpho = Morpho(payable(address(morphoProxy)));
        morpho.initialize(
            entryManager,
            exitManager,
            interestRatesManager,
            ILendingPoolAddressesProvider(poolAddressesProviderAddress),
            defaultMaxGasForMatching,
            20
        );

        // make sure the wEth contract has enough ETH to unwrap any amount
        hevm.deal(wEth, type(uint128).max);

        lens = new Lens(address(morpho), lendingPoolAddressesProvider);
        treasuryVault = new User(morpho);
        morpho.setTreasuryVault(address(treasuryVault));

        if (block.chainid == Chains.ETH_MAINNET || block.chainid == Chains.AVALANCHE_MAINNET) {
            rewardsManagerImplV1 = new RewardsManagerOnMainnetAndAvalanche();
        } else if (block.chainid == Chains.POLYGON_MAINNET) {
            rewardsManagerImplV1 = new RewardsManagerOnPolygon();
        }

        rewardsManagerProxy = new TransparentUpgradeableProxy(
            address(rewardsManagerImplV1),
            address(proxyAdmin),
            ""
        );
        rewardsManager = IRewardsManager(address(rewardsManagerProxy));
        rewardsManager.initialize(address(morpho));
        rewardsManager.setAaveIncentivesController(aaveIncentivesControllerAddress);
        morpho.setAaveIncentivesController(aaveIncentivesControllerAddress);

        /// Create markets ///

        createMarket(aDai);
        createMarket(aUsdc);
        createMarket(aUsdt);
        createMarket(aWbtc);
        createMarket(aWeth);

        hevm.warp(block.timestamp + 100);

        /// Create Morpho token, deploy Incentives Vault and activate rewards ///

        morphoToken = new MorphoToken(address(this));
        dumbOracle = new DumbOracle();
        incentivesVault = new IncentivesVault(
            IMorpho(address(morpho)),
            morphoToken,
            ERC20(IAaveIncentivesController(aaveIncentivesControllerAddress).REWARD_TOKEN()),
            address(1),
            dumbOracle
        );
        morphoToken.transfer(address(incentivesVault), 1_000_000 ether);

        oracle = IPriceOracleGetter(lendingPoolAddressesProvider.getPriceOracle());

        morpho.setRewardsManager(rewardsManager);
        morpho.setIncentivesVault(incentivesVault);
    }

    function createMarket(address _aToken) internal {
        address underlying = IAToken(_aToken).UNDERLYING_ASSET_ADDRESS();
        Types.Market memory market = Types.Market(0, 3_333);
        morpho.createMarket(underlying, market);

        // All tokens must also be added to the pools array, for the correct behavior of TestLiquidate::createAndSetCustomPriceOracle.
        pools.push(_aToken);

        hevm.label(_aToken, ERC20(_aToken).symbol());
        hevm.label(underlying, ERC20(underlying).symbol());
    }

    function initUsers() internal {
        for (uint256 i = 0; i < 3; i++) {
            suppliers.push(new User(morpho));
            hevm.label(
                address(suppliers[i]),
                string(abi.encodePacked("Supplier", Strings.toString(i + 1)))
            );
            fillUserBalances(suppliers[i]);
        }
        supplier1 = suppliers[0];
        supplier2 = suppliers[1];
        supplier3 = suppliers[2];

        for (uint256 i = 0; i < 3; i++) {
            borrowers.push(new User(morpho));
            hevm.label(
                address(borrowers[i]),
                string(abi.encodePacked("Borrower", Strings.toString(i + 1)))
            );
            fillUserBalances(borrowers[i]);
        }

        borrower1 = borrowers[0];
        borrower2 = borrowers[1];
        borrower3 = borrowers[2];
    }

    function fillUserBalances(User _user) internal {
        for (uint256 i; i < pools.length; i++) {
            address token = getUnderlying(pools[i]);
            if (token == wEth) {
                deal(token, address(_user), uint256(5856057446759574251267521) / 2);
            } else {
                deal(token, address(_user), ERC20(token).totalSupply() / 2);
            }
        }
    }

    function setContractsLabels() internal {
        hevm.label(address(morpho), "Morpho");
        hevm.label(address(rewardsManager), "RewardsManager");
        hevm.label(address(morphoToken), "MorphoToken");
        hevm.label(aaveIncentivesControllerAddress, "AaveIncentivesController");
        hevm.label(address(lendingPoolAddressesProvider), "LendingPoolAddressesProvider");
        hevm.label(address(lendingPool), "LendingPool");
        hevm.label(address(oracle), "AaveOracle");
        hevm.label(address(treasuryVault), "TreasuryVault");
        hevm.label(address(interestRatesManager), "InterestRatesManager");
        hevm.label(address(incentivesVault), "IncentivesVault");
    }

    function createSigners(uint256 _nbOfSigners) internal {
        while (borrowers.length < _nbOfSigners) {
            borrowers.push(new User(morpho));
            fillUserBalances(borrowers[borrowers.length - 1]);
            suppliers.push(new User(morpho));
            fillUserBalances(suppliers[suppliers.length - 1]);
        }
    }

    function createAndSetCustomPriceOracle() public returns (SimplePriceOracle) {
        SimplePriceOracle customOracle = new SimplePriceOracle();

        hevm.store(
            address(lendingPoolAddressesProvider),
            keccak256(abi.encode(bytes32("PRICE_ORACLE"), 2)),
            bytes32(uint256(uint160(address(customOracle))))
        );

        for (uint256 i = 0; i < pools.length; i++) {
            address underlying = IAToken(pools[i]).UNDERLYING_ASSET_ADDRESS();

            customOracle.setDirectPrice(underlying, oracle.getAssetPrice(underlying));
        }

        return customOracle;
    }

    function setDefaultMaxGasForMatchingHelper(
        uint64 _supply,
        uint64 _borrow,
        uint64 _withdraw,
        uint64 _repay
    ) public {
        Types.MaxGasForMatching memory newMaxGas = Types.MaxGasForMatching({
            supply: _supply,
            borrow: _borrow,
            withdraw: _withdraw,
            repay: _repay
        });
        morpho.setDefaultMaxGasForMatching(newMaxGas);
    }

    function move1YearForward(address _marketAddress) public {
        for (uint256 k; k < 365; k++) {
            hevm.warp(block.timestamp + (1 days));
            morpho.updateIndexes(_marketAddress);
        }
    }

    /// @notice Computes and returns peer-to-peer rates for a specific market (without taking into account deltas!).
    /// @param _poolTokenAddress The market address.
    /// @return p2pSupplyRate_ The market's supply rate in peer-to-peer (in ray).
    /// @return p2pBorrowRate_ The market's borrow rate in peer-to-peer (in ray).
    function getApproxP2PRates(address _poolTokenAddress)
        public
        view
        returns (uint256 p2pSupplyRate_, uint256 p2pBorrowRate_)
    {
        DataTypes.ReserveData memory reserveData = lendingPool.getReserveData(
            IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS()
        );

        uint256 poolSupplyAPR = reserveData.currentLiquidityRate;
        uint256 poolBorrowAPR = reserveData.currentVariableBorrowRate;
        (uint16 reserveFactor, uint256 p2pIndexCursor) = morpho.market(_poolTokenAddress);

        // rate = (1 - p2pIndexCursor) * poolSupplyRate + p2pIndexCursor * poolBorrowRate.
        uint256 rate = ((10_000 - p2pIndexCursor) *
            poolSupplyAPR +
            p2pIndexCursor *
            poolBorrowAPR) / 10_000;

        p2pSupplyRate_ = rate - (reserveFactor * (rate - poolSupplyAPR)) / 10_000;
        p2pBorrowRate_ = rate + (reserveFactor * (poolBorrowAPR - rate)) / 10_000;
    }

    /// @notice Returns the underlying for a given market.
    /// @param _poolTokenAddress The address of the market.
    function getUnderlying(address _poolTokenAddress) internal view returns (address) {
        return IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS();
    }

    /// @notice Returns the asset and its underlying for a given market, excluding USDT.
    /// @param _asset The fuzzing asset.
    function getSupplyAsset(uint8 _asset)
        internal
        view
        returns (address asset, address underlying)
    {
        asset = pools[_asset % pools.length];
        underlying = getUnderlying(asset);
        if (underlying == usdt) {
            uint256 index = _asset % pools.length;
            index = index == pools.length - 1 ? 0 : index + 1;
            asset = pools[index];
            underlying = getUnderlying(asset);
        }
    }

    function getAsset(uint8 _asset) internal view returns (address asset, address underlying) {
        asset = pools[_asset % pools.length];
        underlying = getUnderlying(asset);
    }

    /// @notice Checks morpho will not revert.
    /// @param _underlying Address of the underlying to supply.
    /// @param _amount To check.
    function getSupplyAmount(address _underlying, uint256 _amount) internal view returns (uint256) {
        uint256 min = 10**ERC20(_underlying).decimals();

        return bound(_amount, min, ERC20(_underlying).balanceOf(address(supplier1)));
    }

    /// @notice Checks morpho will not revert.
    /// @param _underlying Address of the underlying to borrow.
    /// @param _pcent Address of the underlying to borrow.
    function getBorrowAmount(address _underlying, uint256 _pcent) internal view returns (uint256) {
        (, uint256 borrowable) = lens.getUserMaxCapacitiesForAsset(address(borrower1), _underlying);

        return (borrowable * _pcent) / 100;
    }

    function bound(
        uint256 x,
        uint256 min,
        uint256 max
    ) internal pure returns (uint256 result) {
        require(max >= min, "MAX_LESS_THAN_MIN");

        uint256 size = max - min;

        if (max != type(uint256).max) size++; // Make the max inclusive.
        if (size == 0) return min; // Using max would be equivalent as well.
        // Ensure max is inclusive in cases where x != 0 and max is at uint max.
        if (max == type(uint256).max && x != 0) x--; // Accounted for later.

        if (x < min) x += size * (((min - x) / size) + 1);
        result = min + ((x - min) % size);

        // Account for decrementing x to make max inclusive.
        if (max == type(uint256).max && x != 0) result++;

        // emit log_named_uint("Bound entry", x);
        // emit log_named_uint("Bound result", result);
    }

    /// @notice Checks morpho will not revert.
    /// @param underlying Address of the underlying to supply.
    /// @param amount To check.
    function assumeSupplyAmountIsCorrect(address underlying, uint256 amount) internal {
        hevm.assume(amount > 0);
        // All the signers have the same balance at the beginning of a test.
        hevm.assume(amount <= ERC20(underlying).balanceOf(address(supplier1)));
    }

    /// @notice A borrow amount can be too high on Aave due to governance or unsufficient supply.
    /// @param market Address of the AToken.
    /// @param amount To check.
    function assumeBorrowAmountIsCorrect(address market, uint256 amount) internal {
        hevm.assume(amount <= IAToken(market).scaledTotalSupply());
        hevm.assume(amount > 10);
        uint256 borrowCap = IERC20(getUnderlying(market)).balanceOf(market);
        if (borrowCap != 0) hevm.assume(amount <= borrowCap);
    }

    /// @notice Ensures the amount used for the liquidation is correct.
    /// @param amount Considered for the liquidation.
    function assumeLiquidateAmountIsCorrect(uint256 amount) internal {
        hevm.assume(amount > 0);
    }

    /// @notice Ensures the amount used for the repay is correct.
    /// @param amount Considered for the repay.
    function assumeRepayAmountIsCorrect(uint256 amount) internal {
        hevm.assume(amount > 0);
    }

    /// @notice Make sure the amount used for the withdraw is correct.
    /// @param market Address of the AToken.
    /// @param amount Considered for the repay.
    function assumeWithdrawAmountIsCorrect(address market, uint256 amount) internal {
        // TODO hevm.assume(amount.div(ICToken(market).exchangeRateCurrent()) > 0);
    }
}
