package dev.roozbahani.trailmetrics.feature.tracking

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Route
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.filled.Timer
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.google.android.gms.maps.CameraUpdateFactory
import com.google.android.gms.maps.GoogleMap
import com.google.android.gms.maps.model.CameraPosition
import com.google.android.gms.maps.model.LatLng
import com.google.maps.android.compose.MapEffect
import com.google.maps.android.compose.MapsComposeExperimentalApi
import com.google.maps.android.compose.rememberCameraPositionState
import dev.roozbahani.trailmetrics.core.designsystem.component.MetricCell
import dev.roozbahani.trailmetrics.core.designsystem.theme.TrailMetricsTheme
import dev.roozbahani.trailmetrics.core.error.stringRes
import dev.roozbahani.trailmetrics.core.map.CurrentLocationMarker
import dev.roozbahani.trailmetrics.core.map.RoutePolyline
import dev.roozbahani.trailmetrics.core.map.TrailGoogleMap
import dev.roozbahani.trailmetrics.domain.model.ActivityType
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.RouteProgress
import dev.roozbahani.trailmetrics.domain.model.TrackingMetrics
import dev.roozbahani.trailmetrics.domain.model.TrackingState
import dev.roozbahani.trailmetrics.domain.util.formatCalories
import dev.roozbahani.trailmetrics.domain.util.formatDistance
import dev.roozbahani.trailmetrics.domain.util.formatElapsedTime
import dev.roozbahani.trailmetrics.domain.util.formatSpeed
import dev.roozbahani.trailmetrics.feature.tracking.util.saveSnapshotToFile
import org.koin.androidx.compose.koinViewModel
import org.koin.core.parameter.parametersOf

/**
 * NavHost entry point. Keeps the call site in MainActivity unchanged; delegates to [TrackingRoot].
 */
@Composable
fun TrackingScreen(
    initialStartPoint: Coordinates,
    plannedRoutePoints: List<Coordinates>,
    activityType: ActivityType,
    onNavigateBack: () -> Unit
) {
    TrackingRoot(
        initialStartPoint = initialStartPoint,
        plannedRoutePoints = plannedRoutePoints,
        activityType = activityType,
        onNavigateBack = onNavigateBack
    )
}

@Composable
fun TrackingRoot(
    initialStartPoint: Coordinates,
    plannedRoutePoints: List<Coordinates>,
    activityType: ActivityType,
    onNavigateBack: () -> Unit
) {
    val viewModel: TrackingViewModel = koinViewModel(parameters = {
        parametersOf(
            activityType,
            plannedRoutePoints
        )
    })
    val state: TrackingScreenState by viewModel.state.collectAsStateWithLifecycle()
    val snackBarHostState = remember { SnackbarHostState() }
    val context = LocalContext.current

    val permissionHandler = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestMultiplePermissions()
    ) { permissions ->
        val granted = permissions.values.any { granted -> granted }
        if (granted) {
            viewModel.onAction(TrackingAction.LocationPermissionGranted(initialStartPoint))
        }
    }

    val notificationPermissionHandler = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestPermission()
    ) { /** no op */ }

    LaunchedEffect(Unit) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            notificationPermissionHandler.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }

    @Suppress("LocalContextGetResourceValueCall")
    LaunchedEffect(Unit) {
        viewModel.events.collect { event ->
            when (event) {
                is TrackingEvent.ShowError -> {
                    snackBarHostState.showSnackbar(context.getString(event.error.stringRes))
                }

                is TrackingEvent.RequestLocationPermission -> {
                    permissionHandler.launch(LOCATION_PERMISSIONS)
                }

                is TrackingEvent.Saved -> onNavigateBack()
            }
        }
    }

    TrackingScreen(
        state = state,
        onAction = viewModel::onAction,
        initialStartPoint = initialStartPoint,
        snackBarHostState = snackBarHostState,
        onRequestLocationPermission = { permissionHandler.launch(LOCATION_PERMISSIONS) },
        onNavigateBack = onNavigateBack
    )
}

