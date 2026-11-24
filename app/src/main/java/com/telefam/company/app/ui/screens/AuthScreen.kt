package com.telefam.company.app.ui.screens

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onKeyEvent
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.telefam.company.app.R
import com.telefam.company.app.ui.AuthStep
import com.telefam.company.app.ui.TelefamUiState
import com.telefam.company.app.ui.components.TelefamBottomWave
import com.telefam.company.app.ui.components.TelefamBrandHeader
import com.telefam.company.app.ui.components.TelefamTopWave
import com.telefam.company.app.ui.components.swipeBackEdge

@Composable
fun AuthScreen(
    state: TelefamUiState,
    onEmailChange: (String) -> Unit,
    onSendOtp: () -> Unit,
    onGoogleSignIn: () -> Unit,
    onOtpDigitChange: (Int, String) -> Unit,
    onVerifyOtp: () -> Unit,
    onResendOtp: () -> Unit,
    onChangeEmail: () -> Unit
) {
    if (state.authStep == AuthStep.ENTER_OTP) {
        BackHandler { onChangeEmail() }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            .swipeBackEdge(enabled = state.authStep == AuthStep.ENTER_OTP) { onChangeEmail() }
    ) {
        TelefamTopWave(
            modifier = Modifier.align(Alignment.TopCenter),
            height = 78.dp
        )
        TelefamBottomWave(
            modifier = Modifier.align(Alignment.BottomCenter),
            height = 104.dp
        )

        BoxWithConstraints(
            modifier = Modifier
                .fillMaxSize()
                .windowInsetsPadding(WindowInsets.statusBars)
                .windowInsetsPadding(WindowInsets.navigationBars)
                .imePadding()
        ) {
            val isWide = maxWidth >= 600.dp
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = if (isWide) 32.dp else 22.dp, vertical = 24.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center
            ) {
                Spacer(modifier = Modifier.height(24.dp))

                TelefamBrandHeader(logoSize = 68.dp)

                Spacer(modifier = Modifier.height(20.dp))

                Card(
                    modifier = Modifier
                        .fillMaxWidth()
                        .widthIn(max = 420.dp),
                    shape = RoundedCornerShape(20.dp),
                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                    elevation = CardDefaults.cardElevation(defaultElevation = 8.dp)
                ) {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 22.dp, vertical = 26.dp),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        if (state.authStep == AuthStep.ENTER_EMAIL) {
                            EnterEmailCardContent(
                                email = state.email,
                                isLoading = state.isLoading,
                                errorMessage = state.errorMessage,
                                onEmailChange = onEmailChange,
                                onSendOtp = onSendOtp,
                                onGoogleSignIn = onGoogleSignIn
                            )
                        } else {
                            EnterOtpCardContent(
                                email = state.email,
                                otpDigits = state.otpDigits,
                                cooldownSeconds = state.cooldownSeconds,
                                isLoading = state.isLoading,
                                errorMessage = state.errorMessage,
                                onOtpDigitChange = onOtpDigitChange,
                                onVerifyOtp = onVerifyOtp,
                                onResendOtp = onResendOtp,
                                onChangeEmail = onChangeEmail
                            )
                        }
                    }
                }

                Spacer(modifier = Modifier.height(36.dp))
            }
        }
    }
}

