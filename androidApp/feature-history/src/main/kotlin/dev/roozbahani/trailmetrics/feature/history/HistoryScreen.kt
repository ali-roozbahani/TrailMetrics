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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.DirectionsBike
import androidx.compose.material.icons.automirrored.filled.DirectionsRun
import androidx.compose.material.icons.automirrored.filled.DirectionsWalk
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.Route
import androidx.compose.material.icons.filled.Timer
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import coil.compose.AsyncImage
import dev.roozbahani.trailmetrics.core.designsystem.component.MetricCell
import dev.roozbahani.trailmetrics.domain.model.ActivityRecord
import dev.roozbahani.trailmetrics.domain.model.ActivityType
import dev.roozbahani.trailmetrics.domain.util.formatCalories
import dev.roozbahani.trailmetrics.domain.util.formatDistance
import dev.roozbahani.trailmetrics.domain.util.formatElapsedTime
import org.koin.androidx.compose.koinViewModel
import java.text.DateFormat
import java.util.Date

@Composable
fun HistoryScreen(
    onActivityClicked: (activityId: Long) -> Unit,
    bottomBar: @Composable () -> Unit = {},
    viewModel: HistoryViewModel = koinViewModel()
) {

    val uiState: HistoryUiState by viewModel.uiState.collectAsStateWithLifecycle()

    Scaffold(
        bottomBar = bottomBar
    ) { innerPadding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
        ) {
            when {
                uiState.isLoading -> {
                    CircularProgressIndicator(modifier = Modifier.align(Alignment.Center))
                }

                uiState.isEmpty -> {
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
                            items = uiState.activities,
                            key = { activity -> activity.id }
                        ) { activity ->
                            ActivityRow(
                                activity = activity,
                                onClick = { onActivityClicked(activity.id) }
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun ActivityRow(
    activity: ActivityRecord,
    onClick: () -> Unit,
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

typealias CoreStrings = dev.roozbahani.trailmetrics.core.R.string
