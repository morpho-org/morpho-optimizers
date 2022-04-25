// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "hardhat/console.sol";

import "@contracts/compound/interfaces/IRewardsManager.sol";
import "@contracts/compound/interfaces/compound/ICompound.sol";
import "@contracts/common/interfaces/ISwapManager.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "@contracts/compound/PositionsManager.sol";
import "@contracts/compound/MarketsManager.sol";
import "@contracts/compound/MatchingEngine.sol";
import "@contracts/compound/RewardsManager.sol";
import "@contracts/compound/InterestRatesV1.sol";
import "@contracts/compound/Logic.sol";
import "@contracts/compound/libraries/FixedPointMathLib.sol";

import "../../common/helpers/MorphoToken.sol";
import "../../common/helpers/Chains.sol";
import "../../compound/helpers/SimplePriceOracle.sol";
import "../../compound/helpers/IncentivesVault.sol";
import "../../compound/helpers/DumbOracle.sol";
import {User} from "../../compound/helpers/User.sol";
import {Utils} from "../../compound/setup/Utils.sol";
import "forge-std/stdlib.sol";
import "@config/Config.sol";

interface IAdminComptroller {
    function _setPriceOracle(SimplePriceOracle newOracle) external returns (uint256);

    function admin() external view returns (address);
}

