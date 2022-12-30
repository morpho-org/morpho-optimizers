// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import {Morpho} from "src/aave-v2/Morpho.sol";
import {ILens} from "src/aave-v2/lens/interfaces/ILens.sol";

import {Config} from "config/aave-v2/Config.sol";
import {BaseConfigProd} from "config/prod/BaseConfigProd.sol";

contract ConfigProd is Config, BaseConfigProd {
    ILens constant lens = ILens(0x507fA343d0A90786d86C7cd885f5C49263A91FF4);
    Morpho constant morpho = Morpho(0x777777c9898D384F785Ee44Acfe945efDFf5f3E0);
}
