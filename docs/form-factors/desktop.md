# Googlebook, Chromebook and desktop windowing

Googlebooks (Android on ChromeOS desktop foundations), Chromebooks and Android's desktop windowing run the
phone APK in free-form, resizable windows driven by keyboard, trackpad and mouse. No `:desktop` module, no
separate Play track. Sources: `android docs fetch kb://android/develop/adaptive-apps/guides/googlebook/overview`,
`kb://android/develop/adaptive-apps/guides/increase-app-availability`, `kb://android/develop/devices/chromeos/learn/manifest`,
`kb://android/develop/adaptive-apps/guides/support-desktop-windowing`,
`kb://android/develop/adaptive-apps/quality-guidelines/adaptive-app-quality/experiences/desktop`.
Skill: `adaptive` (`scripts/skills.sh` tier `desktop`) — `mediaQuery { pointerPrecision / keyboardKind }`,
Grid/FlexBox, Nav 3 scenes.

Added by `/android-forge-add-form-factor desktop`: the manifest line below, the `desktop` skill tier, the
`desktop_medium` emulator on request (the Android CLI's `medium_desktop` profile), and the form-factor line in
`CLAUDE.md`.

## Recipe (Edit steps on `:app`)

1. **Manifest** — `overlay/form-factors/desktop/app-manifest-snippet.xml` as a direct child of `<manifest>` in `app/src/main/AndroidManifest.xml`:
   ```xml
   <uses-feature
       android:name="android.hardware.touchscreen"
       android:required="false" />
   ```
   Without it Play treats a touchscreen as required and hides the app from non-touch laptops/desktops (they
   report `android.hardware.faketouch`). Keep every other `<uses-feature>` `required="false"` — including the
   ones a permission implies (`CAMERA` implies `android.hardware.camera` **and** `camera.autofocus`, both
   absent on most Chromebooks; also `telephony`, `location.gps`, `nfc`, `sensor.*`, `usb.*`). Never require
   `android.software.app_widgets`, `android.software.leanback` or `android.hardware.type.*`.
   `android.hardware.type.pc` (`required="false"`) only if the app handles mouse/trackpad itself — it turns off
   ChromeOS's input emulation.
2. **Caption bar** (Android 15+ desktop windowing) — the system draws Back/Minimize/Maximize/Close over the
   edge-to-edge content. The scaffold's `MainActivity` already tints them for the app's theme
   (`useLightCaptionBar`, `APPEARANCE_LIGHT_CAPTION_BARS`); content avoids the bar because `safeDrawing` insets
   include `WindowInsets.captionBar`.
3. Check the merged result: `aapt2 dump badging app/build/outputs/apk/debug/app-debug.apk | grep uses-feature`
   — only `uses-feature-not-required` lines. (Before this line, `aapt2` lists `uses-feature: …faketouch` — the
   requirement a required touchscreen implies; with it, no `faketouch` line remains.)

## What android-forge already gives you

No orientation/resizability locks (ignored on large screens anyway), window-size-driven layouts with Nav 3
list-detail scenes (two panes when the window is wide), edge-to-edge, configuration continuity (state in
ViewModels and saveable back stacks), phone + tablet goldens.

## Desktop quality (the desktop app quality guidelines — per feature, not templated)

- **Keyboard**: everything reachable with Tab/arrows/Enter, visible focus; conventional shortcuts (Ctrl+C/V/Z,
  Ctrl+F, Esc) via `Modifier.onPreviewKeyEvent`; publish them in the Keyboard Shortcuts Helper
  (`Activity.onProvideKeyboardShortcuts`).
- **Pointer**: hover states on every interactive element, right-click context menus, pointer icons
  (`Modifier.pointerHoverIcon`), scrollbars, text selection by double/triple click, precise targets — branch with
  `mediaQuery { pointerPrecision == Fine }`.
- **Windows**: state survives free-form resizing; multi-instance where it fits the product
  (`FLAG_ACTIVITY_NEW_TASK` + `PROPERTY_SUPPORTS_MULTI_INSTANCE_SYSTEM_UI`, never `singleInstance`);
  drag and drop in and out of the app; widgets ([widgets.md](widgets.md)) show on the Googlebook desktop.
- **Continuity**: hand off from the phone with Continue On (`HandoffActivityData`).

## QA

- Screenshots: add a `RobolectricDeviceQualifiers.MediumDesktop` golden where a layout branches for desktop.
- Emulator: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/avd.sh" ensure desktop` (the Android CLI's `medium_desktop` profile;
  the AVD is named `desktop_medium` — `avd.sh name desktop`). Image:
  `system-images/android-34/android-desktop` (API 34: caption-bar tinting needs API 35, so check it on a
  newer image or device). `android run --apks=… --device=<serial>`; tap `Maximize` in the caption bar to check
  the wide layout; `android input key …` for keyboard checks.

## Quality

Adaptive ready — the checklist in [quality.md](../quality.md#adaptive-ready-every-project), whose keyboard, mouse,
trackpad and multi-window items matter most here — plus, on interactive screens, the desktop experience items in
§ Desktop quality above (keyboard parity is android-forge's baseline; the rest is per feature), and the manifest: no
required `uses-feature` (touchscreen, camera, telephony, …), checked with `aapt2 dump badging`.
