#ifndef TELEFAM_DESKTOP_CONTROLLER_HPP
#define TELEFAM_DESKTOP_CONTROLLER_HPP

#include "telefam_core.h"

#include <QNetworkAccessManager>
#include <QObject>
#include <QSet>
#include <QTimer>
#include <QUrl>
#include <QVariantList>
#include <QVariantMap>
#include <functional>

class TelefamDesktopController : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool authenticated READ authenticated NOTIFY sessionChanged)
    Q_PROPERTY(bool profileCompleted READ profileCompleted NOTIFY sessionChanged)
    Q_PROPERTY(bool isDarkTheme READ isDarkTheme NOTIFY themeChanged)
    Q_PROPERTY(int authStep READ authStep NOTIFY authStepChanged)
    Q_PROPERTY(QString email READ email WRITE setEmail NOTIFY emailChanged)
    Q_PROPERTY(qint64 cooldownSeconds READ cooldownSeconds NOTIFY cooldownChanged)
    Q_PROPERTY(bool loading READ loading NOTIFY loadingChanged)
    Q_PROPERTY(QString errorMessage READ errorMessage NOTIFY errorChanged)
    Q_PROPERTY(QString networkLabel READ networkLabel NOTIFY networkChanged)
    Q_PROPERTY(QVariantList conversations READ conversations NOTIFY conversationsChanged)
    Q_PROPERTY(QString selectedConversationId READ selectedConversationId WRITE selectConversation NOTIFY selectedConversationChanged)
    Q_PROPERTY(QVariantList messages READ messages NOTIFY messagesChanged)
    Q_PROPERTY(int pendingSyncCount READ pendingSyncCount NOTIFY outboxChanged)
    Q_PROPERTY(QString deviceName READ deviceName CONSTANT)

    // Profile setup autofill & avatar preview
    Q_PROPERTY(QString profileFullName READ profileFullName NOTIFY profileSeedChanged)
    Q_PROPERTY(QString profileUsername READ profileUsername NOTIFY profileSeedChanged)
    Q_PROPERTY(QString profileCountryIso READ profileCountryIso NOTIFY profileSeedChanged)
    Q_PROPERTY(QString profileLocation READ profileLocation NOTIFY profileSeedChanged)
    Q_PROPERTY(QString avatarDataUrl READ avatarDataUrl NOTIFY avatarChanged)

    // Contacts, Feeds, Profile, Search & Notifications
    Q_PROPERTY(int activeTab READ activeTab NOTIFY activeTabChanged)
    Q_PROPERTY(QString homeSearchQuery READ homeSearchQuery WRITE setHomeSearchQuery NOTIFY homeSearchChanged)
    Q_PROPERTY(QVariantList filteredConversations READ filteredConversations NOTIFY conversationsChanged)
    Q_PROPERTY(QVariantList contacts READ contacts NOTIFY contactsChanged)
    Q_PROPERTY(QString contactFilter READ contactFilter NOTIFY contactsChanged)
    Q_PROPERTY(QString contactSearchQuery READ contactSearchQuery NOTIFY contactsChanged)
    Q_PROPERTY(bool contactsLoading READ contactsLoading NOTIFY contactsChanged)
    Q_PROPERTY(bool hasMoreContacts READ hasMoreContacts NOTIFY contactsChanged)
    Q_PROPERTY(QString toastMessage READ toastMessage NOTIFY toastChanged)
    Q_PROPERTY(bool isEditingProfile READ isEditingProfile NOTIFY editingProfileChanged)
    Q_PROPERTY(QVariantMap myProfile READ myProfile NOTIFY myProfileChanged)
    Q_PROPERTY(QVariantList feedPosts READ feedPosts NOTIFY feedChanged)
    Q_PROPERTY(bool feedLoading READ feedLoading NOTIFY feedChanged)
    Q_PROPERTY(QVariantList notifications READ notifications NOTIFY notificationsChanged)
    Q_PROPERTY(int unreadNotificationCount READ unreadNotificationCount NOTIFY notificationsChanged)

    // New Post composer state
    Q_PROPERTY(bool postComposerOpen READ postComposerOpen NOTIFY postComposerChanged)
    Q_PROPERTY(QVariantList postMusicResults READ postMusicResults NOTIFY postMusicChanged)
    Q_PROPERTY(bool postSearchingSongs READ postSearchingSongs NOTIFY postMusicChanged)
    Q_PROPERTY(QString postPlayingPreviewTrackId READ postPlayingPreviewTrackId NOTIFY postAudioChanged)
    Q_PROPERTY(QVariantList postHashtagResults READ postHashtagResults NOTIFY postHashtagsChanged)
    Q_PROPERTY(bool postSearchingHashtags READ postSearchingHashtags NOTIFY postHashtagsChanged)
    Q_PROPERTY(QVariantList postPhotos READ postPhotos NOTIFY postMediaChanged)
    Q_PROPERTY(QString postVideoPath READ postVideoPath NOTIFY postMediaChanged)
    Q_PROPERTY(qint64 postVideoDurationMs READ postVideoDurationMs NOTIFY postMediaChanged)
    Q_PROPERTY(QVariantList postVideoFrames READ postVideoFrames NOTIFY postMediaChanged)
    Q_PROPERTY(int postSelectedThumbIndex READ postSelectedThumbIndex NOTIFY postMediaChanged)
    Q_PROPERTY(qint64 postTrimStartMs READ postTrimStartMs NOTIFY postMediaChanged)
    Q_PROPERTY(qint64 postTrimEndMs READ postTrimEndMs NOTIFY postMediaChanged)
    Q_PROPERTY(QString postUploadStatus READ postUploadStatus NOTIFY postUploadChanged)
    Q_PROPERTY(int postUploadProgress READ postUploadProgress NOTIFY postUploadChanged)
    Q_PROPERTY(QString postErrorMessage READ postErrorMessage NOTIFY postUploadChanged)

    // Short-video Feed, Playback Prefetch, Discovery, Search & Safety
    Q_PROPERTY(bool hasMultimedia READ hasMultimedia CONSTANT)
    Q_PROPERTY(bool isOffline READ isOffline NOTIFY networkChanged)
    Q_PROPERTY(QString videoFeedTab READ videoFeedTab NOTIFY videoFeedChanged)
    Q_PROPERTY(QVariantList forYouVideos READ forYouVideos NOTIFY videoFeedChanged)
    Q_PROPERTY(QVariantList followingVideos READ followingVideos NOTIFY videoFeedChanged)
    Q_PROPERTY(QVariantList activeFeedVideos READ activeFeedVideos NOTIFY videoFeedChanged)
    Q_PROPERTY(int activeVideoIndex READ activeVideoIndex NOTIFY videoFeedChanged)
    Q_PROPERTY(bool videoFeedLoading READ videoFeedLoading NOTIFY videoFeedChanged)
    Q_PROPERTY(QString videoFeedError READ videoFeedError NOTIFY videoFeedChanged)
    Q_PROPERTY(bool feedMuted READ feedMuted WRITE setFeedMuted NOTIFY feedAudioStateChanged)
    Q_PROPERTY(bool feedSearchOpen READ feedSearchOpen NOTIFY feedDiscoveryChanged)
    Q_PROPERTY(QString feedSearchQuery READ feedSearchQuery NOTIFY feedDiscoveryChanged)
    Q_PROPERTY(int feedSearchTab READ feedSearchTab WRITE setFeedSearchTab NOTIFY feedDiscoveryChanged)
    Q_PROPERTY(bool feedSearching READ feedSearching NOTIFY feedDiscoveryChanged)
    Q_PROPERTY(QVariantMap feedSearchResults READ feedSearchResults NOTIFY feedDiscoveryChanged)
    Q_PROPERTY(QVariantList localRecentSearches READ localRecentSearches NOTIFY feedDiscoveryChanged)
    Q_PROPERTY(QString activeHashtagTag READ activeHashtagTag NOTIFY feedDiscoveryChanged)
    Q_PROPERTY(QVariantMap hashtagDiscovery READ hashtagDiscovery NOTIFY feedDiscoveryChanged)
    Q_PROPERTY(bool hashtagLoading READ hashtagLoading NOTIFY feedDiscoveryChanged)
    Q_PROPERTY(QString activeAudioId READ activeAudioId NOTIFY feedDiscoveryChanged)
    Q_PROPERTY(QVariantMap audioDiscovery READ audioDiscovery NOTIFY feedDiscoveryChanged)
    Q_PROPERTY(bool audioLoading READ audioLoading NOTIFY feedDiscoveryChanged)
    Q_PROPERTY(QVariantList modalFeedVideos READ modalFeedVideos NOTIFY feedDiscoveryChanged)
    Q_PROPERTY(int modalFeedIndex READ modalFeedIndex WRITE setModalFeedIndex NOTIFY feedDiscoveryChanged)
    Q_PROPERTY(QString modalFeedTitle READ modalFeedTitle NOTIFY feedDiscoveryChanged)
    Q_PROPERTY(bool modalFeedOpen READ modalFeedOpen NOTIFY feedDiscoveryChanged)
    Q_PROPERTY(bool liveComingSoonOpen READ liveComingSoonOpen WRITE setLiveComingSoonOpen NOTIFY feedDiscoveryChanged)
    Q_PROPERTY(QVariantList savedVideos READ savedVideos NOTIFY savedSafetyChanged)
    Q_PROPERTY(bool savedVideosLoading READ savedVideosLoading NOTIFY savedSafetyChanged)
    Q_PROPERTY(QVariantMap safetyPreferences READ safetyPreferences NOTIFY savedSafetyChanged)
    Q_PROPERTY(bool safetyLoading READ safetyLoading NOTIFY savedSafetyChanged)
    Q_PROPERTY(QVariantMap prefilledPostSong READ prefilledPostSong NOTIFY prefilledPostSongChanged)

    // Owner Profile state
    Q_PROPERTY(QString ownerActiveCategory READ ownerActiveCategory NOTIFY ownerProfileChanged)
    Q_PROPERTY(QVariantList ownerActiveItems READ ownerActiveItems NOTIFY ownerProfileChanged)
    Q_PROPERTY(bool ownerItemsLoading READ ownerItemsLoading NOTIFY ownerProfileChanged)
    Q_PROPERTY(bool ownerRefreshing READ ownerRefreshing NOTIFY ownerProfileChanged)
    Q_PROPERTY(bool ownerUploadingBackgrounds READ ownerUploadingBackgrounds NOTIFY ownerProfileChanged)
    Q_PROPERTY(QString ownerLocalAvatarUrl READ ownerLocalAvatarUrl NOTIFY ownerProfileChanged)
    Q_PROPERTY(QStringList ownerLocalBackgroundUrls READ ownerLocalBackgroundUrls NOTIFY ownerProfileChanged)
    Q_PROPERTY(QVariantList ownerBackgroundSlides READ ownerBackgroundSlides NOTIFY ownerProfileChanged)
    Q_PROPERTY(QString ownerConnectionsMode READ ownerConnectionsMode NOTIFY ownerConnectionsChanged)
    Q_PROPERTY(QVariantList ownerConnectionsUsers READ ownerConnectionsUsers NOTIFY ownerConnectionsChanged)
    Q_PROPERTY(bool ownerConnectionsLoading READ ownerConnectionsLoading NOTIFY ownerConnectionsChanged)
    Q_PROPERTY(QVariantMap ownerActiveViewerItem READ ownerActiveViewerItem NOTIFY ownerProfileChanged)

