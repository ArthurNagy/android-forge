# Preferences (`:core:datastore`)

Use when adding a stored preference, typed DataStore data or a secret in `:core:datastore`.

The template's `UserPreferencesDataSource` is the pattern: one `DataStore<Preferences>` per file, provided
`@Singleton` by `DataStoreModule` with `ReplaceFileCorruptionHandler { emptyPreferences() }`; reads `retryWhen` on
`IOException` — emit `emptyPreferences()`, then retry after a back-off (`catch` would complete the flow) — so they
never throw and keep updating; writes may throw (the repository maps them). Add a key to the existing data source when it
belongs to the same preferences file; a new concern gets its own file and data source. Typed data: a
kotlinx-serialization JSON `Serializer<T>` with `DataStoreFactory`. Secrets: encrypt the serializer with Tink —
never `EncryptedSharedPreferences`.
