// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "./oz/Ownable.sol";
import "./oz/ReentrancyGuard.sol";

/// @title IPNSRegistry — On-chain name registry for IPFS content on Base
/// @author ipns.io
/// @notice Register human-readable names that resolve to IPFS CIDs
/// @dev Names are stored normalized (lowercase). Display names preserve original casing.

contract IPNSRegistry is Ownable, ReentrancyGuard {

    // ──────────────────────────────────────────────
    //  Types
    // ──────────────────────────────────────────────

    struct Record {
        address owner;
        string  cid;            // IPFS CID (e.g. "bafybei...")
        string  displayName;    // Original casing (e.g. "Alice")
        uint64  registered;     // Timestamp of registration
        uint64  expires;        // Timestamp of expiration
    }

    /// @dev Subname record. v1 is parent-controlled; `owner` is reserved for future delegation.
    struct SubRecord {
        address owner; // v2+: optional delegated owner; v1 leaves this as address(0)
        string  cid;   // IPFS CID (e.g. "bafybei...")
    }

    // ──────────────────────────────────────────────
    //  State
    // ──────────────────────────────────────────────

    /// @notice keccak256(normalized name) => Record
    /// @dev Using bytes32 keys avoids expensive string mapping keys.
    mapping(bytes32 => Record) public names;

    /// @notice parentKey => labelKey => SubRecord
    /// @dev labelKey = keccak256(normalized label). Delegation is future work.
    mapping(bytes32 => mapping(bytes32 => SubRecord)) private _subnames;

    /// @notice Names that cannot be registered
    mapping(bytes32 => bool) public reserved;

    /// @notice Price per year in wei, indexed by character length (1-5+)
    /// @dev priceByLength[0] is unused. priceByLength[1] = 1-char price, etc.
    ///      priceByLength[5] applies to all names 5+ chars.
    uint256[6] public priceByLength;

    /// @notice Duration constants
    uint64 public constant REGISTRATION_PERIOD = 365 days;
    uint64 public constant GRACE_PERIOD = 90 days;

    /// @notice Minimum name length
    uint8 public constant MIN_LENGTH = 1;

    /// @notice Maximum name length
    uint8 public constant MAX_LENGTH = 63; // DNS subdomain limit

    /// @notice Protocol fee recipient
    address public treasury;

    // ──────────────────────────────────────────────
    //  Events
    // ──────────────────────────────────────────────

    event NameRegistered(string indexed normalizedName, string displayName, address indexed owner, uint64 expires);
    event NameRenewed(string indexed normalizedName, address indexed owner, uint64 newExpires);
    event CIDUpdated(string indexed normalizedName, string cid);
    event SubCIDUpdated(string indexed normalizedName, string indexed label, string cid);
    event SubCIDCleared(string indexed normalizedName, string indexed label);
    event NameTransferred(string indexed normalizedName, address indexed from, address indexed to);
    event NameReserved(string indexed normalizedName);
    event NameUnreserved(string indexed normalizedName);
    event PriceUpdated(uint256 length, uint256 newPrice);
    event TreasuryUpdated(address newTreasury);

    // ──────────────────────────────────────────────
    //  Errors
    // ──────────────────────────────────────────────

    error NameTooShort();
    error NameTooLong();
    error InvalidCharacter(uint8 char_code);
    error NameReservedError();
    error NameNotOwned();
    error NameUnavailable();
    error IncorrectPayment(uint256 required, uint256 sent);
    error TransferToZeroAddress();
    error ZeroYears();
    error WithdrawFailed();
    error ZeroAddress();
    error EmptyLabel();

    // ──────────────────────────────────────────────
    //  Constructor
    // ──────────────────────────────────────────────

    constructor(address _initialOwner, address _treasury) Ownable(_initialOwner) {
        if (_treasury == address(0)) revert ZeroAddress();
        treasury = _treasury;

        // Default pricing in wei (targeting ~USD equivalent at ~$3000 ETH)
        // These are starting points — update via setPriceByLength()
        priceByLength[1] = 0.017 ether;   // ~$50 — single char
        priceByLength[2] = 0.0083 ether;  // ~$25 — two chars
        priceByLength[3] = 0.0033 ether;  // ~$10 — three chars
        priceByLength[4] = 0.0017 ether;  // ~$5  — four chars
        priceByLength[5] = 0.00033 ether; // ~$1  — five+ chars

        // Reserve protocol names
        _reserve("ipns");
        _reserve("ipfs");
        _reserve("api");
        _reserve("www");
        _reserve("admin");
        _reserve("gateway");
        _reserve("app");
        _reserve("docs");
        _reserve("mail");
        _reserve("ftp");
        _reserve("ns");
        _reserve("ns1");
        _reserve("ns2");
        _reserve("mx");
        _reserve("smtp");
        _reserve("pop");
        _reserve("imap");
        _reserve("blog");
        _reserve("status");
        _reserve("help");
        _reserve("support");
        _reserve("test");
        _reserve("dev");
        _reserve("staging");
        _reserve("beta");
        _reserve("alpha");
        _reserve("cdn");
        _reserve("static");
        _reserve("assets");
        _reserve("images");
        _reserve("img");
        _reserve("js");
        _reserve("css");
        _reserve("node");
        _reserve("registry");
        _reserve("resolver");
        _reserve("contract");
        _reserve("base");
        _reserve("ethereum");
        _reserve("eth");
        _reserve("bitcoin");
        _reserve("btc");
        _reserve("wallet");
        _reserve("login");
        _reserve("signup");
        _reserve("register");
        _reserve("account");
        _reserve("settings");
        _reserve("profile");
        _reserve("dashboard");
        _reserve("root");
        _reserve("null");
        _reserve("undefined");
        _reserve("localhost");
    }

    // ──────────────────────────────────────────────
    //  Registration
    // ──────────────────────────────────────────────

    /// @notice Register a name for one or more years
    /// @param name The name to register (any casing)
    /// @param numYears Number of years to register (1+)
    function register(string calldata name, uint8 numYears) external payable nonReentrant {
        if (numYears == 0) revert ZeroYears();

        string memory normalized = _normalize(name);
        bytes32 key = _nameKey(normalized);
        uint256 len = bytes(normalized).length;
        _requireValidLen(len);
        if (reserved[key]) revert NameReservedError();
        _requireAvailable(key);

        uint256 price = _getPrice(len) * numYears;
        if (msg.value != price) revert IncorrectPayment(price, msg.value);

        uint64 expiry = uint64(block.timestamp) + (REGISTRATION_PERIOD * numYears);
        _writeRecord(key, msg.sender, name, expiry);

        emit NameRegistered(normalized, name, msg.sender, expiry);
    }

    // ──────────────────────────────────────────────
    //  Renewal
    // ──────────────────────────────────────────────

    /// @notice Renew a name for additional years
    /// @dev Anyone can renew any name (gifting renewals is allowed)
    /// @param name The normalized name to renew
    /// @param numYears Number of years to add
    function renew(string calldata name, uint8 numYears) external payable nonReentrant {
        if (numYears == 0) revert ZeroYears();

        string memory normalized = _normalize(name);
        bytes32 key = _nameKey(normalized);
        Record storage record = names[key];

        // Must be currently active or in grace period
        if (record.owner == address(0)) revert NameNotOwned();
        if (block.timestamp > record.expires + GRACE_PERIOD) revert NameNotOwned();

        uint256 len = bytes(normalized).length;
        uint256 price = _getPrice(len) * numYears;
        if (msg.value != price) revert IncorrectPayment(price, msg.value);

        // Extend from current expiry (not from now — no time lost)
        uint64 currentExpiry = record.expires;
        if (block.timestamp > currentExpiry) {
            // In grace period — extend from now, not from expired date
            currentExpiry = uint64(block.timestamp);
        }
        record.expires = currentExpiry + (REGISTRATION_PERIOD * numYears);

        emit NameRenewed(normalized, record.owner, record.expires);
    }

    // ──────────────────────────────────────────────
    //  Content Management
    // ──────────────────────────────────────────────

    /// @notice Set the IPFS CID for a name you own
    /// @param name The name (any casing, will be normalized)
    /// @param cid The IPFS CID to point to
    function setCID(string calldata name, string calldata cid) external {
        string memory normalized = _normalize(name);
        bytes32 key = _nameKey(normalized);
        Record storage record = names[key];

        if (record.owner != msg.sender) revert NameNotOwned();
        if (block.timestamp > record.expires) revert NameNotOwned();

        record.cid = cid;
        emit CIDUpdated(normalized, cid);
    }

    /// @notice Set an IPFS CID for a subname under a name you own (e.g. blog.alice)
    /// @dev v1: parent-controlled. v2 can add delegated ownership using SubRecord.owner.
    /// @param name Parent name (any casing, will be normalized)
    /// @param label Subname label (any casing, will be normalized). No dots.
    /// @param cid IPFS CID to point the subname at
    function setSubCID(string calldata name, string calldata label, string calldata cid) external {
        string memory parentNorm = _normalize(name);
        bytes32 parentKey = _nameKey(parentNorm);
        Record storage parent = names[parentKey];

        if (parent.owner != msg.sender) revert NameNotOwned();
        if (block.timestamp > parent.expires) revert NameNotOwned();

        string memory labelNorm = _normalize(label);
        if (bytes(labelNorm).length == 0) revert EmptyLabel();
        bytes32 labelKey = _nameKey(labelNorm);

        SubRecord storage sub = _subnames[parentKey][labelKey];
        // v1: only parent controls subnames. Reserve `owner` for future delegation.
        sub.cid = cid;

        emit SubCIDUpdated(parentNorm, labelNorm, cid);
    }

    /// @notice Clear a subname CID under a name you own
    function clearSubCID(string calldata name, string calldata label) external {
        string memory parentNorm = _normalize(name);
        bytes32 parentKey = _nameKey(parentNorm);
        Record storage parent = names[parentKey];

        if (parent.owner != msg.sender) revert NameNotOwned();
        if (block.timestamp > parent.expires) revert NameNotOwned();

        string memory labelNorm = _normalize(label);
        if (bytes(labelNorm).length == 0) revert EmptyLabel();
        bytes32 labelKey = _nameKey(labelNorm);

        delete _subnames[parentKey][labelKey].cid;
        emit SubCIDCleared(parentNorm, labelNorm);
    }

    /// @notice Update the display name (casing only — must normalize to same key)
    /// @param name New display casing
    function setDisplayName(string calldata name) external {
        string memory normalized = _normalize(name);
        bytes32 key = _nameKey(normalized);
        Record storage record = names[key];

        if (record.owner != msg.sender) revert NameNotOwned();
        if (block.timestamp > record.expires) revert NameNotOwned();

        record.displayName = name;
    }

    // ──────────────────────────────────────────────
    //  Transfers
    // ──────────────────────────────────────────────

    /// @notice Transfer ownership of a name
    /// @param name The name to transfer
    /// @param to New owner address
    function transfer(string calldata name, address to) external {
        if (to == address(0)) revert TransferToZeroAddress();

        string memory normalized = _normalize(name);
        bytes32 key = _nameKey(normalized);
        Record storage record = names[key];

        if (record.owner != msg.sender) revert NameNotOwned();
        if (block.timestamp > record.expires) revert NameNotOwned();

        address from = record.owner;
        record.owner = to;

        emit NameTransferred(normalized, from, to);
    }

    // ──────────────────────────────────────────────
    //  Views
    // ──────────────────────────────────────────────

    /// @notice Resolve a name to its CID (returns empty string if expired/unregistered)
    /// @param name The name to resolve (any casing)
    /// @return cid The IPFS CID, or empty if not found/expired
    function resolve(string calldata name) external view returns (string memory cid) {
        string memory normalized = _normalize(name);
        bytes32 key = _nameKey(normalized);
        Record storage record = names[key];

        if (record.owner == address(0)) return "";
        if (block.timestamp > record.expires) return "";

        return record.cid;
    }

    /// @notice Resolve a subname label under a parent name
    /// @dev If no subname CID is set, this falls back to the parent CID.
    /// @param name Parent name (any casing)
    /// @param label Subname label (any casing)
    function resolveSub(string calldata name, string calldata label) external view returns (string memory cid) {
        string memory parentNorm = _normalize(name);
        bytes32 parentKey = _nameKey(parentNorm);
        Record storage parent = names[parentKey];

        if (parent.owner == address(0)) return "";
        if (block.timestamp > parent.expires) return "";

        string memory labelNorm = _normalize(label);
        if (bytes(labelNorm).length == 0) return parent.cid;
        bytes32 labelKey = _nameKey(labelNorm);

        SubRecord storage sub = _subnames[parentKey][labelKey];
        if (bytes(sub.cid).length == 0) return parent.cid;
        return sub.cid;
    }

    /// @notice Get subname record (reserved fields for future delegation)
    function getSubRecord(string calldata name, string calldata label) external view returns (
        address owner,
        string memory cid
    ) {
        string memory parentNorm = _normalize(name);
        bytes32 parentKey = _nameKey(parentNorm);
        string memory labelNorm = _normalize(label);
        if (bytes(labelNorm).length == 0) revert EmptyLabel();
        bytes32 labelKey = _nameKey(labelNorm);

        SubRecord storage sub = _subnames[parentKey][labelKey];
        return (sub.owner, sub.cid);
    }

    /// @notice Check if a name is available for registration
    /// @param name The name to check (any casing)
    /// @return available True if the name can be registered
    function isAvailable(string calldata name) external view returns (bool available) {
        string memory normalized = _normalize(name);
        bytes32 key = _nameKey(normalized);

        if (reserved[key]) return false;

        Record storage record = names[key];
        if (record.owner == address(0)) return true;
        if (block.timestamp > record.expires + GRACE_PERIOD) return true;

        return false;
    }

    /// @notice Get the registration price for a name
    /// @param name The name to price (any casing)
    /// @param numYears Number of years
    /// @return price Total price in wei
    function getPrice(string calldata name, uint8 numYears) external view returns (uint256 price) {
        string memory normalized = _normalize(name);
        uint256 len = bytes(normalized).length;
        _requireValidLen(len);
        return _getPrice(len) * numYears;
    }

    /// @notice Get full record for a name
    /// @param name The name to look up
    function getRecord(string calldata name) external view returns (
        address owner,
        string memory cid,
        string memory displayName,
        uint64 registered,
        uint64 expires,
        bool active
    ) {
        string memory normalized = _normalize(name);
        bytes32 key = _nameKey(normalized);
        Record storage record = names[key];
        return (
            record.owner,
            record.cid,
            record.displayName,
            record.registered,
            record.expires,
            record.owner != address(0) && block.timestamp <= record.expires
        );
    }

    // ──────────────────────────────────────────────
    //  Admin
    // ──────────────────────────────────────────────

    /// @notice Reserve a name (prevents registration)
    function reserveName(string calldata name) external onlyOwner {
        string memory normalized = _normalize(name);
        reserved[_nameKey(normalized)] = true;
        emit NameReserved(normalized);
    }

    /// @notice Batch reserve names
    function reserveNames(string[] calldata nameList) external onlyOwner {
        for (uint256 i = 0; i < nameList.length; i++) {
            string memory normalized = _normalize(nameList[i]);
            reserved[_nameKey(normalized)] = true;
            emit NameReserved(normalized);
        }
    }

    /// @notice Unreserve a name (allows registration)
    function unreserveName(string calldata name) external onlyOwner {
        string memory normalized = _normalize(name);
        reserved[_nameKey(normalized)] = false;
        emit NameUnreserved(normalized);
    }

    /// @notice Update price for a name length tier
    /// @param length The character length (1-5, where 5 = 5+)
    /// @param price Price in wei per year
    function setPriceByLength(uint256 length, uint256 price) external onlyOwner {
        require(length >= 1 && length <= 5, "Length must be 1-5");
        priceByLength[length] = price;
        emit PriceUpdated(length, price);
    }

    /// @notice Update treasury address
    function setTreasury(address _treasury) external onlyOwner {
        if (_treasury == address(0)) revert ZeroAddress();
        treasury = _treasury;
        emit TreasuryUpdated(_treasury);
    }

    /// @notice Withdraw accumulated fees to treasury
    function withdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        _sendETH(treasury, balance);
    }

    // ──────────────────────────────────────────────
    //  Internal
    // ──────────────────────────────────────────────

    /// @notice Normalize a name: lowercase, validate characters (a-z, 0-9, hyphen)
    /// @dev Reverts on invalid characters. Does not allow leading/trailing hyphens.
    function _normalize(string memory name) internal pure returns (string memory) {
        bytes memory b = bytes(name);
        bytes memory result = new bytes(b.length);

        for (uint256 i = 0; i < b.length; i++) {
            uint8 c = uint8(b[i]);

            // Uppercase A-Z (65-90) => lowercase a-z (97-122)
            if (c >= 65 && c <= 90) {
                result[i] = bytes1(c + 32);
            }
            // Already lowercase a-z
            else if (c >= 97 && c <= 122) {
                result[i] = b[i];
            }
            // Digits 0-9
            else if (c >= 48 && c <= 57) {
                result[i] = b[i];
            }
            // Hyphen (not at start or end)
            else if (c == 45) {
                if (i == 0 || i == b.length - 1) revert InvalidCharacter(c);
                result[i] = b[i];
            }
            // Everything else is invalid
            else {
                revert InvalidCharacter(c);
            }
        }

        return string(result);
    }

    /// @notice Get price per year for a given name length
    function _getPrice(uint256 length) internal view returns (uint256) {
        if (length >= 5) return priceByLength[5];
        return priceByLength[length];
    }

    function _requireValidLen(uint256 len) internal pure {
        if (len < MIN_LENGTH) revert NameTooShort();
        if (len > MAX_LENGTH) revert NameTooLong();
    }

    function _requireAvailable(bytes32 key) internal view {
        Record storage record = names[key];
        if (record.expires != 0 && block.timestamp < record.expires + GRACE_PERIOD) revert NameUnavailable();
    }

    function _writeRecord(bytes32 key, address newOwner, string calldata displayName, uint64 expiry) internal {
        Record storage rec = names[key];
        rec.owner = newOwner;
        rec.cid = "";
        rec.displayName = displayName;
        rec.registered = uint64(block.timestamp);
        rec.expires = expiry;
    }

    /// @notice Send ETH safely
    function _sendETH(address to, uint256 amount) internal {
        (bool success, ) = to.call{value: amount}("");
        if (!success) revert WithdrawFailed();
    }

    /// @notice Internal reserve helper (used in constructor)
    function _reserve(string memory name) internal {
        string memory normalized = _normalize(name);
        reserved[_nameKey(normalized)] = true;
    }

    function _nameKey(string memory normalized) internal pure returns (bytes32) {
        return keccak256(bytes(normalized));
    }

    /// @notice Allow contract to receive ETH
    receive() external payable {}
}
