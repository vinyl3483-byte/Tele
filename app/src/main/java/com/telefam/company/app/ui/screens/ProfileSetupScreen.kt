package com.telefam.company.app.ui.screens

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Matrix
import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.SelectableDates
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.telefam.company.app.R
import com.telefam.company.app.ui.ProfileSetupState
import com.telefam.company.app.ui.SUPPORTED_COUNTRIES
import com.telefam.company.app.ui.components.swipeBackEdge
import java.util.Calendar
import java.util.TimeZone
import kotlin.math.max
import kotlin.math.min

private val GENDER_OPTIONS = listOf(
    "male" to "Male",
    "female" to "Female",
    "non_binary" to "Non-binary",
    "prefer_not_to_say" to "Prefer not to say"
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProfileSetupScreen(
    state: ProfileSetupState,
    onUpdateField: ((ProfileSetupState) -> ProfileSetupState) -> Unit,
    onAvatarCropped: (Bitmap) -> Unit,
    onSubmit: () -> Unit,
    onBack: () -> Unit
) {
    val context = LocalContext.current
    var pendingCropBitmap by remember { mutableStateOf<Bitmap?>(null) }
    var showCountryMenu by remember { mutableStateOf(false) }
    var showGenderMenu by remember { mutableStateOf(false) }
    var showDobPicker by remember { mutableStateOf(false) }

    BackHandler { onBack() }

    val photoPickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.PickVisualMedia()
    ) { uri: Uri? ->
        if (uri != null) {
            decodeSampledBitmap(context, uri, maxDim = 1024)?.let { bmp ->
                pendingCropBitmap = bmp
            }
        }
    }

    val selectedCountry = remember(state.countryIso) {
        SUPPORTED_COUNTRIES.firstOrNull { it.iso == state.countryIso } ?: SUPPORTED_COUNTRIES.first()
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.primary)
            .swipeBackEdge { onBack() }
            .windowInsetsPadding(WindowInsets.statusBars)
            .windowInsetsPadding(WindowInsets.navigationBars)
            .imePadding()
    ) {
        // Red Header matching reference
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 8.dp, vertical = 12.dp)
        ) {
            IconButton(
                onClick = onBack,
                modifier = Modifier
                    .align(Alignment.CenterStart)
                    .size(48.dp)
                    .testTag("profile_back_button")
            ) {
                Image(
                    painter = painterResource(id = R.drawable.ic_back_white),
                    contentDescription = "Back",
                    modifier = Modifier.size(22.dp)
                )
            }
            Column(
                modifier = Modifier.align(Alignment.Center),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Text(
                    text = stringResource(id = R.string.profile_setup_title),
                    style = MaterialTheme.typography.titleLarge,
                    color = Color.White
                )
                Spacer(modifier = Modifier.height(2.dp))
                Text(
                    text = stringResource(id = R.string.profile_setup_subtitle),
                    style = MaterialTheme.typography.bodyMedium,
                    color = Color.White.copy(alpha = 0.9f)
                )
            }
        }

        // Rounded Sheet Body
        Box(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth()
                .clip(RoundedCornerShape(topStart = 24.dp, topEnd = 24.dp))
                .background(MaterialTheme.colorScheme.surface),
            contentAlignment = Alignment.TopCenter
        ) {
            Column(
                modifier = Modifier
                    .widthIn(max = 520.dp)
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 22.dp, vertical = 22.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                // Avatar Picker
                val primaryColor = MaterialTheme.colorScheme.primary
                val softTint = MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.55f)
                Box(
                    modifier = Modifier
                        .size(102.dp)
                        .clickable {
                            photoPickerLauncher.launch(
                                PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)
                            )
                        }
                        .testTag("avatar_picker_button"),
                    contentAlignment = Alignment.Center
                ) {
                    if (state.avatarBitmap != null) {
                        Image(
                            bitmap = state.avatarBitmap.asImageBitmap(),
                            contentDescription = stringResource(id = R.string.profile_upload_title),
                            contentScale = ContentScale.Crop,
                            modifier = Modifier
                                .size(96.dp)
                                .clip(CircleShape)
                                .border(2.dp, primaryColor, CircleShape)
                        )
                    } else {
                        Box(
                            modifier = Modifier
                                .size(96.dp)
                                .clip(CircleShape)
                                .background(softTint),
                            contentAlignment = Alignment.Center
                        ) {
                            Canvas(modifier = Modifier.fillMaxSize()) {
                                drawCircle(
                                    color = primaryColor.copy(alpha = 0.7f),
                                    style = Stroke(
                                        width = 2.dp.toPx(),
                                        pathEffect = PathEffect.dashPathEffect(floatArrayOf(10f, 8f), 0f)
                                    )
                                )
                            }
                            Image(
                                painter = painterResource(id = R.drawable.ic_camera),
                                contentDescription = stringResource(id = R.string.profile_upload_title),
                                modifier = Modifier.size(34.dp)
                            )
                        }
                    }

                    Box(
                        modifier = Modifier
                            .align(Alignment.BottomEnd)
                            .padding(2.dp)
                            .size(28.dp)
                            .clip(CircleShape)
                            .background(primaryColor)
                            .border(2.dp, MaterialTheme.colorScheme.surface, CircleShape),
                        contentAlignment = Alignment.Center
                    ) {
                        Image(
                            painter = painterResource(id = R.drawable.ic_add),
                            contentDescription = null,
                            modifier = Modifier.size(15.dp)
                        )
                    }
                }

                Spacer(modifier = Modifier.height(10.dp))
                Text(
                    text = stringResource(id = R.string.profile_upload_title),
                    style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.onSurface
                )
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = stringResource(id = R.string.profile_upload_subtitle),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center
                )

                Spacer(modifier = Modifier.height(22.dp))

                // Full Name
                ProfileFieldLabel(
                    iconRes = R.drawable.ic_person_red,
                    label = stringResource(id = R.string.profile_full_name)
                )
                OutlinedTextField(
                    value = state.fullName,
                    onValueChange = { v -> onUpdateField { it.copy(fullName = v) } },
                    placeholder = { Text(stringResource(id = R.string.profile_full_name_hint)) },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words),
                    shape = RoundedCornerShape(10.dp),
                    colors = profileTextFieldColors(),
                    modifier = Modifier
                        .fillMaxWidth()
                        .testTag("profile_fullname_input")
                )

                Spacer(modifier = Modifier.height(14.dp))

                // Username
                ProfileFieldLabel(
                    iconRes = R.drawable.ic_at_red,
                    label = stringResource(id = R.string.profile_username)
                )
                OutlinedTextField(
                    value = state.username,
                    onValueChange = { v ->
                        val cleaned = v.lowercase().filter { it.isLetterOrDigit() || it == '_' }.take(30)
                        onUpdateField { it.copy(username = cleaned) }
                    },
                    placeholder = { Text(stringResource(id = R.string.profile_username_hint)) },
                    singleLine = true,
                    shape = RoundedCornerShape(10.dp),
                    colors = profileTextFieldColors(),
                    modifier = Modifier
                        .fillMaxWidth()
                        .testTag("profile_username_input")
                )

                Spacer(modifier = Modifier.height(14.dp))

                // Phone Number with Country Flag Picker
                ProfileFieldLabel(
                    iconRes = R.drawable.ic_phone_red,
                    label = stringResource(id = R.string.profile_phone)
                )
                Box(modifier = Modifier.fillMaxWidth()) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(54.dp)
                            .border(1.dp, MaterialTheme.colorScheme.outline, RoundedCornerShape(10.dp))
                            .clip(RoundedCornerShape(10.dp)),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Row(
                            modifier = Modifier
                                .height(54.dp)
                                .clickable { showCountryMenu = true }
                                .padding(horizontal = 12.dp)
                                .testTag("profile_country_picker"),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(6.dp)
                        ) {
                            Text(text = selectedCountry.flag, fontSize = 20.sp)
                            Image(
                                painter = painterResource(id = R.drawable.ic_chevron_down),
                                contentDescription = null,
                                modifier = Modifier.size(16.dp)
                            )
                        }
                        Box(
                            modifier = Modifier
                                .width(1.dp)
                                .height(32.dp)
                                .background(MaterialTheme.colorScheme.outlineVariant)
                        )
                        BasicTextField(
                            value = state.phoneNumber,
                            onValueChange = { v ->
                                val filtered = v.filter { it.isDigit() || it == ' ' || it == '-' }.take(16)
                                onUpdateField { it.copy(phoneNumber = filtered) }
                            },
                            singleLine = true,
                            textStyle = MaterialTheme.typography.bodyLarge.copy(
                                color = MaterialTheme.colorScheme.onSurface
                            ),
                            cursorBrush = SolidColor(MaterialTheme.colorScheme.primary),
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone),
                            decorationBox = { innerTextField ->
                                Box(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(horizontal = 12.dp),
                                    contentAlignment = Alignment.CenterStart
                                ) {
                                    if (state.phoneNumber.isEmpty()) {
                                        Text(
                                            text = "${selectedCountry.dialCode}  ${stringResource(id = R.string.profile_phone_hint)}",
                                            style = MaterialTheme.typography.bodyLarge,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant
                                        )
                                    }
                                    innerTextField()
                                }
                            },
                            modifier = Modifier
                                .weight(1f)
                                .testTag("profile_phone_input")
                        )
                    }

                    DropdownMenu(
                        expanded = showCountryMenu,
                        onDismissRequest = { showCountryMenu = false }
                    ) {
                        SUPPORTED_COUNTRIES.forEach { option ->
                            DropdownMenuItem(
                                text = {
                                    Text("${option.flag}  ${option.name} (${option.dialCode})")
                                },
                                onClick = {
                                    onUpdateField { it.copy(countryIso = option.iso) }
                                    showCountryMenu = false
                                }
                            )
                        }
                    }
                }

                Spacer(modifier = Modifier.height(14.dp))

                // Gender Dropdown
                ProfileFieldLabel(
                    iconRes = R.drawable.ic_group_red,
                    label = stringResource(id = R.string.profile_gender)
                )
                val genderLabel = GENDER_OPTIONS.firstOrNull { it.first == state.gender }?.second.orEmpty()
                Box(modifier = Modifier.fillMaxWidth()) {
                    ProfileSelectorField(
                        value = genderLabel,
                        placeholder = stringResource(id = R.string.profile_gender_hint),
                        onClick = { showGenderMenu = true },
                        modifier = Modifier.testTag("profile_gender_selector")
                    )
                    DropdownMenu(
                        expanded = showGenderMenu,
                        onDismissRequest = { showGenderMenu = false }
                    ) {
                        GENDER_OPTIONS.forEach { (key, label) ->
                            DropdownMenuItem(
                                text = { Text(label) },
                                onClick = {
                                    onUpdateField { it.copy(gender = key) }
                                    showGenderMenu = false
                                }
                            )
                        }
                    }
                }

                Spacer(modifier = Modifier.height(14.dp))

                // Date of Birth (13+ only)
                ProfileFieldLabel(
                    iconRes = R.drawable.ic_calendar_red,
                    label = stringResource(id = R.string.profile_dob)
                )
                val dobText = if (state.birthYear != null && state.birthMonth != null && state.birthDay != null) {
                    "%04d-%02d-%02d".format(state.birthYear, state.birthMonth, state.birthDay)
                } else ""
                ProfileSelectorField(
                    value = dobText,
                    placeholder = stringResource(id = R.string.profile_dob_hint),
                    onClick = { showDobPicker = true },
                    modifier = Modifier.testTag("profile_dob_selector")
                )

                Spacer(modifier = Modifier.height(14.dp))

                // Location
                ProfileFieldLabel(
                    iconRes = R.drawable.ic_location_red,
                    label = stringResource(id = R.string.profile_location)
                )
                OutlinedTextField(
                    value = state.location,
                    onValueChange = { v -> onUpdateField { it.copy(location = v.take(100)) } },
                    placeholder = { Text(stringResource(id = R.string.profile_location_hint)) },
                    singleLine = true,
                    shape = RoundedCornerShape(10.dp),
                    colors = profileTextFieldColors(),
                    modifier = Modifier
                        .fillMaxWidth()
                        .testTag("profile_location_input")
                )

                Spacer(modifier = Modifier.height(14.dp))

                // Bio with 0/150 counter
                ProfileFieldLabel(
                    iconRes = R.drawable.ic_bio_red,
                    label = stringResource(id = R.string.profile_bio)
                )
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(112.dp)
                        .border(1.dp, MaterialTheme.colorScheme.outline, RoundedCornerShape(10.dp))
                        .padding(horizontal = 14.dp, vertical = 12.dp)
                ) {
                    BasicTextField(
                        value = state.bio,
                        onValueChange = { v -> onUpdateField { it.copy(bio = v.take(150)) } },
                        textStyle = MaterialTheme.typography.bodyLarge.copy(
                            color = MaterialTheme.colorScheme.onSurface
                        ),
                        cursorBrush = SolidColor(MaterialTheme.colorScheme.primary),
                        decorationBox = { innerTextField ->
                            Box(modifier = Modifier.fillMaxSize()) {
                                if (state.bio.isEmpty()) {
                                    Text(
                                        text = stringResource(id = R.string.profile_bio_hint),
                                        style = MaterialTheme.typography.bodyLarge,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }
                                innerTextField()
                            }
                        },
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(bottom = 18.dp)
                            .testTag("profile_bio_input")
                    )
                    Text(
                        text = "${state.bio.length}/150",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.align(Alignment.BottomEnd)
                    )
                }

                if (!state.errorMessage.isNullOrBlank()) {
                    Spacer(modifier = Modifier.height(10.dp))
                    Text(
                        text = state.errorMessage,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.error,
                        modifier = Modifier
                            .fillMaxWidth()
                            .testTag("profile_error_text")
                    )
                }

                Spacer(modifier = Modifier.height(22.dp))

                Button(
                    onClick = onSubmit,
                    enabled = !state.isSubmitting,
                    shape = RoundedCornerShape(10.dp),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = MaterialTheme.colorScheme.primary,
                        contentColor = Color.White
                    ),
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(50.dp)
                        .testTag("profile_continue_button")
                ) {
                    if (state.isSubmitting) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(20.dp),
                            color = Color.White,
                            strokeWidth = 2.dp
                        )
                    } else {
                        Text(
                            text = stringResource(id = R.string.profile_continue),
                            style = MaterialTheme.typography.labelLarge
                        )
                    }
                }

                Spacer(modifier = Modifier.height(12.dp))
            }
        }
    }

    if (showDobPicker) {
        val maxCal = remember {
            Calendar.getInstance(TimeZone.getTimeZone("UTC")).apply {
                add(Calendar.YEAR, -13)
            }
        }
        val maxMillis = maxCal.timeInMillis
        val datePickerState = rememberDatePickerState(
            initialSelectedDateMillis = maxMillis,
            selectableDates = object : SelectableDates {
                override fun isSelectableDate(utcTimeMillis: Long): Boolean = utcTimeMillis <= maxMillis
            }
        )
        DatePickerDialog(
            onDismissRequest = { showDobPicker = false },
            confirmButton = {
                TextButton(
                    onClick = {
                        val ms = datePickerState.selectedDateMillis
                        if (ms != null) {
                            val c = Calendar.getInstance(TimeZone.getTimeZone("UTC")).apply {
                                timeInMillis = ms
                            }
                            onUpdateField {
                                it.copy(
                                    birthYear = c.get(Calendar.YEAR),
                                    birthMonth = c.get(Calendar.MONTH) + 1,
                                    birthDay = c.get(Calendar.DAY_OF_MONTH)
                                )
                            }
                        }
                        showDobPicker = false
                    }
                ) {
                    Text("OK")
                }
            },
            dismissButton = {
                TextButton(onClick = { showDobPicker = false }) {
                    Text("Cancel")
                }
            }
        ) {
            DatePicker(state = datePickerState)
        }
    }

    pendingCropBitmap?.let { sourceBmp ->
        ProfilePhotoCropDialog(
            source = sourceBmp,
            onDismiss = { pendingCropBitmap = null },
            onApply = { cropped ->
                pendingCropBitmap = null
                onAvatarCropped(cropped)
            }
        )
    }
}

