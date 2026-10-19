---
description: Adopt android-forge into an EXISTING Android project — overlay docs, CI, product workflow and Android skills non-destructively, then drive a reviewer-led, layer-by-layer refactor onto the locked stack (AGP 9 conventions, :core/:feature modules, Hilt, Orbit, Nav 3, Result+DomainError).
---

# /android-forge-adopt

Sibling of `/android-forge-init` for a project that **already exists** — no `android create`. It detects the
existing structure, applies the android-forge overlay **non-destructively**, and turns an `android-reviewer` audit into
a dependency-ordered refactor that the `android-migrator` agent executes one layer at a time.

- **Phase A — overlay** (this command): additive pieces applied automatically; files that already exist are rendered
  to scratch and hand-merged via diff. Never blind-clobbers.
- **Phase B — refactor** (reviewer-driven): audit → work-list → one migrator layer at a time, build + re-review between.

Execute steps **in order**. Stop and ask when unclear. Everything happens on a branch.

## Conventions

- Quote paths and brace variables (`"${TARGET}"` — the Bash tool may run zsh; the folder may contain spaces).
- **Never blind-overwrite.** An existing target → render to scratch (`"${TMPDIR:-/tmp}/aforge-*"`),
  `git --no-index diff`, merge with the Edit tool after showing the user. `apply-overlay.sh render … --no-clobber`
  keeps existing files.
- The plugin never pushes, never enables branch protection.

### 0. Preconditions + safety

Run from the **root of the existing project**:

```bash
TARGET="$PWD"
[[ -f "${TARGET}/settings.gradle.kts" || -f "${TARGET}/settings.gradle" ]] || { echo "✗ no settings.gradle(.kts) — run from the project root"; exit 1; }
grep -rqlE "com\.android\.(application|library)" --include="*.gradle*" --include="*.toml" "${TARGET}" \
  || { echo "✗ no Android Gradle plugin found — not an Android project"; exit 1; }
grep -rqlE "org\.jetbrains\.kotlin\.multiplatform|kotlin\(\"multiplatform\"\)" --include="*.kts" "${TARGET}" \
  && echo "⚠ Kotlin Multiplatform detected — kmp-forge (/kmp-forge-adopt) is the right plugin for KMP projects"
[[ -f "${TARGET}/gradle/libs.versions.toml" ]] || echo "⚠ no version catalog — the build layer creates one"
git -C "${TARGET}" diff --quiet && git -C "${TARGET}" diff --cached --quiet \
  || { echo "✗ working tree dirty — commit or stash first"; exit 1; }
```

Then `git -C "${TARGET}" switch -c chore/adopt-android-forge`, after confirming via `AskUserQuestion` that the user
understands many files will change (on a branch, reversible).

### 1. Detect the existing structure

```bash
grep -nE "include\(" "${TARGET}"/settings.gradle*                                    # modules
grep -rnE "com\.android\.(application|library)|kotlin-kapt|org\.jetbrains\.kotlin\.android" --include="*.gradle*" "${TARGET}" | head -20
grep -nE "^(agp|androidGradlePlugin|kotlin|hilt|koin|room|navigation|composeBom|androidxComposeBom)\b" "${TARGET}/gradle/libs.versions.toml" 2>/dev/null
for lib in "dagger.hilt" "io.insert-koin" "org.orbit-mvi" "androidx.navigation:navigation-compose" "androidx.navigation3" \
           "androidx.room:" "androidx.room3" "retrofit2" "io.ktor" "androidx.fragment" "setContentView"; do
  grep -rqlF "${lib}" --include="*.kt" --include="*.kts" --include="*.toml" --include="*.gradle" "${TARGET}" && echo "has ${lib}"
done
grep -rnE "screenOrientation|resizeableActivity" --include=AndroidManifest.xml "${TARGET}" | head
android describe --project_dir="${TARGET}" 2>/dev/null | grep -E "^Task:" | head      # app modules the Android CLI sees
```

Infer `BASE_PACKAGE` (the app module's `namespace`/`applicationId`), the app name, minSdk, form factors (Wear/TV/
Automotive modules, Car App Library, Leanback), the UI toolkit (Compose vs Views/fragments), DI, navigation,
persistence. Present the map and confirm via `AskUserQuestion` (especially: which module is the app, which modules
are features).

### 2. Overlay variables

