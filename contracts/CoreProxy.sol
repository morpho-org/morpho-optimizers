pragma solidity ^0.8.0;

import "@openzeppelin/contracts/proxy/Proxy.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
// https://docs.openzeppelin.com/contracts/4.x/api/proxy#UUPSUpgradeable


contract CoreProxy is UUPSUpgradeable, Ownable {

	function _authorizeUpgrade(address) internal override onlyOwner {}
}