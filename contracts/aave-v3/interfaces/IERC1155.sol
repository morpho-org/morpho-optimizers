// SPDX-License-Identifier: GNU AGPLv3
pragma solidity >=0.5.0;

interface IERC1155 {
    function balanceOf(address _owner, uint256 _id) external view returns (uint256);

    function safeTransferFrom(
        address _from,
        address _to,
        uint256 _id,
        uint256 _value,
        bytes calldata _data
    ) external;
}