@Composable
private fun ProfileFieldLabel(iconRes: Int, label: String) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(bottom = 6.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Image(
            painter = painterResource(id = iconRes),
            contentDescription = null,
            modifier = Modifier.size(16.dp)
        )
        Spacer(modifier = Modifier.width(8.dp))
        Text(
            text = label,
            style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.SemiBold),
            color = MaterialTheme.colorScheme.onSurface
        )
    }
}

@Composable
private fun ProfileSelectorField(
    value: String,
    placeholder: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .height(54.dp)
            .border(1.dp, MaterialTheme.colorScheme.outline, RoundedCornerShape(10.dp))
            .clip(RoundedCornerShape(10.dp))
            .clickable(onClick = onClick)
            .padding(horizontal = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text(
            text = value.ifEmpty { placeholder },
            style = MaterialTheme.typography.bodyLarge,
            color = if (value.isEmpty()) MaterialTheme.colorScheme.onSurfaceVariant
            else MaterialTheme.colorScheme.onSurface
        )
        Image(
            painter = painterResource(id = R.drawable.ic_chevron_down),
            contentDescription = null,
            modifier = Modifier.size(18.dp)
        )
    }
}

@Composable
private fun profileTextFieldColors() = OutlinedTextFieldDefaults.colors(
    focusedBorderColor = MaterialTheme.colorScheme.primary,
    unfocusedBorderColor = MaterialTheme.colorScheme.outline,
    focusedTextColor = MaterialTheme.colorScheme.onSurface,
    unfocusedTextColor = MaterialTheme.colorScheme.onSurface
)

