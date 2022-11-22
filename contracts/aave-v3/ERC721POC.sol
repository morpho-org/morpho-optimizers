// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.10;

import "./interfaces/IERC1155.sol";

contract ERC721POC {
    IERC1155 public immutable MORPHO;
    address public immutable POOL_TOKEN;

    enum TokenType {
        SUPPLY_POOL,
        SUPPLY_P2P,
        BORROW_POOL,
        BORROW_P2P
    }

    error SomethingWentWrong();

    constructor(address _morpho, address _poolToken) {
        MORPHO = IERC1155(_morpho);
        POOL_TOKEN = _poolToken;
    }

    function balanceOf(address _owner) external view returns (uint256 balance) {
        for (uint256 i; i < 4; i++) {
            TokenType tokenType = TokenType(i);
            if (
                MORPHO.balanceOf(_owner, _getIdFromPoolTokenAndSupplyType(POOL_TOKEN, tokenType)) >
                0
            ) balance++;
        }
    }

    // Can't think of a sensible way to implement this.
    function ownerOf(uint256 _id) external view returns (uint256) {}

    function transferFrom(
        address _from,
        address _to,
        uint256 _id
    ) external payable {
        MORPHO.safeTransferFrom(_from, _to, _id, MORPHO.balanceOf(_from, _id), "");
    }

    function _getPoolTokenAndSupplyTypeFromId(uint256 _id)
        internal
        pure
        returns (address poolToken, TokenType tokenType)
    {
        poolToken = address(uint160(_id));
        uint256 firstTwoBits = _id / (2**254);
        if (firstTwoBits == 0) {
            tokenType = TokenType.SUPPLY_POOL;
        } else if (firstTwoBits == 1) {
            tokenType = TokenType.SUPPLY_P2P;
        } else if (firstTwoBits == 2) {
            tokenType = TokenType.BORROW_POOL;
        } else if (firstTwoBits == 3) {
            tokenType = TokenType.BORROW_P2P;
        } else revert SomethingWentWrong();
    }

    function _getIdFromPoolTokenAndSupplyType(address _poolToken, TokenType _tokenType)
        internal
        pure
        returns (uint256 id)
    {
        // Enums are just uints behind the scenes, so convert it to a uint and do the appropriate multiplication.
        id = uint256(_tokenType) * (2**254);
        id += uint256(uint160(_poolToken));
    }
}
