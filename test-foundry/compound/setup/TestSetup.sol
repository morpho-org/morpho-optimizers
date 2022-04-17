// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "hardhat/console.sol";

import "@contracts/compound/interfaces/IRewardsManagerForCompound.sol";
import "@contracts/compound/interfaces/compound/ICompound.sol";
import "@contracts/common/interfaces/ISwapManager.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "@contracts/compound/PositionsManagerForCompound.sol";
import "@contracts/compound/MarketsManagerForCompound.sol";
import "@contracts/compound/MatchingEngineForCompound.sol";
import "@contracts/compound/RewardsManagerForCompound.sol";
import "@contracts/compound/InterestRatesV1.sol";
import "@contracts/compound/libraries/FixedPointMathLib.sol";

import "../../common/helpers/MorphoToken.sol";
import "../../common/helpers/Chains.sol";
import "../helpers/SimplePriceOracle.sol";
import "../helpers/IncentivesVault.sol";
import "../helpers/DumbOracle.sol";
import {User} from "../helpers/User.sol";
import {Utils} from "./Utils.sol";
import "forge-std/stdlib.sol";
import "@config/Config.sol";

interface IAdminComptroller {
    function _setPriceOracle(SimplePriceOracle newOracle) external returns (uint256);

    function admin() external view returns (address);
}

