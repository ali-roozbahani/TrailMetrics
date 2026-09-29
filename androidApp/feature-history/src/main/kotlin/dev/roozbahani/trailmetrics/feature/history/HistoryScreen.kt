package dev.roozbahani.trailmetrics.feature.history

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.DirectionsBike
import androidx.compose.material.icons.automirrored.filled.DirectionsRun
import androidx.compose.material.icons.automirrored.filled.DirectionsWalk
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.Route
import androidx.compose.material.icons.filled.Timer
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
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
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import coil.compose.AsyncImage
import dev.roozbahani.trailmetrics.core.designsystem.component.MetricCell
import dev.roozbahani.trailmetrics.core.designsystem.theme.TrailMetricsTheme
import dev.roozbahani.trailmetrics.domain.model.ActivityRecord
import dev.roozbahani.trailmetrics.domain.model.ActivityType
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.util.formatCalories
import dev.roozbahani.trailmetrics.domain.util.formatDistance
import dev.roozbahani.trailmetrics.domain.util.formatElapsedTime
import org.koin.androidx.compose.koinViewModel
import java.text.DateFormat
import java.util.Date

/**
 * NavHost entry point. Keeps the call site in MainActivity unchanged; delegates to [HistoryRoot].
 */
@Composable
fun HistoryScreen(
    onActivityClicked: (activityId: Long) -> Unit,
    bottomBar: @Composable () -> Unit = {}
) {
    HistoryRoot(
        onActivityClicked = onActivityClicked,
        bottomBar = bottomBar
    )
}

@Composable
fun HistoryRoot(
    onActivityClicked: (activityId: Long) -> Unit,
    bottomBar: @Composable () -> Unit = {}
) {
    val viewModel: HistoryViewModel = koinViewModel()
    val state: HistoryState by viewModel.state.collectAsStateWithLifecycle()

    LaunchedEffect(Unit) {
        viewModel.events.collect { event ->
            when (event) {
                is HistoryEvent.NavigateToDetails -> onActivityClicked(event.activityId)
            }
        }
    }

    HistoryScreen(
        state = state,
        onAction = viewModel::onAction,
        bottomBar = bottomBar
    )
}

@Composable
fun HistoryScreen(
    state: HistoryState,
    onAction: (HistoryAction) -> Unit,
    bottomBar: @Composable () -> Unit = {}
) {
    var activityPendingDelete by remember { mutableStateOf<ActivityRecord?>(null) }

    Scaffold(
        bottomBar = bottomBar
    ) { innerPadding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
        ) {
            when {
                state.isLoading -> {
                    CircularProgressIndicator(modifier = Modifier.align(Alignment.Center))
                }

                state.isEmpty -> {
                    Text(
                        text = stringResource(R.string.msg_no_activities),
                        modifier = Modifier.align(Alignment.Center),
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }

                else -> {
                    LazyColumn(
                        contentPadding = PaddingValues(16.dp),
                        modifier = Modifier.fillMaxSize(),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        items(
                            items = state.activities,
                            key = { activity -> activity.id }
                        ) { activity ->
                            ActivityRow(
                                activity = activity,
                                onClick = { onAction(HistoryAction.ActivityClicked(activity.id)) },
                                onDeleteClicked = { activityPendingDelete = activity }
                            )
                        }
                    }
                }
            }
        }
    }

    activityPendingDelete?.let { activity ->
        AlertDialog(
            onDismissRequest = { activityPendingDelete = null },
            title = { Text(stringResource(R.string.dialog_delete_activity_title)) },
            text = { Text(stringResource(R.string.dialog_delete_activity_message)) },
            confirmButton = {
                TextButton(onClick = {
                    onAction(HistoryAction.DeleteConfirmed(activity))
                    activityPendingDelete = null
                }) {
                    Text(stringResource(R.string.dialog_delete_activity_confirm))
                }
            },
            dismissButton = {
                TextButton(onClick = { activityPendingDelete = null }) {
                    Text(stringResource(R.string.dialog_delete_activity_dismiss))
                }
            }
        )
    }
}

