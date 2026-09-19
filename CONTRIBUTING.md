# Contributing

Use small, focused branches. During a release cycle, base feature/fix branches on
the active `release/vX-Y-Z` branch and target that branch with pull requests.
Merge the release documentation branch last, then review the release into `main`.
Outside a release cycle, target `main`.
Use Conventional Commits: `feat:`, `fix:`, `refactor:`, `test:`, `docs:`, or `chore:`. Describe the change, not the editing process. Mark breaking changes with `!` and explain migration steps.

## Checks

- Run `dart pub get --enforce-lockfile` and `dart analyze --fatal-infos`.
- Run `python tool/api_contract_check.py dart` and `python tool/docs_check.py dart`.
- Format Dart with the latest stable SDK and Rust with `cargo +1.97.1 fmt --manifest-path native/Cargo.toml`.
- For native builds, JIT/AOT checks, and quality/memory gates, see `.github/workflows/ci.yml` and `tool/`.
- Describe what was tested and any unavailable environment in the PR. A local subset is not a full CI pass.
- Do not regenerate golden outputs just to make a failing gate pass. Submit baseline changes with explicit quality evidence and provenance review.

Keep generated builds, local logs and credentials out of commits. The native Windows DLLs and golden fixtures are intentional versioned inputs; preserve their third-party notices. Configure the `required` check as a branch protection requirement when a GitHub remote is created. Publishing is separate from merging: `publish_to: none` remains intentional.
