// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "@contracts/aave/interfaces/aave/IAaveIncentivesController.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@contracts/aave/interfaces/aave/IProtocolDataProvider.sol";
import "@contracts/aave/interfaces/aave/IPriceOracleGetter.sol";
import "@contracts/aave/interfaces/aave/IVariableDebtToken.sol";
import "@contracts/aave/interfaces/IInterestRatesManager.sol";
import "@contracts/aave/interfaces/aave/ILendingPool.sol";
import "@contracts/aave/interfaces/IRewardsManager.sol";
import "@contracts/common/interfaces/ISwapManager.sol";
import "@contracts/aave/interfaces/aave/IAToken.sol";
import "@contracts/aave/interfaces/IMorpho.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@contracts/aave/libraries/Types.sol";
import "@contracts/aave/libraries/Math.sol";

import {RewardsManagerForAaveOnMainnetAndAvalanche} from "@contracts/aave/rewards-managers/RewardsManagerForAaveOnMainnetAndAvalanche.sol";
import {RewardsManagerForAaveOnPolygon} from "@contracts/aave/rewards-managers/RewardsManagerForAaveOnPolygon.sol";
import {SwapManagerUniV3OnMainnet} from "@contracts/common/SwapManagerUniV3OnMainnet.sol";
import {SwapManagerUniV3} from "@contracts/common/SwapManagerUniV3.sol";
import {SwapManagerUniV2} from "@contracts/common/SwapManagerUniV2.sol";
import {UniswapV3PoolCreator} from "../../common/uniswap/UniswapV3PoolCreator.sol";
import {UniswapV2PoolCreator} from "../../common/uniswap/UniswapV2PoolCreator.sol";
import {InterestRatesManager} from "@contracts/aave/InterestRatesManager.sol";
import {PositionsManager} from "@contracts/aave/PositionsManager.sol";
import {MatchingEngine} from "@contracts/aave/MatchingEngine.sol";
import {Lens} from "@contracts/aave/Lens.sol";
import "@contracts/aave/Morpho.sol";

import "hardhat/console.sol";
import "../../common/helpers/MorphoToken.sol";
import "../helpers/SimplePriceOracle.sol";
import "../../common/helpers/Chains.sol";
import {User} from "../helpers/User.sol";
import {Utils} from "./Utils.sol";
import "forge-std/stdlib.sol";
import "@config/Config.sol";

