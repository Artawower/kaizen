# Engineering Rules

## SOLID (Robert C. Martin)

Apply SOLID pragmatically: give each module and function one clear responsibility; extend behavior through composition; preserve substitutability; keep interfaces narrow; and make high-level policy depend on stable abstractions. Prefer straightforward code over abstractions added only to demonstrate SOLID.

## Readability and Simplicity

Organize code by cohesive module or concept, not one file per type. Prefer small, clearly named functions and idiomatic Rust; local mutability for accumulating results is fine. Avoid speculative abstractions, registries, or mappings that do not serve current requirements.

## Testability and Side Effects

Keep filesystem, network, process, and environment access at the application boundary; pass paths and dependencies explicitly. Tests that read, write, or deploy files must use temporary directories and an isolated target home, never the real user home or process-global environment overrides.
