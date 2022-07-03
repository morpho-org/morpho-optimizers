import "@contracts/aave-v2/interfaces/IRewardsManager.sol";
import {ILendingPoolAddressesProvider} from "@contracts/aave-v2/interfaces/aave/ILendingPoolAddressesProvider.sol";

import "forge-std/Script.sol";
import "@config/mumbai-testnet/aave-v2/Config.sol";
import "@contracts/external/ProxyAdmin.sol";
import {EntryPositionsManager} from "@contracts/aave-v2/EntryPositionsManager.sol";
import {ExitPositionsManager} from "@contracts/aave-v2/ExitPositionsManager.sol";
import {Morpho} from "@contracts/aave-v2/Morpho.sol";
import {InterestRatesManager} from "@contracts/aave-v2/InterestRatesManager.sol";
import {RewardsManagerOnPolygon} from "@contracts/aave-v2/rewards-managers/RewardsManagerOnPolygon.sol";
import {Lens} from "@contracts/aave-v2/Lens.sol";

/// @notice Contract to deploy Morpho AAVE on testnet
/// more informations here: https://book.getfoundry.sh/tutorials/solidity-scripting.html
contract DeployMorphoAaveV2 is Script, Config {
    event ContractDeployed(string name, address deployedAddress);

    function run() external {
        vm.startBroadcast();

        ProxyAdmin proxyAdmin = new ProxyAdmin();
        emit ContractDeployed("Proxy Admin", address(proxyAdmin));

        // Deploy Morpho's dependencies
        EntryPositionsManager entryPositionsManager = new EntryPositionsManager();
        emit ContractDeployed("EntryPositionsManager", address(entryPositionsManager));
        ExitPositionsManager exitPositionsManager = new ExitPositionsManager();
        emit ContractDeployed("ExitPositionsManager", address(exitPositionsManager));
        InterestRatesManager interestRatesManager = new InterestRatesManager();
        emit ContractDeployed("InterestRatesManager", address(interestRatesManager));

        // Deploy Morpho proxy
        Morpho morphoImplementation = new Morpho();
        emit ContractDeployed("MorphoImplementation", address(morphoImplementation));
        TransparentUpgradeableProxy morphoProxy = new TransparentUpgradeableProxy(
            address(morphoImplementation),
            address(proxyAdmin),
            abi.encodeWithSelector( // initialize function
                morphoImplementation.initialize.selector,
                entryPositionsManager,
                exitPositionsManager,
                interestRatesManager,
                lendingPoolAddressesProvider,
                defaultMaxGasForMatching,
                defaultMaxSortedUsers
            )
        );
        emit ContractDeployed("MorphoProxy", address(morphoProxy));

        // Deploy Upgradeable RewardsManager
        IRewardsManager rewardsManagerImplementation = new RewardsManagerOnPolygon();
        emit ContractDeployed(
            "RewardsManagerImplementation",
            address(rewardsManagerImplementation)
        );

        TransparentUpgradeableProxy rewardsManagerProxy = new TransparentUpgradeableProxy(
            address(rewardsManagerImplementation),
            address(proxyAdmin),
            abi.encodeWithSelector( // initialize function
                rewardsManagerImplementation.initialize.selector,
                address(morphoProxy)
            )
        );
        emit ContractDeployed("RewardsManagerProxy", address(rewardsManagerProxy));
        Morpho morpho = Morpho(address(morphoProxy));
        morpho.setRewardsManager(IRewardsManager(address(rewardsManagerProxy)));

        // Deploy Upgradeable Lens
        Lens lens = new Lens(
            address(morpho),
            ILendingPoolAddressesProvider(lendingPoolAddressesProvider)
        );
        emit ContractDeployed("Lens", address(lens));

        // Deploy markets
        Types.MarketParameters memory defaultMarketParameters = Types.MarketParameters({
            reserveFactor: 1000,
            p2pIndexCursor: 3333
        });
        morpho.createMarket(aave, defaultMarketParameters);
        morpho.createMarket(dai, defaultMarketParameters);
        morpho.createMarket(usdc, defaultMarketParameters);
        morpho.createMarket(usdt, defaultMarketParameters);
        morpho.createMarket(wbtc, defaultMarketParameters);
        morpho.createMarket(weth, defaultMarketParameters);
        morpho.createMarket(wmatic, defaultMarketParameters);

        vm.stopBroadcast();
    }
}
