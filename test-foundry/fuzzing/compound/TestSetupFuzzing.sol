// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "@contracts/compound/interfaces/compound/ICompound.sol";
import "@contracts/compound/interfaces/IRewardsManager.sol";
import "@contracts/common/interfaces/ISwapManager.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "@contracts/compound/comp-rewards/IncentivesVault.sol";
import "@contracts/compound/comp-rewards/RewardsManager.sol";
import "@contracts/compound/PositionsManager.sol";
import "@contracts/compound/MatchingEngine.sol";
import "@contracts/compound/InterestRates.sol";
import "@contracts/compound/Morpho.sol";

import "../../common/helpers/MorphoToken.sol";
import "../../common/helpers/Chains.sol";
import "../../compound/helpers/SimplePriceOracle.sol";
import "../../compound/helpers/DumbOracle.sol";
import {User} from "../../compound/helpers/User.sol";
import {Utils} from "../../compound/setup/Utils.sol";
import "forge-std/console.sol";
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
    uint256 internal constant NMAX = 20;
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
    Morpho internal fakeMorphoImpl;
    InterestRates internal interestRates;
    IRewardsManager internal rewardsManager;
    IPositionsManager internal positionsManager;

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
        MorphoStorage.MaxGasForMatching memory maxGasForMatching = MorphoStorage.MaxGasForMatching({
            supply: 3e6,
            borrow: 3e6,
            withdraw: 3e6,
            repay: 3e6
        });

        comptroller = IComptroller(comptrollerAddress);
        interestRates = new InterestRates();
        positionsManager = new PositionsManager();

        /// Deploy proxies ///

        proxyAdmin = new ProxyAdmin();
        interestRates = new InterestRates();

        morphoImplV1 = new Morpho();
        morphoProxy = new TransparentUpgradeableProxy(address(morphoImplV1), address(this), "");

        morphoProxy.changeAdmin(address(proxyAdmin));
        morpho = Morpho(payable(address(morphoProxy)));
        morpho.initialize(
            positionsManager,
            interestRates,
            comptroller,
            1,
            maxGasForMatching,
            NMAX,
            cEth,
            wEth
        );

        treasuryVault = new User(morpho);
        fakeMorphoImpl = new Morpho();
        oracle = ICompoundOracle(comptroller.oracle());
        morpho.setTreasuryVault(address(treasuryVault));

        // make sure the wEth contract has enough ETH to unwrap any amount
        hevm.deal(wEth, type(uint128).max);

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
            address(morpho),
            address(morphoToken),
            address(1),
            address(dumbOracle)
        );
        morphoToken.transfer(address(incentivesVault), 1_000_000 ether);

        rewardsManager = new RewardsManager(address(morpho));

        morpho.setRewardsManager(rewardsManager);
        morpho.setIncentivesVault(incentivesVault);
        morpho.toggleCompRewardsActivation();

        // Tip the Morpho contract to ensure that there are no dust errors on withdraw
        tip(aave, address(morpho), 10**ERC20(aave).decimals());
        tip(dai, address(morpho), 10**ERC20(dai).decimals());
        tip(usdc, address(morpho), 10**ERC20(usdc).decimals());
        tip(usdt, address(morpho), 10**ERC20(usdt).decimals());
        tip(wbtc, address(morpho), 10**ERC20(wbtc).decimals());
        tip(wEth, address(morpho), 10**ERC20(wEth).decimals());
        tip(comp, address(morpho), 10**ERC20(comp).decimals());
        tip(bat, address(morpho), 10**ERC20(bat).decimals());
        tip(tusd, address(morpho), 10**ERC20(tusd).decimals());
        tip(uni, address(morpho), 10**ERC20(uni).decimals());
        tip(zrx, address(morpho), 10**ERC20(zrx).decimals());
        tip(link, address(morpho), 10**ERC20(link).decimals());
        tip(mkr, address(morpho), 10**ERC20(mkr).decimals());
        tip(fei, address(morpho), 10**ERC20(fei).decimals());
        tip(yfi, address(morpho), 10**ERC20(yfi).decimals());
        tip(usdp, address(morpho), 10**ERC20(usdp).decimals());
        tip(sushi, address(morpho), 10**ERC20(sushi).decimals());
    }

    function createMarket(address _cToken) internal {
        morpho.createMarket(_cToken);
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
            tip(tokens[i], address(_user), ERC20(tokens[i]).totalSupply() / 2);
        }
    }

    function setContractsLabels() internal {
        hevm.label(address(proxyAdmin), "ProxyAdmin");
        hevm.label(address(morphoImplV1), "MorphoImplV1");
        hevm.label(address(morpho), "Morpho");
        hevm.label(address(interestRates), "InterestRates");
        hevm.label(address(rewardsManager), "RewardsManager");
        hevm.label(address(morphoToken), "MorphoToken");
        hevm.label(address(comptroller), "Comptroller");
        hevm.label(address(oracle), "CompoundOracle");
        hevm.label(address(dumbOracle), "DumbOracle");
        hevm.label(address(incentivesVault), "IncentivesVault");
        hevm.label(address(treasuryVault), "TreasuryVault");
    }

    function createSigners(uint256 _nbOfSigners) internal {
        while (borrowers.length < _nbOfSigners) {
            borrowers.push(new User(morpho));
            fillUserBalances(borrowers[borrowers.length - 1]);
            suppliers.push(new User(morpho));
            fillUserBalances(suppliers[suppliers.length - 1]);
        }
    }

    function assumeSupplyAmountIsInRange(
        User _user,
        address underlying,
        uint256 amount
    ) internal {
        hevm.assume(amount > 0);
        hevm.assume(ERC20(underlying).balanceOf(address(_user)) >= amount);
    }

    function assumeBorrowAmountIsInRange(
        User _user,
        address _CToken,
        uint128 amount
    ) internal {
        address underlying;
        underlying = _CToken == cEth ? wEth : ICToken(_CToken).underlying();
        assumeAmountIsNotTooLow(underlying, amount);
        assumeBorrowAmountIsNotTooHigh(_CToken, amount);
        (, uint256 borrowable) = morpho.getUserMaxCapacitiesForAsset(address(_user), _CToken);
        hevm.assume(amount <= borrowable);
    }

    /// @notice checks morpho will not revert because of Compound rounding the amount to 0
    function assumeAmountIsNotTooLow(address underlying, uint128 amount) internal {
        uint8 suppliedUnderlyingDecimals = ERC20(underlying).decimals();
        uint256 minValueToSupply = (
            suppliedUnderlyingDecimals > 8 ? 10**(suppliedUnderlyingDecimals - 8) : 1
        );
        hevm.assume(amount >= minValueToSupply);
    }

    /// @notice a borrow amount can be too high on compound due to governance or unsufficient supply
    /// @param market address of the CToken
    function assumeBorrowAmountIsNotTooHigh(address market, uint256 amount) internal {
        hevm.assume(amount <= ICToken(market).getCash());
        uint256 borrowCap = comptroller.borrowCaps(market);
        if (borrowCap != 0) hevm.assume(amount <= borrowCap);
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

    function setMaxGasForMatchingHelper(
        uint64 _supply,
        uint64 _borrow,
        uint64 _withdraw,
        uint64 _repay
    ) public {
        MorphoStorage.MaxGasForMatching memory newMaxGas = MorphoStorage.MaxGasForMatching({
            supply: _supply,
            borrow: _borrow,
            withdraw: _withdraw,
            repay: _repay
        });
        morpho.setMaxGasForMatching(newMaxGas);
    }

    function move1000BlocksForward(address _marketAddress) public {
        hevm.roll(block.number + 1_000);
        hevm.warp(block.timestamp + 13 * 1_000); // mainnet block time is around 13 sec
        morpho.updateP2PIndexes(_marketAddress);
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

    function getUnderlying(address _poolTokenAddress) internal view returns (address) {
        if (_poolTokenAddress == cEth)
            // cETH has no underlying() function.
            return wEth;
        else return ICToken(_poolTokenAddress).underlying();
    }

    function getAsset(uint8 _asset) internal view returns (address asset, address underlying) {
        asset = pools[_asset % pools.length];
        underlying = getUnderlying(asset);
    }
}
