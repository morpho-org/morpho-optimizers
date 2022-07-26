// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "@contracts/compound/interfaces/compound/ICompound.sol";
import "@contracts/compound/interfaces/IRewardsManager.sol";

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

import "@test-common/helpers/MorphoToken.sol";
import "@test-common/helpers/Chains.sol";
import "../../helpers/SimplePriceOracle.sol";
import "../../helpers/DumbOracle.sol";
import {User} from "../../helpers/User.sol";
import {Utils} from "../Utils.sol";
import "@config/Config.sol";
import "forge-std/console.sol";
import "forge-std/Vm.sol";

contract TestSetup is Config, Utils {
    Vm public hevm = Vm(HEVM_ADDRESS);

    uint256 public constant MAX_BASIS_POINTS = 10_000;
    uint256 public constant INITIAL_BALANCE = 1_000_000;

    ProxyAdmin public proxyAdmin;
    TransparentUpgradeableProxy public lensProxy;
    TransparentUpgradeableProxy public morphoProxy;
    TransparentUpgradeableProxy public rewardsManagerProxy;

    Lens public lensImplV1;
    Morpho public morphoImplV1;
    IRewardsManager public rewardsManagerImplV1;

    Lens public lens;
    Morpho public morpho;
    IPositionsManager public positionsManager;
    InterestRatesManager public interestRatesManager;
    IncentivesVault public incentivesVault;
    IRewardsManager public rewardsManager;

    DumbOracle public dumbOracle;
    MorphoToken public morphoToken;
    IComptroller public comptroller;
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

    address[] public pools;

    function setUp() public {
        initContracts();
        setContractsLabels();
        initUsers();

        onSetUp();
    }

    function onSetUp() public virtual {}

    function initContracts() internal {
        comptroller = IComptroller(comptrollerAddress);
        interestRatesManager = InterestRatesManager(interestRatesManager);
        positionsManager = PositionsManager(positionsManager);
        morphoImplV1 = Morpho(morphoImplementation);
        morpho = Morpho(morpho);
        treasuryVault = new User(morpho);
        oracle = ICompoundOracle(comptroller.oracle());
        morphoToken = MorphoToken();
        dumbOracle = new DumbOracle();
        rewardsManagerImplV1 = RewardsManager(rewardsManagerImplementation);
        rewardsManager = RewardsManager(rewardsManager);
        lensImplV1 = Lens(lensImplementation);
        lens = Lens(lens);
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
        deal(dai, address(_user), INITIAL_BALANCE * WAD);
        deal(wEth, address(_user), INITIAL_BALANCE * WAD);
        deal(usdt, address(_user), INITIAL_BALANCE * 1e6);
        deal(usdc, address(_user), INITIAL_BALANCE * 1e6);
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
