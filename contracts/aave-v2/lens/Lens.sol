// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "./MarketsLens.sol";

/// @title Lens.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice This contract exposes an API to query on-chain data related to the Morpho Protocol, its markets and its users.
contract Lens is MarketsLens {
    function initialize(address _morphoAddress, address _addressesProviderAddress)
        external
        initializer
    {
        morpho = IMorpho(_morphoAddress);
        addressesProvider = ILendingPoolAddressesProvider(_addressesProviderAddress);
        pool = ILendingPool(addressesProvider.getLendingPool());
    }
}
