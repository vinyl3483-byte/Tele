package com.telefam.company.app.ui.screens

import androidx.compose.foundation.BorderStroke
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
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items as gridItems
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
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
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.telefam.company.app.R
import com.telefam.company.app.data.ContactModel
import com.telefam.company.app.ui.ContactFilter
import kotlinx.coroutines.flow.distinctUntilChanged

@Composable
fun ContactsTopBar(
    isDarkTheme: Boolean,
    searchQuery: String,
    activeFilter: ContactFilter,
    onSearchQueryChange: (String) -> Unit,
    onSelectFilter: (ContactFilter) -> Unit,
    onToggleTheme: () -> Unit
) {
    val searchBg = if (isDarkTheme) Color(0xFF1A2029) else Color(0xFFA60B0B)
    val themePillBg = if (isDarkTheme) Color(0xFF191C22) else Color(0xFFA60B0B)

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.primary)
            .padding(top = 10.dp, bottom = 10.dp)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Row(
                modifier = Modifier
                    .weight(1f)
                    .height(46.dp)
                    .clip(RoundedCornerShape(23.dp))
                    .background(searchBg)
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
                Spacer(modifier = Modifier.width(10.dp))
                Box(
                    modifier = Modifier.weight(1f),
                    contentAlignment = Alignment.CenterStart
                ) {
                    if (searchQuery.isEmpty()) {
                        Text(
                            text = stringResource(id = R.string.contacts_search_hint),
                            style = MaterialTheme.typography.bodyMedium,
                            color = Color.White.copy(alpha = 0.72f),
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
                            .testTag("contacts_search_input")
                    )
                }
            }

            Row(
                modifier = Modifier
                    .heightIn(min = 48.dp)
                    .clickable(onClick = onToggleTheme)
                    .testTag("contacts_theme_toggle_button"),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(
                    modifier = Modifier
                        .height(38.dp)
                        .clip(RoundedCornerShape(19.dp))
                        .background(themePillBg)
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
        }

        Spacer(modifier = Modifier.height(6.dp))

        LazyRow(
            modifier = Modifier.fillMaxWidth(),
            contentPadding = PaddingValues(horizontal = 14.dp),
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            items(ContactFilter.entries, key = { it.name }) { filter ->
                val selected = filter == activeFilter
                val label = filterLabel(filter)
                Box(
                    modifier = Modifier
                        .heightIn(min = 48.dp)
                        .clip(RoundedCornerShape(24.dp))
                        .clickable { onSelectFilter(filter) }
                        .testTag("contacts_filter_${filter.apiValue}"),
                    contentAlignment = Alignment.Center
                ) {
                    Box(
                        modifier = Modifier
                            .height(36.dp)
                            .clip(RoundedCornerShape(18.dp))
                            .background(if (selected) Color.White else Color.Transparent)
                            .padding(horizontal = 18.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(
                            text = label,
                            style = MaterialTheme.typography.labelLarge.copy(
                                fontSize = 14.sp,
                                fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Medium
                            ),
                            color = if (selected) Color(0xFF111827) else Color.White
                        )
                    }
                }
            }
        }
    }
}

@Composable
fun ContactsScreenContent(
    modifier: Modifier = Modifier,
    isDarkTheme: Boolean,
    contacts: List<ContactModel>,
    activeFilter: ContactFilter,
    isLoading: Boolean,
    hasMore: Boolean,
    onToggleFollow: (ContactModel) -> Unit,
    onOpenProfile: (ContactModel) -> Unit = {},
    onLoadMore: () -> Unit,
    onBottomBarVisibilityChange: (Boolean) -> Unit
) {
    val sectionTitle = filterLabel(activeFilter).uppercase()

    BoxWithConstraints(
        modifier = modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
    ) {
        val columns = when {
            maxWidth >= 900.dp -> 3
            maxWidth >= 600.dp -> 2
            else -> 1
        }

        if (isLoading && contacts.isEmpty()) {
            Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = MaterialTheme.colorScheme.primary)
            }
        } else if (contacts.isEmpty()) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(horizontal = 16.dp, vertical = 14.dp)
            ) {
                SectionHeader(title = sectionTitle)
                Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Text(
                        text = stringResource(id = R.string.contacts_empty),
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        } else if (columns == 1) {
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
                        if (movingDown) {
                            onBottomBarVisibilityChange(false)
                        } else if (movingUp) {
                            onBottomBarVisibilityChange(true)
                        }
                    }
                    prevIndex = index
                    prevOffset = offset
                }
            }

            LaunchedEffect(listState, contacts.size, hasMore, isLoading) {
                snapshotFlow {
                    listState.layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: 0
                }.distinctUntilChanged().collect { lastVisible ->
                    if (hasMore && !isLoading && contacts.isNotEmpty() && lastVisible >= contacts.size - 4) {
                        onLoadMore()
                    }
                }
            }

            LazyColumn(
                state = listState,
                modifier = Modifier
                    .fillMaxSize()
                    .testTag("contacts_list"),
                contentPadding = PaddingValues(top = 14.dp, bottom = 84.dp)
            ) {
                item(key = "section_header") {
                    Box(modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp)) {
                        SectionHeader(title = sectionTitle)
                    }
                }
                items(contacts, key = { it.userId }) { contact ->
                    ContactListRow(
                        contact = contact,
                        isDarkTheme = isDarkTheme,
                        onOpenProfile = { onOpenProfile(contact) },
                        onToggleFollow = { onToggleFollow(contact) }
                    )
                }
                if (isLoading) {
                    item(key = "loading_more") {
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(vertical = 16.dp),
                            contentAlignment = Alignment.Center
                        ) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(24.dp),
                                strokeWidth = 2.dp,
                                color = MaterialTheme.colorScheme.primary
                            )
                        }
                    }
                }
            }
        } else {
            val gridState = rememberLazyGridState()
            LaunchedEffect(gridState, contacts.size, hasMore, isLoading) {
                snapshotFlow {
                    gridState.layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: 0
                }.distinctUntilChanged().collect { lastVisible ->
                    if (hasMore && !isLoading && contacts.isNotEmpty() && lastVisible >= contacts.size - 4) {
                        onLoadMore()
                    }
                }
            }

            LazyVerticalGrid(
                state = gridState,
                columns = GridCells.Fixed(columns),
                modifier = Modifier
                    .fillMaxSize()
                    .testTag("contacts_grid"),
                contentPadding = PaddingValues(18.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                item(span = { GridItemSpan(columns) }, key = "grid_section_header") {
                    SectionHeader(title = sectionTitle)
                }
                gridItems(contacts, key = { it.userId }) { contact ->
                    ContactGridCard(
                        contact = contact,
                        isDarkTheme = isDarkTheme,
                        onOpenProfile = { onOpenProfile(contact) },
                        onToggleFollow = { onToggleFollow(contact) }
                    )
                }
                if (isLoading) {
                    item(span = { GridItemSpan(columns) }, key = "grid_loading_more") {
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(vertical = 12.dp),
                            contentAlignment = Alignment.Center
                        ) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(24.dp),
                                strokeWidth = 2.dp,
                                color = MaterialTheme.colorScheme.primary
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun SectionHeader(title: String) {
    Text(
        text = title,
        style = MaterialTheme.typography.labelMedium.copy(
            fontSize = 12.sp,
            fontWeight = FontWeight.SemiBold,
            letterSpacing = 0.8.sp
        ),
        color = MaterialTheme.colorScheme.onSurfaceVariant
    )
}

@Composable
private fun ContactListRow(
    contact: ContactModel,
    isDarkTheme: Boolean,
    onOpenProfile: () -> Unit,
    onToggleFollow: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onOpenProfile)
            .padding(horizontal = 16.dp, vertical = 10.dp)
            .testTag("contact_row_${contact.userId}"),
        verticalAlignment = Alignment.CenterVertically
    ) {
        InitialsAvatar(fullName = contact.fullName, isDarkTheme = isDarkTheme)
        Spacer(modifier = Modifier.width(14.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = contact.fullName,
                style = MaterialTheme.typography.titleMedium.copy(
                    fontSize = 16.sp,
                    fontWeight = FontWeight.Medium
                ),
                color = MaterialTheme.colorScheme.onBackground,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            Spacer(modifier = Modifier.height(2.dp))
            Text(
                text = formatHandleLocation(contact),
                style = MaterialTheme.typography.bodySmall.copy(fontSize = 13.sp),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
        Spacer(modifier = Modifier.width(10.dp))
        RelationshipActionButton(
            relationship = contact.relationship,
            isDarkTheme = isDarkTheme,
            userId = contact.userId,
            onClick = onToggleFollow
        )
    }
}

@Composable
private fun ContactGridCard(
    contact: ContactModel,
    isDarkTheme: Boolean,
    onOpenProfile: () -> Unit,
    onToggleFollow: () -> Unit
) {
    Surface(
        shape = RoundedCornerShape(16.dp),
        color = MaterialTheme.colorScheme.surface,
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onOpenProfile)
            .testTag("contact_card_${contact.userId}")
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 14.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            InitialsAvatar(fullName = contact.fullName, isDarkTheme = isDarkTheme)
            Spacer(modifier = Modifier.width(12.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = contact.fullName,
                    style = MaterialTheme.typography.titleMedium.copy(
                        fontSize = 15.sp,
                        fontWeight = FontWeight.SemiBold
                    ),
                    color = MaterialTheme.colorScheme.onSurface,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Spacer(modifier = Modifier.height(2.dp))
                Text(
                    text = formatHandleLocation(contact),
                    style = MaterialTheme.typography.bodySmall.copy(fontSize = 13.sp),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
            Spacer(modifier = Modifier.width(10.dp))
            RelationshipActionButton(
                relationship = contact.relationship,
                isDarkTheme = isDarkTheme,
                userId = contact.userId,
                onClick = onToggleFollow
            )
        }
    }
}

@Composable
private fun InitialsAvatar(
    fullName: String,
    isDarkTheme: Boolean
) {
    val bgColor = if (isDarkTheme) Color(0xFF162B3D) else Color(0xFFEAF2FA)
    val textColor = if (isDarkTheme) Color(0xFF5FA8E8) else Color(0xFF1D4ED8)
    Box(
        modifier = Modifier
            .size(48.dp)
            .clip(CircleShape)
            .background(bgColor),
        contentAlignment = Alignment.Center
    ) {
        Text(
            text = computeInitials(fullName),
            style = MaterialTheme.typography.titleMedium.copy(
                fontSize = 15.sp,
                fontWeight = FontWeight.Bold
            ),
            color = textColor
        )
    }
}

@Composable
private fun RelationshipActionButton(
    relationship: String,
    isDarkTheme: Boolean,
    userId: String,
    onClick: () -> Unit
) {
    val primaryRed = MaterialTheme.colorScheme.primary
    val friendsTextRed = if (isDarkTheme) Color(0xFFE05252) else primaryRed
    val friendsBorderRed = if (isDarkTheme) Color(0xFF7D2323) else primaryRed.copy(alpha = 0.65f)
    val friendsBg = if (isDarkTheme) Color(0xFF1E1315) else Color(0xFFFFF5F5)

    Box(
        modifier = Modifier
            .heightIn(min = 48.dp)
            .clip(RoundedCornerShape(24.dp))
            .clickable(onClick = onClick)
            .testTag("contact_action_$userId"),
        contentAlignment = Alignment.Center
    ) {
        when (relationship) {
            "friends" -> {
                Row(
                    modifier = Modifier
                        .height(38.dp)
                        .clip(RoundedCornerShape(19.dp))
                        .background(friendsBg)
                        .border(1.dp, friendsBorderRed, RoundedCornerShape(19.dp))
                        .padding(horizontal = 16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(7.dp)
                ) {
                    Image(
                        painter = painterResource(id = R.drawable.ic_group_red),
                        contentDescription = null,
                        colorFilter = ColorFilter.tint(friendsTextRed),
                        modifier = Modifier.size(16.dp)
                    )
                    Text(
                        text = stringResource(id = R.string.action_friends),
                        style = MaterialTheme.typography.labelLarge.copy(
                            fontSize = 13.sp,
                            fontWeight = FontWeight.SemiBold
                        ),
                        color = friendsTextRed
                    )
                }
            }
            "following" -> {
                Row(
                    modifier = Modifier
                        .height(38.dp)
                        .clip(RoundedCornerShape(19.dp))
                        .border(1.dp, MaterialTheme.colorScheme.outline, RoundedCornerShape(19.dp))
                        .padding(horizontal = 16.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = stringResource(id = R.string.action_following),
                        style = MaterialTheme.typography.labelLarge.copy(
                            fontSize = 13.sp,
                            fontWeight = FontWeight.Medium
                        ),
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
            "follow_back" -> {
                Row(
                    modifier = Modifier
                        .height(38.dp)
                        .clip(RoundedCornerShape(19.dp))
                        .background(primaryRed)
                        .padding(horizontal = 16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Image(
                        painter = painterResource(id = R.drawable.ic_person_add_white),
                        contentDescription = null,
                        modifier = Modifier.size(16.dp)
                    )
                    Text(
                        text = stringResource(id = R.string.action_follow_back),
                        style = MaterialTheme.typography.labelLarge.copy(
                            fontSize = 13.sp,
                            fontWeight = FontWeight.SemiBold
                        ),
                        color = Color.White
                    )
                }
            }
            else -> {
                Row(
                    modifier = Modifier
                        .height(38.dp)
                        .clip(RoundedCornerShape(19.dp))
                        .background(primaryRed)
                        .padding(horizontal = 16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Image(
                        painter = painterResource(id = R.drawable.ic_person_add_white),
                        contentDescription = null,
                        modifier = Modifier.size(16.dp)
                    )
                    Text(
                        text = stringResource(id = R.string.action_follow),
                        style = MaterialTheme.typography.labelLarge.copy(
                            fontSize = 13.sp,
                            fontWeight = FontWeight.SemiBold
                        ),
                        color = Color.White
                    )
                }
            }
        }
    }
}

@Composable
private fun filterLabel(filter: ContactFilter): String = when (filter) {
    ContactFilter.ALL -> stringResource(id = R.string.contacts_filter_all)
    ContactFilter.SUGGESTIONS -> stringResource(id = R.string.contacts_filter_suggestions)
    ContactFilter.FOLLOWERS -> stringResource(id = R.string.contacts_filter_followers)
    ContactFilter.FOLLOWING -> stringResource(id = R.string.contacts_filter_following)
    ContactFilter.FRIENDS -> stringResource(id = R.string.contacts_filter_friends)
}

private fun formatHandleLocation(contact: ContactModel): String {
    val handle = "@${contact.username}"
    return if (contact.location.isNotBlank()) "$handle · ${contact.location}" else handle
}

private fun computeInitials(fullName: String): String {
    val parts = fullName.trim().split(Regex("\\s+")).filter { it.isNotEmpty() }
    return when {
        parts.size >= 2 -> "${parts[0].first()}${parts[1].first()}".uppercase()
        parts.size == 1 && parts[0].length >= 2 -> parts[0].take(2).uppercase()
        parts.size == 1 -> parts[0].uppercase()
        else -> "?"
    }
}