@Composable
internal fun ProfilePhotoCropDialog(
    source: Bitmap,
    onDismiss: () -> Unit,
    onApply: (Bitmap) -> Unit
) {
    val cropBoxDp = 250.dp
    val cropBoxPx = with(LocalDensity.current) { cropBoxDp.toPx() }
    var scale by remember { mutableFloatStateOf(1f) }
    var offset by remember { mutableStateOf(Offset.Zero) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(id = R.string.profile_crop_title)) },
        text = {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Box(
                    modifier = Modifier
                        .size(cropBoxDp)
                        .clip(RoundedCornerShape(14.dp))
                        .background(Color.Black)
                        .pointerInput(Unit) {
                            detectDragGestures { change, dragAmount ->
                                change.consume()
                                val maxOffset = cropBoxPx * (scale - 1f) * 0.5f + cropBoxPx * 0.25f
                                offset = Offset(
                                    x = (offset.x + dragAmount.x).coerceIn(-maxOffset, maxOffset),
                                    y = (offset.y + dragAmount.y).coerceIn(-maxOffset, maxOffset)
                                )
                            }
                        },
                    contentAlignment = Alignment.Center
                ) {
                    Image(
                        bitmap = source.asImageBitmap(),
                        contentDescription = null,
                        contentScale = ContentScale.Crop,
                        modifier = Modifier
                            .fillMaxSize()
                            .graphicsLayer(
                                scaleX = scale,
                                scaleY = scale,
                                translationX = offset.x,
                                translationY = offset.y
                            )
                    )
                    Canvas(modifier = Modifier.fillMaxSize()) {
                        drawCircle(
                            color = Color.White,
                            radius = size.minDimension * 0.46f,
                            style = Stroke(width = 2.dp.toPx())
                        )
                    }
                }
                Spacer(modifier = Modifier.height(12.dp))
                Slider(
                    value = scale,
                    onValueChange = { scale = it },
                    valueRange = 1f..3f,
                    colors = SliderDefaults.colors(
                        thumbColor = MaterialTheme.colorScheme.primary,
                        activeTrackColor = MaterialTheme.colorScheme.primary
                    )
                )
            }
        },
        confirmButton = {
            Button(
                onClick = {
                    val cropped = renderSquareCrop(source, cropBoxPx, scale, offset, targetSize = 512)
                    onApply(cropped)
                },
                colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.primary)
            ) {
                Text(stringResource(id = R.string.profile_crop_apply))
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text("Cancel")
            }
        }
    )
}

