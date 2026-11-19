// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IAgentIDRegistry — minimal interface for the SPACE ID Agent ID registry on BNB Chain
/// @notice Registry: 0x60b9262456de011f7d15a54cdd8c48baaa8b022f ("SPACE ID Agent ID", symbol "AI").
///         The venue's official integration guidance is a single line: balanceOf(address) > 0.
///         This interface captures exactly the calls verified live against that contract.
interface IAgentIDRegistry {
    function balanceOf(address owner) external view returns (uint256);
    function ownerOf(uint256 tokenId) external view returns (address);
    function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256);
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
}

/// @title AgentIDGate — standard, reusable Agent ID gate for BNB Chain dApps
/// @notice Library + base contract. No custody, no payable functions, no credential handling.
///         A holder check is a read against the official registry; nothing else is trusted.
library AgentIDGate {
    address internal constant REGISTRY = 0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F;

    error NotHolder(address account);

    /// @notice True when `account` holds at least one Agent ID.
    function isHolder(address account) internal view returns (bool) {
        return isHolder(REGISTRY, account);
    }

    function isHolder(address registry, address account) internal view returns (bool) {
        if (account == address(0)) return false;
        try IAgentIDRegistry(registry).balanceOf(account) returns (uint256 bal) {
            return bal > 0;
        } catch {
            return false;
        }
    }

    /// @notice Number of Agent IDs held (0 for non-holders / on registry read failure).
    function balanceOf(address registry, address account) internal view returns (uint256) {
        try IAgentIDRegistry(registry).balanceOf(account) returns (uint256 bal) {
            return bal;
        } catch {
            return 0;
        }
    }

    /// @notice Resolve the first token id held by `account`, if the registry exposes enumeration.
    /// @dev Verified live 2026-11-19: the official registry does NOT expose enumeration
    ///      (no tokenOfOwnerByIndex / totalSupply in its bytecode, supportsInterface for
    ///      ERC721Enumerable is false). On the official registry this always returns
    ///      found=false — by design it degrades gracefully instead of reverting.
    ///      The holder check (balanceOf) is the only address-level primitive the
    ///      official contract offers; build on that, not on token-id resolution.
    /// @return found False when the account holds none or enumeration is unavailable.
    /// @return tokenId The first held token id when found.
    function tokenIdOf(address registry, address account)
        internal
        view
        returns (bool found, uint256 tokenId)
    {
        if (!isHolder(registry, account)) return (false, 0);
        try IAgentIDRegistry(registry).tokenOfOwnerByIndex(account, 0) returns (uint256 id) {
            return (true, id);
        } catch {
            return (false, 0);
        }
    }

    function requireHolder(address registry, address account) internal view {
        if (!isHolder(registry, account)) revert NotHolder(account);
    }
}

/// @title AgentIDGated — base contract: inherit and apply `onlyAgentIDHolder` to gated actions.
abstract contract AgentIDGated {
    IAgentIDRegistry public immutable agentIDRegistry;

    event AgentIDRegistrySet(address indexed registry);

    constructor(address registry_) {
        require(registry_ != address(0), "registry is zero address");
        agentIDRegistry = IAgentIDRegistry(registry_);
        emit AgentIDRegistrySet(registry_);
    }

    modifier onlyAgentIDHolder() {
        AgentIDGate.requireHolder(address(agentIDRegistry), msg.sender);
        _;
    }

    function isAgentIDHolder(address account) public view returns (bool) {
        return AgentIDGate.isHolder(address(agentIDRegistry), account);
    }
}
