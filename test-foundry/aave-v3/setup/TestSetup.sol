// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";
import "@aave/core-v3/contracts/interfaces/IPriceOracleGetter.sol";
import "@aave/core-v3/contracts/interfaces/IVariableDebtToken.sol";
import "@aave/core-v3/contracts/interfaces/IPoolDataProvider.sol";
import "@aave/core-v3/contracts/interfaces/IAToken.sol";
import "@aave/core-v3/contracts/interfaces/IPool.sol";
import "@contracts/aave-v3/interfaces/IInterestRatesManager.sol";
import "@contracts/aave-v3/interfaces/IRewardsManager.sol";
import "@contracts/aave-v3/interfaces/IMorpho.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import "@aave/core-v3/contracts/protocol/libraries/math/WadRayMath.sol";
import "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@contracts/aave-v3/libraries/Types.sol";

// import {RewardsManagerOnMainnetAndAvalanche} from "@contracts/aave-v3/rewards-managers/RewardsManagerOnMainnetAndAvalanche.sol";
// import {RewardsManagerOnPolygon} from "@contracts/aave-v3/rewards-managers/RewardsManagerOnPolygon.sol";
import {InterestRatesManager} from "@contracts/aave-v3/InterestRatesManager.sol";
import {IncentivesVault} from "@contracts/aave-v3/IncentivesVault.sol";
import {MatchingEngine} from "@contracts/aave-v3/MatchingEngine.sol";
import {EntryManager} from "@contracts/aave-v3/EntryManager.sol";
import {ExitManager} from "@contracts/aave-v3/ExitManager.sol";
import {Lens} from "@contracts/aave-v3/Lens.sol";
import "@contracts/aave-v3/Morpho.sol";

import "../../common/helpers/MorphoToken.sol";
import "../helpers/SimplePriceOracle.sol";
import {DumbOracle} from "../helpers/DumbOracle.sol";
import "../../common/helpers/Chains.sol";
import {User} from "../helpers/User.sol";
import {Utils} from "./Utils.sol";
import "forge-std/stdlib.sol";
import "hardhat/console.sol";
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
    IEntryManager public entryManager;
    IExitManager public exitManager;
    Lens public lens;
    MorphoToken public morphoToken;
    // TODO: Implement rewards
    // address public REWARD_TOKEN =
    //     IAaveIncentivesController(aaveIncentivesControllerAddress).REWARD_TOKEN();

    IncentivesVault public incentivesVault;
    DumbOracle internal dumbOracle;
    IPoolAddressesProvider public poolAddressesProvider;
    IPoolDataProvider public protocolDataProvider;
    IPriceOracleGetter public oracle;
    IPool public pool;

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

        poolAddressesProvider = IPoolAddressesProvider(poolAddressesProviderAddress);
        pool = IPool(poolAddressesProvider.getPool());
        entryManager = new EntryManager();
        exitManager = new ExitManager();

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
            IPoolAddressesProvider(poolAddressesProviderAddress),
            defaultMaxGasForMatching,
            20
        );

        lens = new Lens(address(morpho), poolAddressesProvider);
        treasuryVault = new User(morpho);
        morpho.setTreasuryVault(address(treasuryVault));

        // TODO:
        // if (block.chainid == Chains.ETH_MAINNET) {
        //     // Mainnet network
        //     rewardsManager = new RewardsManagerOnMainnetAndAvalanche(
        //         pool,
        //         IMorpho(address(morpho))
        //     );
        // } else if (block.chainid == Chains.AVALANCHE_MAINNET) {
        //     // Avalanche network
        //     rewardsManager = new RewardsManagerOnMainnetAndAvalanche(
        //         pool,
        //         IMorpho(address(morpho))
        //     );
        // } else if (block.chainid == Chains.POLYGON_MAINNET) {
        //     // Polygon network
        //     rewardsManager = new RewardsManagerOnPolygon(pool, IMorpho(address(morpho)));
        // }

        // rewardsManager.setAaveIncentivesController(aaveIncentivesControllerAddress);
        // morpho.setAaveIncentivesController(aaveIncentivesControllerAddress);

        /// Create markets ///

        createMarket(aDai);
        createMarket(aUsdc);
        createMarket(aWbtc);
        createMarket(aUsdt);
        createMarket(aAave);

        hevm.warp(block.timestamp + 100);

        /// Create Morpho token, deploy Incentives Vault and activate rewards ///

        // morphoToken = new MorphoToken(address(this));
        // dumbOracle = new DumbOracle();
        // incentivesVault = new IncentivesVault(
        //     IMorpho(address(morpho)),
        //     morphoToken,
        //     ERC20(IAaveIncentivesController(aaveIncentivesControllerAddress).REWARD_TOKEN()),
        //     address(1),
        //     dumbOracle
        // );
        // morphoToken.transfer(address(incentivesVault), 1_000_000 ether);

        oracle = IPriceOracleGetter(poolAddressesProvider.getPriceOracle());
        protocolDataProvider = IPoolDataProvider(poolDataProviderAddress);

        // TODO:
        // morpho.setRewardsManager(rewardsManager);
        // morpho.setIncentivesVault(incentivesVault);
    }

    function createMarket(address _aToken) internal {
        address underlying = IAToken(_aToken).UNDERLYING_ASSET_ADDRESS();
        Types.MarketParameters memory marketParams = Types.MarketParameters(0, 3_333);
        morpho.createMarket(underlying, marketParams);

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
        hevm.label(address(morphoToken), "MorphoToken");
        // TODO: hevm.label(aaveIncentivesControllerAddress, "AaveIncentivesController");
        hevm.label(address(poolAddressesProvider), "LendingPoolAddressesProvider");
        hevm.label(address(pool), "LendingPool");
        hevm.label(address(protocolDataProvider), "ProtocolDataProvider");
        hevm.label(address(oracle), "AaveOracle");
        hevm.label(address(treasuryVault), "TreasuryVault");
        hevm.label(address(interestRatesManager), "InterestRatesManager");
        // TODO: hevm.label(address(incentivesVault), "IncentivesVault");
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
            address(poolAddressesProvider),
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
        DataTypes.ReserveData memory reserveData = pool.getReserveData(
            IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS()
        );

        uint256 poolSupplyAPR = reserveData.currentLiquidityRate;
        uint256 poolBorrowAPR = reserveData.currentVariableBorrowRate;
        (uint16 reserveFactor, uint256 p2pIndexCursor) = morpho.marketParameters(_poolTokenAddress);

        // rate = (1 - p2pIndexCursor) * poolSupplyRate + p2pIndexCursor * poolBorrowRate.
        uint256 rate = ((10_000 - p2pIndexCursor) *
            poolSupplyAPR +
            p2pIndexCursor *
            poolBorrowAPR) / 10_000;

        p2pSupplyRate_ = rate - (reserveFactor * (rate - poolSupplyAPR)) / 10_000;
        p2pBorrowRate_ = rate + (reserveFactor * (poolBorrowAPR - rate)) / 10_000;
    }
}
