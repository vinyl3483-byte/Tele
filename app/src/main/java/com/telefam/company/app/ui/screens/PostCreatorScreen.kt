package com.telefam.company.app.ui.screens

import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RangeSlider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.telefam.company.app.R
import com.telefam.company.app.data.ContactModel
import com.telefam.company.app.data.VideoFrameItem
import com.telefam.company.app.network.MusicTrackDto
import com.telefam.company.app.ui.PostComposerState
import com.telefam.company.app.ui.PostTabMode
import com.telefam.company.app.ui.PostUploadStatus
import com.telefam.company.app.ui.components.POST_BG_COLORS
import com.telefam.company.app.ui.components.POST_IMAGE_THEMES
import com.telefam.company.app.ui.components.PostThemeArtwork
import com.telefam.company.app.ui.components.swipeBackEdge
import com.telefam.company.app.ui.theme.PostFontStyle
import kotlin.math.roundToLong

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun PostCreatorScreen(
    state: PostComposerState,
    isDarkTheme: Boolean,
    contacts: List<ContactModel>,
    onClose: () -> Unit,
    onSelectMode: (PostTabMode) -> Unit,
    onTextBodyChange: (String) -> Unit,
    onCaptionChange: (String) -> Unit,
    onTogglePaletteMode: (Boolean) -> Unit,
    onSelectBgColor: (String) -> Unit,
    onSelectImageTheme: (String) -> Unit,
    onSelectFont: (PostFontStyle) -> Unit,
    onAddPhotos: (List<Uri>) -> Unit,
    onRemovePhoto: (Uri) -> Unit,
    onSelectVideo: (Uri) -> Unit,
    onClearVideo: () -> Unit,
    onUpdateTrim: (Long, Long) -> Unit,
    onSelectThumbFrame: (VideoFrameItem) -> Unit,
    onAutoSelectThumb: () -> Unit,
    onToggleMuteAudio: () -> Unit,
    onSongQueryChange: (String) -> Unit,
    onSelectSong: (MusicTrackDto?) -> Unit,
    onToggleSongPreview: (MusicTrackDto) -> Unit,
    onToggleTagContact: (ContactModel) -> Unit,
    onHashtagQueryChange: (String) -> Unit,
    onToggleHashtag: (String) -> Unit,
    onShare: () -> Unit
) {
    BackHandler(onBack = onClose)

    var showSongSheet by remember { mutableStateOf(false) }
    var showTagSheet by remember { mutableStateOf(false) }
    var showHashtagSheet by remember { mutableStateOf(false) }

    val photosPickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.PickMultipleVisualMedia(10)
    ) { uris ->
        if (uris.isNotEmpty()) onAddPhotos(uris)
    }

    val videoPickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.PickVisualMedia()
    ) { uri ->
        if (uri != null) onSelectVideo(uri)
    }

    val crimson = MaterialTheme.colorScheme.primary
    val bodyBg = MaterialTheme.colorScheme.background

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(crimson)
            .windowInsetsPadding(WindowInsets.statusBars)
            .windowInsetsPadding(WindowInsets.navigationBars)
            .imePadding()
            .swipeBackEdge(enabled = true, onBack = onClose)
    ) {
        PostCreatorHeader(
            state = state,
            onClose = onClose,
            onSelectMode = onSelectMode,
            onShare = onShare
        )

        if (state.uploadStatus == PostUploadStatus.UPLOADING || state.uploadStatus == PostUploadStatus.UPLOADED) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(crimson)
                    .padding(horizontal = 16.dp, vertical = 6.dp)
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text(
                        text = if (state.uploadStatus == PostUploadStatus.UPLOADED) {
                            stringResource(id = R.string.post_uploaded)
                        } else {
                            stringResource(id = R.string.post_uploading_fmt, state.uploadProgress)
                        },
                        style = MaterialTheme.typography.labelLarge.copy(fontSize = 13.sp),
                        color = Color.White
                    )
                }
                if (state.uploadStatus == PostUploadStatus.UPLOADING) {
                    Spacer(modifier = Modifier.height(4.dp))
                    LinearProgressIndicator(
                        progress = { (state.uploadProgress / 100f).coerceIn(0f, 1f) },
                        color = Color.White,
                        trackColor = Color.White.copy(alpha = 0.28f),
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(3.dp)
                            .clip(RoundedCornerShape(2.dp))
                    )
                }
            }
        }

        Box(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth()
                .background(bodyBg)
        ) {
            BoxWithConstraints(modifier = Modifier.fillMaxSize()) {
                val isWide = maxWidth >= 600.dp

                val primaryStageContent: @Composable (Modifier) -> Unit = { mod ->
                    when (state.mode) {
                        PostTabMode.TEXT -> TextComposerCard(
                            state = state,
                            onTextBodyChange = onTextBodyChange,
                            modifier = mod
                        )
                        PostTabMode.PHOTOS -> PhotosComposerCard(
                            state = state,
                            isDarkTheme = isDarkTheme,
                            onPickPhotos = {
                                photosPickerLauncher.launch(
                                    PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)
                                )
                            },
                            onRemovePhoto = onRemovePhoto,
                            modifier = mod
                        )
                        PostTabMode.VIDEO -> VideoComposerCard(
                            state = state,
                            isDarkTheme = isDarkTheme,
                            onPickVideo = {
                                videoPickerLauncher.launch(
                                    PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.VideoOnly)
                                )
                            },
                            onClearVideo = onClearVideo,
                            onUpdateTrim = onUpdateTrim,
                            onSelectThumbFrame = onSelectThumbFrame,
                            onAutoSelectThumb = onAutoSelectThumb,
                            onToggleMuteAudio = onToggleMuteAudio,
                            modifier = mod
                        )
                    }
                }

                val secondaryControlsContent: @Composable (Modifier) -> Unit = { mod ->
                    Column(
                        modifier = mod,
                        verticalArrangement = Arrangement.spacedBy(14.dp)
                    ) {
                        if (state.mode == PostTabMode.TEXT) {
                            TextStyleControls(
                                state = state,
                                isDarkTheme = isDarkTheme,
                                onTogglePaletteMode = onTogglePaletteMode,
                                onSelectBgColor = onSelectBgColor,
                                onSelectImageTheme = onSelectImageTheme,
                                onSelectFont = onSelectFont
                            )
                        } else {
                            CaptionInputCard(
                                caption = state.caption,
                                isDarkTheme = isDarkTheme,
                                onCaptionChange = onCaptionChange
                            )
                        }

                        PostMetadataOptionsCard(
                            state = state,
                            isDarkTheme = isDarkTheme,
                            onOpenSong = { showSongSheet = true },
                            onToggleSongPreview = { track -> onToggleSongPreview(track) },
                            onOpenTagPeople = { showTagSheet = true },
                            onOpenHashtags = { showHashtagSheet = true }
                        )
                    }
                }

                if (isWide) {
                    Row(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(20.dp),
                        horizontalArrangement = Arrangement.spacedBy(20.dp)
                    ) {
                        Column(
                            modifier = Modifier
                                .weight(1.05f)
                                .fillMaxHeight()
                                .verticalScroll(rememberScrollState()),
                            verticalArrangement = Arrangement.spacedBy(12.dp)
                        ) {
                            primaryStageContent(Modifier.fillMaxWidth())
                        }
                        Column(
                            modifier = Modifier
                                .weight(0.95f)
                                .fillMaxHeight()
                                .verticalScroll(rememberScrollState())
                        ) {
                            secondaryControlsContent(Modifier.fillMaxWidth())
                        }
                    }
                } else {
                    Column(
                        modifier = Modifier
                            .fillMaxSize()
                            .verticalScroll(rememberScrollState())
                            .padding(horizontal = 14.dp, vertical = 16.dp),
                        verticalArrangement = Arrangement.spacedBy(16.dp)
                    ) {
                        primaryStageContent(Modifier.fillMaxWidth())
                        secondaryControlsContent(Modifier.fillMaxWidth())
                    }
                }
            }
        }
    }

    if (showSongSheet) {
        SongPickerSheet(
            query = state.songQuery,
            tracks = state.songResults,
            selectedSong = state.selectedSong,
            previewingTrackId = state.previewingTrackId,
            isPlayingPreview = state.isPlayingSongPreview,
            isLoading = state.isSearchingSongs,
            onQueryChange = onSongQueryChange,
            onTogglePreview = onToggleSongPreview,
            onSelectSong = onSelectSong,
            onDismiss = { showSongSheet = false }
        )
    }

    if (showTagSheet) {
        TagPeopleSheet(
            contacts = contacts,
            taggedContacts = state.taggedContacts,
            onToggleContact = onToggleTagContact,
            onDismiss = { showTagSheet = false }
        )
    }

    if (showHashtagSheet) {
        HashtagPickerSheet(
            query = state.hashtagQuery,
            results = state.hashtagResults,
            selectedTags = state.selectedHashtags,
            isLoading = state.isSearchingHashtags,
            onQueryChange = onHashtagQueryChange,
            onToggleTag = onToggleHashtag,
            onDismiss = { showHashtagSheet = false }
        )
    }
}

