// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./IRewardsManagerForCompound.sol";
import "./compound/ICompound.sol";

import "../libraries/Types.sol";

// Collection of all of Morpho's diamond functions in one interface
interface IMorphoCompound {
    /// MARKETS MANAGER ///

    function createMarket(address _poolTokenAddress) external;

    function updateP2PExchangeRates(address _poolTokenAddress) external;

    function setReserveFactor(address _poolTokenAddress, uint256 _newReserveFactor) external;

    function setNoP2P(address _poolTokenAddress, bool _noP2P) external;

    function getAllMarkets() external view returns (address[] memory marketsCreated_);

    function getMarketData(address _poolTokenAddress)
        external
        view
        returns (
            uint256 supplyP2PExchangeRate_,
            uint256 borrowP2PExchangeRate_,
            uint256 lastUpdateBlockNumber_,
            uint256 supplyP2PDelta_,
            uint256 borrowP2PDelta_,
            uint256 supplyP2PAmount_,
            uint256 borrowP2PAmount_
        );

    function getMarketConfiguration(address _poolTokenAddress)
        external
        view
        returns (bool isCreated_, bool noP2P_);

    function getUpdatedP2PExchangeRates(address _poolTokenAddress)
        external
        view
        returns (uint256 newSupplyP2PExchangeRate, uint256 newBorrowP2PExchangeRate);

    function isCreated(address _market) external view returns (bool isCreated_);

    function reserveFactor(address _market) external view returns (uint256 reserveFactor_);

    function supplyP2PExchangeRate(address _market)
        external
        view
        returns (uint256 supplyP2PExchangeRate_);

    function borrowP2PExchangeRate(address _market)
        external
        view
        returns (uint256 borrowP2PExchangeRate_);

    function lastUpdateBlockNumber(address _market)
        external
        view
        returns (uint256 lastUpdateBlockNumber_);

    function lastPoolIndexes(address _market)
        external
        view
        returns (Types.LastPoolIndexes memory lastPoolIndexes_);

    function noP2P(address _market) external view returns (bool noP2P_);

    /// LENS ///

    function rewadsManager() external view returns (IRewardsManagerForCompound rewardsManager_);

    function comptroller() external view returns (IComptroller comptroller_);

    /// POSITIONS MANAGER ///

    function supply(address _poolTokenAddress, uint256 _amount) external;

    function supply(
        address _poolTokenAddress,
        uint256 _amount,
        uint256 _maxGasToConsume
    ) external;

    function borrow(address _poolTokenAddress, uint256 _amount) external;

    function borrow(
        address _poolTokenAddress,
        uint256 _amount,
        uint256 _maxGasToConsume
    ) external;

    function withdraw(address _poolTokenAddress, uint256 _amount) external;

    function repay(address _poolTokenAddress, uint256 _amount) external;

    function liquidate(
        address _poolTokenBorrowedAddress,
        address _poolTokenCollateralAddress,
        address _borrower,
        uint256 _amount
    ) external;

    /// POSITIONS MANAGER SETTERS AND GETTERS ///

    function setNDS(uint8 _newNDS) external;

    function setMaxGas(Types.MaxGas memory _maxGas) external;

    function setTreasuryVault(address _newTreasuryVaultAddress) external;

    function setIncentivesVault(address _newIncentivesVault) external;

    function setRewardsManager(address _rewardsManagerAddress) external;

    function setPauseStatus(address _poolTokenAddress) external;

    function toggleCompRewardsActivation() external;

    function supplyBalanceInOf(address _poolTokenAddress, address _user)
        external
        view
        returns (uint256 inP2P_, uint256 onPool_);

    function borrowBalanceInOf(address _poolTokenAddress, address _user)
        external
        view
        returns (uint256 inP2P_, uint256 onPool_);

    function claimToTreasury(address _poolTokenAddress) external;

    function claimRewards(address[] calldata _cTokenAddresses, bool _claimMorphoToken) external;
}
