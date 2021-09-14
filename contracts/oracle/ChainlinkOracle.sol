pragma solidity 0.8.7;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract ChainlinkOracle {
    AggregatorV3Interface internal priceFeed;

    /**
     * Network: Mainnet
     * Aggregator: DAI / ETH
     * Address: 0x773616E4d11A78F511299002da57A0a94577F1f4
     */
    constructor() {
        priceFeed = AggregatorV3Interface(0x773616E4d11A78F511299002da57A0a94577F1f4);
    }

    /**
     * @return The price of DAI expressed in ETH.
     */
    function consult() public view returns (int256) {
        (
            uint80 roundID,
            int256 price,
            uint256 startedAt,
            uint256 timeStamp,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();
        return price;
    }
}
