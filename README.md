# WindowShopper (WWW)

A fixed-supply ERC-20 token built with Solidity 0.8.26 and the vendored
OpenZeppelin Contracts 5.1.0 ERC-20 implementation.

| Parameter | Value |
| --- | --- |
| Solidity contract | `src/WindowShopper.sol:WindowShopper` |
| Name | `WindowShopper` |
| Symbol | `WWW` |
| Decimals | `18` |
| Whole-token supply | `1,000,000,000` |
| Supply in base units | `1000000000000000000000000000` (`10^27`) |
| Named supply constant | `INITIAL_SUPPLY` |
| Constructor arguments | None |
| Initial recipient | The deploying caller, `msg.sender` |
| Application contracts | None |

## Behavior and assumptions

The constructor mints the entire supply once and emits one
`Transfer(address(0), deployer, INITIAL_SUPPLY)` event. There is no externally
accessible mint or burn, owner, pause, blacklist, seizure, upgrade mechanism,
transfer tax, or rebasing. Transfers deliver the exact requested amount and
preserve total supply. The token makes no external calls.

Standard ERC-20 `transfer`, `approve`, and `transferFrom` return `true` on
success and revert with OpenZeppelin ERC-6093 custom errors on failure.
Transfers and approvals to the zero address revert. Zero-value transfers
between valid addresses succeed and emit `Transfer`. Self transfers preserve
the holder's balance. Allowances are specific to each owner and spender;
finite allowances decrease when spent, including self transfers. The standard
`uint256` maximum allowance stays unchanged when spent. Explicit approvals
emit `Approval`; spending an allowance does not emit another `Approval`.

Approvals replace the previous allowance. Holders should revoke an existing
allowance to zero before granting a different amount to an untrusted spender,
and prefer approvals limited to the amount needed. Direct ETH payments revert.
Tokens sent to this token's own address, or other assets accidentally sent
here, have no recovery function.

## Build and check

Foundry and its Solidity 0.8.26 compiler must be installed. All Solidity
dependencies and their licenses are ordinary files under `lib/`; no package
installation, submodule initialization, RPC, environment configuration, or
network access is required once the compiler is installed.

```sh
forge build
FOUNDRY_FUZZ_SEED=0x9530c5973da1af7ab0ef047b1fa2d6b9e08d9f673621579a02bb3cb540297ede forge test
forge fmt --check
```

The compiler is pinned in `foundry.toml`, with Cancun EVM, optimization enabled
at 200 runs and `bytecode_hash = "none"`. Fuzz tests run 1,024 cases per test;
stateful invariants run 128 sequences of 64 operations. Tests create their own
state and use no environment reads, forks, or external services.

Tests cover metadata, constructor mint and event, factory and CREATE2
deployment, exact distribution, transfers, self and zero-value transfers,
approval replacement/revocation/isolation, finite and maximum allowances,
delegated transfers, invalid recipients, insufficient balance/allowance,
failure rollback, absent administrative entry points, and rejected ETH
payments. Fuzz tests exercise successful and invalid amounts. Stateful tests
compare balances and allowances against an independent model and check
constant supply and metadata after sequences of holder operations.

Local validation passed: `forge build`, seeded `forge test` (35 unit/fuzz
tests plus all three invariants over 8,192 handler operations),
`forge fmt --check`, and a fresh build with `--offline`. Slither and Mythril
were not run. The supplied protected launch tests require the verifier's
separate factory/pool harness and were read as acceptance inputs, not run
as part of this project's local suite.

## Deployment and responsibilities

The intended launch chain is Ethereum mainnet (chain ID 1). The token itself
does not depend on a chain ID, external addresses, services, or constructor
configuration. Deploy the compiled `WindowShopper` creation bytecode with no
constructor arguments and no ETH. The deployment artifact is
`out/WindowShopper.sol/WindowShopper.json`.

If deployed by a factory, the **factory** receives all `10^27` base units;
the transaction origin and requester receive nothing from the constructor.
The launch factory is responsible for subsequent distribution, pool funding,
and forwarding the remainder according to the separate launch policy. The
token does not reserve or distribute any supply itself. This project contains
no launch manifest and performs no broadcast transactions.

The authorized launch operator must check the compiled artifact and launch
parameters, confirm the initial recipient is the factory, perform the launch
distribution, and publish/verify the deployed source and contract address.
The factory and recipients control only the tokens they hold and allowances
granted to them; deploying the token grants no special powers over holders.

### After launch

There are no owner settings, initialization calls, maintenance transactions,
or administrative keys. Holders manage their balances and approvals. Confirm
the deployed metadata, total supply, constructor mint event, and resulting
distribution. An independent adversarial review remains a release
responsibility; the test suite is not a security audit.

## Dependency provenance

Only the required OpenZeppelin source files are included. The forge-std source
tree is included for tests. Neither library is modified. Versions and source
URLs are recorded in [DEPENDENCIES.md](DEPENDENCIES.md), with upstream licenses
preserved in each library directory.
