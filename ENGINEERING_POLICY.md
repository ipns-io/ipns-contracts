# Engineering Policy

This policy keeps `ipns-contracts` safe for mainnet operations and Safe-governed admin actions.

## Commit and Push Rules

- Nothing is published without explicit commit and push.
- Keep commits scoped to one contract behavior/change set.
- Never commit private keys, raw signer exports, or secret env files.

## Branching Rules

- `main` must stay deployable.
- Use feature branches for all contract changes.
- Require PR review for state-changing logic.

## Test Policy (3 Layers)

1. Unit:
- Contract function/unit behavior tests.
- Access control and revert-path coverage.

2. Integration:
- Registry interaction flows (`register`, `setCID`, reserve/unreserve paths).
- Pricing and availability checks.

3. E2E/Onchain Smoke:
- Dry-run deployment or simulation for target network.
- Post-change RPC checks for critical flags/state.

## Deployment Safety

- Safe-controlled admin calls must be batched and reviewed.
- Record exact calldata, nonce, and signer confirmations before execution.
- Confirm onchain state after execution (`reserved`, `resolve`, ownership checks).

## Pre-Merge Checklist

- 3-layer tests completed (or exception documented)
- No secrets in repo diff
- Deployment runbook impacts documented
- Rollback/mitigation plan for risky state changes
