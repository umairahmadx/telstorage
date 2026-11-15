# Git Feature Branch, Pull Request & Repository Hygiene Rules

This rule module governs the Git operational lifecycle across all tasks in TelStorage. It exists to guarantee clean history, prevent branch drift, safeguard the canonical `main` branch, and ensure that the repository remains in an uncluttered, single-branch state.

---

## 1. Direct Commits to `main` Are Strictly Forbidden

- Work must **never** be committed or pushed directly to `main`.
- `main` is the production-ready source of truth. All modifications must land on `main` via GitHub Pull Requests.
- The local `main` branch must strictly track `origin/main` (`branch.main.merge = refs/heads/main`).

---

## 2. Post-Verification Branch Creation

1. When Phase 2 implementation and local verification (`flutter analyze`, `flutter test`, architecture guardrails) are complete, create a dedicated feature or fix branch from `main`:
   ```bash
   git checkout -b <type>/<short-description>
   ```
2. Standard branch prefix conventions:
   - `fix/`: Bug fixes, analyzer warnings, test compilation repairs.
   - `feat/`: New feature components, viewmodels, or capabilities.
   - `refactor/`: Structural or architectural refactoring without behavior change.
   - `chore/`: Dependency updates, tooling, or workflow configurations.

---

## 3. Conventional Commit Discipline

1. Stage all verified files (and verify zero unwanted files are staged):
   ```bash
   git add <modified-files>
   ```
2. Commit using the conventional commit format:
   ```bash
   git commit -m "<type>(<scope>): <summary>"
   ```
3. Commit messages must be clear, imperative, and describe the mechanism changed rather than generic phrasing like "fix bugs".

---

## 4. Push & Pull Request Creation (Squash-and-Merge Convention)

1. Push the branch to `origin` with upstream tracking:
   ```bash
   git push -u origin <type>/<short-description>
   ```
2. Open a Pull Request targeting base branch `main`:
   - Via GitHub CLI:
     ```bash
     gh pr create --base main --head <type>/<short-description> --title "..." --body "..."
     ```
   - Or by visiting the GitHub web compare URL output by `git push`.
3. **Squash and Merge Policy**: All PRs in this repository are merged using **Squash and merge**. This maintains a clean, linear git history on `main` and appends the PR number (`(#<pr-id>)`) to the commit title.

---

## 5. Post-Merge Cleanup & Main Synchronization

Immediately after the PR is merged on GitHub and the remote branch is deleted:
1. Switch local working tree back to `main`:
   ```bash
   git checkout main
   ```
2. Fetch remote with prune and fast-forward pull `origin/main`:
   ```bash
   git fetch origin --prune
   git pull origin main
   ```
3. Delete the merged local branch:
   ```bash
   git branch -d <type>/<short-description>
   ```
   *(Use `-D` if the squash-merge commit hash on remote differs from the local branch commit).*

---

## 6. Repository Single-Branch Invariant

At the conclusion of every task turn:
- **`git branch -l`** must list **only** `main`. No lingering local feature or fix branches may remain.
- **`git status`** must be completely clean with zero uncommitted changes.
- **`git branch -vv`** must confirm `* main` is up to date with `[origin/main]`.
- Stale tracking references must be pruned (`git fetch origin --prune`).
