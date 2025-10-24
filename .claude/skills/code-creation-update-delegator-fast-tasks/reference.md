# Delegation Reference (Creation & Updates)

## Grok-Code-Fast-1 Specs
- Trigger: For new builds or refinements; skip for minor tweaks.
- Quotas: 400 RPM; prioritize dense specs.
- Outputs: Favor "full" for creation, "highlighted" for updates.

## Errors
- 429: Local fallback for creation sketches.
- 400: Reprompt with explicit structure.

## Best Practices
- Spec First: Always detail interfaces, deps, and tests.
- Chain Delegations: Create base → Update iteratively.
