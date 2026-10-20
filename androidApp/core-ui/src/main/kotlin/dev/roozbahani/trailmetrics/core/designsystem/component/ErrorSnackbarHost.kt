package dev.roozbahani.trailmetrics.core.designsystem.component

import androidx.compose.foundation.layout.padding
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

/**
 * The error snackbar of a screen whose bottom holds its controls (Route, Tracking). A `Scaffold`'s
 * `snackbarHost` slot sits at the bottom and takes the taps meant for the buttons there, so the
 * screen places this host last in its content `Box` with `Modifier.align(Alignment.TopCenter)`.
 * The top padding keeps it clear of the 40 dp corner buttons (16 dp padding) at the top.
 */
@Composable
fun ErrorSnackbarHost(
    hostState: SnackbarHostState,
    modifier: Modifier = Modifier
) {
    SnackbarHost(
        hostState = hostState,
        modifier = modifier.padding(top = CORNER_BUTTONS_CLEARANCE)
    )
}

private val CORNER_BUTTONS_CLEARANCE = 72.dp
