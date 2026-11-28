#include "TelefamDesktopController.hpp"
#include "telefam_crypto.hpp"

#include <QBuffer>
#include <QDate>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QHttpMultiPart>
#include <QImage>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocale>
#include <QNetworkInformation>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QPainter>
#include <QProcess>
#include <QRandomGenerator>
#include <QStandardPaths>
#include <QSysInfo>
#include <QTimeZone>
#include <QUrlQuery>
#include <QUuid>
#include <algorithm>
#include <cmath>
#include <cstring>
#include <limits>
#include <vector>

#ifdef TELEFAM_HAS_QT_MULTIMEDIA
#include <QAudioOutput>
#include <QMediaPlayer>
#endif

TelefamDesktopController::TelefamDesktopController(QObject* parent)
    : QObject(parent) {
    const QString fallbackApi = QStringLiteral("https://api.telefam.app");
    const QString envBase = qEnvironmentVariable("TELEFAM_API_BASE_URL", fallbackApi).trimmed();
    const QUrl parsedBase(envBase);
    const QString scheme = parsedBase.scheme().toLower();
    const QString host = parsedBase.host().toLower();
    if (parsedBase.isValid() && !host.isEmpty() &&
        (scheme == QStringLiteral("https") ||
         (scheme == QStringLiteral("http") && (host == QStringLiteral("localhost") || host == QStringLiteral("127.0.0.1"))))) {
        apiBase_ = parsedBase.toString(QUrl::StripTrailingSlash);
    } else {
        apiBase_ = fallbackApi;
    }

    deviceName_ = QSysInfo::machineHostName();
    if (deviceName_.isEmpty()) deviceName_ = QStringLiteral("Desktop");

    const QString appDir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    QDir().mkpath(appDir);
    const QString vaultPath = appDir + QStringLiteral("/telefam_vault.dat");

    const QString saltPath = appDir + QStringLiteral("/.vault_salt");
    QByteArray saltBytes;
    {
        QFile saltFile(saltPath);
        if (saltFile.open(QIODevice::ReadOnly)) {
            saltBytes = saltFile.read(32);
            saltFile.close();
        }
    }
    if (saltBytes.size() != 32) {
        saltBytes.resize(32);
        QRandomGenerator::system()->fillRange(reinterpret_cast<quint32*>(saltBytes.data()), 8);
        QFile saltOut(saltPath);
        if (saltOut.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
            saltOut.write(saltBytes);
            saltOut.close();
            saltOut.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner);
        }
    }

    const QByteArray hwRaw = QSysInfo::machineUniqueId() + "|" + QSysInfo::prettyProductName().toUtf8();
    const auto keyVec = telefam::crypto::hkdf_sha256(
        reinterpret_cast<const uint8_t*>(hwRaw.constData()), static_cast<size_t>(hwRaw.size()),
        reinterpret_cast<const uint8_t*>(saltBytes.constData()), static_cast<size_t>(saltBytes.size()),
        reinterpret_cast<const uint8_t*>("telefam-desktop-key-v1"), 22, 32
    );
    engine_ = telefam_engine_create(vaultPath.toUtf8().constData(), keyVec.data(), 32);

    char fpBuf[65]{};
    telefam_compute_device_fingerprint(
        "desktop",
        QSysInfo::prettyProductName().toUtf8().constData(),
        deviceName_.toUtf8().constData(),
        QSysInfo::machineUniqueId().constData(),
        "telefam-desktop-fp-v1",
        fpBuf, sizeof(fpBuf)
    );
    deviceFP_ = QString::fromUtf8(fpBuf);

    char attBuf[65]{};
    telefam_compute_device_fingerprint(
        "desktop-attest",
        QSysInfo::kernelType().toUtf8().constData(),
        deviceName_.toUtf8().constData(),
        QSysInfo::machineUniqueId().constData(),
        "telefam-desktop-fp-v1",
        attBuf, sizeof(attBuf)
    );
    hwAttest_ = QString::fromUtf8(attBuf);

    connect(&cooldownTimer_, &QTimer::timeout, this, [this]() {
        if (cooldownSeconds_ > 0) {
            --cooldownSeconds_;
            emit cooldownChanged();
        } else {
            cooldownTimer_.stop();
        }
    });

    contactSearchTimer_.setSingleShot(true);
    contactSearchTimer_.setInterval(280);
    connect(&contactSearchTimer_, &QTimer::timeout, this, [this]() {
        refreshContacts(true);
    });

    toastTimer_.setSingleShot(true);
    toastTimer_.setInterval(1800);
    connect(&toastTimer_, &QTimer::timeout, this, [this]() {
        toastMessage_.clear();
        emit toastChanged();
    });

    if (QNetworkInformation::loadDefaultBackend()) {
        if (auto* netInfo = QNetworkInformation::instance()) {
            auto updateNet = [this, netInfo]() {
                if (netInfo->reachability() == QNetworkInformation::Reachability::Disconnected) {
                    isOffline_ = true;
                    networkLabel_ = QStringLiteral("Offline");
                } else {
                    isOffline_ = false;
                    networkLabel_ = QStringLiteral("Connected");
                    syncNow();
                }
                emit networkChanged();
            };
            connect(netInfo, &QNetworkInformation::reachabilityChanged, this, updateNet);
            updateNet();
        }
    }

    initFeedSubsystem();
    initOwnerProfileSubsystem();
    restoreSession();
    restoreOwnerProfileCache();
}

TelefamDesktopController::~TelefamDesktopController() {
    stopAudioPreview();
    if (engine_) telefam_engine_destroy(engine_);
}

void TelefamDesktopController::toggleTheme() {
    isDarkTheme_ = !isDarkTheme_;
    const QByteArray v = isDarkTheme_ ? QByteArrayLiteral("true") : QByteArrayLiteral("false");
    telefam_vault_put(engine_, "theme_dark", reinterpret_cast<const uint8_t*>(v.constData()), static_cast<size_t>(v.size()));
    emit themeChanged();
}

void TelefamDesktopController::showToast(const QString& msg) {
    toastMessage_ = msg;
    emit toastChanged();
    toastTimer_.start();
}

void TelefamDesktopController::selectTab(int tabIndex) {
    if (activeTab_ != tabIndex) {
        activeTab_ = tabIndex;
        emit activeTabChanged();
    }
    if (tabIndex == 1) {
        refreshContacts(true);
    } else if (tabIndex == 2) {
        if (activeFeedVideos().isEmpty()) {
            refreshVideoFeed(videoFeedTab_, true);
        } else {
            prefetchUpcomingVideos(activeFeedVideos(), activeVideoIndex());
        }
    } else if (tabIndex == 3) {
        refreshOwnerProfile(false);
    }
}

void TelefamDesktopController::setHomeSearchQuery(const QString& query) {
    if (homeSearchQuery_ != query) {
        homeSearchQuery_ = query;
        emit homeSearchChanged();
        emit conversationsChanged();
        emit feedChanged();
    }
}

QVariantList TelefamDesktopController::filteredConversations() const {
    const QString q = homeSearchQuery_.trimmed().toLower();
    if (q.isEmpty()) return conversations_;
    QVariantList out;
    for (const auto& item : conversations_) {
        if (item.toMap().value("title").toString().toLower().contains(q)) {
            out.append(item);
        }
    }
    return out;
}

QVariantList TelefamDesktopController::feedPosts() const {
    const QString q = homeSearchQuery_.trimmed().toLower();
    if (q.isEmpty()) return feedPosts_;
    QVariantList out;
    for (const auto& item : feedPosts_) {
        const auto m = item.toMap();
        if (m.value("body").toString().toLower().contains(q) ||
            m.value("author_name").toString().toLower().contains(q) ||
            m.value("author_handle").toString().toLower().contains(q)) {
            out.append(item);
        }
    }
    return out;
}

int TelefamDesktopController::unreadNotificationCount() const {
    int count = 0;
    for (const auto& item : notifications_) {
        if (!item.toMap().value("is_read").toBool()) ++count;
    }
    return count;
}

void TelefamDesktopController::selectContactFilter(const QString& filter) {
    const QString norm = filter.trimmed().toLower();
    if (contactFilter_ != norm) {
        contactFilter_ = norm;
        contactsNextCursor_.clear();
        hasMoreContacts_ = false;
        rebuildFilteredContacts();
        refreshContacts(true);
    }
}

void TelefamDesktopController::setContactSearchQuery(const QString& query) {
    if (contactSearchQuery_ != query) {
        contactSearchQuery_ = query;
        rebuildFilteredContacts();
        contactSearchTimer_.start();
    }
}

void TelefamDesktopController::loadMoreContacts() {
    if (contactsLoading_ || !hasMoreContacts_ || contactsNextCursor_.isEmpty()) return;
    refreshContacts(false);
}

