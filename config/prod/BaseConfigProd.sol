// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";

contract BaseConfigProd {
    address constant morphoDao = 0xcBa28b38103307Ec8dA98377ffF9816C164f9AFa;
    ProxyAdmin constant proxyAdmin = ProxyAdmin(0x99917ca0426fbC677e84f873Fb0b726Bb4799cD8);
    ERC20 constant morphoToken = ERC20(0x9994E35Db50125E0DF82e4c2dde62496CE330999);
}
