// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "ds-test/test.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

import "@contracts/aave/interfaces/aave/IAaveIncentivesController.sol";
import "@contracts/aave/interfaces/aave/IPriceOracleGetter.sol";
import "@contracts/aave/interfaces/aave/IProtocolDataProvider.sol";
import "@contracts/aave/interfaces/IRewardsManagerForAave.sol";

import {RewardsManagerForAaveOnAvalanche} from "@contracts/aave/markets-managers/RewardsManagerForAaveOnAvalanche.sol";
import {RewardsManagerForAaveOnPolygon} from "@contracts/aave/markets-managers/RewardsManagerForAaveOnPolygon.sol";
import "@contracts/aave/PositionsManagerForAave.sol";
import "@contracts/aave/MarketsManagerForAave.sol";
import "@contracts/common/SwapManager.sol";

import "@config/Config.sol";
import "./HevmAdapter.sol";
import "../helpers/Utils.sol";
import "../helpers/User.sol";
import "../helpers/MorphoToken.sol";
import "../helpers/SimplePriceOracle.sol";
import "../uniswap/UniswapPoolCreator.sol";

contract TestSetup is DSTest, Config, Utils, HevmAdapter {
    using WadRayMath for uint256;

    uint256 public constant MAX_BASIS_POINTS = 10000;
    uint256 public constant INITIAL_BALANCE = 1_000_000;

    PositionsManagerForAave internal positionsManager;
    PositionsManagerForAave internal fakePositionsManager;
    MarketsManagerForAave internal marketsManager;
    IRewardsManagerForAave internal rewardsManager;
    SwapManager public swapManager;
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

    function setUp() public {
        initContracts();
        setContractsLabels();
        initUsers();
    }

    function initContracts() internal {
        PositionsManagerForAave.MaxGas memory maxGas = PositionsManagerForAaveStorage.MaxGas({
            supply: 3e6,
            borrow: 3e6,
            withdraw: 1.5e6,
            repay: 1.5e6
        });

        lendingPoolAddressesProvider = ILendingPoolAddressesProvider(
            lendingPoolAddressesProviderAddress
        );
        lendingPool = ILendingPool(lendingPoolAddressesProvider.getLendingPool());

        if (block.chainid != 43114) {
            // NOT Avalanche network
            // Create a MORPHO / WETH pool
            uniswapPoolCreator = new UniswapPoolCreator();
            writeBalanceOf(
                address(uniswapPoolCreator),
                uniswapPoolCreator.WETH9(),
                INITIAL_BALANCE * WAD
            );
            morphoToken = new MorphoToken(address(uniswapPoolCreator));
            swapManager = new SwapManager(
                address(morphoToken),
                morphoPoolFee,
                REWARD_TOKEN,
                rewardPoolFee
            );
        }

        marketsManager = new MarketsManagerForAave(lendingPool);
        positionsManager = new PositionsManagerForAave(
            address(marketsManager),
            lendingPoolAddressesProviderAddress,
            swapManager,
            maxGas
        );

        if (block.chainid == 43114) {
            // Avalanche network
            rewardsManager = new RewardsManagerForAaveOnAvalanche(
                lendingPool,
                IPositionsManagerForAave(address(positionsManager))
            );
        } else {
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

        createMarket(aDai, WAD);
        createMarket(aUsdc, to6Decimals(WAD));
        createMarket(aWbtc, 100);
        createMarket(aUsdt, to6Decimals(WAD));
    }

    function createMarket(address _aToken, uint256 _threshold) internal {
        address underlying = IAToken(_aToken).UNDERLYING_ASSET_ADDRESS();
        marketsManager.createMarket(underlying, _threshold);

        // All tokens must also be added to the pools array, for the correct behavior of TestLiquidate::createAndSetCustomPriceOracle.
        pools.push(_aToken);

        hevm.label(_aToken, ERC20(_aToken).symbol());
        hevm.label(underlying, ERC20(underlying).symbol());
    }

    function setContractsLabels() internal {
        hevm.label(address(positionsManager), "PositionsManager");
        hevm.label(address(fakePositionsManager), "FakePositionsManager");
        hevm.label(address(marketsManager), "MarketsManager");
        hevm.label(address(rewardsManager), "RewardsManager");
        hevm.label(address(swapManager), "SwapManager");
        hevm.label(address(uniswapPoolCreator), "UniswapPoolCreator");
        hevm.label(address(morphoToken), "MorphoToken");
        hevm.label(aaveIncentivesControllerAddress, "AaveIncentivesController");
        hevm.label(address(lendingPoolAddressesProvider), "LendingPoolAddressesProvider");
        hevm.label(address(lendingPool), "LendingPool");
        hevm.label(address(protocolDataProvider), "ProtocolDataProvider");
        hevm.label(address(oracle), "AaveOracle");
        hevm.label(address(treasuryVault), "TreasuryVault");
    }

    function initUsers() internal {
        for (uint256 i = 0; i < 3; i++) {
            suppliers.push(new User(positionsManager, marketsManager, rewardsManager));
            fillDaiAndUsdcBalances(suppliers[i]);

            hevm.label(
                address(suppliers[i]),
                string(abi.encodePacked("Supplier", Strings.toString(i + 1)))
            );
        }
        supplier1 = suppliers[0];
        supplier2 = suppliers[1];
        supplier3 = suppliers[2];

        for (uint256 i = 0; i < 3; i++) {
            borrowers.push(new User(positionsManager, marketsManager, rewardsManager));
            fillDaiAndUsdcBalances(borrowers[i]);

            hevm.label(
                address(borrowers[i]),
                string(abi.encodePacked("Borrower", Strings.toString(i + 1)))
            );
        }
        borrower1 = borrowers[0];
        borrower2 = borrowers[1];
        borrower3 = borrowers[2];
    }

    function createSigners(uint8 _nbOfSigners) internal {
        while (borrowers.length < _nbOfSigners) {
            borrowers.push(new User(positionsManager, marketsManager, rewardsManager));
            fillDaiAndUsdcBalances(borrowers[borrowers.length - 1]);

            suppliers.push(new User(positionsManager, marketsManager, rewardsManager));
            fillDaiAndUsdcBalances(suppliers[suppliers.length - 1]);
        }
    }

    function fillDaiAndUsdcBalances(User _user) internal {
        writeBalanceOf(address(_user), dai, INITIAL_BALANCE * WAD);
        writeBalanceOf(address(_user), usdc, INITIAL_BALANCE * 1e6);
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

    function testEquality(uint256 _firstValue, uint256 _secondValue) internal {
        assertApproxEq(_firstValue, _secondValue, 20);
    }

    function testEquality(
        uint256 _firstValue,
        uint256 _secondValue,
        string memory err
    ) internal {
        assertApproxEq(_firstValue, _secondValue, 20, err);
    }
}
