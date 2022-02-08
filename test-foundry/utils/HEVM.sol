// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

interface HEVM {
    // Sets the block timestamp to x.
    function warp(uint256 x) external;

    // Sets the block number to x.
    function roll(uint256 x) external;

    // Sets the slot loc of contract c to val.
    function store(
        address c,
        bytes32 loc,
        bytes32 val
    ) external;

    // Reads the slot loc of contract c.
    function load(address c, bytes32 loc) external returns (bytes32 val);

    // Signs the digest using the private key sk. Note that signatures produced via hevm.sign will leak the private key.
    function sign(uint256 sk, bytes32 digest)
        external
        returns (
            uint8 v,
            bytes32 r,
            bytes32 s
        );

    // Derives an ethereum address from the private key sk. Note that hevm.addr(0) will fail with BadCheatCode as 0 is an invalid ECDSA private key.
    function addr(uint256 sk) external returns (address addr);

    // Executes the arguments as a command in the system shell and returns stdout. Expects abi encoded values to be returned from the shell or an error will be thrown.
    // Note that this cheatcode means test authors can execute arbitrary code on user machines as part of a call to dapp test,
    // for this reason all calls to ffi will fail unless the --ffi flag is passed.
    function ffi(string[] calldata) external returns (bytes memory);

    // Sets the *next* call's msg.sender to be the input address
    function prank(address) external;

    // Sets all subsequent calls' msg.sender to be the input address until `stopPrank` is called
    function startPrank(address) external;

    // Resets subsequent calls' msg.sender to be `address(this)`
    function stopPrank() external;

    // Sets an address' balance, (who, newBalance)
    function deal(address, uint256) external;

    // Sets an address' code, (who, newCode)
    function etch(address, bytes calldata) external;

    // Expects an error on next call
    function expectRevert(bytes calldata) external;

    // Record all storage reads and writes
    function record() external;

    // Gets all accessed reads and write slot from a recording session, for a given address
    function accesses(address) external returns (bytes32[] memory reads, bytes32[] memory writes);

    // Prepare an expected log with (bool checkTopic1, bool checkTopic2, bool checkTopic3, bool checkData).
    // Call this function, then emit an event, then call a function. Internally after the call, we check if
    // logs were emitted in the expected order with the expected topics and data (as specified by the booleans)
    function expectEmit(
        bool,
        bool,
        bool,
        bool
    ) external;

    // Mocks a call to an address, returning specified data.
    // Calldata can either be strict or a partial match, e.g. if you only
    // pass a Solidity selector to the expected calldata, then the entire Solidity
    // function will be mocked.
    function mockCall(
        address,
        bytes calldata,
        bytes calldata
    ) external;

    // Clears all mocked calls
    function clearMockedCalls() external;

    // Expect a call to an address with the specified calldata.
    // Calldata can either be strict or a partial match
    function expectCall(address, bytes calldata) external;

    // Gets the code from an artifact file. Takes in the relative path to the json file
    function getCode(string calldata) external returns (bytes memory);

    // Labels an address in call traces
    function label(address, string calldata) external;
}
