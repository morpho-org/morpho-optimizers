// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

interface HEVM {
	function warp(uint x) external;
	function roll(uint x) external;
	function store(address c, bytes32 loc, bytes32 val) external;
	function load(address c, bytes32 loc) external returns (bytes32 val);
	function sign(uint sk, bytes32 digest) external returns (uint8 v, bytes32 r, bytes32 s);
	function addr(uint sk) external returns (address addr);
	function ffi(string[] calldata) external returns (bytes memory);
}
