# Vendored dependencies

These files are checked into the project as ordinary source files. Builds and
tests never download dependencies. There are no submodules or linked external
libraries.

| Dependency | Version | Source | License | Use |
| --- | --- | --- | --- | --- |
| OpenZeppelin Contracts | `v5.1.0` | <https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.1.0> | MIT, `lib/openzeppelin-contracts/LICENSE` | Production ERC-20 |
| forge-std | `v1.9.6` | <https://github.com/foundry-rs/forge-std/tree/v1.9.6> | Apache-2.0 or MIT, licenses in `lib/forge-std/` | Tests only |

OpenZeppelin's vendored subset consists of `ERC20.sol`, `IERC20.sol`,
`IERC20Metadata.sol`, `Context.sol`, and `draft-IERC6093.sol` in their original
`contracts/` paths, plus the upstream license. forge-std includes the upstream
Solidity files under `src/` and both licenses. The source files are unmodified.

`DEPENDENCIES.sha256` records SHA-256 checksums for every vendored file. Check
the installed copy with `sha256sum -c DEPENDENCIES.sha256` from the project root.