contract TestSetupFuzzing is Config, Utils, stdCheats {
    Vm public hevm = Vm(HEVM_ADDRESS);

    uint256 public constant MAX_BASIS_POINTS = 10_000;
    uint256 public constant INITIAL_BALANCE = 15_000_000_000;

    ProxyAdmin public proxyAdmin;
    TransparentUpgradeableProxy public positionsManagerProxy;
    TransparentUpgradeableProxy public marketsManagerProxy;
    PositionsManager internal positionsManagerImplV1;
    PositionsManager internal positionsManager;
    PositionsManager internal fakePositionsManagerImpl;
    MarketsManager internal marketsManager;
    MarketsManager internal marketsManagerImplV1;
    IRewardsManager internal rewardsManager;
    IInterestRates internal interestRates;
    ILogic internal logic;

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
        PositionsManager.MaxGas memory maxGas = PositionsManagerStorage.MaxGas({
            supply: 3e6,
            borrow: 3e6,
            withdraw: 3e6,
            repay: 3e6
        });

        comptroller = IComptroller(comptrollerAddress);
        interestRates = new InterestRatesV1();
        logic = new Logic();

        /// Deploy proxies ///

        proxyAdmin = new ProxyAdmin();
        marketsManagerImplV1 = new MarketsManager();
        marketsManagerProxy = new TransparentUpgradeableProxy(
            address(marketsManagerImplV1),
            address(this),
            ""
        );

        marketsManagerProxy.changeAdmin(address(proxyAdmin));
        marketsManager = MarketsManager(address(marketsManagerProxy));
        marketsManager.initialize(comptroller, interestRates);
        positionsManagerImplV1 = new PositionsManager();
        positionsManagerProxy = new TransparentUpgradeableProxy(
            address(positionsManagerImplV1),
            address(this),
            ""
        );

        positionsManagerProxy.changeAdmin(address(proxyAdmin));
        positionsManager = PositionsManager(payable(address(positionsManagerProxy)));
        positionsManager.initialize(marketsManager, logic, comptroller, 1, maxGas, 20, cEth, wEth);

        treasuryVault = new User(positionsManager);
        fakePositionsManagerImpl = new PositionsManager();
        oracle = ICompoundOracle(comptroller.oracle());
        marketsManager.setPositionsManager(address(positionsManager));
        positionsManager.setTreasuryVault(address(treasuryVault));

        /// Create markets ///

        createMarket(cDai);
        createMarket(cUsdc);
        createMarket(cUsdt);
        createMarket(cBat);
        createMarket(cEth);
        createMarket(cAave);
        createMarket(cTusd);
        createMarket(cUni);
        createMarket(cComp);
        createMarket(cZrx);
        createMarket(cLink);
        createMarket(cMkr);
        createMarket(cFei);
        createMarket(cYfi);
        createMarket(cUsdp);
        createMarket(cSushi);
        // createMarket(cWbtc); // Mint is paused on compound

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

        rewardsManager = new RewardsManager(address(positionsManager));

        positionsManager.setRewardsManager(address(rewardsManager));
        positionsManager.setIncentivesVault(address(incentivesVault));
        positionsManager.toggleCompRewardsActivation();
    }

    function createMarket(address _cToken) internal {
        marketsManager.createMarket(_cToken);

        // All tokens must also be added to the pools array, for the correct behavior of TestLiquidate::createAndSetCustomPriceOracle.
        pools.push(_cToken);

        hevm.label(_cToken, ERC20(_cToken).symbol());
        if (_cToken == cEth) hevm.label(wEth, "WETH");
        else {
            address underlying = ICToken(_cToken).underlying();
            if (underlying == 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2) {
                hevm.label(underlying, "mkr");
                // This is because mkr symbol is a byte32
            } else {
                hevm.label(underlying, ERC20(underlying).symbol());
            }
        }
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
        tip(aave, address(_user), INITIAL_BALANCE * 10**ERC20(aave).decimals());
        tip(dai, address(_user), INITIAL_BALANCE * 10**ERC20(dai).decimals());
        tip(usdc, address(_user), INITIAL_BALANCE * 10**ERC20(usdc).decimals());
        tip(usdt, address(_user), INITIAL_BALANCE * 10**ERC20(usdt).decimals());
        tip(wbtc, address(_user), INITIAL_BALANCE * 10**ERC20(wbtc).decimals());
        tip(wEth, address(_user), INITIAL_BALANCE * 10**ERC20(wEth).decimals());
        tip(comp, address(_user), INITIAL_BALANCE * 10**ERC20(comp).decimals());
        tip(bat, address(_user), INITIAL_BALANCE * 10**ERC20(bat).decimals());
        tip(tusd, address(_user), INITIAL_BALANCE * 10**ERC20(tusd).decimals());
        tip(uni, address(_user), INITIAL_BALANCE * 10**ERC20(uni).decimals());
        tip(zrx, address(_user), INITIAL_BALANCE * 10**ERC20(zrx).decimals());
        tip(link, address(_user), INITIAL_BALANCE * 10**ERC20(link).decimals());
        tip(mkr, address(_user), INITIAL_BALANCE * 10**ERC20(mkr).decimals());
        tip(fei, address(_user), INITIAL_BALANCE * 10**ERC20(fei).decimals());
        tip(yfi, address(_user), INITIAL_BALANCE * 10**ERC20(yfi).decimals());
        tip(usdp, address(_user), INITIAL_BALANCE * 10**ERC20(usdp).decimals());
        tip(sushi, address(_user), INITIAL_BALANCE * 10**ERC20(sushi).decimals());
    }

    function setContractsLabels() internal {
        hevm.label(address(proxyAdmin), "ProxyAdmin");
        hevm.label(address(positionsManagerImplV1), "PositionsManagerImplV1");
        hevm.label(address(positionsManager), "PositionsManager");
        hevm.label(address(marketsManagerImplV1), "MarketsManagerImplV1");
        hevm.label(address(marketsManager), "MarketsManager");
        hevm.label(address(rewardsManager), "RewardsManager");
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
        PositionsManagerStorage.MaxGas memory newMaxGas = PositionsManagerStorage.MaxGas({
            supply: _supply,
            borrow: _borrow,
            withdraw: _withdraw,
            repay: _repay
        });
        positionsManager.setMaxGas(newMaxGas);
    }

    function move1000BlocksForward(address _marketAddress) public {
        for (uint256 k; k < 100; k++) {
            hevm.roll(block.number + 10);
            hevm.warp(block.timestamp + 1);
            marketsManager.updateP2PExchangeRates(_marketAddress);
        }
    }

    /// @notice Computes and returns P2P rates for a specific market (without taking into account deltas !).
    /// @param _poolTokenAddress The market address.
    /// @return p2pSupplyRate_ The market's supply rate in P2P (in ray).
    /// @return p2pBorrowRate_ The market's borrow rate in P2P (in ray).
    function getApproxBPYs(address _poolTokenAddress)
        public
        view
        returns (uint256 p2pSupplyRate_, uint256 p2pBorrowRate_)
    {
        ICToken cToken = ICToken(_poolTokenAddress);

        uint256 poolSupplyBPY = cToken.supplyRatePerBlock();
        uint256 poolBorrowBPY = cToken.borrowRatePerBlock();
        uint256 reserveFactor = marketsManager.reserveFactor(_poolTokenAddress);

        // rate = 2/3 * poolSupplyRate + 1/3 * poolBorrowRate.
        uint256 rate = (2 * poolSupplyBPY + poolBorrowBPY) / 3;

        p2pSupplyRate_ = rate - (reserveFactor * (rate - poolSupplyBPY)) / 10_000;
        p2pBorrowRate_ = rate + (reserveFactor * (poolBorrowBPY - rate)) / 10_000;
    }

    function getUnderlying(address _poolTokenAddress) internal view returns (address) {
        if (_poolTokenAddress == cEth)
            // cETH has no underlying() function.
            return wEth;
        else return ICToken(_poolTokenAddress).underlying();
    }

    function getAsset(uint8 _asset) internal returns (address asset, address underlying) {
        asset = pools[_asset % pools.length];
        underlying = getUnderlying(asset);
    }
}
