# Google Cast (sender)

Casting media from the phone/tablet app to a Cast receiver (Chromecast, Google TV, Cast-enabled speakers). It lives
in `:app` — there is no separate module or template: a Cast sender is only meaningful once the app plays media, so
it is added by the slice that needs it, following the **`media3-cast-integration`** skill.

## Shape

- **Media3 everywhere**: `androidx.media3:media3-exoplayer`, `media3-session`, `media3-ui-compose`, `media3-cast`
  (all one version, ≥ 1.9; catalog key `media3`). The legacy Cast SDK UI is not used.
- A `:core:media` library module (Android library + Hilt) owns playback: a `MediaSessionService` hosting a
  `CastPlayer` that wraps the local `ExoPlayer` and switches between local and remote playback. Features talk to it
  through a `:core:domain` interface (e.g. `PlaybackController`) — never to Media3 directly (features see only
  `:core:domain`).
- `DefaultCastOptionsProvider` (or a custom `OptionsProvider` with your receiver app ID) declared in the manifest;
  the Media3 `MediaRouteButton` composable in the player UI.
- The TV side of casting (receiving) is **Cast Connect** in the `:tv` app — see [tv.md](tv.md).

## Adding it

1. `/android-forge-add-form-factor cast` installs the `cast` skill tier and the catalog entries.
2. The first media slice creates `:core:media` per the skill (its architect notes should say so) and records the
   receiver choice (default vs custom receiver) as an ADR.

## QA

Cast needs real hardware; the `android-qa` agent reports Cast scenarios as unverified (`ERROR`) — check them by hand
on a Cast device on the same network. Local playback around it is testable as usual (Media3 test utilities, Robolectric).

## Quality

Play publishes no quality tier for Cast senders. android-forge's bar is Google's Cast guideline for media apps in the
Apps Experience Program (`android docs fetch kb://android/distribute/aep/aep-req-cast-support`), met by the first media
slice — adding the form factor alone (catalog + skill) has nothing to check yet:
- `AEP-CS-GAA` Cast through Media3: the Cast button is visible in the player UI and connects to a Cast device.
- `AEP-CS-GAB` Output Switcher: the media notification's and lock screen's device chip moves playback correctly when
  the output route changes (built into Media3's `MediaSession`).
- The phone app around it stays Adaptive ready ([quality.md](../quality.md#adaptive-ready-every-project)).