@Composable
private fun ActivityRow(
    activity: ActivityRecord,
    onClick: () -> Unit,
    onDeleteClicked: () -> Unit,
    modifier: Modifier = Modifier
) {
    Card(
        onClick = onClick,
        modifier = modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainer)
    ) {
        Box {
            // Route image snapshot
            if (!activity.snapshotFilePath.isNullOrBlank()) {
                AsyncImage(
                    model = activity.snapshotFilePath,
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(160.dp)
                )
            } else {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(160.dp)
                        .background(MaterialTheme.colorScheme.surfaceContainerHigh)
                )
            }

            Row( // Activity type icon & label
                modifier = Modifier
                    .align(Alignment.TopStart)
                    .padding(8.dp)
                    .background(
                        color = MaterialTheme.colorScheme.surface,
                        shape = RoundedCornerShape(8.dp)
                    )
                    .padding(horizontal = 8.dp, vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    imageVector = iconFor(activity.activityType),
                    contentDescription = null,
                    modifier = Modifier.size(16.dp),
                    tint = MaterialTheme.colorScheme.primary
                )
                Spacer(Modifier.size(4.dp))
                Text(
                    text = labelFor(activity.activityType),
                    style = MaterialTheme.typography.labelMedium
                )
            }

            Text( // Started At Datetime
                text = DateFormat.getDateTimeInstance(
                    DateFormat.MEDIUM,
                    DateFormat.SHORT
                ).format(Date(activity.startedAtEpochMillis)),
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(8.dp)
                    .background(
                        color = MaterialTheme.colorScheme.surface,
                        shape = RoundedCornerShape(8.dp)
                    )
                    .padding(horizontal = 8.dp, vertical = 4.dp),
                style = MaterialTheme.typography.labelSmall
            )

            FilledIconButton( // Delete Button
                onClick = onDeleteClicked,
                colors = IconButtonDefaults.filledIconButtonColors(
                    containerColor = MaterialTheme.colorScheme.surface
                ),
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .padding(8.dp)
                    .shadow(elevation = 4.dp, shape = CircleShape)
            ) {
                Icon(
                    imageVector = Icons.Filled.Delete,
                    contentDescription = stringResource(R.string.cd_delete_activity),
                    tint = MaterialTheme.colorScheme.error
                )
            }
        }

        Row(
            modifier = Modifier.padding(8.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            MetricCell(
                label = stringResource(CoreStrings.label_distance),
                value = formatDistance(activity.distanceMeters),
                icon = Icons.Filled.Route,
                modifier = Modifier.weight(1f)
            )
            MetricCell(
                label = stringResource(CoreStrings.label_duration),
                value = formatElapsedTime(activity.durationMillis),
                icon = Icons.Filled.Timer,
                modifier = Modifier.weight(1f)
            )
            MetricCell(
                label = stringResource(CoreStrings.label_calories),
                value = formatCalories(activity.calories),
                icon = Icons.Filled.LocalFireDepartment,
                modifier = Modifier.weight(1f)
            )
        }
    }
}

private fun iconFor(activityType: ActivityType): ImageVector =
    when (activityType) {
        ActivityType.Running -> Icons.AutoMirrored.Filled.DirectionsRun
        ActivityType.Cycling -> Icons.AutoMirrored.Filled.DirectionsBike
        ActivityType.Walking -> Icons.AutoMirrored.Filled.DirectionsWalk
    }

@Composable
private fun labelFor(type: ActivityType): String = when (type) {
    ActivityType.Running -> stringResource(CoreStrings.activity_type_running)
    ActivityType.Cycling -> stringResource(CoreStrings.activity_type_cycling)
    ActivityType.Walking -> stringResource(CoreStrings.activity_type_walking)
}

// Detekt counts private @Preview functions as unused; they are only used by the IDE preview.
@Suppress("UnusedPrivateMember")
@Preview(showBackground = true)
@Composable
private fun HistoryScreenPreview() {
    val start = Coordinates(latitude = 52.52, longitude = 13.405)
    TrailMetricsTheme {
        HistoryScreen(
            state = HistoryState(
                activities = listOf(
                    ActivityRecord(
                        id = 1L,
                        activityType = ActivityType.Running,
                        startedAtEpochMillis = 1_758_000_000_000L,
                        endedAtEpochMillis = 1_758_001_800_000L,
                        distanceMeters = 5_230.0,
                        durationMillis = 1_800_000L,
                        averageSpeedMetersPerSecond = 2.9f,
                        calories = 412.0,
                        plannedRoutePoints = listOf(start),
                        actualPath = listOf(start),
                        snapshotFilePath = null
                    ),
                    ActivityRecord(
                        id = 2L,
                        activityType = ActivityType.Cycling,
                        startedAtEpochMillis = 1_758_100_000_000L,
                        endedAtEpochMillis = 1_758_103_600_000L,
                        distanceMeters = 21_400.0,
                        durationMillis = 3_600_000L,
                        averageSpeedMetersPerSecond = 5.9f,
                        calories = null,
                        plannedRoutePoints = listOf(start),
                        actualPath = listOf(start),
                        snapshotFilePath = null
                    )
                ),
                isLoading = false
            ),
            onAction = {}
        )
    }
}

typealias CoreStrings = dev.roozbahani.trailmetrics.core.ui.R.string