void TelefamDesktopController::refreshContacts(bool reset) {
    if (accessToken_.isEmpty() || !profileCompleted_ || isOffline_) {
        if (contactsLoading_) {
            contactsLoading_ = false;
            emit contactsChanged();
        }
        return;
    }
    if (!reset && (contactsLoading_ || !hasMoreContacts_ || contactsNextCursor_.isEmpty())) {
        return;
    }
    contactsLoading_ = true;
    emit contactsChanged();

    const QString cursor = reset ? QString() : contactsNextCursor_;
    QUrlQuery q;
    q.addQueryItem(QStringLiteral("filter"), contactFilter_);
    q.addQueryItem(QStringLiteral("q"), contactSearchQuery_);
    q.addQueryItem(QStringLiteral("cursor"), cursor);
    q.addQueryItem(QStringLiteral("limit"), QStringLiteral("30"));

    const QString path = QStringLiteral("/v1/contacts?") + q.toString(QUrl::FullyEncoded);
    const bool replaceAll = reset && contactFilter_ == QStringLiteral("all") && contactSearchQuery_.trimmed().isEmpty();

    getJson(path, [this, replaceAll](int status, const QByteArray& raw) {
        contactsLoading_ = false;
        if (status >= 200 && status < 300) {
            const auto doc = QJsonDocument::fromJson(raw).object();
            const auto arr = doc.value("contacts").toArray();
            if (replaceAll) {
                cachedContacts_.clear();
            }
            for (const auto& v : arr) {
                const auto obj = v.toObject();
                const QString uid = obj.value("user_id").toString();
                QVariantMap m = obj.toVariantMap();
                bool updated = false;
                for (int i = 0; i < cachedContacts_.size(); ++i) {
                    if (cachedContacts_[i].toMap().value("user_id").toString() == uid) {
                        cachedContacts_[i] = m;
                        updated = true;
                        break;
                    }
                }
                if (!updated) {
                    cachedContacts_.append(m);
                }
            }
            contactsNextCursor_ = doc.value("next_cursor").toString();
            hasMoreContacts_ = doc.value("has_more").toBool(false);
            persistContactsCache();
            rebuildFilteredContacts();
        } else {
            emit contactsChanged();
        }
    });
}

void TelefamDesktopController::toggleFollow(const QString& targetUserId) {
    int idx = -1;
    for (int i = 0; i < cachedContacts_.size(); ++i) {
        if (cachedContacts_[i].toMap().value("user_id").toString() == targetUserId) {
            idx = i;
            break;
        }
    }
    if (idx < 0) return;

    const qint64 nowSec = QDateTime::currentSecsSinceEpoch();
    if (telefam_follow_rate_limit_allow(engine_, userId_.toUtf8().constData(), nowSec) != 1) {
        showToast(QStringLiteral("Try again later"));
        return;
    }

    QVariantMap prevMap = cachedContacts_[idx].toMap();
    const bool prevFollowing = prevMap.value("is_following").toBool();
    const bool followsMe = prevMap.value("follows_me").toBool();
    const bool nextFollowing = !prevFollowing;
    auto relString = [](bool f, bool fm) -> QString {
        switch (telefam_relationship_state(f ? 1 : 0, fm ? 1 : 0)) {
            case 3: return QStringLiteral("friends");
            case 2: return QStringLiteral("following");
            case 1: return QStringLiteral("follow_back");
            default: return QStringLiteral("follow");
        }
    };

    QVariantMap nextMap = prevMap;
    nextMap.insert("is_following", nextFollowing);
    nextMap.insert("relationship", relString(nextFollowing, followsMe));
    cachedContacts_[idx] = nextMap;
    persistContactsCache();
    rebuildFilteredContacts();

    const QString actionType = nextFollowing ? QStringLiteral("follow_user") : QStringLiteral("unfollow_user");
    const QString mutId = QUuid::createUuid().toString(QUuid::WithoutBraces);
    const QByteArray payload = QJsonDocument(QJsonObject{{"target_user_id", targetUserId}}).toJson(QJsonDocument::Compact);

    if (isOffline_) {
        telefam_outbox_enqueue(engine_, mutId.toUtf8().constData(), actionType.toUtf8().constData(), payload.constData(),
                               QDateTime::currentMSecsSinceEpoch());
        emit outboxChanged();
        return;
    }

    postJson(QStringLiteral("/v1/contacts/follow"),
             QJsonObject{{"target_user_id", targetUserId}, {"follow", nextFollowing}},
             true,
             [this, targetUserId, prevMap, mutId, actionType, payload](int status, const QByteArray& raw) {
        if (status >= 200 && status < 300) {
            const auto obj = QJsonDocument::fromJson(raw).object();
            for (int i = 0; i < cachedContacts_.size(); ++i) {
                QVariantMap m = cachedContacts_[i].toMap();
                if (m.value("user_id").toString() == targetUserId) {
                    m.insert("is_following", obj.value("is_following").toBool());
                    m.insert("follows_me", obj.value("follows_me").toBool());
                    m.insert("relationship", obj.value("relationship").toString());
                    m.insert("risk_score", obj.value("risk_score").toInt());
                    cachedContacts_[i] = m;
                    break;
                }
            }
            persistContactsCache();
            rebuildFilteredContacts();
        } else if (status == 0) {
            telefam_outbox_enqueue(engine_, mutId.toUtf8().constData(), actionType.toUtf8().constData(), payload.constData(),
                                   QDateTime::currentMSecsSinceEpoch());
            emit outboxChanged();
        } else {
            for (int i = 0; i < cachedContacts_.size(); ++i) {
                if (cachedContacts_[i].toMap().value("user_id").toString() == targetUserId) {
                    cachedContacts_[i] = prevMap;
                    break;
                }
            }
            persistContactsCache();
            rebuildFilteredContacts();
            if (status == 429) {
                showToast(QStringLiteral("Try again later"));
            } else {
                char safeBuf[160]{};
                telefam_sanitize_error(status, nullptr, safeBuf, sizeof(safeBuf));
                showToast(QString::fromUtf8(safeBuf));
            }
        }
    });
}

void TelefamDesktopController::rebuildFilteredContacts() {
    filteredContacts_.clear();
    const QString q = contactSearchQuery_.trimmed().toLower();
    for (const auto& item : cachedContacts_) {
        const QVariantMap m = item.toMap();
        const bool isFollowing = m.value("is_following").toBool();
        const bool followsMe = m.value("follows_me").toBool();
        bool matchFilter = true;
        if (contactFilter_ == QStringLiteral("suggestions")) matchFilter = !isFollowing;
        else if (contactFilter_ == QStringLiteral("followers")) matchFilter = followsMe;
        else if (contactFilter_ == QStringLiteral("following")) matchFilter = isFollowing;
        else if (contactFilter_ == QStringLiteral("friends")) matchFilter = isFollowing && followsMe;

        const bool matchQuery = q.isEmpty() ||
            m.value("full_name").toString().toLower().contains(q) ||
            m.value("username").toString().toLower().contains(q);

        if (matchFilter && matchQuery) {
            filteredContacts_.append(m);
        }
    }
    emit contactsChanged();
}

void TelefamDesktopController::persistContactsCache() {
    QJsonArray arr;
    for (const auto& item : cachedContacts_) {
        arr.append(QJsonObject::fromVariantMap(item.toMap()));
    }
    const QByteArray bytes = QJsonDocument(arr).toJson(QJsonDocument::Compact);
    telefam_vault_put(engine_, "contacts_cache_json",
                      reinterpret_cast<const uint8_t*>(bytes.constData()),
                      static_cast<size_t>(bytes.size()));
}

void TelefamDesktopController::setEmail(const QString& value) {
    if (email_ != value) {
        email_ = value;
        emit emailChanged();
    }
}

void TelefamDesktopController::setLoading(bool v) {
    if (loading_ != v) {
        loading_ = v;
        emit loadingChanged();
    }
}

void TelefamDesktopController::setError(const QString& msg) {
    errorMessage_ = msg;
    emit errorChanged();
}

void TelefamDesktopController::startCooldown(qint64 seconds) {
    cooldownSeconds_ = std::max<qint64>(0, seconds);
    emit cooldownChanged();
    if (cooldownSeconds_ > 0) {
        cooldownTimer_.start(1000);
    } else {
        cooldownTimer_.stop();
    }
}

void TelefamDesktopController::sendOtp(bool isResend) {
    Q_UNUSED(isResend)
    setError(QString());
    const QString trimmed = email_.trimmed();
    if (telefam_validate_email(trimmed.toUtf8().constData()) != 1) {
        setError(QStringLiteral("Please enter a valid email address."));
        return;
    }
    setEmail(trimmed);

    char ipBuf[65]{};
    telefam_compute_ip_fingerprint("desktop-edge", "local", "telefam-desktop-ip-v1", ipBuf, sizeof(ipBuf));
    const qint64 nowSec = QDateTime::currentSecsSinceEpoch();
    if (telefam_rate_limit_allow(engine_, trimmed.toUtf8().constData(),
                                 deviceFP_.toUtf8().constData(), ipBuf, nowSec) != 1) {
        char safeBuf[160]{};
        telefam_sanitize_error(429, nullptr, safeBuf, sizeof(safeBuf));
        setError(QString::fromUtf8(safeBuf));
        return;
    }

    telefam_cooldown_state_t state{};
    telefam_otp_check_cooldown(engine_, trimmed.toUtf8().constData(), nowSec, &state);
    if (state.can_resend != 1) {
        startCooldown(state.remaining_seconds);
        authStep_ = 1;
        emit authStepChanged();
        return;
    }

    setLoading(true);
    QJsonObject body{
        {"email", trimmed},
        {"device_fingerprint", deviceFP_},
        {"hardware_attestation", hwAttest_},
        {"device_name", deviceName_},
        {"platform", "desktop"}
    };
    postJson(QStringLiteral("/v1/auth/otp/send"), body, false, [this, trimmed](int status, const QByteArray& raw) {
        setLoading(false);
        if (status >= 200 && status < 300) {
            telefam_cooldown_state_t recorded{};
            telefam_otp_record_send(engine_, trimmed.toUtf8().constData(), QDateTime::currentSecsSinceEpoch(), &recorded);
            const auto doc = QJsonDocument::fromJson(raw).object();
            const qint64 serverSecs = doc.value("cooldown_seconds").toInteger();
            startCooldown(std::max<qint64>(serverSecs, recorded.remaining_seconds));
            authStep_ = 1;
            emit authStepChanged();
        } else {
            char safeBuf[160]{};
            telefam_sanitize_error(status, nullptr, safeBuf, sizeof(safeBuf));
            setError(QString::fromUtf8(safeBuf));
        }
    });
}

