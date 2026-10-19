---
description: Add a new screen (key + @HiltViewModel Orbit ViewModel + state + Composable + entry) inside an existing feature's :api / :impl modules.
argument-hint: <feature-name> <screen-name>
---

# /android-forge-add-screen

Adds a screen to an existing feature — no new modules. The key goes into `:feature:<feature>:api`, everything else
into `:feature:<feature>:impl`, and the feature's existing entry builder gains an `entry<…>`.

## Arguments

- **`<feature-name>`**: an existing feature (`gallery`).
- **`<screen-name>`**: kebab-case (`photo-detail`) → `PhotoDetail` for class names.

Ask via `AskUserQuestion` if missing, plus: does the key carry an argument (`photoId: String`)?

## Flow

1. **Verify** `feature/<feature-name>/impl` exists — else point at `/android-forge-add-feature`.
2. **Read** the feature's existing screen, ViewModel, entries and entry module for style.
3. **Generate** (the Bash tool may run zsh — brace variables), rendering the feature templates with the **feature's**
   package and resource prefix and the **screen's** PascalCase name:
   ```bash
   export BASE_PACKAGE="<base>" FEATURE_NAME="<feature-name>" FEATURE_NAME_PKG="<feature pkg>" \
          FEATURE_NAME_SNAKE="<feature snake>" FEATURE_NAME_PASCAL="<ScreenPascal>" FEATURE_NAME_CAMEL="<screenCamel>"
   T="${CLAUDE_PLUGIN_ROOT}/overlay/modules/feature"
   VARS='${BASE_PACKAGE} ${FEATURE_NAME} ${FEATURE_NAME_PKG} ${FEATURE_NAME_SNAKE} ${FEATURE_NAME_PASCAL} ${FEATURE_NAME_CAMEL}'
   API="<project>/feature/${FEATURE_NAME}/api/src/main/kotlin/<base-path>/feature/${FEATURE_NAME_PKG}/api"
   IMPL="<project>/feature/${FEATURE_NAME}/impl/src/main/kotlin/<base-path>/feature/${FEATURE_NAME_PKG}/impl"
   TEST="<project>/feature/${FEATURE_NAME}/impl/src/test/kotlin/<base-path>/feature/${FEATURE_NAME_PKG}/impl"
   envsubst "${VARS}" < "${T}/api/src/main/kotlin/FeatureKey.kt.tmpl"        > "${API}/${FEATURE_NAME_PASCAL}Key.kt"
   for f in State ViewModel Screen; do
       envsubst "${VARS}" < "${T}/impl/src/main/kotlin/Feature${f}.kt.tmpl"  > "${IMPL}/${FEATURE_NAME_PASCAL}${f}.kt"
   done
   for f in ViewModelTest ScreenTest; do
       envsubst "${VARS}" < "${T}/impl/src/test/kotlin/Feature${f}.kt.tmpl"  > "${TEST}/${FEATURE_NAME_PASCAL}${f}.kt"
   done
   ```
   Then fix up by hand: the rendered files reference `R.string.<feature snake>_placeholder_content` — add a
   screen-specific key to the feature's existing `strings.xml` (`<feature snake>_<screen snake>_…`, keep the module
   prefix) instead of creating a second table, and point the new screen and tests at it.
   Do **not** create a second entry module — the feature already has one.
4. **Key argument?** Make the key a `data class` and give the ViewModel `@AssistedInject` + an `@AssistedFactory`
   (see the `presentation-layer` skill § ViewModel); the entry creates it with
   `hiltViewModel<VM, VM.Factory>(creationCallback = { it.create(key) })`.
5. **Entry**: in the feature's `<Feature>Entries.kt`, add `entry<<Screen>Key> { <Screen>Screen(onNavigateBack = navigator.backOrNull()) }`
   (with `ListDetailSceneStrategy.detailPane()` metadata when it is the detail of a list in this feature).
   The screen that opens it sets `pendingNavigation = <Screen>Key(…)` and its entry passes `onNavigate = navigator::navigate`.
6. **Format, record, build**:
   `./gradlew spotlessApply -q && ./gradlew :feature:<feature>:impl:recordRoborazziDebug -q && ./gradlew :feature:<feature>:impl:testDebugUnitTest :app:assembleDebug`.
7. **Report** files created, edits applied, the screenshots to review, build result.

## Notes

- Many screens per feature is normal (list + detail). Past ~5, consider splitting the feature — say so.
- Use cases live in `:core:domain` and are injected per ViewModel; this command does not create them.
