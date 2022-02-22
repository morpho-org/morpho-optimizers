// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "@config/Config.sol";
import "@contracts/aave/PositionsManagerForAaveStorage.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "lib/ds-test/src/test.sol";

// mocks isolating the tested function

contract AaveMock {
    address public asset_;
    uint256 public amount_;
    address public onBehalfOf_;
    uint16 public referralCode_;
    uint256 public timesCalled;

    function deposit(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external {
        asset_ = asset;
        amount_ = amount;
        onBehalfOf_ = onBehalfOf;
        referralCode_ = referralCode;
        timesCalled++;
    }
}

contract MarketsManagerMock {
    uint256 public timesCalled;
    address public marketAddress_;

    function updateSPYs(address _marketAddress) external {
        marketAddress_ = _marketAddress;
        timesCalled++;
    }
}

contract MockERC20 is ERC20 {
    constructor(uint256 initialSupply) ERC20("Mock", "MOCK") {
        _mint(msg.sender, initialSupply);
    }
}

// the test contract inherits the one containing the function so we can assess its effects
// from an internal standpoint

contract TestSupplyERC20ToPool is Config, PositionsManagerForAaveStorage, DSTest {
    AaveMock aaveMock;
    MarketsManagerMock marketsManagerMock;

    constructor() {
        aaveMock = new AaveMock();
        marketsManagerMock = new MarketsManagerMock();
        lendingPool = ILendingPool(address(aaveMock));
        marketsManager = IMarketsManagerForAave(address(marketsManagerMock));
    }

    function test_unit_supplyERC20ToPool(uint256 _amount) public {
        // we do not use a fuzz for poolToken because it can't be the 0 adddress
        address poolToken = address(new MockERC20(0));
        uint256 callsAaveBefore = aaveMock.timesCalled();
        uint256 callsMarketsBefore = marketsManagerMock.timesCalled();
        MockERC20 underlyingToken = new MockERC20(_amount);

        _supplyERC20ToPool(poolToken, underlyingToken, _amount);

        uint256 allowanceAfter = underlyingToken.allowance(address(this), address(lendingPool));

        // checks that the function did what is expected
        require(aaveMock.asset_() == address(underlyingToken), "asset");
        require(aaveMock.onBehalfOf_() == address(this), "onBehalfOf");
        require(marketsManagerMock.marketAddress_() == poolToken, "marketAddress");
        assertEq(aaveMock.amount_(), _amount, "aave amount");
        assertEq(callsAaveBefore + 1, aaveMock.timesCalled(), "calls number aave");
        assertEq(callsMarketsBefore + 1, marketsManagerMock.timesCalled(), "calls number markets");
        assertEq(aaveMock.referralCode_(), 0, "referral code");
        assertEq(allowanceAfter, _amount, "allowance after");
    }
}