public:
    explicit TelefamDesktopController(QObject* parent = nullptr);
    ~TelefamDesktopController() override;

    bool authenticated() const { return !accessToken_.isEmpty(); }
    bool profileCompleted() const { return profileCompleted_; }
    bool isDarkTheme() const { return isDarkTheme_; }
    int authStep() const { return authStep_; }
    QString email() const { return email_; }
    void setEmail(const QString& value);
    qint64 cooldownSeconds() const { return cooldownSeconds_; }
    bool loading() const { return loading_; }
    QString errorMessage() const { return errorMessage_; }
    QString networkLabel() const { return networkLabel_; }
    QVariantList conversations() const { return conversations_; }
    QString selectedConversationId() const { return selectedConversationId_; }
    QVariantList messages() const { return messages_; }
    int pendingSyncCount() const { return engine_ ? telefam_outbox_pending_count(engine_) : 0; }
    QString deviceName() const { return deviceName_; }

    QString profileFullName() const { return profileFullName_; }
    QString profileUsername() const { return profileUsername_; }
    QString profileCountryIso() const { return profileCountryIso_; }
    QString profileLocation() const { return profileLocation_; }
    QString avatarDataUrl() const { return avatarDataUrl_; }

    int activeTab() const { return activeTab_; }
    QString homeSearchQuery() const { return homeSearchQuery_; }
    void setHomeSearchQuery(const QString& query);
    QVariantList filteredConversations() const;
    QVariantList contacts() const { return filteredContacts_; }
    QString contactFilter() const { return contactFilter_; }
    QString contactSearchQuery() const { return contactSearchQuery_; }
    bool contactsLoading() const { return contactsLoading_; }
    bool hasMoreContacts() const { return hasMoreContacts_; }
    QString toastMessage() const { return toastMessage_; }
    bool isEditingProfile() const { return isEditingProfile_; }
    QVariantMap myProfile() const { return myProfile_; }
    QVariantList feedPosts() const;
    bool feedLoading() const { return feedLoading_; }
    QVariantList notifications() const { return notifications_; }
    int unreadNotificationCount() const;

    bool postComposerOpen() const { return postComposerOpen_; }
    QVariantList postMusicResults() const { return postMusicResults_; }
    bool postSearchingSongs() const { return postSearchingSongs_; }
    QString postPlayingPreviewTrackId() const { return postPlayingPreviewTrackId_; }
    QVariantList postHashtagResults() const { return postHashtagResults_; }
    bool postSearchingHashtags() const { return postSearchingHashtags_; }
    QVariantList postPhotos() const { return postPhotos_; }
    QString postVideoPath() const { return postVideoPath_; }
    qint64 postVideoDurationMs() const { return postVideoDurationMs_; }
    QVariantList postVideoFrames() const { return postVideoFrames_; }
    int postSelectedThumbIndex() const { return postSelectedThumbIndex_; }
    qint64 postTrimStartMs() const { return postTrimStartMs_; }
    qint64 postTrimEndMs() const { return postTrimEndMs_; }
    QString postUploadStatus() const { return postUploadStatus_; }
    int postUploadProgress() const { return postUploadProgress_; }
    QString postErrorMessage() const { return postErrorMessage_; }

    // Short-video Feed getters
    bool hasMultimedia() const;
    bool isOffline() const { return isOffline_; }
    QString videoFeedTab() const { return videoFeedTab_; }
    QVariantList forYouVideos() const { return forYouVideos_; }
    QVariantList followingVideos() const { return followingVideos_; }
    QVariantList activeFeedVideos() const { return videoFeedTab_ == QStringLiteral("following") ? followingVideos_ : forYouVideos_; }
    int activeVideoIndex() const { return videoFeedTab_ == QStringLiteral("following") ? activeFollowingIndex_ : activeForYouIndex_; }
    bool videoFeedLoading() const { return videoFeedLoading_; }
    QString videoFeedError() const { return videoFeedError_; }
    bool feedMuted() const { return feedMuted_; }
    void setFeedMuted(bool muted);
    bool feedSearchOpen() const { return feedSearchOpen_; }
    QString feedSearchQuery() const { return feedSearchQuery_; }
    int feedSearchTab() const { return feedSearchTab_; }
    void setFeedSearchTab(int tab);
    bool feedSearching() const { return feedSearching_; }
    QVariantMap feedSearchResults() const { return feedSearchResults_; }
    QVariantList localRecentSearches() const { return localRecentSearches_; }
    QString activeHashtagTag() const { return activeHashtagTag_; }
    QVariantMap hashtagDiscovery() const { return hashtagDiscovery_; }
    bool hashtagLoading() const { return hashtagLoading_; }
    QString activeAudioId() const { return activeAudioId_; }
    QVariantMap audioDiscovery() const { return audioDiscovery_; }
    bool audioLoading() const { return audioLoading_; }
    QVariantList modalFeedVideos() const { return modalFeedVideos_; }
    int modalFeedIndex() const { return modalFeedIndex_; }
    void setModalFeedIndex(int idx);
    QString modalFeedTitle() const { return modalFeedTitle_; }
    bool modalFeedOpen() const { return modalFeedOpen_; }
    bool liveComingSoonOpen() const { return liveComingSoonOpen_; }
    void setLiveComingSoonOpen(bool open);
    QVariantList savedVideos() const { return savedVideos_; }
    bool savedVideosLoading() const { return savedVideosLoading_; }
    QVariantMap safetyPreferences() const { return safetyPreferences_; }
    bool safetyLoading() const { return safetyLoading_; }
    QVariantMap prefilledPostSong() const { return prefilledPostSong_; }

    Q_INVOKABLE void toggleTheme();
    Q_INVOKABLE void selectTab(int tabIndex);
    Q_INVOKABLE void selectContactFilter(const QString& filter);
    Q_INVOKABLE void setContactSearchQuery(const QString& query);
    Q_INVOKABLE void refreshContacts(bool reset);
    Q_INVOKABLE void loadMoreContacts();
    Q_INVOKABLE void toggleFollow(const QString& targetUserId);
    Q_INVOKABLE void sendOtp(bool isResend);
    Q_INVOKABLE void verifyOtp(const QString& otp, const QString& magicToken = QString());
    Q_INVOKABLE void verifyGoogleIdToken(const QString& idToken);
    Q_INVOKABLE void changeEmail();
    Q_INVOKABLE void cropAndUploadAvatar(const QUrl& fileUrl, qreal zoom, qreal offsetXRatio, qreal offsetYRatio);
    Q_INVOKABLE void submitProfileSetup(
        const QString& fullName,
        const QString& username,
        const QString& countryIso,
        const QString& phoneNumber,
        const QString& gender,
        const QString& dobIso,
        const QString& location,
        const QString& bio
    );
    Q_INVOKABLE void selectConversation(const QString& id);
    Q_INVOKABLE void createConversation(const QString& title);
    Q_INVOKABLE void sendMessageOfflineFirst(const QString& body);
    Q_INVOKABLE void syncNow();
    Q_INVOKABLE void refreshFeedPosts();
    Q_INVOKABLE void refreshMyProfile();
    Q_INVOKABLE void refreshNotifications();
    Q_INVOKABLE void markNotificationsRead();
    Q_INVOKABLE void openEditProfile();
    Q_INVOKABLE void closeEditProfile();
    Q_INVOKABLE void signOut();

    // New Post composer actions
    Q_INVOKABLE void openPostComposer();
    Q_INVOKABLE void closePostComposer();
    Q_INVOKABLE void searchMusic(const QString& query);
    Q_INVOKABLE void toggleSongPreview(const QString& trackId, const QString& previewUrl);
    Q_INVOKABLE void stopAudioPreview();
    Q_INVOKABLE void searchHashtags(const QString& query);
    Q_INVOKABLE void addPostPhotos(const QList<QUrl>& fileUrls);
    Q_INVOKABLE void removePostPhoto(int index);
    Q_INVOKABLE void selectPostVideo(const QUrl& fileUrl);
    Q_INVOKABLE void clearPostVideo();
    Q_INVOKABLE void selectPostVideoThumb(int index);
    Q_INVOKABLE void autoSelectPostVideoThumb();
    Q_INVOKABLE void updatePostVideoTrim(qint64 startMs, qint64 endMs);
    Q_INVOKABLE void submitPost(
        const QString& postType,
        const QString& body,
        const QString& bgColorHex,
        const QString& bgThemeId,
        const QString& fontFamily,
        const QString& songId,
        const QString& songTitle,
        const QString& songArtist,
        const QString& songPreviewUrl,
        bool muteOriginalAudio,
        const QStringList& taggedUserIds,
        const QStringList& hashtags
    );

    // Short-video Feed, Discovery, Search, Safety & C++ Core helpers
    Q_INVOKABLE QString resolveMediaUrl(const QString& rawUrl) const;
    Q_INVOKABLE QVariantMap computeFeedFit(qreal containerW, qreal containerH, int videoW, int videoH, qreal explicitRatio) const;
    Q_INVOKABLE QString formatFeedCount(qint64 count) const;
    Q_INVOKABLE void selectVideoFeedTab(const QString& tab);
    Q_INVOKABLE void refreshVideoFeed(const QString& tab, bool reset);
    Q_INVOKABLE void onFeedVideoSettled(int index);
    Q_INVOKABLE void refreshSignedStreamUrl(const QString& videoId);
    Q_INVOKABLE void sendWatchProgress(const QString& videoId, qint64 watchMs, qint64 posMs, double completionPct, int rewatchDelta, bool isViewPing);
    Q_INVOKABLE void toggleVideoLike(const QString& videoId, bool forceLikeOnly = false);
    Q_INVOKABLE void toggleVideoSave(const QString& videoId);
    Q_INVOKABLE void shareVideo(const QString& videoId, const QString& streamUrl);
    Q_INVOKABLE void toggleFollowCreator(const QString& creatorId);
    Q_INVOKABLE void toggleVideoRepost(const QString& videoId);
    Q_INVOKABLE void markVideoNotInterested(const QString& videoId);
    Q_INVOKABLE void reportVideo(const QString& videoId, const QString& reason, const QString& details);
    Q_INVOKABLE void blockCreator(const QString& creatorId);
    Q_INVOKABLE void muteCreator(const QString& creatorId);
    Q_INVOKABLE void updateOwnerVideoDetails(const QString& videoId, const QString& title, const QString& description);
    Q_INVOKABLE void updateOwnerVideoVisibility(const QString& videoId, const QString& visibility);
    Q_INVOKABLE void deleteOwnerVideo(const QString& videoId);
    Q_INVOKABLE void openHashtagDiscovery(const QString& tag);
    Q_INVOKABLE void closeHashtagDiscovery();
    Q_INVOKABLE void loadMoreHashtagDiscovery();
    Q_INVOKABLE void openAudioDiscovery(const QString& audioId);
    Q_INVOKABLE void closeAudioDiscovery();
    Q_INVOKABLE void loadMoreAudioDiscovery();
    Q_INVOKABLE void useSoundInPostComposer(const QVariantMap& audioObj);
    Q_INVOKABLE void clearPrefilledPostSong();
    Q_INVOKABLE void openFeedSearch();
    Q_INVOKABLE void closeFeedSearch();
    Q_INVOKABLE void updateFeedSearchQuery(const QString& query);
    Q_INVOKABLE void executeFeedSearch(const QString& query, bool reset);
    Q_INVOKABLE void clearAllSearchHistory();
    Q_INVOKABLE void deleteRecentSearch(const QString& id, const QString& query);
    Q_INVOKABLE void openModalFeedPlayer(const QVariantList& videos, int initialIndex, const QString& title);
    Q_INVOKABLE void closeModalFeedPlayer();
    Q_INVOKABLE void loadSavedVideos();
    Q_INVOKABLE void loadSafetyPreferences();
    Q_INVOKABLE void unblockUserFromSafety(const QString& userId);
    Q_INVOKABLE void unmuteUserFromSafety(const QString& userId);

    // Owner Profile actions
    Q_INVOKABLE void copyToClipboard(const QString& text, const QString& toastMsg);
    Q_INVOKABLE void refreshOwnerProfile(bool isPullGesture);
    Q_INVOKABLE void selectOwnerCategory(const QString& category);
    Q_INVOKABLE void uploadOwnerBackgroundPhotos(const QList<QUrl>& fileUrls);
    Q_INVOKABLE void deleteOwnerBackgroundPhoto(const QString& bgId);
    Q_INVOKABLE void openOwnerConnections(const QString& mode);
    Q_INVOKABLE void closeOwnerConnections();
    Q_INVOKABLE void toggleOwnerConnectionFollow(const QString& targetUserId);
    Q_INVOKABLE void openOwnerGridItem(const QVariantMap& item);
    Q_INVOKABLE void closeOwnerGridViewer();
    Q_INVOKABLE void toggleOwnerPostLike(const QString& postId);
    Q_INVOKABLE void toggleOwnerPostSave(const QString& postId);
    Q_INVOKABLE void toggleOwnerPostLock(const QString& postId);

    QString ownerActiveCategory() const { return ownerActiveCategory_; }
    QVariantList ownerActiveItems() const;
    bool ownerItemsLoading() const { return ownerItemsLoading_; }
    bool ownerRefreshing() const { return ownerRefreshing_; }
    bool ownerUploadingBackgrounds() const { return ownerUploadingBackgrounds_; }
    QString ownerLocalAvatarUrl() const;
    QStringList ownerLocalBackgroundUrls() const { return ownerLocalBackgroundUrls_; }
    QVariantList ownerBackgroundSlides() const;
    QString ownerConnectionsMode() const { return ownerConnectionsMode_; }
    QVariantList ownerConnectionsUsers() const { return ownerConnectionsUsers_; }
    bool ownerConnectionsLoading() const { return ownerConnectionsLoading_; }
    QVariantMap ownerActiveViewerItem() const { return ownerActiveViewerItem_; }