internal fun decodeSampledBitmap(context: Context, uri: Uri, maxDim: Int): Bitmap? {
    return runCatching {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        context.contentResolver.openInputStream(uri)?.use {
            BitmapFactory.decodeStream(it, null, bounds)
        }
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return@runCatching null
        var sample = 1
        val largest = max(bounds.outWidth, bounds.outHeight)
        while (largest / sample > maxDim * 2) {
            sample *= 2
        }
        val opts = BitmapFactory.Options().apply { inSampleSize = sample }
        context.contentResolver.openInputStream(uri)?.use {
            BitmapFactory.decodeStream(it, null, opts)
        }
    }.getOrNull()
}

private fun renderSquareCrop(
    source: Bitmap,
    viewportPx: Float,
    scale: Float,
    offset: Offset,
    targetSize: Int
): Bitmap {
    val safeSize = targetSize.coerceAtLeast(64)
    val out = Bitmap.createBitmap(safeSize, safeSize, Bitmap.Config.ARGB_8888)
    if (source.isRecycled || source.width <= 0 || source.height <= 0) {
        return out
    }
    val canvas = Canvas(out)
    val baseScale = max(
        safeSize.toFloat() / source.width.toFloat(),
        safeSize.toFloat() / source.height.toFloat()
    )
    val effectiveScale = baseScale * scale.coerceIn(1f, 4f)
    val dxViewportRatio = if (viewportPx > 0f) offset.x / viewportPx else 0f
    val dyViewportRatio = if (viewportPx > 0f) offset.y / viewportPx else 0f
    val matrix = Matrix().apply {
        postTranslate(-source.width / 2f, -source.height / 2f)
        postScale(effectiveScale, effectiveScale)
        postTranslate(
            safeSize / 2f + dxViewportRatio * safeSize,
            safeSize / 2f + dyViewportRatio * safeSize
        )
    }
    canvas.drawBitmap(source, matrix, null)
    return out
}