void TelefamDesktopController::verifyOtp(const QString& otp, const QString& magicToken) {
    setError(QString());
    if (magicToken.isEmpty() && telefam_validate_otp(otp.toUtf8().constData()) != 1) {
        setError(QStringLiteral("Please enter the 6-digit verification code."));
        return;
    }
    setLoading(true);
    QJsonObject body{
        {"email", email_},
        {"otp", otp},
        {"magic_token", magicToken},
        {"device_fingerprint", deviceFP_},
        {"hardware_attestation", hwAttest_},
        {"device_name", deviceName_},
        {"platform", "desktop"}
    };
    postJson(QStringLiteral("/v1/auth/otp/verify"), body, false, [this](int status, const QByteArray& raw) {
        setLoading(false);
        if (status >= 200 && status < 300) {
            telefam_otp_reset_cooldown(engine_, email_.toUtf8().constData());
            persistSession(QJsonDocument::fromJson(raw).object());
            if (profileCompleted_) {
                syncNow();
            }
        } else {
            char safeBuf[160]{};
            telefam_sanitize_error(status, nullptr, safeBuf, sizeof(safeBuf));
            setError(QString::fromUtf8(safeBuf));
        }
    });
}

void TelefamDesktopController::verifyGoogleIdToken(const QString& idToken) {
    setError(QString());
    setLoading(true);
    QJsonObject body{
        {"id_token", idToken},
        {"device_fingerprint", deviceFP_},
        {"hardware_attestation", hwAttest_},
        {"device_name", deviceName_},
        {"platform", "desktop"}
    };
    postJson(QStringLiteral("/v1/auth/oauth/google"), body, false, [this](int status, const QByteArray& raw) {
        setLoading(false);
        if (status >= 200 && status < 300) {
            persistSession(QJsonDocument::fromJson(raw).object());
            if (profileCompleted_) {
                syncNow();
            }
        } else {
            char safeBuf[160]{};
            telefam_sanitize_error(status, nullptr, safeBuf, sizeof(safeBuf));
            setError(QString::fromUtf8(safeBuf));
        }
    });
}

void TelefamDesktopController::changeEmail() {
    setError(QString());
    authStep_ = 0;
    emit authStepChanged();
}

void TelefamDesktopController::cropAndUploadAvatar(const QUrl& fileUrl, qreal zoom, qreal offsetXRatio, qreal offsetYRatio) {
    const QString localPath = fileUrl.isLocalFile() ? fileUrl.toLocalFile() : fileUrl.toString();
    QImage src(localPath);
    if (src.isNull()) return;

    const int target = 512;
    QImage out(target, target, QImage::Format_ARGB32);
    out.fill(Qt::black);

    const qreal clampedZoom = std::clamp<qreal>(zoom, 1.0, 3.0);
    const qreal baseScale = std::max(
        static_cast<qreal>(target) / src.width(),
        static_cast<qreal>(target) / src.height()
    ) * clampedZoom;
    const qreal drawW = src.width() * baseScale;
    const qreal drawH = src.height() * baseScale;
    const qreal dx = offsetXRatio * target;
    const qreal dy = offsetYRatio * target;

    QPainter painter(&out);
    painter.setRenderHint(QPainter::SmoothPixmapTransform, true);
    painter.drawImage(
        QRectF((target - drawW) / 2.0 + dx, (target - drawH) / 2.0 + dy, drawW, drawH),
        src
    );
    painter.end();

    QByteArray jpegBytes;
    QBuffer buf(&jpegBytes);
    buf.open(QIODevice::WriteOnly);
    out.save(&buf, "JPEG", 90);

    avatarDataUrl_ = QStringLiteral("data:image/jpeg;base64,") + QString::fromLatin1(jpegBytes.toBase64());
    saveOwnerAvatarBytesLocally(jpegBytes);
    emit avatarChanged();

    if (!isOffline_ && !accessToken_.isEmpty()) {
        QNetworkRequest req(QUrl(apiBase_ + QStringLiteral("/v1/profile/avatar")));
        req.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("image/jpeg"));
        req.setTransferTimeout(12000);
        req.setRawHeader("Authorization", QByteArray("Bearer ") + accessToken_.toUtf8());
        auto* reply = nam_.post(req, jpegBytes);
        connect(reply, &QNetworkReply::finished, this, [this, reply]() {
            const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
            const QByteArray data = reply->readAll();
            reply->deleteLater();
            if (status >= 200 && status < 300) {
                avatarFingerprintHash_ = QJsonDocument::fromJson(data).object().value("avatar_fingerprint_hash").toString();
                if (!myProfile_.isEmpty() && !avatarFingerprintHash_.isEmpty()) {
                    myProfile_.insert("avatar_fingerprint_hash", avatarFingerprintHash_);
                    const QByteArray bytes = QJsonDocument(QJsonObject::fromVariantMap(myProfile_)).toJson(QJsonDocument::Compact);
                    telefam_vault_put(engine_, "my_profile_json",
                                      reinterpret_cast<const uint8_t*>(bytes.constData()),
                                      static_cast<size_t>(bytes.size()));
                    emit myProfileChanged();
                    emit ownerProfileChanged();
                }
            }
        });
    }
}

void TelefamDesktopController::submitProfileSetup(
    const QString& fullName,
    const QString& username,
    const QString& countryIso,
    const QString& phoneNumber,
    const QString& gender,
    const QString& dobIso,
    const QString& location,
    const QString& bio
) {
    setError(QString());
    const QString fn = fullName.trimmed();
    const QString un = username.trimmed().toLower();
    if (fn.length() < 2 || un.length() < 3 || gender.trimmed().isEmpty()) {
        setError(QStringLiteral("Please complete all required fields."));
        return;
    }
    if (telefam_validate_phone_number(countryIso.toUtf8().constData(), phoneNumber.toUtf8().constData()) != 1) {
        setError(QStringLiteral("Please enter a valid phone number for the selected country."));
        return;
    }
    const QDate dob = QDate::fromString(dobIso.trimmed(), QStringLiteral("yyyy-MM-dd"));
    const QDate today = QDate::currentDate();
    if (!dob.isValid() || telefam_validate_age_13_plus(
            dob.year(), dob.month(), dob.day(),
            today.year(), today.month(), today.day()) != 1) {
        setError(QStringLiteral("You must be at least 13 years old."));
        return;
    }

    QJsonObject reqObj{
        {"full_name", fn},
        {"username", un},
        {"country_iso", countryIso.toUpper()},
        {"phone_number", phoneNumber.trimmed()},
        {"gender", gender},
        {"date_of_birth", dobIso.trimmed()},
        {"location", location.trimmed()},
        {"bio", bio.trimmed().left(150)},
        {"avatar_fingerprint_hash", avatarFingerprintHash_}
    };

    if (isOffline_) {
        const QString mutId = QUuid::createUuid().toString(QUuid::WithoutBraces);
        const QByteArray payload = QJsonDocument(reqObj).toJson(QJsonDocument::Compact);
        telefam_outbox_enqueue(engine_, mutId.toUtf8().constData(), "profile_setup", payload.constData(),
                               QDateTime::currentMSecsSinceEpoch());
        emit outboxChanged();
        isEditingProfile_ = false;
        emit editingProfileChanged();
        lastSessionObj_.insert("profile_completed", true);
        lastSessionObj_.insert("display_name", fn);
        persistSession(lastSessionObj_);
        return;
    }

    setLoading(true);
    postJson(QStringLiteral("/v1/profile/setup"), reqObj, true, [this, fn](int status, const QByteArray& raw) {
        setLoading(false);
        if (status >= 200 && status < 300) {
            const auto obj = QJsonDocument::fromJson(raw).object();
            if (!obj.isEmpty() && !obj.value("user_id").toString().isEmpty()) {
                myProfile_ = obj.toVariantMap();
                const QByteArray bytes = QJsonDocument(obj).toJson(QJsonDocument::Compact);
                telefam_vault_put(engine_, "my_profile_json",
                                  reinterpret_cast<const uint8_t*>(bytes.constData()),
                                  static_cast<size_t>(bytes.size()));
                emit myProfileChanged();
                emit ownerProfileChanged();
            }
            isEditingProfile_ = false;
            emit editingProfileChanged();
            lastSessionObj_.insert("profile_completed", true);
            lastSessionObj_.insert("display_name", fn);
            persistSession(lastSessionObj_);
            syncNow();
        } else {
            char safeBuf[160]{};
            telefam_sanitize_error(status, nullptr, safeBuf, sizeof(safeBuf));
            setError(QString::fromUtf8(safeBuf));
        }
    });
}

