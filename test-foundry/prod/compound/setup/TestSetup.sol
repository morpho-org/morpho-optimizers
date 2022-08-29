// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "@contracts/compound/interfaces/IRewardsManager.sol";
import "@contracts/compound/interfaces/IMorpho.sol";

import "@openzeppelin/contracts/utils/Strings.sol";
import "@contracts/compound/libraries/CompoundMath.sol";
import "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import "@morpho-dao/morpho-utils/math/Math.sol";

import {User} from "../../../compound/helpers/User.sol";
import "@config/Config.sol";
import "@forge-std/console.sol";
import "@forge-std/Test.sol";
import "@forge-std/Vm.sol";

contract TestSetup is Config, Test {
    using CompoundMath for uint256;
    using SafeTransferLib for ERC20;

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
        rewardsManager = RewardsManager(address(morpho.rewardsManager()));
        incentivesVault = morpho.incentivesVault();
        positionsManager = morpho.positionsManager();
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
    }

    function setContractsLabels() internal {
        vm.label(address(proxyAdmin), "ProxyAdmin");
        vm.label(address(morphoImplV1), "MorphoImplV1");
        vm.label(address(morpho), "Morpho");
        vm.label(address(interestRatesManager), "InterestRatesManager");
        vm.label(address(rewardsManager), "RewardsManager");
        vm.label(address(comptroller), "Comptroller");
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

        vm.label(address(cAave), "cAAVE");
        vm.label(address(cDai), "cDAI");
        vm.label(address(cUsdc), "cUSDC");
        vm.label(address(cUsdt), "cUSDT");
        vm.label(address(cWbtc2), "cWBTC");
        vm.label(address(cEth), "cWETH");
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

    function getAllFullyActiveMarkets() public view returns (address[] memory activeMarkets) {
        address[] memory createdMarkets = morpho.getAllMarkets();
        uint256 nbCreatedMarkets = createdMarkets.length;

        uint256 nbActiveMarkets;
        activeMarkets = new address[](nbCreatedMarkets);

        for (uint256 i; i < nbCreatedMarkets; ) {
            address poolToken = createdMarkets[i];

            (, bool isPaused, bool isPartiallyPaused) = morpho.marketStatus(poolToken);
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
        address[] memory createdMarkets = morpho.getAllMarkets();
        uint256 nbCreatedMarkets = createdMarkets.length;

        uint256 nbActiveMarkets;
        unpausedMarkets = new address[](nbCreatedMarkets);

        for (uint256 i; i < nbCreatedMarkets; ) {
            address poolToken = createdMarkets[i];

            (, bool isPaused, ) = morpho.marketStatus(poolToken);
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

            (, uint256 collateralFactor, ) = morpho.comptroller().markets(poolToken);
            (, bool isPaused, bool isPartiallyPaused) = morpho.marketStatus(poolToken);
            if (collateralFactor > 0 && !isPaused && !isPartiallyPaused) {
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
        uint256 borrowCap = morpho.comptroller().borrowCaps(_poolToken);

        return
            bound(
                _amount,
                10**(_decimals - 6),
                Math.min(
                    (borrowCap > 0 ? borrowCap - 1 : type(uint256).max) -
                        ICToken(_poolToken).totalBorrows(),
                    _underlying == wEth
                        ? _poolToken.balance
                        : ERC20(_underlying).balanceOf(_poolToken)
                )
            );
    }

    function _getUnderlying(address _poolToken)
        internal
        view
        returns (ERC20 underlying, uint256 decimals)
    {
        underlying = ERC20(_poolToken == cEth ? wEth : ICToken(_poolToken).underlying());
        decimals = underlying.decimals();
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
    /// @dev Also avoids to mess with snapshots of snapshotted ERC20 (e.g. AAVE).
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
