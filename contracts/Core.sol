pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";

// TODO: add only proxy
// No constructor here as it will be called by a Proxy
// TODO resolve issue when token is not allowed anymore
// TODO abstract function so that to perform a delegate call inside a unique function but with the right function selector
contract Core {
    address owner;
    mapping(address => bool) tokenToLendAllowed;
    mapping(address => bool) tokenToStakeAllowed;
    mapping(address => address) tokenToTokenModule; // To know if tokens is related to Compound or Aave.
    mapping(address => bool) modules; // modules linked to Compoud or Aave.
    mapping(address => mapping(address => LendingBalance)) lendingBalanceOf;
    mapping(address => mapping(address => uint256)) collateralBalanceOf;
    mapping(address => mapping(address => uint256)) borrowingBalanceOf;
    mapping(address => mapping(address => uint256)) stakingBalanceOf;

    struct LendingBalance {
        uint256 total;
        uint256 used;
    }

    // TODO: replace by only Governance
    modifier onlyOwner {
        require(msg.sender == owner, "Only owner");
        _;
    }

    // function _delegate(address implementation) internal virtual {
    //     // solhint-disable-next-line no-inline-assembly
    //     assembly {
    //         // Copy msg.data. We take full control of memory in this inline assembly
    //         // block because it will not return to Solidity code. We overwrite the
    //         // Solidity scratch pad at memory position 0.
    //         calldatacopy(0, 0, calldatasize())

    //         // Call the implementation.
    //         // out and outsize are 0 because we don't know the size yet.
    //         let result := delegatecall(gas(), implementation, 0, calldatasize(), 0, 0)

    //         // Copy the returned data.
    //         returndatacopy(0, 0, returndatasize())

    //         switch result
    //         // delegatecall returns 0 on error.
    //         case 0 { revert(0, returndatasize()) }
    //         default { return(0, returndatasize()) }
    //     }
    // }

    function stake(uint256 _amount, address _token) external {
        require(tokenToStakeAllowed[_token], "");
        require(_amount > 0, "Amount cannot be 0");
        IERC20(_token).transferFrom(msg.sender, address(this), _amount);
        // TODO: write logic
    }

    function lend(
        uint256 _amount,
        address _token,
        address _module
    ) external {
        require(tokenToLendAllowed[_token], "");
        (bool success, bytes memory result) = _module.delegatecall(
            abi.encodeWithSignature("lend(uint256,address)", _amount, _token)
        );
        require(success, "");
    }

    function borrow(
        uint256 _amount,
        address _token,
        address _module
    ) external {
        require(tokenToLendAllowed[_token], "");
        (bool success, bytes memory result) = _module.delegatecall(
            abi.encodeWithSignature("borrow(uint256,address)", _amount, _token)
        );
        require(success, "");
    }

    function payback(
        uint256 _amount,
        address _token,
        address _module
    ) external {
        require(tokenToLendAllowed[_token], "");
        (bool success, bytes memory result) = _module.delegatecall(
            abi.encodeWithSignature("payback(uint256,address)", _amount, _token)
        );
        require(success, "");
    }

    function cashOut(
        uint256 _amount,
        address _token,
        address _module
    ) external {
        require(tokenToLendAllowed[_token], "");
        (bool success, bytes memory result) = _module.delegatecall(
            abi.encodeWithSignature("cashOut(uint256,address)", _amount, _token)
        );
        require(success, "");
    }

    function cashOutAll(address _token, address _module) external {
        require(tokenToLendAllowed[_token], "");
        (bool success, bytes memory result) = _module.delegatecall(
            abi.encodeWithSignature("cashOutAll(address)", _token)
        );
        require(success, "");
    }

    function setTokenAllowed(address _token) external onlyOwner() {
        tokenToLendAllowed[_token] = !tokenToLendAllowed[_token];
    }

    function setModule(address _module) external onlyOwner() {
        modules[_module] = !modules[_module];
    }

    function pauseModule() external onlyOwner() {}

    function unPauseModule() external onlyOwner() {}

    function setTokenToTokenModule() external onlyOwner() {}
}
