package com.telefam.company.app

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalView
import androidx.core.view.WindowCompat
import androidx.credentials.CredentialManager
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.lifecycleScope
import com.google.android.libraries.identity.googleid.GetSignInWithGoogleOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import com.telefam.company.app.ui.TelefamViewModel
import com.telefam.company.app.ui.screens.AuthScreen
import com.telefam.company.app.ui.screens.PostCreatorScreen
import com.telefam.company.app.ui.screens.ProfileSetupScreen
import com.telefam.company.app.ui.screens.WorkspaceScreen
import com.telefam.company.app.ui.theme.TelefamTheme
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {

    private val viewModel: TelefamViewModel by viewModels {
        val app = application as TelefamApplication
        TelefamViewModel.Factory(app.repository, app.networkMonitor)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.auto(
                android.graphics.Color.TRANSPARENT,
                android.graphics.Color.TRANSPARENT
            )
        )
        handleDeepLinkIntent(intent)

        setContent {
            val state by viewModel.uiState.collectAsStateWithLifecycle()
            val conversations by viewModel.conversations.collectAsStateWithLifecycle()
            val messages by viewModel.messages.collectAsStateWithLifecycle()
            val contacts by viewModel.contacts.collectAsStateWithLifecycle()
            val view = LocalView.current
            val currentSession = state.session

            SideEffect {
                val window = (view.context as? Activity)?.window ?: return@SideEffect
                val controller = WindowCompat.getInsetsController(window, view)
                // Top wave / top header bar across Auth, Profile Setup, Chats, and Contacts is Crimson (#C81010)
                controller.isAppearanceLightStatusBars = false
                // Bottom navigation / gesture bar adapts cleanly to dark vs light theme
                controller.isAppearanceLightNavigationBars = !state.isDarkTheme
            }

            TelefamTheme(darkTheme = state.isDarkTheme) {
                when {
                    !state.initialized -> {
                        Box(
                            modifier = Modifier.fillMaxSize(),
                            contentAlignment = Alignment.Center
                        ) {
                            CircularProgressIndicator(color = MaterialTheme.colorScheme.primary)
                        }
                    }

                    currentSession == null -> {
                        AuthScreen(
                            state = state,
                            onEmailChange = viewModel::updateEmail,
                            onSendOtp = viewModel::sendOtp,
                            onGoogleSignIn = ::launchGoogleSignIn,
                            onOtpDigitChange = viewModel::updateOtpDigit,
                            onVerifyOtp = { viewModel.verifyOtp() },
                            onResendOtp = viewModel::sendOtp,
                            onChangeEmail = viewModel::changeEmail
                        )
                    }

                    !currentSession.profileCompleted -> {
                        ProfileSetupScreen(
                            state = state.profileSetup,
                            onUpdateField = viewModel::updateProfileField,
                            onAvatarCropped = viewModel::setCroppedAvatar,
                            onSubmit = viewModel::submitProfileSetup,
                            onBack = viewModel::signOut
                        )
                    }

                    state.postComposer.isOpen -> {
                        PostCreatorScreen(
                            state = state.postComposer,
                            isDarkTheme = state.isDarkTheme,
                            contacts = contacts,
                            onClose = viewModel::closePostComposer,
                            onSelectMode = viewModel::selectPostMode,
                            onTextBodyChange = viewModel::updatePostTextBody,
                            onCaptionChange = viewModel::updatePostCaption,
                            onTogglePaletteMode = viewModel::togglePostPaletteMode,
                            onSelectBgColor = viewModel::selectPostBgColor,
                            onSelectImageTheme = viewModel::selectPostImageTheme,
                            onSelectFont = viewModel::selectPostFont,
                            onAddPhotos = viewModel::addSelectedPhotos,
                            onRemovePhoto = viewModel::removeSelectedPhoto,
                            onSelectVideo = viewModel::selectPostVideo,
                            onClearVideo = viewModel::clearSelectedVideo,
                            onUpdateTrim = viewModel::updateVideoTrim,
                            onSelectThumbFrame = viewModel::selectVideoThumbnailFrame,
                            onAutoSelectThumb = viewModel::autoSelectVideoThumbnail,
                            onToggleMuteAudio = viewModel::toggleMuteOriginalAudio,
                            onSongQueryChange = viewModel::searchSongs,
                            onSelectSong = viewModel::selectSong,
                            onToggleSongPreview = viewModel::toggleSongPreview,
                            onToggleTagContact = viewModel::toggleTagContact,
                            onHashtagQueryChange = viewModel::searchHashtags,
                            onToggleHashtag = viewModel::toggleHashtag,
                            onShare = viewModel::shareCurrentPost
                        )
                    }

                    else -> {
                        WorkspaceScreen(
                            session = currentSession,
                            isDarkTheme = state.isDarkTheme,
                            activeTab = state.activeTab,
                            conversations = conversations,
                            selectedConversationId = state.selectedConversationId,
                            messages = messages,
                            contacts = contacts,
                            contactFilter = state.contactFilter,
                            contactSearchQuery = state.contactSearchQuery,
                            isLoadingContacts = state.isLoadingContacts,
                            hasMoreContacts = state.hasMoreContacts,
                            contactsToastMessage = state.contactsToastMessage,
                            onToggleTheme = viewModel::toggleTheme,
                            onSelectTab = viewModel::selectHomeTab,
                            onSelectConversation = viewModel::selectConversation,
                            onCreateConversation = viewModel::createConversation,
                            onSendMessage = viewModel::sendMessage,
                            onDeleteMessage = viewModel::deleteMessage,
                            onSelectContactFilter = viewModel::selectContactFilter,
                            onContactSearchQueryChange = viewModel::updateContactSearchQuery,
                            onToggleFollow = viewModel::toggleFollow,
                            onLoadMoreContacts = viewModel::loadMoreContacts,
                            onClearContactsToast = viewModel::clearContactsToast,
                            onOpenPost = viewModel::openPostComposer
                        )
                    }
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleDeepLinkIntent(intent)
    }

    private fun handleDeepLinkIntent(intent: Intent?) {
        val uri = intent?.data ?: return
        val token = uri.getQueryParameter("token") ?: return
        val email = uri.getQueryParameter("email")
        viewModel.verifyOtp(magicToken = token, emailFromLink = email)
    }

    private fun launchGoogleSignIn() {
        val clientId = BuildConfig.TELEFAM_GOOGLE_WEB_CLIENT_ID
        if (clientId.isBlank() || clientId == "YOUR_GOOGLE_WEB_CLIENT_ID") {
            viewModel.reportSanitizedError(getString(R.string.error_generic))
            return
        }

        lifecycleScope.launch {
            try {
                val cm = CredentialManager.create(this@MainActivity)
                val googleOption = GetSignInWithGoogleOption.Builder(clientId).build()
                val request = GetCredentialRequest.Builder()
                    .addCredentialOption(googleOption)
                    .build()
                val result = cm.getCredential(this@MainActivity, request)
                val cred = result.credential
                if (cred is CustomCredential &&
                    cred.type == GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL
                ) {
                    val tokenCred = GoogleIdTokenCredential.createFrom(cred.data)
                    viewModel.signInWithGoogleToken(tokenCred.idToken)
                } else {
                    viewModel.reportSanitizedError(getString(R.string.error_generic))
                }
            } catch (_: Exception) {
                viewModel.reportSanitizedError(getString(R.string.error_generic))
            }
        }
    }
}
