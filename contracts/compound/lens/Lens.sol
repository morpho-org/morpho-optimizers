// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "./RewardsLens.sol";

/// @title Lens.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice This contract exposes an API to query on-chain data related to the Morpho Protocol, its markets and its users.
contract Lens is RewardsLens {
    function initialize(address _morphoAddress) external initializer {
        morpho = IMorpho(_morphoAddress);
        comptroller = IComptroller(morpho.comptroller());
        rewardsManager = IRewardsManager(morpho.rewardsManager());
    }
}