contract TestSetup is Config, Utils, stdCheats {
    Vm public hevm = Vm(HEVM_ADDRESS);

    uint256 public constant MAX_BASIS_POINTS = 10_000;
    uint256 public constant INITIAL_BALANCE = 1_000_000;

    ProxyAdmin public proxyAdmin;
    TransparentUpgradeableProxy public positionsManagerProxy;
    TransparentUpgradeableProxy public marketsManagerProxy;
    MatchingEngineForCompound internal matchingEngine;
    PositionsManagerForCompound internal positionsManagerImplV1;
    PositionsManagerForCompound internal positionsManager;
    PositionsManagerForCompound internal fakePositionsManagerImpl;
    MarketsManagerForCompound internal marketsManager;
    MarketsManagerForCompound internal marketsManagerImplV1;
    IRewardsManagerForCompound internal rewardsManager;
    IInterestRates internal interestRates;

    IncentivesVault public incentivesVault;
    DumbOracle internal dumbOracle;
    MorphoToken public morphoToken;
    IComptroller public comptroller;
    ICompoundOracle public oracle;

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
        PositionsManagerForCompound.MaxGas memory maxGas = PositionsManagerForCompoundStorage
        .MaxGas({supply: 3e6, borrow: 3e6, withdraw: 3e6, repay: 3e6});

        comptroller = IComptroller(comptrollerAddress);
        matchingEngine = new MatchingEngineForCompound();
        interestRates = new InterestRatesV1();

        /// Deploy proxies ///

        proxyAdmin = new ProxyAdmin();
        marketsManagerImplV1 = new MarketsManagerForCompound();
        marketsManagerProxy = new TransparentUpgradeableProxy(
            address(marketsManagerImplV1),
            address(this),
            ""
        );

        marketsManagerProxy.changeAdmin(address(proxyAdmin));
        marketsManager = MarketsManagerForCompound(address(marketsManagerProxy));
        marketsManager.initialize(comptroller, interestRates);
        positionsManagerImplV1 = new PositionsManagerForCompound();
        positionsManagerProxy = new TransparentUpgradeableProxy(
            address(positionsManagerImplV1),
            address(this),
            ""
        );

        positionsManagerProxy.changeAdmin(address(proxyAdmin));
        positionsManager = PositionsManagerForCompound(address(positionsManagerProxy));
        positionsManager.initialize(marketsManager, matchingEngine, comptroller, maxGas, 20);

        treasuryVault = new User(positionsManager);
        fakePositionsManagerImpl = new PositionsManagerForCompound();
        oracle = ICompoundOracle(comptroller.oracle());
        marketsManager.setPositionsManager(address(positionsManager));
        positionsManager.setTreasuryVault(address(treasuryVault));

        /// Create markets ///

        createMarket(cDai);
        createMarket(cUsdc);
        createMarket(cWbtc);
        createMarket(cUsdt);
        createMarket(cBat);
        hevm.roll(block.number + 1);

        ///  Create Morpho token, deploy Incentives Vault and activate COMP rewards ///

        morphoToken = new MorphoToken(address(this));
        dumbOracle = new DumbOracle();
        incentivesVault = new IncentivesVault(
            address(positionsManager),
            address(morphoToken),
            address(dumbOracle)
        );
        morphoToken.transfer(address(incentivesVault), 1_000_000 ether);

        rewardsManager = new RewardsManagerForCompound(address(positionsManager), comptroller);

        positionsManager.setRewardsManager(address(rewardsManager));
        positionsManager.setIncentivesVault(address(incentivesVault));
        positionsManager.setCompRewardsActive();
    }

    function createMarket(address _cToken) internal {
        marketsManager.createMarket(_cToken);

        // All tokens must also be added to the pools array, for the correct behavior of TestLiquidate::createAndSetCustomPriceOracle.
        pools.push(_cToken);

        hevm.label(_cToken, ERC20(_cToken).symbol());
        address underlying = ICToken(_cToken).underlying();
        hevm.label(underlying, ERC20(underlying).symbol());
    }

    function initUsers() internal {
        for (uint256 i = 0; i < 3; i++) {
            suppliers.push(new User(positionsManager));
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
            borrowers.push(new User(positionsManager));
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
        tip(usdc, address(_user), INITIAL_BALANCE * 1e6);
    }

    function setContractsLabels() internal {
        hevm.label(address(proxyAdmin), "ProxyAdmin");
        hevm.label(address(positionsManagerImplV1), "PositionsManagerImplV1");
        hevm.label(address(positionsManager), "PositionsManager");
        hevm.label(address(marketsManagerImplV1), "MarketsManagerImplV1");
        hevm.label(address(marketsManager), "MarketsManager");
        hevm.label(address(rewardsManager), "RewardsManager");
        hevm.label(address(matchingEngine), "MatchingEngine");
        hevm.label(address(morphoToken), "MorphoToken");
        hevm.label(address(comptroller), "Comptroller");
        hevm.label(address(oracle), "CompoundOracle");
        hevm.label(address(dumbOracle), "DumbOracle");
        hevm.label(address(incentivesVault), "IncentivesVault");
        hevm.label(address(treasuryVault), "TreasuryVault");
    }

    function createSigners(uint8 _nbOfSigners) internal {
        while (borrowers.length < _nbOfSigners) {
            borrowers.push(new User(positionsManager));
            fillUserBalances(borrowers[borrowers.length - 1]);
            suppliers.push(new User(positionsManager));
            fillUserBalances(suppliers[suppliers.length - 1]);
        }
    }

    function createAndSetCustomPriceOracle() public returns (SimplePriceOracle) {
        SimplePriceOracle customOracle = new SimplePriceOracle();

        IAdminComptroller adminComptroller = IAdminComptroller(address(comptroller));
        hevm.prank(adminComptroller.admin());
        uint256 result = adminComptroller._setPriceOracle(customOracle);
        require(result == 0); // No error

        for (uint256 i = 0; i < pools.length; i++) {
            customOracle.setUnderlyingPrice(pools[i], oracle.getUnderlyingPrice(pools[i]));
        }
        return customOracle;
    }

    function setMaxGasHelper(
        uint64 _supply,
        uint64 _borrow,
        uint64 _withdraw,
        uint64 _repay
    ) public {

            PositionsManagerForCompoundStorage.MaxGas memory newMaxGas
         = PositionsManagerForCompoundStorage.MaxGas({
            supply: _supply,
            borrow: _borrow,
            withdraw: _withdraw,
            repay: _repay
        });
        positionsManager.setMaxGas(newMaxGas);
    }
}
