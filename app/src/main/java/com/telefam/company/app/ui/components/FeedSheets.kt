package com.telefam.company.app.ui.components

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.telefam.company.app.R
import com.telefam.company.app.feed.FeedReportReason
import com.telefam.company.app.feed.FeedVideoVisibility
import com.telefam.company.app.network.FeedVideoDto
import com.telefam.company.app.ui.OwnerEditSheetState
import com.telefam.company.app.ui.ReportSheetState

private val SheetSurface = Color(0xFF15171C)
private val SheetDivider = Color(0xFF262A33)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CommentsComingSoonSheet(
    video: FeedVideoDto,
    onDismiss: () -> Unit
) {
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor = SheetSurface,
        contentColor = Color.White,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .navigationBarsPadding()
                .padding(horizontal = 24.dp, vertical = 16.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Box(
                modifier = Modifier
                    .size(56.dp)
                    .clip(CircleShape)
                    .background(FeedAccentCoral.copy(alpha = 0.16f)),
                contentAlignment = Alignment.Center
            ) {
                Image(
                    painter = painterResource(id = R.drawable.ic_feed_comment),
                    contentDescription = null,
                    colorFilter = ColorFilter.tint(FeedAccentCoral),
                    modifier = Modifier.size(26.dp)
                )
            }
            Spacer(modifier = Modifier.height(12.dp))
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Text(
                    text = stringResource(id = R.string.feed_comments_coming_soon),
                    fontSize = 18.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.White
                )
                Surface(
                    shape = RoundedCornerShape(10.dp),
                    color = FeedAccentCoral.copy(alpha = 0.2f)
                ) {
                    Text(
                        text = stringResource(id = R.string.feed_coming_soon_badge),
                        fontSize = 11.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = FeedAccentCoral,
                        modifier = Modifier.padding(horizontal = 8.dp, vertical = 3.dp)
                    )
                }
            }
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = stringResource(id = R.string.feed_comments_coming_soon_desc),
                fontSize = 14.sp,
                color = Color.White.copy(alpha = 0.72f)
            )
            if (video.commentsCount > 0L) {
                Spacer(modifier = Modifier.height(6.dp))
                Text(
                    text = "@${video.creatorUsername}",
                    fontSize = 12.sp,
                    color = Color.White.copy(alpha = 0.55f)
                )
            }
            Spacer(modifier = Modifier.height(20.dp))
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FeedVideoOptionsSheet(
    video: FeedVideoDto,
    onDismiss: () -> Unit,
    onReport: (FeedVideoDto) -> Unit,
    onToggleRepost: (FeedVideoDto) -> Unit,
    onBlockUser: (FeedVideoDto) -> Unit,
    onMuteUser: (FeedVideoDto) -> Unit,
    onNotInterested: (FeedVideoDto) -> Unit,
    onEditDetails: (FeedVideoDto) -> Unit,
    onMarkPrivate: (FeedVideoDto) -> Unit,
    onChangeVisibility: (FeedVideoDto) -> Unit,
    onDeleteVideo: (FeedVideoDto) -> Unit
) {
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor = SheetSurface,
        contentColor = Color.White,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .navigationBarsPadding()
                .padding(bottom = 16.dp)
        ) {
            if (video.isOwner) {
                SheetActionRow(
                    iconRes = R.drawable.ic_edit,
                    label = stringResource(id = R.string.feed_menu_edit_details),
                    onClick = { onEditDetails(video) },
                    testTag = "feed_owner_edit"
                )
                SheetActionRow(
                    iconRes = R.drawable.ic_visibility,
                    label = stringResource(id = R.string.feed_menu_visibility),
                    trailing = FeedVideoVisibility.fromApi(video.visibility).let { stringResource(id = it.labelRes) },
                    onClick = { onChangeVisibility(video) },
                    testTag = "feed_owner_visibility"
                )
                if (video.visibility != "private") {
                    SheetActionRow(
                        iconRes = R.drawable.ic_lock,
                        label = stringResource(id = R.string.feed_menu_mark_private),
                        onClick = { onMarkPrivate(video) },
                        testTag = "feed_owner_private"
                    )
                }
                HorizontalDivider(color = SheetDivider, modifier = Modifier.padding(vertical = 4.dp))
                SheetActionRow(
                    iconRes = R.drawable.ic_delete,
                    label = stringResource(id = R.string.feed_menu_delete),
                    tint = FeedAccentCoral,
                    onClick = { onDeleteVideo(video) },
                    testTag = "feed_owner_delete"
                )
            } else {
                SheetActionRow(
                    iconRes = R.drawable.ic_repost,
                    label = stringResource(id = if (video.isReposted) R.string.feed_menu_unrepost else R.string.feed_menu_repost),
                    tint = if (video.isReposted) FeedAccentCoral else Color.White,
                    onClick = { onToggleRepost(video) },
                    testTag = "feed_viewer_repost"
                )
                SheetActionRow(
                    iconRes = R.drawable.ic_visibility,
                    label = stringResource(id = R.string.feed_menu_not_interested),
                    onClick = { onNotInterested(video) },
                    testTag = "feed_viewer_not_interested"
                )
                SheetActionRow(
                    iconRes = R.drawable.ic_volume_off,
                    label = stringResource(id = R.string.feed_menu_mute),
                    onClick = { onMuteUser(video) },
                    testTag = "feed_viewer_mute"
                )
                HorizontalDivider(color = SheetDivider, modifier = Modifier.padding(vertical = 4.dp))
                SheetActionRow(
                    iconRes = R.drawable.ic_flag_report,
                    label = stringResource(id = R.string.feed_menu_report),
                    tint = FeedAccentCoral,
                    onClick = { onReport(video) },
                    testTag = "feed_viewer_report"
                )
                SheetActionRow(
                    iconRes = R.drawable.ic_block,
                    label = stringResource(id = R.string.feed_menu_block),
                    tint = FeedAccentCoral,
                    onClick = { onBlockUser(video) },
                    testTag = "feed_viewer_block"
                )
            }
        }
    }
}

