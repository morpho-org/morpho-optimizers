// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "@contracts/compound/interfaces/compound/ICompound.sol";
import "@contracts/compound/interfaces/ICompRewardsLens.sol";
import "@contracts/compound/interfaces/IRewardsManager.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "@contracts/compound/IncentivesVault.sol";
import "@contracts/compound/RewardsManager.sol";
import "@contracts/compound/CompRewardsLens.sol";
import "@contracts/compound/PositionsManager.sol";
import "@contracts/compound/MatchingEngine.sol";
import "@contracts/compound/InterestRatesManager.sol";
import "@contracts/compound/Morpho.sol";
import "@contracts/compound/Lens.sol";

import "../../../common/helpers/MorphoToken.sol";
import "../../../compound/helpers/SimplePriceOracle.sol";
import "../../../compound/helpers/DumbOracle.sol";
import {User} from "../../../compound/helpers/User.sol";
import {Utils} from "../../../compound/setup/Utils.sol";
import "@forge-std/stdlib.sol";
import "@forge-std/console.sol";
import "@config/Config.sol";

interface IAdminComptroller {
    function _setPriceOracle(SimplePriceOracle newOracle) external returns (uint256);

    function admin() external view returns (address);
}

contract TestSetupFuzzing is Config, Utils, stdCheats {
    using CompoundMath for uint256;

    Vm public hevm = Vm(HEVM_ADDRESS);

    uint256 public constant MAX_BASIS_POINTS = 10_000;
    uint256 public constant INITIAL_BALANCE = 15_000_000_000;
    uint256 public NMAX = 20;
    address[] internal tokens = [
        dai,
        usdc,
        usdt,
        wbtc,
        wEth,
        comp,
        bat,
        tusd,
        uni,
        zrx,
        link,
        mkr,
        fei,
        yfi,
        usdp,
        sushi,
        aave
    ];

    ProxyAdmin public proxyAdmin;
    TransparentUpgradeableProxy public morphoProxy;
    Morpho internal morphoImplV1;
    Morpho internal morpho;
    InterestRatesManager internal interestRatesManager;
    TransparentUpgradeableProxy internal rewardsManagerProxy;
    IRewardsManager internal rewardsManagerImplV1;
    IRewardsManager internal rewardsManager;
    ICompRewardsLens internal compRewardsLens;
    IPositionsManager internal positionsManager;
    Lens internal lens;

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

        // make sure the wEth contract has enough ETH to unwrap any amount
        hevm.deal(wEth, type(uint128).max);

        lens = new Lens(address(morpho));

        /// Create markets ///

        createMarket(cDai);
        createMarket(cUsdc);
        createMarket(cUsdt);
        createMarket(cBat);
        createMarket(cEth);
        createMarket(cAave);
        createMarket(cTusd);
        createMarket(cUni);
        // createMarket(cComp);
        createMarket(cZrx);
        createMarket(cLink);
        createMarket(cMkr);
        // createMarket(cFei);
        createMarket(cYfi);
        createMarket(cUsdp);
        createMarket(cSushi);
        // createMarket(cWbtc2); // Mint is paused on compound

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
        compRewardsLens = new CompRewardsLens(address(morpho));

        // Tip the Morpho contract to ensure that there are no dust errors on withdraw
        deal(aave, address(morpho), 10**ERC20(aave).decimals());
        deal(dai, address(morpho), 10**ERC20(dai).decimals());
        deal(usdc, address(morpho), 10**ERC20(usdc).decimals());
        deal(usdt, address(morpho), 10**ERC20(usdt).decimals());
        deal(wbtc, address(morpho), 10**ERC20(wbtc).decimals());
        deal(wEth, address(morpho), 10**ERC20(wEth).decimals());
        deal(comp, address(morpho), 10**ERC20(comp).decimals());
        deal(bat, address(morpho), 10**ERC20(bat).decimals());
        deal(tusd, address(morpho), 10**ERC20(tusd).decimals());
        deal(uni, address(morpho), 10**ERC20(uni).decimals());
        deal(zrx, address(morpho), 10**ERC20(zrx).decimals());
        deal(link, address(morpho), 10**ERC20(link).decimals());
        deal(mkr, address(morpho), 10**ERC20(mkr).decimals());
        deal(fei, address(morpho), 10**ERC20(fei).decimals());
        deal(yfi, address(morpho), 10**ERC20(yfi).decimals());
        deal(usdp, address(morpho), 10**ERC20(usdp).decimals());
        deal(sushi, address(morpho), 10**ERC20(sushi).decimals());
    }

    function createMarket(address _cToken) internal {
        Types.MarketParameters memory defaultMarketParams = Types.MarketParameters({
            reserveFactor: 0,
            p2pIndexCursor: 5000
        });

        morpho.createMarket(_cToken, defaultMarketParams);
        morpho.setP2PIndexCursor(_cToken, 3_333);

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
        for (uint256 i; i < tokens.length; i++) {
            if (tokens[i] == wEth) {
                deal(tokens[i], address(_user), uint256(5856057446759574251267521) / 2); // wEth totalSupply() returns a weird value on pinned block
            } else {
                deal(tokens[i], address(_user), ERC20(tokens[i]).totalSupply() / 2);
            }
        }
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

        IAdminComptroller adminComptroller = IAdminComptroller(address(comptroller));
        hevm.prank(adminComptroller.admin());
        uint256 result = adminComptroller._setPriceOracle(customOracle);
        require(result == 0); // No error

        for (uint256 i = 0; i < pools.length; i++) {
            customOracle.setUnderlyingPrice(pools[i], oracle.getUnderlyingPrice(pools[i]));
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

    function move1000BlocksForward(address _marketAddress) public {
        hevm.roll(block.number + 1_000);
        hevm.warp(block.timestamp + 13 * 1_000); // mainnet block time is around 13 sec
        morpho.updateP2PIndexes(_marketAddress);
    }

    /// @notice Computes and returns peer-to-peer rates for a specific market (without taking into account deltas !).
    /// @param _poolToken The market address.
    /// @return p2pSupplyRate_ The market's supply rate in peer-to-peer (in ray).
    /// @return p2pBorrowRate_ The market's borrow rate in peer-to-peer (in ray).
    function getApproxBPYs(address _poolToken)
        public
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

    /// @notice Returns the underlying for a given market.
    /// @param _poolToken The address of the market.
    function getUnderlying(address _poolToken) internal view returns (address) {
        if (_poolToken == cEth)
            // cETH has no underlying() function.
            return wEth;
        else return ICToken(_poolToken).underlying();
    }

    function getAsset(uint8 _asset) internal view returns (address asset, address underlying) {
        asset = pools[_asset % pools.length];
        underlying = getUnderlying(asset);
    }

    /// @notice Checks morpho will not revert because of Compound rounding the amount to 0.
    /// @param underlying Address of the underlying to supply.
    /// @param amount To check.
    function assumeSupplyAmountIsCorrect(address underlying, uint256 amount) internal {
        hevm.assume(amount > 0);
        // All the signers have the same balance at the beginning of a test.
        hevm.assume(amount <= ERC20(underlying).balanceOf(address(supplier1)));
    }

    /// @notice A borrow amount can be too high on compound due to governance or unsufficient supply.
    /// @param market Address of the CToken.
    /// @param amount To check.
    function assumeBorrowAmountIsCorrect(address market, uint256 amount) internal {
        hevm.assume(amount <= ICToken(market).getCash());
        hevm.assume(amount > 0);
        uint256 borrowCap = comptroller.borrowCaps(market);
        if (borrowCap != 0) hevm.assume(amount <= borrowCap);
    }

    /// @notice Ensures the amount used for the liquidation is correct.
    /// @param amount Considered for the liquidation.
    function assumeLiquidateAmountIsCorrect(uint256 amount) internal {
        hevm.assume(amount > 0);
    }

    /// @notice Ensures the amount used for the repay is correct.
    /// @param amount Considered for the repay.
    function assumeRepayAmountIsCorrect(address underlying, uint256 amount) internal {
        hevm.assume(amount > 0);
        // All the signers have the same balance at the beginning of a test.
        hevm.assume(amount <= ERC20(underlying).balanceOf(address(supplier1)));
    }

    /// @notice Make sure the amount used for the withdraw is correct.
    /// @param market Address of the CToken.
    /// @param amount Considered for the repay.
    function assumeWithdrawAmountIsCorrect(address market, uint256 amount) internal {
        hevm.assume(amount.div(ICToken(market).exchangeRateCurrent()) > 0);
    }

    function moveOneBlockForwardBorrowRepay() public {
        hevm.roll(block.number + 1);
    }
}
