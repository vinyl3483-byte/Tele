package com.telefam.company.app.ui.screens

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
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
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.ui.layout.ContentScale
import coil.compose.AsyncImage
import com.telefam.company.app.R
import com.telefam.company.app.data.ContactModel
import com.telefam.company.app.data.ConversationModel
import com.telefam.company.app.data.MessageModel
import com.telefam.company.app.feed.FeedFormatter
import com.telefam.company.app.feed.FeedPlaybackState
import com.telefam.company.app.network.AuthSessionDto
import com.telefam.company.app.network.MyProfileDto
import com.telefam.company.app.network.NotificationDto
import com.telefam.company.app.network.TelefamNetworkClient
import android.graphics.Bitmap
import android.net.Uri
import com.telefam.company.app.network.OwnerProfileItemDto
import com.telefam.company.app.ui.ContactFilter
import com.telefam.company.app.ui.FeedController
import com.telefam.company.app.ui.HomeTab
import com.telefam.company.app.ui.OwnerProfileTab
import com.telefam.company.app.ui.OwnerProfileUiState
import com.telefam.company.app.ui.VideoFeedUiState
import com.telefam.company.app.ui.components.swipeBackEdge
import kotlinx.coroutines.flow.distinctUntilChanged

@Composable
fun WorkspaceScreen(
    session: AuthSessionDto,
    isDarkTheme: Boolean,
    activeTab: HomeTab,
    homeSearchQuery: String,
    conversations: List<ConversationModel>,
    selectedConversationId: String?,
    messages: List<MessageModel>,
    contacts: List<ContactModel>,
    contactFilter: ContactFilter,
    contactSearchQuery: String,
    isLoadingContacts: Boolean,
    hasMoreContacts: Boolean,
    contactsToastMessage: String?,
    myProfile: MyProfileDto?,
    ownerProfileState: OwnerProfileUiState,
    videoFeedState: VideoFeedUiState,
    feedPlaybackState: FeedPlaybackState,
    feedController: FeedController,
    notifications: List<NotificationDto>,
    onHomeSearchQueryChange: (String) -> Unit,
    onToggleTheme: () -> Unit,
    onSelectTab: (HomeTab) -> Unit,
    onSelectConversation: (String?) -> Unit,
    onCreateConversation: (String) -> Unit,
    onSendMessage: (String) -> Unit,
    onDeleteMessage: (String) -> Unit,
    onSelectContactFilter: (ContactFilter) -> Unit,
    onContactSearchQueryChange: (String) -> Unit,
    onToggleFollow: (ContactModel) -> Unit,
    onLoadMoreContacts: () -> Unit,
    onClearContactsToast: () -> Unit,
    onAvatarCropped: (Bitmap) -> Unit,
    onUploadBackgroundPhotos: (List<Uri>) -> Unit,
    onDeleteBackgroundPhoto: (String) -> Unit,
    onSelectOwnerCategory: (OwnerProfileTab) -> Unit,
    onRefreshOwnerProfile: () -> Unit,
    onOpenConnections: (String) -> Unit,
    onCloseConnections: () -> Unit,
    onToggleConnectionFollow: (ContactModel) -> Unit,
    onOpenOwnerItem: (OwnerProfileItemDto) -> Unit,
    onCloseOwnerItemViewer: () -> Unit,
    onToggleOwnerPostLike: (OwnerProfileItemDto) -> Unit,
    onToggleOwnerPostSave: (OwnerProfileItemDto) -> Unit,
    onToggleOwnerPostLock: (OwnerProfileItemDto) -> Unit,
    onShowOwnerToast: (String) -> Unit,
    onClearOwnerToast: () -> Unit,
    onOpenPost: () -> Unit,
    onOpenNotifications: () -> Unit,
    onMarkNotificationsRead: () -> Unit,
    onSyncNow: () -> Unit,
    onEditProfile: () -> Unit,
    onSignOut: () -> Unit,
    onOpenUserProfile: (String) -> Unit = {}
) {
    var showNewChatDialog by remember { mutableStateOf(false) }
    var showNotificationsDialog by remember { mutableStateOf(false) }
    var showMoreMenu by remember { mutableStateOf(false) }
    var isBottomBarVisible by remember { mutableStateOf(true) }
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(activeTab) {
        isBottomBarVisible = true
    }

    LaunchedEffect(contactsToastMessage) {
        if (!contactsToastMessage.isNullOrBlank()) {
            snackbarHostState.currentSnackbarData?.dismiss()
            snackbarHostState.showSnackbar(contactsToastMessage)
            onClearContactsToast()
        }
    }

    LaunchedEffect(ownerProfileState.toastMessage) {
        val msg = ownerProfileState.toastMessage
        if (!msg.isNullOrBlank()) {
            snackbarHostState.currentSnackbarData?.dismiss()
            snackbarHostState.showSnackbar(msg)
            onClearOwnerToast()
        }
    }

    val filteredConversations = remember(conversations, homeSearchQuery) {
        val q = homeSearchQuery.trim().lowercase()
        if (q.isEmpty()) conversations else conversations.filter { it.title.lowercase().contains(q) }
    }

    val unreadCount = remember(notifications) { notifications.count { !it.isRead } }

    val selectedConversation = remember(conversations, selectedConversationId) {
        conversations.firstOrNull { it.id == selectedConversationId }
    }

    val isImmersiveFeed = activeTab == HomeTab.FEEDS
    val isEdgeToEdgeProfile = activeTab == HomeTab.PROFILE
    val rootModifier = Modifier
        .fillMaxSize()
        .background(
            when {
                isImmersiveFeed -> Color.Black
                isEdgeToEdgeProfile -> MaterialTheme.colorScheme.background
                else -> MaterialTheme.colorScheme.primary
            }
        )
        .let { m -> if (isImmersiveFeed || isEdgeToEdgeProfile) m else m.windowInsetsPadding(WindowInsets.statusBars) }
        .windowInsetsPadding(WindowInsets.navigationBars)

    Box(modifier = rootModifier) {
        BoxWithConstraints(modifier = Modifier.fillMaxSize()) {
            val isWide = maxWidth >= 600.dp

            Box(modifier = Modifier.fillMaxSize()) {
                Column(modifier = Modifier.fillMaxSize()) {
                    when (activeTab) {
                        HomeTab.FEEDS, HomeTab.PROFILE -> Unit
                        HomeTab.CONTACTS -> {
                            ContactsTopBar(
                                isDarkTheme = isDarkTheme,
                                searchQuery = contactSearchQuery,
                                activeFilter = contactFilter,
                                onSearchQueryChange = onContactSearchQueryChange,
                                onSelectFilter = onSelectContactFilter,
                                onToggleTheme = onToggleTheme
                            )
                        }
                        else -> {
                            HomeTopBar(
                                isDarkTheme = isDarkTheme,
                                searchQuery = homeSearchQuery,
                                unreadCount = unreadCount,
                                showMoreMenu = showMoreMenu,
                                onSearchQueryChange = onHomeSearchQueryChange,
                                onToggleTheme = onToggleTheme,
                                onNotificationsClick = {
                                    onOpenNotifications()
                                    showNotificationsDialog = true
                                },
                                onMoreClick = { showMoreMenu = true },
                                onDismissMoreMenu = { showMoreMenu = false },
                                onSyncClick = {
                                    showMoreMenu = false
                                    onSyncNow()
                                },
                                onEditProfileClick = {
                                    showMoreMenu = false
                                    onEditProfile()
                                },
                                onSignOutClick = {
                                    showMoreMenu = false
                                    onSignOut()
                                }
                            )
                        }
                    }

                    val bodyShape = if (activeTab == HomeTab.CONTACTS || isImmersiveFeed || isEdgeToEdgeProfile) {
                        RoundedCornerShape(0.dp)
                    } else {
                        RoundedCornerShape(topStart = 24.dp, topEnd = 24.dp)
                    }

                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .fillMaxWidth()
                            .clip(bodyShape)
                            .background(if (isImmersiveFeed) Color.Black else MaterialTheme.colorScheme.background)
                    ) {
                        if (isWide) {
                            Row(modifier = Modifier.fillMaxSize()) {
                                HomeNavigationRail(
                                    isDarkTheme = isDarkTheme || isImmersiveFeed,
                                    activeTab = activeTab,
                                    onChatsClick = {
                                        onSelectTab(HomeTab.CHATS)
                                        onSelectConversation(null)
                                    },
                                    onContactsClick = { onSelectTab(HomeTab.CONTACTS) },
                                    onOpenPost = onOpenPost,
                                    onFeedsClick = { onSelectTab(HomeTab.FEEDS) },
                                    onProfileClick = { onSelectTab(HomeTab.PROFILE) }
                                )
                                HorizontalDivider(
                                    modifier = Modifier
                                        .width(1.dp)
                                        .fillMaxHeight(),
                                    color = if (isImmersiveFeed) Color(0xFF1F222A) else MaterialTheme.colorScheme.outlineVariant
                                )
                                when (activeTab) {
                                    HomeTab.CONTACTS -> {
                                        BackHandler { onSelectTab(HomeTab.CHATS) }
                                        ContactsScreenContent(
                                            modifier = Modifier
                                                .weight(1f)
                                                .fillMaxHeight(),
                                            isDarkTheme = isDarkTheme,
                                            contacts = contacts,
                                            activeFilter = contactFilter,
                                            isLoading = isLoadingContacts,
                                            hasMore = hasMoreContacts,
                                            onToggleFollow = onToggleFollow,
                                            onOpenProfile = { contact -> onOpenUserProfile(contact.userId) },
                                            onLoadMore = onLoadMoreContacts,
                                            onBottomBarVisibilityChange = { isBottomBarVisible = it }
                                        )
                                    }

                                    HomeTab.FEEDS -> {
                                        BackHandler { onSelectTab(HomeTab.CHATS) }
                                        FeedScreen(
                                            feedState = videoFeedState,
                                            playbackState = feedPlaybackState,
                                            feedController = feedController,
                                            bottomOverlayPadding = 8.dp,
                                            isActiveTab = true,
                                            modifier = Modifier
                                                .weight(1f)
                                                .fillMaxHeight()
                                        )
                                    }

                                    HomeTab.PROFILE -> {
                                        BackHandler { onSelectTab(HomeTab.CHATS) }
                                        OwnerProfileScreen(
                                            modifier = Modifier
                                                .weight(1f)
                                                .fillMaxHeight(),
                                            isDarkTheme = isDarkTheme,
                                            session = session,
                                            profile = myProfile,
                                            ownerState = ownerProfileState,
                                            bottomNavInsetPadding = 16.dp,
                                            onEditProfile = onEditProfile,
                                            onAvatarCropped = onAvatarCropped,
                                            onUploadBackgroundPhotos = onUploadBackgroundPhotos,
                                            onDeleteBackgroundPhoto = onDeleteBackgroundPhoto,
                                            onSelectCategory = onSelectOwnerCategory,
                                            onPullRefresh = onRefreshOwnerProfile,
                                            onOpenConnections = onOpenConnections,
                                            onCloseConnections = onCloseConnections,
                                            onToggleConnectionFollow = onToggleConnectionFollow,
                                            onOpenItem = onOpenOwnerItem,
                                            onCloseItemViewer = onCloseOwnerItemViewer,
                                            onTogglePostLike = onToggleOwnerPostLike,
                                            onTogglePostSave = onToggleOwnerPostSave,
                                            onTogglePostLock = onToggleOwnerPostLock,
                                            onShowToast = onShowOwnerToast,
                                            onBottomBarVisibilityChange = { isBottomBarVisible = it },
                                            onOpenUserProfile = onOpenUserProfile
                                        )
                                    }

                                    HomeTab.CHATS -> {
                                        if (filteredConversations.isEmpty()) {
                                            EmptyHomeConversations(
                                                modifier = Modifier
                                                    .weight(1f)
                                                    .fillMaxHeight(),
                                                onStartChat = { showNewChatDialog = true }
                                            )
                                        } else {
                                            ConversationListPane(
                                                modifier = Modifier
                                                    .width(320.dp)
                                                    .fillMaxHeight(),
                                                conversations = filteredConversations,
                                                selectedId = selectedConversationId,
                                                onSelectConversation = { onSelectConversation(it) },
                                                onNewChatClick = { showNewChatDialog = true },
                                                onBottomBarVisibilityChange = { isBottomBarVisible = it }
                                            )
                                            HorizontalDivider(
                                                modifier = Modifier
                                                    .width(1.dp)
                                                    .fillMaxHeight(),
                                                color = MaterialTheme.colorScheme.outlineVariant
                                            )
                                            Box(
                                                modifier = Modifier
                                                    .weight(1f)
                                                    .fillMaxHeight()
                                            ) {
                                                if (selectedConversation != null) {
                                                    ChatThreadPane(
                                                        conversation = selectedConversation,
                                                        currentUserId = session.userId,
                                                        messages = messages,
                                                        showBackButton = false,
                                                        onBack = { onSelectConversation(null) },
                                                        onSendMessage = onSendMessage,
                                                        onDeleteMessage = onDeleteMessage
                                                    )
                                                } else {
                                                    EmptyHomeConversations(
                                                        modifier = Modifier.fillMaxSize(),
                                                        onStartChat = { showNewChatDialog = true }
                                                    )
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        } else {
                            when (activeTab) {
                                HomeTab.CONTACTS -> {
                                    BackHandler { onSelectTab(HomeTab.CHATS) }
                                    ContactsScreenContent(
                                        modifier = Modifier
                                            .fillMaxSize()
                                            .swipeBackEdge { onSelectTab(HomeTab.CHATS) },
                                        isDarkTheme = isDarkTheme,
                                        contacts = contacts,
                                        activeFilter = contactFilter,
                                        isLoading = isLoadingContacts,
                                        hasMore = hasMoreContacts,
                                        onToggleFollow = onToggleFollow,
                                        onOpenProfile = { contact -> onOpenUserProfile(contact.userId) },
                                        onLoadMore = onLoadMoreContacts,
                                        onBottomBarVisibilityChange = { isBottomBarVisible = it }
                                    )
                                }

                                HomeTab.FEEDS -> {
                                    BackHandler { onSelectTab(HomeTab.CHATS) }
                                    FeedScreen(
                                        feedState = videoFeedState,
                                        playbackState = feedPlaybackState,
                                        feedController = feedController,
                                        bottomOverlayPadding = 66.dp,
                                        isActiveTab = true,
                                        modifier = Modifier.fillMaxSize()
                                    )
                                }

                                HomeTab.PROFILE -> {
                                    BackHandler { onSelectTab(HomeTab.CHATS) }
                                    OwnerProfileScreen(
                                        modifier = Modifier
                                            .fillMaxSize()
                                            .swipeBackEdge { onSelectTab(HomeTab.CHATS) },
                                        isDarkTheme = isDarkTheme,
                                        session = session,
                                        profile = myProfile,
                                        ownerState = ownerProfileState,
                                        bottomNavInsetPadding = 74.dp,
                                        onEditProfile = onEditProfile,
                                        onAvatarCropped = onAvatarCropped,
                                        onUploadBackgroundPhotos = onUploadBackgroundPhotos,
                                        onDeleteBackgroundPhoto = onDeleteBackgroundPhoto,
                                        onSelectCategory = onSelectOwnerCategory,
                                        onPullRefresh = onRefreshOwnerProfile,
                                        onOpenConnections = onOpenConnections,
                                        onCloseConnections = onCloseConnections,
                                        onToggleConnectionFollow = onToggleConnectionFollow,
                                        onOpenItem = onOpenOwnerItem,
                                        onCloseItemViewer = onCloseOwnerItemViewer,
                                        onTogglePostLike = onToggleOwnerPostLike,
                                        onTogglePostSave = onToggleOwnerPostSave,
                                        onTogglePostLock = onToggleOwnerPostLock,
                                        onShowToast = onShowOwnerToast,
                                        onBottomBarVisibilityChange = { isBottomBarVisible = it },
                                        onOpenUserProfile = onOpenUserProfile
                                    )
                                }

                                HomeTab.CHATS -> {
                                    if (selectedConversation != null) {
                                        BackHandler { onSelectConversation(null) }
                                        ChatThreadPane(
                                            conversation = selectedConversation,
                                            currentUserId = session.userId,
                                            messages = messages,
                                            showBackButton = true,
                                            onBack = { onSelectConversation(null) },
                                            onSendMessage = onSendMessage,
                                            onDeleteMessage = onDeleteMessage
                                        )
                                    } else if (filteredConversations.isEmpty()) {
                                        EmptyHomeConversations(
                                            modifier = Modifier.fillMaxSize(),
                                            onStartChat = { showNewChatDialog = true }
                                        )
                                    } else {
                                        ConversationListPane(
                                            modifier = Modifier.fillMaxSize(),
                                            conversations = filteredConversations,
                                            selectedId = selectedConversationId,
                                            onSelectConversation = { onSelectConversation(it) },
                                            onNewChatClick = { showNewChatDialog = true },
                                            onBottomBarVisibilityChange = { isBottomBarVisible = it }
                                        )
                                    }
                                }
                            }
                        }
                    }
                }

                val shouldShowBottomNav = !isWide &&
                    (activeTab != HomeTab.CHATS || selectedConversation == null) &&
                    isBottomBarVisible

                AnimatedVisibility(
                    visible = shouldShowBottomNav,
                    enter = slideInVertically(initialOffsetY = { it }) + fadeIn(),
                    exit = slideOutVertically(targetOffsetY = { it }) + fadeOut(),
                    modifier = Modifier.align(Alignment.BottomCenter)
                ) {
                    HomeBottomNavBar(
                        isDarkTheme = isDarkTheme || isImmersiveFeed,
                        activeTab = activeTab,
                        onChatsClick = { onSelectTab(HomeTab.CHATS) },
                        onContactsClick = { onSelectTab(HomeTab.CONTACTS) },
                        onOpenPost = onOpenPost,
                        onFeedsClick = { onSelectTab(HomeTab.FEEDS) },
                        onProfileClick = { onSelectTab(HomeTab.PROFILE) }
                    )
                }
            }
        }

        SnackbarHost(
            hostState = snackbarHostState,
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(bottom = 78.dp, start = 16.dp, end = 16.dp)
        )
    }

    if (showNewChatDialog) {
        var titleDraft by remember { mutableStateOf("") }
        AlertDialog(
            onDismissRequest = { showNewChatDialog = false },
            title = { Text(stringResource(id = R.string.home_start_chat)) },
            text = {
                OutlinedTextField(
                    value = titleDraft,
                    onValueChange = { titleDraft = it },
                    singleLine = true,
                    placeholder = { Text("Recipient name or email") },
                    modifier = Modifier
                        .fillMaxWidth()
                        .testTag("new_chat_title_input")
                )
            },
            confirmButton = {
                Button(
                    onClick = {
                        onCreateConversation(titleDraft)
                        showNewChatDialog = false
                    },
                    colors = ButtonDefaults.buttonColors(
                        containerColor = MaterialTheme.colorScheme.primary
                    ),
                    modifier = Modifier.testTag("confirm_new_chat_button")
                ) {
                    Text("Create")
                }
            },
            dismissButton = {
                TextButton(onClick = { showNewChatDialog = false }) {
                    Text("Cancel")
                }
            }
        )
    }

    if (showNotificationsDialog) {
        AlertDialog(
            onDismissRequest = { showNotificationsDialog = false },
            title = { Text(stringResource(id = R.string.notifications_title)) },
            text = {
                if (notifications.isEmpty()) {
                    Text(
                        text = stringResource(id = R.string.notifications_empty),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                } else {
                    LazyColumn(
                        modifier = Modifier
                            .fillMaxWidth()
                            .heightIn(max = 320.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        items(notifications, key = { it.id }) { item ->
                            Surface(
                                shape = RoundedCornerShape(12.dp),
                                color = if (item.isRead) MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.4f)
                                else MaterialTheme.colorScheme.primary.copy(alpha = 0.12f)
                            ) {
                                Column(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(12.dp)
                                ) {
                                    Text(
                                        text = item.actorName.ifBlank { "Telefam" },
                                        style = MaterialTheme.typography.labelLarge,
                                        color = MaterialTheme.colorScheme.onSurface
                                    )
                                    Spacer(modifier = Modifier.height(2.dp))
                                    Text(
                                        text = item.message,
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }
                            }
                        }
                    }
                }
            },
            confirmButton = {
                if (unreadCount > 0) {
                    TextButton(onClick = {
                        onMarkNotificationsRead()
                        showNotificationsDialog = false
                    }) {
                        Text(stringResource(id = R.string.notifications_mark_read))
                    }
                }
            },
            dismissButton = {
                TextButton(onClick = { showNotificationsDialog = false }) {
                    Text(stringResource(id = R.string.post_done))
                }
            }
        )
    }
}

@Composable
private fun HomeTopBar(
    isDarkTheme: Boolean,
    searchQuery: String,
    unreadCount: Int,
    showMoreMenu: Boolean,
    onSearchQueryChange: (String) -> Unit,
    onToggleTheme: () -> Unit,
    onNotificationsClick: () -> Unit,
    onMoreClick: () -> Unit,
    onDismissMoreMenu: () -> Unit,
    onSyncClick: () -> Unit,
    onEditProfileClick: () -> Unit,
    onSignOutClick: () -> Unit
) {
    val pillBg = if (isDarkTheme) Color(0xFF1E1F24) else Color(0xFFA60B0B)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 14.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Row(
            modifier = Modifier
                .weight(1f)
                .height(46.dp)
                .clip(RoundedCornerShape(23.dp))
                .background(pillBg)
                .border(1.dp, Color.White.copy(alpha = 0.08f), RoundedCornerShape(23.dp))
                .padding(horizontal = 14.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Image(
                painter = painterResource(id = R.drawable.ic_search),
                contentDescription = null,
                colorFilter = ColorFilter.tint(Color.White.copy(alpha = 0.72f)),
                modifier = Modifier.size(18.dp)
            )
            Spacer(modifier = Modifier.width(8.dp))
            Box(
                modifier = Modifier.weight(1f),
                contentAlignment = Alignment.CenterStart
            ) {
                if (searchQuery.isEmpty()) {
                    Text(
                        text = stringResource(id = R.string.home_search_hint),
                        style = MaterialTheme.typography.bodyMedium,
                        color = Color.White.copy(alpha = 0.75f),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
                BasicTextField(
                    value = searchQuery,
                    onValueChange = onSearchQueryChange,
                    singleLine = true,
                    textStyle = MaterialTheme.typography.bodyMedium.copy(color = Color.White),
                    cursorBrush = SolidColor(Color.White),
                    modifier = Modifier
                        .fillMaxWidth()
                        .testTag("home_search_input")
                )
            }
            if (searchQuery.isNotEmpty()) {
                Image(
                    painter = painterResource(id = R.drawable.ic_close_white),
                    contentDescription = "Clear",
                    modifier = Modifier
                        .size(16.dp)
                        .clickable { onSearchQueryChange("") }
                )
            }
        }

        Box(
            modifier = Modifier
                .heightIn(min = 48.dp)
                .clip(RoundedCornerShape(24.dp))
                .clickable(onClick = onToggleTheme)
                .testTag("theme_toggle_button"),
            contentAlignment = Alignment.Center
        ) {
            Row(
                modifier = Modifier
                    .height(38.dp)
                    .clip(RoundedCornerShape(19.dp))
                    .background(pillBg)
                    .border(1.dp, Color.White.copy(alpha = 0.12f), RoundedCornerShape(19.dp))
                    .padding(horizontal = 13.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                Image(
                    painter = painterResource(id = if (isDarkTheme) R.drawable.ic_moon else R.drawable.ic_sun),
                    contentDescription = null,
                    modifier = Modifier.size(15.dp)
                )
                Text(
                    text = if (isDarkTheme) stringResource(id = R.string.home_theme_dark)
                    else stringResource(id = R.string.home_theme_light),
                    style = MaterialTheme.typography.labelLarge.copy(fontSize = 12.sp),
                    color = Color.White
                )
            }
        }

        Box(contentAlignment = Alignment.TopEnd) {
            IconButton(
                onClick = onNotificationsClick,
                modifier = Modifier
                    .size(48.dp)
                    .testTag("notifications_button")
            ) {
                Image(
                    painter = painterResource(id = R.drawable.ic_bell),
                    contentDescription = "Notifications",
                    modifier = Modifier.size(22.dp)
                )
            }
            if (unreadCount > 0) {
                Box(
                    modifier = Modifier
                        .padding(top = 10.dp, end = 10.dp)
                        .size(9.dp)
                        .clip(CircleShape)
                        .background(Color.White)
                )
            }
        }

        Box {
            IconButton(
                onClick = onMoreClick,
                modifier = Modifier
                    .size(48.dp)
                    .testTag("more_options_button")
            ) {
                Image(
                    painter = painterResource(id = R.drawable.ic_more_vert),
                    contentDescription = "More options",
                    modifier = Modifier.size(22.dp)
                )
            }
            DropdownMenu(
                expanded = showMoreMenu,
                onDismissRequest = onDismissMoreMenu
            ) {
                DropdownMenuItem(
                    text = { Text(stringResource(id = R.string.action_sync)) },
                    leadingIcon = {
                        Image(
                            painter = painterResource(id = R.drawable.ic_sync),
                            contentDescription = null,
                            colorFilter = ColorFilter.tint(MaterialTheme.colorScheme.onSurface),
                            modifier = Modifier.size(18.dp)
                        )
                    },
                    onClick = onSyncClick
                )
                DropdownMenuItem(
                    text = { Text(stringResource(id = R.string.action_edit_profile)) },
                    leadingIcon = {
                        Image(
                            painter = painterResource(id = R.drawable.ic_nav_profile),
                            contentDescription = null,
                            colorFilter = ColorFilter.tint(MaterialTheme.colorScheme.onSurface),
                            modifier = Modifier.size(18.dp)
                        )
                    },
                    onClick = onEditProfileClick
                )
                DropdownMenuItem(
                    text = { Text(stringResource(id = R.string.action_sign_out), color = MaterialTheme.colorScheme.primary) },
                    leadingIcon = {
                        Image(
                            painter = painterResource(id = R.drawable.ic_sign_out),
                            contentDescription = null,
                            colorFilter = ColorFilter.tint(MaterialTheme.colorScheme.primary),
                            modifier = Modifier.size(18.dp)
                        )
                    },
                    onClick = onSignOutClick
                )
            }
        }
    }
}

@Composable
private fun EmptyHomeConversations(
    modifier: Modifier,
    onStartChat: () -> Unit
) {
    Box(
        modifier = modifier.padding(horizontal = 32.dp),
        contentAlignment = Alignment.Center
    ) {
        Column(
            modifier = Modifier.widthIn(max = 360.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Box(
                modifier = Modifier
                    .size(72.dp)
                    .clip(CircleShape)
                    .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.14f)),
                contentAlignment = Alignment.Center
            ) {
                Image(
                    painter = painterResource(id = R.drawable.ic_chat_bubbles_red),
                    contentDescription = null,
                    modifier = Modifier.size(32.dp)
                )
            }
            Spacer(modifier = Modifier.height(18.dp))
            Text(
                text = stringResource(id = R.string.home_empty_title),
                style = MaterialTheme.typography.titleLarge,
                color = MaterialTheme.colorScheme.onBackground,
                textAlign = TextAlign.Center
            )
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = stringResource(id = R.string.home_empty_subtitle),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center
            )
            Spacer(modifier = Modifier.height(22.dp))
            Button(
                onClick = onStartChat,
                shape = RoundedCornerShape(24.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.primary,
                    contentColor = Color.White
                ),
                contentPadding = PaddingValues(horizontal = 24.dp, vertical = 12.dp),
                modifier = Modifier
                    .height(48.dp)
                    .testTag("start_chat_button")
            ) {
                Image(
                    painter = painterResource(id = R.drawable.ic_chat_plus_white),
                    contentDescription = null,
                    modifier = Modifier.size(18.dp)
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text(
                    text = stringResource(id = R.string.home_start_chat),
                    style = MaterialTheme.typography.labelLarge
                )
            }
        }
    }
}

@Composable
private fun HomeBottomNavBar(
    isDarkTheme: Boolean,
    activeTab: HomeTab,
    onChatsClick: () -> Unit,
    onContactsClick: () -> Unit,
    onOpenPost: () -> Unit,
    onFeedsClick: () -> Unit,
    onProfileClick: () -> Unit
) {
    val barBg = if (isDarkTheme) Color(0xFF16181C) else Color.White
    val inactiveTint = MaterialTheme.colorScheme.onSurfaceVariant
    val activeColor = MaterialTheme.colorScheme.primary
    val chatsActive = activeTab == HomeTab.CHATS
    val contactsActive = activeTab == HomeTab.CONTACTS
    val feedsActive = activeTab == HomeTab.FEEDS
    val profileActive = activeTab == HomeTab.PROFILE

    Surface(
        color = barBg,
        shadowElevation = 6.dp
    ) {
        Column(modifier = Modifier.fillMaxWidth()) {
            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(66.dp)
                    .padding(horizontal = 6.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceEvenly
            ) {
                BottomNavItem(
                    iconRes = if (chatsActive) R.drawable.ic_nav_chats else R.drawable.ic_nav_chats_outline,
                    label = stringResource(id = R.string.nav_chats),
                    tint = if (chatsActive) activeColor else inactiveTint,
                    isActive = chatsActive,
                    useIconTint = true,
                    onClick = onChatsClick,
                    modifier = Modifier
                        .weight(1f)
                        .testTag("nav_chats_tab")
                )
                BottomNavItem(
                    iconRes = if (contactsActive) R.drawable.ic_nav_contacts_active else R.drawable.ic_nav_contacts,
                    label = stringResource(id = R.string.nav_contacts),
                    tint = if (contactsActive) activeColor else inactiveTint,
                    isActive = contactsActive,
                    useIconTint = true,
                    onClick = onContactsClick,
                    modifier = Modifier
                        .weight(1f)
                        .testTag("nav_contacts_tab")
                )
                Column(
                    modifier = Modifier
                        .weight(1f)
                        .clickable(onClick = onOpenPost)
                        .testTag("nav_post_tab"),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center
                ) {
                    Box(
                        modifier = Modifier
                            .offset(y = (-4).dp)
                            .size(40.dp)
                            .clip(CircleShape)
                            .background(activeColor),
                        contentAlignment = Alignment.Center
                    ) {
                        Image(
                            painter = painterResource(id = R.drawable.ic_add),
                            contentDescription = stringResource(id = R.string.nav_post),
                            modifier = Modifier.size(20.dp)
                        )
                    }
                    Text(
                        text = stringResource(id = R.string.nav_post),
                        style = MaterialTheme.typography.labelSmall,
                        color = inactiveTint
                    )
                }
                BottomNavItem(
                    iconRes = R.drawable.ic_nav_feeds,
                    label = stringResource(id = R.string.nav_feeds),
                    tint = if (feedsActive) activeColor else inactiveTint,
                    isActive = feedsActive,
                    useIconTint = true,
                    onClick = onFeedsClick,
                    modifier = Modifier
                        .weight(1f)
                        .testTag("nav_feeds_tab")
                )
                BottomNavItem(
                    iconRes = R.drawable.ic_nav_profile,
                    label = stringResource(id = R.string.nav_profile),
                    tint = if (profileActive) activeColor else inactiveTint,
                    isActive = profileActive,
                    useIconTint = true,
                    onClick = onProfileClick,
                    modifier = Modifier
                        .weight(1f)
                        .testTag("nav_profile_tab")
                )
            }
        }
    }
}

@Composable
private fun BottomNavItem(
    iconRes: Int,
    label: String,
    tint: Color,
    isActive: Boolean,
    useIconTint: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier
            .height(54.dp)
            .clickable(onClick = onClick),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Image(
            painter = painterResource(id = iconRes),
            contentDescription = label,
            colorFilter = if (useIconTint) ColorFilter.tint(tint) else null,
            modifier = Modifier.size(22.dp)
        )
        Spacer(modifier = Modifier.height(3.dp))
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall.copy(
                fontWeight = if (isActive) FontWeight.SemiBold else FontWeight.Normal
            ),
            color = tint
        )
    }
}

@Composable
private fun HomeNavigationRail(
    isDarkTheme: Boolean,
    activeTab: HomeTab,
    onChatsClick: () -> Unit,
    onContactsClick: () -> Unit,
    onOpenPost: () -> Unit,
    onFeedsClick: () -> Unit,
    onProfileClick: () -> Unit
) {
    val railBg = if (isDarkTheme) Color(0xFF16181C) else MaterialTheme.colorScheme.surfaceVariant
    val inactiveTint = MaterialTheme.colorScheme.onSurfaceVariant
    val activeColor = MaterialTheme.colorScheme.primary
    val chatsActive = activeTab == HomeTab.CHATS
    val contactsActive = activeTab == HomeTab.CONTACTS
    val feedsActive = activeTab == HomeTab.FEEDS
    val profileActive = activeTab == HomeTab.PROFILE

    Column(
        modifier = Modifier
            .width(84.dp)
            .fillMaxHeight()
            .background(railBg)
            .padding(vertical = 18.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(18.dp)
    ) {
        BottomNavItem(
            iconRes = if (chatsActive) R.drawable.ic_nav_chats else R.drawable.ic_nav_chats_outline,
            label = stringResource(id = R.string.nav_chats),
            tint = if (chatsActive) activeColor else inactiveTint,
            isActive = chatsActive,
            useIconTint = true,
            onClick = onChatsClick,
            modifier = Modifier.testTag("rail_chats_tab")
        )
        BottomNavItem(
            iconRes = if (contactsActive) R.drawable.ic_nav_contacts_active else R.drawable.ic_nav_contacts,
            label = stringResource(id = R.string.nav_contacts),
            tint = if (contactsActive) activeColor else inactiveTint,
            isActive = contactsActive,
            useIconTint = true,
            onClick = onContactsClick,
            modifier = Modifier.testTag("rail_contacts_tab")
        )
        Box(
            modifier = Modifier
                .size(48.dp)
                .clip(CircleShape)
                .background(activeColor)
                .clickable(onClick = onOpenPost)
                .testTag("rail_post_tab"),
            contentAlignment = Alignment.Center
        ) {
            Image(
                painter = painterResource(id = R.drawable.ic_add),
                contentDescription = stringResource(id = R.string.nav_post),
                modifier = Modifier.size(20.dp)
            )
        }
        BottomNavItem(
            iconRes = R.drawable.ic_nav_feeds,
            label = stringResource(id = R.string.nav_feeds),
            tint = if (feedsActive) activeColor else inactiveTint,
            isActive = feedsActive,
            useIconTint = true,
            onClick = onFeedsClick,
            modifier = Modifier.testTag("rail_feeds_tab")
        )
        BottomNavItem(
            iconRes = R.drawable.ic_nav_profile,
            label = stringResource(id = R.string.nav_profile),
            tint = if (profileActive) activeColor else inactiveTint,
            isActive = profileActive,
            useIconTint = true,
            onClick = onProfileClick,
            modifier = Modifier.testTag("rail_profile_tab")
        )
    }
}

@Composable
private fun ConversationListPane(
    modifier: Modifier,
    conversations: List<ConversationModel>,
    selectedId: String?,
    onSelectConversation: (String) -> Unit,
    onNewChatClick: () -> Unit,
    onBottomBarVisibilityChange: (Boolean) -> Unit
) {
    val listState = rememberLazyListState()
    var prevIndex by remember { mutableIntStateOf(0) }
    var prevOffset by remember { mutableIntStateOf(0) }

    LaunchedEffect(listState) {
        snapshotFlow {
            Triple(
                listState.isScrollInProgress,
                listState.firstVisibleItemIndex,
                listState.firstVisibleItemScrollOffset
            )
        }.distinctUntilChanged().collect { (scrolling, index, offset) ->
            if (!scrolling) {
                onBottomBarVisibilityChange(true)
            } else {
                val movingDown = index > prevIndex || (index == prevIndex && offset > prevOffset + 6)
                val movingUp = index < prevIndex || (index == prevIndex && offset < prevOffset - 6)
                if (movingDown) onBottomBarVisibilityChange(false)
                else if (movingUp) onBottomBarVisibilityChange(true)
            }
            prevIndex = index
            prevOffset = offset
        }
    }

    Box(modifier = modifier.background(MaterialTheme.colorScheme.background)) {
        LazyColumn(
            state = listState,
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(top = 14.dp, start = 14.dp, end = 14.dp, bottom = 84.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            items(conversations, key = { it.id }) { conv ->
                val isSelected = conv.id == selectedId
                Surface(
                    shape = RoundedCornerShape(14.dp),
                    color = if (isSelected) MaterialTheme.colorScheme.primaryContainer
                    else MaterialTheme.colorScheme.surface,
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { onSelectConversation(conv.id) }
                        .testTag("conversation_item_${conv.id}")
                ) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 14.dp, vertical = 14.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Box(
                            modifier = Modifier
                                .size(42.dp)
                                .clip(CircleShape)
                                .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.14f)),
                            contentAlignment = Alignment.Center
                        ) {
                            Text(
                                text = conv.title.take(1).uppercase(),
                                style = MaterialTheme.typography.titleMedium,
                                color = MaterialTheme.colorScheme.primary
                            )
                        }
                        Spacer(modifier = Modifier.width(12.dp))
                        Text(
                            text = conv.title,
                            style = MaterialTheme.typography.titleMedium,
                            color = MaterialTheme.colorScheme.onSurface,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                    }
                }
            }
        }

        FloatingActionButton(
            onClick = onNewChatClick,
            containerColor = MaterialTheme.colorScheme.primary,
            contentColor = Color.White,
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .padding(bottom = 82.dp, end = 18.dp)
                .testTag("new_chat_fab")
        ) {
            Image(
                painter = painterResource(id = R.drawable.ic_add),
                contentDescription = stringResource(id = R.string.home_start_chat),
                modifier = Modifier.size(22.dp)
            )
        }
    }
}

@Composable
private fun ChatThreadPane(
    conversation: ConversationModel,
    currentUserId: String,
    messages: List<MessageModel>,
    showBackButton: Boolean,
    onBack: () -> Unit,
    onSendMessage: (String) -> Unit,
    onDeleteMessage: (String) -> Unit
) {
    var draft by remember { mutableStateOf("") }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            .swipeBackEdge(enabled = showBackButton) { onBack() }
            .imePadding()
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            if (showBackButton) {
                IconButton(
                    onClick = onBack,
                    modifier = Modifier
                        .size(48.dp)
                        .testTag("chat_back_button")
                ) {
                    Image(
                        painter = painterResource(id = R.drawable.ic_back),
                        contentDescription = "Back",
                        colorFilter = ColorFilter.tint(MaterialTheme.colorScheme.onBackground),
                        modifier = Modifier.size(22.dp)
                    )
                }
            }
            Text(
                text = conversation.title,
                style = MaterialTheme.typography.titleLarge,
                color = MaterialTheme.colorScheme.onBackground,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.padding(horizontal = 8.dp)
            )
        }

        HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)

        LazyColumn(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth(),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            items(messages, key = { it.id }) { msg ->
                val isMine = msg.senderId == currentUserId
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = if (isMine) Arrangement.End else Arrangement.Start
                ) {
                    Surface(
                        shape = RoundedCornerShape(16.dp),
                        color = if (isMine) MaterialTheme.colorScheme.primary
                        else MaterialTheme.colorScheme.surface,
                        modifier = Modifier.widthIn(max = 320.dp)
                    ) {
                        Column(modifier = Modifier.padding(horizontal = 14.dp, vertical = 10.dp)) {
                            Text(
                                text = msg.body,
                                style = MaterialTheme.typography.bodyLarge,
                                color = if (isMine) Color.White
                                else MaterialTheme.colorScheme.onSurface
                            )
                            if (isMine) {
                                Spacer(modifier = Modifier.height(4.dp))
                                Row(
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                                ) {
                                    Text(
                                        text = if (msg.isPendingSync) stringResource(id = R.string.chat_queued)
                                        else stringResource(id = R.string.chat_sent),
                                        style = MaterialTheme.typography.labelSmall,
                                        color = Color.White.copy(alpha = 0.8f)
                                    )
                                    Text(
                                        text = "Delete",
                                        style = MaterialTheme.typography.labelSmall,
                                        color = Color.White.copy(alpha = 0.8f),
                                        modifier = Modifier.clickable { onDeleteMessage(msg.id) }
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }

        HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            OutlinedTextField(
                value = draft,
                onValueChange = { draft = it },
                placeholder = { Text(stringResource(id = R.string.chat_message_hint)) },
                shape = RoundedCornerShape(24.dp),
                modifier = Modifier
                    .weight(1f)
                    .testTag("message_input")
            )
            Spacer(modifier = Modifier.width(8.dp))
            IconButton(
                onClick = {
                    val toSend = draft
                    draft = ""
                    onSendMessage(toSend)
                },
                modifier = Modifier
                    .size(48.dp)
                    .clip(CircleShape)
                    .background(MaterialTheme.colorScheme.primary)
                    .testTag("send_message_button")
            ) {
                Image(
                    painter = painterResource(id = R.drawable.ic_send),
                    contentDescription = stringResource(id = R.string.chat_send_cd),
                    modifier = Modifier.size(20.dp)
                )
            }
        }
    }
}