@Composable
fun TrackingScreen(
    state: TrackingScreenState,
    onAction: (TrackingAction) -> Unit,
    initialStartPoint: Coordinates,
    snackBarHostState: SnackbarHostState,
    onRequestLocationPermission: () -> Unit,
    onNavigateBack: () -> Unit
) {
    val cameraPositionState = rememberCameraPositionState()
    val context = LocalContext.current

    var showExitConfirmation by remember { mutableStateOf(false) }
    val hasActiveSession = state.canPause || state.canResume

    BackHandler(enabled = hasActiveSession) {
        showExitConfirmation = true
    }

    val onBackRequested: () -> Unit = {
        if (hasActiveSession) {
            showExitConfirmation = true
        } else {
            onNavigateBack()
        }
    }

    if (showExitConfirmation) {
        AlertDialog(
            onDismissRequest = { showExitConfirmation = false },
            title = { Text(stringResource(R.string.dialog_exit_tracking_title)) },
            text = { Text(stringResource(R.string.dialog_exit_tracking_message)) },
            confirmButton = {
                TextButton(onClick = {
                    showExitConfirmation = false
                    onAction(TrackingAction.Stop)
                    onNavigateBack()
                }) {
                    Text(stringResource(R.string.dialog_exit_tracking_confirm))
                }
            },
            dismissButton = {
                TextButton(onClick = { showExitConfirmation = false }) {
                    Text(stringResource(R.string.dialog_exit_tracking_dismiss))
                }
            }
        )
    }

    LaunchedEffect(initialStartPoint) {
        cameraPositionState.position = CameraPosition.fromLatLngZoom(
            LatLng(initialStartPoint.latitude, initialStartPoint.longitude),
            DEFAULT_ZOOM
        )
    }

    LaunchedEffect(state.currentPath) {
        state.currentPath.lastOrNull()?.let { coordinates ->
            cameraPositionState.animate(
                CameraUpdateFactory.newLatLng(LatLng(coordinates.latitude, coordinates.longitude))
            )
        }
    }

    val currentLocation = state.currentPath.lastOrNull()

    var googleMapRef by remember { mutableStateOf<GoogleMap?>(null) }
    // Set while a Finish tap waits for map.snapshot { }, so a repeated tap doesn't write a second file.
    var isSnapshotPending by remember { mutableStateOf(false) }

    Scaffold(
        snackbarHost = { SnackbarHost(snackBarHostState) }
    ) { innerPadding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
        ) {
            TrailGoogleMap(cameraPositionState = cameraPositionState) {
                if (state.plannedRoutePoints.isNotEmpty()) {
                    RoutePolyline(
                        points = state.plannedRoutePoints,
                        color = MaterialTheme.colorScheme.outlineVariant
                    )
                }

                state.routeProgress?.traveledSegment?.let { traveled ->
                    RoutePolyline(points = traveled, color = MaterialTheme.colorScheme.primary)
                }

                CurrentLocationMarker(coordinates = currentLocation ?: initialStartPoint)

                // MapEffect is the only maps-compose hook that exposes the raw GoogleMap,
                // which the Finish button needs for map.snapshot { }.
                @OptIn(MapsComposeExperimentalApi::class)
                MapEffect(Unit) { map ->
                    googleMapRef = map
                }
            }

            FilledIconButton( // Back Button
                onClick = onBackRequested,
                colors = IconButtonDefaults.filledIconButtonColors(
                    containerColor = MaterialTheme.colorScheme.surface
                ),
                modifier = Modifier
                    .align(Alignment.TopStart)
                    .padding(16.dp)
                    .shadow(elevation = 4.dp, shape = CircleShape)
            ) {
                Icon(
                    imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                    contentDescription = stringResource(R.string.cd_navigate_back)
                )
            }

            Column(
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .fillMaxWidth()
                    .padding(16.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                state.currentMetrics?.let { metrics ->
                    MetricsDisplay(metrics = metrics, calories = state.calories)
                    Spacer(modifier = Modifier.height(16.dp))
                }

                AnimatedContent(
                    targetState = state.hasReachedDestination,
                    transitionSpec = {
                        (fadeIn() + slideInVertically { fullHeight -> fullHeight / 2 }) togetherWith fadeOut()
                    },
                    label = "tracking_controls"
                ) { completed ->
                    if (completed) {
                        Card(
                            colors = CardDefaults.cardColors(
                                containerColor = MaterialTheme.colorScheme.primaryContainer
                            ),
                            elevation = CardDefaults.cardElevation(defaultElevation = 4.dp)
                        ) {
                            Column(
                                modifier = Modifier.padding(24.dp),
                                horizontalAlignment = Alignment.CenterHorizontally
                            ) {
                                Text(
                                    text = stringResource(R.string.msg_route_completed),
                                    style = MaterialTheme.typography.titleMedium,
                                    color = MaterialTheme.colorScheme.onPrimaryContainer
                                )
                                Spacer(Modifier.height(12.dp))
                                Button( // Finish
                                    onClick = {
                                        val map = googleMapRef
                                        if (map != null) {
                                            if (!isSnapshotPending) {
                                                isSnapshotPending = true
                                                map.snapshot { bitmap ->
                                                    isSnapshotPending = false
                                                    val filePath = bitmap?.let { saveSnapshotToFile(context, it) }
                                                    onAction(TrackingAction.Finish(filePath))
                                                }
                                            }
                                        } else {
                                            onAction(TrackingAction.Finish(null))
                                        }
                                    }
                                ) {
                                    Icon(
                                        imageVector = Icons.Filled.Check,
                                        contentDescription = null
                                    )
                                    Spacer(Modifier.width(8.dp))
                                    Text(stringResource(R.string.btn_tracking_finish))
                                }
                            }
                        }
                    } else {
                        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            if (state.canStart) {
                                Button( // Start
                                    onClick = {
                                        if (hasLocationPermission(context)) {
                                            onAction(TrackingAction.Start(initialStartPoint))
                                        } else {
                                            onRequestLocationPermission()
                                        }
                                    }
                                ) {
                                    Icon(
                                        imageVector = Icons.Filled.PlayArrow,
                                        contentDescription = null
                                    )
                                    Spacer(Modifier.width(8.dp))
                                    Text(stringResource(R.string.btn_tracking_start))
                                }
                            }
                            if (state.canPause) {
                                Button( // Pause
                                    onClick = { onAction(TrackingAction.Pause) },
                                    colors = ButtonDefaults.buttonColors(
                                        containerColor = MaterialTheme.colorScheme.tertiary,
                                        contentColor = MaterialTheme.colorScheme.onTertiary
                                    )
                                ) {
                                    Icon(
                                        imageVector = Icons.Filled.Pause,
                                        contentDescription = null
                                    )
                                    Spacer(Modifier.width(8.dp))
                                    Text(stringResource(R.string.btn_tracking_pause))
                                }
                            }
                            if (state.canResume) {
                                Button( // Resume
                                    onClick = { onAction(TrackingAction.Resume) }
                                ) {
                                    Icon(
                                        imageVector = Icons.Filled.PlayArrow,
                                        contentDescription = null
                                    )
                                    Spacer(Modifier.width(8.dp))
                                    Text(stringResource(R.string.btn_tracking_resume))
                                }
                            }
                            if (state.canStop) {
                                Button( // Stop
                                    onClick = {
                                        onAction(TrackingAction.Stop)
                                        onNavigateBack()
                                    },
                                    colors = ButtonDefaults.buttonColors(
                                        containerColor = MaterialTheme.colorScheme.error,
                                        contentColor = MaterialTheme.colorScheme.onError
                                    )
                                ) {
                                    Icon(imageVector = Icons.Filled.Stop, contentDescription = null)
                                    Spacer(Modifier.width(8.dp))
                                    Text(stringResource(R.string.btn_tracking_stop))
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun MetricsDisplay(
    metrics: TrackingMetrics,
    calories: Double?,
    modifier: Modifier = Modifier
) {
    Card(
        modifier = modifier,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerHigh),
        elevation = CardDefaults.cardElevation(defaultElevation = 4.dp)
    ) {
        Column(modifier = Modifier.padding(8.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                MetricCell(
                    label = stringResource(CoreStrings.label_distance),
                    value = formatDistance(metrics.distanceMeters),
                    icon = Icons.Filled.Route,
                    modifier = Modifier.weight(1f)
                )
                MetricCell(
                    label = stringResource(CoreStrings.label_time),
                    value = formatElapsedTime(metrics.elapsedMillis),
                    icon = Icons.Filled.Timer,
                    modifier = Modifier.weight(1f)
                )
            }
            Spacer(Modifier.height(8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                MetricCell(
                    label = stringResource(CoreStrings.label_speed),
                    value = formatSpeed(metrics.currentSpeedMetersPerSecond),
                    icon = Icons.Filled.Speed,
                    modifier = Modifier.weight(1f)
                )
                MetricCell(
                    label = stringResource(CoreStrings.label_calories),
                    value = formatCalories(calories),
                    icon = Icons.Filled.LocalFireDepartment,
                    modifier = Modifier.weight(1f)
                )
            }
        }
    }
}

// Detekt counts private @Preview functions as unused; they are only used by the IDE preview.
@Suppress("UnusedPrivateMember")
@Preview(showBackground = true)
@Composable
private fun TrackingScreenPreview() {
    val plannedRoute = listOf(
        Coordinates(latitude = 52.520, longitude = 13.405),
        Coordinates(latitude = 52.523, longitude = 13.401),
        Coordinates(latitude = 52.525, longitude = 13.410),
        Coordinates(latitude = 52.520, longitude = 13.405)
    )
    val path = plannedRoute.take(2)
    TrailMetricsTheme {
        TrackingScreen(
            state = TrackingScreenState(
                trackingState = TrackingState.Tracking(
                    TrackingMetrics(
                        elapsedMillis = 754_000L,
                        lastUpdateElapsedRealtimeMillis = 754_000L,
                        distanceMeters = 2_140.0,
                        path = path,
                        currentSpeedMetersPerSecond = 2.8f
                    )
                ),
                calories = 148.0,
                plannedRoutePoints = plannedRoute,
                routeProgress = RouteProgress(
                    traveledSegment = path,
                    remainingSegment = plannedRoute.drop(1),
                    lastIndex = 1
                )
            ),
            onAction = {},
            initialStartPoint = plannedRoute.first(),
            snackBarHostState = remember { SnackbarHostState() },
            onRequestLocationPermission = {},
            onNavigateBack = {}
        )
    }
}

private typealias CoreStrings = dev.roozbahani.trailmetrics.core.ui.R.string

private const val DEFAULT_ZOOM = 15f
private val LOCATION_PERMISSIONS = arrayOf(
    Manifest.permission.ACCESS_FINE_LOCATION,
    Manifest.permission.ACCESS_COARSE_LOCATION
)

private fun hasLocationPermission(context: Context): Boolean {
    return ContextCompat.checkSelfPermission(
        context, Manifest.permission.ACCESS_FINE_LOCATION
    ) == PackageManager.PERMISSION_GRANTED ||
            ContextCompat.checkSelfPermission(
                context, Manifest.permission.ACCESS_COARSE_LOCATION
            ) == PackageManager.PERMISSION_GRANTED
}
