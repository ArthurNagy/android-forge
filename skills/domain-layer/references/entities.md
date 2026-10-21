# Entities and value types (`:core:model`)

Use when adding or changing an entity or value type in `:core:model`.

```kotlin
package <base>.core.model

@JvmInline
value class PhotoId(
    val value: String,
)

data class Photo(
    val id: PhotoId,
    val title: String,
    val description: String?,
    val favorite: Boolean,
)
```

- **No default values.** Every call site states every field, and adding a field breaks every place that must
  decide its value. (`null` is a value you pass explicitly, not a default.)
- Immutable: `val`s and read-only collections. An invariant the type must always hold goes in `init { require(…) }`.
- IDs as value classes, so a `PhotoId` can't be passed where a `UserId` is expected. Nav 3 keys carry the raw
  `String` (`PhotoDetailKey(photoId = id.value)`), not the entity.
- No presentation: no display strings, no formatting, no colors, no `@StringRes`. Time is `java.time` /
  `kotlin.time.Instant`.