void TelefamDesktopController::selectConversation(const QString& id) {
    if (selectedConversationId_ != id) {
        selectedConversationId_ = id;
        emit selectedConversationChanged();
        syncNow();
    }
}

void TelefamDesktopController::createConversation(const QString& title) {
    const QString trimmed = title.trimmed();
    if (trimmed.isEmpty()) return;
    postJson(QStringLiteral("/v1/conversations"), QJsonObject{{"title", trimmed}}, true, [this](int status, const QByteArray& raw) {
        if (status >= 200 && status < 300) {
            const auto obj = QJsonDocument::fromJson(raw).object();
            selectedConversationId_ = obj.value("id").toString();
            emit selectedConversationChanged();
            syncNow();
        }
    });
}

void TelefamDesktopController::sendMessageOfflineFirst(const QString& body) {
    const QString trimmed = body.trimmed();
    if (trimmed.isEmpty() || selectedConversationId_.isEmpty()) return;

    const QString mutId = QUuid::createUuid().toString(QUuid::WithoutBraces);
    const qint64 nowMs = QDateTime::currentMSecsSinceEpoch();
    QVariantMap optimistic{
        {"id", mutId},
        {"conversation_id", selectedConversationId_},
        {"sender_id", userId_},
        {"body", trimmed},
        {"created_at", nowMs},
        {"pending", true}
    };
    messages_.append(optimistic);
    emit messagesChanged();

    const QByteArray payload = QJsonDocument(QJsonObject{
        {"conversation_id", selectedConversationId_},
        {"body", trimmed}
    }).toJson(QJsonDocument::Compact);

    telefam_outbox_enqueue(engine_, mutId.toUtf8().constData(), "send_message", payload.constData(), nowMs);
    emit outboxChanged();
    syncNow();
}

void TelefamDesktopController::syncNow() {
    if (accessToken_.isEmpty() || !profileCompleted_ || isOffline_) return;
    if (pendingSyncCount() > 0) {
        char buf[65536]{};
        if (telefam_outbox_peek_batch(engine_, 16, buf, sizeof(buf)) == TELEFAM_OK) {
            const auto arr = QJsonDocument::fromJson(QByteArray(buf)).array();
            postJson(QStringLiteral("/v1/sync/mutations"), QJsonObject{{"mutations", arr}}, true, [this](int status, const QByteArray& raw) {
                if (status >= 200 && status < 300) {
                    const auto acked = QJsonDocument::fromJson(raw).object().value("acked_ids").toArray();
                    for (const auto& id : acked) {
                        telefam_outbox_ack(engine_, id.toString().toUtf8().constData());
                    }
                    emit outboxChanged();
                }
            });
        }
    }

    getJson(QStringLiteral("/v1/conversations"), [this](int status, const QByteArray& raw) {
        if (status >= 200 && status < 300) {
            const auto arr = QJsonDocument::fromJson(raw).object().value("conversations").toArray();
            QVariantList list;
            for (const auto& v : arr) list.append(v.toObject().toVariantMap());
            conversations_ = list;
            const QByteArray cBytes = QJsonDocument(arr).toJson(QJsonDocument::Compact);
            telefam_vault_put(engine_, "conversations_json",
                              reinterpret_cast<const uint8_t*>(cBytes.constData()),
                              static_cast<size_t>(cBytes.size()));
            emit conversationsChanged();
        }
    });

    if (!selectedConversationId_.isEmpty()) {
        getJson(QStringLiteral("/v1/conversations/") + selectedConversationId_ + QStringLiteral("/messages"),
                [this](int status, const QByteArray& raw) {
            if (status >= 200 && status < 300) {
                const auto arr = QJsonDocument::fromJson(raw).object().value("messages").toArray();
                QVariantList list;
                for (const auto& v : arr) {
                    auto m = v.toObject().toVariantMap();
                    m.insert("pending", false);
                    list.append(m);
                }
                messages_ = list;
                emit messagesChanged();
            }
        });
    }

    refreshContacts(true);
    refreshMyProfile();
    refreshFeedPosts();
    refreshNotifications();
    flushQueuedPosts();
}

void TelefamDesktopController::refreshMyProfile() {
    if (accessToken_.isEmpty() || isOffline_) return;
    getJson(QStringLiteral("/v1/profile/me"), [this](int status, const QByteArray& raw) {
        if (status >= 200 && status < 300) {
            const auto obj = QJsonDocument::fromJson(raw).object();
            myProfile_ = obj.toVariantMap();
            const QByteArray bytes = QJsonDocument(obj).toJson(QJsonDocument::Compact);
            telefam_vault_put(engine_, "my_profile_json",
                              reinterpret_cast<const uint8_t*>(bytes.constData()),
                              static_cast<size_t>(bytes.size()));
            emit myProfileChanged();
            syncOwnerMediaToLocalCache(obj);
            emit ownerProfileChanged();
        }
    });
}

void TelefamDesktopController::refreshFeedPosts() {
    if (accessToken_.isEmpty() || isOffline_) {
        if (feedLoading_) {
            feedLoading_ = false;
            emit feedChanged();
        }
        return;
    }
    feedLoading_ = true;
    emit feedChanged();
    QUrlQuery q;
    q.addQueryItem(QStringLiteral("q"), homeSearchQuery_.trimmed());
    q.addQueryItem(QStringLiteral("limit"), QStringLiteral("30"));
    getJson(QStringLiteral("/v1/posts/feed?") + q.toString(QUrl::FullyEncoded), [this](int status, const QByteArray& raw) {
        feedLoading_ = false;
        if (status >= 200 && status < 300) {
            const auto arr = QJsonDocument::fromJson(raw).object().value("posts").toArray();
            QVariantList list;
            for (const auto& v : arr) list.append(v.toObject().toVariantMap());
            feedPosts_ = list;
            if (homeSearchQuery_.trimmed().isEmpty()) {
                const QByteArray bytes = QJsonDocument(arr).toJson(QJsonDocument::Compact);
                telefam_vault_put(engine_, "feed_cache_json",
                                  reinterpret_cast<const uint8_t*>(bytes.constData()),
                                  static_cast<size_t>(bytes.size()));
            }
        }
        emit feedChanged();
    });
}

void TelefamDesktopController::refreshNotifications() {
    if (accessToken_.isEmpty() || isOffline_) return;
    getJson(QStringLiteral("/v1/notifications"), [this](int status, const QByteArray& raw) {
        if (status >= 200 && status < 300) {
            const auto arr = QJsonDocument::fromJson(raw).object().value("notifications").toArray();
            QVariantList list;
            for (const auto& v : arr) list.append(v.toObject().toVariantMap());
            notifications_ = list;
            const QByteArray bytes = QJsonDocument(arr).toJson(QJsonDocument::Compact);
            telefam_vault_put(engine_, "notifications_json",
                              reinterpret_cast<const uint8_t*>(bytes.constData()),
                              static_cast<size_t>(bytes.size()));
            emit notificationsChanged();
        }
    });
}

void TelefamDesktopController::markNotificationsRead() {
    QJsonArray updatedArr;
    QVariantList updatedList;
    for (const auto& item : notifications_) {
        auto m = item.toMap();
        m.insert("is_read", true);
        updatedList.append(m);
        updatedArr.append(QJsonObject::fromVariantMap(m));
    }
    notifications_ = updatedList;
    const QByteArray bytes = QJsonDocument(updatedArr).toJson(QJsonDocument::Compact);
    telefam_vault_put(engine_, "notifications_json",
                      reinterpret_cast<const uint8_t*>(bytes.constData()),
                      static_cast<size_t>(bytes.size()));
    emit notificationsChanged();
    if (!accessToken_.isEmpty() && !isOffline_) {
        postJson(QStringLiteral("/v1/notifications/read"), QJsonObject{}, true, [](int, const QByteArray&) {});
    }
}

void TelefamDesktopController::openEditProfile() {
    if (!myProfile_.isEmpty()) {
        profileFullName_ = myProfile_.value("full_name").toString();
        profileUsername_ = myProfile_.value("username").toString();
        const QString cIso = myProfile_.value("country_iso").toString();
        if (!cIso.isEmpty()) profileCountryIso_ = cIso;
        profileLocation_ = myProfile_.value("location").toString();
        avatarFingerprintHash_ = myProfile_.value("avatar_fingerprint_hash").toString();
        emit profileSeedChanged();
    } else if (!email_.isEmpty()) {
        seedProfileFromEmail(email_);
    }
    setError(QString());
    isEditingProfile_ = true;
    emit editingProfileChanged();
}

