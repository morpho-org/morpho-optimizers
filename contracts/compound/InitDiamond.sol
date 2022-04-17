// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {LibStorage, MarketsStorage} from "./libraries/LibStorage.sol";
import "./interfaces/compound/ICompound.sol";
import "./interfaces/IInterestRates.sol";

contract InitDiamond {
  struct Args {
    IComptroller comptroller;
    IInterestRates interestRates;
  }

  function init(Args memory _args) external {
    MarketsStorage storage ms = LibStorage.marketsStorage();
    ms.comptroller = _args.comptroller;
    ms.interestRates = _args.interestRates;
  }
}