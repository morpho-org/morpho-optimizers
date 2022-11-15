// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.10;

import {Modifiers} from "../abstract/Modifiers.sol";
import {LibMarkets} from "../libraries/LibMarkets.sol";
import {LibIndexes} from "../libraries/LibIndexes.sol";
import {Math, EventsAndErrors as E} from "../libraries/Libraries.sol";

contract EntryPositionsManager is Modifiers {}
