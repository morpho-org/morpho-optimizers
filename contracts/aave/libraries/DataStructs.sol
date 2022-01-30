// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAToken} from "../interfaces/aave/IAToken.sol";
import "../interfaces/IMatchingEngineManager.sol";
import "../interfaces/IMarketsManagerForAave.sol";
import "../interfaces/aave/ILendingPool.sol";

library DataStructs {
    struct SupplyBalance {
        uint256 inP2P; // In supplier's p2pUnit, a unit that grows in value, to keep track of the interests earned when users are in P2P.
        uint256 onPool; // In aToken.
    }

    struct BorrowBalance {
        uint256 inP2P; // In borrower's p2pUnit, a unit that grows in value, to keep track of the interests paid when users are in P2P.
        uint256 onPool; // In adUnit, a unit that grows in value, to keep track of the debt increase when users are in Aave. Multiply by current borrowIndex to get the underlying amount.
    }

    struct CommonParams {
        uint256 amount; // The amount of underlying token (in underlying).
        address poolTokenAddress; // The address of the pool token.
        IERC20 underlyingToken; // The underlying token.
        ILendingPool lendingPool; // Thes Aave's Lending Pool.
        IMarketsManagerForAave marketsManagerForAave; // The Morpho's Markets Manager.
        IMatchingEngineManager matchingEngineManager; // The Morpho's Maching Engine Manager.
    }
}
