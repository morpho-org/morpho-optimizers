// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "@contracts/compound/interfaces/compound/ICompound.sol";
import "@contracts/compound/interfaces/IRewardsManager.sol";
import "@contracts/common/interfaces/ISwapManager.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "@contracts/compound/IncentivesVault.sol";
import "@contracts/compound/RewardsManager.sol";
import "@contracts/compound/PositionsManager.sol";
import "@contracts/compound/MatchingEngine.sol";
import "@contracts/compound/InterestRatesManager.sol";
import "@contracts/compound/Morpho.sol";
import "@contracts/compound/lens/Lens.sol";

import "../../common/helpers/MorphoToken.sol";
import "../../common/helpers/Chains.sol";
import "../helpers/SimplePriceOracle.sol";
import "../helpers/DumbOracle.sol";
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
    Morpho internal morphoImplV1;
    Morpho internal morpho;
    InterestRatesManager internal interestRatesManager;
    TransparentUpgradeableProxy internal rewardsManagerProxy;
    IRewardsManager internal rewardsManagerImplV1;
    IRewardsManager internal rewardsManager;
    IPositionsManager internal positionsManager;
    Lens internal lensImplV1;
    Lens internal lens;
    TransparentUpgradeableProxy internal lensProxy;

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
        Types.MaxGasForMatching memory defaultMaxGasForMatching = Types.MaxGasForMatching({
            supply: 3e6,
            borrow: 3e6,
            withdraw: 3e6,
            repay: 3e6
        });

        comptroller = IComptroller(comptrollerAddress);
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
            defaultMaxGasForMatching,
            1,
            20,
            cEth,
            wEth
        );

        treasuryVault = new User(morpho);

        oracle = ICompoundOracle(comptroller.oracle());
        morpho.setTreasuryVault(address(treasuryVault));

        /// Create markets ///

        createMarket(cDai);
        createMarket(cUsdc);
        createMarket(cWbtc);
        createMarket(cUsdt);
        createMarket(cBat);
        createMarket(cEth);

        hevm.roll(block.number + 1);

        ///  Create Morpho token, deploy Incentives Vault and activate COMP rewards ///

        morphoToken = new MorphoToken(address(this));
        dumbOracle = new DumbOracle();
        incentivesVault = new IncentivesVault(
            IComptroller(comptrollerAddress),
            IMorpho(address(morpho)),
            morphoToken,
            address(1),
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

        lensImplV1 = new Lens();
        lensProxy = new TransparentUpgradeableProxy(address(lensImplV1), address(proxyAdmin), "");
        lens = Lens(address(lensProxy));
        lens.initialize(address(morpho));
    }

    function createMarket(address _cToken) internal {
        Types.MarketParameters memory marketParams = Types.MarketParameters(0, 3_333);
        morpho.createMarket(_cToken, marketParams);

        // All tokens must also be added to the pools array, for the correct behavior of TestLiquidate::createAndSetCustomPriceOracle.
        pools.push(_cToken);

        hevm.label(_cToken, ERC20(_cToken).symbol());
        if (_cToken == cEth) hevm.label(wEth, "WETH");
        else {
            address underlying = ICToken(_cToken).underlying();
            hevm.label(underlying, ERC20(underlying).symbol());
        }
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
        tip(wEth, address(_user), INITIAL_BALANCE * WAD);
        tip(usdt, address(_user), INITIAL_BALANCE * 1e6);
        tip(usdc, address(_user), INITIAL_BALANCE * 1e6);
    }

    function setContractsLabels() internal {
        hevm.label(address(proxyAdmin), "ProxyAdmin");
        hevm.label(address(morphoImplV1), "MorphoImplV1");
        hevm.label(address(morpho), "Morpho");
        hevm.label(address(interestRatesManager), "InterestRatesManager");
        hevm.label(address(rewardsManager), "RewardsManager");
        hevm.label(address(morphoToken), "MorphoToken");
        hevm.label(address(comptroller), "Comptroller");
        hevm.label(address(oracle), "CompoundOracle");
        hevm.label(address(dumbOracle), "DumbOracle");
        hevm.label(address(incentivesVault), "IncentivesVault");
        hevm.label(address(treasuryVault), "TreasuryVault");
        hevm.label(address(lens), "Lens");
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

        IComptroller adminComptroller = IComptroller(address(comptroller));
        hevm.prank(adminComptroller.admin());
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
    ) public {
        Types.MaxGasForMatching memory newMaxGas = Types.MaxGasForMatching({
            supply: _supply,
            borrow: _borrow,
            withdraw: _withdraw,
            repay: _repay
        });
        morpho.setDefaultMaxGasForMatching(newMaxGas);
    }

    function moveOneBlockForwardBorrowRepay() public {
        hevm.roll(block.number + 1);
    }

    function move1000BlocksForward(address _marketAddress) public {
        for (uint256 k; k < 100; k++) {
            hevm.roll(block.number + 10);
            hevm.warp(block.timestamp + 1);
            morpho.updateP2PIndexes(_marketAddress);
        }
    }

    /// @notice Computes and returns peer-to-peer rates for a specific market (without taking into account deltas !).
    /// @param _poolTokenAddress The market address.
    /// @return p2pSupplyRate_ The market's supply rate in peer-to-peer (in wad).
    /// @return p2pBorrowRate_ The market's borrow rate in peer-to-peer (in wad).
    function getApproxP2PRates(address _poolTokenAddress)
        public
        view
        returns (uint256 p2pSupplyRate_, uint256 p2pBorrowRate_)
    {
        ICToken cToken = ICToken(_poolTokenAddress);

        uint256 poolSupplyBPY = cToken.supplyRatePerBlock();
        uint256 poolBorrowBPY = cToken.borrowRatePerBlock();
        (uint256 reserveFactor, uint256 p2pIndexCursor) = morpho.marketParameters(
            _poolTokenAddress
        );

        // rate = 2/3 * poolSupplyRate + 1/3 * poolBorrowRate.
        uint256 rate = ((10_000 - p2pIndexCursor) *
            poolSupplyBPY +
            p2pIndexCursor *
            poolBorrowBPY) / 10_000;

        p2pSupplyRate_ = rate - (reserveFactor * (rate - poolSupplyBPY)) / 10_000;
        p2pBorrowRate_ = rate + (reserveFactor * (poolBorrowBPY - rate)) / 10_000;
    }
}
