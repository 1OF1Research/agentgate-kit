// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./AgentIDGate.sol";

/// @title CapabilityRegistry — opt-in, self-registered capability profiles for Agent ID holders
/// @notice Design rules, by construction:
///         - Self-registration only: a wallet registers ITSELF, never another wallet.
///           There is deliberately no function to look up a wallet by name, and no
///           function that lets one address write another address's profile.
///         - Agent ID gated: registration and check-in require holding an Agent ID
///           in the official registry at the moment of the call.
///         - No custody: the contract holds no funds, has no payable functions, no
///           transfer, approval, or withdrawal logic of any kind.
///         - No credentials: profiles carry only what the holder chooses to publish
///           (a display name, a category, and a hash of an endpoint description).
///         Owner permissions (disclosed, per venue rules): the owner may pause and
///         unpause new registrations/check-ins, and transfer ownership. The owner
///         cannot edit or delete another holder's profile, cannot move funds
///         (none exist), and cannot change the Agent ID registry address.
contract CapabilityRegistry is AgentIDGated {
    struct Profile {
        string displayName;   // holder-chosen public label (NOT a wallet lookup key)
        string category;      // e.g. "payments", "data", "automation"
        bytes32 endpointHash; // hash of an off-chain endpoint description the holder publishes
        uint64 registeredAt;
        uint64 updatedAt;
        bool exists;
    }

    address public owner;
    bool public paused;

    mapping(address => Profile) private _profiles;
    address[] private _registrants;

    // Check-in attestation: a non-transferable, zero-value record that the holder
    // showed up as themselves. It is data in this contract, not a token.
    mapping(address => uint64) public lastCheckIn;
    mapping(address => uint64) private _lastCheckInDay;
    mapping(address => uint32) public checkInCount;
    uint256 public totalRegistrants;
    uint256 public totalCheckIns;

    event ProfileRegistered(address indexed holder, string category, uint64 at);
    event ProfileUpdated(address indexed holder, uint64 at);
    event ProfileRemoved(address indexed holder, uint64 at);
    event CheckedIn(address indexed holder, uint32 count, uint64 at);
    event Paused(bool paused);
    event OwnershipTransferred(address indexed from, address indexed to);

    error PausedError();
    error NotOwner();
    error EmptyField();
    error NotRegistered();
    error AlreadyCheckedInToday();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier whenNotPaused() {
        if (paused) revert PausedError();
        _;
    }

    constructor(address registry_) AgentIDGated(registry_) {
        owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    /// @notice Register your own capability profile. Caller must hold an Agent ID.
    function register(string calldata displayName, string calldata category, bytes32 endpointHash)
        external
        onlyAgentIDHolder
        whenNotPaused
    {
        if (bytes(displayName).length == 0 || bytes(category).length == 0) revert EmptyField();
        Profile storage p = _profiles[msg.sender];
        bool isNew = !p.exists;
        p.displayName = displayName;
        p.category = category;
        p.endpointHash = endpointHash;
        p.updatedAt = uint64(block.timestamp);
        if (isNew) {
            p.exists = true;
            p.registeredAt = uint64(block.timestamp);
            _registrants.push(msg.sender);
            totalRegistrants += 1;
            emit ProfileRegistered(msg.sender, category, uint64(block.timestamp));
        } else {
            emit ProfileUpdated(msg.sender, uint64(block.timestamp));
        }
    }

    /// @notice Remove your own profile. Only the holder themselves can do this.
    function deregister() external {
        Profile storage p = _profiles[msg.sender];
        if (!p.exists) revert NotRegistered();
        delete _profiles[msg.sender];
        totalRegistrants -= 1;
        emit ProfileRemoved(msg.sender, uint64(block.timestamp));
    }

    /// @notice Check in as yourself. One check-in per holder per UTC day.
    ///         This is the single cheap interaction a holder makes to signal liveness.
    function checkIn() external onlyAgentIDHolder whenNotPaused {
        uint64 today = uint64(block.timestamp / 1 days);
        if (checkInCount[msg.sender] > 0 && _lastCheckInDay[msg.sender] == today) {
            revert AlreadyCheckedInToday();
        }
        _lastCheckInDay[msg.sender] = today;
        lastCheckIn[msg.sender] = uint64(block.timestamp);
        checkInCount[msg.sender] += 1;
        totalCheckIns += 1;
        emit CheckedIn(msg.sender, checkInCount[msg.sender], uint64(block.timestamp));
    }

    /// @notice Read a profile by holder address (address-keyed only; no name lookup exists).
    function profileOf(address holder) external view returns (Profile memory) {
        return _profiles[holder];
    }

    function isRegistered(address holder) external view returns (bool) {
        return _profiles[holder].exists;
    }

    function registrantCount() external view returns (uint256) {
        return _registrants.length;
    }

    function registrantAt(uint256 index) external view returns (address) {
        return _registrants[index];
    }

    // --- Owner controls (disclosed above; no fund movement exists in this contract) ---
    function setPaused(bool paused_) external onlyOwner {
        paused = paused_;
        emit Paused(paused_);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "new owner is zero address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
}
