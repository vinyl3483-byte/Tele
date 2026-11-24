#ifndef TELEFAM_DESKTOP_CONTROLLER_HPP
#define TELEFAM_DESKTOP_CONTROLLER_HPP

#include "telefam_core.h"

#include <QNetworkAccessManager>
#include <QObject>
#include <QTimer>
#include <QUrl>
#include <QVariantList>
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

    // Contacts & navigation tab
    Q_PROPERTY(int activeTab READ activeTab NOTIFY activeTabChanged)
    Q_PROPERTY(QVariantList contacts READ contacts NOTIFY contactsChanged)
    Q_PROPERTY(QString contactFilter READ contactFilter NOTIFY contactsChanged)
    Q_PROPERTY(QString contactSearchQuery READ contactSearchQuery NOTIFY contactsChanged)
    Q_PROPERTY(bool contactsLoading READ contactsLoading NOTIFY contactsChanged)
    Q_PROPERTY(bool hasMoreContacts READ hasMoreContacts NOTIFY contactsChanged)
    Q_PROPERTY(QString toastMessage READ toastMessage NOTIFY toastChanged)

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
    QVariantList contacts() const { return filteredContacts_; }
    QString contactFilter() const { return contactFilter_; }
    QString contactSearchQuery() const { return contactSearchQuery_; }
    bool contactsLoading() const { return contactsLoading_; }
    bool hasMoreContacts() const { return hasMoreContacts_; }
    QString toastMessage() const { return toastMessage_; }

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
    void contactsChanged();
    void toastChanged();

    void postComposerChanged();
    void postMusicChanged();
    void postAudioChanged();
    void postHashtagsChanged();
    void postMediaChanged();
    void postUploadChanged();

private:
    void postJson(const QString& path, const QJsonObject& body, bool authed,
                  std::function<void(int, const QByteArray&)> callback);
    void getJson(const QString& path, std::function<void(int, const QByteArray&)> callback);
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

    int activeTab_ = 0; // 0 = Chats, 1 = Contacts
    QVariantList cachedContacts_;
    QVariantList filteredContacts_;
    QString contactFilter_ = QStringLiteral("all");
    QString contactSearchQuery_;
    bool contactsLoading_ = false;
    bool hasMoreContacts_ = false;
    QString contactsNextCursor_;
    QString toastMessage_;

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
};

#endif