@Composable
private fun EnterEmailCardContent(
    email: String,
    isLoading: Boolean,
    errorMessage: String?,
    onEmailChange: (String) -> Unit,
    onSendOtp: () -> Unit,
    onGoogleSignIn: () -> Unit
) {
    Text(
        text = stringResource(id = R.string.auth_enter_email_title),
        style = MaterialTheme.typography.titleLarge,
        color = MaterialTheme.colorScheme.primary
    )
    Spacer(modifier = Modifier.height(4.dp))
    Text(
        text = stringResource(id = R.string.auth_enter_email_subtitle),
        style = MaterialTheme.typography.bodyMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant
    )

    Spacer(modifier = Modifier.height(20.dp))

    Text(
        text = stringResource(id = R.string.auth_email_label),
        style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.SemiBold),
        color = MaterialTheme.colorScheme.onSurface,
        modifier = Modifier.fillMaxWidth()
    )
    Spacer(modifier = Modifier.height(6.dp))

    OutlinedTextField(
        value = email,
        onValueChange = onEmailChange,
        placeholder = {
            Text(
                text = stringResource(id = R.string.auth_email_placeholder),
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        },
        leadingIcon = {
            Image(
                painter = painterResource(id = R.drawable.ic_mail_outline),
                contentDescription = null,
                modifier = Modifier.size(20.dp)
            )
        },
        singleLine = true,
        keyboardOptions = KeyboardOptions(
            keyboardType = KeyboardType.Email,
            imeAction = ImeAction.Done
        ),
        keyboardActions = KeyboardActions(onDone = { onSendOtp() }),
        shape = RoundedCornerShape(10.dp),
        colors = OutlinedTextFieldDefaults.colors(
            focusedBorderColor = MaterialTheme.colorScheme.primary,
            unfocusedBorderColor = MaterialTheme.colorScheme.outline
        ),
        modifier = Modifier
            .fillMaxWidth()
            .testTag("email_input")
    )

    if (!errorMessage.isNullOrBlank()) {
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = errorMessage,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.error,
            modifier = Modifier
                .fillMaxWidth()
                .testTag("auth_error_text")
        )
    }

    Spacer(modifier = Modifier.height(16.dp))

    Button(
        onClick = onSendOtp,
        enabled = !isLoading,
        shape = RoundedCornerShape(10.dp),
        colors = ButtonDefaults.buttonColors(
            containerColor = MaterialTheme.colorScheme.primary,
            contentColor = MaterialTheme.colorScheme.onPrimary
        ),
        modifier = Modifier
            .fillMaxWidth()
            .height(48.dp)
            .testTag("send_otp_button")
    ) {
        if (isLoading) {
            CircularProgressIndicator(
                modifier = Modifier.size(20.dp),
                color = MaterialTheme.colorScheme.onPrimary,
                strokeWidth = 2.dp
            )
        } else {
            Text(
                text = stringResource(id = R.string.auth_send_otp),
                style = MaterialTheme.typography.labelLarge
            )
        }
    }

    Spacer(modifier = Modifier.height(18.dp))

    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically
    ) {
        HorizontalDivider(
            modifier = Modifier.weight(1f),
            color = MaterialTheme.colorScheme.outlineVariant
        )
        Text(
            text = stringResource(id = R.string.auth_or),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(horizontal = 12.dp)
        )
        HorizontalDivider(
            modifier = Modifier.weight(1f),
            color = MaterialTheme.colorScheme.outlineVariant
        )
    }

    Spacer(modifier = Modifier.height(18.dp))

    OutlinedButton(
        onClick = onGoogleSignIn,
        enabled = !isLoading,
        shape = RoundedCornerShape(10.dp),
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline),
        colors = ButtonDefaults.outlinedButtonColors(
            containerColor = MaterialTheme.colorScheme.surface,
            contentColor = MaterialTheme.colorScheme.onSurface
        ),
        modifier = Modifier
            .fillMaxWidth()
            .height(48.dp)
            .testTag("google_signin_button")
    ) {
        Image(
            painter = painterResource(id = R.drawable.ic_google_logo),
            contentDescription = null,
            modifier = Modifier.size(20.dp)
        )
        Spacer(modifier = Modifier.width(10.dp))
        Text(
            text = stringResource(id = R.string.auth_continue_google),
            style = MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.Medium)
        )
    }
}

