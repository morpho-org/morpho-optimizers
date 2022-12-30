// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import {Morpho} from "src/compound/Morpho.sol";
import {ILens} from "src/compound/lens/interfaces/ILens.sol";

import {Config} from "config/compound/Config.sol";
import {BaseConfigProd} from "config/prod/BaseConfigProd.sol";

contract ConfigProd is Config, BaseConfigProd {
    ILens constant lens = ILens(0x930f1b46e1D081Ec1524efD95752bE3eCe51EF67);
    Morpho constant morpho = Morpho(payable(0x8888882f8f843896699869179fB6E4f7e3B58888));
}
