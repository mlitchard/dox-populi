<!-- 
Use this template for cleaning up code, optimizing performance, 
or consolidating redundant logic without changing user-facing features.
-->

## 🔧 Refactor Overview
<!-- What are we refactoring, and why? -->
We need to consolidate two similar Nix scripts into a single, reusable script.

## 📁 Target Files / Code Base
- [ ] `path/to/first-script.nix`
- [ ] `path/to/second-script.nix`

## 🎯 Goal & Benefits
<!-- Why take the time to do this? (e.g., reduces duplication, easier updates) -->
- Eliminates duplicate logic between the two files.
- Makes future configuration updates easier by having a single source of truth.

## 🧪 Verification & Testing Plan
<!-- Since functionality shouldn't change, how do we prove nothing broke? -->
- [ ] Run both configurations locally to ensure identical outputs.
- [ ] Verify the consolidated script passes `nix-instantiate` or standard evaluation checks.

***

<!-- AUTOMATION QUICK ACTIONS -->
/label ~"Type::Refactor" ~"Status::To Do"