void TelefamDesktopController::closeEditProfile() {
    setError(QString());
    isEditingProfile_ = false;
    emit editingProfileChanged();
}

void TelefamDesktopController::signOut() {
    if (!accessToken_.isEmpty() && !isOffline_) {
        QNetworkRequest req(QUrl(apiBase_ + QStringLiteral("/v1/auth/logout")));
        req.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
        req.setTransferTimeout(5000);
        req.setRawHeader("Authorization", QByteArray("Bearer ") + accessToken_.toUtf8());
        auto* reply = nam_.post(req, QByteArrayLiteral("{}"));
        connect(reply, &QNetworkReply::finished, reply, &QNetworkReply::deleteLater);
    }
    stopAudioPreview();
    telefam_vault_delete(engine_, "session_json");
    telefam_vault_delete(engine_, "conversations_json");
    telefam_vault_delete(engine_, "contacts_cache_json");
    telefam_vault_delete(engine_, "queued_posts_json");
    telefam_vault_delete(engine_, "my_profile_json");
    telefam_vault_delete(engine_, "feed_cache_json");
    telefam_vault_delete(engine_, "notifications_json");
    clearEncryptedVideoFeedCaches();
    clearOwnerProfileCache();
    accessToken_.clear();
    refreshToken_.clear();
    userId_.clear();
    profileCompleted_ = false;
    isEditingProfile_ = false;
    lastSessionObj_ = QJsonObject{};
    myProfile_.clear();
    feedPosts_.clear();
    notifications_.clear();
    homeSearchQuery_.clear();
    conversations_.clear();
    messages_.clear();
    cachedContacts_.clear();
    filteredContacts_.clear();
    selectedConversationId_.clear();
    activeTab_ = 0;
    authStep_ = 0;
    postComposerOpen_ = false;
    emit sessionChanged();
    emit editingProfileChanged();
    emit myProfileChanged();
    emit feedChanged();
    emit notificationsChanged();
    emit homeSearchChanged();
    emit authStepChanged();
    emit activeTabChanged();
    emit conversationsChanged();
    emit messagesChanged();
    emit contactsChanged();
    emit postComposerChanged();
}

// MARK: - New Post Composer

void TelefamDesktopController::openPostComposer() {
    postComposerOpen_ = true;
    postUploadStatus_.clear();
    postUploadProgress_ = 0;
    postErrorMessage_.clear();
    emit postComposerChanged();
    emit postUploadChanged();
    if (postMusicResults_.isEmpty()) searchMusic(QString());
    if (postHashtagResults_.isEmpty()) searchHashtags(QString());
}

void TelefamDesktopController::closePostComposer() {
    stopAudioPreview();
    postComposerOpen_ = false;
    postPhotos_.clear();
    clearPostVideo();
    postUploadStatus_.clear();
    postUploadProgress_ = 0;
    postErrorMessage_.clear();
    emit postComposerChanged();
    emit postMediaChanged();
    emit postUploadChanged();
}

void TelefamDesktopController::searchMusic(const QString& query) {
    if (accessToken_.isEmpty() || isOffline_) return;
    postSearchingSongs_ = true;
    emit postMusicChanged();

    QUrlQuery q;
    q.addQueryItem(QStringLiteral("q"), query.trimmed());
    const QString path = QStringLiteral("/v1/music/search?") + q.toString(QUrl::FullyEncoded);
    getJson(path, [this](int status, const QByteArray& raw) {
        postSearchingSongs_ = false;
        if (status >= 200 && status < 300) {
            const auto arr = QJsonDocument::fromJson(raw).object().value("tracks").toArray();
            QVariantList list;
            for (const auto& v : arr) list.append(v.toObject().toVariantMap());
            postMusicResults_ = list;
        }
        emit postMusicChanged();
    });
}

void TelefamDesktopController::toggleSongPreview(const QString& trackId, const QString& previewUrl) {
    if (previewUrl.trimmed().isEmpty()) return;
    if (postPlayingPreviewTrackId_ == trackId) {
        stopAudioPreview();
        return;
    }
    stopAudioPreview();

#ifdef TELEFAM_HAS_QT_MULTIMEDIA
    auto* player = new QMediaPlayer(this);
    auto* audioOut = new QAudioOutput(player);
    audioOut->setVolume(0.85f);
    player->setAudioOutput(audioOut);
    player->setSource(QUrl(previewUrl));
    connect(player, &QMediaPlayer::playbackStateChanged, this, [this](QMediaPlayer::PlaybackState st) {
        if (st == QMediaPlayer::StoppedState && !postPlayingPreviewTrackId_.isEmpty()) {
            postPlayingPreviewTrackId_.clear();
            emit postAudioChanged();
        }
    });
    mediaPlayerObj_ = player;
    postPlayingPreviewTrackId_ = trackId;
    emit postAudioChanged();
    player->play();
#else
    auto* proc = new QProcess(this);
    connect(proc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished), this, [this](int, QProcess::ExitStatus) {
        postPlayingPreviewTrackId_.clear();
        emit postAudioChanged();
    });
    proc->start(QStringLiteral("ffplay"), {QStringLiteral("-nodisp"), QStringLiteral("-autoexit"), QStringLiteral("-loglevel"), QStringLiteral("quiet"), previewUrl});
    mediaPlayerObj_ = proc;
    postPlayingPreviewTrackId_ = trackId;
    emit postAudioChanged();
#endif
}

void TelefamDesktopController::stopAudioPreview() {
    if (mediaPlayerObj_) {
#ifdef TELEFAM_HAS_QT_MULTIMEDIA
        if (auto* p = qobject_cast<QMediaPlayer*>(mediaPlayerObj_)) {
            p->stop();
        }
#else
        if (auto* proc = qobject_cast<QProcess*>(mediaPlayerObj_)) {
            proc->kill();
            proc->waitForFinished(300);
        }
#endif
        mediaPlayerObj_->deleteLater();
        mediaPlayerObj_ = nullptr;
    }
    if (!postPlayingPreviewTrackId_.isEmpty()) {
        postPlayingPreviewTrackId_.clear();
        emit postAudioChanged();
    }
}

void TelefamDesktopController::searchHashtags(const QString& query) {
    if (accessToken_.isEmpty() || isOffline_) return;
    postSearchingHashtags_ = true;
    emit postHashtagsChanged();

    QUrlQuery q;
    q.addQueryItem(QStringLiteral("q"), query.trimmed());
    const QString path = QStringLiteral("/v1/hashtags/search?") + q.toString(QUrl::FullyEncoded);
    getJson(path, [this](int status, const QByteArray& raw) {
        postSearchingHashtags_ = false;
        if (status >= 200 && status < 300) {
            const auto arr = QJsonDocument::fromJson(raw).object().value("hashtags").toArray();
            QVariantList list;
            for (const auto& v : arr) list.append(v.toObject().toVariantMap());
            postHashtagResults_ = list;
        }
        emit postHashtagsChanged();
    });
}

QString TelefamDesktopController::computeQImageDHash(const QImage& img) const {
    if (img.isNull()) return QString();
    QImage rgba = img.scaled(64, 64, Qt::IgnoreAspectRatio, Qt::SmoothTransformation)
                     .convertToFormat(QImage::Format_RGBA8888);
    char out[17]{};
    telefam_compute_frame_dhash(rgba.constBits(), rgba.width(), rgba.height(), out, sizeof(out));
    return QString::fromUtf8(out);
}

void TelefamDesktopController::addPostPhotos(const QList<QUrl>& fileUrls) {
    if (fileUrls.isEmpty()) return;
    const QString stagingDir = QStandardPaths::writableLocation(QStandardPaths::TempLocation) + QStringLiteral("/telefam_stage");
    QDir().mkpath(stagingDir);

    for (const QUrl& u : fileUrls) {
        if (postPhotos_.size() >= 10) break;
        const QString localPath = u.isLocalFile() ? u.toLocalFile() : u.toString();
        QImage src(localPath);
        if (src.isNull()) continue;

        QImage scaled = src;
        if (src.width() > 1600 || src.height() > 1600) {
            scaled = src.scaled(1600, 1600, Qt::KeepAspectRatio, Qt::SmoothTransformation);
        }
        QByteArray jpegBytes;
        QBuffer buf(&jpegBytes);
        buf.open(QIODevice::WriteOnly);
        scaled.save(&buf, "JPEG", 85);

        const QString stagedPath = stagingDir + QStringLiteral("/photo_") + QUuid::createUuid().toString(QUuid::WithoutBraces) + QStringLiteral(".jpg");
        QFile f(stagedPath);
        if (!f.open(QIODevice::WriteOnly)) continue;
        f.write(jpegBytes);
        f.close();

        const QString dhash = computeQImageDHash(scaled);
        char cidBuf[65]{};
        telefam_compute_media_content_id(
            "photo",
            dhash.toUtf8().constData(),
            "",
            scaled.width(),
            scaled.height(),
            0,
            "telefam-content-id-v1",
            cidBuf, sizeof(cidBuf)
        );

        QVariantMap item{
            {"path", stagedPath},
            {"previewDataUrl", QStringLiteral("data:image/jpeg;base64,") + QString::fromLatin1(jpegBytes.toBase64())},
            {"dhash", dhash},
            {"contentId", QString::fromUtf8(cidBuf)},
            {"width", scaled.width()},
            {"height", scaled.height()}
        };
        postPhotos_.append(item);
    }
    emit postMediaChanged();
}

