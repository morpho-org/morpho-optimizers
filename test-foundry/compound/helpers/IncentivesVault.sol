// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "@rari-capital/solmate/src/utils/SafeTransferLib.sol";

contract IncentivesVault {
    using SafeTransferLib for ERC20;

    address public immutable morphoToken;
    address public immutable positionsManager;

    constructor(address _positionsManager, address _morphoToken) {
        positionsManager = _positionsManager;
        morphoToken = _morphoToken;
    }

    function sendMorphoRewards(address _to, uint256 _amount) external {
        require(msg.sender == positionsManager);
        ERC20(morphoToken).transfer(_to, _amount);
    }
}
