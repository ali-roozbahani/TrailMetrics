package dev.roozbahani.trailmetrics.feature.route

import android.Manifest
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.DirectionsBike
import androidx.compose.material.icons.automirrored.filled.DirectionsRun
import androidx.compose.material.icons.automirrored.filled.DirectionsWalk
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.google.android.gms.maps.model.CameraPosition
import com.google.android.gms.maps.model.LatLng
import com.google.maps.android.compose.MarkerComposable
import com.google.maps.android.compose.rememberCameraPositionState
import com.google.maps.android.compose.rememberUpdatedMarkerState
import dev.roozbahani.trailmetrics.core.designsystem.theme.TrailMetricsTheme
import dev.roozbahani.trailmetrics.core.error.stringRes
import dev.roozbahani.trailmetrics.core.map.RoutePolyline
import dev.roozbahani.trailmetrics.core.map.StartFinishMarker
import dev.roozbahani.trailmetrics.core.map.TrailGoogleMap
import dev.roozbahani.trailmetrics.domain.model.ActivityType
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.RoutePoint
import dev.roozbahani.trailmetrics.domain.model.UserProfile
import kotlinx.coroutines.launch
import org.koin.androidx.compose.koinViewModel

/**
 * NavHost entry point. Keeps the call site in MainActivity unchanged; delegates to [RouteRoot].
 */
@Composable
fun RouteScreen(
    onStartTrackingClicked: (
        startPoint: Coordinates,
        plannedRoutePoints: List<Coordinates>,
        activityType: ActivityType
    ) -> Unit,
    bottomBar: @Composable () -> Unit = {}
) {
    RouteRoot(
        onStartTrackingClicked = onStartTrackingClicked,
        bottomBar = bottomBar
    )
}

@Composable
fun RouteRoot(
    onStartTrackingClicked: (
        startPoint: Coordinates,
        plannedRoutePoints: List<Coordinates>,
        activityType: ActivityType
    ) -> Unit,
    bottomBar: @Composable () -> Unit = {}
) {
    val viewModel: RouteViewModel = koinViewModel()
    val state: RouteState by viewModel.state.collectAsStateWithLifecycle()
    val snackBarHostState = remember { SnackbarHostState() }
    val context = LocalContext.current
    var showProfileSheet: Boolean by remember { mutableStateOf(false) }

    val permissionHandler = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestMultiplePermissions()
    ) { permissions ->
        val granted = permissions.values.any { granted -> granted }
        if (granted) {
            viewModel.onAction(RouteAction.LocationPermissionGranted)
        }
    }

    @Suppress("LocalContextGetResourceValueCall")
    LaunchedEffect(Unit) {
        viewModel.events.collect { event ->
            when (event) {
                is RouteEvent.ShowError -> {
                    // A child of this effect, so the next event is not held until the snackbar is
                    // dismissed; SnackbarHostState still shows queued messages one at a time, in order.
                    launch { snackBarHostState.showSnackbar(context.getString(event.error.stringRes)) }
                }

                is RouteEvent.RequestLocationPermission -> {
                    permissionHandler.launch(
                        arrayOf(
                            Manifest.permission.ACCESS_FINE_LOCATION,
                            Manifest.permission.ACCESS_COARSE_LOCATION
                        )
                    )
                }

                is RouteEvent.RequestUserProfile -> {
                    showProfileSheet = true
                }

                is RouteEvent.NavigateToTracking -> {
                    onStartTrackingClicked(
                        event.startPoint,
                        event.plannedRoutePoints,
                        event.activityType
                    )
                }
            }
        }
    }

    RouteScreen(
        state = state,
        onAction = viewModel::onAction,
        snackBarHostState = snackBarHostState,
        showProfileSheet = showProfileSheet,
        onShowProfileSheetChange = { showProfileSheet = it },
        bottomBar = bottomBar
    )
}