signals:
    void sessionChanged();
    void themeChanged();
    void authStepChanged();
    void emailChanged();
    void cooldownChanged();
    void loadingChanged();
    void errorChanged();
    void networkChanged();
    void conversationsChanged();
    void selectedConversationChanged();
    void messagesChanged();
    void outboxChanged();
    void profileSeedChanged();
    void avatarChanged();
    void activeTabChanged();
    void homeSearchChanged();
    void contactsChanged();
    void toastChanged();
    void editingProfileChanged();
    void myProfileChanged();
    void feedChanged();
    void notificationsChanged();

    void postComposerChanged();
    void postMusicChanged();
    void postAudioChanged();
    void postHashtagsChanged();
    void postMediaChanged();
    void postUploadChanged();

    void videoFeedChanged();
    void feedAudioStateChanged();
    void feedDiscoveryChanged();
    void savedSafetyChanged();
    void prefilledPostSongChanged();
    void ownerProfileChanged();
    void ownerConnectionsChanged();

private:
    void postJson(const QString& path, const QJsonObject& body, bool authed,
                  std::function<void(int, const QByteArray&)> callback, bool allowRefresh = true);
    void sendCustomJson(const QByteArray& verb, const QString& path, const QByteArray& bodyBytes, bool authed,
                        std::function<void(int, const QByteArray&)> callback, bool allowRefresh = true);
    void getJson(const QString& path, std::function<void(int, const QByteArray&)> callback, bool allowRefresh = true);
    void initFeedSubsystem();
    void initOwnerProfileSubsystem();
    void restoreOwnerProfileCache();
    void clearOwnerProfileCache();
    void saveOwnerAvatarBytesLocally(const QByteArray& jpegBytes);
    void syncOwnerMediaToLocalCache(const QJsonObject& profileObj);
    void loadOwnerProfileItemsInternal(const QString& tab);
    void patchOwnerItemEverywhere(const QString& postId, const std::function<void(QVariantMap&)>& mutator);
    void restoreEncryptedVideoFeedCaches();
    void clearEncryptedVideoFeedCaches();
    void persistVideoFeedCache(const QString& tab);
    void prefetchUpcomingVideos(const QVariantList& list, int currentIndex);
    void mutateVideoEverywhere(const QString& videoId, const std::function<void(QVariantMap&)>& mutator);
    void mutateCreatorFollowingEverywhere(const QString& creatorId, bool following);
    void removeVideoEverywhere(const QString& videoId);
    void removeCreatorVideosEverywhere(const QString& creatorId);
    void loadHashtagDiscoveryInternal(const QString& tag, bool reset);
    void loadAudioDiscoveryInternal(const QString& audioId, bool reset);
    void recordLocalRecentSearch(const QString& query);
    void refreshSessionAndThen(std::function<void(bool)> done);
    void persistSession(const QJsonObject& obj);
    void restoreSession();
    void seedProfileFromEmail(const QString& email);
    void setLoading(bool v);
    void setError(const QString& msg);
    void showToast(const QString& msg);
    void rebuildFilteredContacts();
    void persistContactsCache();
    void startCooldown(qint64 seconds);
    void uploadDraftAndCreatePost(const QJsonObject& draft, bool interactive);
    void enqueuePostDraft(const QJsonObject& draft);
    void flushQueuedPosts();
    QString computeQImageDHash(const QImage& img) const;

    telefam_engine_t* engine_ = nullptr;
    QNetworkAccessManager nam_;
    QTimer cooldownTimer_;
    QTimer contactSearchTimer_;
    QTimer toastTimer_;
    QString apiBase_;
    QString deviceFP_;
    QString hwAttest_;
    QString deviceName_;

    bool isDarkTheme_ = true;
    bool profileCompleted_ = false;
    bool isOffline_ = false;
    int authStep_ = 0; // 0 = Enter Email, 1 = Enter OTP
    QString email_;
    QString accessToken_;
    QString refreshToken_;
    QString userId_;
    qint64 cooldownSeconds_ = 0;
    bool loading_ = false;
    QString errorMessage_;
    QString networkLabel_ = QStringLiteral("Connected");
    QVariantList conversations_;
    QString selectedConversationId_;
    QVariantList messages_;

    QString profileFullName_;
    QString profileUsername_;
    QString profileCountryIso_ = QStringLiteral("KE");
    QString profileLocation_;
    QString avatarDataUrl_;
    QString avatarFingerprintHash_;
    QJsonObject lastSessionObj_;

    int activeTab_ = 0; // 0 = Chats, 1 = Contacts, 2 = Feeds, 3 = Profile
    QString homeSearchQuery_;
    QVariantList cachedContacts_;
    QVariantList filteredContacts_;
    QString contactFilter_ = QStringLiteral("all");
    QString contactSearchQuery_;
    bool contactsLoading_ = false;
    bool hasMoreContacts_ = false;
    QString contactsNextCursor_;
    QString toastMessage_;
    bool isEditingProfile_ = false;
    QVariantMap myProfile_;
    QVariantList feedPosts_;
    bool feedLoading_ = false;
    QVariantList notifications_;

    bool postComposerOpen_ = false;
    QVariantList postMusicResults_;
    bool postSearchingSongs_ = false;
    QString postPlayingPreviewTrackId_;
    QVariantList postHashtagResults_;
    bool postSearchingHashtags_ = false;
    QVariantList postPhotos_;
    QString postVideoPath_;
    qint64 postVideoDurationMs_ = 0;
    QVariantList postVideoFrames_;
    int postSelectedThumbIndex_ = -1;
    qint64 postTrimStartMs_ = 0;
    qint64 postTrimEndMs_ = 0;
    QString postUploadStatus_;
    int postUploadProgress_ = 0;
    QString postErrorMessage_;
    bool postQueueFlushing_ = false;
    QObject* mediaPlayerObj_ = nullptr;

    // Short-video Feed state
    QNetworkAccessManager prefetchNam_;
    QTimer feedSearchTimer_;
    QSet<QString> prefetchedVideoIds_;
    QString videoFeedTab_ = QStringLiteral("for_you");
    QVariantList forYouVideos_;
    QVariantList followingVideos_;
    QString forYouCursor_;
    QString followingCursor_;
    bool forYouHasMore_ = false;
    bool followingHasMore_ = false;
    bool videoFeedLoading_ = false;
    QString videoFeedError_;
    int activeForYouIndex_ = 0;
    int activeFollowingIndex_ = 0;
    bool feedMuted_ = false;

    bool feedSearchOpen_ = false;
    QString feedSearchQuery_;
    int feedSearchTab_ = 0;
    bool feedSearching_ = false;
    QVariantMap feedSearchResults_;
    QVariantList localRecentSearches_;

    QString activeHashtagTag_;
    QVariantMap hashtagDiscovery_;
    bool hashtagLoading_ = false;
    QString activeAudioId_;
    QVariantMap audioDiscovery_;
    bool audioLoading_ = false;

    QVariantList modalFeedVideos_;
    int modalFeedIndex_ = 0;
    QString modalFeedTitle_;
    bool modalFeedOpen_ = false;
    bool liveComingSoonOpen_ = false;

    QVariantList savedVideos_;
    bool savedVideosLoading_ = false;
    QVariantMap safetyPreferences_;
    bool safetyLoading_ = false;
    QVariantMap prefilledPostSong_;

    // Owner Profile state
    QString ownerCacheDir_;
    QString ownerActiveCategory_ = QStringLiteral("posts");
    QMap<QString, QVariantList> ownerItemsByCategory_;
    bool ownerItemsLoading_ = false;
    bool ownerRefreshing_ = false;
    bool ownerUploadingBackgrounds_ = false;
    QString ownerLocalAvatarUrl_;
    QStringList ownerLocalBackgroundUrls_;
    QString ownerConnectionsMode_;
    QVariantList ownerConnectionsUsers_;
    bool ownerConnectionsLoading_ = false;
    QVariantMap ownerActiveViewerItem_;
};

#endif
