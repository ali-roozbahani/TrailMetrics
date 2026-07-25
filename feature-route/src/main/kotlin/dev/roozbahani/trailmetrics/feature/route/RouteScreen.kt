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
import dev.roozbahani.trailmetrics.core.map.RoutePolyline
import dev.roozbahani.trailmetrics.core.map.StartFinishMarker
import dev.roozbahani.trailmetrics.core.map.TrailGoogleMap
import dev.roozbahani.trailmetrics.domain.model.ActivityType
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import org.koin.androidx.compose.koinViewModel

@Composable
fun RouteScreen(
    viewModel: RouteViewModel = koinViewModel(),
    onStartTrackingClicked: (startPoint: Coordinates, plannedRoutePoints: List<Coordinates>, activityType: ActivityType) -> Unit
) {
    val uiState: RouteUiState by viewModel.uiState.collectAsStateWithLifecycle()
    val cameraPositionState = rememberCameraPositionState()
    val snackBarHostState = remember { SnackbarHostState() }
    val hapticFeedback = LocalHapticFeedback.current
    val context = LocalContext.current
    var showProfileSheet: Boolean by remember { mutableStateOf(false) }

    val permissionHandler = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestMultiplePermissions()
    ) { permissions ->
        val granted = permissions.values.any { granted -> granted }
        if (granted) {
            viewModel.onLocationPermissionGranted()
        }
    }

    @Suppress("LocalContextGetResourceValueCall")
    LaunchedEffect(Unit) {
        viewModel.uiEvents.collect { event ->
            when (event) {
                is RouteUiEvent.ShowError -> {
                    snackBarHostState.showSnackbar(context.getString(event.error.errorResId))
                }

                is RouteUiEvent.RequestLocationPermission -> {
                    permissionHandler.launch(
                        arrayOf(
                            Manifest.permission.ACCESS_FINE_LOCATION,
                            Manifest.permission.ACCESS_COARSE_LOCATION
                        )
                    )
                }

                is RouteUiEvent.RequestUserProfile -> {
                    showProfileSheet = true
                }

                is RouteUiEvent.NavigateToTracking -> {
                    onStartTrackingClicked(
                        event.startPoint,
                        event.plannedRoutePoints,
                        event.activityType
                    )
                }
            }
        }
    }

    LaunchedEffect(uiState.startPoint) {
        uiState.startPoint?.let { coordinates ->
            cameraPositionState.position = CameraPosition.fromLatLngZoom(
                LatLng(coordinates.latitude, coordinates.longitude),
                DEFAULT_ZOOM
            )
        }
    }

    if (showProfileSheet) {
        UserProfileBottomSheet(
            initialWeightKg = uiState.userProfile?.weightKg,
            onDismiss = { showProfileSheet = false },
            onSave = { viewModel.saveUserProfile(it) }
        )
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackBarHostState) }
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
                    viewModel.onMapTapped(
                        Coordinates(latitude = latLng.latitude, longitude = latLng.longitude)
                    )
                }
            ) {
                uiState.startPoint?.let { startPoint ->
                    StartFinishMarker(
                        title = stringResource(R.string.marker_title_start_finish),
                        coordinates = startPoint,
                    )
                }

                uiState.waypoints.forEach { point ->
                    MarkerComposable(
                        state = rememberUpdatedMarkerState(
                            position = LatLng(
                                point.coordinates.latitude,
                                point.coordinates.longitude
                            )
                        ),
                        onClick = {
                            viewModel.onWaypointRemoved(point)
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

                uiState.generatedRoute?.let { route ->
                    RoutePolyline(points = route.points.map { it.coordinates })
                }
            }

            if (uiState.startPoint == null) {
                CircularProgressIndicator(
                    modifier = Modifier.align(Alignment.Center)
                )
            }

            FilledIconButton( // Reset Button
                onClick = viewModel::onResetClicked,
                colors = IconButtonDefaults.filledIconButtonColors(
                    containerColor = MaterialTheme.colorScheme.surface
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
                onClick = { showProfileSheet = true },
                colors = IconButtonDefaults.filledIconButtonColors(
                    containerColor = MaterialTheme.colorScheme.surface
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
                val startPoint = uiState.startPoint
                val generatedRoute = uiState.generatedRoute
                if (generatedRoute != null && startPoint != null) {
                    StartTrackingPanel(
                        selectedActivityType = uiState.selectedActivityType,
                        onActivityTypeSelected = { viewModel.onActivityTypeSelected(it) },
                        onResetClicked = viewModel::onResetClicked,
                        onStartTrackingClicked = viewModel::onStartTrackingClicked
                    )
                }

                if (uiState.generatedRoute == null) {
                    Button( // Generate Button
                        onClick = { viewModel.onGenerateRouteClicked() },
                        enabled = uiState.canGenerateRoute
                    ) {
                        if (uiState.isLoading) {
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
        modifier = modifier.fillMaxWidth(),
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
    ActivityType.Running -> stringResource(R.string.activity_type_running)
    ActivityType.Cycling -> stringResource(R.string.activity_type_cycling)
    ActivityType.Walking -> stringResource(R.string.activity_type_walking)
}

private fun iconFor(type: ActivityType): ImageVector = when (type) {
    ActivityType.Running -> Icons.AutoMirrored.Filled.DirectionsRun
    ActivityType.Cycling -> Icons.AutoMirrored.Filled.DirectionsBike
    ActivityType.Walking -> Icons.AutoMirrored.Filled.DirectionsWalk
}

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

private const val DEFAULT_ZOOM = 15f