@Composable
fun RouteScreen(
    state: RouteState,
    onAction: (RouteAction) -> Unit,
    snackBarHostState: SnackbarHostState,
    showProfileSheet: Boolean,
    onShowProfileSheetChange: (Boolean) -> Unit,
    bottomBar: @Composable () -> Unit = {}
) {
    val cameraPositionState = rememberCameraPositionState()
    val hapticFeedback = LocalHapticFeedback.current

    LaunchedEffect(state.startPoint) {
        state.startPoint?.let { coordinates ->
            cameraPositionState.position = CameraPosition.fromLatLngZoom(
                LatLng(coordinates.latitude, coordinates.longitude),
                DEFAULT_ZOOM
            )
        }
    }

    if (showProfileSheet) {
        UserProfileBottomSheet(
            initialWeightKg = state.userProfile?.weightKg,
            onDismiss = { onShowProfileSheetChange(false) },
            onSave = { onAction(RouteAction.UserProfileSaved(it)) }
        )
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackBarHostState) },
        bottomBar = bottomBar
    ) { innerPadding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
        ) {
            TrailGoogleMap(
                cameraPositionState = cameraPositionState,
                onMapLongClicked = { latLng ->
                    hapticFeedback.performHapticFeedback(HapticFeedbackType.LongPress)
                    onAction(
                        RouteAction.MapTapped(
                            Coordinates(latitude = latLng.latitude, longitude = latLng.longitude)
                        )
                    )
                }
            ) {
                state.startPoint?.let { startPoint ->
                    StartFinishMarker(
                        title = stringResource(CoreStrings.marker_title_start_finish),
                        coordinates = startPoint,
                    )
                }

                state.waypoints.forEach { point ->
                    MarkerComposable(
                        state = rememberUpdatedMarkerState(
                            position = LatLng(
                                point.coordinates.latitude,
                                point.coordinates.longitude
                            )
                        ),
                        onClick = {
                            onAction(RouteAction.WaypointRemoved(point))
                            true
                        }
                    ) {
                        Icon(
                            imageVector = Icons.Default.LocationOn,
                            contentDescription = null,
                            tint = Color.Red,
                            modifier = Modifier.size(48.dp)
                        )
                    }
                }

                state.generatedRoute?.let { route ->
                    RoutePolyline(points = route.points.map { it.coordinates })
                }
            }

            if (state.startPoint == null) {
                CircularProgressIndicator(
                    modifier = Modifier.align(Alignment.Center)
                )
            }

            FilledIconButton( // Reset Button
                onClick = { onAction(RouteAction.ResetClicked) },
                colors = IconButtonDefaults.filledIconButtonColors(
                    containerColor = MaterialTheme.colorScheme.surface,
                    contentColor = MaterialTheme.colorScheme.primary
                ),
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(16.dp)
                    .shadow(elevation = 4.dp, shape = CircleShape)
            ) {
                Icon(
                    imageVector = Icons.Default.Refresh,
                    contentDescription = stringResource(R.string.btn_reset_route)
                )
            }

            FilledIconButton(
                onClick = { onShowProfileSheetChange(true) },
                colors = IconButtonDefaults.filledIconButtonColors(
                    containerColor = MaterialTheme.colorScheme.surface,
                    contentColor = MaterialTheme.colorScheme.primary
                ),
                modifier = Modifier
                    .align(Alignment.TopStart)
                    .padding(16.dp)
                    .shadow(elevation = 4.dp, shape = CircleShape)
            ) {
                Icon(
                    imageVector = Icons.Filled.Person,
                    contentDescription = stringResource(R.string.cd_user_profile)
                )
            }

            Column(
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .fillMaxWidth()
                    .padding(16.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                val startPoint = state.startPoint
                val generatedRoute = state.generatedRoute
                if (generatedRoute != null && startPoint != null) {
                    StartTrackingPanel(
                        selectedActivityType = state.selectedActivityType,
                        onActivityTypeSelected = { onAction(RouteAction.ActivityTypeSelected(it)) },
                        onResetClicked = { onAction(RouteAction.ResetClicked) },
                        onStartTrackingClicked = { onAction(RouteAction.StartTrackingClicked) }
                    )
                }

                if (state.generatedRoute == null) {
                    Button( // Generate Button
                        onClick = { onAction(RouteAction.GenerateRouteClicked) },
                        enabled = state.canGenerateRoute
                    ) {
                        if (state.isLoading) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(20.dp),
                                strokeWidth = 2.dp
                            )
                        } else {
                            Text(stringResource(R.string.btn_generate_route))
                        }
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun UserProfileBottomSheet(
    initialWeightKg: Double?,
    onDismiss: () -> Unit,
    onSave: (weightKg: Double) -> Unit
) {
    var weightInput: String by remember { mutableStateOf(initialWeightKg?.toString().orEmpty()) }
    LaunchedEffect(initialWeightKg) {
        if (weightInput.isEmpty() && initialWeightKg != null) {
            weightInput = initialWeightKg.toString()
        }
    }
    val weightKg: Double? = weightInput.toDoubleOrNull()
    val isValid: Boolean = weightKg != null && weightKg > 0

    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text(
                modifier = Modifier.align(Alignment.CenterHorizontally),
                text = stringResource(R.string.title_user_profile),
                style = MaterialTheme.typography.titleLarge
            )
            Spacer(Modifier.height(16.dp))
            OutlinedTextField(
                modifier = Modifier.fillMaxWidth(),
                value = weightInput,
                onValueChange = { weightInput = it },
                label = { Text(stringResource(R.string.label_weight_kg)) },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                singleLine = true
            )
            Spacer(Modifier.height(24.dp))
            Button(
                onClick = {
                    weightKg?.let { onSave(it) }
                    onDismiss()
                },
                enabled = isValid,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(stringResource(R.string.btn_save))
            }
        }
    }
}

@Composable
fun StartTrackingPanel(
    selectedActivityType: ActivityType,
    onActivityTypeSelected: (ActivityType) -> Unit,
    onResetClicked: () -> Unit,
    onStartTrackingClicked: () -> Unit,
    modifier: Modifier = Modifier
) {
    Card(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceContainerHigh
        ),
        elevation = CardDefaults.cardElevation(defaultElevation = 4.dp)
    ) {
        Column {
            ActivityTypeSelector(
                selected = selectedActivityType,
                onSelected = onActivityTypeSelected,
                modifier = Modifier.padding(8.dp)
            )
            Row(
                modifier = Modifier
                    .align(Alignment.CenterHorizontally)
                    .padding(8.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                OutlinedButton(onClick = onResetClicked) {
                    Icon(imageVector = Icons.Filled.Refresh, contentDescription = null)
                    Spacer(Modifier.width(8.dp))
                    Text(stringResource(R.string.btn_reset_route))
                }
                Button(onClick = onStartTrackingClicked) {
                    Text(stringResource(R.string.btn_start_tracking))
                }
            }
        }
    }
}

@Composable
fun ActivityTypeSelector(
    selected: ActivityType,
    onSelected: (ActivityType) -> Unit,
    modifier: Modifier = Modifier
) {
    val options = ActivityType.entries

    SingleChoiceSegmentedButtonRow(modifier = modifier.fillMaxWidth()) {
        options.forEachIndexed { index, activityType ->
            SegmentedButton(
                selected = activityType == selected,
                onClick = { onSelected(activityType) },
                shape = SegmentedButtonDefaults.itemShape(index = index, count = options.count()),
                colors = SegmentedButtonDefaults.colors(
                    activeContainerColor = MaterialTheme.colorScheme.primary,
                    activeContentColor = MaterialTheme.colorScheme.onPrimary,
                    activeBorderColor = MaterialTheme.colorScheme.primary
                ),
                icon = {
                    Icon(
                        imageVector = iconFor(activityType),
                        contentDescription = null,
                        modifier = Modifier.size(SegmentedButtonDefaults.IconSize)
                    )
                },
                label = { Text(labelFor(activityType)) }
            )
        }
    }
}

@Composable
private fun labelFor(type: ActivityType): String = when (type) {
    ActivityType.Running -> stringResource(CoreStrings.activity_type_running)
    ActivityType.Cycling -> stringResource(CoreStrings.activity_type_cycling)
    ActivityType.Walking -> stringResource(CoreStrings.activity_type_walking)
}

private fun iconFor(type: ActivityType): ImageVector = when (type) {
    ActivityType.Running -> Icons.AutoMirrored.Filled.DirectionsRun
    ActivityType.Cycling -> Icons.AutoMirrored.Filled.DirectionsBike
    ActivityType.Walking -> Icons.AutoMirrored.Filled.DirectionsWalk
}

@Suppress("UnusedPrivateMember")
@Preview(showBackground = true)
@Composable
private fun ActivityTypeSelectorPreview() {
    TrailMetricsTheme {
        var selected by remember { mutableStateOf(ActivityType.Running) }

        Box(modifier = Modifier.padding(16.dp)) {
            ActivityTypeSelector(
                selected = selected,
                onSelected = { selected = it }
            )
        }
    }
}

// Detekt counts private @Preview functions as unused; they are only used by the IDE preview.
@Suppress("UnusedPrivateMember")
@Preview(showBackground = true)
@Composable
private fun RouteScreenPreview() {
    val start = Coordinates(latitude = 52.52, longitude = 13.405)
    TrailMetricsTheme {
        RouteScreen(
            state = RouteState(
                startPoint = start,
                waypoints = listOf(
                    RoutePoint(Coordinates(latitude = 52.523, longitude = 13.401), order = 0),
                    RoutePoint(Coordinates(latitude = 52.525, longitude = 13.410), order = 1),
                    RoutePoint(Coordinates(latitude = 52.519, longitude = 13.412), order = 2)
                ),
                userProfile = UserProfile(weightKg = 70.0)
            ),
            onAction = {},
            snackBarHostState = remember { SnackbarHostState() },
            showProfileSheet = false,
            onShowProfileSheetChange = {}
        )
    }
}

private const val DEFAULT_ZOOM = 15f
private typealias CoreStrings = dev.roozbahani.trailmetrics.core.ui.R.string
