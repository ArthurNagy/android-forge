# Observability

## Tiered approach

**Default**: what Android gives you with nothing added — Play Console **Android Vitals**, Android Studio's
**App Quality Insights**, and **JankStats**-style frame metrics during development. **Opt-in**: Firebase
Crashlytics + Performance, or Sentry Android. Analytics is opt-in per project.

## Default: Android Vitals + App Quality Insights

Android Vitals captures, for Play-installed users: crash rate, ANR rate, excessive wakeups, slow/frozen
frames, startup time — Play Console ▸ Quality ▸ Android Vitals. Android Studio's **App Quality Insights**
window shows the same Vitals issues (and Crashlytics, if added) next to the code. Limits: Play installs only,
hourly batches, no breadcrumbs, nothing for sideloaded or App Distribution builds.

Enough when: store-only distribution, you can wait hours for crash data, and you don't need log context.

### Performance during development
- `android-profiler` skill (baseline tier) — record and analyze Perfetto traces: jank, startup, ANRs, memory.
- `jetpack-compose-performance` skill — recomposition and frame-time issues.
- Macrobenchmark + Baseline Profiles (`:benchmarks` opt-in) — startup and scroll numbers you can compare across releases.
- JankStats (`androidx.metrics:metrics-performance`) — add to `MainActivity` to log janky frames in debug.

## Opt-in: Firebase Crashlytics (+ Performance)

1. Create the Firebase project; download `app/google-services.json` (git-ignored; CI writes it from the
   `GOOGLE_SERVICES_JSON` secret).
2. Put the `com.google.gms:google-services` and `com.google.firebase:firebase-crashlytics-gradle` plugins on
   build-logic's classpath (catalog keys `googleServices`, `firebaseCrashlyticsPlugin`) and apply them in
   `app/build.gradle.kts`; add `implementation(platform(libs.firebase.bom))` + `firebase-crashlytics`
   (+ `firebase-perf` for performance traces).
3. Plant a release tree in `MainApplication`:
   ```kotlin
   if (BuildConfig.DEBUG) Timber.plant(Timber.DebugTree()) else Timber.plant(CrashlyticsTree())

   private class CrashlyticsTree : Timber.Tree() {
       override fun log(priority: Int, tag: String?, message: String, t: Throwable?) {
           if (priority < Log.WARN) return
           FirebaseCrashlytics.getInstance().log(message)          // breadcrumb
           if (t != null && priority >= Log.ERROR) FirebaseCrashlytics.getInstance().recordException(t)
       }
   }
   ```
4. R8 mapping uploads automatically with the Crashlytics plugin on `bundleRelease`.

Crash data then shows in App Quality Insights too.

## Opt-in: Sentry Android

`io.sentry:sentry-android` + the `io.sentry.android.gradle` plugin (auto-init via manifest meta-data, R8
mapping upload with `SENTRY_AUTH_TOKEN`). Use a `SentryTimberTree` (`sentry-android-timber`) so `Timber.w/e`
become breadcrumbs/events. DSN from `BuildConfig` (see [secrets.md](secrets.md)). Pick Sentry over
Crashlytics when you want real-time alerts, sideload coverage without Firebase, or one tool across several
non-Firebase projects.

## Analytics (opt-in, per project)

Not a default. Options: Firebase Analytics (pairs with Crashlytics), PostHog Android. Record the choice as an
ADR. Feature-owned events live in the feature module (`GalleryAnalytics.kt` over an injected client
interface from `:core:domain` or a `:core:analytics` module).

## What to log

- **Info**: user-initiated actions worth seeing as breadcrumbs ("opened photo:123").
- **Warn**: recoverable failures, retries, fallbacks — every `DomainError` produced at a boundary
  (`catchNetwork`, `catchStorage`) logs once with `Timber.w(e, …)` — a 404 that became `NotFound` included.
  Cancellation and `Error`s (OOM, stack overflow) are rethrown, not logged there: the crash reporter sees them.
- **Error**: unexpected states that should never happen.

`Timber.d` is for development: release builds plant no debug tree.

## Privacy

Never log PII: no emails, names, locations, photos or free-text input; hash IDs when you need correlation.
The `play-policy-insights` skill checks data-collection declarations against what the code does.
