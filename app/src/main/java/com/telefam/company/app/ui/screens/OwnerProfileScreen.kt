package com.telefam.company.app.ui.screens

import android.content.Intent
import android.graphics.Bitmap
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.telefam.company.app.R
import com.telefam.company.app.data.ContactModel
import com.telefam.company.app.feed.FeedFormatter
import com.telefam.company.app.network.AuthSessionDto
import com.telefam.company.app.network.MyProfileDto
import com.telefam.company.app.network.OwnerProfileItemDto
import com.telefam.company.app.ui.OwnerProfileTab
import com.telefam.company.app.ui.OwnerProfileUiState
import kotlinx.coroutines.delay
import java.io.File

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun OwnerProfileScreen(
    modifier: Modifier = Modifier,
    isDarkTheme: Boolean,
    session: AuthSessionDto,
    profile: MyProfileDto?,
    ownerState: OwnerProfileUiState,
    bottomNavInsetPadding: Dp,
    onEditProfile: () -> Unit,
    onAvatarCropped: (Bitmap) -> Unit,
    onUploadBackgroundPhotos: (List<Uri>) -> Unit,
    onDeleteBackgroundPhoto: (String) -> Unit,
    onSelectCategory: (OwnerProfileTab) -> Unit,
    onPullRefresh: () -> Unit,
    onOpenConnections: (String) -> Unit,
    onCloseConnections: () -> Unit,
    onToggleConnectionFollow: (ContactModel) -> Unit,
    onOpenItem: (OwnerProfileItemDto) -> Unit,
    onCloseItemViewer: () -> Unit,
    onTogglePostLike: (OwnerProfileItemDto) -> Unit,
    onTogglePostSave: (OwnerProfileItemDto) -> Unit,
    onTogglePostLock: (OwnerProfileItemDto) -> Unit,
    onShowToast: (String) -> Unit,
    onBottomBarVisibilityChange: (Boolean) -> Unit,
    onOpenUserProfile: (String) -> Unit = {}
) {
    val context = LocalContext.current
    val clipboard = LocalClipboardManager.current
    val gridState = rememberLazyGridState()

    var comingSoonReason by remember { mutableStateOf<String?>(null) }
    var showBackgroundManager by remember { mutableStateOf(false) }
    var pendingCropBitmap by remember { mutableStateOf<Bitmap?>(null) }
    var activeBgIndex by remember { mutableIntStateOf(0) }

    val avatarPicker = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.PickVisualMedia()
    ) { uri ->
        if (uri != null) {
            pendingCropBitmap = decodeSampledBitmap(context, uri, 1024)
        }
    }

    val backgroundPicker = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.PickMultipleVisualMedia(5)
    ) { uris ->
        if (uris.isNotEmpty()) {
            onUploadBackgroundPhotos(uris)
        }
    }

    // Track scroll for cover parallax / collapse and bottom-bar show-hide
    var prevScrollIndex by remember { mutableIntStateOf(0) }
    var prevScrollOffset by remember { mutableIntStateOf(0) }
    LaunchedEffect(gridState.isScrollInProgress, gridState.firstVisibleItemIndex, gridState.firstVisibleItemScrollOffset) {
        if (gridState.isScrollInProgress) {
            val idx = gridState.firstVisibleItemIndex
            val off = gridState.firstVisibleItemScrollOffset
            val down = idx > prevScrollIndex || (idx == prevScrollIndex && off > prevScrollOffset + 10)
            val up = idx < prevScrollIndex || (idx == prevScrollIndex && off + 10 < prevScrollOffset)
            if (down) onBottomBarVisibilityChange(false)
            else if (up) onBottomBarVisibilityChange(true)
            prevScrollIndex = idx
            prevScrollOffset = off
        } else {
            onBottomBarVisibilityChange(true)
        }
    }

    // Resolve cover photo models (local cached files take priority for offline-first speed)
    val coverModels: List<Any> = remember(ownerState.localBackgroundPaths, profile?.backgroundPhotos) {
        if (ownerState.localBackgroundPaths.isNotEmpty()) {
            ownerState.localBackgroundPaths.map { File(it) }
        } else {
            emptyList()
        }
    }

    LaunchedEffect(coverModels.size) {
        if (activeBgIndex >= coverModels.size.coerceAtLeast(1)) {
            activeBgIndex = 0
        }
        if (coverModels.size > 1) {
            while (true) {
                delay(5000L)
                activeBgIndex = (activeBgIndex + 1) % coverModels.size
            }
        }
    }

    val scrollPx by remember {
        derivedStateOf {
            if (gridState.firstVisibleItemIndex == 0) {
                gridState.firstVisibleItemScrollOffset.toFloat()
            } else {
                900f
            }
        }
    }
    val density = LocalDensity.current
    val maxCollapsePx = with(density) { 170.dp.toPx() }
    val collapseFraction = (scrollPx / maxCollapsePx).coerceIn(0f, 1f)

    val fullName = profile?.fullName?.takeIf { it.isNotBlank() } ?: session.displayName.ifBlank { "Telefam User" }
    val username = profile?.username?.takeIf { it.isNotBlank() } ?: session.email.substringBefore("@")
    val bio = profile?.bio.orEmpty().trim()
    val followersCount = profile?.followersCount ?: 0L
    val followingCount = profile?.followingCount ?: 0L
    val postsCount = profile?.postsCount ?: 0L
    val viewsCount = profile?.viewsCount ?: 0L

    val activeTab = ownerState.activeCategory
    val gridItems = ownerState.itemsByCategory[activeTab].orEmpty()
    val surfaceBg = MaterialTheme.colorScheme.background
    val primaryCrimson = MaterialTheme.colorScheme.primary
    val secondaryInk = MaterialTheme.colorScheme.onSurfaceVariant
    val primaryInk = MaterialTheme.colorScheme.onBackground
    val cardBorder = MaterialTheme.colorScheme.outlineVariant
    val usernameCopiedMsg = stringResource(id = R.string.owner_profile_username_copied)
    val linkCopiedMsg = stringResource(id = R.string.owner_profile_link_copied)

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(surfaceBg)
    ) {
        BoxWithConstraints(modifier = Modifier.fillMaxSize()) {
            val isWide = maxWidth >= 680.dp
            val gridColumns = if (maxWidth >= 960.dp) 5 else if (isWide) 4 else 3
            val headerMaxWidth = if (isWide) 840.dp else Dp.Unspecified

            PullToRefreshBox(
                isRefreshing = ownerState.isRefreshing,
                onRefresh = onPullRefresh,
                modifier = Modifier.fillMaxSize()
            ) {
                LazyVerticalGrid(
                    columns = GridCells.Fixed(gridColumns),
                    state = gridState,
                    modifier = Modifier
                        .fillMaxSize()
                        .testTag("owner_profile_grid"),
                    contentPadding = PaddingValues(
                        bottom = bottomNavInsetPadding + 18.dp
                    ),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    // Header spans all columns
                    item(span = { GridItemSpan(gridColumns) }, key = "owner_header") {
                        Column(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalAlignment = Alignment.CenterHorizontally
                        ) {
                            // 1) Top Crimson Wave + Crossfading Cover Banner + Floating Avatar + Edit/Settings
                            Box(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .then(if (headerMaxWidth != Dp.Unspecified) Modifier.widthIn(max = headerMaxWidth) else Modifier)
                            ) {
                                // Cover container with parallax + gentle scroll compression
                                val baseCoverHeight = if (isWide) 245.dp else 230.dp
                                Box(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .height(baseCoverHeight)
                                        .graphicsLayer {
                                            translationY = -scrollPx * 0.25f
                                            alpha = (1f - collapseFraction * 0.35f).coerceIn(0.6f, 1f)
                                        }
                                ) {
                                    if (coverModels.isNotEmpty()) {
                                        Crossfade(
                                            targetState = activeBgIndex % coverModels.size,
                                            animationSpec = tween(durationMillis = 850),
                                            label = "cover_crossfade"
                                        ) { idx ->
                                            AsyncImage(
                                                model = coverModels[idx],
                                                contentDescription = null,
                                                contentScale = ContentScale.Crop,
                                                modifier = Modifier.fillMaxSize()
                                            )
                                        }
                                    } else {
                                        Box(
                                            modifier = Modifier
                                                .fillMaxSize()
                                                .background(
                                                    Brush.linearGradient(
                                                        colors = listOf(
                                                            Color(0xFF9C0A0A),
                                                            Color(0xFFD9381E),
                                                            Color(0xFFF39C12),
                                                            Color(0xFF4B1D3F)
                                                        )
                                                    )
                                                )
                                        )
                                    }

                                    // Top subtle crimson gradient + layered crimson wave matching uploaded screenshot
                                    Canvas(
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .height(104.dp)
                                            .align(Alignment.TopCenter)
                                    ) {
                                        val w = size.width
                                        val h = size.height
                                        val backWave = Path().apply {
                                            moveTo(0f, 0f)
                                            lineTo(w, 0f)
                                            lineTo(w, h * 0.56f)
                                            cubicTo(
                                                w * 0.72f, h * 0.78f,
                                                w * 0.42f, h * 0.42f,
                                                0f, h * 0.72f
                                            )
                                            close()
                                        }
                                        drawPath(backWave, color = Color(0xFFB30E0E).copy(alpha = 0.86f))

                                        val frontWave = Path().apply {
                                            moveTo(0f, 0f)
                                            lineTo(w, 0f)
                                            lineTo(w, h * 0.44f)
                                            cubicTo(
                                                w * 0.76f, h * 0.74f,
                                                w * 0.48f, h * 0.28f,
                                                0f, h * 0.62f
                                            )
                                            close()
                                        }
                                        drawPath(frontWave, color = primaryCrimson)
                                    }

                                    // Top-right 3-dash menu button inside status bar safe area
                                    IconButton(
                                        onClick = { comingSoonReason = "menu" },
                                        modifier = Modifier
                                            .align(Alignment.TopEnd)
                                            .windowInsetsPadding(WindowInsets.statusBars)
                                            .padding(top = 2.dp, end = 6.dp)
                                            .size(48.dp)
                                            .testTag("owner_profile_menu_button")
                                    ) {
                                        Image(
                                            painter = painterResource(id = R.drawable.ic_menu_dashes),
                                            contentDescription = "Menu",
                                            modifier = Modifier.size(22.dp)
                                        )
                                    }

                                    // Arched white/surface bottom seam overlapping cover
                                    Canvas(
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .height(34.dp)
                                            .align(Alignment.BottomCenter)
                                    ) {
                                        val w = size.width
                                        val h = size.height
                                        val arch = Path().apply {
                                            moveTo(0f, h)
                                            lineTo(0f, h * 0.55f)
                                            cubicTo(
                                                w * 0.34f, h * 0.96f,
                                                w * 0.72f, h * 0.42f,
                                                w, h * 0.14f
                                            )
                                            lineTo(w, h)
                                            close()
                                        }
                                        drawPath(arch, color = surfaceBg)
                                    }

                                    // "Change Background" dark translucent pill at bottom-right of cover
                                    Box(
                                        modifier = Modifier
                                            .align(Alignment.BottomEnd)
                                            .padding(end = 14.dp, bottom = 22.dp)
                                            .heightIn(min = 48.dp)
                                            .clickable { showBackgroundManager = true }
                                            .testTag("owner_profile_change_bg_button"),
                                        contentAlignment = Alignment.Center
                                    ) {
                                        Row(
                                            modifier = Modifier
                                                .clip(RoundedCornerShape(22.dp))
                                                .background(Color.Black.copy(alpha = 0.58f))
                                                .border(1.dp, Color.White.copy(alpha = 0.22f), RoundedCornerShape(22.dp))
                                                .padding(horizontal = 12.dp, vertical = 7.dp),
                                            verticalAlignment = Alignment.CenterVertically,
                                            horizontalArrangement = Arrangement.spacedBy(7.dp)
                                        ) {
                                            if (ownerState.isUploadingBackgrounds) {
                                                CircularProgressIndicator(
                                                    color = Color.White,
                                                    strokeWidth = 2.dp,
                                                    modifier = Modifier.size(16.dp)
                                                )
                                            } else {
                                                Image(
                                                    painter = painterResource(id = R.drawable.ic_camera),
                                                    contentDescription = null,
                                                    colorFilter = ColorFilter.tint(Color.White),
                                                    modifier = Modifier.size(18.dp)
                                                )
                                            }
                                            Text(
                                                text = stringResource(id = R.string.owner_profile_change_bg),
                                                color = Color.White,
                                                fontSize = 11.sp,
                                                lineHeight = 13.sp,
                                                fontWeight = FontWeight.Medium
                                            )
                                        }
                                    }
                                }

                                // Row straddling bottom of cover: Overlapping Avatar + Edit Profile & Settings buttons
                                Row(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(top = baseCoverHeight - 66.dp, start = 16.dp, end = 16.dp),
                                    verticalAlignment = Alignment.Bottom
                                ) {
                                    // Overlapping Circular Avatar + Camera Badge
                                    val avatarScale = 1f - collapseFraction * 0.16f
                                    Box(
                                        modifier = Modifier
                                            .size(112.dp)
                                            .graphicsLayer {
                                                scaleX = avatarScale
                                                scaleY = avatarScale
                                            }
                                    ) {
                                        Box(
                                            modifier = Modifier
                                                .size(106.dp)
                                                .shadow(6.dp, CircleShape)
                                                .clip(CircleShape)
                                                .background(surfaceBg)
                                                .border(4.dp, surfaceBg, CircleShape)
                                                .clickable {
                                                    avatarPicker.launch(
                                                        PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)
                                                    )
                                                }
                                                .testTag("owner_profile_avatar_button"),
                                            contentAlignment = Alignment.Center
                                        ) {
                                            val avatarFile = ownerState.localAvatarPath?.let { File(it) }?.takeIf { it.exists() }
                                            if (avatarFile != null) {
                                                AsyncImage(
                                                    model = avatarFile,
                                                    contentDescription = fullName,
                                                    contentScale = ContentScale.Crop,
                                                    modifier = Modifier
                                                        .fillMaxSize()
                                                        .clip(CircleShape)
                                                )
                                            } else {
                                                Box(
                                                    modifier = Modifier
                                                        .fillMaxSize()
                                                        .background(primaryCrimson.copy(alpha = 0.14f)),
                                                    contentAlignment = Alignment.Center
                                                ) {
                                                    Text(
                                                        text = fullName.take(2).uppercase(),
                                                        color = primaryCrimson,
                                                        fontWeight = FontWeight.Bold,
                                                        fontSize = 30.sp
                                                    )
                                                }
                                            }
                                            if (ownerState.isUploadingAvatar) {
                                                Box(
                                                    modifier = Modifier
                                                        .fillMaxSize()
                                                        .background(Color.Black.copy(alpha = 0.4f)),
                                                    contentAlignment = Alignment.Center
                                                ) {
                                                    CircularProgressIndicator(
                                                        color = Color.White,
                                                        strokeWidth = 2.5.dp,
                                                        modifier = Modifier.size(24.dp)
                                                    )
                                                }
                                            }
                                        }

                                        // Bottom-right circular camera badge
                                        Box(
                                            modifier = Modifier
                                                .align(Alignment.BottomEnd)
                                                .size(48.dp)
                                                .clickable {
                                                    avatarPicker.launch(
                                                        PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)
                                                    )
                                                }
                                                .testTag("owner_profile_avatar_camera_badge"),
                                            contentAlignment = Alignment.BottomEnd
                                        ) {
                                            Box(
                                                modifier = Modifier
                                                    .size(34.dp)
                                                    .shadow(3.dp, CircleShape)
                                                    .clip(CircleShape)
                                                    .background(if (isDarkTheme) Color(0xFF23262E) else Color.White)
                                                    .border(1.dp, cardBorder, CircleShape),
                                                contentAlignment = Alignment.Center
                                            ) {
                                                Image(
                                                    painter = painterResource(id = R.drawable.ic_camera),
                                                    contentDescription = "Change avatar",
                                                    colorFilter = ColorFilter.tint(primaryInk),
                                                    modifier = Modifier.size(16.dp)
                                                )
                                            }
                                        }
                                    }

                                    Spacer(modifier = Modifier.width(8.dp))

                                    // Edit Profile & Settings Outlined Pills
                                    Row(
                                        modifier = Modifier
                                            .weight(1f)
                                            .padding(bottom = 8.dp),
                                        horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End),
                                        verticalAlignment = Alignment.CenterVertically
                                    ) {
                                        OutlinedButton(
                                            onClick = onEditProfile,
                                            shape = RoundedCornerShape(22.dp),
                                            border = androidx.compose.foundation.BorderStroke(1.dp, cardBorder),
                                            colors = ButtonDefaults.outlinedButtonColors(
                                                containerColor = surfaceBg,
                                                contentColor = primaryInk
                                            ),
                                            contentPadding = PaddingValues(horizontal = 12.dp, vertical = 0.dp),
                                            modifier = Modifier
                                                .heightIn(min = 48.dp)
                                                .height(40.dp)
                                                .testTag("owner_profile_edit_button")
                                        ) {
                                            Image(
                                                painter = painterResource(id = R.drawable.ic_edit),
                                                contentDescription = null,
                                                colorFilter = ColorFilter.tint(primaryInk),
                                                modifier = Modifier.size(15.dp)
                                            )
                                            Spacer(modifier = Modifier.width(5.dp))
                                            Text(
                                                text = stringResource(id = R.string.owner_profile_edit_profile),
                                                fontSize = 12.5.sp,
                                                fontWeight = FontWeight.SemiBold,
                                                maxLines = 1
                                            )
                                        }

                                        OutlinedButton(
                                            onClick = { comingSoonReason = "settings" },
                                            shape = RoundedCornerShape(22.dp),
                                            border = androidx.compose.foundation.BorderStroke(1.dp, cardBorder),
                                            colors = ButtonDefaults.outlinedButtonColors(
                                                containerColor = surfaceBg,
                                                contentColor = primaryInk
                                            ),
                                            contentPadding = PaddingValues(horizontal = 12.dp, vertical = 0.dp),
                                            modifier = Modifier
                                                .heightIn(min = 48.dp)
                                                .height(40.dp)
                                                .testTag("owner_profile_settings_button")
                                        ) {
                                            Image(
                                                painter = painterResource(id = R.drawable.ic_settings),
                                                contentDescription = null,
                                                colorFilter = ColorFilter.tint(primaryInk),
                                                modifier = Modifier.size(15.dp)
                                            )
                                            Spacer(modifier = Modifier.width(5.dp))
                                            Text(
                                                text = stringResource(id = R.string.owner_profile_settings),
                                                fontSize = 12.5.sp,
                                                fontWeight = FontWeight.SemiBold,
                                                maxLines = 1
                                            )
                                        }
                                    }
                                }
                            }

                            // 2) Identity, Bio, Stats (Followers/Following + Posts/Views below), Share Profile & Category Pills
                            Column(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .then(if (headerMaxWidth != Dp.Unspecified) Modifier.widthIn(max = headerMaxWidth) else Modifier)
                                    .padding(horizontal = 16.dp)
                            ) {
                                Spacer(modifier = Modifier.height(6.dp))

                                // Full Name — explicitly NO verification badge
                                Text(
                                    text = fullName,
                                    color = primaryInk,
                                    fontSize = 23.sp,
                                    fontWeight = FontWeight.Bold,
                                    maxLines = 2,
                                    overflow = TextOverflow.Ellipsis,
                                    modifier = Modifier.testTag("owner_profile_full_name")
                                )

                                // Clickable @username to copy
                                if (username.isNotBlank()) {
                                    Text(
                                        text = "@$username",
                                        color = secondaryInk,
                                        fontSize = 15.sp,
                                        fontWeight = FontWeight.Medium,
                                        modifier = Modifier
                                            .padding(top = 2.dp)
                                            .clip(RoundedCornerShape(8.dp))
                                            .clickable {
                                                clipboard.setText(AnnotatedString("@$username"))
                                                onShowToast(usernameCopiedMsg)
                                            }
                                            .padding(vertical = 4.dp, horizontal = 2.dp)
                                            .testTag("owner_profile_username_copy")
                                    )
                                }

                                // Bio with opening quote icon matching screenshot
                                if (bio.isNotEmpty()) {
                                    Spacer(modifier = Modifier.height(6.dp))
                                    Row(
                                        verticalAlignment = Alignment.Top,
                                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                                    ) {
                                        Image(
                                            painter = painterResource(id = R.drawable.ic_quote_open),
                                            contentDescription = null,
                                            colorFilter = ColorFilter.tint(primaryInk),
                                            modifier = Modifier
                                                .padding(top = 1.dp)
                                                .size(18.dp)
                                        )
                                        Text(
                                            text = bio,
                                            color = primaryInk,
                                            fontSize = 14.5.sp,
                                            lineHeight = 20.sp,
                                            modifier = Modifier.weight(1f)
                                        )
                                    }
                                }

                                Spacer(modifier = Modifier.height(14.dp))

                                // Followers / Following + Posts / Views below + Share Profile Crimson Pill
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.SpaceBetween
                                ) {
                                    Column(modifier = Modifier.weight(1f)) {
                                        Row(
                                            verticalAlignment = Alignment.CenterVertically
                                        ) {
                                            Column(
                                                modifier = Modifier
                                                    .clip(RoundedCornerShape(8.dp))
                                                    .clickable { onOpenConnections("followers") }
                                                    .padding(horizontal = 4.dp, vertical = 4.dp)
                                                    .testTag("owner_profile_followers_button"),
                                                horizontalAlignment = Alignment.CenterHorizontally
                                            ) {
                                                Text(
                                                    text = FeedFormatter.formatCount(followersCount),
                                                    color = primaryInk,
                                                    fontSize = 18.sp,
                                                    fontWeight = FontWeight.Bold
                                                )
                                                Text(
                                                    text = stringResource(id = R.string.owner_profile_followers),
                                                    color = secondaryInk,
                                                    fontSize = 13.sp
                                                )
                                            }

                                            Box(
                                                modifier = Modifier
                                                    .padding(horizontal = 14.dp)
                                                    .width(1.dp)
                                                    .height(30.dp)
                                                    .background(cardBorder)
                                            )

                                            Column(
                                                modifier = Modifier
                                                    .clip(RoundedCornerShape(8.dp))
                                                    .clickable { onOpenConnections("following") }
                                                    .padding(horizontal = 4.dp, vertical = 4.dp)
                                                    .testTag("owner_profile_following_button"),
                                                horizontalAlignment = Alignment.CenterHorizontally
                                            ) {
                                                Text(
                                                    text = FeedFormatter.formatCount(followingCount),
                                                    color = primaryInk,
                                                    fontSize = 18.sp,
                                                    fontWeight = FontWeight.Bold
                                                )
                                                Text(
                                                    text = stringResource(id = R.string.owner_profile_following),
                                                    color = secondaryInk,
                                                    fontSize = 13.sp
                                                )
                                            }
                                        }

                                        // Posts & Views counts directly below Followers & Following
                                        Row(
                                            modifier = Modifier.padding(top = 6.dp, start = 4.dp),
                                            verticalAlignment = Alignment.CenterVertically,
                                            horizontalArrangement = Arrangement.spacedBy(12.dp)
                                        ) {
                                            Text(
                                                text = "${FeedFormatter.formatCount(postsCount)} ${stringResource(id = R.string.owner_profile_posts)}",
                                                color = secondaryInk,
                                                fontSize = 12.5.sp,
                                                fontWeight = FontWeight.SemiBold,
                                                modifier = Modifier.testTag("owner_profile_posts_count")
                                            )
                                            Text(
                                                text = "${FeedFormatter.formatCount(viewsCount)} ${stringResource(id = R.string.owner_profile_views)}",
                                                color = secondaryInk,
                                                fontSize = 12.5.sp,
                                                fontWeight = FontWeight.SemiBold,
                                                modifier = Modifier.testTag("owner_profile_views_count")
                                            )
                                        }
                                    }

                                    Spacer(modifier = Modifier.width(8.dp))

                                    Button(
                                        onClick = {
                                            val shareLink = "https://telefam.app/@$username"
                                            clipboard.setText(AnnotatedString(shareLink))
                                            onShowToast(linkCopiedMsg)
                                            val sendIntent = Intent(Intent.ACTION_SEND).apply {
                                                type = "text/plain"
                                                putExtra(Intent.EXTRA_TEXT, "$fullName (@$username)\n$shareLink")
                                            }
                                            runCatching {
                                                context.startActivity(Intent.createChooser(sendIntent, null))
                                            }
                                        },
                                        shape = RoundedCornerShape(24.dp),
                                        colors = ButtonDefaults.buttonColors(
                                            containerColor = primaryCrimson,
                                            contentColor = Color.White
                                        ),
                                        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 10.dp),
                                        modifier = Modifier
                                            .height(44.dp)
                                            .testTag("owner_profile_share_button")
                                    ) {
                                        Image(
                                            painter = painterResource(id = R.drawable.ic_share_nodes),
                                            contentDescription = null,
                                            colorFilter = ColorFilter.tint(Color.White),
                                            modifier = Modifier.size(18.dp)
                                        )
                                        Spacer(modifier = Modifier.width(7.dp))
                                        Text(
                                            text = stringResource(id = R.string.owner_profile_share_profile),
                                            fontSize = 14.sp,
                                            fontWeight = FontWeight.SemiBold,
                                            maxLines = 1
                                        )
                                    }
                                }

                                Spacer(modifier = Modifier.height(16.dp))

                                // Category Filter Pills Row: Posts | Reposts | Locked | Saved
                                LazyRow(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                                ) {
                                    items(OwnerProfileTab.entries, key = { it.name }) { tab ->
                                        val selected = activeTab == tab
                                        val labelRes = when (tab) {
                                            OwnerProfileTab.POSTS -> R.string.owner_profile_tab_posts
                                            OwnerProfileTab.REPOSTS -> R.string.owner_profile_tab_reposts
                                            OwnerProfileTab.LOCKED -> R.string.owner_profile_tab_locked
                                            OwnerProfileTab.SAVED -> R.string.owner_profile_tab_saved
                                        }
                                        val iconRes = when (tab) {
                                            OwnerProfileTab.POSTS -> R.drawable.ic_grid_posts
                                            OwnerProfileTab.REPOSTS -> R.drawable.ic_repost
                                            OwnerProfileTab.LOCKED -> R.drawable.ic_lock
                                            OwnerProfileTab.SAVED -> R.drawable.ic_bookmark_outline
                                        }
                                        val chipBg = if (selected) primaryCrimson else {
                                            if (isDarkTheme) Color(0xFF1A1C22) else Color.White
                                        }
                                        val chipTint = if (selected) Color.White else primaryInk
                                        Row(
                                            modifier = Modifier
                                                .height(40.dp)
                                                .clip(RoundedCornerShape(20.dp))
                                                .background(chipBg)
                                                .then(
                                                    if (!selected) Modifier.border(1.dp, cardBorder, RoundedCornerShape(20.dp))
                                                    else Modifier
                                                )
                                                .clickable { onSelectCategory(tab) }
                                                .padding(horizontal = 14.dp)
                                                .testTag("owner_profile_tab_${tab.apiValue}"),
                                            verticalAlignment = Alignment.CenterVertically,
                                            horizontalArrangement = Arrangement.spacedBy(6.dp)
                                        ) {
                                            Image(
                                                painter = painterResource(id = iconRes),
                                                contentDescription = null,
                                                colorFilter = ColorFilter.tint(chipTint),
                                                modifier = Modifier.size(16.dp)
                                            )
                                            Text(
                                                text = stringResource(id = labelRes),
                                                color = chipTint,
                                                fontSize = 13.5.sp,
                                                fontWeight = if (selected) FontWeight.Bold else FontWeight.Medium,
                                                maxLines = 1
                                            )
                                        }
                                    }
                                }

                                Spacer(modifier = Modifier.height(10.dp))
                            }
                        }
                    }

                    // 3) Grid Content or Loading / Empty State
                    if (ownerState.isLoadingItems && gridItems.isEmpty()) {
                        item(span = { GridItemSpan(gridColumns) }, key = "owner_loading") {
                            Box(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .height(180.dp),
                                contentAlignment = Alignment.Center
                            ) {
                                CircularProgressIndicator(color = primaryCrimson)
                            }
                        }
                    } else if (gridItems.isEmpty()) {
                        item(span = { GridItemSpan(gridColumns) }, key = "owner_empty") {
                            val emptyRes = when (activeTab) {
                                OwnerProfileTab.POSTS -> R.string.owner_profile_empty_posts
                                OwnerProfileTab.REPOSTS -> R.string.owner_profile_empty_reposts
                                OwnerProfileTab.LOCKED -> R.string.owner_profile_empty_locked
                                OwnerProfileTab.SAVED -> R.string.owner_profile_empty_saved
                            }
                            Box(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .height(170.dp)
                                    .padding(horizontal = 24.dp),
                                contentAlignment = Alignment.Center
                            ) {
                                Text(
                                    text = stringResource(id = emptyRes),
                                    color = secondaryInk,
                                    fontSize = 14.sp,
                                    textAlign = TextAlign.Center
                                )
                            }
                        }
                    } else {
                        items(
                            items = gridItems,
                            key = { "${activeTab.apiValue}_${it.itemId}_${it.videoId}" }
                        ) { item ->
                            OwnerProfileMediaTile(
                                item = item,
                                isDarkTheme = isDarkTheme,
                                onClick = { onOpenItem(item) }
                            )
                        }
                    }
                }
            }
        }

        // Smooth sticky crimson bar on scroll-down so user keeps name & menu accessible cleanly
        AnimatedVisibility(
            visible = collapseFraction > 0.72f,
            enter = fadeIn(animationSpec = tween(180)),
            exit = fadeOut(animationSpec = tween(150)),
            modifier = Modifier.align(Alignment.TopCenter)
        ) {
            Surface(
                color = primaryCrimson,
                shadowElevation = 4.dp,
                modifier = Modifier.fillMaxWidth()
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .windowInsetsPadding(WindowInsets.statusBars)
                        .height(54.dp)
                        .padding(horizontal = 16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text(
                        text = fullName,
                        color = Color.White,
                        fontSize = 17.sp,
                        fontWeight = FontWeight.Bold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f)
                    )
                    IconButton(
                        onClick = { comingSoonReason = "menu" },
                        modifier = Modifier.size(48.dp)
                    ) {
                        Image(
                            painter = painterResource(id = R.drawable.ic_menu_dashes),
                            contentDescription = "Menu",
                            modifier = Modifier.size(22.dp)
                        )
                    }
                }
            }
        }
    }

    // Crop dialog when owner picks a new avatar from camera badge
    pendingCropBitmap?.let { rawBmp ->
        ProfilePhotoCropDialog(
            source = rawBmp,
            onDismiss = { pendingCropBitmap = null },
            onApply = { cropped ->
                pendingCropBitmap = null
                onAvatarCropped(cropped)
            }
        )
    }

    // Coming Soon dialog for Settings and 3-dash Menu
    comingSoonReason?.let { reason ->
        val bodyRes = if (reason == "settings") {
            R.string.owner_profile_settings_coming_soon
        } else {
            R.string.owner_profile_menu_coming_soon
        }
        AlertDialog(
            onDismissRequest = { comingSoonReason = null },
            title = {
                Text(
                    text = stringResource(id = R.string.owner_profile_coming_soon_title),
                    fontWeight = FontWeight.Bold
                )
            },
            text = { Text(stringResource(id = bodyRes)) },
            confirmButton = {
                TextButton(onClick = { comingSoonReason = null }) {
                    Text(stringResource(id = R.string.post_done), color = primaryCrimson)
                }
            }
        )
    }

    // Background Photos Manager Sheet (up to 5 photos, add or delete)
    if (showBackgroundManager) {
        val bgs = profile?.backgroundPhotos.orEmpty()
        ModalBottomSheet(
            onDismissRequest = { showBackgroundManager = false },
            sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp, vertical = 12.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text(
                        text = stringResource(id = R.string.owner_profile_bg_manager_title, bgs.size),
                        fontSize = 18.sp,
                        fontWeight = FontWeight.Bold,
                        color = primaryInk
                    )
                    Button(
                        onClick = {
                            if (bgs.size >= 5) {
                                onShowToast(context.getString(R.string.owner_profile_bg_max_error))
                            } else {
                                backgroundPicker.launch(
                                    PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)
                                )
                            }
                        },
                        enabled = bgs.size < 5 && !ownerState.isUploadingBackgrounds,
                        colors = ButtonDefaults.buttonColors(containerColor = primaryCrimson)
                    ) {
                        Text(stringResource(id = R.string.owner_profile_bg_add), color = Color.White)
                    }
                }

                if (bgs.isEmpty()) {
                    Text(
                        text = stringResource(id = R.string.owner_profile_bg_empty),
                        color = secondaryInk,
                        modifier = Modifier.padding(vertical = 18.dp)
                    )
                } else {
                    LazyRow(
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        items(bgs.size, key = { idx -> bgs[idx].id }) { idx ->
                            val bg = bgs[idx]
                            val localFile = ownerState.localBackgroundPaths.getOrNull(idx)?.let { File(it) }?.takeIf { it.exists() }
                            Box(
                                modifier = Modifier
                                    .width(150.dp)
                                    .height(100.dp)
                                    .clip(RoundedCornerShape(12.dp))
                                    .background(Color(0xFF1F232B))
                            ) {
                                if (localFile != null) {
                                    AsyncImage(
                                        model = localFile,
                                        contentDescription = null,
                                        contentScale = ContentScale.Crop,
                                        modifier = Modifier.fillMaxSize()
                                    )
                                }
                                IconButton(
                                    onClick = { onDeleteBackgroundPhoto(bg.id) },
                                    modifier = Modifier
                                        .align(Alignment.TopEnd)
                                        .size(38.dp)
                                ) {
                                    Box(
                                        modifier = Modifier
                                            .size(28.dp)
                                            .clip(CircleShape)
                                            .background(Color.Black.copy(alpha = 0.68f)),
                                        contentAlignment = Alignment.Center
                                    ) {
                                        Image(
                                            painter = painterResource(id = R.drawable.ic_delete),
                                            contentDescription = "Delete background photo",
                                            colorFilter = ColorFilter.tint(Color.White),
                                            modifier = Modifier.size(15.dp)
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
                Spacer(modifier = Modifier.height(12.dp))
            }
        }
    }

    // Followers / Following Sheet
    ownerState.connectionsSheetMode?.let { mode ->
        ModalBottomSheet(
            onDismissRequest = onCloseConnections,
            sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = 240.dp, max = 520.dp)
                    .padding(horizontal = 18.dp, vertical = 10.dp)
            ) {
                Text(
                    text = if (mode == "followers") stringResource(id = R.string.owner_profile_followers)
                    else stringResource(id = R.string.owner_profile_following),
                    fontSize = 18.sp,
                    fontWeight = FontWeight.Bold,
                    color = primaryInk
                )
                Spacer(modifier = Modifier.height(10.dp))
                HorizontalDivider(color = cardBorder)
                if (ownerState.isLoadingConnections) {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(180.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        CircularProgressIndicator(color = primaryCrimson)
                    }
                } else if (ownerState.connectionsUsers.isEmpty()) {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(150.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(
                            text = stringResource(id = R.string.contacts_empty),
                            color = secondaryInk
                        )
                    }
                } else {
                    LazyColumn(
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                        contentPadding = PaddingValues(vertical = 10.dp)
                    ) {
                        items(ownerState.connectionsUsers, key = { it.userId }) { user ->
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clip(RoundedCornerShape(12.dp))
                                    .clickable {
                                        onCloseConnections()
                                        onOpenUserProfile(user.userId)
                                    }
                                    .padding(vertical = 6.dp, horizontal = 4.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(12.dp)
                            ) {
                                Box(
                                    modifier = Modifier
                                        .size(44.dp)
                                        .clip(CircleShape)
                                        .background(primaryCrimson.copy(alpha = 0.14f)),
                                    contentAlignment = Alignment.Center
                                ) {
                                    Text(
                                        text = user.fullName.ifBlank { user.username }.take(2).uppercase(),
                                        color = primaryCrimson,
                                        fontWeight = FontWeight.Bold
                                    )
                                }
                                Column(modifier = Modifier.weight(1f)) {
                                    Text(
                                        text = user.fullName.ifBlank { user.username },
                                        color = primaryInk,
                                        fontWeight = FontWeight.SemiBold,
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis
                                    )
                                    Text(
                                        text = "@${user.username}",
                                        color = secondaryInk,
                                        fontSize = 12.5.sp
                                    )
                                }
                                val btnLabel = when (user.relationship) {
                                    "friends" -> stringResource(id = R.string.action_friends)
                                    "following" -> stringResource(id = R.string.action_following)
                                    "follow_back" -> stringResource(id = R.string.action_follow_back)
                                    else -> stringResource(id = R.string.action_follow)
                                }
                                if (user.isFollowing) {
                                    OutlinedButton(
                                        onClick = { onToggleConnectionFollow(user) },
                                        shape = RoundedCornerShape(20.dp),
                                        contentPadding = PaddingValues(horizontal = 14.dp, vertical = 6.dp)
                                    ) {
                                        Text(btnLabel, fontSize = 12.5.sp)
                                    }
                                } else {
                                    Button(
                                        onClick = { onToggleConnectionFollow(user) },
                                        shape = RoundedCornerShape(20.dp),
                                        colors = ButtonDefaults.buttonColors(containerColor = primaryCrimson),
                                        contentPadding = PaddingValues(horizontal = 14.dp, vertical = 6.dp)
                                    ) {
                                        Text(btnLabel, color = Color.White, fontSize = 12.5.sp)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Photo / Text Post Viewer Dialog
    ownerState.activeViewerItem?.let { item ->
        OwnerPostDetailDialog(
            item = item,
            onDismiss = onCloseItemViewer,
            onToggleLike = { onTogglePostLike(item) },
            onToggleSave = { onTogglePostSave(item) },
            onToggleLock = { onTogglePostLock(item) }
        )
    }
}

@Composable
private fun OwnerProfileMediaTile(
    item: OwnerProfileItemDto,
    isDarkTheme: Boolean,
    onClick: () -> Unit
) {
    val thumbUrl = remember(item.thumbnailUrl) {
        if (item.thumbnailUrl.isBlank()) ""
        else com.telefam.company.app.network.TelefamNetworkClient.resolveMediaUrl(item.thumbnailUrl)
    }
    val parsedCardBg = remember(item.bgColorHex) {
        runCatching {
            if (item.bgColorHex.startsWith("#") && item.bgColorHex.length >= 7) {
                Color(android.graphics.Color.parseColor(item.bgColorHex))
            } else null
        }.getOrNull()
    }

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .aspectRatio(0.95f)
            .clip(RoundedCornerShape(10.dp))
            .background(
                parsedCardBg ?: if (isDarkTheme) Color(0xFF1C1F26) else Color(0xFFE5E7EB)
            )
            .clickable(onClick = onClick)
            .testTag("owner_grid_item_${item.itemId}")
    ) {
        if (item.mediaType == "text") {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(
                        parsedCardBg ?: Color(0xFFC81010)
                    )
                    .padding(10.dp),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = item.body.ifBlank { "Post" },
                    color = Color.White,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold,
                    textAlign = TextAlign.Center,
                    maxLines = 4,
                    overflow = TextOverflow.Ellipsis
                )
            }
        } else if (thumbUrl.isNotBlank()) {
            AsyncImage(
                model = thumbUrl,
                contentDescription = item.body.ifBlank { item.mediaType },
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize()
            )
        }

        // Top-right media badge (Play icon for video, Photos icon for photos)
        val badgeIcon = when (item.mediaType) {
            "video" -> R.drawable.ic_play_arrow
            "photos" -> R.drawable.ic_photos_tab
            else -> null
        }
        if (badgeIcon != null) {
            Image(
                painter = painterResource(id = badgeIcon),
                contentDescription = null,
                colorFilter = ColorFilter.tint(Color.White),
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(7.dp)
                    .size(18.dp)
            )
        } else {
            Text(
                text = "Aa",
                color = Color.White,
                fontSize = 11.sp,
                fontWeight = FontWeight.Bold,
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(7.dp)
            )
        }

        // Bottom-left subtle gradient + heart + likes count
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(34.dp)
                .align(Alignment.BottomCenter)
                .background(
                    Brush.verticalGradient(
                        colors = listOf(Color.Transparent, Color.Black.copy(alpha = 0.56f))
                    )
                )
        )
        Row(
            modifier = Modifier
                .align(Alignment.BottomStart)
                .padding(horizontal = 7.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Image(
                painter = painterResource(id = R.drawable.ic_heart_filled),
                contentDescription = null,
                colorFilter = ColorFilter.tint(Color.White),
                modifier = Modifier.size(13.dp)
            )
            Text(
                text = FeedFormatter.formatCount(item.likesCount),
                color = Color.White,
                fontSize = 11.5.sp,
                fontWeight = FontWeight.SemiBold
            )
        }
    }
}

@Composable
private fun OwnerPostDetailDialog(
    item: OwnerProfileItemDto,
    onDismiss: () -> Unit,
    onToggleLike: () -> Unit,
    onToggleSave: () -> Unit,
    onToggleLock: () -> Unit
) {
    val parsedBg = remember(item.bgColorHex) {
        runCatching {
            if (item.bgColorHex.startsWith("#") && item.bgColorHex.length >= 7) {
                Color(android.graphics.Color.parseColor(item.bgColorHex))
            } else null
        }.getOrNull()
    }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = null,
        text = {
            Column(
                modifier = Modifier.fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                if (item.mediaType == "photos" && item.photoUrls.isNotEmpty()) {
                    LazyRow(
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        items(item.photoUrls) { rawUrl ->
                            val resolved = com.telefam.company.app.network.TelefamNetworkClient.resolveMediaUrl(rawUrl)
                            AsyncImage(
                                model = resolved,
                                contentDescription = item.body,
                                contentScale = ContentScale.Crop,
                                modifier = Modifier
                                    .size(220.dp)
                                    .clip(RoundedCornerShape(12.dp))
                            )
                        }
                    }
                } else if (item.mediaType == "text") {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(180.dp)
                            .clip(RoundedCornerShape(14.dp))
                            .background(parsedBg ?: MaterialTheme.colorScheme.primary)
                            .padding(16.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(
                            text = item.body,
                            color = Color.White,
                            fontSize = 18.sp,
                            fontWeight = FontWeight.Bold,
                            textAlign = TextAlign.Center
                        )
                    }
                }
                if (item.body.isNotBlank() && item.mediaType != "text") {
                    Text(text = item.body, fontSize = 14.sp)
                }
                if (item.songTitle.isNotBlank()) {
                    Text(
                        text = "${item.songTitle} • ${item.songArtist}",
                        fontSize = 12.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    TextButton(onClick = onToggleLike) {
                        Text(
                            text = "${if (item.isLiked) "Liked" else "Like"} (${FeedFormatter.formatCount(item.likesCount)})",
                            color = if (item.isLiked) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface
                        )
                    }
                    TextButton(onClick = onToggleSave) {
                        Text(if (item.isSaved) "Saved" else "Save")
                    }
                }
                TextButton(onClick = onToggleLock) {
                    Text(
                        text = stringResource(
                            id = if (item.visibility == "private") R.string.owner_profile_unlock_post
                            else R.string.owner_profile_lock_post
                        ),
                        color = MaterialTheme.colorScheme.primary
                    )
                }
            }
        },
        confirmButton = {
            TextButton(onClick = onDismiss) {
                Text(stringResource(id = R.string.post_done))
            }
        }
    )
}
