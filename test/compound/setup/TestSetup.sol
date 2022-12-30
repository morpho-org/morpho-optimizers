// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "src/compound/interfaces/IMorpho.sol";
import {IIncentivesVault} from "src/compound/interfaces/IIncentivesVault.sol";
import {IPositionsManager} from "src/compound/interfaces/IPositionsManager.sol";
import {IInterestRatesManager} from "src/compound/interfaces/IInterestRatesManager.sol";

import "@openzeppelin/contracts/utils/Strings.sol";
import "src/compound/libraries/CompoundMath.sol";
import "solmate/src/utils/SafeTransferLib.sol";

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {RewardsManager} from "src/compound/RewardsManager.sol";
import {Lens} from "src/compound/lens/Lens.sol";
import {Morpho} from "src/compound/Morpho.sol";
import {IncentivesVault} from "src/compound/IncentivesVault.sol";
import {PositionsManager} from "src/compound/PositionsManager.sol";
import {InterestRatesManager} from "src/compound/InterestRatesManager.sol";

import {MorphoToken} from "test/common/helpers/MorphoToken.sol";
import {SimplePriceOracle} from "test/compound/helpers/SimplePriceOracle.sol";
import {DumbOracle} from "test/compound/helpers/DumbOracle.sol";
import {User} from "test/compound/helpers/User.sol";
import {Utils} from "test/compound/setup/Utils.sol";
import {Config} from "config/compound/Config.sol";
import {console} from "forge-std/console.sol";

