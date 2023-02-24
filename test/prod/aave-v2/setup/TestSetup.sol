// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "src/aave-v2/interfaces/aave/IVariableDebtToken.sol";
import "src/aave-v2/interfaces/aave/IAToken.sol";
import "src/aave-v2/interfaces/lido/ILido.sol";

import {ReserveConfiguration} from "src/aave-v2/libraries/aave/ReserveConfiguration.sol";
import "@morpho-dao/morpho-utils/math/WadRayMath.sol";
import "@morpho-dao/morpho-utils/math/PercentageMath.sol";
import "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import "@morpho-dao/morpho-utils/math/Math.sol";

import {InterestRatesManager} from "src/aave-v2/InterestRatesManager.sol";
import {MatchingEngine} from "src/aave-v2/MatchingEngine.sol";
import {PositionsManagerUtils} from "src/aave-v2/PositionsManagerUtils.sol";
import {EntryPositionsManager} from "src/aave-v2/EntryPositionsManager.sol";
import {ExitPositionsManager} from "src/aave-v2/ExitPositionsManager.sol";
import "src/aave-v2/Morpho.sol";

import {User} from "../../../aave-v2/helpers/User.sol";
import "config/aave-v2/Config.sol";
import "@forge-std/console.sol";
import "@forge-std/Test.sol";