Same as `/android-forge-init` step 2, **inferred** and confirmed: `APP_NAME`, `APP_TAGLINE`, `BASE_PACKAGE`,
`BASE_PACKAGE_PATH`, `MIN_SDK` (the app's), `SCAFFOLD_DATE`, `FORM_FACTORS` (detected), `BUILD_COMMANDS`,
`MODULE_LIST` (the REAL modules), `FEATURE_LIST`, `OPTIONAL_LIBS` (detected), `FIGMA_URL`, `PROJECT_OVERRIDES`,
`TIMELINE`, `USE_OPENSPEC` (yes when `openspec/` exists; else ask as init does — OpenSpec ≥ 1.14, never install
without an answer), `SPEC_WORKFLOW` (copy init's `if … fi` block verbatim, single quotes). Persist them with
`typeset -p … > "${TMPDIR:-/tmp}/android-forge-adopt.env"` and `source` it in every later block.

### 3. Phase A — additive (automatic)

```bash
source "${TMPDIR:-/tmp}/android-forge-adopt.env"; : "${TARGET:?}" "${BASE_PACKAGE:?}"
OVERLAY="${CLAUDE_PLUGIN_ROOT}/overlay"; SH="${CLAUDE_PLUGIN_ROOT}/scripts/apply-overlay.sh"
copy_new() {   # copy only if absent; otherwise show the diff for a hand-merge
    if [[ -e "$2" ]]; then echo "=== exists, not replaced — diff (existing ← → android-forge): $2"; git --no-pager diff --no-index "$2" "$1" || true
    else mkdir -p "$(dirname "$2")" && cp "$1" "$2" && echo "added: $2"; fi
}

# Secrets hygiene
copy_new "${OVERLAY}/git/.gitleaks.toml" "${TARGET}/.gitleaks.toml"
copy_new "${OVERLAY}/git/pre-commit-hook.sh" "${TARGET}/.android-forge-pre-commit.sh"; chmod +x "${TARGET}/.android-forge-pre-commit.sh"
HOOK="$(git -C "${TARGET}" rev-parse --git-path hooks/pre-commit)"; [[ "${HOOK}" = /* ]] || HOOK="${TARGET}/${HOOK}"
if [[ ! -e "${HOOK}" ]]; then cp "${TARGET}/.android-forge-pre-commit.sh" "${HOOK}" && chmod +x "${HOOK}" && echo "installed: pre-commit hook"
elif ! grep -q "android-forge-pre-commit" "${HOOK}"; then echo '⚠ existing pre-commit hook — chain: "$(git rev-parse --show-toplevel)/.android-forge-pre-commit.sh" || exit 1'; fi

# Product docs + ADRs, gap-filling only
rm -rf "${TMPDIR:-/tmp}/aforge-product" && bash "${SH}" render "${OVERLAY}/product" "${TMPDIR:-/tmp}/aforge-product"
copy_new "${TMPDIR:-/tmp}/aforge-product/MVP_SPEC.md" "${TARGET}/docs/MVP_SPEC.md"
for adr in "${TMPDIR:-/tmp}/aforge-product/DECISIONS/"*.md; do copy_new "${adr}" "${TARGET}/docs/DECISIONS/$(basename "${adr}")"; done

# Android skills — baseline tier (+ the detected form factors' tiers, + `adopt` for the migration skills)
bash "${CLAUDE_PLUGIN_ROOT}/scripts/skills.sh" install "${TARGET}" baseline adopt
```

Add each detected form factor's tier too (`wear`, `tv`, `cars`, …). Report every result.

**OpenSpec** (`USE_OPENSPEC=yes`): render `${CLAUDE_PLUGIN_ROOT}/overlay/openspec` to scratch; with an existing `openspec/`, merge
android-forge's `context`/`rules`/`operations` into its `config.yaml` by hand; else `openspec init --tools claude
--no-animation "${TARGET}"` and copy the rendered `config.yaml` over the stub.

**Issue labels** — only if `origin` is on GitHub and the user says yes (it writes to GitHub):
`(cd "${TARGET}" && bash "${CLAUDE_PLUGIN_ROOT}/scripts/issues.sh" labels)`.

### 4. Phase A — overwrite-danger (scratch + diff + merge)

```bash
bash "${SH}" render "${OVERLAY}/root" "${TMPDIR:-/tmp}/aforge-root"
for f in CLAUDE.md .gitignore .editorconfig cliff.toml; do
    if [[ -f "${TARGET}/${f}" ]]; then echo "=== diff: ${f}"; git --no-pager diff --no-index "${TARGET}/${f}" "${TMPDIR:-/tmp}/aforge-root/${f}" || true
    else cp "${TMPDIR:-/tmp}/aforge-root/${f}" "${TARGET}/${f}" && echo "added: ${f}"; fi
done
```

`CLAUDE.md`: merge the android-forge sections (the "android-forge project rules" line, stack, doc links, Android CLI
& skills) into the existing one — never replace the user's guidance. `.editorconfig`: the ktlint keys matter
(Spotless reads them).

### 5. Phase A — CI workflows

```bash
rm -rf "${TMPDIR:-/tmp}/aforge-ci" && bash "${SH}" render "${OVERLAY}/ci" "${TMPDIR:-/tmp}/aforge-ci"
for wf in pr.yml release.yml spec-link.yml; do copy_new "${TMPDIR:-/tmp}/aforge-ci/${wf}" "${TARGET}/.github/workflows/${wf}"; done
copy_new "${OVERLAY}/git/pull_request_template.md" "${TARGET}/.github/pull_request_template.md"
for t in "${OVERLAY}/git/ISSUE_TEMPLATE/"*.yml; do copy_new "${t}" "${TARGET}/.github/ISSUE_TEMPLATE/$(basename "${t}")"; done
```

Exactly one workflow must run the gate — `spotlessCheck lint coverageVerify -Proborazzi.test.verify=true assembleDebug`.
Until Phase B's `build` layer lands, those tasks don't exist yet: keep `pr.yml` but tell the user the gate turns
green only after the `build` and `tests` layers.

### 6. Phase B — audit

Invoke **`android-forge:android-reviewer`** over the whole codebase (every module) and aggregate its findings. Turn them into a
**dependency-ordered work-list** — the layer keys map 1:1 to the `android-migrator`'s `layer` input:

1. `build` — AGP 9 + built-in Kotlin + KSP (via the `agp-9-upgrade` skill), `build-logic` conventions, the catalog
   (`patch-libs`), `android-forge.root` (gate tasks). Everything after relies on it.
2. `modules` — `:core:*` + `:feature:*:{api,impl}`; features stop depending on data modules. Per area.
3. `dispatchers` — `DispatcherProvider` instead of `Dispatchers.*`.
4. `result` — `Result<T, DomainError>`; `catchNetwork`/`catchStorage` boundaries; no `try/catch` in ViewModels.
5. `repos` — one repository per domain type.
6. `hilt` — Hilt with constructor injection (from Koin / Dagger / manual DI). Per module.
7. `orbit` — state-only Orbit ViewModels (from StateFlow/LiveData MVVM or effectful Orbit). Per screen.
8. `nav` — Navigation 3 keys + `@IntoSet` entries (from Navigation 2 / fragments; XML screens go through the
   `migrate-xml-views-to-jetpack-compose` skill first — each screen is its own step).
9. `visibility` — `internal` everything that isn't cross-module API; `State.Initial`, no defaults.
10. `tests` — fakes, Orbit harness, Robolectric screen tests, phone + tablet goldens, the 75% gate.
11. `a11y` — strings with module prefixes, descriptions, typography, start/end.
12. `adaptive` — no orientation locks, window-size layouts, list-detail scenes, edge-to-edge.

Present the plan (counts per layer) and refactor **one layer at a time** by delegating to the
**`android-forge:android-migrator`** agent with `project_root`, `base_package`, `claude_plugin_root`, `layer` (and
`target` for per-area / per-screen layers). The user confirms between layers; never fire them all at once. After each
layer, re-run `android-forge:android-reviewer` on the touched files.

### 7. Verify

After the `build` layer, and after every later one:

```bash
./gradlew spotlessCheck lint coverageVerify assembleDebug -Proborazzi.test.verify=true
```

(`coverageVerify` will fail below 75% until the `tests` layer — say so; don't lower the bound.) Run the app on an
emulator (`android emulator start …`, `android run --apks=…`) after `hilt` and `nav`.

### 8. Report

```
✓ Branch: chore/adopt-android-forge
✓ Docs + ADRs: added/merged · Android skills: baseline<+ tiers> in .claude/skills/
✓ CI: pr.yml / release.yml / spec-link.yml added<, merged>
✓ Spec workflow: <OpenSpec with android-forge rules | plain docs>; issue labels <created | skipped>
~ CLAUDE.md / .gitignore / .editorconfig: merged (review the diffs)

Phase B remaining (android-reviewer): <N> blocking, <N> warn, <N> nits — by layer:
  [ ] build  [ ] modules  [ ] dispatchers  [ ] result  [ ] repos  [ ] hilt
  [ ] orbit  [ ] nav  [ ] visibility  [ ] tests  [ ] a11y  [ ] adaptive

Next: work the layers top-down; the gate must pass before merging; open a PR from chore/adopt-android-forge.
```

## Notes

- Non-destructive by design; if a script errors, surface it verbatim and stop (the branch keeps it safe).
- Phase B is a guided refactor: big surfaces go per area / per screen with a build and a review between steps.