@Composable
private fun PostCreatorHeader(
    state: PostComposerState,
    onClose: () -> Unit,
    onSelectMode: (PostTabMode) -> Unit,
    onShare: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp, vertical = 8.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically
        ) {
            IconButton(
                onClick = onClose,
                modifier = Modifier
                    .size(48.dp)
                    .testTag("post_close_button")
            ) {
                Image(
                    painter = painterResource(id = R.drawable.ic_close_white),
                    contentDescription = "Close",
                    modifier = Modifier.size(22.dp)
                )
            }
            Text(
                text = stringResource(id = R.string.post_title),
                style = MaterialTheme.typography.titleLarge,
                color = Color.White,
                modifier = Modifier
                    .weight(1f)
                    .padding(start = 4.dp)
            )
            Surface(
                shape = RoundedCornerShape(20.dp),
                color = if (state.canShare) Color.White else Color.White.copy(alpha = 0.65f),
                modifier = Modifier
                    .heightIn(min = 38.dp)
                    .clip(RoundedCornerShape(20.dp))
                    .clickable(enabled = state.canShare, onClick = onShare)
                    .testTag("post_share_button")
            ) {
                Box(
                    modifier = Modifier.padding(horizontal = 18.dp, vertical = 8.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = stringResource(id = R.string.post_share),
                        style = MaterialTheme.typography.labelLarge.copy(fontSize = 14.sp),
                        color = MaterialTheme.colorScheme.primary.copy(
                            alpha = if (state.canShare) 1f else 0.55f
                        )
                    )
                }
            }
        }

        Spacer(modifier = Modifier.height(10.dp))

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 4.dp, vertical = 4.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            PostModeTabPill(
                label = stringResource(id = R.string.post_tab_text),
                iconRes = null,
                leadingChar = "T",
                selected = state.mode == PostTabMode.TEXT,
                onClick = { onSelectMode(PostTabMode.TEXT) },
                testTag = "post_tab_text"
            )
            PostModeTabPill(
                label = stringResource(id = R.string.post_tab_photos),
                iconRes = R.drawable.ic_photos_tab,
                leadingChar = null,
                selected = state.mode == PostTabMode.PHOTOS,
                onClick = { onSelectMode(PostTabMode.PHOTOS) },
                testTag = "post_tab_photos"
            )
            PostModeTabPill(
                label = stringResource(id = R.string.post_tab_video),
                iconRes = R.drawable.ic_video_tab,
                leadingChar = null,
                selected = state.mode == PostTabMode.VIDEO,
                onClick = { onSelectMode(PostTabMode.VIDEO) },
                testTag = "post_tab_video"
            )
        }
    }
}

