# Strings and errors

Use when adding user-facing strings or plurals, or wording a `DomainError` on a screen or in a snackbar slot.

- Every user-facing string, `contentDescription` included, comes from the module's
  `src/main/res/values/strings.xml`, keys prefixed with its `resourcePrefix` — the feature name in snake_case
  (`gallery_…`; `photo_detail_…` for `photo-detail`). The shared Back label
  is `CoreUiR.string.core_ui_navigate_back` (`import <base>.core.ui.R as CoreUiR`).
- **Errors**: `:core:ui`'s `DomainError.toMessage()` words the built-in cases once; never re-word them. The screen
  words the area's typed errors it reacts to, from its own table, and falls back to `toMessage()`:
  ```kotlin
  @Composable
  private fun DomainError.message(): String = when (this) {
      PhotoError.TitleBlank -> stringResource(R.string.gallery_title_blank)
      is PhotoError.AlbumFull -> stringResource(R.string.gallery_album_full, limit)
      else -> toMessage()
  }
  ```
  Never show a `cause`. Outside composition — an intent filling `pendingMessage` for a snackbar — use the
  `@StringRes` behind it: `:core:ui`'s `error.messageRes()` (the area's typed errors map to their own string IDs
  the same way).
- Plurals: `pluralStringResource(R.plurals.gallery_photo_count, count, count)`. Inside an effect, resolve with
  `LocalResources.current.getString(id)` captured outside the effect.
- Remove the template's `<feature_snake>_placeholder_content` string and its `// TODO(android-forge):` line once real
  content exists (`android-reviewer` flags it).