contract TestSetup is Config, Test {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using SafeTransferLib for ERC20;
    using stdStorage for StdStorage;

    uint256 MIN_ETH_AMOUNT = 0.001 ether;
    uint256 MAX_ETH_AMOUNT = 50_000_000 ether;

    User public user;

    struct TestMarket {
        address poolToken;
        address debtToken;
        address underlying;
        string symbol;
        uint256 decimals;
        uint256 ltv;
        uint256 liquidationThreshold;
        Types.Market config;
        //
        bool isActive;
        bool isFrozen;
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
        entryPositionsManager = morpho.entryPositionsManager();
        exitPositionsManager = morpho.exitPositionsManager();
        interestRatesManager = morpho.interestRatesManager();
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
        deal(crv, address(this), type(uint256).max);
        deal(frax, address(this), type(uint256).max);

        deal(stEth, type(uint256).max);
        stdstore.target(stEth).sig("sharesOf(address)").with_key(address(this)).checked_write(
            type(uint256).max / 1e36
        );
    }

    function setContractsLabels() internal {
        vm.label(address(poolAddressesProvider), "PoolAddressesProvider");
        vm.label(address(pool), "LendingPool");
        vm.label(address(proxyAdmin), "ProxyAdmin");
        vm.label(address(morphoImplV1), "MorphoImplV1");
        vm.label(address(morpho), "Morpho");
        vm.label(address(interestRatesManager), "InterestRatesManager");
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
        vm.label(address(crv), "CRV");
        vm.label(address(stEth), "stETH");
        vm.label(address(frax), "FRAX");

        vm.label(address(aAave), "aAAVE");
        vm.label(address(aDai), "aDAI");
        vm.label(address(aUsdc), "aUSDC");
        vm.label(address(aUsdt), "aUSDT");
        vm.label(address(aWbtc), "aWBTC");
        vm.label(address(aWeth), "aWETH");
        vm.label(address(aDai), "aDAI");
        vm.label(address(aCrv), "aCrv");
        vm.label(address(aStEth), "astETH");
        vm.label(address(aFrax), "aFRAX");
    }

    function _initMarkets() internal {
        address[] memory createdMarkets = morpho.getMarketsCreated();

        for (uint256 i; i < createdMarkets.length; ++i) {
            address poolToken = createdMarkets[i];
            address underlying = IAToken(poolToken).UNDERLYING_ASSET_ADDRESS();
            string memory symbol = ERC20(poolToken).symbol();

            Types.Market memory marketConfig;
            (
                marketConfig.underlyingToken,
                marketConfig.reserveFactor,
                marketConfig.p2pIndexCursor,
                marketConfig.isCreated,
                marketConfig.isPaused,
                marketConfig.isPartiallyPaused,
                marketConfig.isP2PDisabled
            ) = morpho.market(poolToken);
            TestMarket memory market = TestMarket({
                poolToken: poolToken,
                debtToken: pool.getReserveData(underlying).variableDebtTokenAddress,
                underlying: underlying,
                symbol: symbol,
                ltv: 0,
                liquidationThreshold: 0,
                decimals: 0,
                config: marketConfig,
                isActive: false,
                isFrozen: false,
                status: IMorpho(address(morpho)).marketPauseStatus(poolToken)
            });

            DataTypes.ReserveConfigurationMap memory config = pool.getConfiguration(underlying);
            (market.ltv, market.liquidationThreshold, , market.decimals, ) = config
            .getParamsMemory();

            bool isBorrowable;
            (market.isActive, market.isFrozen, isBorrowable, ) = config.getFlagsMemory();

            markets.push(market);

            if (!market.config.isPaused) {
                unpausedMarkets.push(market);

                if (!market.config.isPartiallyPaused) {
                    activeMarkets.push(market);

                    if (isBorrowable) borrowableMarkets.push(market);
                    else console.log("Unborrowable market:", symbol);

                    if (market.ltv > 0) {
                        collateralMarkets.push(market);

                        if (isBorrowable) borrowableCollateralMarkets.push(market);
                        else console.log("Unborrowable collateral market:", symbol);
                    } else console.log("Zero ltv market:", symbol);
                } else console.log("Partially paused market:", symbol);
            } else console.log("Paused market:", symbol);
        }
    }

    function _boundSupplyAmount(
        TestMarket memory _market,
        uint96 _amount,
        uint256 _price
    ) internal view returns (uint256) {
        return
            bound(
                _amount,
                (MIN_ETH_AMOUNT * 10**_market.decimals) / _price,
                Math.min((MAX_ETH_AMOUNT * 10**_market.decimals) / _price, type(uint96).max)
            );
    }

    function _boundBorrowAmount(
        TestMarket memory _market,
        uint96 _amount,
        uint256 _price
    ) internal view returns (uint256) {
        return
            bound(
                _amount,
                (MIN_ETH_AMOUNT * 10**_market.decimals) / _price,
                Math.min(
                    Math.min(
                        ERC20(_market.underlying).balanceOf(_market.poolToken),
                        (MAX_ETH_AMOUNT * 10**_market.decimals) / _price
                    ),
                    type(uint96).max / 2 // so that collateral amount < type(uint96).max
                )
            );
    }

    function _getMinimumCollateralAmount(
        uint256 _borrowedAmount,
        uint256 _borrowedPrice,
        uint256 _borrowedDecimals,
        uint256 _collateralPrice,
        uint256 _collateralDecimals,
        uint256 _collateralLtv
    ) internal pure returns (uint256) {
        return (
            ((_borrowedAmount * _borrowedPrice * 10**_collateralDecimals).percentDiv(
                _collateralLtv
            ) / (_collateralPrice * 10**_borrowedDecimals))
        );
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
        address morphoImplV2 = address(new Morpho());
        proxyAdmin.upgrade(morphoProxy, morphoImplV2);
        vm.label(morphoImplV2, "MorphoImplV2");

        address lensImplV2 = address(new Lens(address(morpho)));
        proxyAdmin.upgrade(lensProxy, lensImplV2);
        vm.label(lensImplV2, "LensImplV2");

        morpho.setEntryPositionsManager(new EntryPositionsManager());
        vm.label(address(morpho.entryPositionsManager()), "EntryPositionsManagerV2");

        morpho.setExitPositionsManager(new ExitPositionsManager());
        vm.label(address(morpho.exitPositionsManager()), "ExitPositionsManagerV2");

        morpho.setInterestRatesManager(new InterestRatesManager());
        vm.label(address(morpho.interestRatesManager()), "InterestRatesManagerV2");

        vm.stopPrank();
    }
}
