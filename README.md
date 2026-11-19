# AgentGate Kit

A standard, reusable Agent ID gate for BNB Chain dApps, plus an opt-in capability
registry that shows the gate doing real work. Built as a public good for the
Binance Wallet / BNB Chain Agent ID ecosystem: the venue's official integration
guidance for Agent ID is a single line — call `balanceOf(address)` — and every
builder otherwise re-implements the check alone. This kit is that missing
reference pattern, ready to pick up cold.

## What is in the kit

| Piece | File | What it does |
|---|---|---|
| Gate library + base contract | `contracts/AgentIDGate.sol` | `isHolder`, `balanceOf`, best-effort `tokenIdOf`, and an `onlyAgentIDHolder` modifier against the official registry |
| Capability registry (demo dApp) | `contracts/CapabilityRegistry.sol` | A live-pattern dApp on the gate: holders register a public capability profile for their own wallet and check in daily |
| TypeScript helper | `src/agentgate.ts` | `isAgentIDHolder` / `agentIDTokenOf` for ethers v6 frontends |
| Tests | `test/run-tests.mjs` | Compile + 20 behavioural checks on a local chain (`npm test`) |

Official Agent ID registry (BNB Chain mainnet):
`0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F` ("SPACE ID Agent ID", symbol "AI").

## Live deployment (BNB Chain mainnet)

`CapabilityRegistry` is deployed and live:

- Contract: `0x3E826ddaF46965c5825E1Bb1c20830E68119D7AC`
  ([BscScan](https://bscscan.com/address/0x3E826ddaF46965c5825E1Bb1c20830E68119D7AC))
- Deployment transaction:
  `0xb90786b13755b50e382963cc870f6fe0a674a13f0cfe42f98373050ace11238a`
  ([BscScan](https://bscscan.com/tx/0xb90786b13755b50e382963cc870f6fe0a674a13f0cfe42f98373050ace11238a)),
  block 134537509, 2026-11-19
- Wired to the official Agent ID registry above; registration and check-in are
  open to any Agent ID holder from their own wallet.

Any Agent ID holder can register a capability profile with one call to
`register(displayName, category, endpointHash)` — see the registry rules below.

## Use the gate in your dApp (2 minutes)

```solidity
import "./AgentIDGate.sol";

contract MyDApp is AgentIDGated {
    constructor() AgentIDGated(0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F) {}

    function holderOnlyAction() external onlyAgentIDHolder {
        // msg.sender holds an Agent ID — verified against the registry here.
    }
}
```

Or call the library directly: `AgentIDGate.isHolder(account)`.

Frontend:

```ts
import { Contract } from "ethers";
import { AGENT_ID_REGISTRY, REGISTRY_ABI, isAgentIDHolder } from "./src/agentgate";

const registry = new Contract(AGENT_ID_REGISTRY, REGISTRY_ABI, provider);
const gated = await isAgentIDHolder(registry, userAddress);
```

## Facts about the official registry, verified live (2026-11-19)

These cost every builder a probing session; they are recorded here so yours is free.

- `balanceOf(address)` is the holder check. It **reverts for the zero address**
  (standard ERC-721 `InvalidOwner`) — the gate short-circuits zero and wraps the
  call in try/catch, so a bad address reads as "not a holder", never a crash.
- The registry is ERC-721 with metadata (`supportsInterface` true for
  `0x80ac58cd` and `0x5b5e139f`), and token ids are **not sequential**
  (`ownerOf(0)`, `ownerOf(1)`, `ownerOf(1000)` all revert as nonexistent).
- There is **no enumeration**: no `totalSupply`, no `tokenOfOwnerByIndex` in the
  bytecode, and `supportsInterface(0x780e9d63)` is false. You cannot resolve a
  token id from an address with this contract — design on the holder check.
- Gas price on BSC was 0.05 gwei at verification time; the gate check is one
  external view call.

## Gas estimation note

Local-chain `estimateGas` under-reported a gated write in testing (46,190
estimated vs 48,281 actual), because the write's cost depends on the external
holder check. When sending gated writes from a frontend, estimate and add a
buffer (or set a sane explicit limit) rather than sending the raw estimate.

## Capability registry rules (by construction)

- **Self-registration only.** A wallet registers itself; there is no function to
  register, edit, or remove another wallet, and no lookup of wallets by name.
- **No custody.** No payable functions, no transfers, no approvals, no withdrawals.
- **No credentials.** Profiles carry only what the holder chooses to publish:
  a display name, a category, and a hash of an endpoint description.
- **Owner permissions, disclosed:** the owner may pause/unpause registrations
  and check-ins and transfer ownership. The owner cannot touch profiles or funds.

## Run the tests

```bash
npm install
npm test   # compiles all contracts and runs 20 checks on a local chain
```

Latest recorded result: 20/20 checks passed, three consecutive runs,
2026-11-19 (`test-results.json`).

## License

MIT
