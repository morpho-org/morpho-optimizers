// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "hardhat/console.sol";

import "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@contracts/aave/interfaces/aave/IAaveIncentivesController.sol";
import "@contracts/aave/interfaces/aave/IPriceOracleGetter.sol";
import "@contracts/aave/interfaces/aave/IProtocolDataProvider.sol";
import "@contracts/aave/interfaces/IRewardsManagerForAave.sol";
import "@contracts/common/interfaces/ISwapManager.sol";

import {RewardsManagerForAaveOnEthAndAvax} from "@contracts/aave/markets-managers/RewardsManagerForAaveOnEthAndAvax.sol";
import {RewardsManagerForAaveOnPolygon} from "@contracts/aave/markets-managers/RewardsManagerForAaveOnPolygon.sol";
import {SwapManagerUniV3OnEth} from "@contracts/common/SwapManagerUniV3OnEth.sol";
import {SwapManagerUniV3} from "@contracts/common/SwapManagerUniV3.sol";
import {PositionsManagerForAave} from "@contracts/aave/PositionsManagerForAave.sol";
import {UniswapPoolCreator} from "./UniswapPoolCreator.sol";
import {Utils} from "./Utils.sol";
import {User} from "./User.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@contracts/aave/PositionsManagerForAave.sol";
import "@contracts/aave/MarketsManagerForAave.sol";
import "@config/Config.sol";
import "./HevmHelper.sol";
import "./HEVM.sol";
import "./MorphoToken.sol";
import "./SimplePriceOracle.sol";

