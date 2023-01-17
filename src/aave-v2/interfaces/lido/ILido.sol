// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

interface ILido {
    function getPooledEthByShares(uint256 _sharesAmount) external view returns (uint256);

    function submit(address _referral) external payable returns (uint256);
}
