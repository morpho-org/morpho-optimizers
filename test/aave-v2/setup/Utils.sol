// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "@morpho-dao/morpho-utils/math/WadRayMath.sol";

import "@forge-std/Test.sol";

contract Utils is Test {
    using WadRayMath for uint256;

    uint256 internal constant WAD = 1e18;
    uint256 internal constant RAY = 1e27;
    uint256 internal constant SECONDS_PER_YEAR = 365 days;
    uint256 internal constant DEFAULT_LIQUIDATION_CLOSE_FACTOR = 5_000;

    uint256 internal constant PERCENT_BASE = 10_000;
    uint256 internal constant AVERAGE_BLOCK_TIME = 2;

    /// https://github.com/lidofinance/lido-dao/blob/df95e563445821988baf9869fde64d86c36be55f/contracts/0.4.24/Lido.sol#L99-L105
    bytes32 internal constant LIDO_BUFFERED_ETHER = keccak256("lido.Lido.bufferedEther");
    bytes32 internal constant LIDO_DEPOSITED_VALIDATORS =
        keccak256("lido.Lido.depositedValidators");
    bytes32 internal constant LIDO_BEACON_BALANCE = keccak256("lido.Lido.beaconBalance");
    bytes32 internal constant LIDO_BEACON_VALIDATORS = keccak256("lido.Lido.beaconValidators");

    function to6Decimals(uint256 value) internal pure returns (uint256) {
        return value / 1e12;
    }

    function to8Decimals(uint256 value) internal pure returns (uint256) {
        return value / 1e10;
    }

    function testEquality(uint256 _firstValue, uint256 _secondValue) internal {
        assertApproxEqAbs(_firstValue, _secondValue, 20);
    }

    function testEquality(
        uint256 _firstValue,
        uint256 _secondValue,
        string memory err
    ) internal {
        assertApproxEqAbs(_firstValue, _secondValue, 20, err);
    }

    /// @dev calculates compounded interest over a period of time.
    ///   To avoid expensive exponentiation, the calculation is performed using a binomial approximation:
    ///   (1+x)^n = 1+n*x+[n/2*(n-1)]*x^2+[n/6*(n-1)*(n-2)*x^3...
    /// @param _rate The APR to use in the computation.
    /// @param _elapsedTime The amount of time during to get the interest for.
    /// @return results in ray
    function computeCompoundedInterest(uint256 _rate, uint256 _elapsedTime)
        public
        pure
        returns (uint256)
    {
        uint256 rate = _rate / SECONDS_PER_YEAR;

        if (_elapsedTime == 0) return WadRayMath.RAY;

        if (_elapsedTime == 1) return WadRayMath.RAY + rate;

        uint256 ratePowerTwo = rate.rayMul(rate);
        uint256 ratePowerThree = ratePowerTwo.rayMul(rate);

        return
            WadRayMath.RAY +
            rate *
            _elapsedTime +
            (_elapsedTime * (_elapsedTime - 1) * ratePowerTwo) /
            2 +
            (_elapsedTime * (_elapsedTime - 1) * (_elapsedTime - 2) * ratePowerThree) /
            6;
    }

    function bytes32ToAddress(bytes32 _bytes) internal pure returns (address) {
        return address(uint160(uint256(_bytes)));
    }
}
