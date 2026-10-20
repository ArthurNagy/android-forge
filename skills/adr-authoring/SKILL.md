---
name: adr-authoring
description: Author or supersede an Architecture Decision Record in an android-forge project (its CLAUDE.md says "android-forge project rules") — Nygard format in docs/DECISIONS/NNNN-kebab-title.md, next free number, Context with alternatives considered, Decision, Consequences. Use when recording why a stack, module or architecture choice was made, adopting an opt-in library (Room, Retrofit, WorkManager, Crashlytics/Sentry, gradle-play-publisher), adding a form factor with real alternatives, changing distribution or observability tier, superseding an earlier ADR, or when /android-forge-add-library, /android-forge-refine or the android-architect agent calls for an ADR.
---

# ADR authoring — android-forge style

ADRs live in `docs/DECISIONS/NNNN-kebab-case-title.md`. They capture *why* a non-obvious decision was made — the kind of thing you'd otherwise re-debate every six months.

## Format (Michael Nygard)

```markdown
# NNNN. <title>

Date: YYYY-MM-DD
Status: Accepted | Accepted (supersedes [NNNN](NNNN-...)) | Superseded by [NNNN](NNNN-...) | Deprecated

## Context
<what's driving this decision? what's the problem or the constraint?>

Alternatives considered:
- **<option>** — <why it loses here>
- **<option>** — <why it loses here>

## Decision
<imperative, starting with the verb: "Use …", "Adopt …" — concrete, action-oriented>

## Consequences
<what becomes easier, what becomes harder, what reviewer must enforce going forward>
```

## File naming

`NNNN-kebab-case-title.md` where:

- `NNNN` is the highest number in `docs/DECISIONS/` plus one, four digits — never reused, never reordered
- title is kebab-case, brief (3–6 words)

Examples:
- `0010-add-room-for-photo-cache.md`
- `0012-switch-to-posthog.md`
- `0018-extract-auth-module.md`

## Status

- **Accepted** — current decision
- **Accepted (supersedes [NNNN](NNNN-...))** — current decision that replaces an earlier ADR (§ Updating decisions)
- **Superseded by [NNNN](NNNN-...)** — replaced by a later ADR; this ADR is read-only history
- **Deprecated** — no longer relevant (the thing it governed is gone); left for context

Never edit an Accepted ADR's substance. Write a new ADR that supersedes it.

## When to write an ADR

✓ Adopting an opt-in library (Room, Retrofit, Crashlytics/Sentry, WorkManager, gradle-play-publisher)
✓ Changing a core stack choice (Hilt → Metro — rare; supersedes 0002)
✓ Adding a form factor whose design has real alternatives (Wear standalone vs companion, TV in the phone APK vs `:tv`)
✓ Architectural decisions affecting 2+ modules (extracting `:core:auth`, splitting `:core:data` per area)
✓ Distribution tier change (graduating from GitHub Releases to Play Store)
✓ Observability tier change (opting into Sentry)
✓ Per-project decisions that diverge from android-forge defaults
✓ A leaked secret — `NNNN-secret-rotation.md`: date, secret type, scope, remediation ([secrets.md](../../docs/secrets.md))

✗ Library version bumps (no ADR; just commit)
✗ Internal refactors with no architectural impact
✗ Bug fixes
✗ UI / design changes (those live in Figma + design tokens)

## Pre-seeded ADRs (from android-forge overlay)

Every scaffolded project ships with these 9, documenting the locked-stack rationale:

- `0001-orbit-mvi.md` — why Orbit (state-only) over a hand-rolled ViewModel + StateFlow / Molecule / Circuit
- `0002-hilt.md` — why Hilt over Metro / Koin
- `0003-modules.md` — why `:core:*` + `:feature:*:{api,impl}`, features seeing only `:core:domain`
- `0004-nav3.md` — why androidx Nav 3 (api keys, `@IntoSet` entries) over Navigation 2 / Compose Destinations
- `0005-result-domain-error.md` — why kotlin-result (Result<V, E>) + sealed DomainError over Arrow / exceptions
- `0006-dispatcher-provider.md` — why inject DispatcherProvider
- `0007-lint-over-detekt.md` — why Android Lint + compose-lints, ktlint + compose-rules, without detekt (AGP 9)
- `0008-jacoco.md` — why JaCoCo through AGP over Kover (AGP 9)
- `0009-app-module-per-form-factor.md` — why Wear / TV / AAOS get their own app modules

A new ADR takes the highest number in `docs/DECISIONS/` plus one — `0010` in a fresh scaffold, later in an adopted
project that already had ADRs. Commit ADRs on their own as `docs(adr): <title>` (what `/android-forge-refine`
tells the user to do).

## Writing tips

### Context section

State the *forcing function* — what made this decision necessary? Not "we should do X"; instead "we need X because Y, and the existing approach doesn't work because Z."

✓ "Crashes from our Firebase App Distribution testers never reach Play Vitals (it covers Play installs only), and Vitals has no breadcrumbs — we ship betas weekly and can't debug them."

✗ "We need crash reporting." (no forcing function — leaves the reader wondering why now)

### Decision section

Imperative, starting with the verb — "Use X", "Adopt X" — like the seeded ADRs.

Include the specific shape of the adoption — version, library, idiomatic snippet. Reviewer should be able to enforce it.

✓ "Adopt Firebase Crashlytics (Firebase BOM, `firebase-crashlytics` + its Gradle plugin through build-logic) in every app module. Plant a release `Timber.Tree` that records `Timber.w` as breadcrumbs and `Timber.e` with a throwable as non-fatals. `google-services.json` is written in CI from the `GOOGLE_SERVICES_JSON` secret."

✗ "Add Sentry." (no shape)

### Consequences section

Three pillars:
- **Easier** — what does this unlock or simplify?
- **Harder** — what new ongoing cost does it create?
- **Enforced** — what must every PR now respect? `android-reviewer` enforces the rules in the project's CLAUDE.md
  § Project-specific overrides, not the ADRs themselves — so copy each enforceable rule there as one line
  (`- <rule> (ADR NNNN)`), in the same commit as the ADR.

✓
> - Easier: tester and store crashes in one dashboard (and in Studio's App Quality Insights); breadcrumbs from Timber attached.
> - Harder: `GOOGLE_SERVICES_JSON` secret to manage; another SDK and Gradle plugin to bump on `/android-forge-bump-stack`.
> - Enforced (copied to CLAUDE.md § Project-specific overrides): don't log raw user input (PII); add `Timber.w`/`Timber.e` calls at semantic boundaries.

### Length

Usually under ~60 lines — the seeded ADRs are 20–35. ADRs are not specs; they're decision logs. If you find yourself writing implementation detail, link to code or a doc instead.

## Updating decisions

Don't edit Accepted ADRs in place. Write a new ADR that supersedes:

```markdown
# 0014. Switch from kotlin-result to Arrow Either

Date: 2026-09-01
Status: Accepted (supersedes [0005](0005-result-domain-error.md))

## Context
After 18 months, multi-step domain workflows have grown verbose even with kotlin-result's `coroutineBinding`; we want Raise's typed-error effect scopes...

## Decision
Adopt arrow-kt's Either<DomainError, T> with Raise DSL across :core:domain...
```

Then update `0005-result-domain-error.md`:

```diff
- Status: Accepted
+ Status: Superseded by [0014](0014-switch-to-arrow-either.md)
```

(That's the *only* edit to an Accepted ADR that's allowed.)

## Linking ADRs

Use relative paths within the project:

```markdown
See [0003 — Module shape](0003-modules.md) for module-layout rationale.
```

For cross-project plugin docs, use the full GitHub URL:

```markdown
See [architecture.md](https://github.com/arthurnagy/android-forge/blob/main/docs/architecture.md).
```