void TelefamDesktopController::removePostPhoto(int index) {
    if (index < 0 || index >= postPhotos_.size()) return;
    const QString path = postPhotos_[index].toMap().value("path").toString();
    if (!path.isEmpty()) QFile::remove(path);
    postPhotos_.removeAt(index);
    emit postMediaChanged();
}

void TelefamDesktopController::selectPostVideo(const QUrl& fileUrl) {
    postErrorMessage_.clear();
    const QString localPath = fileUrl.isLocalFile() ? fileUrl.toLocalFile() : fileUrl.toString();
    QFileInfo info(localPath);
    const qint64 maxBytes = 200LL * 1024LL * 1024LL;
    if (!info.exists() || info.size() <= 0 || info.size() > maxBytes) {
        postErrorMessage_ = QStringLiteral("Max 200 MB");
        emit postUploadChanged();
        return;
    }

    qint64 durationMs = 15000;
    QProcess probe;
    probe.start(QStringLiteral("ffprobe"), {
        QStringLiteral("-v"), QStringLiteral("error"),
        QStringLiteral("-show_entries"), QStringLiteral("format=duration"),
        QStringLiteral("-of"), QStringLiteral("default=noprint_wrappers=1:nokey=1"),
        localPath
    });
    if (probe.waitForFinished(4000) && probe.exitCode() == 0) {
        bool ok = false;
        const double secs = QString::fromUtf8(probe.readAllStandardOutput()).trimmed().toDouble(&ok);
        if (ok && secs > 0.2) durationMs = static_cast<qint64>(secs * 1000.0);
    }

    const QString stagingDir = QStandardPaths::writableLocation(QStandardPaths::TempLocation) + QStringLiteral("/telefam_stage");
    QDir().mkpath(stagingDir);

    QVariantList frames;
    const int frameCount = 8;
    for (int i = 0; i < frameCount; ++i) {
        const qint64 tsMs = (durationMs * i) / std::max(1, frameCount - 1);
        const QString secStr = QString::number(tsMs / 1000.0, 'f', 2);
        const QString outFrame = stagingDir + QStringLiteral("/vf_") + QUuid::createUuid().toString(QUuid::WithoutBraces) + QStringLiteral(".jpg");
        QProcess ff;
        ff.start(QStringLiteral("ffmpeg"), {
            QStringLiteral("-y"), QStringLiteral("-ss"), secStr,
            QStringLiteral("-i"), localPath,
            QStringLiteral("-frames:v"), QStringLiteral("1"),
            QStringLiteral("-vf"), QStringLiteral("scale=320:-1"),
            QStringLiteral("-q:v"), QStringLiteral("4"),
            outFrame
        });
        if (ff.waitForFinished(5000) && ff.exitCode() == 0 && QFileInfo::exists(outFrame)) {
            QImage fImg(outFrame);
            QFile f(outFrame);
            if (f.open(QIODevice::ReadOnly)) {
                const QByteArray bytes = f.readAll();
                const QString dhash = computeQImageDHash(fImg);
                frames.append(QVariantMap{
                    {"timestampMs", tsMs},
                    {"previewDataUrl", QStringLiteral("data:image/jpeg;base64,") + QString::fromLatin1(bytes.toBase64())},
                    {"dhash", dhash},
                    {"thumbJpegPath", outFrame}
                });
            }
        }
    }

    postVideoPath_ = localPath;
    postVideoDurationMs_ = durationMs;
    postVideoFrames_ = frames;
    postTrimStartMs_ = 0;
    postTrimEndMs_ = durationMs;
    postSelectedThumbIndex_ = frames.isEmpty() ? -1 : (frames.size() / 2);
    emit postMediaChanged();
    emit postUploadChanged();
}

void TelefamDesktopController::clearPostVideo() {
    for (const auto& f : postVideoFrames_) {
        const QString p = f.toMap().value("thumbJpegPath").toString();
        if (!p.isEmpty()) QFile::remove(p);
    }
    postVideoPath_.clear();
    postVideoDurationMs_ = 0;
    postVideoFrames_.clear();
    postSelectedThumbIndex_ = -1;
    postTrimStartMs_ = 0;
    postTrimEndMs_ = 0;
    postErrorMessage_.clear();
    emit postMediaChanged();
    emit postUploadChanged();
}

void TelefamDesktopController::selectPostVideoThumb(int index) {
    if (index >= 0 && index < postVideoFrames_.size()) {
        postSelectedThumbIndex_ = index;
        emit postMediaChanged();
    }
}

void TelefamDesktopController::autoSelectPostVideoThumb() {
    if (postVideoFrames_.isEmpty()) return;
    const qint64 midTs = (postTrimStartMs_ + postTrimEndMs_) / 2;
    int bestIdx = 0;
    qint64 bestDist = std::numeric_limits<qint64>::max();
    for (int i = 0; i < postVideoFrames_.size(); ++i) {
        const qint64 ts = postVideoFrames_[i].toMap().value("timestampMs").toLongLong();
        const qint64 d = std::abs(ts - midTs);
        if (d < bestDist) {
            bestDist = d;
            bestIdx = i;
        }
    }
    selectPostVideoThumb(bestIdx);
}

void TelefamDesktopController::updatePostVideoTrim(qint64 startMs, qint64 endMs) {
    const qint64 dur = std::max<qint64>(1000, postVideoDurationMs_);
    const qint64 s = std::clamp<qint64>(startMs, 0, dur - 500);
    const qint64 e = std::clamp<qint64>(endMs, s + 500, dur);
    postTrimStartMs_ = s;
    postTrimEndMs_ = e;
    emit postMediaChanged();
}

void TelefamDesktopController::submitPost(
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
) {
    if (accessToken_.isEmpty()) return;
    stopAudioPreview();

    const QString queueId = QUuid::createUuid().toString(QUuid::WithoutBraces);
    const QString qDir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation) + QStringLiteral("/post_queue");
    QDir().mkpath(qDir);

    QJsonArray photoPaths;
    if (postType == QStringLiteral("photos")) {
        for (int i = 0; i < postPhotos_.size(); ++i) {
            const QString src = postPhotos_[i].toMap().value("path").toString();
            const QString dst = qDir + QStringLiteral("/") + queueId + QStringLiteral("_p") + QString::number(i) + QStringLiteral(".jpg");
            QFile::copy(src, dst);
            photoPaths.append(dst);
        }
    }

    QString queuedVideoPath;
    QString queuedThumbPath;
    qint64 thumbAtMs = 0;
    if (postType == QStringLiteral("video") && !postVideoPath_.isEmpty()) {
        queuedVideoPath = qDir + QStringLiteral("/") + queueId + QStringLiteral("_video.mp4");
        if (!QFile::copy(postVideoPath_, queuedVideoPath)) {
            queuedVideoPath = postVideoPath_;
        }
        if (postSelectedThumbIndex_ >= 0 && postSelectedThumbIndex_ < postVideoFrames_.size()) {
            const auto frameMap = postVideoFrames_[postSelectedThumbIndex_].toMap();
            thumbAtMs = frameMap.value("timestampMs").toLongLong();
            const QString srcThumb = frameMap.value("thumbJpegPath").toString();
            if (!srcThumb.isEmpty()) {
                queuedThumbPath = qDir + QStringLiteral("/") + queueId + QStringLiteral("_thumb.jpg");
                QFile::copy(srcThumb, queuedThumbPath);
            }
        }
    }

    QJsonArray tagArr;
    for (const auto& t : taggedUserIds) tagArr.append(t);
    QJsonArray hashArr;
    for (const auto& h : hashtags) hashArr.append(h);

    QJsonObject draft{
        {"queue_id", queueId},
        {"post_type", postType},
        {"body", body.trimmed()},
        {"bg_color_hex", bgThemeId.isEmpty() ? bgColorHex : QString()},
        {"bg_theme_id", bgThemeId},
        {"font_family", fontFamily},
        {"song_id", songId},
        {"song_title", songTitle},
        {"song_artist", songArtist},
        {"song_preview_url", songPreviewUrl},
        {"mute_original_audio", muteOriginalAudio},
        {"trim_start_ms", postTrimStartMs_},
        {"trim_end_ms", postTrimEndMs_},
        {"thumbnail_at_ms", thumbAtMs},
        {"tagged_user_ids", tagArr},
        {"hashtags", hashArr},
        {"photo_paths", photoPaths},
        {"video_path", queuedVideoPath},
        {"thumb_path", queuedThumbPath}
    };

    postUploadStatus_ = QStringLiteral("uploading");
    postUploadProgress_ = 2;
    postErrorMessage_.clear();
    emit postUploadChanged();

    if (isOffline_) {
        enqueuePostDraft(draft);
        postUploadStatus_ = QStringLiteral("queued");
        postUploadProgress_ = 100;
        emit postUploadChanged();
        QTimer::singleShot(550, this, [this]() { closePostComposer(); });
        return;
    }

    uploadDraftAndCreatePost(draft, true);
}

