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
    // MorphoToken public morphoToken;

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

        // morphoToken = new MorphoToken(address(this));
        // morphoToken.transfer(address(incentivesVault), 1_000_000 ether);
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
    }

    function setContractsLabels() internal {
        vm.label(address(proxyAdmin), "ProxyAdmin");
        vm.label(address(morphoImplV1), "MorphoImplV1");
        vm.label(address(morpho), "Morpho");
        vm.label(address(interestRatesManager), "InterestRatesManager");
        vm.label(address(rewardsManager), "RewardsManager");
        // vm.label(address(morphoToken), "MorphoToken");
        vm.label(address(comptroller), "Comptroller");
        vm.label(comptroller.oracle(), "CompoundOracle");
        vm.label(address(incentivesVault), "IncentivesVault");
        vm.label(address(lens), "Lens");
    }

    function to6Decimals(uint256 value) internal pure returns (uint256) {
        return value / 1e12;
    }

    function to8Decimals(uint256 value) internal pure returns (uint256) {
        return value / 1e10;
    }
}
