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
import {PositionsManagerUtils} from "@contracts/aave-v2/PositionsManagerUtils.sol";
import {EntryPositionsManager} from "@contracts/aave-v2/EntryPositionsManager.sol";
import {ExitPositionsManager} from "@contracts/aave-v2/ExitPositionsManager.sol";
import "@contracts/aave-v2/Morpho.sol";

import "../../../common/helpers/Chains.sol";
import {User} from "../../../aave-v2/helpers/User.sol";
import {Utils} from "../../../aave-v2/setup/Utils.sol";
import "@config/Config.sol";
import "@forge-std/Test.sol";
import "@forge-std/console.sol";

contract TestSetup is Config, Test {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using SafeTransferLib for ERC20;
    using stdStorage for StdStorage;

    User public supplier1;
    User public supplier2;
    User public supplier3;
    User[] public suppliers;

    User public borrower1;
    User public borrower2;
    User public borrower3;
    User[] public borrowers;

    function setUp() public {
        initContracts();
        setContractsLabels();
        initUsers();

        onSetUp();
    }

    function onSetUp() public virtual {}

    function initContracts() internal {
        // vm.prank(address(proxyAdmin));
        // lensImplV1 = Lens(lensProxy.implementation());
        // morphoImplV1 = Morpho(payable(morphoProxy.implementation()));
        // rewardsManagerImplV1 = RewardsManager(rewardsManagerProxy.implementation());

        lens = Lens(address(lensProxy));
        morpho = Morpho(payable(morphoProxy));
        rewardsManager = morpho.rewardsManager();
        incentivesVault = morpho.incentivesVault();
        entryPositionsManager = morpho.entryPositionsManager();
        exitPositionsManager = morpho.exitPositionsManager();
        interestRatesManager = morpho.interestRatesManager();

        rewardsManagerProxy = TransparentUpgradeableProxy(payable(address(rewardsManager)));
    }

    function initUsers() internal {
        for (uint256 i = 0; i < 3; i++) {
            suppliers.push(new User(morpho));
            vm.label(
                address(suppliers[i]),
                string(abi.encodePacked("Supplier", Strings.toString(i + 1)))
            );
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
        }

        borrower1 = borrowers[0];
        borrower2 = borrowers[1];
        borrower3 = borrowers[2];

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

        deal(address(this), type(uint256).max);
        (bool deposited, ) = payable(stEth).call{value: 100_000 ether}("");
        require(deposited, "ETH not deposited into stEth");

        uint256 balance = ERC20(stEth).balanceOf(stEthWhale);
        vm.prank(stEthWhale);
        ERC20(stEth).transfer(address(this), balance);

        balance = ERC20(stEth).balanceOf(stEthWhale2);
        vm.prank(stEthWhale2);
        ERC20(stEth).transfer(address(this), balance);
    }

    function setContractsLabels() internal {
        vm.label(address(poolAddressesProvider), "PoolAddressesProvider");
        vm.label(address(aaveIncentivesController), "IncentivesController");
        vm.label(address(pool), "LendingPool");
        vm.label(address(proxyAdmin), "ProxyAdmin");
        vm.label(address(morphoImplV1), "MorphoImplV1");
        vm.label(address(morpho), "Morpho");
        vm.label(address(interestRatesManager), "InterestRatesManager");
        vm.label(address(rewardsManager), "RewardsManager");
        vm.label(address(oracle), "Oracle");
        vm.label(address(incentivesVault), "IncentivesVault");
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

        vm.label(address(aAave), "aAAVE");
        vm.label(address(aDai), "aDAI");
        vm.label(address(aUsdc), "aUSDC");
        vm.label(address(aUsdt), "aUSDT");
        vm.label(address(aWbtc), "aWBTC");
        vm.label(address(aWeth), "aWETH");
    }

    function getAllFullyActiveMarkets() public view returns (address[] memory activeMarkets) {
        address[] memory createdMarkets = morpho.getMarketsCreated();
        uint256 nbCreatedMarkets = createdMarkets.length;

        uint256 nbActiveMarkets;
        activeMarkets = new address[](nbCreatedMarkets);

        for (uint256 i; i < nbCreatedMarkets; ) {
            address poolToken = createdMarkets[i];

            (, , , , bool isPaused, bool isPartiallyPaused, ) = morpho.market(poolToken);
            if (!isPaused && !isPartiallyPaused) {
                activeMarkets[nbActiveMarkets] = poolToken;
                ++nbActiveMarkets;
            } else console.log("Skipping paused (or partially paused) market:", poolToken);

            unchecked {
                ++i;
            }
        }

        // Resize the array for return
        assembly {
            mstore(activeMarkets, nbActiveMarkets)
        }
    }

    function getAllUnpausedMarkets() public view returns (address[] memory unpausedMarkets) {
        address[] memory createdMarkets = morpho.getMarketsCreated();
        uint256 nbCreatedMarkets = createdMarkets.length;

        uint256 nbActiveMarkets;
        unpausedMarkets = new address[](nbCreatedMarkets);

        for (uint256 i; i < nbCreatedMarkets; ) {
            address poolToken = createdMarkets[i];

            (, , , , bool isPaused, , ) = morpho.market(poolToken);
            if (!isPaused) {
                unpausedMarkets[nbActiveMarkets] = poolToken;
                ++nbActiveMarkets;
            } else console.log("Skipping paused market:", poolToken);

            unchecked {
                ++i;
            }
        }

        // Resize the array for return
        assembly {
            mstore(unpausedMarkets, nbActiveMarkets)
        }
    }

    function getAllBorrowingEnabledMarkets()
        public
        view
        returns (address[] memory borrowingEnabledMarkets)
    {
        address[] memory activeMarkets = getAllFullyActiveMarkets();
        uint256 nbActiveMarkets = activeMarkets.length;

        uint256 nbBorrowingEnabledMarkets;
        borrowingEnabledMarkets = new address[](nbActiveMarkets);

        for (uint256 i; i < nbActiveMarkets; ) {
            address poolToken = activeMarkets[i];

            if (
                pool
                    .getConfiguration(IAToken(poolToken).UNDERLYING_ASSET_ADDRESS())
                    .getBorrowingEnabled()
            ) {
                borrowingEnabledMarkets[nbBorrowingEnabledMarkets] = poolToken;
                ++nbBorrowingEnabledMarkets;
            } else console.log("Skipping borrowing disabled market:", poolToken);

            unchecked {
                ++i;
            }
        }

        // Resize the array for return
        assembly {
            mstore(borrowingEnabledMarkets, nbBorrowingEnabledMarkets)
        }
    }

    function getAllFullyActiveCollateralMarkets()
        public
        view
        returns (address[] memory activeCollateralMarkets)
    {
        address[] memory activeMarkets = getAllFullyActiveMarkets();
        uint256 nbActiveMarkets = activeMarkets.length;

        uint256 nbActiveCollateralMarkets;
        activeCollateralMarkets = new address[](nbActiveMarkets);

        for (uint256 i; i < nbActiveMarkets; ) {
            address poolToken = activeMarkets[i];
            address underlying = IAToken(poolToken).UNDERLYING_ASSET_ADDRESS();

            (uint256 ltv, , , , ) = pool.getConfiguration(underlying).getParamsMemory();
            (, , , , bool isPaused, bool isPartiallyPaused, ) = morpho.market(poolToken);
            if (ltv > 0 && !isPaused && !isPartiallyPaused) {
                activeCollateralMarkets[nbActiveCollateralMarkets] = poolToken;
                ++nbActiveCollateralMarkets;
            } else console.log("Skipping paused (or partially paused) market:", poolToken);

            unchecked {
                ++i;
            }
        }

        // Resize the array for return
        assembly {
            mstore(activeCollateralMarkets, nbActiveCollateralMarkets)
        }
    }

    function _boundBorrowedAmount(
        uint96 _amount,
        address _poolToken,
        address _underlying,
        uint256 _decimals
    ) internal returns (uint256) {
        return bound(_amount, 10**(_decimals - 6), ERC20(_underlying).balanceOf(_poolToken));
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
}
