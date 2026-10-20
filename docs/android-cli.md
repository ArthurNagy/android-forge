# Android CLI and Android skills

android-forge leans on Google's **Android CLI** (`android`, installed by `/android-forge-doctor`) for
everything that touches the SDK, devices or official docs, and on Google's **Android agent skills** for
task know-how. This page is the map: which command each android-forge component uses, the emulator
profiles per form factor, and the skill tiers.

## Commands and who uses them

| CLI command | Used by | For |
|---|---|---|
| `android create empty-activity` | `/android-forge-init` (`scripts/android-new.sh`) | the base project |
| `android sdk list` / `install` | doctor, init (`ensure-sdk`), `scripts/avd.sh` | compile platform, system images per form factor |
| `android skills add` / `list` / `update` (`--project --agent claude-code`) | init, add-form-factor, add-library, doctor (`scripts/skills.sh`) | project-scoped Android skills |
| `android docs search` / `fetch kb://…` | architect, implementer, feature-builder, form-factor-builder, add-library, bump-stack | current official guidance before using an unfamiliar or pre-stable API |
| `android studio version-lookup` | bump-stack, add-library (`scripts/fetch-latest-versions.sh`, when Studio runs) | latest versions, cross-checked with Maven metadata |
| `android studio check` | doctor, add-library, bump-stack | whether a Studio is running (`version-lookup` needs one) |
| `android describe` | android-qa, add-form-factor, adopt, release skill | where each module's APK/AAB lands (no hard-coded paths) |
| `android emulator list` / `start` / `stop` / `create` | android-qa, add-form-factor, init, `scripts/avd.sh` | phone/tablet/desktop AVDs (`create` takes only those profiles) |
| `android install` / `run [--type …]` | android-qa, add-form-factor | deploy + launch (Wear: `--type TILE | WEAR_WIDGET | COMPLICATION | WATCH_FACE | DECLARATIVE_WATCH_FACE`) |
| `android layout [--flat]` | android-qa | the UI as JSON — the primary way to read a screen |
| `android screen capture [--annotate]` / `resolve` | android-qa | screenshots; visual targeting when the layout lacks a node |
| `android input tap | swipe | text | key | scroll` | android-qa | selector-based input (`text=…`, `desc=…`, `id=…`); D-pad and back keys |
| `android device remote` | android-qa (optional) | reserved remote physical devices when no local one fits |
| `android init` / `update` / `info` | doctor | environment setup and freshness |

**adb** is used only for `adb devices -l` (the CLI does not list attached devices) — and once by
`scripts/avd.sh ensure tv` / `prepare tv`, which runs the SDK's `platform-tools/adb shell settings put` inside the TV
emulator to turn Play Protect's app verification off (see the gotchas). Everything else — install, launch, input, screenshots —
goes through `android`.

Gotchas:
- The Bash tool may run **zsh**: brace variables (`"${SERIAL}"`) — `"$SERIAL:x"` is a zsh modifier.
- `android describe` writes `.gradle/init.gradle.kts` into the project (git-ignored).
- An app whose only launcher category is `LEANBACK_LAUNCHER` (`:tv`) needs `android run --activity=MainActivity`
  (otherwise "Component check failed").
- TV system images ship Play Protect, which blocks the CLI's on-device instrumentation server ("Unsafe app blocked …
  built for an older version of Android"): `android layout` fails and `android input` hangs. `avd.sh ensure tv` turns
  app verification off inside `tv_1080p` (booting it if needed) and marks the AVD prepared; `avd.sh prepare tv` redoes
  it. On another TV AVD do it in its Settings.
- On a device with several displays (foldables, some Automotive images) `android screen capture` prepends
  screencap's "Multiple displays were found" warning to the PNG file; strip everything before the `\x89PNG`
  signature before viewing it (the `android-qa` agent does).
- `android create` installs the platform its template needs; android-forge also installs compileSdk 37
  (`android-new.sh ensure-sdk 37`).

## Emulators per form factor