contract TestSetup is Config, Utils, stdCheats {
    Vm public hevm = Vm(HEVM_ADDRESS);

    uint256 public constant MAX_BASIS_POINTS = 10_000;
    uint256 public constant INITIAL_BALANCE = 1_000_000;

    ProxyAdmin public proxyAdmin;
    TransparentUpgradeableProxy public morphoProxy;
    Morpho public morphoImplV1;
    Morpho public morpho;
    IInterestRatesManager public interestRatesManager;
    IRewardsManager public rewardsManager;
    IPositionsManager public positionsManager;
    Lens public lens;
    ISwapManager public swapManager;
    UniswapV3PoolCreator public uniswapV3PoolCreator;
    UniswapV2PoolCreator public uniswapV2PoolCreator;
    MorphoToken public morphoToken;
    address public REWARD_TOKEN =
        IAaveIncentivesController(aaveIncentivesControllerAddress).REWARD_TOKEN();

    ILendingPoolAddressesProvider public lendingPoolAddressesProvider;
    IProtocolDataProvider public protocolDataProvider;
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

        lendingPoolAddressesProvider = ILendingPoolAddressesProvider(
            lendingPoolAddressesProviderAddress
        );
        lendingPool = ILendingPool(lendingPoolAddressesProvider.getLendingPool());
        positionsManager = new PositionsManager();

        if (block.chainid == Chains.ETH_MAINNET) {
            // Mainnet network.
            // Create a MORPHO / WETH pool.
            uniswapV3PoolCreator = new UniswapV3PoolCreator();
            tip(uniswapV3PoolCreator.WETH9(), address(uniswapV3PoolCreator), INITIAL_BALANCE * WAD);
            morphoToken = new MorphoToken(address(uniswapV3PoolCreator));
            swapManager = new SwapManagerUniV3OnMainnet(
                address(morphoToken),
                MORPHO_UNIV3_FEE,
                1 hours,
                1 hours
            );
        } else if (block.chainid == Chains.POLYGON_MAINNET) {
            // Polygon network.
            // Create a MORPHO / WMATIC pool.
            uniswapV3PoolCreator = new UniswapV3PoolCreator();
            tip(uniswapV3PoolCreator.WETH9(), address(uniswapV3PoolCreator), INITIAL_BALANCE * WAD);
            morphoToken = new MorphoToken(address(uniswapV3PoolCreator));
            swapManager = new SwapManagerUniV3(
                address(morphoToken),
                MORPHO_UNIV3_FEE,
                REWARD_TOKEN,
                REWARD_UNIV3_FEE,
                1 hours,
                1 hours
            );
        } else if (block.chainid == Chains.AVALANCHE_MAINNET) {
            // Avalanche network.
            // Create a MORPHO / WAVAX pool.
            uniswapV2PoolCreator = new UniswapV2PoolCreator();
            tip(REWARD_TOKEN, address(uniswapV2PoolCreator), INITIAL_BALANCE * WAD);
            morphoToken = new MorphoToken(address(uniswapV2PoolCreator));
            uniswapV2PoolCreator.createPoolAndAddLiquidity(address(morphoToken));
            swapManager = new SwapManagerUniV2(
                0x60aE616a2155Ee3d9A68541Ba4544862310933d4,
                address(morphoToken),
                REWARD_TOKEN,
                1 hours
            );
        }

        proxyAdmin = new ProxyAdmin();
        interestRatesManager = new InterestRatesManager();

        morphoImplV1 = new Morpho();
        morphoProxy = new TransparentUpgradeableProxy(address(morphoImplV1), address(this), "");

        morphoProxy.changeAdmin(address(proxyAdmin));
        morpho = Morpho(payable(address(morphoProxy)));
        morpho.initialize(
            positionsManager,
            interestRatesManager,
            ILendingPoolAddressesProvider(lendingPoolAddressesProviderAddress),
            defaultMaxGasForMatching,
            20
        );

        lens = new Lens(address(morpho), lendingPoolAddressesProvider);

        if (block.chainid == Chains.ETH_MAINNET) {
            // Mainnet network
            rewardsManager = new RewardsManagerForAaveOnMainnetAndAvalanche(
                lendingPool,
                IMorpho(address(morpho)),
                address(swapManager)
            );
            uniswapV3PoolCreator.createPoolAndMintPosition(address(morphoToken));
        } else if (block.chainid == Chains.AVALANCHE_MAINNET) {
            // Avalanche network
            rewardsManager = new RewardsManagerForAaveOnMainnetAndAvalanche(
                lendingPool,
                IMorpho(address(morpho)),
                address(swapManager)
            );
        } else if (block.chainid == Chains.POLYGON_MAINNET) {
            // Polygon network
            rewardsManager = new RewardsManagerForAaveOnPolygon(
                lendingPool,
                IMorpho(address(morpho)),
                address(swapManager)
            );
            uniswapV3PoolCreator.createPoolAndMintPosition(address(morphoToken));
        }

        /// Create markets ///

        createMarket(aDai);
        createMarket(aUsdc);
        createMarket(aWbtc);
        createMarket(aUsdt);
        createMarket(aAave);

        treasuryVault = new User(morpho);

        oracle = IPriceOracleGetter(lendingPoolAddressesProvider.getPriceOracle());
        protocolDataProvider = IProtocolDataProvider(protocolDataProviderAddress);

        morpho.setAaveIncentivesController(aaveIncentivesControllerAddress);
        morpho.setTreasuryVault(address(treasuryVault));
        morpho.setRewardsManager(rewardsManager);
        rewardsManager.setAaveIncentivesController(aaveIncentivesControllerAddress);
    }

    function createMarket(address _aToken) internal {
        address underlying = IAToken(_aToken).UNDERLYING_ASSET_ADDRESS();
        morpho.createMarket(underlying);
        morpho.setP2PIndexCursor(_aToken, 3_333);

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
        tip(dai, address(_user), INITIAL_BALANCE * WAD);
        tip(aave, address(_user), INITIAL_BALANCE * WAD);
        tip(wEth, address(_user), INITIAL_BALANCE * WAD);
        tip(usdt, address(_user), INITIAL_BALANCE * WAD);
        tip(usdc, address(_user), INITIAL_BALANCE * 1e6);
    }

    function setContractsLabels() internal {
        hevm.label(address(morpho), "Morpho");
        hevm.label(address(rewardsManager), "RewardsManager");
        hevm.label(address(swapManager), "SwapManager");
        hevm.label(address(uniswapV3PoolCreator), "UniswapV3PoolCreator");
        hevm.label(address(morphoToken), "MorphoToken");
        hevm.label(aaveIncentivesControllerAddress, "AaveIncentivesController");
        hevm.label(address(lendingPoolAddressesProvider), "LendingPoolAddressesProvider");
        hevm.label(address(lendingPool), "LendingPool");
        hevm.label(address(protocolDataProvider), "ProtocolDataProvider");
        hevm.label(address(oracle), "AaveOracle");
        hevm.label(address(treasuryVault), "TreasuryVault");
        hevm.label(address(interestRatesManager), "InterestRatesManager");
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
            morpho.updateP2PIndexes(_marketAddress);
        }
    }

    /// @notice Computes and returns peer-to-peer rates for a specific market (without taking into account deltas !).
    /// @param _poolTokenAddress The market address.
    /// @return p2pSupplyRate_ The market's supply rate in peer-to-peer (in ray).
    /// @return p2pBorrowRate_ The market's borrow rate in peer-to-peer (in ray).
    function getApproxAPRs(address _poolTokenAddress)
        public
        view
        returns (uint256 p2pSupplyRate_, uint256 p2pBorrowRate_)
    {
        DataTypes.ReserveData memory reserveData = lendingPool.getReserveData(
            IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS()
        );

        uint256 poolSupplyAPR = reserveData.currentLiquidityRate;
        uint256 poolBorrowAPR = reserveData.currentVariableBorrowRate;
        (uint16 reserveFactor, uint256 p2pIndexCursor) = morpho.marketParameters(_poolTokenAddress);

        // rate = 2/3 * poolSupplyRate + 1/3 * poolBorrowRate.
        uint256 rate = ((10_000 - p2pIndexCursor) *
            poolSupplyAPR +
            p2pIndexCursor *
            poolBorrowAPR) / 10_000;

        p2pSupplyRate_ = rate - (reserveFactor * (rate - poolSupplyAPR)) / 10_000;
        p2pBorrowRate_ = rate + (reserveFactor * (poolBorrowAPR - rate)) / 10_000;
    }
}
