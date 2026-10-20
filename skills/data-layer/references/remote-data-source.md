# Remote data source (`:core:network`)

Use when adding an API call — and, once, to create `:core:network` (**First API call**) when it doesn't exist yet.

**First API call** — when `:core:network` doesn't exist yet (the network opt-in wasn't picked at init), create it
once; the Retrofit/OkHttp catalog entries are already there (`${CLAUDE_PLUGIN_ROOT}` is the android-forge plugin
root — your `claude_plugin_root` input when you read this file directly instead of invoking the skill):

```bash
AO="${CLAUDE_PLUGIN_ROOT}/scripts/apply-overlay.sh"
BASE_PACKAGE="<base package>" bash "${AO}" render-module core.network "${CLAUDE_PLUGIN_ROOT}/overlay/optional/network" core/network "<base-path>"
bash "${AO}" patch-settings . "core:network"
```

Then `implementation(project(":core:network"))` in `core/data/build.gradle.kts` above the
`// android-forge:core-data-deps` marker, `<uses-permission android:name="android.permission.INTERNET" />` above
`<application` in `app/src/main/AndroidManifest.xml`, and the real base URL in `core/network/build.gradle.kts`
(`API_BASE_URL`). The module ships `NetworkModule` (one `OkHttpClient`, `Json`, `Retrofit`) and `catchNetwork` with
its tests.

```kotlin
@Serializable
data class PhotoDto(
    val id: String,
    val title: String,
    val description: String? = null,                  // the API omits it when empty
    @SerialName("is_favorite") val favorite: Boolean = false,
)

internal interface PhotoApi {
    @GET("photos")
    suspend fun photos(): List<PhotoDto>
}

/** May throw: IOException (transport), HttpException (non-2xx), SerializationException (bad body). */
interface PhotoRemoteDataSource {
    suspend fun photos(): List<PhotoDto>
}

internal class RetrofitPhotoRemoteDataSource
    @Inject
    constructor(
        private val api: PhotoApi,
    ) : PhotoRemoteDataSource {
        override suspend fun photos(): List<PhotoDto> = api.photos()
    }

@Module
@InstallIn(SingletonComponent::class)
internal interface PhotoNetworkModule {
    @Binds
    fun bindsPhotoRemoteDataSource(impl: RetrofitPhotoRemoteDataSource): PhotoRemoteDataSource

    companion object {
        @Provides
        fun providePhotoApi(retrofit: Retrofit): PhotoApi = retrofit.create(PhotoApi::class.java)
    }
}
```

- A DTO mirrors the wire format; it is the one **model type** that may have default values (for fields the API
  omits).
- A Retrofit `suspend` function returning a body **throws `HttpException` on non-2xx**. When a status means
  something (404 = "doesn't exist"), declare `Response<PhotoDto>` and decide in the data source:
  `if (response.code() == 404) return null`, else `response.body() ?: throw HttpException(response)`.
- One `Retrofit` / `OkHttpClient` for the app (`NetworkModule`); per-host clients get a Hilt qualifier.
  Auth headers go in an OkHttp `Interceptor`; secrets come from `BuildConfig` fields fed by
  `local.properties`/CI env, never source ([secrets.md](../../../docs/secrets.md)).
- Retrofit, Room and DataStore `suspend` APIs are **main-safe** — no `withContext` needed around them. Blocking
  APIs (`java.io` streams, `ContentResolver` queries, image decoding) run on the injected
  `dispatchers.io`; CPU-heavy mapping on `dispatchers.default`.
