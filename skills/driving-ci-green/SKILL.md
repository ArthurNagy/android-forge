---
name: driving-ci-green
description: Watch a PR's GitHub Actions checks and drive them to green from the CLI in an android-forge-scaffolded project, without flooding the context window with CI logs. Use in an android-forge project (its CLAUDE.md says "android-forge project rules") when watching PR checks after a push, diagnosing a red check, mirroring the CI gate locally before pushing, or when an agent needs the canonical gh commands for CI status and failure logs.
---

# Driving CI green — android-forge style

The android-forge PR gate lives in `.github/workflows/pr.yml` (rendered from the plugin's `overlay/ci/pr.yml.tmpl`). This skill is the one place that defines how to watch it, read its failures, and mirror it locally. CI logs run to megabytes — every command here is shaped to keep them out of the context window.

## Watch, don't poll

**1. Wait for the checks to register.** Right after `gh pr create` or a push, GitHub has not attached the workflow runs yet, and `gh pr checks` exits **1** with `no checks reported on the '<branch>' branch` — the same exit code as a failed check. Never read that as red. Wait until at least one check exists (bounded, ~3 min):

```bash
for i in $(seq 1 18); do
  n=$(gh pr checks <pr> --json name --jq length 2>/dev/null) && [ "${n:-0}" -gt 0 ] && break
  sleep 10
done; echo "checks registered: ${n:-0}"
```

Still `0` after the loop → the workflow is not triggering (missing `pr.yml`, a path filter, Actions disabled). Report that; do not keep watching.

**2. Watch.**

```bash
err="${TMPDIR:-/tmp}/ci-watch-<pr>.err"   # per PR: parallel loop workers must not share it
gh pr checks <pr> --watch --fail-fast --interval 20 >/dev/null 2>"${err}"; rc=$?
echo "exit=${rc}"; grep -q "no checks reported" "${err}" && echo "NOT REGISTERED — back to step 1"
```

Run it with a Bash `timeout` of `600000` (10 min). Exit meanings:

- `0` — all checks green.
- `1` — a check failed — **unless** stderr says `no checks reported` (then go back to step 1; nothing failed).
- `8` — checks still pending when the command returned.

If the *Bash call itself* times out, simply re-run it — the checks resume server-side. After 3 such timeouts (~30 min wall), stop and report `CI: timeout` rather than watching forever.

Never busy-poll `gh pr checks` without `--watch`, and never dump its table repeatedly — one wait + one watch per push is the pattern.

## Reading failures without flooding context

`gh run view --log-failed` without a run id is interactive (it prompts you to pick a run) and errors out in a non-interactive session. Resolve the failing run for the PR's head commit first:

```bash
sha=$(gh pr view <pr> --json headRefOid --jq .headRefOid)
run=$(gh run list --commit "$sha" --json databaseId,conclusion \
        --jq '[.[] | select(.conclusion == "failure")][0].databaseId')
gh run view "$run" --log-failed 2>&1 | tail -100
```

Never run `gh run view --log-failed` unpiped. Always `| tail -100`; widen to `tail -300` only if the first 100 lines genuinely do not contain the error. If `$run` is empty, no run on the head commit has failed — re-check `gh pr checks <pr>` (a failing check may come from an external status, not a workflow run).

The gate uploads a `reports` artifact even when it fails (Lint HTML, test reports, JaCoCo, Roborazzi diffs):
`gh run download "$run" -n reports -D "${TMPDIR:-/tmp}/ci-reports-<pr>"`, then read only the file the log names.

### Red step → fix

| Red step | Fix |
|---|---|
| `spotlessCheck` | `./gradlew spotlessApply`; a compose-rules finding needs a code change, not a reformat |
| `lint` | Lint warnings are errors — fix the finding; a baseline entry or `@Suppress` is not a fix. A fixed finding still reported locally (seen after a manifest edit: AGP kept the old report) → `./gradlew :<module>:clean`, then re-run |
| `coverageVerify` — a test failed | read the test report; fix the code or the test that encodes the wrong expectation |
| `coverageVerify` — below 85% | add tests for the new code (ViewModel, use case, repository); never widen the excludes |
| Roborazzi "differs from" / lacks its golden | an intended new or changed screen → `./gradlew recordRoborazziDebug`, look at the PNGs, commit them; an unintended diff → fix the UI |
| `assembleDebug` | compile error — usually a module dependency or a missing catalog alias |
| `spec-link` | a `feat:` PR touching `src/main/` without an OpenSpec change: add the change, or the `no-spec` label when it deliberately has no spec-visible behavior |

## Mirror CI locally before pushing

The CI gate (see `overlay/ci/pr.yml.tmpl`) runs, in order: `spotlessCheck`, `lint`, `coverageVerify -Proborazzi.test.verify=true` (every module's unit tests + screenshot verification + the 85% JaCoCo gate), `assembleDebug`. Mirror it locally with the auto-fix variant before every push:

```bash
gate_log="${TMPDIR:-/tmp}/gate.log"
{ ./gradlew spotlessApply && ./gradlew spotlessCheck lint coverageVerify assembleDebug -Proborazzi.test.verify=true; } > "${gate_log}" 2>&1; rc=$?
tail -80 "${gate_log}"; echo "gate exit=${rc}"
```

Read the exit code, not the tail: piping Gradle straight into `tail` reports `tail`'s status, so a red build looks
green. A change that adds or intentionally changes a screen runs `./gradlew recordRoborazziDebug` first and commits
the new goldens.

`spotlessApply` auto-fixes formatting (CI runs the check-only `spotlessCheck`). Iterate until this is clean — a push with a locally-red build wastes a CI cycle. Do not weaken the gate to pass it: no lowering the JaCoCo threshold or widening its excludes, no deleting or `@Ignore`-ing a test, no Lint baseline entry or `@Suppress` to silence a real finding, no re-recording a screenshot golden to make an unintended UI change pass.

## Context discipline

- Send every noisy command to a log and tail the log, keeping the command's exit code — the gate block above is the pattern. Never pipe Gradle straight into `tail`.
- `git diff --stat` before `git diff`; prefer reading the specific file a failure names over globbing the module.
- Fix-read cycles happen where the work is: read the failing test/file, fix, re-run the local mirror, push once.

## Fix-cycle budget

Two red-CI fix cycles per PR is the budget: red CI → read failure → fix → push → re-watch, at most twice. Still red after the second cycle? Stop and report the failure precisely (what failed, what you tried) instead of thrashing — a human decision is cheaper than a third blind attempt.
