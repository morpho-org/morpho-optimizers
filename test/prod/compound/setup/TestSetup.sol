// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {CompoundMath} from "@morpho-dao/morpho-utils/math/CompoundMath.sol";
import {PercentageMath} from "@morpho-dao/morpho-utils/math/PercentageMath.sol";
import {SafeTransferLib, ERC20} from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import {Math} from "@morpho-dao/morpho-utils/math/Math.sol";
import {Types} from "src/compound/libraries/Types.sol";

import {PositionsManager} from "src/compound/PositionsManager.sol";
import {InterestRatesManager} from "src/compound/InterestRatesManager.sol";

import {User} from "../../../compound/helpers/User.sol";
import "config/compound/Config.sol";
import "@forge-std/console.sol";
import "@forge-std/Test.sol";

contract TestSetup is Config, Test {
    using CompoundMath for uint256;
    using PercentageMath for uint256;
    using SafeTransferLib for ERC20;

    uint256 MIN_USD_AMOUNT = 0.5 ether;
    uint256 MAX_USD_AMOUNT = 50_000_000_000 ether;

    User public user;

    struct TestMarket {
        address poolToken;
        address underlying;
        string symbol;
        uint256 decimals;
        uint256 collateralFactor;
        uint256 maxBorrows;
        uint256 totalBorrows;
        //
        bool mintGuardianPaused;
        bool borrowGuardianPaused;
        //
        Types.MarketPauseStatus status;
    }

    TestMarket[] public markets;
    TestMarket[] public activeMarkets;
    TestMarket[] public unpausedMarkets;
    TestMarket[] public collateralMarkets;
    TestMarket[] public borrowableMarkets;
    TestMarket[] public borrowableCollateralMarkets;

    uint256 snapshotId = type(uint256).max;

    function setUp() public virtual {
        initContracts();
        setContractsLabels();
        initUsers();

        _initMarkets();
    }

    function initContracts() internal {
        lens = Lens(address(lensProxy));
        morpho = Morpho(payable(morphoProxy));
        rewardsManager = RewardsManager(address(morpho.rewardsManager()));
        positionsManager = morpho.positionsManager();
        interestRatesManager = morpho.interestRatesManager();

        rewardsManagerProxy = TransparentUpgradeableProxy(payable(address(rewardsManager)));
    }

    function initUsers() internal {
        user = new User(morpho);

        vm.label(address(user), "User");

        deal(aave, address(this), type(uint256).max);
        deal(dai, address(this), type(uint256).max);
        deal(usdc, address(this), type(uint256).max);
        deal(usdt, address(this), type(uint256).max);
        deal(wbtc, address(this), type(uint256).max);
        deal(wEth, address(this), type(uint256).max);
        deal(comp, address(this), type(uint256).max);
        deal(bat, address(this), type(uint256).max);
        deal(tusd, address(this), type(uint256).max);
        deal(uni, address(this), type(uint256).max);
        deal(zrx, address(this), type(uint256).max);
        deal(link, address(this), type(uint256).max);
        deal(mkr, address(this), type(uint256).max);
        deal(fei, address(this), type(uint256).max);
        deal(yfi, address(this), type(uint256).max);
        deal(usdp, address(this), type(uint256).max);
        deal(sushi, address(this), type(uint256).max);
    }

    function setContractsLabels() internal {
        vm.label(address(proxyAdmin), "ProxyAdmin");
        vm.label(address(morphoImplV1), "MorphoImplV1");
        vm.label(address(morpho), "Morpho");
        vm.label(address(interestRatesManager), "InterestRatesManager");
        vm.label(address(rewardsManager), "RewardsManager");
        vm.label(address(comptroller), "Comptroller");
        vm.label(address(oracle), "Oracle");
        vm.label(address(lens), "Lens");

        vm.label(address(aave), "AAVE");
        vm.label(address(dai), "DAI");
        vm.label(address(usdc), "USDC");
        vm.label(address(usdt), "USDT");
        vm.label(address(wbtc), "WBTC");
        vm.label(address(wEth), "WETH");
        vm.label(address(comp), "COMP");
        vm.label(address(bat), "BAT");
        vm.label(address(tusd), "TUSD");
        vm.label(address(uni), "UNI");
        vm.label(address(zrx), "ZRX");
        vm.label(address(link), "LINK");
        vm.label(address(mkr), "MKR");
        vm.label(address(fei), "FEI");
        vm.label(address(yfi), "YFI");
        vm.label(address(usdp), "USDP");
        vm.label(address(sushi), "SUSHI");

        vm.label(address(cAave), "cAAVE");
        vm.label(address(cDai), "cDAI");
        vm.label(address(cUsdc), "cUSDC");
        vm.label(address(cUsdt), "cUSDT");
        vm.label(address(cWbtc2), "cWBTC");
        vm.label(address(cEth), "cETH");
        vm.label(address(cComp), "cCOMP");
        vm.label(address(cBat), "cBAT");
        vm.label(address(cTusd), "cTUSD");
        vm.label(address(cUni), "cUNI");
        vm.label(address(cZrx), "cZRX");
        vm.label(address(cLink), "cLINK");
        vm.label(address(cMkr), "cMKR");
        vm.label(address(cFei), "cFEI");
        vm.label(address(cYfi), "cYFI");
        vm.label(address(cUsdp), "cUSDP");
        vm.label(address(cSushi), "cSUSHI");
    }

    function _initMarkets() internal {
        address[] memory createdMarkets = morpho.getAllMarkets();

        for (uint256 i; i < createdMarkets.length; ++i) {
            address poolToken = createdMarkets[i];
            address underlying = _getUnderlying(poolToken);
            string memory symbol = ERC20(poolToken).symbol();

            TestMarket memory market = TestMarket({
                poolToken: poolToken,
                underlying: underlying,
                symbol: symbol,
                decimals: ERC20(underlying).decimals(),
                collateralFactor: 0,
                maxBorrows: comptroller.borrowCaps(poolToken),
                totalBorrows: ICToken(poolToken).totalBorrows(),
                mintGuardianPaused: comptroller.mintGuardianPaused(poolToken),
                borrowGuardianPaused: comptroller.borrowGuardianPaused(poolToken),
                status: IMorpho(address(morpho)).marketPauseStatus(poolToken)
            });

            (, bool isPaused, bool isPartiallyPaused) = morpho.marketStatus(poolToken);
            (, market.collateralFactor, ) = comptroller.markets(poolToken);
            market.maxBorrows = market.maxBorrows == 0 ? type(uint256).max : market.maxBorrows;

            markets.push(market);

            if (!isPaused) {
                unpausedMarkets.push(market);

                if (!isPartiallyPaused) {
                    activeMarkets.push(market);

                    bool isBorrowable = market.maxBorrows > market.totalBorrows.percentMul(103_00);

                    if (isBorrowable) borrowableMarkets.push(market);
                    else console.log("Unborrowable market:", symbol);

                    if (market.collateralFactor > 0) {
                        collateralMarkets.push(market);

                        if (isBorrowable) borrowableCollateralMarkets.push(market);
                        else console.log("Unborrowable collateral market:", symbol);
                    } else console.log("Zero collateral factor market:", symbol);
                } else console.log("Partially paused market:", symbol);
            } else console.log("Paused market:", symbol);
        }
    }

    function _boundBorrowAmount(
        TestMarket memory _market,
        uint96 _amount,
        uint256 _price
    ) internal view returns (uint256) {
        return
            bound(
                _amount,
                MIN_USD_AMOUNT.div(_price),
                Math.min(
                    Math.min(
                        Math.min(
                            (_market.maxBorrows - _market.totalBorrows) / 2,
                            _market.underlying == wEth
                                ? cEth.balance
                                : ERC20(_market.underlying).balanceOf(_market.poolToken)
                        ),
                        MAX_USD_AMOUNT.div(_price)
                    ),
                    type(uint96).max / 2 // so that collateral amount < type(uint96).max
                )
            );
    }

    function _getUnderlying(address _poolToken) internal view returns (address underlying) {
        return _poolToken == cEth ? wEth : ICToken(_poolToken).underlying();
    }

    function _getMinimumCollateralAmount(
        uint256 _borrowedAmount,
        uint256 _borrowedPrice,
        uint256 _collateralPrice,
        uint256 _collateralFactor
    ) internal pure returns (uint256) {
        return _borrowedAmount.mul(_borrowedPrice).div(_collateralFactor).div(_collateralPrice);
    }

    /// @dev Allows to add ERC20 tokens to the current balance of a given user (instead of resetting it via `deal`).
    /// @dev Also avoids to revert because of AAVE token snapshots: https://github.com/aave/aave-token-v2/blob/master/contracts/token/base/GovernancePowerDelegationERC20.sol#L174
    function _tip(
        address _underlying,
        address _user,
        uint256 _amount
    ) internal {
        if (_amount == 0) return;

        if (_underlying == wEth) deal(wEth, wEth.balance + _amount); // Refill wrapped Ether.

        ERC20(_underlying).safeTransfer(_user, _amount);
    }

    /// @dev Rolls & warps `_blocks` blocks forward the blockchain.
    function _forward(uint256 _blocks) internal {
        vm.roll(block.number + _blocks);
        vm.warp(block.timestamp + _blocks * 12);
    }

    /// @dev Reverts the fork to its initial fork state.
    function _revert() internal {
        if (snapshotId < type(uint256).max) vm.revertTo(snapshotId);
        snapshotId = vm.snapshot();
    }

    /// @dev Upgrades all the protocol contracts.
    function _upgrade() internal {
        vm.startPrank(proxyAdmin.owner());
        address rewardsManagerImplV2 = address(new RewardsManager());
        proxyAdmin.upgrade(rewardsManagerProxy, rewardsManagerImplV2);
        vm.label(rewardsManagerImplV2, "RewardsManagerImplV2");

        address morphoImplV2 = address(new Morpho());
        proxyAdmin.upgrade(morphoProxy, morphoImplV2);
        vm.label(morphoImplV2, "MorphoImplV2");

        lensExtension = new LensExtension(address(morpho));

        address lensImplV2 = address(new Lens(address(lensExtension)));
        proxyAdmin.upgrade(lensProxy, lensImplV2);
        vm.label(lensImplV2, "LensImplV2");

        morpho.setPositionsManager(new PositionsManager());
        vm.label(address(morpho.positionsManager()), "PositionsManagerV2");

        morpho.setInterestRatesManager(new InterestRatesManager());
        vm.label(address(morpho.interestRatesManager()), "InterestRatesManagerV2");

        vm.stopPrank();
    }
}