`android emulator create` makes only `small_phone`, `medium_phone`, `medium_tablet`, `small_desktop`,
`medium_desktop`, `large_desktop`. Every other form factor needs an AVD made with the SDK's `avdmanager`
from a hardware profile and a system image; `scripts/avd.sh ensure <form-factor>` does both (it installs the
image with `android sdk install`, and is never run without the user's go-ahead). `android emulator start`
boots any AVD.

| Form factor | AVD (`avd.sh` name) | Hardware profile | System image |
|---|---|---|---|
| Phone | `medium_phone` | CLI `medium_phone` | CLI default |
| Tablet | `medium_tablet` | CLI `medium_tablet` | CLI default |
| Desktop / Googlebook | `desktop_medium` | CLI `medium_desktop` | CLI default |
| Foldable | `pixel_10_pro_fold` | `pixel_10_pro_fold` | `system-images/android-37.0/google_apis_playstore_ps16k/<abi>` |
| Wear OS | `wearos_large_round` | `wearos_large_round` | `system-images/android-37.0/android-wear-signed/<abi>` |
| TV | `tv_1080p` | `tv_1080p` | `system-images/android-36/android-tv/<abi>` (`ensure` turns Play Protect app verification off inside it — see gotchas) |
| Android Automotive OS | `automotive_1408p_landscape_with_play` | same | `system-images/android-35-ext15/android-automotive-playstore/<abi>` |
| XR headset | `xr_headset_device` | `xr_headset_device` | `system-images/android-34/google-xr/<abi>` |
| XR display glasses | `ai_glasses_device` | `ai_glasses_device` | `system-images/android-36/ai-glasses/<abi>` — runs paired with a host phone AVD on the API CANARY 16 KB Play image; Android Studio Canary's Pairing Assistant pairs them (`avd.sh` can't) |
| Android Auto | — | Desktop Head Unit (`android sdk install extras/google/auto`) | a phone AVD/device running the app |
| Google Cast | — | a real Cast device only | — |

AVDs are named after their hardware profile, except desktop: the CLI names its `medium_desktop` AVD `desktop_medium`.
`scripts/avd.sh name <form-factor>` prints the name, `status` shows what is installed, `ensure` installs the image
(gigabytes — callers ask first) and creates the AVD. `<abi>` is `arm64-v8a`
on Apple Silicon, `x86_64` elsewhere. `scripts/avd.sh` is the source of truth for this table.

## Android skills (project-scoped tiers)

Installed into the project's `.claude/skills/` with `android skills add --project <dir> --agent claude-code`
and committed — every session, cloud run and the autonomous loop has them. `scripts/skills.sh` holds the tier
lists (single source of truth; this table mirrors it).

| Tier | Skills | Installed by | Loaded by |
|---|---|---|---|
| `baseline` | android-cli, adaptive, navigation-3, navigation-event, edge-to-edge, testing-setup, jetpack-compose-performance, android-profiler, android-intent-security, android-permissions-security, r8-analyzer, play-policy-insights | init, adopt | QA (android-cli); the presentation-layer skill — so screen work by the implementer or after the feature-builder — (adaptive, navigation-3, navigation-event, edge-to-edge); migrator (navigation-3, edge-to-edge, adaptive, testing-setup); reviewer (the security pair, on manifest/IPC changes); release skill (r8-analyzer, play-policy-insights); jetpack-compose-performance and android-profiler on demand ([observability.md](observability.md)) |
| `desktop`, `xr` | adaptive | add-form-factor | form-factor-builder (its form factor's skill, for what the templates don't cover), implementer |
| `glasses` | display-glasses-with-jetpack-compose-glimmer | add-form-factor | form-factor-builder, implementer |
| `cars` | android-for-cars-parked-apps | add-form-factor (Auto/AAOS) | form-factor-builder (parked apps) |
| `tv` | leanback-to-compose-tv-migration, engage-sdk-integration | add-form-factor | form-factor-builder, implementer (Compose for TV patterns, Google TV discovery) |
| `wear` | wear-compose-m3, wear-widgets | add-form-factor | form-factor-builder, implementer |
| `cast` | media3-cast-integration | add-form-factor | the first media slice (implementer) |
| `widgets` | glance-canonical-layouts | add-form-factor | implementer (widget layouts) |
| `camerax` · `appfunctions` · `genai` · `litert` · `credentials` · `billing` · `engage` | camerax · appfunctions · ml-kit-genai-prompt-api · litert-runtime · restore-credentials + verified-email · play-billing-library-version-upgrade · engage-sdk-integration | add-library (library → tier map) | implementer |
| `adopt` | agp-9-upgrade, migrate-xml-views-to-jetpack-compose, styles | suggested by adopt; never automatic | migrator |

Gaps no official skill covers yet — android-forge documents them in [form-factors/](form-factors/):
templated Car App Library apps, XR headset spatial UI, Health Connect, the phone↔watch Data Layer.

**Lockstep:** a tier change touches `scripts/skills.sh`, this table, the README, `docs/form-factors/<ff>.md`
(`cars.md` for Auto/AAOS), the `android-form-factor-builder` agent and `/android-forge-add-library`'s map.