@Composable
private fun PostModeTabPill(
    label: String,
    iconRes: Int?,
    leadingChar: String?,
    selected: Boolean,
    onClick: () -> Unit,
    testTag: String
) {
    val contentColor = if (selected) Color(0xFF121316) else Color.White
    Row(
        modifier = Modifier
            .heightIn(min = 40.dp)
            .clip(RoundedCornerShape(20.dp))
            .background(if (selected) Color.White else Color.Transparent)
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 8.dp)
            .testTag(testTag),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        if (leadingChar != null) {
            Text(
                text = leadingChar,
                style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Bold),
                color = contentColor
            )
        } else if (iconRes != null) {
            Image(
                painter = painterResource(id = iconRes),
                contentDescription = null,
                colorFilter = ColorFilter.tint(contentColor),
                modifier = Modifier.size(18.dp)
            )
        }
        Text(
            text = label,
            style = MaterialTheme.typography.labelLarge.copy(fontSize = 14.sp),
            color = contentColor
        )
    }
}

@Composable
private fun TextComposerCard(
    state: PostComposerState,
    onTextBodyChange: (String) -> Unit,
    modifier: Modifier = Modifier
) {
    val activeTheme = remember(state.selectedImageThemeId) {
        POST_IMAGE_THEMES.firstOrNull { it.id == state.selectedImageThemeId }
    }
    val activeBgOption = remember(state.selectedBgColorHex) {
        POST_BG_COLORS.firstOrNull { it.hex.equals(state.selectedBgColorHex, ignoreCase = true) }
            ?: POST_BG_COLORS.first()
    }
    val textColor = when {
        activeTheme != null -> if (activeTheme.isDarkText) Color(0xFF1C1E22) else Color.White
        activeBgOption.isDarkText -> Color(0xFF1C1E22)
        else -> Color.White
    }

    Box(
        modifier = modifier
            .heightIn(min = 290.dp, max = 330.dp)
            .clip(RoundedCornerShape(20.dp))
            .background(activeBgOption.color),
        contentAlignment = Alignment.Center
    ) {
        if (activeTheme != null) {
            PostThemeArtwork(
                theme = activeTheme,
                modifier = Modifier.matchParentSize()
            )
        }

        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(24.dp),
            contentAlignment = Alignment.Center
        ) {
            if (state.textBody.isEmpty()) {
                Text(
                    text = stringResource(id = R.string.post_text_placeholder),
                    style = TextStyle(
                        fontFamily = state.selectedFont.fontFamily,
                        fontWeight = state.selectedFont.fontWeight,
                        fontStyle = state.selectedFont.fontStyle,
                        fontSize = 24.sp,
                        lineHeight = 32.sp,
                        textAlign = TextAlign.Center
                    ),
                    color = textColor.copy(alpha = 0.72f)
                )
            }
            BasicTextField(
                value = state.textBody,
                onValueChange = onTextBodyChange,
                textStyle = TextStyle(
                    fontFamily = state.selectedFont.fontFamily,
                    fontWeight = state.selectedFont.fontWeight,
                    fontStyle = state.selectedFont.fontStyle,
                    fontSize = 24.sp,
                    lineHeight = 32.sp,
                    color = textColor,
                    textAlign = TextAlign.Center
                ),
                cursorBrush = SolidColor(textColor),
                modifier = Modifier
                    .fillMaxWidth()
                    .testTag("post_text_input")
            )
        }

        Text(
            text = "${state.textBody.length}/280",
            style = MaterialTheme.typography.bodyMedium,
            color = textColor.copy(alpha = 0.78f),
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .padding(16.dp)
        )
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun TextStyleControls(
    state: PostComposerState,
    isDarkTheme: Boolean,
    onTogglePaletteMode: (Boolean) -> Unit,
    onSelectBgColor: (String) -> Unit,
    onSelectImageTheme: (String) -> Unit,
    onSelectFont: (PostFontStyle) -> Unit
) {
    val pillBg = if (isDarkTheme) Color(0xFF1B1D22) else Color(0xFFF3F4F6)
    val pillBorder = MaterialTheme.colorScheme.outlineVariant
    val primary = MaterialTheme.colorScheme.primary

    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            PaletteSwitchChip(
                iconRes = R.drawable.ic_palette,
                label = stringResource(id = R.string.post_colors),
                selected = !state.showImageThemes,
                pillBg = pillBg,
                pillBorder = pillBorder,
                onClick = { onTogglePaletteMode(false) },
                testTag = "palette_colors_tab"
            )
            PaletteSwitchChip(
                iconRes = R.drawable.ic_image_theme,
                label = stringResource(id = R.string.post_themes),
                selected = state.showImageThemes,
                pillBg = pillBg,
                pillBorder = pillBorder,
                onClick = { onTogglePaletteMode(true) },
                testTag = "palette_themes_tab"
            )
        }

        if (!state.showImageThemes) {
            LazyRow(
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                contentPadding = PaddingValues(horizontal = 2.dp)
            ) {
                items(POST_BG_COLORS, key = { it.hex }) { opt ->
                    val selected = state.selectedImageThemeId == null &&
                        state.selectedBgColorHex.equals(opt.hex, ignoreCase = true)
                    Box(
                        modifier = Modifier
                            .size(44.dp)
                            .clip(CircleShape)
                            .background(opt.color)
                            .border(
                                width = if (selected) 2.5.dp else 1.dp,
                                color = if (selected) Color.White else MaterialTheme.colorScheme.outlineVariant,
                                shape = CircleShape
                            )
                            .clickable { onSelectBgColor(opt.hex) }
                            .testTag("bg_color_${opt.hex}"),
                        contentAlignment = Alignment.Center
                    ) {
                        if (selected) {
                            Image(
                                painter = painterResource(id = R.drawable.ic_check),
                                contentDescription = "Selected",
                                colorFilter = ColorFilter.tint(if (opt.isDarkText) Color(0xFF121316) else Color.White),
                                modifier = Modifier.size(18.dp)
                            )
                        }
                    }
                }
            }
        } else {
            LazyRow(
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                contentPadding = PaddingValues(horizontal = 2.dp)
            ) {
                items(POST_IMAGE_THEMES, key = { it.id }) { theme ->
                    val selected = state.selectedImageThemeId == theme.id
                    Box(
                        modifier = Modifier
                            .size(48.dp)
                            .clip(CircleShape)
                            .border(
                                width = if (selected) 2.5.dp else 1.dp,
                                color = if (selected) Color.White else MaterialTheme.colorScheme.outlineVariant,
                                shape = CircleShape
                            )
                            .clickable { onSelectImageTheme(theme.id) }
                            .testTag("bg_theme_${theme.id}"),
                        contentAlignment = Alignment.Center
                    ) {
                        PostThemeArtwork(theme = theme, modifier = Modifier.matchParentSize())
                        if (selected) {
                            Image(
                                painter = painterResource(id = R.drawable.ic_check),
                                contentDescription = theme.name,
                                modifier = Modifier.size(18.dp)
                            )
                        }
                    }
                }
            }
        }

        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            PostFontStyle.entries.forEach { font ->
                val isSelected = state.selectedFont == font
                Row(
                    modifier = Modifier
                        .heightIn(min = 38.dp)
                        .clip(RoundedCornerShape(10.dp))
                        .background(
                            if (isSelected) primary.copy(alpha = 0.14f) else pillBg
                        )
                        .border(
                            width = 1.dp,
                            color = if (isSelected) primary else pillBorder,
                            shape = RoundedCornerShape(10.dp)
                        )
                        .clickable { onSelectFont(font) }
                        .padding(horizontal = 13.dp, vertical = 8.dp)
                        .testTag("font_pill_${font.id}"),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Text(
                        text = font.badge,
                        style = TextStyle(
                            fontFamily = font.fontFamily,
                            fontWeight = font.fontWeight,
                            fontStyle = font.fontStyle,
                            fontSize = 13.sp
                        ),
                        color = if (isSelected) primary else MaterialTheme.colorScheme.onSurface
                    )
                    Text(
                        text = font.label,
                        style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Medium),
                        color = if (isSelected) primary else MaterialTheme.colorScheme.onSurface
                    )
                }
            }
        }
    }
}

