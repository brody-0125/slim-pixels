# Contributing

Use small, focused branches and pull requests against `main`.
Use Conventional Commits: `feat:`, `fix:`, `refactor:`, `test:`, `docs:`, or `chore:`. Describe the change, not the editing process. Mark breaking changes with `!` and explain migration steps.

## Checks

- Run `dart pub get --enforce-lockfile` and `dart analyze --fatal-infos`.
- Format Dart with the latest stable SDK and Rust with `cargo +1.97.1 fmt --manifest-path native/Cargo.toml`.
- Follow [CI.md](CI.md) for native builds and JIT/AOT checks, and [GATES.md](GATES.md) for full quality/memory gates.
- Describe what was tested and any unavailable environment in the PR. A local subset is not a full CI pass.
- Do not regenerate golden outputs just to make a failing gate pass. Submit baseline changes with explicit quality evidence and provenance review.

Keep generated builds, local logs and credentials out of commits. The native Windows DLLs and golden fixtures are intentional versioned inputs; preserve their third-party notices. Configure the `required` check as a branch protection requirement when a GitHub remote is created. Publishing is separate from merging: `publish_to: none` remains intentional.
