// SPDX-License-Identifier: GNU AGPLv3
pragma solidity >=0.8.0;

import "@forge-std/Vm.sol";
import "@forge-std/StdJson.sol";

library TestHelpers {
    using stdJson for string;

    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    string private constant CONFIG_PATH = "/config/Config.json";

    function setForkFromJson(string memory network, string memory protocol)
        internal
        returns (uint256 forkId)
    {
        string memory root = vm.projectRoot();
        string memory path = string(abi.encodePacked(root, CONFIG_PATH));
        string memory json = vm.readFile(path);

        bool rpcPrefixed = stdJson.readBool(
            json,
            string(abi.encodePacked("$.", network, ".uses-rpc-prefix"))
        );
        string memory endpoint = rpcPrefixed
            ? string(
                abi.encodePacked(
                    json.readString(string(abi.encodePacked("$.", network, ".rpc"))),
                    vm.envString("ALCHEMY_KEY")
                )
            )
            : json.readString(string(abi.encodePacked("$.", network, ".rpc")));

        forkId = vm.createSelectFork(
            endpoint,
            json.readUint(string(abi.encodePacked("$.", network, ".", protocol, ".", "test-block")))
        );
        vm.chainId(json.readUint(string(abi.encodePacked("$.", network, ".chain-id"))));
    }

    function setForkFromEnv() internal returns (uint256 forkId) {
        string memory endpoint = vm.envString("FOUNDRY_ETH_RPC_URL");
        uint256 blockNumber = vm.envUint("FOUNDRY_FORK_BLOCK_NUMBER");

        forkId = vm.createSelectFork(endpoint, blockNumber);
    }
}
