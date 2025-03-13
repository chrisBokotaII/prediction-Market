// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IoptimisticOracleV3 {
    function settleAssertion(bytes32 _assertionId, bool _verified) external;
}

contract MultiSigWallet {
    struct Transaction {
        bytes32 txId;
        bytes claim;
        bool executed;
        uint256 numConfirmations;
        uint256 votingWindow;
        address oracle;
    }

    address public owner;
    uint256 constant requiredSignatures = 3;
    uint256 public Idno;
    address[5] public signers;
    mapping(address => bool) public isSigner;
    mapping(uint256 => mapping(address => bool)) public isSigned;
    mapping(uint256 => Transaction) public transactions;

    event TransactionCreated(
        uint256 indexed Idno,
        bytes32 indexed txId,
        bytes claim
    );
    event TransactionExecuted(uint256 indexed Idno, bytes32 indexed txId);
    event TransactionSigned(uint256 indexed Idno, address indexed signer);

    error TransactionNotFound(uint256 _Idno);
    error TransactionAlreadyExecuted(uint256 _Idno);
    error TransactionAlreadySigned(uint256 _Idno, address _signer);
    error OnlyOwnerCanCallThisFunction();
    error OnlySignerCanCallThisFunction();
    error StillTime();
    error TimePassed();

    modifier onlyOwner() {
        if (msg.sender != owner) {
            revert OnlyOwnerCanCallThisFunction();
        }
        _;
    }
    modifier onlySigner() {
        require(isSigner[msg.sender], OnlySignerCanCallThisFunction());

        _;
    }
    constructor(address[5] memory _signers) {
        owner = msg.sender;
        signers = _signers;
        for (uint256 i = 0; i < 5; i++) {
            isSigner[_signers[i]] = true;
        }
    }

    function createTransaction(bytes32 _txId, bytes memory claim) public {
        Idno++;
        transactions[Idno] = Transaction(
            _txId,
            claim,
            false,
            0,
            block.timestamp + 1 days,
            msg.sender
        );
        emit TransactionCreated(Idno, _txId, claim);
    }

    function signTransaction(uint256 _Idno) public onlySigner {
        Transaction storage transaction = transactions[_Idno];
        require(transaction.txId != bytes32(0), TransactionNotFound(_Idno));
        require(!transaction.executed, TransactionAlreadyExecuted(_Idno));
        require(
            !isSigned[_Idno][msg.sender],
            TransactionAlreadySigned(_Idno, msg.sender)
        );
        require(block.timestamp < transaction.votingWindow, TimePassed());
        isSigned[_Idno][msg.sender] = true;
        transaction.numConfirmations++;
        emit TransactionSigned(_Idno, msg.sender);
    }

    function executeTransaction(uint256 _Idno) public onlyOwner {
        Transaction storage transaction = transactions[_Idno];
        require(transaction.txId != bytes32(0), TransactionNotFound(_Idno));
        require(!transaction.executed, TransactionAlreadyExecuted(_Idno));
        require(block.timestamp > transaction.votingWindow, StillTime());

        if (transaction.numConfirmations < requiredSignatures) {
            IoptimisticOracleV3(transaction.oracle).settleAssertion(
                transaction.txId,
                false
            );
        } else {
            IoptimisticOracleV3(transaction.oracle).settleAssertion(
                transaction.txId,
                true
            );
        }

        transaction.executed = true;
        emit TransactionExecuted(_Idno, transaction.txId);
    }

    function get_Transaction(
        uint256 _Idno
    ) public view returns (Transaction memory t) {
        t = transactions[_Idno];
        return t;
    }
}
