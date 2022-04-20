// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./interfaces/IMarketsManagerForCompound.sol";
import "./interfaces/compound/ICompound.sol";

import {LibStorage, MarketsStorage, PositionsStorage} from "./libraries/LibStorage.sol";
import "./libraries/Types.sol";

contract InitDiamond {
    struct Args {
        IComptroller comptroller;
        uint8 NDS;
        address cEth;
        address wEth;
        Types.MaxGas maxGas;
    }

    function init(Args memory _args) external {
        MarketsStorage storage ms = LibStorage.marketsStorage();
        ms.comptroller = _args.comptroller;

        PositionsStorage storage ps = LibStorage.positionsStorage();
        ps.maxGas = _args.maxGas;
        ps.NDS = _args.NDS;
        ps.cEth = _args.cEth;
        ps.wEth = _args.wEth;
    }
}
