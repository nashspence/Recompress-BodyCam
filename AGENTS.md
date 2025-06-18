## I. Formatting & Dependencies

1. **Code Style**

   * **Formatting:** run [`shfmt`](https://github.com/mvdan/sh) with flags `-w -i 2 -ci` on all `.sh`/`.zsh` files.
   * **Linting:** run [`shellcheck`](https://www.shellcheck.net) with `--severity=warning`.
   * **Workflow:** maintain `check.sh` that installs any required Homebrew tools and then runs `shfmt` + `shellcheck`. **Run `check.sh` before every push.**

2. **Dependency Management**

   * List every external CLI dependency (e.g. `jq`, `yq`, `git`, `awk`, etc.) in `macenv/Brewfile`, pinning each to the exact version you’ve tested.
   * **Verify** manually that the versions in `Brewfile` match your local environment before merging.

---

## II. Dev Environment

 **Bootstrap Script**

 ```
 macenv/
   Brewfile
   bootstrap.sh   # installs Homebrew (if missing) + `brew bundle --file="$PWD/Brewfile"`
 ```

 * **Humans** run `./macenv/bootstrap.sh` on first clone and whenever `Brewfile` changes.
 * **Agents** do **not** run `bootstrap.sh`; they rely on CI to catch missing deps.

---

## III. Features & Structure

1. **Atomic Scripts**

   * Each “feature” is a folder under `features/` in TitleCase, containing one or more cooperating scripts:

     ```
     features/
       BackupDotfiles/
         scripts/
           backup.zsh
         tests/
           backup.bats
         input/                # sample input files or env vars
         expected/             # expected outputs for test assertions
     ```
   * Ensure all `.zsh` files in `scripts/` are executable (`chmod +x`).

2. **Shared Library Code**

   * Put reusable functions in `shared/` as sourced modules (e.g. `shared/log.sh`, `shared/assert.sh`).
   * Never test `shared/` in isolation—always via a consuming feature’s test harness.

---

## IV. Testing & CI

1. **Local (Human) Testing**

   * On a real macOS machine, after `./macenv/bootstrap.sh`:

     ```bash
     ./check.sh                # formatting + linting
     for feature in features/*; do
       (cd "$feature" && ./tests/run_tests.sh)
     done
     ```
   * Humans must verify scripts behave as expected on their own Mac before pushing.

2. **GitHub Actions (Agent CI)**

   ```yaml
   name: CI

   on: [push]

   jobs:
     lint:
       runs-on: macos-latest
       steps:
         - uses: actions/checkout@v3
         - name: Agents Check
           run: ./check.sh

     test:
       runs-on: macos-latest
       env:
         CI: true
         SKIP_OSASCRIPT_UI: "1"   # bypass any macOS UI prompts
       strategy:
         matrix:
           feature: [BackupDotfiles, SyncPhotos, GenerateReport]
       steps:
         - uses: actions/checkout@v3
         - name: Run tests for ${{ matrix.feature }}
           run: |
             cd features/${{ matrix.feature }}
             ./tests/run_tests.sh
   ```

   > ⚠️ **UI Stubs:** Any `osascript` calls in `.zsh` must be guarded:
   >
   > ```zsh
   > if [[ -n $CI || -n $SKIP_OSASCRIPT_UI ]]; then
   >   echo "Skipping UI prompt in CI"
   > else
   >   osascript -e 'display dialog "Approve?"'
   > fi
   > ```

3. **Failure Reporting**

   * CI logs should end with:

     ```text
     ci failed, see below:
     <relevant log snippet>
     ```
   * Humans copy-paste that snippet into PR comments.

---

## V. Logging & Observability

Log well enough to fix build & test failures based off your logging alone.

---

## VI. Documentation

 * **Purpose & Audience:** e.g. “A set of macOS zsh scripts to automate backups and reports for power users.”
 * **Prereqs:** “macOS ≥ 10.15, Homebrew, zsh ≥ 5.8.”
 * **Features:** list each script with one-line description and link to its tests.
 * **Getting Started:** clone → `./macenv/bootstrap.sh` → `./check.sh` → `for feature; do …; done` → open PR.

---

## VII. Releases

Use `.github/workflows/release.yml`:

1. **Trigger:** on tag `vX.Y.Z`.
2. **Steps:**

   * Checkout + `brew bundle --file=macenv/Brewfile --no-upgrade`.
   * Archive scripts:

     ```bash
     tar czf my-scripts-vX.Y.Z.tar.gz \
         features/*/scripts/*.zsh shared/*.sh
     ```
   * Create GitHub Release, upload the tarball.
   * (Optional) Publish a Homebrew tap or update a formula.

---

## VIII. Maintenance

* **Refactor** monolithic scripts into smaller modules under `shared/`.
* **Convert** any `osascript` UI dialogs to CLI flags or headless mocks.
* **Sync** `macenv/Brewfile` whenever dependencies change.
* **Review** and bump pinned versions before you push.
