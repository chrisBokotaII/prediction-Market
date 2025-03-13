// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IMultiSig {
    function createTransaction(bytes32 _txId, bytes memory claim) external;
}

contract OptimisticOracleV3 {
    struct Assertion {
        bytes32 identifier;
        address asserter;
        bytes claim;
        uint256 challengeWindow;
        bool settled;
        bool completed;
    }

    bytes32 private assertionId;
    IMultiSig public multiSig;
    address public multiSigAddress;
    mapping(bytes32 => Assertion) public assertions;

    // Events
    event AssertionCreated(
        bytes32 indexed assertionId,
        address indexed asserter,
        bytes claim,
        uint256 challengeWindow
    );
    event AssertionSettled(bytes32 indexed assertionId);
    event AssertionChallenged(
        bytes32 indexed assertionId,
        address indexed challenger
    );

    // Errors
    error AssertionNotFound(bytes32 _assertionId);
    error AssertionNotSettled(bytes32 _assertionId);
    error ChallengedWindowPassed(bytes32 _assertionId);
    error AssertionAlreadySettled();

    // Modifiers

    modifier onlySettledAssertion(bytes32 _assertionId) {
        if (!assertions[_assertionId].settled) {
            revert AssertionNotSettled(_assertionId);
        }
        _;
    }

    constructor(address _multiSig) {
        multiSig = IMultiSig(_multiSig);
        multiSigAddress = _multiSig;
    }
    function assertTruth(
        bytes32 _identifier,
        address asserter,
        bytes memory claim,
        uint256 challengeWindowSeconds
    ) public returns (bytes32 _assertionId) {
        assertionId = keccak256(
            abi.encodePacked(
                _identifier,
                asserter,
                claim,
                challengeWindowSeconds
            )
        );

        assertions[assertionId] = Assertion({
            identifier: _identifier,
            asserter: asserter,
            claim: claim,
            challengeWindow: block.timestamp + challengeWindowSeconds,
            settled: false,
            completed: false
        });
        multiSig.createTransaction(assertionId, claim);
        emit AssertionCreated(
            assertionId,
            asserter,
            claim,
            block.timestamp + challengeWindowSeconds
        );
        return assertionId;
    }

    function settleAssertion(bytes32 _assertionId, bool _verified) external {
        require(msg.sender == multiSigAddress, "not allowes to call this");
        Assertion storage assertion = assertions[_assertionId];
        require(!assertion.settled, AssertionAlreadySettled());

        assertion.settled = _verified;
        assertion.completed = true;
        emit AssertionSettled(_assertionId);
    }

    function getAssertionResult(
        bytes32 _assertionId
    ) external view returns (bool s) {
        require(
            assertions[_assertionId].asserter != address(0),
            AssertionNotFound(_assertionId)
        );
        require(
            assertions[_assertionId].completed,
            " result not available yet"
        );

        s = assertions[_assertionId].settled;
        return s;
    }
}