void TelefamDesktopController::uploadDraftAndCreatePost(const QJsonObject& draft, bool interactive) {
    const QString postType = draft.value("post_type").toString();
    auto finishCreate = [this, draft, interactive](const QJsonArray& mediaIds) {
        QJsonObject req = draft;
        req.remove("queue_id");
        req.remove("photo_paths");
        req.remove("video_path");
        req.remove("thumb_path");
        req.remove("thumbnail_at_ms");
        req.insert("media_ids", mediaIds);

        postJson(QStringLiteral("/v1/posts"), req, true, [this, draft, interactive](int status, const QByteArray&) {
            if (status >= 200 && status < 300) {
                for (const auto& p : draft.value("photo_paths").toArray()) QFile::remove(p.toString());
                const QString vp = draft.value("video_path").toString();
                if (!vp.isEmpty()) QFile::remove(vp);
                const QString tp = draft.value("thumb_path").toString();
                if (!tp.isEmpty()) QFile::remove(tp);

                if (interactive) {
                    postUploadStatus_ = QStringLiteral("uploaded");
                    postUploadProgress_ = 100;
                    emit postUploadChanged();
                    refreshOwnerProfile(false);
                    QTimer::singleShot(700, this, [this]() { closePostComposer(); });
                }
            } else if (status == 0) {
                enqueuePostDraft(draft);
                if (interactive) {
                    postUploadStatus_ = QStringLiteral("queued");
                    postUploadProgress_ = 100;
                    emit postUploadChanged();
                    QTimer::singleShot(550, this, [this]() { closePostComposer(); });
                }
            } else {
                if (interactive) {
                    char safeBuf[160]{};
                    telefam_sanitize_error(status, nullptr, safeBuf, sizeof(safeBuf));
                    postUploadStatus_ = QStringLiteral("error");
                    postErrorMessage_ = QString::fromUtf8(safeBuf);
                    emit postUploadChanged();
                } else {
                    enqueuePostDraft(draft);
                }
            }
        });
    };

    if (postType == QStringLiteral("photos")) {
        auto* multiPart = new QHttpMultiPart(QHttpMultiPart::FormDataType);
        const auto paths = draft.value("photo_paths").toArray();
        for (int i = 0; i < paths.size(); ++i) {
            auto* file = new QFile(paths[i].toString(), multiPart);
            if (file->open(QIODevice::ReadOnly)) {
                QHttpPart part;
                part.setHeader(QNetworkRequest::ContentDispositionHeader,
                               QStringLiteral("form-data; name=\"photos\"; filename=\"photo_%1.jpg\"").arg(i));
                part.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("image/jpeg"));
                part.setBodyDevice(file);
                multiPart->append(part);
            }
        }
        QNetworkRequest req(QUrl(apiBase_ + QStringLiteral("/v1/posts/media/photos")));
        req.setTransferTimeout(120000);
        req.setRawHeader("Authorization", QByteArray("Bearer ") + accessToken_.toUtf8());
        auto* reply = nam_.post(req, multiPart);
        multiPart->setParent(reply);

        if (interactive) {
            connect(reply, &QNetworkReply::uploadProgress, this, [this](qint64 sent, qint64 total) {
                if (total > 0) {
                    postUploadProgress_ = std::clamp<int>(static_cast<int>((sent * 90) / total), 2, 92);
                    emit postUploadChanged();
                }
            });
        }
        connect(reply, &QNetworkReply::finished, this, [this, reply, draft, interactive, finishCreate]() {
            const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
            const QByteArray raw = reply->readAll();
            reply->deleteLater();
            if (status >= 200 && status < 300) {
                const auto media = QJsonDocument::fromJson(raw).object().value("media").toArray();
                QJsonArray ids;
                for (const auto& m : media) ids.append(m.toObject().value("media_id").toString());
                finishCreate(ids);
            } else if (status == 0) {
                enqueuePostDraft(draft);
                if (interactive) {
                    postUploadStatus_ = QStringLiteral("queued");
                    postUploadProgress_ = 100;
                    emit postUploadChanged();
                    QTimer::singleShot(550, this, [this]() { closePostComposer(); });
                }
            } else if (interactive) {
                char safeBuf[160]{};
                telefam_sanitize_error(status, nullptr, safeBuf, sizeof(safeBuf));
                postUploadStatus_ = QStringLiteral("error");
                postErrorMessage_ = QString::fromUtf8(safeBuf);
                emit postUploadChanged();
            } else {
                enqueuePostDraft(draft);
            }
        });
        return;
    }

    if (postType == QStringLiteral("video")) {
        auto* multiPart = new QHttpMultiPart(QHttpMultiPart::FormDataType);
        auto addText = [&](const QString& key, const QString& val) {
            QHttpPart p;
            p.setHeader(QNetworkRequest::ContentDispositionHeader, QStringLiteral("form-data; name=\"%1\"").arg(key));
            p.setBody(val.toUtf8());
            multiPart->append(p);
        };
        addText(QStringLiteral("trim_start_ms"), QString::number(draft.value("trim_start_ms").toInteger()));
        addText(QStringLiteral("trim_end_ms"), QString::number(draft.value("trim_end_ms").toInteger()));
        addText(QStringLiteral("thumbnail_at_ms"), QString::number(draft.value("thumbnail_at_ms").toInteger()));
        addText(QStringLiteral("mute_original_audio"), draft.value("mute_original_audio").toBool() ? QStringLiteral("true") : QStringLiteral("false"));
        addText(QStringLiteral("song_preview_url"), draft.value("song_preview_url").toString());

        const QString tp = draft.value("thumb_path").toString();
        if (!tp.isEmpty()) {
            auto* tf = new QFile(tp, multiPart);
            if (tf->open(QIODevice::ReadOnly)) {
                QHttpPart p;
                p.setHeader(QNetworkRequest::ContentDispositionHeader, QStringLiteral("form-data; name=\"thumbnail\"; filename=\"thumb.jpg\""));
                p.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("image/jpeg"));
                p.setBodyDevice(tf);
                multiPart->append(p);
            }
        }

        auto* vf = new QFile(draft.value("video_path").toString(), multiPart);
        if (vf->open(QIODevice::ReadOnly)) {
            QHttpPart p;
            p.setHeader(QNetworkRequest::ContentDispositionHeader, QStringLiteral("form-data; name=\"video\"; filename=\"video.mp4\""));
            p.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("video/mp4"));
            p.setBodyDevice(vf);
            multiPart->append(p);
        }

        QNetworkRequest req(QUrl(apiBase_ + QStringLiteral("/v1/posts/media/video")));
        req.setTransferTimeout(120000);
        req.setRawHeader("Authorization", QByteArray("Bearer ") + accessToken_.toUtf8());
        auto* reply = nam_.post(req, multiPart);
        multiPart->setParent(reply);

        if (interactive) {
            connect(reply, &QNetworkReply::uploadProgress, this, [this](qint64 sent, qint64 total) {
                if (total > 0) {
                    postUploadProgress_ = std::clamp<int>(static_cast<int>((sent * 90) / total), 2, 92);
                    emit postUploadChanged();
                }
            });
        }
        connect(reply, &QNetworkReply::finished, this, [this, reply, draft, interactive, finishCreate]() {
            const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
            const QByteArray raw = reply->readAll();
            reply->deleteLater();
            if (status >= 200 && status < 300) {
                const QString mid = QJsonDocument::fromJson(raw).object().value("media_id").toString();
                finishCreate(QJsonArray{mid});
            } else if (status == 0) {
                enqueuePostDraft(draft);
                if (interactive) {
                    postUploadStatus_ = QStringLiteral("queued");
                    postUploadProgress_ = 100;
                    emit postUploadChanged();
                    QTimer::singleShot(550, this, [this]() { closePostComposer(); });
                }
            } else if (interactive) {
                char safeBuf[160]{};
                telefam_sanitize_error(status, nullptr, safeBuf, sizeof(safeBuf));
                postUploadStatus_ = QStringLiteral("error");
                postErrorMessage_ = QString::fromUtf8(safeBuf);
                emit postUploadChanged();
            } else {
                enqueuePostDraft(draft);
            }
        });
        return;
    }

    finishCreate(QJsonArray{});
}

void TelefamDesktopController::enqueuePostDraft(const QJsonObject& draft) {
    if (!engine_) return;
    size_t len = 0;
    std::vector<uint8_t> buf(65536, 0);
    QJsonArray arr;
    auto st = telefam_vault_get(engine_, "queued_posts_json", buf.data(), buf.size(), &len);
    if (st == TELEFAM_ERR_STORAGE && len > buf.size()) {
        buf.resize(len);
        st = telefam_vault_get(engine_, "queued_posts_json", buf.data(), buf.size(), &len);
    }
    if (st == TELEFAM_OK && len > 0) {
        arr = QJsonDocument::fromJson(QByteArray(reinterpret_cast<const char*>(buf.data()), static_cast<int>(len))).array();
    }
    arr.append(draft);
    const QByteArray out = QJsonDocument(arr).toJson(QJsonDocument::Compact);
    telefam_vault_put(engine_, "queued_posts_json",
                      reinterpret_cast<const uint8_t*>(out.constData()),
                      static_cast<size_t>(out.size()));
}

