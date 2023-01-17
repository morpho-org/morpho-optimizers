// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DummyCEth {
    // all fields are made public for easier spec usage
    uint256 public _borrowRate;
    uint256 public _borrowIndex;
    uint256 public _borrowRatePerBlock;

    uint256 public _exchangeRateStored;
    mapping(uint256 => uint256) public _exchangeRate;

    mapping(address => uint256) public _balances; // debt of the poolToken to the user
    mapping(address => uint256) public _userDebt; // debt of the users

    uint256 _supply; // total supply of the pool

    uint256 public _supplyRatePerBlock;

    // not used at the moment
    function accrueInterest() external returns (uint256) {
        return 0;
    }

    // arbitrary returns
    function borrowRate() external returns (uint256) {
        return _borrowRate;
    }

    function borrowIndex() external returns (uint256) {
        return _borrowIndex;
    }

    function borrowBalanceStored(address account) external returns (uint256) {
        return _userDebt[account];
    }

    // currently 1:1 ratio for simplicity, change as you would like
    function mint() external payable returns (uint256) {
        uint256 amount = msg.value;
        _supply += amount;
        _balances[msg.sender] += amount;
        return 0;
    }

    // will simulate exchange rate changing over time
    function exchangeRateCurrent() external returns (uint256) {
        return 1; // hopefully to help with timeouts
        // return _exchangeRate[block.timestamp];
    }

    function exchangeRateStored() external view returns (uint256) {
        return 1;
        // return _exchangeRateStored;
    }

    function supplyRatePerBlock() external returns (uint256) {
        return _supplyRatePerBlock;
    }

    // removing your balance from the pool balance goes down by amount
    // supply goes down by amount
    // transfer from the underlying to the msg.sender
    function redeem(uint256 amount) external returns (uint256) {
        require(amount <= _balances[msg.sender]);
        _balances[msg.sender] -= amount;
        _supply -= amount;
        payable(msg.sender).transfer(amount);
        return 0;
    }

    // same as redeem since the ratio is 1:1
    function redeemUnderlying(uint256 amount) external returns (uint256) {
        require(amount <= _balances[msg.sender]);
        _balances[msg.sender] -= amount;
        _supply -= amount;
        payable(msg.sender).transfer(amount);
        return 0;
    }

    function balanceOf(address account) external returns (uint256) {
        return _balances[account];
    }

    // The user's underlying balance, representing their assets in the protocol, is equal to the user's cToken
    // balance multiplied by the Exchange Rate.
    function balanceOfUnderlying(address account) external returns (uint256) {
        return _balances[account];
    }

    function borrow(uint256 amount) external returns (uint256) {
        require(_supply >= amount);
        _userDebt[msg.sender] += amount;
        _supply -= amount;
        payable(msg.sender).transfer(amount);
        return 0;
    }

    function borrowRatePerBlock() external view returns (uint256) {
        return _borrowRatePerBlock;
    }

    // did not impliment interest, if you do please keep it simple to avoid timeouts
    function borrowBalanceCurrent(address account) external returns (uint256) {
        return _userDebt[account];
    }

    function repayBorrow() external payable returns (uint256) {
        uint256 amount = msg.value;
        require(amount <= _userDebt[msg.sender]);
        _userDebt[msg.sender] -= amount;
        _supply += amount;
        return 0;
    }

    function supply() external view returns (uint256) {
        return _supply;
    }
}
