// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./interfaces/compound/ICompound.sol";
import "./interfaces/IPositionsManagerForCompound.sol";

import "./libraries/CompoundMath.sol";

import "@openzeppelin/contracts/access/Ownable.sol";

abstract contract RewardsManagerForCompound is Ownable {
    using CompoundMath for uint256;

    /// STORAGE ///

    uint224 public constant COMP_INITIAL_INDEX = 1e36;
    uint256 public constant COMP_CLAIM_THRESHOLD = 0.001e18;

    mapping(address => uint256) public userUnclaimedCompRewards; // The unclaimed rewards of the user.
    mapping(address => mapping(address => uint256)) public compSupplierIndex;
    mapping(address => mapping(address => uint256)) public compBorrowerIndex;
    mapping(address => IComptroller.CompMarketState) public localCompSupplyState;
    mapping(address => IComptroller.CompMarketState) public localCompBorrowState;

    IPositionsManagerForCompound public immutable positionsManager;
    IComptroller public immutable comptroller;

    /// EVENTS ///

    /// ERRORS ///

    /// @notice Thrown when only the positions manager can call the function.
    error OnlyPositionsManager();

    /// @notice Thrown when an invalid asset is passed to accrue rewards.
    error InvalidAsset();

    /// MODIFIERS ///

    /// @notice Prevents a user to call function allowed for the positions manager only.
    modifier onlyPositionsManager() {
        if (msg.sender != address(positionsManager)) revert OnlyPositionsManager();
        _;
    }

    /// CONSTRUCTOR ///

    /// @notice Constructs the RewardsManager contract.
    /// @param _positionsManager The `positionsManager`.
    /// @param _comptroller The `comptroller`.
    constructor(IPositionsManagerForCompound _positionsManager, IComptroller _comptroller) {
        positionsManager = _positionsManager;
        comptroller = _comptroller;
    }

    /// EXTERNAL ///

    /// @notice Accrues unclaimed rewards for the given assets and returns the total unclaimed rewards.
    /// @param _cTokenAddresses The assets for which to accrue rewards (aToken or variable debt token).
    /// @param _user The address of the user.
    function claimRewards(address[] calldata _cTokenAddresses, address _user)
        external
        onlyPositionsManager
        returns (uint256 amountToClaim)
    {
        amountToClaim = accrueUserUnclaimedRewards(_cTokenAddresses, _user);
        if (amountToClaim > 0) userUnclaimedCompRewards[_user] = 0;
    }

    function getUserUnclaimedRewards(address[] calldata _cTokenAddresses, address _user)
        external
        returns (uint256 unclaimedRewards)
    {
        unclaimedRewards = userUnclaimedCompRewards[_user];

        for (uint256 i; i < _cTokenAddresses.length; i++) {
            address cTokenAddress = _cTokenAddresses[i];

            unclaimedRewards += _accrueSupplierComp(
                _user,
                cTokenAddress,
                positionsManager.supplyBalanceInOf(cTokenAddress, _user).onPool
            );
            unclaimedRewards += _accrueBorrowerComp(
                _user,
                cTokenAddress,
                positionsManager.borrowBalanceInOf(cTokenAddress, _user).onPool
            );
        }
    }

    /// @notice Updates the unclaimed rewards of an user.
    /// @param _user The address of the user.
    /// @param _cTokenAddress The address of the reference asset of the distribution (aToken or variable debt token).
    /// @param _userBalance The user balance of tokens in the distribution.
    function accrueUserSupplyUnclaimedRewards(
        address _user,
        address _cTokenAddress,
        uint256 _userBalance
    ) external onlyPositionsManager {
        _updateSupplyIndex(_cTokenAddress);
        userUnclaimedCompRewards[_user] += _accrueSupplierComp(_user, _cTokenAddress, _userBalance);
    }

    /// @notice Updates the unclaimed rewards of an user.
    /// @param _user The address of the user.
    /// @param _cTokenAddress The address of the reference asset of the distribution (aToken or variable debt token).
    /// @param _userBalance The user balance of tokens in the distribution.
    function accrueUserBorrowUnclaimedRewards(
        address _user,
        address _cTokenAddress,
        uint256 _userBalance
    ) external onlyPositionsManager {
        _updateBorrowIndex(_cTokenAddress);
        userUnclaimedCompRewards[_user] += _accrueBorrowerComp(_user, _cTokenAddress, _userBalance);
    }

    /// PUBLIC ///

    /// @notice Accrues unclaimed rewards for the given assets and returns the total unclaimed rewards.
    /// @param _cTokenAddresses The assets for which to accrue rewards (aToken or variable debt token).
    /// @param _user The address of the user.
    /// @return unclaimedRewards The user unclaimed rewards.
    function accrueUserUnclaimedRewards(address[] calldata _cTokenAddresses, address _user)
        public
        returns (uint256 unclaimedRewards)
    {
        unclaimedRewards = userUnclaimedCompRewards[_user];

        for (uint256 i; i < _cTokenAddresses.length; i++) {
            address cTokenAddress = _cTokenAddresses[i];

            _updateSupplyIndex(cTokenAddress);
            unclaimedRewards += _accrueSupplierComp(
                _user,
                cTokenAddress,
                positionsManager.supplyBalanceInOf(cTokenAddress, _user).onPool
            );

            _updateBorrowIndex(cTokenAddress);
            unclaimedRewards += _accrueBorrowerComp(
                _user,
                cTokenAddress,
                positionsManager.borrowBalanceInOf(cTokenAddress, _user).onPool
            );
        }

        userUnclaimedCompRewards[_user] = unclaimedRewards;
    }

    /// INTERNAL ///

    function _updateSupplyIndex(address _cTokenAddress) internal {
        IComptroller.CompMarketState storage localSupplyState = localCompSupplyState[
            _cTokenAddress
        ];
        uint256 blockNumber = block.number;

        if (localSupplyState.block == blockNumber) return;
        else {
            IComptroller.CompMarketState memory supplyState = comptroller.compSupplyState(
                _cTokenAddress
            );

            if (supplyState.block == blockNumber)
                localCompSupplyState[_cTokenAddress] = supplyState;
            else {
                uint256 supplySpeed = comptroller.compSpeeds(_cTokenAddress);
                uint256 deltaBlocks = blockNumber - uint256(localSupplyState.block);

                if (supplySpeed > 0) {
                    uint256 supplyTokens = ICToken(_cTokenAddress).totalSupply();
                    uint256 compAccrued = deltaBlocks * supplySpeed;
                    uint256 ratio = supplyTokens > 0 ? (compAccrued * 1e36) / supplyTokens : 0;
                    uint256 index = localSupplyState.index + ratio;
                    localCompSupplyState[_cTokenAddress] = IComptroller.CompMarketState({
                        index: CompoundMath.safe224(index, "new index exceeds 224 bits"),
                        block: CompoundMath.safe32(blockNumber, "block number exceeds 32 bits")
                    });
                } else
                    localSupplyState.block = CompoundMath.safe32(
                        blockNumber,
                        "block number exceeds 32 bits"
                    );
            }
        }
    }

    function _updateBorrowIndex(address _cTokenAddress) internal {
        IComptroller.CompMarketState storage localBorrowState = localCompBorrowState[
            _cTokenAddress
        ];
        uint256 blockNumber = block.number;

        if (localBorrowState.block == blockNumber) return;
        else {
            IComptroller.CompMarketState memory borrowState = comptroller.compBorrowState(
                _cTokenAddress
            );

            if (borrowState.block == blockNumber) {
                localBorrowState.block = borrowState.block;
                localBorrowState.index = borrowState.index;
            } else {
                uint256 borrowSpeed = comptroller.compSpeeds(_cTokenAddress);
                uint256 deltaBlocks = blockNumber - uint256(borrowState.block);

                if (borrowSpeed > 0) {
                    uint256 borrowAmount = ICToken(_cTokenAddress).totalBorrows().div(
                        ICToken(_cTokenAddress).borrowIndex()
                    );
                    uint256 compAccrued = deltaBlocks * borrowSpeed;
                    uint256 ratio = borrowAmount > 0 ? (compAccrued * 1e36) / borrowAmount : 0;
                    uint256 index = borrowState.index + ratio;
                    localBorrowState.index = CompoundMath.safe224(
                        index,
                        "new index exceeds 224 bits"
                    );
                    localBorrowState.block = CompoundMath.safe32(
                        blockNumber,
                        "block number exceeds 32 bits"
                    );
                } else
                    localBorrowState.block = CompoundMath.safe32(
                        blockNumber,
                        "block number exceeds 32 bits"
                    );
            }
        }
    }

    function _accrueSupplierComp(
        address _cTokenAddress,
        address _supplier,
        uint256 _balance
    ) internal returns (uint256) {
        IComptroller.CompMarketState memory localSupplyState = localCompSupplyState[_cTokenAddress];
        uint256 supplyIndex = localSupplyState.index;
        uint256 supplierIndex = compSupplierIndex[_cTokenAddress][_supplier];
        compSupplierIndex[_cTokenAddress][_supplier] = supplyIndex;

        if (supplierIndex == 0 && supplyIndex > 0) supplierIndex = COMP_INITIAL_INDEX;

        return _balance * (supplyIndex - supplierIndex);
    }

    function _accrueBorrowerComp(
        address _cTokenAddress,
        address _borrower,
        uint256 _balance
    ) internal returns (uint256) {
        IComptroller.CompMarketState memory localBorrowState = localCompBorrowState[_cTokenAddress];
        uint256 borrowIndex = localBorrowState.index;
        uint256 borrowerIndex = compBorrowerIndex[_cTokenAddress][_borrower];
        compBorrowerIndex[_cTokenAddress][_borrower] = borrowIndex;

        if (borrowerIndex > 0) return _balance * (borrowIndex - borrowerIndex);
        else return 0;
    }
}