void TelefamDesktopController::flushQueuedPosts() {
    if (!engine_ || accessToken_.isEmpty() || isOffline_ || postQueueFlushing_) return;
    size_t len = 0;
    std::vector<uint8_t> buf(65536, 0);
    auto st = telefam_vault_get(engine_, "queued_posts_json", buf.data(), buf.size(), &len);
    if (st == TELEFAM_ERR_STORAGE && len > buf.size()) {
        buf.resize(len);
        st = telefam_vault_get(engine_, "queued_posts_json", buf.data(), buf.size(), &len);
    }
    if (st != TELEFAM_OK || len == 0) return;

    const QJsonArray arr = QJsonDocument::fromJson(QByteArray(reinterpret_cast<const char*>(buf.data()), static_cast<int>(len))).array();
    if (arr.isEmpty()) return;

    postQueueFlushing_ = true;
    telefam_vault_delete(engine_, "queued_posts_json");
    for (const auto& item : arr) {
        uploadDraftAndCreatePost(item.toObject(), false);
    }
    postQueueFlushing_ = false;
}

void TelefamDesktopController::seedProfileFromEmail(const QString& email) {
    char nameBuf[96]{};
    char userBuf[48]{};
    telefam_autofill_profile_from_email(
        email.toUtf8().constData(),
        nameBuf, sizeof(nameBuf),
        userBuf, sizeof(userBuf)
    );
    profileFullName_ = QString::fromUtf8(nameBuf);
    profileUsername_ = QString::fromUtf8(userBuf);

    const QByteArray tz = QTimeZone::systemTimeZoneId();
    const QString localeName = QLocale::system().name();
    const QString localeCountry = localeName.contains('_') ? localeName.section('_', 1, 1) : QString();
    char isoBuf[4]{};
    telefam_suggest_country_iso("", tz.constData(), localeCountry.toUtf8().constData(), isoBuf, sizeof(isoBuf));
    profileCountryIso_ = QString::fromUtf8(isoBuf);
    profileLocation_ = QLocale::territoryToString(QLocale(QLocale::AnyLanguage, QLocale::codeToTerritory(profileCountryIso_)).territory());
    emit profileSeedChanged();
}

void TelefamDesktopController::persistSession(const QJsonObject& obj) {
    lastSessionObj_ = obj;
    accessToken_ = obj.value("access_token").toString();
    refreshToken_ = obj.value("refresh_token").toString();
    userId_ = obj.value("user_id").toString();
    email_ = obj.value("email").toString();
    profileCompleted_ = obj.value("profile_completed").toBool(false);
    if (!profileCompleted_) {
        seedProfileFromEmail(email_);
    }
    const QByteArray bytes = QJsonDocument(obj).toJson(QJsonDocument::Compact);
    telefam_vault_put(engine_, "session_json",
                      reinterpret_cast<const uint8_t*>(bytes.constData()),
                      static_cast<size_t>(bytes.size()));
    emit sessionChanged();
    emit emailChanged();
}

void TelefamDesktopController::restoreSession() {
    uint8_t themeBuf[16]{};
    size_t themeLen = 0;
    if (telefam_vault_get(engine_, "theme_dark", themeBuf, sizeof(themeBuf), &themeLen) == TELEFAM_OK) {
        const QByteArray tv(reinterpret_cast<const char*>(themeBuf), static_cast<int>(themeLen));
        isDarkTheme_ = (tv == "true");
        emit themeChanged();
    }

    uint8_t buf[16384]{};
    size_t outLen = 0;
    if (telefam_vault_get(engine_, "session_json", buf, sizeof(buf), &outLen) == TELEFAM_OK) {
        const auto obj = QJsonDocument::fromJson(QByteArray(reinterpret_cast<const char*>(buf), static_cast<int>(outLen))).object();
        lastSessionObj_ = obj;
        accessToken_ = obj.value("access_token").toString();
        refreshToken_ = obj.value("refresh_token").toString();
        userId_ = obj.value("user_id").toString();
        email_ = obj.value("email").toString();
        profileCompleted_ = obj.value("profile_completed").toBool(false);
        if (!profileCompleted_ && !email_.isEmpty()) {
            seedProfileFromEmail(email_);
        }
        emit sessionChanged();
    }

    auto readVaultArray = [this](const char* key) -> QJsonArray {
        size_t len = 0;
        std::vector<uint8_t> vbuf(65536, 0);
        auto st = telefam_vault_get(engine_, key, vbuf.data(), vbuf.size(), &len);
        if (st == TELEFAM_ERR_STORAGE && len > vbuf.size()) {
            vbuf.resize(len);
            st = telefam_vault_get(engine_, key, vbuf.data(), vbuf.size(), &len);
        }
        if (st == TELEFAM_OK && len > 0) {
            return QJsonDocument::fromJson(QByteArray(reinterpret_cast<const char*>(vbuf.data()), static_cast<int>(len))).array();
        }
        return QJsonArray{};
    };

    {
        const auto arr = readVaultArray("contacts_cache_json");
        cachedContacts_.clear();
        for (const auto& v : arr) cachedContacts_.append(v.toObject().toVariantMap());
        rebuildFilteredContacts();
    }
    {
        const auto arr = readVaultArray("conversations_json");
        conversations_.clear();
        for (const auto& v : arr) conversations_.append(v.toObject().toVariantMap());
        emit conversationsChanged();
    }
    {
        const auto arr = readVaultArray("feed_cache_json");
        feedPosts_.clear();
        for (const auto& v : arr) feedPosts_.append(v.toObject().toVariantMap());
        emit feedChanged();
    }
    {
        const auto arr = readVaultArray("notifications_json");
        notifications_.clear();
        for (const auto& v : arr) notifications_.append(v.toObject().toVariantMap());
        emit notificationsChanged();
    }
    {
        uint8_t pbuf[32768]{};
        size_t plen = 0;
        if (telefam_vault_get(engine_, "my_profile_json", pbuf, sizeof(pbuf), &plen) == TELEFAM_OK && plen > 0) {
            myProfile_ = QJsonDocument::fromJson(QByteArray(reinterpret_cast<const char*>(pbuf), static_cast<int>(plen))).object().toVariantMap();
            emit myProfileChanged();
        }
    }
    restoreEncryptedVideoFeedCaches();
}

void TelefamDesktopController::refreshSessionAndThen(std::function<void(bool)> done) {
    if (refreshToken_.isEmpty() || isOffline_) {
        done(false);
        return;
    }
    QJsonObject body{
        {"refresh_token", refreshToken_},
        {"device_fingerprint", deviceFP_},
        {"hardware_attestation", hwAttest_},
        {"platform", "desktop"}
    };
    postJson(QStringLiteral("/v1/auth/refresh"), body, false, [this, done](int status, const QByteArray& raw) {
        if (status >= 200 && status < 300) {
            const auto obj = QJsonDocument::fromJson(raw).object();
            if (!obj.value("access_token").toString().isEmpty()) {
                persistSession(obj);
                done(true);
                return;
            }
        }
        done(false);
    }, false);
}

void TelefamDesktopController::postJson(const QString& path, const QJsonObject& body, bool authed,
                                        std::function<void(int, const QByteArray&)> callback, bool allowRefresh) {
    QNetworkRequest req(QUrl(apiBase_ + path));
    req.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
    req.setTransferTimeout(12000);
    if (authed && !accessToken_.isEmpty()) {
        req.setRawHeader("Authorization", QByteArray("Bearer ") + accessToken_.toUtf8());
    }
    auto* reply = nam_.post(req, QJsonDocument(body).toJson(QJsonDocument::Compact));
    connect(reply, &QNetworkReply::finished, this, [this, reply, path, body, authed, callback, allowRefresh]() {
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const QByteArray data = reply->readAll();
        reply->deleteLater();
        if (status == 401 && authed && allowRefresh && !refreshToken_.isEmpty()) {
            refreshSessionAndThen([this, path, body, authed, callback](bool ok) {
                if (ok) {
                    postJson(path, body, authed, callback, false);
                } else {
                    callback(401, QByteArray());
                }
            });
            return;
        }
        callback(status, data);
    });
}

void TelefamDesktopController::getJson(const QString& path, std::function<void(int, const QByteArray&)> callback, bool allowRefresh) {
    QNetworkRequest req(QUrl(apiBase_ + path));
    req.setTransferTimeout(12000);
    if (!accessToken_.isEmpty()) {
        req.setRawHeader("Authorization", QByteArray("Bearer ") + accessToken_.toUtf8());
    }
    auto* reply = nam_.get(req);
    connect(reply, &QNetworkReply::finished, this, [this, reply, path, callback, allowRefresh]() {
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const QByteArray data = reply->readAll();
        reply->deleteLater();
        if (status == 401 && allowRefresh && !refreshToken_.isEmpty()) {
            refreshSessionAndThen([this, path, callback](bool ok) {
                if (ok) {
                    getJson(path, callback, false);
                } else {
                    callback(401, QByteArray());
                }
            });
            return;
        }
        callback(status, data);
    });
}