contract TestSetup is Config, Utils, HevmHelper {
    using WadRayMath for uint256;
    using SafeERC20 for IERC20;

    uint256 public constant MAX_BASIS_POINTS = 10000;
    uint256 public constant INITIAL_BALANCE = 1_000_000;

    PositionsManagerForAave internal positionsManager;
    PositionsManagerForAave internal fakePositionsManager;
    MarketsManagerForAave internal marketsManager;
    IRewardsManagerForAave internal rewardsManager;
    ISwapManager public swapManager;
    UniswapPoolCreator public uniswapPoolCreator;
    MorphoToken public morphoToken;
    address public REWARD_TOKEN =
        IAaveIncentivesController(aaveIncentivesControllerAddress).REWARD_TOKEN();

    ILendingPoolAddressesProvider public lendingPoolAddressesProvider;
    ILendingPool public lendingPool;
    IProtocolDataProvider public protocolDataProvider;
    IPriceOracleGetter public oracle;

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
    address[] public underlyings;

    function setUp() public {
        PositionsManagerForAave.MaxGas memory maxGas = PositionsManagerForAaveStorage.MaxGas({
            supply: 3e6,
            borrow: 3e6,
            withdraw: 3e6,
            repay: 3e6
        });

        lendingPoolAddressesProvider = ILendingPoolAddressesProvider(
            lendingPoolAddressesProviderAddress
        );
        lendingPool = ILendingPool(lendingPoolAddressesProvider.getLendingPool());

        if (block.chainid == 1) {
            // Mainnet network
            // Create a MORPHO / WETH pool
            uniswapPoolCreator = new UniswapPoolCreator();
            writeBalanceOf(
                address(uniswapPoolCreator),
                uniswapPoolCreator.WETH9(),
                INITIAL_BALANCE * WAD
            );
            morphoToken = new MorphoToken(address(uniswapPoolCreator));
            swapManager = new SwapManagerUniV3OnEth(address(morphoToken), MORPHO_UNIV3_FEE);
        } else if (block.chainid == 137) {
            // Polygon network
            // Create a MORPHO / WETH pool
            uniswapPoolCreator = new UniswapPoolCreator();
            writeBalanceOf(
                address(uniswapPoolCreator),
                uniswapPoolCreator.WETH9(),
                INITIAL_BALANCE * WAD
            );
            morphoToken = new MorphoToken(address(uniswapPoolCreator));
            swapManager = new SwapManagerUniV3(
                address(morphoToken),
                MORPHO_UNIV3_FEE,
                REWARD_TOKEN,
                REWARD_UNIV3_FEE
            );
        }

        marketsManager = new MarketsManagerForAave(lendingPool);
        positionsManager = new PositionsManagerForAave(
            address(marketsManager),
            lendingPoolAddressesProviderAddress,
            swapManager,
            maxGas
        );

        if (block.chainid == 1) {
            // Mainnet network
            rewardsManager = new RewardsManagerForAaveOnEthAndAvax(
                lendingPool,
                IPositionsManagerForAave(address(positionsManager))
            );
            uniswapPoolCreator.createPoolAndMintPosition(address(morphoToken));
        } else if (block.chainid == 43114) {
            // Avalanche network
            rewardsManager = new RewardsManagerForAaveOnEthAndAvax(
                lendingPool,
                IPositionsManagerForAave(address(positionsManager))
            );
        } else if (block.chainid == 137) {
            // Polygon network
            rewardsManager = new RewardsManagerForAaveOnPolygon(
                lendingPool,
                IPositionsManagerForAave(address(positionsManager))
            );
            uniswapPoolCreator.createPoolAndMintPosition(address(morphoToken));
        }

        treasuryVault = new User(positionsManager, marketsManager, rewardsManager);

        fakePositionsManager = new PositionsManagerForAave(
            address(marketsManager),
            lendingPoolAddressesProviderAddress,
            swapManager,
            maxGas
        );

        protocolDataProvider = IProtocolDataProvider(protocolDataProviderAddress);

        oracle = IPriceOracleGetter(lendingPoolAddressesProvider.getPriceOracle());

        marketsManager.setPositionsManager(address(positionsManager));
        positionsManager.setAaveIncentivesController(aaveIncentivesControllerAddress);

        rewardsManager.setAaveIncentivesController(aaveIncentivesControllerAddress);
        positionsManager.setTreasuryVault(address(treasuryVault));
        positionsManager.setRewardsManager(address(rewardsManager));

        // !!! WARNING !!!
        // All tokens must also be added to the pools array, for the correct behavior of TestLiquidate::createAndSetCustomPriceOracle.
        marketsManager.createMarket(dai);
        pools.push(aDai);
        underlyings.push(dai);
        marketsManager.createMarket(usdc);
        pools.push(aUsdc);
        underlyings.push(usdc);
        marketsManager.createMarket(wbtc);
        pools.push(aWbtc);
        underlyings.push(wbtc);
        marketsManager.createMarket(usdt);
        pools.push(aUsdt);
        underlyings.push(usdt);

        for (uint256 i = 0; i < 3; i++) {
            suppliers.push(new User(positionsManager, marketsManager, rewardsManager));

            writeBalanceOf(address(suppliers[i]), dai, INITIAL_BALANCE * WAD);
            writeBalanceOf(address(suppliers[i]), usdc, INITIAL_BALANCE * 1e6);
        }
        supplier1 = suppliers[0];
        supplier2 = suppliers[1];
        supplier3 = suppliers[2];

        for (uint256 i = 0; i < 3; i++) {
            borrowers.push(new User(positionsManager, marketsManager, rewardsManager));

            writeBalanceOf(address(borrowers[i]), dai, INITIAL_BALANCE * WAD);
            writeBalanceOf(address(borrowers[i]), usdc, INITIAL_BALANCE * 1e6);
        }
        borrower1 = borrowers[0];
        borrower2 = borrowers[1];
        borrower3 = borrowers[2];
    }

    function createSigners(uint8 _nbOfSigners) internal {
        while (borrowers.length < _nbOfSigners) {
            borrowers.push(new User(positionsManager, marketsManager, rewardsManager));
            writeBalanceOf(address(borrowers[borrowers.length - 1]), dai, INITIAL_BALANCE * WAD);
            writeBalanceOf(address(borrowers[borrowers.length - 1]), usdc, INITIAL_BALANCE * 1e6);

            suppliers.push(new User(positionsManager, marketsManager, rewardsManager));
            writeBalanceOf(address(suppliers[suppliers.length - 1]), dai, INITIAL_BALANCE * WAD);
            writeBalanceOf(address(suppliers[suppliers.length - 1]), usdc, INITIAL_BALANCE * 1e6);
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

    function setMaxGasHelper(
        uint64 _supply,
        uint64 _borrow,
        uint64 _withdraw,
        uint64 _repay
    ) public {
        PositionsManagerForAaveStorage.MaxGas memory newMaxGas = PositionsManagerForAaveStorage
        .MaxGas({supply: _supply, borrow: _borrow, withdraw: _withdraw, repay: _repay});

        positionsManager.setMaxGas(newMaxGas);
    }
}
