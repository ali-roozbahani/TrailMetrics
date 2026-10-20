package dev.roozbahani.trailmetrics.data.location

import android.location.Location
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.tasks.TaskCompletionSource
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runTest
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.lang.reflect.Proxy
import kotlin.test.assertNull
import kotlin.test.assertTrue

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class AndroidLocationRepositoryImplTest {

    // The client is an interface with dozens of members; only getCurrentLocation is answered. Its task
    // never completes, so the call stays suspended until the test cancels the caller.
    private val pendingClient = Proxy.newProxyInstance(
        FusedLocationProviderClient::class.java.classLoader,
        arrayOf(FusedLocationProviderClient::class.java)
    ) { _, method, _ ->
        check(method.name == "getCurrentLocation") { "unexpected call: ${method.name}" }
        TaskCompletionSource<Location>().task
    } as FusedLocationProviderClient

    @Test
    fun `getCurrentLocation rethrows when its caller is cancelled instead of returning a Result`() = runTest {
        val repo = AndroidLocationRepositoryImpl(pendingClient)
        var returned: Result<Coordinates>? = null

        val caller = launch { returned = repo.getCurrentLocation() }
        testScheduler.runCurrent()
        assertTrue(caller.isActive)

        caller.cancel()
        caller.join()

        assertNull(returned)
    }
}
