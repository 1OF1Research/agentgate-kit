// AgentGate Kit — compile + behavioural tests on a local in-process chain (ganache).
// Every assertion is recorded; the runner exits non-zero on any failure.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import solc from "solc";
import ganache from "ganache";
import { ethers } from "ethers";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.join(here, "..");
const results = [];
function check(name, cond, detail = "") {
  results.push({ name, pass: !!cond, detail });
  console.log(`${cond ? "PASS" : "FAIL"}  ${name}${detail ? " — " + detail : ""}`);
}
async function expectRevert(name, thunk) {
  // Assert via staticCall: a write-call promise resolves at broadcast time and
  // cannot prove a revert; a static call executes against current state and throws.
  try {
    await thunk();
    check(name, false, "did not revert");
  } catch (e) {
    const msg = String(e?.shortMessage || e?.message || e);
    check(name, true, msg.slice(0, 140));
  }
}

// ---------- compile ----------
const sources = {};
for (const f of ["AgentIDGate.sol", "CapabilityRegistry.sol", "MockAgentID.sol"]) {
  sources[f] = { content: fs.readFileSync(path.join(root, "contracts", f), "utf8") };
}
const input = {
  language: "Solidity",
  sources,
  settings: { evmVersion: "paris", optimizer: { enabled: true, runs: 200 }, outputSelection: { "*": { "*": ["abi", "evm.bytecode"] } } },
};
const out = JSON.parse(solc.compile(JSON.stringify(input)));
const errors = (out.errors || []).filter((e) => e.severity === "error");
check("compile: no errors", errors.length === 0, errors.map((e) => e.formattedMessage).join("; ").slice(0, 300));
if (errors.length) { summarize(); process.exit(1); }
function artifact(file, name) {
  const c = out.contracts[file][name];
  return { abi: c.abi, bytecode: "0x" + c.evm.bytecode.object };
}

// ---------- chain ----------
// Ganache as an HTTP server + JsonRpcProvider: the in-process BrowserProvider
// path intermittently delivered transactions with empty calldata in this
// environment (static calls fine, broadcast tx reverted); HTTP is the robust route.
const server = ganache.server({ logging: { quiet: true } });
await server.listen(0);
const { port } = server.address();
const provider = new ethers.JsonRpcProvider(`http://127.0.0.1:${port}`);
const [deployer, holder, holder2, stranger] = await Promise.all([0, 1, 2, 3].map((i) => provider.getSigner(i)));

// Explicit gas for every write: this environment's estimateGas under-reports
// for calls that make an external holder check (observed 46,190 estimated vs
// 48,281 actual on re-register), and an under-estimated tx mines as status 0.
const GAS = { gasLimit: 600000 };

const mockArt = artifact("MockAgentID.sol", "MockAgentID");
const mock = await new ethers.ContractFactory(mockArt.abi, mockArt.bytecode, deployer).deploy();
await mock.waitForDeployment();
const mockAddr = await mock.getAddress();

const regArt = artifact("CapabilityRegistry.sol", "CapabilityRegistry");
const registry = await new ethers.ContractFactory(regArt.abi, regArt.bytecode, deployer).deploy(mockAddr);
await registry.waitForDeployment();

// ---------- gate behaviour ----------
check("gate: stranger is not a holder", !(await registry.isAgentIDHolder(await stranger.getAddress())));
const holderAddr = await holder.getAddress();
const txMint = await mock.connect(deployer).mint(holderAddr, GAS);
await txMint.wait();
check("gate: minted address is a holder", await registry.isAgentIDHolder(holderAddr));
check("gate: zero address is not a holder", !(await registry.isAgentIDHolder(ethers.ZeroAddress)));

// ---------- registry behaviour ----------
const epHash = ethers.keccak256(ethers.toUtf8Bytes("https://example.invalid/endpoint"));
await expectRevert("registry: non-holder cannot register", () => registry.connect(stranger).register.staticCall("X", "data", epHash));
const rtx = await registry.connect(holder).register("Helper One", "automation", epHash, GAS);
await rtx.wait();
check("registry: holder registered", await registry.isRegistered(holderAddr));
check("registry: totalRegistrants == 1", (await registry.totalRegistrants()) === 1n);
const prof = await registry.profileOf(holderAddr);
check("registry: profile fields round-trip", prof.displayName === "Helper One" && prof.category === "automation" && prof.endpointHash === epHash);

// update path (same holder re-registers = update, not duplicate)
await (await registry.connect(holder).register("Helper One", "payments", epHash, GAS)).wait();
check("registry: re-register updates, count stays 1", (await registry.totalRegistrants()) === 1n && (await registry.profileOf(holderAddr)).category === "payments");

// check-in: once per day
await (await registry.connect(holder).checkIn(GAS)).wait();
check("registry: check-in counted", Number(await registry.checkInCount(holderAddr)) === 1 && (await registry.totalCheckIns()) === 1n);
await expectRevert("registry: second check-in same day reverts", () => registry.connect(holder).checkIn.staticCall());
await expectRevert("registry: non-holder cannot check in", () => registry.connect(stranger).checkIn.staticCall());

// second holder
const holder2Addr = await holder2.getAddress();
await (await mock.connect(deployer).mint(holder2Addr, GAS)).wait();
await (await registry.connect(holder2).register("Second", "data", epHash, GAS)).wait();
check("registry: two registrants", (await registry.totalRegistrants()) === 2n);

// deregister: holder deregisters self; a second deregister must revert
await (await registry.connect(holder).deregister(GAS)).wait();
check("registry: deregister removes self", !(await registry.isRegistered(holderAddr)) && (await registry.totalRegistrants()) === 1n);
await expectRevert("registry: deregister when not registered reverts", () => registry.connect(holder).deregister.staticCall());

// owner controls
await expectRevert("owner: non-owner cannot pause", () => registry.connect(stranger).setPaused.staticCall(true));
await (await registry.connect(deployer).setPaused(true, GAS)).wait();
await expectRevert("owner: paused blocks registration", () => registry.connect(holder2).register.staticCall("Second", "data", epHash));
await (await registry.connect(deployer).setPaused(false, GAS)).wait();
check("owner: unpause restores flow", !(await registry.paused()));

// safety invariants on the compiled registry
const payableFns = regArt.abi.filter((e) => e.type === "function" && e.stateMutability === "payable");
check("safety: registry has zero payable functions", payableFns.length === 0);
const gateArt = artifact("AgentIDGate.sol", "AgentIDGate");
check("compile: AgentIDGate library compiled", gateArt.bytecode.length > 2);

summarize();
await server.close();
function summarize() {
  const failed = results.filter((r) => !r.pass);
  console.log(`\n${results.length - failed.length}/${results.length} checks passed`);
  fs.writeFileSync(path.join(root, "test-results.json"), JSON.stringify({ at: new Date().toISOString(), results }, null, 2));
  if (failed.length) process.exitCode = 1;
}
