package com.telefam.company.app.ui.screens

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBars
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
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
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
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalClipboardManager
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
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import coil.compose.AsyncImage
import com.telefam.company.app.R
import com.telefam.company.app.data.ContactModel
import com.telefam.company.app.feed.FeedFormatter
import com.telefam.company.app.network.OwnerProfileItemDto
import com.telefam.company.app.network.TelefamNetworkClient
import com.telefam.company.app.ui.OtherProfileInstanceState
import com.telefam.company.app.ui.OtherProfileTab
import com.telefam.company.app.ui.UserReportCategory
import com.telefam.company.app.ui.UserReportSheetState
import com.telefam.company.app.ui.components.swipeBackEdge
import kotlinx.coroutines.delay
import java.io.File

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun OtherProfileScreen(
    isDarkTheme: Boolean,
    instance: OtherProfileInstanceState,
    reportSheet: UserReportSheetState,
    toastMessage: String?,
    onBack: () -> Unit,
    onPullRefresh: () -> Unit,
    onToggleFollow: () -> Unit,
    onSelectCategory: (OtherProfileTab) -> Unit,
    onOpenConnections: (String) -> Unit,
    onCloseConnections: () -> Unit,
    onToggleConnectionFollow: (ContactModel) -> Unit,
    onOpenUserProfile: (String) -> Unit,
    onSetNickname: (String) -> Unit,
    onToggleBlock: () -> Unit,
    onToggleMute: () -> Unit,
    onOpenReport: () -> Unit,
    onSelectReportCategory: (UserReportCategory) -> Unit,
    onSelectReportSubReason: (String) -> Unit,
    onUpdateReportDetails: (String) -> Unit,
    onBackReportStep: () -> Unit,
    onSubmitReport: () -> Unit,
    onCloseReportSheet: () -> Unit,
    onOpenItem: (OwnerProfileItemDto) -> Unit,
    onCloseItemViewer: () -> Unit,
    onTogglePostLike: (OwnerProfileItemDto) -> Unit,
    onTogglePostSave: (OwnerProfileItemDto) -> Unit,
    onShowToast: (String) -> Unit,
    onClearToast: () -> Unit
) {
    BackHandler(onBack = onBack)

    val clipboard = LocalClipboardManager.current
    val gridState = rememberLazyGridState()
    val snackbarHostState = remember { SnackbarHostState() }

    var comingSoonReason by remember { mutableStateOf<String?>(null) }
    var showOptionsMenu by remember { mutableStateOf(false) }
    var showNicknameDialog by remember { mutableStateOf(false) }
    var showBlockConfirmDialog by remember { mutableStateOf(false) }
    var showAvatarLightbox by remember { mutableStateOf(false) }
    var activeBgIndex by remember(instance.userId) { mutableIntStateOf(0) }

    LaunchedEffect(toastMessage) {
        if (!toastMessage.isNullOrBlank()) {
            snackbarHostState.currentSnackbarData?.dismiss()
            snackbarHostState.showSnackbar(toastMessage)
            onClearToast()
        }
    }

    val profile = instance.profile
    val coverModels: List<Any> = remember(instance.localBackgroundPaths, profile?.backgroundPhotos, instance.userId) {
        if (instance.localBackgroundPaths.isNotEmpty()) {
            instance.localBackgroundPaths.map { File(it) }
        } else {
            profile?.backgroundPhotos.orEmpty()
                .mapNotNull { bg ->
                    val resolved = TelefamNetworkClient.resolveMediaUrl(bg.url)
                    resolved.takeIf { it.isNotBlank() }
                }
        }
    }

    LaunchedEffect(coverModels.size, instance.userId) {
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

    val rawFullName = profile?.fullName?.takeIf { it.isNotBlank() } ?: "Telefam User"
    val nickname = profile?.nickname.orEmpty().trim()
    val displayName = nickname.ifBlank { rawFullName }
    val username = profile?.username.orEmpty().trim()
    val bio = profile?.bio.orEmpty().trim()
    val followersCount = profile?.followersCount ?: 0L
    val followingCount = profile?.followingCount ?: 0L
    val subscribersCount = profile?.subscribersCount ?: 0L
    val isBlocked = profile?.isBlocked == true
    val isBlockedBy = profile?.isBlockedBy == true

    val activeTab = instance.activeCategory
    val gridItems = instance.itemsByCategory[activeTab].orEmpty()

    val surfaceBg = MaterialTheme.colorScheme.background
    val primaryCrimson = MaterialTheme.colorScheme.primary
    val secondaryInk = MaterialTheme.colorScheme.onSurfaceVariant
    val primaryInk = MaterialTheme.colorScheme.onBackground
    val cardBorder = MaterialTheme.colorScheme.outlineVariant
    val usernameCopiedMsg = stringResource(id = R.string.owner_profile_username_copied)
    val linkCopiedMsg = stringResource(id = R.string.owner_profile_link_copied)

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(surfaceBg)
            .windowInsetsPadding(WindowInsets.navigationBars)
            .swipeBackEdge { onBack() }
            .testTag("other_profile_screen")
    ) {
        BoxWithConstraints(modifier = Modifier.fillMaxSize()) {
            val isWide = maxWidth >= 680.dp
            val gridColumns = if (maxWidth >= 960.dp) 5 else if (isWide) 4 else 3
            val headerMaxWidth = if (isWide) 840.dp else Dp.Unspecified

            PullToRefreshBox(
                isRefreshing = instance.isRefreshing,
                onRefresh = onPullRefresh,
                modifier = Modifier.fillMaxSize()
            ) {
                LazyVerticalGrid(
                    columns = GridCells.Fixed(gridColumns),
                    state = gridState,
                    modifier = Modifier
                        .fillMaxSize()
                        .testTag("other_profile_grid"),
                    contentPadding = PaddingValues(bottom = 24.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    item(span = { GridItemSpan(gridColumns) }, key = "other_header") {
                        Column(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalAlignment = Alignment.CenterHorizontally
                        ) {
                            // 1) Top Full-Bleed Slideshow Cover + Back/More Translucent Buttons + Arched Seam + Overlapping Avatar & Name/@username
                            Box(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .then(if (headerMaxWidth != Dp.Unspecified) Modifier.widthIn(max = headerMaxWidth) else Modifier)
                            ) {
                                val baseCoverHeight = if (isWide) 248.dp else 224.dp
                                Box(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .height(baseCoverHeight)
                                        .graphicsLayer {
                                            translationY = -scrollPx * 0.25f
                                            alpha = (1f - collapseFraction * 0.35f).coerceIn(0.6f, 1f)
                                        }
                                ) {
                                    if (coverModels.isNotEmpty() && !isBlocked && !isBlockedBy) {
                                        Crossfade(
                                            targetState = activeBgIndex % coverModels.size,
                                            animationSpec = tween(durationMillis = 850),
                                            label = "other_cover_crossfade"
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

                                    // Top subtle dark scrim for legibility of status bar & top circular buttons
                                    Box(
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .height(92.dp)
                                            .align(Alignment.TopCenter)
                                            .background(
                                                Brush.verticalGradient(
                                                    colors = listOf(
                                                        Color.Black.copy(alpha = 0.42f),
                                                        Color.Transparent
                                                    )
                                                )
                                            )
                                    )

                                    // Top-left circular translucent Back button (48dp touch target)
                                    IconButton(
                                        onClick = onBack,
                                        modifier = Modifier
                                            .align(Alignment.TopStart)
                                            .windowInsetsPadding(WindowInsets.statusBars)
                                            .padding(start = 10.dp, top = 4.dp)
                                            .size(48.dp)
                                            .testTag("other_profile_back_button")
                                    ) {
                                        Box(
                                            modifier = Modifier
                                                .size(38.dp)
                                                .clip(CircleShape)
                                                .background(Color.Black.copy(alpha = 0.54f)),
                                            contentAlignment = Alignment.Center
                                        ) {
                                            Image(
                                                painter = painterResource(id = R.drawable.ic_back),
                                                contentDescription = stringResource(id = R.string.other_profile_back),
                                                colorFilter = ColorFilter.tint(Color.White),
                                                modifier = Modifier.size(20.dp)
                                            )
                                        }
                                    }

                                    // Top-right circular translucent 3-dots Options button (48dp touch target)
                                    IconButton(
                                        onClick = { showOptionsMenu = true },
                                        modifier = Modifier
                                            .align(Alignment.TopEnd)
                                            .windowInsetsPadding(WindowInsets.statusBars)
                                            .padding(end = 10.dp, top = 4.dp)
                                            .size(48.dp)
                                            .testTag("other_profile_more_button")
                                    ) {
                                        Box(
                                            modifier = Modifier
                                                .size(38.dp)
                                                .clip(CircleShape)
                                                .background(Color.Black.copy(alpha = 0.54f)),
                                            contentAlignment = Alignment.Center
                                        ) {
                                            Image(
                                                painter = painterResource(id = R.drawable.ic_more_vert),
                                                contentDescription = stringResource(id = R.string.other_profile_options),
                                                colorFilter = ColorFilter.tint(Color.White),
                                                modifier = Modifier.size(20.dp)
                                            )
                                        }
                                    }

                                    // Arched white/surface bottom seam matching reference screenshot
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
                                }

                                // Row straddling bottom of cover: Overlapping Avatar on Left + Display Name & @username on Right
                                Row(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(top = baseCoverHeight - 64.dp, start = 16.dp, end = 16.dp),
                                    verticalAlignment = Alignment.Bottom
                                ) {
                                    val avatarScale = 1f - collapseFraction * 0.16f
                                    val avatarModel: Any? = remember(
                                        instance.localAvatarPath,
                                        profile?.avatarUrl,
                                        profile?.avatarFingerprintHash
                                    ) {
                                        val file = instance.localAvatarPath?.let { File(it) }?.takeIf { it.exists() }
                                        file ?: profile?.avatarUrl?.takeIf { it.isNotBlank() }?.let {
                                            TelefamNetworkClient.resolveMediaUrl(it)
                                        }
                                    }

                                    Box(
                                        modifier = Modifier
                                            .size(112.dp)
                                            .graphicsLayer {
                                                scaleX = avatarScale
                                                scaleY = avatarScale
                                            }
                                            .shadow(6.dp, CircleShape)
                                            .clip(CircleShape)
                                            .background(surfaceBg)
                                            .border(4.dp, surfaceBg, CircleShape)
                                            .clickable { showAvatarLightbox = true }
                                            .testTag("other_profile_avatar_button"),
                                        contentAlignment = Alignment.Center
                                    ) {
                                        if (avatarModel != null) {
                                            AsyncImage(
                                                model = avatarModel,
                                                contentDescription = displayName,
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
                                                    text = displayName.take(2).uppercase(),
                                                    color = primaryCrimson,
                                                    fontWeight = FontWeight.Bold,
                                                    fontSize = 32.sp
                                                )
                                            }
                                        }
                                    }

                                    Spacer(modifier = Modifier.width(14.dp))

                                    Column(
                                        modifier = Modifier
                                            .weight(1f)
                                            .padding(bottom = 8.dp)
                                    ) {
                                        Text(
                                            text = displayName,
                                            color = primaryInk,
                                            fontSize = 23.sp,
                                            fontWeight = FontWeight.Bold,
                                            maxLines = 2,
                                            overflow = TextOverflow.Ellipsis,
                                            modifier = Modifier.testTag("other_profile_display_name")
                                        )
                                        if (username.isNotBlank()) {
                                            Text(
                                                text = "@$username",
                                                color = secondaryInk,
                                                fontSize = 15.sp,
                                                fontWeight = FontWeight.Medium,
                                                maxLines = 1,
                                                overflow = TextOverflow.Ellipsis,
                                                modifier = Modifier
                                                    .padding(top = 2.dp)
                                                    .clip(RoundedCornerShape(8.dp))
                                                    .clickable {
                                                        clipboard.setText(AnnotatedString("@$username"))
                                                        onShowToast(usernameCopiedMsg)
                                                    }
                                                    .padding(vertical = 3.dp, horizontal = 2.dp)
                                                    .testTag("other_profile_username_copy")
                                            )
                                        }
                                    }
                                }
                            }

                            // 2) Bio, 3-Stat Row (Followers | Following | Subscribers), 3 Action Pills, 2 Category Pills
                            Column(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .then(if (headerMaxWidth != Dp.Unspecified) Modifier.widthIn(max = headerMaxWidth) else Modifier)
                                    .padding(horizontal = 16.dp)
                            ) {
                                if (bio.isNotEmpty() && !isBlocked && !isBlockedBy) {
                                    Spacer(modifier = Modifier.height(10.dp))
                                    Text(
                                        text = bio,
                                        color = primaryInk,
                                        fontSize = 14.5.sp,
                                        lineHeight = 20.sp,
                                        textAlign = TextAlign.Center,
                                        modifier = Modifier.fillMaxWidth()
                                    )
                                }

                                Spacer(modifier = Modifier.height(16.dp))

                                // Followers | Following | Subscribers row
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.SpaceEvenly
                                ) {
                                    StatCounterColumn(
                                        countText = FeedFormatter.formatCount(followersCount),
                                        label = stringResource(id = R.string.owner_profile_followers),
                                        primaryInk = primaryInk,
                                        secondaryInk = secondaryInk,
                                        enabled = !isBlocked && !isBlockedBy,
                                        testTag = "other_profile_followers_button",
                                        onClick = { onOpenConnections("followers") }
                                    )
                                    Box(
                                        modifier = Modifier
                                            .width(1.dp)
                                            .height(30.dp)
                                            .background(cardBorder)
                                    )
                                    StatCounterColumn(
                                        countText = FeedFormatter.formatCount(followingCount),
                                        label = stringResource(id = R.string.owner_profile_following),
                                        primaryInk = primaryInk,
                                        secondaryInk = secondaryInk,
                                        enabled = !isBlocked && !isBlockedBy,
                                        testTag = "other_profile_following_button",
                                        onClick = { onOpenConnections("following") }
                                    )
                                    Box(
                                        modifier = Modifier
                                            .width(1.dp)
                                            .height(30.dp)
                                            .background(cardBorder)
                                    )
                                    StatCounterColumn(
                                        countText = FeedFormatter.formatCount(subscribersCount),
                                        label = stringResource(id = R.string.other_profile_subscribers),
                                        primaryInk = primaryInk,
                                        secondaryInk = secondaryInk,
                                        enabled = false,
                                        testTag = "other_profile_subscribers_stat",
                                        onClick = {}
                                    )
                                }

                                Spacer(modifier = Modifier.height(16.dp))

                                // 3 Action Pills: Follow | Message (Coming Soon) | Subscribe (Coming Soon)
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    // 1. Follow Pill
                                    if (isBlocked) {
                                        Button(
                                            onClick = onToggleBlock,
                                            shape = RoundedCornerShape(24.dp),
                                            colors = ButtonDefaults.buttonColors(
                                                containerColor = primaryCrimson,
                                                contentColor = Color.White
                                            ),
                                            contentPadding = PaddingValues(horizontal = 10.dp, vertical = 0.dp),
                                            modifier = Modifier
                                                .weight(1f)
                                                .height(48.dp)
                                                .testTag("other_profile_unblock_pill")
                                        ) {
                                            Text(
                                                text = stringResource(id = R.string.other_profile_unblock),
                                                fontSize = 13.5.sp,
                                                fontWeight = FontWeight.SemiBold,
                                                maxLines = 1
                                            )
                                        }
                                    } else {
                                        OtherFollowButton(
                                            relationship = profile?.relationship ?: "follow",
                                            isDarkTheme = isDarkTheme,
                                            primaryCrimson = primaryCrimson,
                                            cardBorder = cardBorder,
                                            surfaceBg = surfaceBg,
                                            enabled = !isBlockedBy,
                                            onClick = onToggleFollow,
                                            modifier = Modifier.weight(1f)
                                        )
                                    }

                                    // 2. Message Pill (Outlined, Coming Soon)
                                    OutlinedButton(
                                        onClick = { comingSoonReason = "message" },
                                        shape = RoundedCornerShape(24.dp),
                                        border = BorderStroke(1.dp, cardBorder),
                                        colors = ButtonDefaults.outlinedButtonColors(
                                            containerColor = surfaceBg,
                                            contentColor = primaryInk
                                        ),
                                        contentPadding = PaddingValues(horizontal = 10.dp, vertical = 0.dp),
                                        modifier = Modifier
                                            .weight(1f)
                                            .height(48.dp)
                                            .testTag("other_profile_message_button")
                                    ) {
                                        Image(
                                            painter = painterResource(id = R.drawable.ic_message_dots),
                                            contentDescription = null,
                                            colorFilter = ColorFilter.tint(primaryInk),
                                            modifier = Modifier.size(16.dp)
                                        )
                                        Spacer(modifier = Modifier.width(6.dp))
                                        Text(
                                            text = stringResource(id = R.string.other_profile_message),
                                            fontSize = 13.5.sp,
                                            fontWeight = FontWeight.SemiBold,
                                            maxLines = 1
                                        )
                                    }

                                    // 3. Subscribe Pill (Solid Crimson with Crown, Coming Soon)
                                    Button(
                                        onClick = { comingSoonReason = "subscribe" },
                                        shape = RoundedCornerShape(24.dp),
                                        colors = ButtonDefaults.buttonColors(
                                            containerColor = primaryCrimson,
                                            contentColor = Color.White
                                        ),
                                        contentPadding = PaddingValues(horizontal = 10.dp, vertical = 0.dp),
                                        modifier = Modifier
                                            .weight(1f)
                                            .height(48.dp)
                                            .testTag("other_profile_subscribe_button")
                                    ) {
                                        Image(
                                            painter = painterResource(id = R.drawable.ic_crown),
                                            contentDescription = null,
                                            colorFilter = ColorFilter.tint(Color.White),
                                            modifier = Modifier.size(16.dp)
                                        )
                                        Spacer(modifier = Modifier.width(6.dp))
                                        Text(
                                            text = stringResource(id = R.string.other_profile_subscribe),
                                            fontSize = 13.5.sp,
                                            fontWeight = FontWeight.SemiBold,
                                            maxLines = 1
                                        )
                                    }
                                }

                                Spacer(modifier = Modifier.height(16.dp))

                                // 2 Category Filter Pills Row: Posts | Reposts with active crimson underline bar
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                                    verticalAlignment = Alignment.Top
                                ) {
                                    OtherProfileTab.entries.forEach { tab ->
                                        val selected = activeTab == tab
                                        val labelRes = if (tab == OtherProfileTab.POSTS) {
                                            R.string.owner_profile_tab_posts
                                        } else {
                                            R.string.owner_profile_tab_reposts
                                        }
                                        val iconRes = if (tab == OtherProfileTab.POSTS) {
                                            R.drawable.ic_grid_posts
                                        } else {
                                            R.drawable.ic_repost
                                        }
                                        val chipBg = if (selected) primaryCrimson else {
                                            if (isDarkTheme) Color(0xFF1A1C22) else Color.White
                                        }
                                        val chipTint = if (selected) Color.White else primaryInk

                                        Column(
                                            horizontalAlignment = Alignment.CenterHorizontally
                                        ) {
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
                                                    .padding(horizontal = 18.dp)
                                                    .testTag("other_profile_tab_${tab.apiValue}"),
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
                                            Spacer(modifier = Modifier.height(6.dp))
                                            Box(
                                                modifier = Modifier
                                                    .width(64.dp)
                                                    .height(2.5.dp)
                                                    .clip(RoundedCornerShape(2.dp))
                                                    .background(if (selected) primaryCrimson else Color.Transparent)
                                            )
                                        }
                                    }
                                }

                                Spacer(modifier = Modifier.height(8.dp))
                            }
                        }
                    }

                    // 3) Grid Content / Blocked Notice / Loading / Empty State
                    when {
                        isBlocked -> {
                            item(span = { GridItemSpan(gridColumns) }, key = "other_blocked") {
                                Box(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .height(180.dp)
                                        .padding(horizontal = 28.dp),
                                    contentAlignment = Alignment.Center
                                ) {
                                    Text(
                                        text = stringResource(id = R.string.other_profile_blocked_notice),
                                        color = secondaryInk,
                                        fontSize = 14.sp,
                                        textAlign = TextAlign.Center
                                    )
                                }
                            }
                        }
                        isBlockedBy -> {
                            item(span = { GridItemSpan(gridColumns) }, key = "other_blocked_by") {
                                Box(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .height(180.dp)
                                        .padding(horizontal = 28.dp),
                                    contentAlignment = Alignment.Center
                                ) {
                                    Text(
                                        text = stringResource(id = R.string.other_profile_blocked_by_notice),
                                        color = secondaryInk,
                                        fontSize = 14.sp,
                                        textAlign = TextAlign.Center
                                    )
                                }
                            }
                        }
                        (instance.isLoadingProfile || instance.isLoadingItems) && gridItems.isEmpty() -> {
                            item(span = { GridItemSpan(gridColumns) }, key = "other_loading") {
                                Box(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .height(180.dp),
                                    contentAlignment = Alignment.Center
                                ) {
                                    CircularProgressIndicator(color = primaryCrimson)
                                }
                            }
                        }
                        gridItems.isEmpty() -> {
                            item(span = { GridItemSpan(gridColumns) }, key = "other_empty") {
                                val emptyRes = if (activeTab == OtherProfileTab.POSTS) {
                                    R.string.owner_profile_empty_posts
                                } else {
                                    R.string.owner_profile_empty_reposts
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
                        }
                        else -> {
                            items(
                                items = gridItems,
                                key = { "${activeTab.apiValue}_${it.itemId}_${it.videoId}" }
                            ) { item ->
                                OtherProfileMediaTile(
                                    item = item,
                                    isDarkTheme = isDarkTheme,
                                    onClick = { onOpenItem(item) }
                                )
                            }
                        }
                    }
                }
            }
        }

        // Smooth sticky compact top bar on scroll-down
        AnimatedVisibility(
            visible = collapseFraction > 0.72f,
            enter = fadeIn(animationSpec = tween(180)),
            exit = fadeOut(animationSpec = tween(150)),
            modifier = Modifier.align(Alignment.TopCenter)
        ) {
            Surface(
                color = surfaceBg,
                shadowElevation = 4.dp,
                modifier = Modifier.fillMaxWidth()
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .windowInsetsPadding(WindowInsets.statusBars)
                        .height(54.dp)
                        .padding(horizontal = 6.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    IconButton(
                        onClick = onBack,
                        modifier = Modifier.size(48.dp)
                    ) {
                        Image(
                            painter = painterResource(id = R.drawable.ic_back),
                            contentDescription = stringResource(id = R.string.other_profile_back),
                            colorFilter = ColorFilter.tint(primaryInk),
                            modifier = Modifier.size(22.dp)
                        )
                    }
                    Text(
                        text = displayName,
                        color = primaryInk,
                        fontSize = 17.sp,
                        fontWeight = FontWeight.Bold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f)
                    )
                    if (!isBlocked && !isBlockedBy && profile?.isFollowing == false) {
                        Button(
                            onClick = onToggleFollow,
                            shape = RoundedCornerShape(18.dp),
                            colors = ButtonDefaults.buttonColors(containerColor = primaryCrimson),
                            contentPadding = PaddingValues(horizontal = 14.dp, vertical = 4.dp),
                            modifier = Modifier.height(34.dp)
                        ) {
                            Text(
                                text = if (profile.followsMe) stringResource(id = R.string.action_follow_back)
                                else stringResource(id = R.string.action_follow),
                                color = Color.White,
                                fontSize = 12.5.sp,
                                fontWeight = FontWeight.SemiBold
                            )
                        }
                        Spacer(modifier = Modifier.width(4.dp))
                    }
                    IconButton(
                        onClick = { showOptionsMenu = true },
                        modifier = Modifier.size(48.dp)
                    ) {
                        Image(
                            painter = painterResource(id = R.drawable.ic_more_vert),
                            contentDescription = stringResource(id = R.string.other_profile_options),
                            colorFilter = ColorFilter.tint(primaryInk),
                            modifier = Modifier.size(22.dp)
                        )
                    }
                }
            }
        }

        SnackbarHost(
            hostState = snackbarHostState,
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(bottom = 18.dp, start = 16.dp, end = 16.dp)
        )
    }

    // Full-screen Avatar Lightbox Viewer (tap profile photo to see full size + pinch zoom)
    if (showAvatarLightbox) {
        val avatarModel: Any? = remember(instance.localAvatarPath, profile?.avatarUrl) {
            val file = instance.localAvatarPath?.let { File(it) }?.takeIf { it.exists() }
            file ?: profile?.avatarUrl?.takeIf { it.isNotBlank() }?.let {
                TelefamNetworkClient.resolveMediaUrl(it)
            }
        }
        var scale by remember { mutableFloatStateOf(1f) }
        Dialog(
            onDismissRequest = { showAvatarLightbox = false },
            properties = DialogProperties(usePlatformDefaultWidth = false)
        ) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Color.Black.copy(alpha = 0.96f))
                    .pointerInput(Unit) {
                        detectTransformGestures { _, _, zoom, _ ->
                            scale = (scale * zoom).coerceIn(1f, 3.5f)
                        }
                    }
            ) {
                if (avatarModel != null) {
                    AsyncImage(
                        model = avatarModel,
                        contentDescription = stringResource(id = R.string.other_profile_avatar_zoom),
                        contentScale = ContentScale.Fit,
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(24.dp)
                            .graphicsLayer {
                                scaleX = scale
                                scaleY = scale
                            }
                    )
                } else {
                    Box(
                        modifier = Modifier
                            .size(180.dp)
                            .align(Alignment.Center)
                            .clip(CircleShape)
                            .background(primaryCrimson.copy(alpha = 0.28f)),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(
                            text = displayName.take(2).uppercase(),
                            color = Color.White,
                            fontSize = 54.sp,
                            fontWeight = FontWeight.Bold
                        )
                    }
                }

                IconButton(
                    onClick = { showAvatarLightbox = false },
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .windowInsetsPadding(WindowInsets.statusBars)
                        .padding(14.dp)
                        .size(48.dp)
                        .testTag("other_profile_avatar_lightbox_close")
                ) {
                    Image(
                        painter = painterResource(id = R.drawable.ic_close_white),
                        contentDescription = "Close",
                        modifier = Modifier.size(22.dp)
                    )
                }

                Text(
                    text = displayName,
                    color = Color.White,
                    fontSize = 16.sp,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier
                        .align(Alignment.BottomCenter)
                        .padding(bottom = 32.dp)
                )
            }
        }
    }

    // Coming Soon dialog for Message and Subscribe buttons
    comingSoonReason?.let { reason ->
        val bodyRes = if (reason == "message") {
            R.string.other_profile_message_coming_soon
        } else {
            R.string.other_profile_subscribe_coming_soon
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

    // 3-Dots Profile Options Sheet
    if (showOptionsMenu) {
        ModalBottomSheet(
            onDismissRequest = { showOptionsMenu = false },
            sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                OtherOptionRow(
                    iconRes = R.drawable.ic_share_nodes,
                    label = stringResource(id = R.string.other_profile_copy_link),
                    tint = primaryInk,
                    testTag = "other_option_copy_link"
                ) {
                    showOptionsMenu = false
                    val shareLink = if (username.isNotBlank()) "https://telefam.app/@$username"
                    else "https://telefam.app/u/${instance.userId}"
                    clipboard.setText(AnnotatedString(shareLink))
                    onShowToast(linkCopiedMsg)
                }

                OtherOptionRow(
                    iconRes = R.drawable.ic_edit,
                    label = stringResource(id = R.string.other_profile_give_nickname),
                    subtitle = if (nickname.isNotBlank()) nickname else null,
                    tint = primaryInk,
                    testTag = "other_option_give_nickname"
                ) {
                    showOptionsMenu = false
                    showNicknameDialog = true
                }

                OtherOptionRow(
                    iconRes = if (profile?.isMuted == true) R.drawable.ic_volume_on else R.drawable.ic_volume_off,
                    label = stringResource(
                        id = if (profile?.isMuted == true) R.string.other_profile_unmute
                        else R.string.other_profile_mute
                    ),
                    tint = primaryInk,
                    testTag = "other_option_mute"
                ) {
                    showOptionsMenu = false
                    onToggleMute()
                }

                OtherOptionRow(
                    iconRes = R.drawable.ic_block,
                    label = stringResource(
                        id = if (isBlocked) R.string.other_profile_unblock
                        else R.string.other_profile_block
                    ),
                    tint = primaryCrimson,
                    testTag = "other_option_block"
                ) {
                    showOptionsMenu = false
                    if (isBlocked) {
                        onToggleBlock()
                    } else {
                        showBlockConfirmDialog = true
                    }
                }

                OtherOptionRow(
                    iconRes = R.drawable.ic_flag_report,
                    label = stringResource(id = R.string.other_profile_report_user),
                    tint = primaryCrimson,
                    testTag = "other_option_report"
                ) {
                    showOptionsMenu = false
                    onOpenReport()
                }

                Spacer(modifier = Modifier.height(14.dp))
            }
        }
    }

    // Give Nickname Dialog (private per-viewer alias only)
    if (showNicknameDialog) {
        var draft by remember(nickname) { mutableStateOf(nickname) }
        AlertDialog(
            onDismissRequest = { showNicknameDialog = false },
            title = {
                Text(
                    text = stringResource(id = R.string.other_profile_nickname_title),
                    fontWeight = FontWeight.Bold
                )
            },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(
                        value = draft,
                        onValueChange = { if (it.length <= 60) draft = it },
                        singleLine = true,
                        placeholder = { Text(stringResource(id = R.string.other_profile_nickname_hint)) },
                        modifier = Modifier
                            .fillMaxWidth()
                            .testTag("other_nickname_input")
                    )
                    Text(
                        text = stringResource(id = R.string.other_profile_nickname_note),
                        color = secondaryInk,
                        fontSize = 12.sp
                    )
                }
            },
            confirmButton = {
                Button(
                    onClick = {
                        showNicknameDialog = false
                        onSetNickname(draft)
                    },
                    colors = ButtonDefaults.buttonColors(containerColor = primaryCrimson),
                    modifier = Modifier.testTag("other_nickname_save_button")
                ) {
                    Text(stringResource(id = R.string.other_profile_save), color = Color.White)
                }
            },
            dismissButton = {
                Row {
                    if (nickname.isNotBlank()) {
                        TextButton(
                            onClick = {
                                showNicknameDialog = false
                                onSetNickname("")
                            },
                            modifier = Modifier.testTag("other_nickname_clear_button")
                        ) {
                            Text(stringResource(id = R.string.other_profile_clear), color = primaryCrimson)
                        }
                    }
                    TextButton(onClick = { showNicknameDialog = false }) {
                        Text("Cancel")
                    }
                }
            }
        )
    }

    // Confirm Block Dialog
    if (showBlockConfirmDialog) {
        AlertDialog(
            onDismissRequest = { showBlockConfirmDialog = false },
            title = {
                Text(
                    text = stringResource(
                        id = R.string.feed_confirm_block_title,
                        username.ifBlank { displayName }
                    ),
                    fontWeight = FontWeight.Bold
                )
            },
            text = { Text(stringResource(id = R.string.feed_confirm_block_desc)) },
            confirmButton = {
                Button(
                    onClick = {
                        showBlockConfirmDialog = false
                        onToggleBlock()
                    },
                    colors = ButtonDefaults.buttonColors(containerColor = primaryCrimson),
                    modifier = Modifier.testTag("other_block_confirm_button")
                ) {
                    Text(stringResource(id = R.string.other_profile_block), color = Color.White)
                }
            },
            dismissButton = {
                TextButton(onClick = { showBlockConfirmDialog = false }) {
                    Text("Cancel")
                }
            }
        )
    }

    // Multi-step Report Sheet (Step 1 Category -> Step 2 Sub-reason & Details -> Step 3 Confirmation)
    if (reportSheet.isOpen) {
        ModalBottomSheet(
            onDismissRequest = onCloseReportSheet,
            sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp, vertical = 10.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                when (reportSheet.step) {
                    1 -> {
                        Text(
                            text = stringResource(id = R.string.other_profile_report_step1_title),
                            fontSize = 18.sp,
                            fontWeight = FontWeight.Bold,
                            color = primaryInk
                        )
                        LazyColumn(
                            modifier = Modifier
                                .fillMaxWidth()
                                .heightIn(max = 420.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            items(UserReportCategory.entries, key = { it.apiValue }) { cat ->
                                Row(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .clip(RoundedCornerShape(14.dp))
                                        .border(1.dp, cardBorder, RoundedCornerShape(14.dp))
                                        .clickable { onSelectReportCategory(cat) }
                                        .padding(horizontal = 14.dp, vertical = 14.dp)
                                        .testTag("other_report_cat_${cat.apiValue}"),
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.SpaceBetween
                                ) {
                                    Text(
                                        text = cat.title,
                                        color = primaryInk,
                                        fontSize = 14.5.sp,
                                        fontWeight = FontWeight.Medium,
                                        modifier = Modifier.weight(1f)
                                    )
                                    Image(
                                        painter = painterResource(id = R.drawable.ic_chevron_right),
                                        contentDescription = null,
                                        colorFilter = ColorFilter.tint(secondaryInk),
                                        modifier = Modifier.size(16.dp)
                                    )
                                }
                            }
                        }
                    }

                    2 -> {
                        val selectedCat = reportSheet.selectedCategory
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            IconButton(
                                onClick = onBackReportStep,
                                modifier = Modifier.size(40.dp)
                            ) {
                                Image(
                                    painter = painterResource(id = R.drawable.ic_back),
                                    contentDescription = stringResource(id = R.string.other_profile_back),
                                    colorFilter = ColorFilter.tint(primaryInk),
                                    modifier = Modifier.size(18.dp)
                                )
                            }
                            Column {
                                Text(
                                    text = stringResource(id = R.string.other_profile_report_step2_title),
                                    fontSize = 18.sp,
                                    fontWeight = FontWeight.Bold,
                                    color = primaryInk
                                )
                                if (selectedCat != null) {
                                    Text(
                                        text = selectedCat.title,
                                        fontSize = 12.5.sp,
                                        color = secondaryInk
                                    )
                                }
                            }
                        }

                        Text(
                            text = stringResource(id = R.string.other_profile_report_sub_reason),
                            fontSize = 13.5.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = primaryInk
                        )

                        FlowRow(
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            selectedCat?.subReasons.orEmpty().forEach { sub ->
                                val active = reportSheet.selectedSubReason == sub
                                Surface(
                                    shape = RoundedCornerShape(18.dp),
                                    color = if (active) primaryCrimson else surfaceBg,
                                    border = if (active) null else BorderStroke(1.dp, cardBorder),
                                    modifier = Modifier
                                        .clickable { onSelectReportSubReason(sub) }
                                        .testTag("other_report_sub_$sub")
                                ) {
                                    Text(
                                        text = sub,
                                        color = if (active) Color.White else primaryInk,
                                        fontSize = 13.sp,
                                        fontWeight = if (active) FontWeight.SemiBold else FontWeight.Normal,
                                        modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp)
                                    )
                                }
                            }
                        }

                        OutlinedTextField(
                            value = reportSheet.details,
                            onValueChange = onUpdateReportDetails,
                            placeholder = { Text(stringResource(id = R.string.other_profile_report_details_hint)) },
                            minLines = 3,
                            maxLines = 4,
                            modifier = Modifier
                                .fillMaxWidth()
                                .testTag("other_report_details_input")
                        )

                        Button(
                            onClick = onSubmitReport,
                            enabled = !reportSheet.isSubmitting,
                            shape = RoundedCornerShape(24.dp),
                            colors = ButtonDefaults.buttonColors(containerColor = primaryCrimson),
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(48.dp)
                                .testTag("other_report_submit_button")
                        ) {
                            if (reportSheet.isSubmitting) {
                                CircularProgressIndicator(
                                    color = Color.White,
                                    strokeWidth = 2.dp,
                                    modifier = Modifier.size(18.dp)
                                )
                            } else {
                                Text(
                                    text = stringResource(id = R.string.other_profile_report_submit),
                                    color = Color.White,
                                    fontWeight = FontWeight.Bold
                                )
                            }
                        }
                    }

                    else -> {
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(vertical = 12.dp),
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(12.dp)
                        ) {
                            Box(
                                modifier = Modifier
                                    .size(56.dp)
                                    .clip(CircleShape)
                                    .background(primaryCrimson.copy(alpha = 0.14f)),
                                contentAlignment = Alignment.Center
                            ) {
                                Image(
                                    painter = painterResource(id = R.drawable.ic_check),
                                    contentDescription = null,
                                    colorFilter = ColorFilter.tint(primaryCrimson),
                                    modifier = Modifier.size(28.dp)
                                )
                            }
                            Text(
                                text = stringResource(id = R.string.other_profile_report_step3_title),
                                fontSize = 18.sp,
                                fontWeight = FontWeight.Bold,
                                color = primaryInk
                            )
                            Text(
                                text = stringResource(id = R.string.other_profile_report_thanks),
                                fontSize = 14.sp,
                                color = secondaryInk,
                                textAlign = TextAlign.Center
                            )
                            Button(
                                onClick = onCloseReportSheet,
                                shape = RoundedCornerShape(24.dp),
                                colors = ButtonDefaults.buttonColors(containerColor = primaryCrimson),
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .height(48.dp)
                                    .testTag("other_report_done_button")
                            ) {
                                Text(stringResource(id = R.string.post_done), color = Color.White, fontWeight = FontWeight.Bold)
                            }
                        }
                    }
                }
                Spacer(modifier = Modifier.height(10.dp))
            }
        }
    }

    // Followers / Following Connections Sheet (tap any user row to open their profile)
    instance.connectionsSheetMode?.let { mode ->
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
                if (instance.isLoadingConnections) {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(180.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        CircularProgressIndicator(color = primaryCrimson)
                    }
                } else if (instance.connectionsUsers.isEmpty()) {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(150.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(text = stringResource(id = R.string.contacts_empty), color = secondaryInk)
                    }
                } else {
                    LazyColumn(
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                        contentPadding = PaddingValues(vertical = 10.dp)
                    ) {
                        items(instance.connectionsUsers, key = { it.userId }) { user ->
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

    // Shared Photo / Text Post Viewer Dialog
    instance.activeViewerItem?.let { item ->
        OtherPostDetailDialog(
            item = item,
            onDismiss = onCloseItemViewer,
            onToggleLike = { onTogglePostLike(item) },
            onToggleSave = { onTogglePostSave(item) }
        )
    }
}

@Composable
private fun StatCounterColumn(
    countText: String,
    label: String,
    primaryInk: Color,
    secondaryInk: Color,
    enabled: Boolean,
    testTag: String,
    onClick: () -> Unit
) {
    Column(
        modifier = Modifier
            .clip(RoundedCornerShape(8.dp))
            .then(if (enabled) Modifier.clickable(onClick = onClick) else Modifier)
            .padding(horizontal = 10.dp, vertical = 4.dp)
            .testTag(testTag),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(
            text = countText,
            color = primaryInk,
            fontSize = 18.sp,
            fontWeight = FontWeight.Bold
        )
        Text(
            text = label,
            color = secondaryInk,
            fontSize = 13.sp
        )
    }
}

@Composable
private fun OtherFollowButton(
    relationship: String,
    isDarkTheme: Boolean,
    primaryCrimson: Color,
    cardBorder: Color,
    surfaceBg: Color,
    enabled: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    val friendsTextRed = if (isDarkTheme) Color(0xFFE05252) else primaryCrimson
    val friendsBorderRed = if (isDarkTheme) Color(0xFF7D2323) else primaryCrimson.copy(alpha = 0.65f)
    val friendsBg = if (isDarkTheme) Color(0xFF1E1315) else Color(0xFFFFF5F5)

    when (relationship) {
        "friends" -> {
            OutlinedButton(
                onClick = onClick,
                enabled = enabled,
                shape = RoundedCornerShape(24.dp),
                border = BorderStroke(1.dp, friendsBorderRed),
                colors = ButtonDefaults.outlinedButtonColors(
                    containerColor = friendsBg,
                    contentColor = friendsTextRed
                ),
                contentPadding = PaddingValues(horizontal = 10.dp, vertical = 0.dp),
                modifier = modifier
                    .height(48.dp)
                    .testTag("other_profile_follow_button")
            ) {
                Image(
                    painter = painterResource(id = R.drawable.ic_group_red),
                    contentDescription = null,
                    colorFilter = ColorFilter.tint(friendsTextRed),
                    modifier = Modifier.size(16.dp)
                )
                Spacer(modifier = Modifier.width(6.dp))
                Text(
                    text = stringResource(id = R.string.action_friends),
                    fontSize = 13.5.sp,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1
                )
            }
        }
        "following" -> {
            OutlinedButton(
                onClick = onClick,
                enabled = enabled,
                shape = RoundedCornerShape(24.dp),
                border = BorderStroke(1.dp, cardBorder),
                colors = ButtonDefaults.outlinedButtonColors(
                    containerColor = surfaceBg,
                    contentColor = MaterialTheme.colorScheme.onSurfaceVariant
                ),
                contentPadding = PaddingValues(horizontal = 10.dp, vertical = 0.dp),
                modifier = modifier
                    .height(48.dp)
                    .testTag("other_profile_follow_button")
            ) {
                Text(
                    text = stringResource(id = R.string.action_following),
                    fontSize = 13.5.sp,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1
                )
            }
        }
        else -> {
            Button(
                onClick = onClick,
                enabled = enabled,
                shape = RoundedCornerShape(24.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = primaryCrimson,
                    contentColor = Color.White
                ),
                contentPadding = PaddingValues(horizontal = 10.dp, vertical = 0.dp),
                modifier = modifier
                    .height(48.dp)
                    .testTag("other_profile_follow_button")
            ) {
                Image(
                    painter = painterResource(id = R.drawable.ic_person_add_white),
                    contentDescription = null,
                    modifier = Modifier.size(16.dp)
                )
                Spacer(modifier = Modifier.width(6.dp))
                Text(
                    text = stringResource(
                        id = if (relationship == "follow_back") R.string.action_follow_back
                        else R.string.action_follow
                    ),
                    fontSize = 13.5.sp,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1
                )
            }
        }
    }
}

@Composable
private fun OtherOptionRow(
    iconRes: Int,
    label: String,
    subtitle: String? = null,
    tint: Color,
    testTag: String,
    onClick: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 50.dp)
            .clip(RoundedCornerShape(12.dp))
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 10.dp)
            .testTag(testTag),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        Image(
            painter = painterResource(id = iconRes),
            contentDescription = null,
            colorFilter = ColorFilter.tint(tint),
            modifier = Modifier.size(20.dp)
        )
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = label,
                color = tint,
                fontSize = 15.sp,
                fontWeight = FontWeight.Medium
            )
            if (!subtitle.isNullOrBlank()) {
                Text(
                    text = subtitle,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    fontSize = 12.5.sp
                )
            }
        }
    }
}

@Composable
private fun OtherProfileMediaTile(
    item: OwnerProfileItemDto,
    isDarkTheme: Boolean,
    onClick: () -> Unit
) {
    val thumbUrl = remember(item.thumbnailUrl) {
        if (item.thumbnailUrl.isBlank()) ""
        else TelefamNetworkClient.resolveMediaUrl(item.thumbnailUrl)
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
            .testTag("other_grid_item_${item.itemId}")
    ) {
        if (item.mediaType == "text") {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(parsedCardBg ?: Color(0xFFC81010))
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
private fun OtherPostDetailDialog(
    item: OwnerProfileItemDto,
    onDismiss: () -> Unit,
    onToggleLike: () -> Unit,
    onToggleSave: () -> Unit
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
                            val resolved = TelefamNetworkClient.resolveMediaUrl(rawUrl)
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
            }
        },
        confirmButton = {
            TextButton(onClick = onDismiss) {
                Text(stringResource(id = R.string.post_done))
            }
        }
    )
}