contract TestSetup is Config, Utils {
    uint256 internal constant MAX_BASIS_POINTS = 100_00;
    uint256 internal constant INITIAL_BALANCE = 1_000_000;

    ProxyAdmin internal proxyAdmin;

    Morpho internal morpho;
    Morpho internal morphoImplV1;
    TransparentUpgradeableProxy internal morphoProxy;

    IPositionsManager internal positionsManager;
    IIncentivesVault internal incentivesVault;
    IInterestRatesManager internal interestRatesManager;

    RewardsManager internal rewardsManager;
    RewardsManager internal rewardsManagerImplV1;
    TransparentUpgradeableProxy internal rewardsManagerProxy;

    Lens internal lens;
    Lens internal lensImplV1;
    TransparentUpgradeableProxy internal lensProxy;

    DumbOracle internal dumbOracle;
    MorphoToken internal morphoToken;

    User internal treasuryVault;

    User internal supplier1;
    User internal supplier2;
    User internal supplier3;
    User[] internal suppliers;

    User internal borrower1;
    User internal borrower2;
    User internal borrower3;
    User[] internal borrowers;

    address[] internal pools;

    function setUp() public {
        initContracts();
        setContractsLabels();
        initUsers();

        onSetUp();
    }

    function onSetUp() internal virtual {}

    function initContracts() internal {
        interestRatesManager = new InterestRatesManager();
        positionsManager = new PositionsManager();

        /// Deploy proxies ///

        proxyAdmin = new ProxyAdmin();

        morphoImplV1 = new Morpho();
        morphoProxy = new TransparentUpgradeableProxy(address(morphoImplV1), address(this), "");

        morphoProxy.changeAdmin(address(proxyAdmin));
        morpho = Morpho(payable(address(morphoProxy)));
        morpho.initialize(
            positionsManager,
            interestRatesManager,
            comptroller,
            Types.MaxGasForMatching({supply: 3e6, borrow: 3e6, withdraw: 3e6, repay: 3e6}),
            1,
            20,
            cEth,
            wEth
        );

        treasuryVault = new User(morpho);

        morpho.setTreasuryVault(address(treasuryVault));

        /// Create markets ///

        createMarket(cDai);
        createMarket(cUsdc);
        createMarket(cWbtc2);
        createMarket(cUsdt);
        createMarket(cBat);
        createMarket(cEth);

        vm.roll(block.number + 1);

        ///  Create Morpho token, deploy Incentives Vault and activate COMP rewards ///

        morphoToken = new MorphoToken(address(this));
        dumbOracle = new DumbOracle();
        incentivesVault = new IncentivesVault(
            comptroller,
            IMorpho(address(morpho)),
            morphoToken,
            address(treasuryVault),
            dumbOracle
        );
        morphoToken.transfer(address(incentivesVault), 1_000_000 ether);
        morpho.setIncentivesVault(incentivesVault);

        rewardsManagerImplV1 = new RewardsManager();
        rewardsManagerProxy = new TransparentUpgradeableProxy(
            address(rewardsManagerImplV1),
            address(proxyAdmin),
            ""
        );
        rewardsManager = RewardsManager(address(rewardsManagerProxy));
        rewardsManager.initialize(address(morpho));

        morpho.setRewardsManager(rewardsManager);

        lensImplV1 = new Lens(address(morpho));
        lensProxy = new TransparentUpgradeableProxy(address(lensImplV1), address(proxyAdmin), "");
        lens = Lens(address(lensProxy));
    }

    function createMarket(address _cToken) internal {
        Types.MarketParameters memory marketParams = Types.MarketParameters(0, 3_333);
        morpho.createMarket(_cToken, marketParams);

        // All tokens must also be added to the pools array, for the correct behavior of TestLiquidate::createAndSetCustomPriceOracle.
        pools.push(_cToken);

        vm.label(_cToken, ERC20(_cToken).symbol());
        if (_cToken == cEth) vm.label(wEth, "WETH");
        else {
            address underlying = ICToken(_cToken).underlying();
            vm.label(underlying, ERC20(underlying).symbol());
        }
    }

    function initUsers() internal {
        for (uint256 i = 0; i < 3; i++) {
            suppliers.push(new User(morpho));
            vm.label(
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
            vm.label(
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
        deal(wEth, address(_user), INITIAL_BALANCE * WAD);
        deal(bat, address(_user), INITIAL_BALANCE * WAD);
        deal(usdt, address(_user), INITIAL_BALANCE * 1e6);
        deal(usdc, address(_user), INITIAL_BALANCE * 1e6);
    }

    function setContractsLabels() internal {
        vm.label(address(proxyAdmin), "ProxyAdmin");
        vm.label(address(morphoImplV1), "MorphoImplV1");
        vm.label(address(morpho), "Morpho");
        vm.label(address(interestRatesManager), "InterestRatesManager");
        vm.label(address(rewardsManager), "RewardsManager");
        vm.label(address(morphoToken), "MorphoToken");
        vm.label(address(comptroller), "Comptroller");
        vm.label(address(oracle), "CompoundOracle");
        vm.label(address(dumbOracle), "DumbOracle");
        vm.label(address(incentivesVault), "IncentivesVault");
        vm.label(address(treasuryVault), "TreasuryVault");
        vm.label(address(lens), "Lens");
    }

    function createSigners(uint256 _nbOfSigners) internal {
        while (borrowers.length < _nbOfSigners) {
            borrowers.push(new User(morpho));
            fillUserBalances(borrowers[borrowers.length - 1]);
            suppliers.push(new User(morpho));
            fillUserBalances(suppliers[suppliers.length - 1]);
        }
    }

    function createAndSetCustomPriceOracle() internal returns (SimplePriceOracle) {
        SimplePriceOracle customOracle = new SimplePriceOracle();

        IComptroller adminComptroller = IComptroller(address(comptroller));
        vm.prank(adminComptroller.admin());
        uint256 result = adminComptroller._setPriceOracle(address(customOracle));
        require(result == 0); // No error

        for (uint256 i = 0; i < pools.length; i++) {
            customOracle.setUnderlyingPrice(pools[i], oracle.getUnderlyingPrice(pools[i]));
        }
        return customOracle;
    }

    function setDefaultMaxGasForMatchingHelper(
        uint64 _supply,
        uint64 _borrow,
        uint64 _withdraw,
        uint64 _repay
    ) internal {
        Types.MaxGasForMatching memory newMaxGas = Types.MaxGasForMatching({
            supply: _supply,
            borrow: _borrow,
            withdraw: _withdraw,
            repay: _repay
        });
        morpho.setDefaultMaxGasForMatching(newMaxGas);
    }

    function moveOneBlockForwardBorrowRepay() internal {
        vm.roll(block.number + 1);
    }

    function move1000BlocksForward(address _marketAddress) internal {
        for (uint256 k; k < 100; k++) {
            vm.roll(block.number + 10);
            vm.warp(block.timestamp + 1);
            morpho.updateP2PIndexes(_marketAddress);
        }
    }

    /// @notice Computes and returns peer-to-peer rates for a specific market (without taking into account deltas !).
    /// @param _poolToken The market address.
    /// @return p2pSupplyRate_ The market's supply rate in peer-to-peer (in wad).
    /// @return p2pBorrowRate_ The market's borrow rate in peer-to-peer (in wad).
    function getApproxP2PRates(address _poolToken)
        internal
        view
        returns (uint256 p2pSupplyRate_, uint256 p2pBorrowRate_)
    {
        ICToken cToken = ICToken(_poolToken);

        uint256 poolSupplyBPY = cToken.supplyRatePerBlock();
        uint256 poolBorrowBPY = cToken.borrowRatePerBlock();
        (uint256 reserveFactor, uint256 p2pIndexCursor) = morpho.marketParameters(_poolToken);

        // rate = 2/3 * poolSupplyRate + 1/3 * poolBorrowRate.
        uint256 rate = ((10_000 - p2pIndexCursor) *
            poolSupplyBPY +
            p2pIndexCursor *
            poolBorrowBPY) / 10_000;

        p2pSupplyRate_ = rate - (reserveFactor * (rate - poolSupplyBPY)) / 10_000;
        p2pBorrowRate_ = rate + (reserveFactor * (poolBorrowBPY - rate)) / 10_000;
    }
}
