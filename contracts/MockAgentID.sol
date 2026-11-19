// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title MockAgentID — test-only stand-in for the SPACE ID Agent ID registry.
/// @notice Mirrors the live registry's observed behaviour: balanceOf reverts for the
///         zero address, ownerOf reverts for nonexistent tokens, token ids are
///         non-sequential, and enumeration is exposed via tokenOfOwnerByIndex.
contract MockAgentID {
    string public name = "SPACE ID Agent ID";
    string public symbol = "AI";

    mapping(address => uint256[]) private _tokens;
    mapping(uint256 => address) private _owners;
    uint256 private _counter = 1000003; // non-sequential-looking ids, like the live registry

    error InvalidOwner(address owner);
    error NonexistentToken(uint256 tokenId);

    function mint(address to) external returns (uint256 tokenId) {
        tokenId = _counter;
        _counter += 7919; // prime stride: ids never look sequential
        _owners[tokenId] = to;
        _tokens[to].push(tokenId);
    }

    function balanceOf(address owner_) external view returns (uint256) {
        if (owner_ == address(0)) revert InvalidOwner(owner_);
        return _tokens[owner_].length;
    }

    function ownerOf(uint256 tokenId) external view returns (address) {
        address o = _owners[tokenId];
        if (o == address(0)) revert NonexistentToken(tokenId);
        return o;
    }

    function tokenOfOwnerByIndex(address owner_, uint256 index) external view returns (uint256) {
        if (owner_ == address(0)) revert InvalidOwner(owner_);
        return _tokens[owner_][index];
    }
}