@Composable
private fun PaletteSwitchChip(
    iconRes: Int,
    label: String,
    selected: Boolean,
    pillBg: Color,
    pillBorder: Color,
    onClick: () -> Unit,
    testTag: String
) {
    val primary = MaterialTheme.colorScheme.primary
    val fg = if (selected) primary else MaterialTheme.colorScheme.onSurfaceVariant
    Row(
        modifier = Modifier
            .heightIn(min = 36.dp)
            .clip(RoundedCornerShape(18.dp))
            .background(if (selected) primary.copy(alpha = 0.14f) else pillBg)
            .border(1.dp, if (selected) primary else pillBorder, RoundedCornerShape(18.dp))
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 6.dp)
            .testTag(testTag),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Image(
            painter = painterResource(id = iconRes),
            contentDescription = null,
            colorFilter = ColorFilter.tint(fg),
            modifier = Modifier.size(16.dp)
        )
        Text(
            text = label,
            style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.SemiBold),
            color = fg
        )
    }
}

@Composable
private fun PhotosComposerCard(
    state: PostComposerState,
    isDarkTheme: Boolean,
    onPickPhotos: () -> Unit,
    onRemovePhoto: (Uri) -> Unit,
    modifier: Modifier = Modifier
) {
    val cardBg = if (isDarkTheme) Color(0xFF1B1D22) else Color(0xFFF6F7F9)
    val primary = MaterialTheme.colorScheme.primary

    if (state.selectedPhotos.isEmpty()) {
        Box(
            modifier = modifier
                .height(290.dp)
                .clip(RoundedCornerShape(20.dp))
                .background(cardBg)
                .border(1.dp, MaterialTheme.colorScheme.outlineVariant, RoundedCornerShape(20.dp))
                .clickable(onClick = onPickPhotos)
                .testTag("add_photos_card"),
            contentAlignment = Alignment.Center
        ) {
            if (state.isExtractingMedia) {
                CircularProgressIndicator(color = primary)
            } else {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Box(
                        modifier = Modifier
                            .size(58.dp)
                            .clip(CircleShape)
                            .background(primary.copy(alpha = 0.16f)),
                        contentAlignment = Alignment.Center
                    ) {
                        Image(
                            painter = painterResource(id = R.drawable.ic_photos_tab),
                            contentDescription = stringResource(id = R.string.post_add_photos),
                            colorFilter = ColorFilter.tint(primary),
                            modifier = Modifier.size(28.dp)
                        )
                    }
                    Spacer(modifier = Modifier.height(14.dp))
                    Text(
                        text = stringResource(id = R.string.post_add_photos),
                        style = MaterialTheme.typography.titleMedium,
                        color = MaterialTheme.colorScheme.onBackground
                    )
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(
                        text = stringResource(id = R.string.post_up_to_10),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }
    } else {
        Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(10.dp)) {
            LazyRow(
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                contentPadding = PaddingValues(horizontal = 2.dp)
            ) {
                items(state.selectedPhotos, key = { it.uri.toString() }) { item ->
                    Box(
                        modifier = Modifier
                            .size(width = 180.dp, height = 240.dp)
                            .clip(RoundedCornerShape(16.dp))
                            .background(cardBg)
                    ) {
                        Image(
                            bitmap = item.thumbnail.asImageBitmap(),
                            contentDescription = null,
                            contentScale = ContentScale.Crop,
                            modifier = Modifier.fillMaxSize()
                        )
                        IconButton(
                            onClick = { onRemovePhoto(item.uri) },
                            modifier = Modifier
                                .align(Alignment.TopEnd)
                                .padding(6.dp)
                                .size(32.dp)
                                .clip(CircleShape)
                                .background(Color.Black.copy(alpha = 0.65f))
                        ) {
                            Image(
                                painter = painterResource(id = R.drawable.ic_close_white),
                                contentDescription = "Remove photo",
                                modifier = Modifier.size(16.dp)
                            )
                        }
                    }
                }
                if (state.selectedPhotos.size < 10) {
                    item(key = "add_more_photos") {
                        Box(
                            modifier = Modifier
                                .size(width = 110.dp, height = 240.dp)
                                .clip(RoundedCornerShape(16.dp))
                                .background(cardBg)
                                .border(1.dp, MaterialTheme.colorScheme.outlineVariant, RoundedCornerShape(16.dp))
                                .clickable(onClick = onPickPhotos)
                                .testTag("add_more_photos_button"),
                            contentAlignment = Alignment.Center
                        ) {
                            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                Image(
                                    painter = painterResource(id = R.drawable.ic_add),
                                    contentDescription = stringResource(id = R.string.post_add_photos),
                                    colorFilter = ColorFilter.tint(primary),
                                    modifier = Modifier.size(28.dp)
                                )
                                Spacer(modifier = Modifier.height(6.dp))
                                Text(
                                    text = "${state.selectedPhotos.size}/10",
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun VideoComposerCard(
    state: PostComposerState,
    isDarkTheme: Boolean,
    onPickVideo: () -> Unit,
    onClearVideo: () -> Unit,
    onUpdateTrim: (Long, Long) -> Unit,
    onSelectThumbFrame: (VideoFrameItem) -> Unit,
    onAutoSelectThumb: () -> Unit,
    onToggleMuteAudio: () -> Unit,
    modifier: Modifier = Modifier
) {
    val cardBg = if (isDarkTheme) Color(0xFF1B1D22) else Color(0xFFF6F7F9)
    val primary = MaterialTheme.colorScheme.primary

    if (state.videoUri == null) {
        Box(
            modifier = modifier
                .height(290.dp)
                .clip(RoundedCornerShape(20.dp))
                .background(cardBg)
                .border(1.dp, MaterialTheme.colorScheme.outlineVariant, RoundedCornerShape(20.dp))
                .clickable(onClick = onPickVideo)
                .testTag("add_video_card"),
            contentAlignment = Alignment.Center
        ) {
            if (state.isExtractingMedia) {
                CircularProgressIndicator(color = primary)
            } else {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Box(
                        modifier = Modifier
                            .size(58.dp)
                            .clip(CircleShape)
                            .background(primary.copy(alpha = 0.16f)),
                        contentAlignment = Alignment.Center
                    ) {
                        Image(
                            painter = painterResource(id = R.drawable.ic_clapperboard),
                            contentDescription = stringResource(id = R.string.post_add_video),
                            modifier = Modifier.size(28.dp)
                        )
                    }
                    Spacer(modifier = Modifier.height(14.dp))
                    Text(
                        text = stringResource(id = R.string.post_add_video),
                        style = MaterialTheme.typography.titleMedium,
                        color = MaterialTheme.colorScheme.onBackground
                    )
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(
                        text = state.inlineError ?: stringResource(id = R.string.post_up_to_200_mb),
                        style = MaterialTheme.typography.bodyMedium,
                        color = if (state.inlineError != null) primary else MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }
    } else {
        Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(240.dp)
                    .clip(RoundedCornerShape(20.dp))
                    .background(Color.Black)
            ) {
                val thumb = state.selectedThumbBitmap
                if (thumb != null) {
                    Image(
                        bitmap = thumb.asImageBitmap(),
                        contentDescription = null,
                        contentScale = ContentScale.Crop,
                        modifier = Modifier.fillMaxSize()
                    )
                }
                Row(
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .padding(10.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Surface(
                        shape = RoundedCornerShape(16.dp),
                        color = Color.Black.copy(alpha = 0.65f),
                        modifier = Modifier
                            .heightIn(min = 34.dp)
                            .clip(RoundedCornerShape(16.dp))
                            .clickable(onClick = onAutoSelectThumb)
                            .testTag("auto_thumb_button")
                    ) {
                        Row(
                            modifier = Modifier.padding(horizontal = 10.dp, vertical = 6.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(4.dp)
                        ) {
                            Image(
                                painter = painterResource(id = R.drawable.ic_auto_sparkle),
                                contentDescription = null,
                                modifier = Modifier.size(14.dp)
                            )
                            Text(
                                text = stringResource(id = R.string.post_auto_thumb),
                                style = MaterialTheme.typography.labelSmall,
                                color = Color.White
                            )
                        }
                    }

                    IconButton(
                        onClick = onClearVideo,
                        modifier = Modifier
                            .size(34.dp)
                            .clip(CircleShape)
                            .background(Color.Black.copy(alpha = 0.65f))
                    ) {
                        Image(
                            painter = painterResource(id = R.drawable.ic_close_white),
                            contentDescription = "Remove video",
                            modifier = Modifier.size(16.dp)
                        )
                    }
                }

                Box(
                    modifier = Modifier
                        .align(Alignment.BottomStart)
                        .padding(12.dp)
                        .clip(RoundedCornerShape(12.dp))
                        .background(Color.Black.copy(alpha = 0.65f))
                        .padding(horizontal = 10.dp, vertical = 4.dp)
                ) {
                    Text(
                        text = "${formatDurationMs(state.trimStartMs)} – ${formatDurationMs(state.trimEndMs)}",
                        style = MaterialTheme.typography.labelSmall,
                        color = Color.White
                    )
                }
            }

            if (state.videoFrames.isNotEmpty()) {
                LazyRow(
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    items(state.videoFrames, key = { it.timestampMs }) { frame ->
                        val isSelectedThumb = frame.timestampMs == state.selectedThumbTimestampMs
                        Box(
                            modifier = Modifier
                                .size(width = 62.dp, height = 54.dp)
                                .clip(RoundedCornerShape(8.dp))
                                .border(
                                    width = if (isSelectedThumb) 2.5.dp else 1.dp,
                                    color = if (isSelectedThumb) primary else MaterialTheme.colorScheme.outlineVariant,
                                    shape = RoundedCornerShape(8.dp)
                                )
                                .clickable { onSelectThumbFrame(frame) }
                                .testTag("video_frame_${frame.timestampMs}")
                        ) {
                            Image(
                                bitmap = frame.thumbnail.asImageBitmap(),
                                contentDescription = null,
                                contentScale = ContentScale.Crop,
                                modifier = Modifier.fillMaxSize()
                            )
                        }
                    }
                }
            }

            if (state.videoDurationMs > 500L) {
                RangeSlider(
                    value = state.trimStartMs.toFloat()..state.trimEndMs.toFloat(),
                    onValueChange = { range ->
                        onUpdateTrim(range.start.roundToLong(), range.endInclusive.roundToLong())
                    },
                    valueRange = 0f..state.videoDurationMs.toFloat(),
                    colors = SliderDefaults.colors(
                        thumbColor = primary,
                        activeTrackColor = primary,
                        inactiveTrackColor = MaterialTheme.colorScheme.outlineVariant
                    ),
                    modifier = Modifier
                        .fillMaxWidth()
                        .testTag("video_trim_slider")
                )
            }

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(14.dp))
                    .background(cardBg)
                    .border(1.dp, MaterialTheme.colorScheme.outlineVariant, RoundedCornerShape(14.dp))
                    .padding(horizontal = 14.dp, vertical = 6.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    Image(
                        painter = painterResource(
                            id = if (state.muteOriginalAudio) R.drawable.ic_volume_off else R.drawable.ic_volume_on
                        ),
                        contentDescription = null,
                        colorFilter = ColorFilter.tint(MaterialTheme.colorScheme.onBackground),
                        modifier = Modifier.size(18.dp)
                    )
                    Text(
                        text = stringResource(id = R.string.post_mute_audio),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onBackground
                    )
                }
                Switch(
                    checked = state.muteOriginalAudio,
                    onCheckedChange = { onToggleMuteAudio() },
                    colors = SwitchDefaults.colors(checkedTrackColor = primary),
                    modifier = Modifier.testTag("mute_audio_switch")
                )
            }
        }
    }
}

@Composable
private fun CaptionInputCard(
    caption: String,
    isDarkTheme: Boolean,
    onCaptionChange: (String) -> Unit
) {
    val cardBg = if (isDarkTheme) Color(0xFF1B1D22) else Color(0xFFF6F7F9)
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 112.dp)
            .clip(RoundedCornerShape(16.dp))
            .background(cardBg)
            .border(1.dp, MaterialTheme.colorScheme.outlineVariant, RoundedCornerShape(16.dp))
            .padding(14.dp)
    ) {
        if (caption.isEmpty()) {
            Text(
                text = stringResource(id = R.string.post_caption_hint),
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        BasicTextField(
            value = caption,
            onValueChange = onCaptionChange,
            textStyle = MaterialTheme.typography.bodyLarge.copy(
                color = MaterialTheme.colorScheme.onBackground
            ),
            cursorBrush = SolidColor(MaterialTheme.colorScheme.primary),
            modifier = Modifier
                .fillMaxWidth()
                .padding(bottom = 20.dp)
                .testTag("post_caption_input")
        )
        Text(
            text = "${caption.length}/2200",
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.align(Alignment.BottomEnd)
        )
    }
}

@Composable
private fun PostMetadataOptionsCard(
    state: PostComposerState,
    isDarkTheme: Boolean,
    onOpenSong: () -> Unit,
    onToggleSongPreview: (MusicTrackDto) -> Unit,
    onOpenTagPeople: () -> Unit,
    onOpenHashtags: () -> Unit
) {
    val cardBg = if (isDarkTheme) Color(0xFF1B1D22) else Color(0xFFF6F7F9)
    val primary = MaterialTheme.colorScheme.primary

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(cardBg)
            .border(1.dp, MaterialTheme.colorScheme.outlineVariant, RoundedCornerShape(16.dp))
    ) {
        val song = state.selectedSong
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 54.dp)
                .clickable(onClick = onOpenSong)
                .padding(horizontal = 14.dp, vertical = 10.dp)
                .testTag("post_song_row"),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Box(
                modifier = Modifier
                    .size(34.dp)
                    .clip(CircleShape)
                    .background(primary.copy(alpha = 0.16f)),
                contentAlignment = Alignment.Center
            ) {
                Image(
                    painter = painterResource(id = R.drawable.ic_music_note),
                    contentDescription = null,
                    modifier = Modifier.size(18.dp)
                )
            }
            Spacer(modifier = Modifier.width(12.dp))
            Text(
                text = song?.title ?: stringResource(id = R.string.post_song),
                style = MaterialTheme.typography.titleMedium.copy(fontSize = 15.sp),
                color = MaterialTheme.colorScheme.onBackground,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f)
            )
            if (song != null && song.previewUrl.isNotBlank()) {
                val playingThis = state.isPlayingSongPreview && state.previewingTrackId == song.trackId
                IconButton(
                    onClick = { onToggleSongPreview(song) },
                    modifier = Modifier
                        .size(36.dp)
                        .clip(CircleShape)
                        .background(primary)
                        .testTag("selected_song_preview_button")
                ) {
                    Image(
                        painter = painterResource(
                            id = if (playingThis) R.drawable.ic_pause else R.drawable.ic_play_arrow
                        ),
                        contentDescription = if (playingThis) "Pause" else "Play",
                        modifier = Modifier.size(16.dp)
                    )
                }
                Spacer(modifier = Modifier.width(6.dp))
            } else {
                Text(
                    text = stringResource(id = R.string.post_add_action),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Spacer(modifier = Modifier.width(4.dp))
                Image(
                    painter = painterResource(id = R.drawable.ic_chevron_right),
                    contentDescription = null,
                    colorFilter = ColorFilter.tint(MaterialTheme.colorScheme.onSurfaceVariant),
                    modifier = Modifier.size(16.dp)
                )
            }
        }

        HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)

        PostOptionRow(
            iconRes = R.drawable.ic_person_add_white,
            iconTint = primary,
            title = stringResource(id = R.string.post_tag_people),
            trailingText = if (state.taggedContacts.isEmpty()) {
                stringResource(id = R.string.post_add_action)
            } else {
                "${state.taggedContacts.size}"
            },
            onClick = onOpenTagPeople,
            testTag = "post_tag_people_row"
        )

        if (state.mode != PostTabMode.TEXT) {
            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
            PostOptionRow(
                iconRes = R.drawable.ic_hashtag,
                iconTint = null,
                title = stringResource(id = R.string.post_hashtags),
                trailingText = if (state.selectedHashtags.isEmpty()) {
                    stringResource(id = R.string.post_add_action)
                } else {
                    state.selectedHashtags.joinToString(" ") { "#$it" }
                },
                onClick = onOpenHashtags,
                testTag = "post_hashtags_row"
            )
        }
    }
}

@Composable
private fun PostOptionRow(
    iconRes: Int,
    iconTint: Color?,
    title: String,
    trailingText: String,
    onClick: () -> Unit,
    testTag: String
) {
    val primary = MaterialTheme.colorScheme.primary
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 54.dp)
            .clickable(onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 10.dp)
            .testTag(testTag),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier
                .size(34.dp)
                .clip(CircleShape)
                .background(primary.copy(alpha = 0.16f)),
            contentAlignment = Alignment.Center
        ) {
            Image(
                painter = painterResource(id = iconRes),
                contentDescription = null,
                colorFilter = iconTint?.let { ColorFilter.tint(it) },
                modifier = Modifier.size(18.dp)
            )
        }
        Spacer(modifier = Modifier.width(12.dp))
        Text(
            text = title,
            style = MaterialTheme.typography.titleMedium.copy(fontSize = 15.sp),
            color = MaterialTheme.colorScheme.onBackground,
            modifier = Modifier.weight(1f)
        )
        Text(
            text = trailingText,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.widthIn(max = 140.dp)
        )
        Spacer(modifier = Modifier.width(4.dp))
        Image(
            painter = painterResource(id = R.drawable.ic_chevron_right),
            contentDescription = null,
            colorFilter = ColorFilter.tint(MaterialTheme.colorScheme.onSurfaceVariant),
            modifier = Modifier.size(16.dp)
        )
    }
}

private fun formatDurationMs(ms: Long): String {
    val totalSec = (ms / 1000L).coerceAtLeast(0L)
    val min = totalSec / 60L
    val sec = totalSec % 60L
    return "%d:%02d".format(min, sec)
}
