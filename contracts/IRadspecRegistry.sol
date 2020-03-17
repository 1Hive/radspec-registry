pragma solidity ^0.5.8;

import "@aragon/os/contracts/apps/AragonApp.sol";

import "@aragon/court/contracts/arbitration/IArbitrable.sol";
import "@aragon/court/contracts/arbitration/IArbitrator.sol";

import "@aragon/os/contracts/lib/math/SafeMath.sol";
import "@aragon/os/contracts/lib/math/SafeMath64.sol";

// TODO Add pull fees method

contract RadspecRegistry is IArbitrable, AragonApp {
    using SafeMath for uint256;
    using SafeMath64 for uint64;

    // Roles
    bytes32 public constant SET_BENEFICIARY_ROLE = keccak256("SET_BENEFICIARY_ROLE");
    bytes32 public constant SET_FEE_PERCENTAGE_ROLE = keccak256("SET_FEE_PERCENTAGE_ROLE");
    bytes32 public constant SET_ARBITRATOR_ROLE = keccak256("SET_ARBITRATOR_ROLE");
    bytes32 public constant STAKED_UPSERT_ENTRY_ROLE = keccak256("STAKED_UPSERT_ENTRY_ROLE");
    bytes32 public constant UPSERT_ENTRY_ROLE = keccak256("UPSERT_ENTRY_ROLE");
    bytes32 public constant REMOVE_ENTRY_ROLE = keccak256("REMOVE_ENTRY_ROLE");

    // Error codes
    string public constant ERROR_FEE_PCT_TOO_BIG = "ERROR_FEE_PCT_TOO_BIG";
    string public constant ERROR_STAKE_TOO_LOW = "ERROR_STAKE_TOO_LOW";
    string public constant ERROR_DISPUTE_EXISTS = "ERROR_DISPUTE_EXISTS";
    string public constant ERROR_ENTRY_DOESNT_EXIST = "ERROR_ENTRY_DOESNT_EXIST";
    string public constant ERROR_ENTRY_DOESNT_EXIST = "ERROR_ENTRY_DOESNT_EXIST";

    // Misc constants
    uint64 public constant PCT_BASE = 10 ** 18; // 0% = 0; 1% = 10^16; 100% = 10^18

    // Storage
    /**
     * A registry entry.
     */
    struct Entry {
        uint256 stake;
        string cid;
        address submitter;
    }

    /**
     * A nested mapping of scope -> sig -> entry.
     */
    mapping (address => mapping(bytes4 => Entry)) internal entries;

    /**
     * A mapping of entries to dispute IDs.
     */
    mapping (address => mapping(bytes4 => uint256)) internal disputes;

    IArbitrator public arbitrator;
    address public beneficiary;
    uint64 public feePct;
    uint256 public pendingFees;

    /**
     * @dev Emitted when an entry is inserted or updated.
     * @param scope
     *        The scope of the entry.
     *        If the scope is the zero address, then the entry is global.
     * @param sig
     *        The signature of the method the entry is describing.
     * @param submitter
     *        The address that upserted the entry.
     * @param stake
     *        The stake that was used to upsert the entry.
     * @param cid
     *        The IPFS CID of the file containing the Radspec description.
     */
    event EntryUpserted(
        address indexed scope,
        bytes4 indexed sig,
        address submitter,
        uint256 stake,
        string cid
    );

    /**
     * @dev Emitted when an entry is removed.
     * @param scope
     *        The scope of the entry.
     *        If the scope is the zero address, then the entry is global.
     * @param sig
     *        The signature of the method the entry is describing.
     */
    event EntryRemoved(
        address indexed scope,
        bytes4 indexed sig
    );

    /**
     * @dev Emitted when a dispute for an entry is created.
     * @param scope
     *        The scope of the entry.
     *        If the scope is the zero address, then the entry is global.
     * @param sig
     *        The signature of the method the entry is describing.
     * @param disputeId
     *        The Aragon Court dispute ID for the dispute.
     */
    event EntryDisputed(address indexed scope, bytes4 indexed sig, uint256 disputeId);

    /**
     * @dev Initializes the registry.
     * @param _arbitrator The arbitrator of the registry.
     * @param _feePct The percentage of stakes sent to `_beneficiary`
     * @param _beneficiary The beneficiary of registry fees
     */
    function initialize(IArbitrator _arbitrator, uint64 _feePct, address _beneficiary)
        external
        onlyInit
    {
        initialized();

        require(_feePct < PCT_BASE, ERROR_FEE_PCT_TOO_BIG);

        arbitrator = _arbitrator;
        feePct = _feePct;
        beneficiary = _beneficiary;
    }

    /**
     * @dev Set the arbitrator of the registry.
     * @param _arbitrator The arbitrator of the registry.
     */
    function setArbitrator(IArbitrator _arbitrator)
        external
        auth(SET_ARBITRATOR_ROLE)
    {
        arbitrator = _arbitrator;
    }

    /**
     * @dev Set fee perecentage of the registry.
     * @param _feePct The percentage of stakes sent to `_beneficiary`
     */
    function setFeePct(uint64 _feePct)
        external
        auth(SET_FEE_PERCENTAGE_ROLE)
    {
        feePct = _feePct;
    }

    /**
     * @dev Set beneficiary of registry fees.
     * @param _beneficiary The beneficiary of registry fees
     */
    function setBeneficiary(address _beneficiary)
        external
        auth(SET_BENEFICIARY_ROLE)
    {
        beneficiary = _beneficiary;
    }

    /**
     * @dev Upsert a registry entry with a stake.
     * @param _scope
     *        The scope of the entry.
     *        If the scope is the zero address, then the entry is global.
     * @param _sig
     *        The signature of the method the entry is describing.
     * @param _cid
     *        The IPFS CID of the file containing the Radspec description.
     */
    function stakeAndUpsertEntry(address _scope, bytes4 _sig, string _cid) external payable;

    /**
     * @dev Upsert a registry entry without a stake.
     * @param _scope
     *        The scope of the entry.
     *        If the scope is the zero address, then the entry is global.
     * @param _sig
     *        The signature of the method the entry is describing.
     * @param _cid
     *        The IPFS CID of the file containing the Radspec description.
     */
    function upsertEntry(address _scope, bytes4 _sig, string _cid)
        external
        auth(UPSERT_ENTRY_ROLE)
    {
        Entry storage entry_ = entries[_scope][_sig];
        entry_.stake = 0;
        entry_.cid = _cid;
        entry_.submitter = msg.sender;

        emit EntryUpserted(_scope, _sig, msg.sender, 0, _cid);
    }

    /**
     * @dev Get an entry from the registry.
     * @param _scope
     *        The scope of the entry.
     *        If the scope is the zero address, then the entry is global.
     * @param _sig
     *        The signature of the method the entry is describing.
     * @return The CID of the entry, the submitter of the entry and the stake for the entry.
     */
    function getEntry(address _scope, bytes4 _sig)
        external
        view
        returns (string, address, uint256)
    {
        require(_hasEntry(_scope, _sig), ERROR_ENTRY_DOESNT_EXIST);
        Entry storage entry_ = entries[_scope][_sig];

        return (entry_.cid, entry_.submitter, entry_.stake);
    }

    /**
     * @dev Check whether an entry exists in the registry.
     * @param _scope
     *        The scope of the entry.
     *        If the scope is the zero address, then the entry is global.
     * @param _sig
     *        The signature of the method the entry is describing.
     * @return True if the entry exists, false otherwise.
     */
    function hasEntry(address _scope, bytes4 _sig)
        external
        view
        returns (bool)
    {
        return _hasEntry(_scope, _sig);
    }

    function _hasEntry(address _scope, bytes4 _sig)
        internal
        view
        returns (bool)
    {
        Entry storage entry_ = entries[_scope][_sig];

        return entry_.cid.length > 0;
    }

    /**
     * @dev Remove an entry from the registry.
     * @param _scope
     *        The scope of the entry.
     *        If the scope is the zero address, then the entry is global.
     * @param _sig
     *        The signature of the method the entry is describing.
     */
    function removeEntry(address _scope, bytes4 _sig)
        external
        auth(REMOVE_ENTRY_ROLE)
    {
        _removeEntry(_scope, _sig);
    }

    function _removeEntry(address _scope, bytes4 _sig) internal {
        delete entries[_scope][_sig];
        emit EntryRemoved(_scope, _sig);
    }

    /**
     * @dev Dispute an entry in the registry.
     * @param _scope
     *        The scope of the entry.
     *        If the scope is the zero address, then the entry is global.
     * @param _sig
     *        The signature of the method the entry is describing.
     * @return The dispute ID.
     */
    function createDispute(address _scope, bytes4 _sig)
        external
        returns (uint256)
    {
        return _createDispute(_scope, _sig);
    }

    function _createDispute(address _scope, bytes4 _sig)
        internal
        returns (uint256)
    {
        // We don't need to check that the entry exists, since this
        // check will fail if it doesn't.
        require(disputes[_scope][_sig] == 0, ERROR_DISPUTE_EXISTS);

        (address recipient, ERC20 feeToken, uint256 disputeFees) = arbitrator.getDisputeFees();
        feeToken.approve(recipient, disputeFees);

        // TODO _metadata
        return arbitrator.createDispute(2, _metadata);
    }

    /**
     * @dev Creates a dispute for an entry in the registry and submits some evidence.
     * @param _scope
     *        The scope of the entry.
     *        If the scope is the zero address, then the entry is global.
     * @param _sig
     *        The signature of the method the entry is describing.
     * @param _evidence Data submitted for the evidence of the dispute
     * @return The dispute ID.
     */
    function createDisputeAndSubmitEvidence(
        address _scope,
        bytes4 _sig,
        bytes calldata _evidence
    )
        external
        returns (uint256)
    {
        uint256 disputeId = _createDispute(_scope, _sig);
        _submitEvidence(disputeId, _evidence, false);

        return disputeId;
    }


    /**
    * @dev Emitted when an IArbitrable instance's dispute is ruled by an IArbitrator
    * @param arbitrator IArbitrator instance ruling the dispute
    * @param disputeId Identification number of the dispute being ruled by the arbitrator
    * @param ruling Ruling given by the arbitrator
    */
    event Ruled(IArbitrator indexed arbitrator, uint256 indexed disputeId, uint256 ruling);

    /**
    * @dev Emitted when new evidence is submitted for the IArbitrable instance's dispute
    * @param disputeId Identification number of the dispute receiving new evidence
    * @param submitter Address of the account submitting the evidence
    * @param evidence Data submitted for the evidence of the dispute
    * @param finished Whether or not the submitter has finished submitting evidence
    */
    event EvidenceSubmitted(uint256 indexed disputeId, address indexed submitter, bytes evidence, bool finished);

    /**
    * @dev Submit evidence for a dispute
    * @param _disputeId Id of the dispute in the Court
    * @param _evidence Data submitted for the evidence related to the dispute
    * @param _finished Whether or not the submitter has finished submitting evidence
    */
    function submitEvidence(uint256 _disputeId, bytes calldata _evidence, bool _finished) external {
        _submitEvidence(_disputeId, _evidence, _finished);
    }

    function _submitEvidence(
        uint256 _disputeId,
        bytes calldata _evidence,
        bool _finished
    )
        internal
    {
        // TODO Error message
        require(_disputeExists(_disputeId));
        emit EvidenceSubmitted(_disputeId, msg.sender, _evidence, _finished);

        if (_finished) {
            arbitrator.closeEvidencePeriod(_disputeId);
        }
    }

    /**
    * @dev Give a ruling for a certain dispute, the account calling it must have rights to rule on the contract
    * @param _disputeId Identification number of the dispute to be ruled
    * @param _ruling Ruling given by the arbitrator, where 0 is reserved for "refused to make a decision"
    */
    function rule(uint256 _disputeId, uint256 _ruling) external {
        // TODO Error messages
        require(msg.sender == arbitrator);
        require(_disputeExists(_disputeId));

        // TODO Transfer stake to plaintiff
        // TODO Remove entry
        // TODO Remove dispute

        emit Ruled(IArbitrator(msg.sender), _disputeId, _ruling);
    }
}
