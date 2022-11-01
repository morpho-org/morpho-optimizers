// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "@contracts/aave-v2/interfaces/aave/IAaveIncentivesController.sol";
import "@contracts/aave-v2/interfaces/aave/IVariableDebtToken.sol";
import "@contracts/aave-v2/interfaces/aave/IAToken.sol";
import "@contracts/aave-v2/interfaces/IMorpho.sol";

import {ReserveConfiguration} from "@contracts/aave-v2/libraries/aave/ReserveConfiguration.sol";
import "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import "@morpho-dao/morpho-utils/math/WadRayMath.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@contracts/aave-v2/libraries/Types.sol";

import {RewardsManagerOnMainnetAndAvalanche} from "@contracts/aave-v2/rewards-managers/RewardsManagerOnMainnetAndAvalanche.sol";
import {RewardsManagerOnPolygon} from "@contracts/aave-v2/rewards-managers/RewardsManagerOnPolygon.sol";
import {InterestRatesManager} from "@contracts/aave-v2/InterestRatesManager.sol";
import {IncentivesVault} from "@contracts/aave-v2/IncentivesVault.sol";
import {MatchingEngine} from "@contracts/aave-v2/MatchingEngine.sol";
import {EntryPositionsManager} from "@contracts/aave-v2/EntryPositionsManager.sol";
import {ExitPositionsManager} from "@contracts/aave-v2/ExitPositionsManager.sol";
import "@contracts/aave-v2/Morpho.sol";

import "../../common/helpers/MorphoToken.sol";
import "../helpers/SimplePriceOracle.sol";
import {DumbOracle} from "../helpers/DumbOracle.sol";
import {User} from "../helpers/User.sol";
import {Utils} from "./Utils.sol";
import "@config/Config.sol";
import "@forge-std/Test.sol";
import "@forge-std/console.sol";

contract TestSetup is Config, Utils {
    Vm public hevm = Vm(HEVM_ADDRESS);

    uint256 public constant INITIAL_BALANCE = 1_000_000;

    DumbOracle internal dumbOracle;
    MorphoToken public morphoToken;

    User public treasuryVault;

    User public supplier1;
    User public supplier2;
    User public supplier3;
    User[] public suppliers;

    User public borrower1;
    User public borrower2;
    User public borrower3;
    User[] public borrowers;

    address[] public pools;

    function setUp() public {
        initContracts();
        setContractsLabels();
        initUsers();

        onSetUp();
    }

    function onSetUp() public virtual {}

    function initContracts() internal {
        interestRatesManager = new InterestRatesManager();
        entryPositionsManager = new EntryPositionsManager();
        exitPositionsManager = new ExitPositionsManager();

        /// Deploy proxies ///

        proxyAdmin = new ProxyAdmin();

        morphoImplV1 = new Morpho();
        morphoProxy = new TransparentUpgradeableProxy(
            address(morphoImplV1),
            address(proxyAdmin),
            ""
        );
        morpho = Morpho(payable(address(morphoProxy)));
        morpho.initialize(
            entryPositionsManager,
            exitPositionsManager,
            interestRatesManager,
            poolAddressesProvider,
            Types.MaxGasForMatching({supply: 3e6, borrow: 3e6, withdraw: 3e6, repay: 3e6}),
            20
        );

        treasuryVault = new User(morpho);
        morpho.setTreasuryVault(address(treasuryVault));
        morpho.setAaveIncentivesController(address(aaveIncentivesController));

        rewardsManagerImplV1 = new RewardsManagerOnMainnetAndAvalanche();
        rewardsManagerProxy = new TransparentUpgradeableProxy(
            address(rewardsManagerImplV1),
            address(proxyAdmin),
            ""
        );
        rewardsManager = IRewardsManager(address(rewardsManagerProxy));
        rewardsManager.initialize(address(morpho));

        /// Create markets ///

        createMarket(aDai);
        createMarket(aUsdc);
        createMarket(aWbtc);
        createMarket(aUsdt);
        createMarket(aAave);

        hevm.warp(block.timestamp + 100);

        /// Create Morpho token, deploy Incentives Vault and activate rewards ///

        morphoToken = new MorphoToken(address(this));
        dumbOracle = new DumbOracle();
        incentivesVault = new IncentivesVault(
            IMorpho(address(morpho)),
            morphoToken,
            ERC20(REWARD_TOKEN),
            address(treasuryVault),
            dumbOracle
        );
        morphoToken.transfer(address(incentivesVault), 1_000_000 ether);
        morpho.setIncentivesVault(incentivesVault);

        morpho.setRewardsManager(rewardsManager);

        lensImplV1 = new Lens(address(morpho));
        lensProxy = new TransparentUpgradeableProxy(address(lensImplV1), address(proxyAdmin), "");
        lens = Lens(address(lensProxy));
    }

    function createMarket(address _aToken) internal {
        address underlying = IAToken(_aToken).UNDERLYING_ASSET_ADDRESS();
        morpho.createMarket(underlying, 0, 3_333);

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
        deal(dai, address(_user), INITIAL_BALANCE * WAD);
        deal(aave, address(_user), INITIAL_BALANCE * WAD);
        deal(wEth, address(_user), INITIAL_BALANCE * WAD);
        deal(usdt, address(_user), INITIAL_BALANCE * 1e6);
        deal(usdc, address(_user), INITIAL_BALANCE * 1e6);
        deal(wbtc, address(_user), INITIAL_BALANCE * 1e8);
    }

    function setContractsLabels() internal {
        hevm.label(address(morpho), "Morpho");
        hevm.label(address(rewardsManager), "RewardsManager");
        hevm.label(address(morphoToken), "MorphoToken");
        hevm.label(address(aaveIncentivesController), "AaveIncentivesController");
        hevm.label(address(poolAddressesProvider), "PoolAddressesProvider");
        hevm.label(address(pool), "Pool");
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

    function _setDefaultMaxGasForMatching(
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
    /// @param _poolToken The market address.
    /// @return p2pSupplyRate_ The market's supply rate in peer-to-peer (in ray).
    /// @return p2pBorrowRate_ The market's borrow rate in peer-to-peer (in ray).
    function getApproxP2PRates(address _poolToken)
        public
        view
        returns (uint256 p2pSupplyRate_, uint256 p2pBorrowRate_)
    {
        DataTypes.ReserveData memory reserveData = pool.getReserveData(
            IAToken(_poolToken).UNDERLYING_ASSET_ADDRESS()
        );

        uint256 poolSupplyAPR = reserveData.currentLiquidityRate;
        uint256 poolBorrowAPR = reserveData.currentVariableBorrowRate;
        (, uint16 reserveFactor, uint256 p2pIndexCursor, , , , ) = morpho.market(_poolToken);

        // rate = (1 - p2pIndexCursor) * poolSupplyRate + p2pIndexCursor * poolBorrowRate.
        uint256 rate = ((10_000 - p2pIndexCursor) *
            poolSupplyAPR +
            p2pIndexCursor *
            poolBorrowAPR) / 10_000;

        p2pSupplyRate_ = rate - (reserveFactor * (rate - poolSupplyAPR)) / 10_000;
        p2pBorrowRate_ = rate + (reserveFactor * (poolBorrowAPR - rate)) / 10_000;
    }
}
