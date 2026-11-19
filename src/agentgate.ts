/**
 * AgentGate Kit — TypeScript helper
 *
 * Minimal, dependency-light helpers for gating a BNB Chain dApp on Agent ID.
 * The only on-chain fact used is the venue's own rule: an address holds an
 * Agent ID when balanceOf(address) > 0 on the official registry.
 *
 * Bring your own ethers v6 provider / contract runner.
 */

export const AGENT_ID_REGISTRY = "0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F";

export const REGISTRY_ABI = [
  "function balanceOf(address owner) view returns (uint256)",
  "function ownerOf(uint256 tokenId) view returns (address)",
  "function tokenOfOwnerByIndex(address owner, uint256 index) view returns (uint256)",
  "function name() view returns (string)",
  "function symbol() view returns (string)",
] as const;

export const CAPABILITY_REGISTRY_ABI = [
  "function register(string displayName, string category, bytes32 endpointHash)",
  "function deregister()",
  "function checkIn()",
  "function isRegistered(address holder) view returns (bool)",
  "function profileOf(address holder) view returns (tuple(string displayName, string category, bytes32 endpointHash, uint64 registeredAt, uint64 updatedAt, bool exists))",
  "function checkInCount(address holder) view returns (uint32)",
  "function totalRegistrants() view returns (uint256)",
  "function totalCheckIns() view returns (uint256)",
] as const;

/** Structural type for an ethers v6 Contract-like object (avoids a hard peer import here). */
export interface RegistryContract {
  balanceOf(owner: string): Promise<bigint>;
  tokenOfOwnerByIndex(owner: string, index: bigint): Promise<bigint>;
}

/** True when `address` holds at least one Agent ID. Zero address is always false. */
export async function isAgentIDHolder(
  registry: RegistryContract,
  address: string,
): Promise<boolean> {
  if (!address || address === "0x0000000000000000000000000000000000000000") return false;
  try {
    return (await registry.balanceOf(address)) > 0n;
  } catch {
    return false;
  }
}

/**
 * First Agent ID token id held by `address`, or null when none / enumeration unavailable.
 * Note (verified live 2026-11-19): the official registry exposes no enumeration,
 * so on BNB Chain mainnet this returns null — the holder check is the primitive
 * to build on. This helper exists for registries that do enumerate.
 */
export async function agentIDTokenOf(
  registry: RegistryContract,
  address: string,
): Promise<bigint | null> {
  if (!(await isAgentIDHolder(registry, address))) return null;
  try {
    return await registry.tokenOfOwnerByIndex(address, 0n);
  } catch {
    return null;
  }
}