@Composable
private fun EnterOtpCardContent(
    email: String,
    otpDigits: List<String>,
    cooldownSeconds: Long,
    isLoading: Boolean,
    errorMessage: String?,
    onOtpDigitChange: (Int, String) -> Unit,
    onVerifyOtp: () -> Unit,
    onResendOtp: () -> Unit,
    onChangeEmail: () -> Unit
) {
    val focusRequesters = remember { List(6) { FocusRequester() } }
    var focusedIndex by remember { mutableIntStateOf(0) }

    Text(
        text = stringResource(id = R.string.auth_enter_otp_title),
        style = MaterialTheme.typography.titleLarge,
        color = MaterialTheme.colorScheme.primary
    )
    Spacer(modifier = Modifier.height(6.dp))
    Text(
        text = stringResource(id = R.string.auth_otp_sent_prefix),
        style = MaterialTheme.typography.bodyMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant
    )
    Text(
        text = email,
        style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Bold),
        color = MaterialTheme.colorScheme.onSurface
    )
    Spacer(modifier = Modifier.height(6.dp))
    Text(
        text = stringResource(id = R.string.auth_otp_link_hint),
        style = MaterialTheme.typography.labelSmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        textAlign = TextAlign.Center
    )

    Spacer(modifier = Modifier.height(18.dp))

    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        for (i in 0 until 6) {
            val digit = otpDigits.getOrElse(i) { "" }
            val isFocused = focusedIndex == i
            val borderColor = if (isFocused) {
                MaterialTheme.colorScheme.primary
            } else {
                MaterialTheme.colorScheme.outline
            }
            Box(
                modifier = Modifier
                    .weight(1f)
                    .height(52.dp)
                    .border(
                        width = if (isFocused) 1.6.dp else 1.dp,
                        color = borderColor,
                        shape = RoundedCornerShape(10.dp)
                    )
                    .background(
                        color = MaterialTheme.colorScheme.surface,
                        shape = RoundedCornerShape(10.dp)
                    ),
                contentAlignment = Alignment.Center
            ) {
                if (digit.isEmpty() && !isFocused) {
                    Text(
                        text = "•",
                        fontSize = 20.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                BasicTextField(
                    value = digit,
                    onValueChange = { incoming ->
                        val cleaned = incoming.filter { it.isDigit() }
                        onOtpDigitChange(i, cleaned)
                        if (cleaned.length > 1) {
                            val nextIdx = (cleaned.length - 1).coerceAtMost(5)
                            runCatching { focusRequesters[nextIdx].requestFocus() }
                        } else if (cleaned.isNotEmpty() && i < 5) {
                            runCatching { focusRequesters[i + 1].requestFocus() }
                        }
                    },
                    singleLine = true,
                    textStyle = MaterialTheme.typography.titleLarge.copy(
                        textAlign = TextAlign.Center,
                        color = MaterialTheme.colorScheme.onSurface
                    ),
                    cursorBrush = SolidColor(MaterialTheme.colorScheme.primary),
                    keyboardOptions = KeyboardOptions(
                        keyboardType = KeyboardType.Number,
                        imeAction = if (i == 5) ImeAction.Done else ImeAction.Next
                    ),
                    keyboardActions = KeyboardActions(onDone = { onVerifyOtp() }),
                    modifier = Modifier
                        .fillMaxWidth()
                        .focusRequester(focusRequesters[i])
                        .onFocusChanged { if (it.isFocused) focusedIndex = i }
                        .onKeyEvent { event ->
                            if (event.key == Key.Backspace && digit.isEmpty() && i > 0) {
                                runCatching { focusRequesters[i - 1].requestFocus() }
                                true
                            } else {
                                false
                            }
                        }
                        .testTag("otp_box_$i")
                )
            }
        }
    }

    if (!errorMessage.isNullOrBlank()) {
        Spacer(modifier = Modifier.height(10.dp))
        Text(
            text = errorMessage,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.error,
            textAlign = TextAlign.Center,
            modifier = Modifier
                .fillMaxWidth()
                .testTag("otp_error_text")
        )
    }

    Spacer(modifier = Modifier.height(18.dp))

    Button(
        onClick = onVerifyOtp,
        enabled = !isLoading,
        shape = RoundedCornerShape(10.dp),
        colors = ButtonDefaults.buttonColors(
            containerColor = MaterialTheme.colorScheme.primary,
            contentColor = MaterialTheme.colorScheme.onPrimary
        ),
        modifier = Modifier
            .fillMaxWidth()
            .height(48.dp)
            .testTag("verify_otp_button")
    ) {
        if (isLoading) {
            CircularProgressIndicator(
                modifier = Modifier.size(20.dp),
                color = MaterialTheme.colorScheme.onPrimary,
                strokeWidth = 2.dp
            )
        } else {
            Text(
                text = stringResource(id = R.string.auth_verify_otp),
                style = MaterialTheme.typography.labelLarge
            )
        }
    }

    Spacer(modifier = Modifier.height(14.dp))

    if (cooldownSeconds > 0L) {
        val formatted = formatCooldown(cooldownSeconds)
        Row(
            horizontalArrangement = Arrangement.Center,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = stringResource(id = R.string.auth_resend_in_prefix) + " ",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Text(
                text = formatted,
                style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Bold),
                color = MaterialTheme.colorScheme.primary,
                modifier = Modifier.testTag("cooldown_timer_text")
            )
        }
        Spacer(modifier = Modifier.height(4.dp))
        Row(
            horizontalArrangement = Arrangement.Center,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = "${stringResource(id = R.string.auth_after_prefix)} $formatted ${stringResource(id = R.string.auth_you_can)} ",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Text(
                text = stringResource(id = R.string.auth_resend_code),
                style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.SemiBold),
                color = MaterialTheme.colorScheme.primary.copy(alpha = 0.5f)
            )
        }
    } else {
        TextButton(
            onClick = onResendOtp,
            enabled = !isLoading,
            modifier = Modifier
                .height(48.dp)
                .testTag("resend_otp_button")
        ) {
            Text(
                text = stringResource(id = R.string.auth_resend_code),
                style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.SemiBold),
                color = MaterialTheme.colorScheme.primary
            )
        }
    }

    TextButton(
        onClick = onChangeEmail,
        enabled = !isLoading,
        modifier = Modifier
            .height(48.dp)
            .testTag("change_email_button")
    ) {
        Text(
            text = stringResource(id = R.string.auth_change_email),
            style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.SemiBold),
            color = MaterialTheme.colorScheme.primary
        )
    }
}

private fun formatCooldown(seconds: Long): String {
    val h = seconds / 3600L
    val m = (seconds % 3600L) / 60L
    val s = seconds % 60L
    return if (h > 0) {
        "%02d:%02d:%02d".format(h, m, s)
    } else {
        "%02d:%02d".format(m, s)
    }
}
