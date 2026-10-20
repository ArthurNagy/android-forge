# Tests

Use when writing use-case tests — the happy path, every error, `TestDispatcherProvider`.

`core/domain/src/test/kotlin/…`: JUnit 4 + `kotlin.test` assertions + Turbine. Every use case gets its happy
path and **each error it can return**. Tag a test that covers an OpenSpec scenario with
`// Scenario: <exact name>`, which is how QA traces coverage.

```kotlin
class ObservePhotosUseCaseTest {
    @Test
    fun emitsPhotosSortedByTitle() = runTest {
        val repository = FakePhotoRepository().apply { seed(photo(id = "1", title = "b"), photo(id = "2", title = "a")) }

        ObservePhotosUseCase(repository)().test {
            assertEquals(listOf("a", "b"), awaitItem().map { it.title })
        }
    }
}

class ToggleFavoriteUseCaseTest {
    @Test
    fun anUnknownPhotoIsNotFound() = runTest {
        assertEquals(Err(DomainError.NotFound), ToggleFavoriteUseCase(FakePhotoRepository())(PhotoId("missing")))
    }
}
```

A use case that takes `DispatcherProvider` gets `TestDispatcherProvider(testScheduler)` — the `runTest`
scheduler; a dispatcher with its own scheduler hangs or fails with "Detected use of different schedulers".
Build test entities with `:core:testing`'s builders (`photo(id = "1", title = "a")`, [Fake and entity builder](fakes-and-builders.md)).
