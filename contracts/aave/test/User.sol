// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "ds-test/test.sol";
import "../PositionsManagerForAave.sol";
import "../MarketsManagerForAave.sol";


contract User {

	PositionsManagerForAave internal pm;
	MarketsManagerForAave internal mm;

	constructor(PositionsManagerForAave _pm, MarketsManagerForAave _mm) {
		pm = _pm;
		mm = _mm;
	}
	
	receive() payable external {}


	function approve(address _token, address _spender, uint256 _amount) external {
		IERC20(_token).approve(_spender, _amount);
	}
	
	
	function pmSupply(address _poolTokenAddress, uint256 _amount) external {
		pm.supply(_poolTokenAddress, _amount);
	}
}
