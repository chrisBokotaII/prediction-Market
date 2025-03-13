// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IoptimisticOracleV3 {
    function assertTruth(
        bytes32 identifier,
        address asserter,
        bytes memory claim,
        uint256 challengeWindowSeconds
    ) external returns (bytes32 _assertionId);

    function getAssertionResult(
        bytes32 _assertionId
    ) external view returns (bool);
}

contract VerifyOracle {
    IoptimisticOracleV3 public oracle;

    // Events
    event AssertionCreated(
        bytes32 indexed _assertionId,
        address indexed _asserter,
        bytes _claim,
        uint256 challengeWindowSeconds
    );
    event AssertionSettled(bytes32 indexed assertionId, bool verified);

    // Errors
    error OnlyMarketCanCallThis();
    error AssertionAlreadyVerified(bytes32 _assertionId);

    constructor(address _oracle) {
        oracle = IoptimisticOracleV3(_oracle);
    }

    function assertQuestion(
        address asserter,
        bytes memory claim
    ) public returns (bytes32 _assertionId) {
        uint256 challengeWindowSeconds = 2 * 60 * 60;
        _assertionId = oracle.assertTruth(
            keccak256(abi.encodePacked("identifier")),
            asserter,
            claim,
            challengeWindowSeconds
        );

        emit AssertionCreated(
            _assertionId,
            asserter,
            claim,
            challengeWindowSeconds
        );
        return _assertionId;
    }

    function getResult(bytes32 _assertionId) external view returns (bool) {
        return oracle.getAssertionResult(_assertionId);
    }
}
