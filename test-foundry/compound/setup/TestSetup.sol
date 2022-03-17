// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {ICToken, ICompoundOracle} from "@contracts/compound/interfaces/compound/ICompound.sol";
import "@contracts/compound/interfaces/IRewardsManagerForCompound.sol";
import "@contracts/common/interfaces/ISwapManager.sol";

import "hardhat/console.sol";
import "../../common/helpers/Chains.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import {SwapManagerUniV3OnEth} from "@contracts/common/SwapManagerUniV3OnEth.sol";
import {SwapManagerUniV3} from "@contracts/common/SwapManagerUniV3.sol";
import {SwapManagerUniV2} from "@contracts/common/SwapManagerUniV2.sol";
import {UniswapPoolCreator} from "../../common/uniswap/UniswapPoolCreator.sol";
import {UniswapV2PoolCreator} from "../../common/uniswap/UniswapV2PoolCreator.sol";
import "@contracts/compound/PositionsManagerForCompound.sol";
import "@contracts/compound/MarketsManagerForCompound.sol";
import "@contracts/compound/MatchingEngineForCompound.sol";

import "../../common/helpers/MorphoToken.sol";
import "../../common/helpers/SimplePriceOracle.sol";
import {User} from "../helpers/User.sol";
import "../../common/setup/HevmAdapter.sol";
import {Utils} from "./Utils.sol";
import "@config/Config.sol";

contract TestSetup is Config, Utils, HevmAdapter {
    using SafeERC20 for IERC20;

    uint256 public constant MAX_BASIS_POINTS = 10_000;
    uint256 public constant INITIAL_BALANCE = 1_000_000;

    ProxyAdmin public proxyAdmin;
    TransparentUpgradeableProxy public positionsManagerProxy;
    TransparentUpgradeableProxy public marketsManagerProxy;

    MatchingEngineForCompound internal matchingEngine;
    PositionsManagerForCompound internal positionsManagerImplV1;
    PositionsManagerForCompound internal positionsManager;
    PositionsManagerForCompound internal fakePositionsManagerImpl;
    MarketsManagerForCompound internal marketsManager;
    MarketsManagerForCompound internal marketsManagerImplV1;
    IRewardsManagerForCompound internal rewardsManager;
    ISwapManager public swapManager;
    UniswapPoolCreator public uniswapPoolCreator;
    UniswapV2PoolCreator public uniswapV2PoolCreator;
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
        PositionsManagerForCompound.MaxGas memory maxGas = PositionsManagerForCompoundStorage
        .MaxGas({supply: 3e6, borrow: 3e6, withdraw: 3e6, repay: 3e6});

        comptroller = IComptroller(comptrollerAddress);
        matchingEngine = new MatchingEngineForCompound();

        // Deploy proxy

        proxyAdmin = new ProxyAdmin();

        marketsManagerImplV1 = new MarketsManagerForCompound();
        marketsManagerProxy = new TransparentUpgradeableProxy(
            address(marketsManagerImplV1),
            address(this),
            ""
        );
        marketsManagerProxy.changeAdmin(address(proxyAdmin));
        marketsManager = MarketsManagerForCompound(address(marketsManagerProxy));
        marketsManager.initialize(comptroller);

        positionsManagerImplV1 = new PositionsManagerForCompound();
        positionsManagerProxy = new TransparentUpgradeableProxy(
            address(positionsManagerImplV1),
            address(this),
            ""
        );
        positionsManagerProxy.changeAdmin(address(proxyAdmin));
        positionsManager = PositionsManagerForCompound(address(positionsManagerProxy));
        positionsManager.initialize(
            marketsManager,
            matchingEngine,
            comptroller,
            swapManager,
            maxGas,
            20
        );

        treasuryVault = new User(positionsManager);

        fakePositionsManagerImpl = new PositionsManagerForCompound();
        oracle = ICompoundOracle(comptroller.oracle());

        marketsManager.setPositionsManager(address(positionsManager));
        positionsManager.setTreasuryVault(address(treasuryVault));

        createMarket(cDai);
        createMarket(cUsdc);
        createMarket(cWbtc);
        createMarket(cUsdt);
    }

    function createMarket(address _cToken) internal {
        marketsManager.createMarket(_cToken);

        // All tokens must also be added to the pools array, for the correct behavior of TestLiquidate::createAndSetCustomPriceOracle.
        pools.push(_cToken);

        hevm.label(_cToken, ERC20(_cToken).symbol());
        address underlying = ICToken(_cToken).underlying();
        hevm.label(underlying, ERC20(underlying).symbol());
    }

    function initUsers() internal {
        for (uint256 i = 0; i < 3; i++) {
            suppliers.push(new User(positionsManager));
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
            borrowers.push(new User(positionsManager));
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
        writeBalanceOf(address(_user), dai, INITIAL_BALANCE * WAD);
        writeBalanceOf(address(_user), usdc, INITIAL_BALANCE * 1e6);
    }

    function setContractsLabels() internal {
        hevm.label(address(positionsManager), "PositionsManager");
        hevm.label(address(marketsManager), "MarketsManager");
        hevm.label(address(rewardsManager), "RewardsManager");
        hevm.label(address(swapManager), "SwapManager");
        hevm.label(address(uniswapPoolCreator), "UniswapPoolCreator");
        hevm.label(address(morphoToken), "MorphoToken");
        hevm.label(address(comptroller), "Comptroller");
        hevm.label(address(oracle), "CompoundOracle");
        hevm.label(address(treasuryVault), "TreasuryVault");
    }

    function createSigners(uint8 _nbOfSigners) internal {
        while (borrowers.length < _nbOfSigners) {
            borrowers.push(new User(positionsManager));
            fillUserBalances(borrowers[borrowers.length - 1]);

            suppliers.push(new User(positionsManager));
            fillUserBalances(suppliers[suppliers.length - 1]);
        }
    }

    function createAndSetCustomPriceOracle() public returns (SimplePriceOracle) {
        SimplePriceOracle customOracle = new SimplePriceOracle();

        hevm.store(
            address(comptroller),
            keccak256(abi.encode(bytes32("oracle"), 2)),
            bytes32(uint256(uint160(address(customOracle))))
        );

        for (uint256 i = 0; i < pools.length; i++) {
            address underlying = ICToken(pools[i]).underlying();

            customOracle.setDirectPrice(underlying, oracle.getUnderlyingPrice(underlying));
        }

        return customOracle;
    }

    function setMaxGasHelper(
        uint64 _supply,
        uint64 _borrow,
        uint64 _withdraw,
        uint64 _repay
    ) public {

            PositionsManagerForCompoundStorage.MaxGas memory newMaxGas
         = PositionsManagerForCompoundStorage.MaxGas({
            supply: _supply,
            borrow: _borrow,
            withdraw: _withdraw,
            repay: _repay
        });

        positionsManager.setMaxGas(newMaxGas);
    }
}
