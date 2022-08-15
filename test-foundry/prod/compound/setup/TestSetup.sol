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
    uint256 public constant MAX_BASIS_POINTS = 10_000;
    uint256 public constant INITIAL_BALANCE = 1_000_000;

    // DumbOracle public dumbOracle;
    // MorphoToken public morphoToken;
    ICompoundOracle public oracle;

    User public treasuryVault;

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
        // Types.MaxGasForMatching memory defaultMaxGasForMatching = Types.MaxGasForMatching({
        //     supply: 3e6,
        //     borrow: 3e6,
        //     withdraw: 3e6,
        //     repay: 3e6
        // });

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

        // treasuryVault = new User(morpho);

        // oracle = ICompoundOracle(comptroller.oracle());
        // morpho.setTreasuryVault(address(treasuryVault));

        // ///  Create Morpho token, deploy Incentives Vault and activate COMP rewards ///

        // morphoToken = new MorphoToken(address(this));
        // dumbOracle = new DumbOracle();
        // morphoToken.transfer(address(incentivesVault), 1_000_000 ether);
        // morpho.setIncentivesVault(incentivesVault);
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
        vm.label(address(oracle), "CompoundOracle");
        // vm.label(address(dumbOracle), "DumbOracle");
        vm.label(address(incentivesVault), "IncentivesVault");
        vm.label(address(treasuryVault), "TreasuryVault");
        vm.label(address(lens), "Lens");
    }

    function to6Decimals(uint256 value) internal pure returns (uint256) {
        return value / 1e12;
    }

    function to8Decimals(uint256 value) internal pure returns (uint256) {
        return value / 1e10;
    }
}
