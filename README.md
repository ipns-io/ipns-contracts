# ipns-contracts

Apache-2.0 licensed contracts for `ipns`.

## What’s Here

- `src/IPNSRegistry.sol`: main registry contract (names, renewals, pricing, subnames)
- `src/oz/*`: minimal vendored utility contracts (Ownable/ReentrancyGuard/EIP712/ECDSA)
  - Note: in production you likely swap these for full OpenZeppelin once networked dependency install is available.

## Pinned Decisions (This Thread)

### Subnames (v1) + Upgrade Path (v2)

- v1 ships **parent-controlled subnames**.
  - Example: owner of `alice` can set `blog.alice` without delegating ownership.
  - Implemented as `_subnames[parentKey][labelKey]`.
- Storage includes `SubRecord.owner` but it is **unused in v1**.
  - Reserved for **delegated subname ownership** later (v2) without migrating storage.
- Resolution behavior:
  - `resolveSub(parent, label)` returns the subname CID if set.
  - If no subname CID is set, it **falls back to the parent CID**.
- Planned v2 extension (not implemented yet):
  - `setSubOwner(parent, label, to)` (parent assigns).
  - `setSubCID` allows either parent owner (if subOwner unset) or delegated `subOwner` (if set).

## Foundry Quickstart (Walkthrough)

From `/Users/guy3/Documents/guy3/ipns-contracts`:

Note: in this Codex sandbox, Foundry can’t write to `~/.foundry`, so set `XDG_CACHE_HOME` to a project-local directory:

```bash
export XDG_CACHE_HOME="/Users/guy3/Documents/guy3/ipns-contracts/.xdg-cache"
```

1. Build:
```bash
forge build
```

2. Run tests:
```bash
forge test -vv
```

3. Start a local chain (optional):
```bash
anvil
```

4. Deploy locally (after adding a deploy script):
```bash
forge script script/Deploy.s.sol:Deploy --rpc-url http://127.0.0.1:8545 --broadcast
```

## Mainnet Deployment Inputs

`script/Deploy.s.sol` requires:

- `INITIAL_OWNER` (recommended: multisig/safe)
- `TREASURY` (recommended: multisig/safe)