@Composable
private fun SheetActionRow(
    iconRes: Int,
    label: String,
    trailing: String = "",
    tint: Color = Color.White,
    onClick: () -> Unit,
    testTag: String
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 22.dp, vertical = 14.dp)
            .testTag(testTag),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Image(
            painter = painterResource(id = iconRes),
            contentDescription = label,
            colorFilter = ColorFilter.tint(tint),
            modifier = Modifier.size(22.dp)
        )
        Spacer(modifier = Modifier.width(16.dp))
        Text(
            text = label,
            color = tint,
            fontSize = 15.sp,
            fontWeight = FontWeight.Medium,
            modifier = Modifier.weight(1f)
        )
        if (trailing.isNotBlank()) {
            Text(
                text = trailing,
                color = Color.White.copy(alpha = 0.6f),
                fontSize = 13.sp
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReportVideoSheet(
    state: ReportSheetState,
    onSelectReason: (FeedReportReason) -> Unit,
    onDetailsChange: (String) -> Unit,
    onBackStep: () -> Unit,
    onSubmit: () -> Unit,
    onDismiss: () -> Unit
) {
    if (state.video == null) return
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor = SheetSurface,
        contentColor = Color.White,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .navigationBarsPadding()
                .padding(horizontal = 20.dp, vertical = 12.dp)
        ) {
            Text(
                text = stringResource(
                    id = if (state.step == 1) R.string.feed_report_step1_title else R.string.feed_report_step2_title
                ),
                fontSize = 18.sp,
                fontWeight = FontWeight.Bold,
                color = Color.White
            )
            Spacer(modifier = Modifier.height(12.dp))
            if (state.step == 1) {
                FeedReportReason.entries.forEach { reason ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(12.dp))
                            .clickable { onSelectReason(reason) }
                            .padding(horizontal = 10.dp, vertical = 12.dp)
                            .testTag("report_reason_${reason.apiValue}"),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Text(
                            text = stringResource(id = reason.labelRes),
                            fontSize = 15.sp,
                            color = Color.White
                        )
                        Image(
                            painter = painterResource(id = R.drawable.ic_chevron_right),
                            contentDescription = null,
                            colorFilter = ColorFilter.tint(Color.White.copy(alpha = 0.5f)),
                            modifier = Modifier.size(18.dp)
                        )
                    }
                }
            } else {
                state.selectedReason?.let { r ->
                    Text(
                        text = stringResource(id = r.labelRes),
                        fontSize = 13.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = FeedAccentCoral
                    )
                    Spacer(modifier = Modifier.height(10.dp))
                }
                OutlinedTextField(
                    value = state.details,
                    onValueChange = onDetailsChange,
                    placeholder = {
                        Text(
                            stringResource(id = R.string.feed_report_details_hint),
                            color = Color.White.copy(alpha = 0.45f)
                        )
                    },
                    minLines = 3,
                    maxLines = 5,
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedTextColor = Color.White,
                        unfocusedTextColor = Color.White,
                        focusedBorderColor = FeedAccentCoral,
                        unfocusedBorderColor = SheetDivider
                    ),
                    modifier = Modifier
                        .fillMaxWidth()
                        .testTag("report_details_input")
                )
                Spacer(modifier = Modifier.height(14.dp))
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    OutlinedButton(
                        onClick = onBackStep,
                        enabled = !state.isSubmitting,
                        colors = ButtonDefaults.outlinedButtonColors(contentColor = Color.White),
                        modifier = Modifier
                            .weight(1f)
                            .height(48.dp)
                    ) {
                        Text(stringResource(id = R.string.feed_cancel))
                    }
                    Button(
                        onClick = onSubmit,
                        enabled = !state.isSubmitting,
                        colors = ButtonDefaults.buttonColors(
                            containerColor = FeedAccentCoral,
                            contentColor = Color.White
                        ),
                        modifier = Modifier
                            .weight(1f)
                            .height(48.dp)
                            .testTag("report_submit_button")
                    ) {
                        if (state.isSubmitting) {
                            CircularProgressIndicator(color = Color.White, modifier = Modifier.size(18.dp))
                        } else {
                            Text(stringResource(id = R.string.feed_report_submit))
                        }
                    }
                }
            }
            Spacer(modifier = Modifier.height(12.dp))
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun OwnerEditDetailsSheet(
    state: OwnerEditSheetState,
    onTitleChange: (String) -> Unit,
    onDescriptionChange: (String) -> Unit,
    onSave: () -> Unit,
    onDismiss: () -> Unit
) {
    if (state.video == null) return
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor = SheetSurface,
        contentColor = Color.White,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .navigationBarsPadding()
                .padding(horizontal = 20.dp, vertical = 14.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text(
                text = stringResource(id = R.string.feed_menu_edit_details),
                fontSize = 18.sp,
                fontWeight = FontWeight.Bold,
                color = Color.White
            )
            OutlinedTextField(
                value = state.title,
                onValueChange = onTitleChange,
                label = { Text("Title", color = Color.White.copy(alpha = 0.65f)) },
                singleLine = true,
                colors = OutlinedTextFieldDefaults.colors(
                    focusedTextColor = Color.White,
                    unfocusedTextColor = Color.White,
                    focusedBorderColor = FeedAccentCoral,
                    unfocusedBorderColor = SheetDivider
                ),
                modifier = Modifier.fillMaxWidth()
            )
            OutlinedTextField(
                value = state.description,
                onValueChange = onDescriptionChange,
                label = { Text("Description", color = Color.White.copy(alpha = 0.65f)) },
                minLines = 3,
                maxLines = 5,
                colors = OutlinedTextFieldDefaults.colors(
                    focusedTextColor = Color.White,
                    unfocusedTextColor = Color.White,
                    focusedBorderColor = FeedAccentCoral,
                    unfocusedBorderColor = SheetDivider
                ),
                modifier = Modifier.fillMaxWidth()
            )
            Button(
                onClick = onSave,
                enabled = !state.isSaving,
                colors = ButtonDefaults.buttonColors(
                    containerColor = FeedAccentCoral,
                    contentColor = Color.White
                ),
                modifier = Modifier
                    .fillMaxWidth()
                    .height(48.dp)
            ) {
                if (state.isSaving) {
                    CircularProgressIndicator(color = Color.White, modifier = Modifier.size(18.dp))
                } else {
                    Text(stringResource(id = R.string.feed_save))
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun OwnerVisibilitySheet(
    video: FeedVideoDto,
    onSelectVisibility: (String) -> Unit,
    onDismiss: () -> Unit
) {
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor = SheetSurface,
        contentColor = Color.White
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .navigationBarsPadding()
                .padding(horizontal = 20.dp, vertical = 12.dp)
        ) {
            Text(
                text = stringResource(id = R.string.feed_menu_visibility),
                fontSize = 18.sp,
                fontWeight = FontWeight.Bold,
                color = Color.White
            )
            Spacer(modifier = Modifier.height(10.dp))
            FeedVideoVisibility.entries.forEach { vis ->
                val selected = video.visibility.equals(vis.apiValue, ignoreCase = true)
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(12.dp))
                        .clickable { onSelectVisibility(vis.apiValue) }
                        .padding(horizontal = 12.dp, vertical = 14.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text(
                        text = stringResource(id = vis.labelRes),
                        fontSize = 15.sp,
                        fontWeight = if (selected) FontWeight.Bold else FontWeight.Normal,
                        color = if (selected) FeedAccentCoral else Color.White
                    )
                    if (selected) {
                        Image(
                            painter = painterResource(id = R.drawable.ic_check),
                            contentDescription = null,
                            colorFilter = ColorFilter.tint(FeedAccentCoral),
                            modifier = Modifier.size(18.dp)
                        )
                    }
                }
            }
            Spacer(modifier = Modifier.height(8.dp))
        }
    }
}

@Composable
fun ConfirmSafetyDialog(
    title: String,
    description: String,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = SheetSurface,
        titleContentColor = Color.White,
        textContentColor = Color.White.copy(alpha = 0.78f),
        title = { Text(title, fontWeight = FontWeight.Bold) },
        text = { Text(description) },
        confirmButton = {
            Button(
                onClick = onConfirm,
                colors = ButtonDefaults.buttonColors(
                    containerColor = FeedAccentCoral,
                    contentColor = Color.White
                )
            ) {
                Text(stringResource(id = R.string.feed_confirm))
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text(stringResource(id = R.string.feed_cancel), color = Color.White.copy(alpha = 0.8f))
            }
        }
    )
}
