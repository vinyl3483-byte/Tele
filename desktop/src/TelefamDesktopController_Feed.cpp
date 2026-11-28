#include "TelefamDesktopController.hpp"

#include <QClipboard>
#include <QDateTime>
#include <QDir>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkDiskCache>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QStandardPaths>
#include <QUrlQuery>
#include <algorithm>
#include <vector>

bool TelefamDesktopController::hasMultimedia() const {
#ifdef TELEFAM_HAS_QT_MULTIMEDIA
    return true;
#else
    return false;
#endif
}

void TelefamDesktopController::initFeedSubsystem() {
    auto* cache = new QNetworkDiskCache(&prefetchNam_);
    const QString cacheDir = QStandardPaths::writableLocation(QStandardPaths::CacheLocation) + QStringLiteral("/telefam_feed_media");
    QDir().mkpath(cacheDir);
    cache->setCacheDirectory(cacheDir);
    cache->setMaximumCacheSize(192LL * 1024LL * 1024LL);
    prefetchNam_.setCache(cache);

    feedSearchTimer_.setSingleShot(true);
    feedSearchTimer_.setInterval(280);
    connect(&feedSearchTimer_, &QTimer::timeout, this, [this]() {
        executeFeedSearch(feedSearchQuery_, true);
    });
}

QString TelefamDesktopController::resolveMediaUrl(const QString& rawUrl) const {
    const QString trimmed = rawUrl.trimmed();
    if (trimmed.isEmpty()) return QString();
    if (trimmed.startsWith(QStringLiteral("http://"), Qt::CaseInsensitive) ||
        trimmed.startsWith(QStringLiteral("https://"), Qt::CaseInsensitive) ||
        trimmed.startsWith(QStringLiteral("file://"), Qt::CaseInsensitive)) {
        return trimmed;
    }
    if (trimmed.startsWith('/')) {
        return apiBase_ + trimmed;
    }
    return apiBase_ + QStringLiteral("/") + trimmed;
}

QVariantMap TelefamDesktopController::computeFeedFit(
    qreal containerW, qreal containerH, int videoW, int videoH, qreal explicitRatio
) const {
    const auto fit = telefam_feed_compute_fit(
        static_cast<double>(containerW),
        static_cast<double>(containerH),
        videoW,
        videoH,
        static_cast<double>(explicitRatio)
    );
    return QVariantMap{
        {QStringLiteral("width"), fit.width},
        {QStringLiteral("height"), fit.height},
        {QStringLiteral("needsAmbientBackdrop"), fit.needs_ambient_backdrop != 0}
    };
}

QString TelefamDesktopController::formatFeedCount(qint64 count) const {
    char buf[32]{};
    telefam_feed_format_count(static_cast<int64_t>(count), buf, sizeof(buf));
    return QString::fromUtf8(buf);
}

void TelefamDesktopController::setFeedMuted(bool muted) {
    if (feedMuted_ != muted) {
        feedMuted_ = muted;
        emit feedAudioStateChanged();
    }
}

void TelefamDesktopController::setFeedSearchTab(int tab) {
    if (feedSearchTab_ != tab) {
        feedSearchTab_ = tab;
        emit feedDiscoveryChanged();
    }
}

void TelefamDesktopController::setModalFeedIndex(int idx) {
    if (modalFeedIndex_ != idx) {
        modalFeedIndex_ = idx;
        emit feedDiscoveryChanged();
    }
}

void TelefamDesktopController::setLiveComingSoonOpen(bool open) {
    if (liveComingSoonOpen_ != open) {
        liveComingSoonOpen_ = open;
        emit feedDiscoveryChanged();
    }
}

void TelefamDesktopController::sendCustomJson(
    const QByteArray& verb,
    const QString& path,
    const QByteArray& bodyBytes,
    bool authed,
    std::function<void(int, const QByteArray&)> callback,
    bool allowRefresh
) {
    QNetworkRequest req(QUrl(apiBase_ + path));
    if (!bodyBytes.isEmpty()) {
        req.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
    }
    req.setTransferTimeout(12000);
    if (authed && !accessToken_.isEmpty()) {
        req.setRawHeader("Authorization", QByteArray("Bearer ") + accessToken_.toUtf8());
    }
    auto* reply = nam_.sendCustomRequest(req, verb, bodyBytes);
    connect(reply, &QNetworkReply::finished, this, [this, reply, verb, path, bodyBytes, authed, callback, allowRefresh]() {
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const QByteArray data = reply->readAll();
        reply->deleteLater();
        if (status == 401 && authed && allowRefresh && !refreshToken_.isEmpty()) {
            refreshSessionAndThen([this, verb, path, bodyBytes, authed, callback](bool ok) {
                if (ok) {
                    sendCustomJson(verb, path, bodyBytes, authed, callback, false);
                } else {
                    callback(401, QByteArray());
                }
            });
            return;
        }
        callback(status, data);
    });
}

void TelefamDesktopController::restoreEncryptedVideoFeedCaches() {
    if (!engine_) return;
    auto readVaultArray = [this](const char* key) -> QVariantList {
        size_t len = 0;
        std::vector<uint8_t> buf(65536, 0);
        auto st = telefam_vault_get(engine_, key, buf.data(), buf.size(), &len);
        if (st == TELEFAM_ERR_STORAGE && len > buf.size()) {
            buf.resize(len);
            st = telefam_vault_get(engine_, key, buf.data(), buf.size(), &len);
        }
        if (st == TELEFAM_OK && len > 0) {
            const auto arr = QJsonDocument::fromJson(QByteArray(reinterpret_cast<const char*>(buf.data()), static_cast<int>(len))).array();
            QVariantList list;
            for (const auto& v : arr) list.append(v.toObject().toVariantMap());
            return list;
        }
        return {};
    };

    forYouVideos_ = readVaultArray("video_feed_for_you_json");
    followingVideos_ = readVaultArray("video_feed_following_json");
    savedVideos_ = readVaultArray("video_feed_saved_json");

    {
        size_t len = 0;
        std::vector<uint8_t> buf(16384, 0);
        if (telefam_vault_get(engine_, "feed_recent_searches_json", buf.data(), buf.size(), &len) == TELEFAM_OK && len > 0) {
            const auto arr = QJsonDocument::fromJson(QByteArray(reinterpret_cast<const char*>(buf.data()), static_cast<int>(len))).array();
            localRecentSearches_.clear();
            for (const auto& v : arr) localRecentSearches_.append(v.toString());
        }
    }
    emit videoFeedChanged();
    emit savedSafetyChanged();
    emit feedDiscoveryChanged();
}

void TelefamDesktopController::clearEncryptedVideoFeedCaches() {
    if (engine_) {
        telefam_vault_delete(engine_, "video_feed_for_you_json");
        telefam_vault_delete(engine_, "video_feed_following_json");
        telefam_vault_delete(engine_, "video_feed_saved_json");
        telefam_vault_delete(engine_, "feed_recent_searches_json");
    }
    prefetchedVideoIds_.clear();
    forYouVideos_.clear();
    followingVideos_.clear();
    forYouCursor_.clear();
    followingCursor_.clear();
    forYouHasMore_ = false;
    followingHasMore_ = false;
    activeForYouIndex_ = 0;
    activeFollowingIndex_ = 0;
    videoFeedError_.clear();
    feedSearchOpen_ = false;
    feedSearchQuery_.clear();
    feedSearchResults_.clear();
    localRecentSearches_.clear();
    activeHashtagTag_.clear();
    hashtagDiscovery_.clear();
    activeAudioId_.clear();
    audioDiscovery_.clear();
    modalFeedVideos_.clear();
    modalFeedOpen_ = false;
    liveComingSoonOpen_ = false;
    savedVideos_.clear();
    safetyPreferences_.clear();
    prefilledPostSong_.clear();
    emit videoFeedChanged();
    emit feedDiscoveryChanged();
    emit savedSafetyChanged();
    emit prefilledPostSongChanged();
}

void TelefamDesktopController::persistVideoFeedCache(const QString& tab) {
    if (!engine_) return;
    const QVariantList& src = (tab == QStringLiteral("following")) ? followingVideos_ : forYouVideos_;
    const char* key = (tab == QStringLiteral("following")) ? "video_feed_following_json" : "video_feed_for_you_json";
    QJsonArray arr;
    const int limit = std::min<int>(src.size(), 60);
    for (int i = 0; i < limit; ++i) {
        arr.append(QJsonObject::fromVariantMap(src[i].toMap()));
    }
    const QByteArray bytes = QJsonDocument(arr).toJson(QJsonDocument::Compact);
    telefam_vault_put(engine_, key, reinterpret_cast<const uint8_t*>(bytes.constData()), static_cast<size_t>(bytes.size()));
}

void TelefamDesktopController::prefetchUpcomingVideos(const QVariantList& list, int currentIndex) {
    if (isOffline_) return;
    const int end = std::min<int>(list.size(), currentIndex + 6);
    for (int i = currentIndex + 1; i < end; ++i) {
        const auto m = list[i].toMap();
        const QString vid = m.value("video_id").toString();
        if (vid.isEmpty() || prefetchedVideoIds_.contains(vid)) continue;
        prefetchedVideoIds_.insert(vid);

        const QString thumb = resolveMediaUrl(m.value("thumbnail_url").toString());
        if (!thumb.isEmpty()) {
            QNetworkRequest treq{QUrl(thumb)};
            treq.setAttribute(QNetworkRequest::CacheLoadControlAttribute, QNetworkRequest::PreferCache);
            auto* treply = prefetchNam_.get(treq);
            connect(treply, &QNetworkReply::finished, treply, &QNetworkReply::deleteLater);
        }

        const QString stream = resolveMediaUrl(m.value("stream_url").toString().isEmpty()
                                               ? m.value("fallback_mp4_url").toString()
                                               : m.value("stream_url").toString());
        if (!stream.isEmpty()) {
            QNetworkRequest sreq{QUrl(stream)};
            sreq.setRawHeader("Range", "bytes=0-1048575");
            sreq.setAttribute(QNetworkRequest::CacheLoadControlAttribute, QNetworkRequest::PreferCache);
            auto* sreply = prefetchNam_.get(sreq);
            connect(sreply, &QNetworkReply::finished, sreply, &QNetworkReply::deleteLater);
        }
    }
}

void TelefamDesktopController::selectVideoFeedTab(const QString& tab) {
    const QString norm = (tab == QStringLiteral("following")) ? QStringLiteral("following") : QStringLiteral("for_you");
    if (videoFeedTab_ != norm) {
        videoFeedTab_ = norm;
        emit videoFeedChanged();
        if (activeFeedVideos().isEmpty()) {
            refreshVideoFeed(norm, true);
        } else {
            prefetchUpcomingVideos(activeFeedVideos(), activeVideoIndex());
        }
    }
}

void TelefamDesktopController::refreshVideoFeed(const QString& tab, bool reset) {
    if (accessToken_.isEmpty()) return;
    const QString targetTab = (tab == QStringLiteral("following")) ? QStringLiteral("following") : QStringLiteral("for_you");
    const QVariantList& current = (targetTab == QStringLiteral("following")) ? followingVideos_ : forYouVideos_;
    const QString cursor = reset ? QString() : ((targetTab == QStringLiteral("following")) ? followingCursor_ : forYouCursor_);
    const bool hasMore = (targetTab == QStringLiteral("following")) ? followingHasMore_ : forYouHasMore_;

    if (isOffline_) {
        if (current.isEmpty()) {
            videoFeedError_ = QStringLiteral("No internet.");
            emit videoFeedChanged();
        }
        return;
    }
    if (!reset && (videoFeedLoading_ || !hasMore || cursor.isEmpty())) return;

    videoFeedLoading_ = true;
    videoFeedError_.clear();
    emit videoFeedChanged();

    QUrlQuery q;
    if (!cursor.isEmpty()) q.addQueryItem(QStringLiteral("cursor"), cursor);
    q.addQueryItem(QStringLiteral("limit"), QStringLiteral("15"));
    const QString endpoint = (targetTab == QStringLiteral("following")) ? QStringLiteral("/v1/feed/following?") : QStringLiteral("/v1/feed/for-you?");

    getJson(endpoint + q.toString(QUrl::FullyEncoded), [this, targetTab, reset](int status, const QByteArray& raw) {
        videoFeedLoading_ = false;
        if (status >= 200 && status < 300) {
            const auto doc = QJsonDocument::fromJson(raw).object();
            const auto arr = doc.value("videos").toArray();
            QVariantList incoming;
            for (const auto& v : arr) incoming.append(v.toObject().toVariantMap());

            QVariantList& dest = (targetTab == QStringLiteral("following")) ? followingVideos_ : forYouVideos_;
            if (reset) {
                dest = incoming;
                if (targetTab == QStringLiteral("following")) activeFollowingIndex_ = 0;
                else activeForYouIndex_ = 0;
            } else {
                QSet<QString> seen;
                for (const auto& ex : dest) seen.insert(ex.toMap().value("video_id").toString());
                for (const auto& item : incoming) {
                    const QString id = item.toMap().value("video_id").toString();
                    if (!seen.contains(id)) {
                        seen.insert(id);
                        dest.append(item);
                    }
                }
            }
            if (targetTab == QStringLiteral("following")) {
                followingCursor_ = doc.value("next_cursor").toString();
                followingHasMore_ = doc.value("has_more").toBool(false);
            } else {
                forYouCursor_ = doc.value("next_cursor").toString();
                forYouHasMore_ = doc.value("has_more").toBool(false);
            }
            persistVideoFeedCache(targetTab);
            prefetchUpcomingVideos(dest, targetTab == QStringLiteral("following") ? activeFollowingIndex_ : activeForYouIndex_);
        } else {
            const QVariantList& dest = (targetTab == QStringLiteral("following")) ? followingVideos_ : forYouVideos_;
            if (dest.isEmpty()) {
                char safeBuf[160]{};
                telefam_sanitize_error(status, nullptr, safeBuf, sizeof(safeBuf));
                videoFeedError_ = QString::fromUtf8(safeBuf);
            }
        }
        emit videoFeedChanged();
    });
}

void TelefamDesktopController::onFeedVideoSettled(int index) {
    const QVariantList list = activeFeedVideos();
    if (index < 0 || index >= list.size()) return;
    if (videoFeedTab_ == QStringLiteral("following")) {
        activeFollowingIndex_ = index;
    } else {
        activeForYouIndex_ = index;
    }
    emit videoFeedChanged();
    prefetchUpcomingVideos(list, index);

    if (index >= list.size() - 4) {
        const bool hasMore = (videoFeedTab_ == QStringLiteral("following")) ? followingHasMore_ : forYouHasMore_;
        if (hasMore && !videoFeedLoading_) {
            refreshVideoFeed(videoFeedTab_, false);
        }
    }
}

void TelefamDesktopController::refreshSignedStreamUrl(const QString& videoId) {
    if (accessToken_.isEmpty() || isOffline_ || videoId.isEmpty()) return;
    getJson(QStringLiteral("/v1/videos/") + videoId + QStringLiteral("/refresh-stream-url"), [this, videoId](int status, const QByteArray& raw) {
        if (status >= 200 && status < 300) {
            const auto obj = QJsonDocument::fromJson(raw).object();
            mutateVideoEverywhere(videoId, [obj](QVariantMap& m) {
                m.insert("stream_url", obj.value("stream_url").toString());
                m.insert("fallback_mp4_url", obj.value("fallback_mp4_url").toString());
                m.insert("thumbnail_url", obj.value("thumbnail_url").toString());
                m.insert("stream_type", obj.value("stream_type").toString());
                m.insert("url_expires_at", obj.value("url_expires_at").toVariant());
                m.insert("variants", obj.value("variants").toArray().toVariantList());
            });
        }
    });
}

void TelefamDesktopController::sendWatchProgress(
    const QString& videoId, qint64 watchMs, qint64 posMs, double completionPct, int rewatchDelta, bool isViewPing
) {
    if (accessToken_.isEmpty() || isOffline_ || videoId.isEmpty()) return;
    const QJsonObject body{
        {"watch_duration_ms", watchMs},
        {"last_position_ms", posMs},
        {"completion_pct", completionPct},
        {"rewatch_delta", rewatchDelta}
    };
    const QString path = QStringLiteral("/v1/videos/") + videoId + (isViewPing ? QStringLiteral("/view") : QStringLiteral("/watch-progress"));
    postJson(path, body, true, [](int, const QByteArray&) {});
}

void TelefamDesktopController::toggleVideoLike(const QString& videoId, bool forceLikeOnly) {
    if (accessToken_.isEmpty() || videoId.isEmpty()) return;
    bool wasLiked = false;
    qint64 prevCount = 0;
    for (const auto& item : activeFeedVideos()) {
        const auto m = item.toMap();
        if (m.value("video_id").toString() == videoId) {
            wasLiked = m.value("is_liked").toBool();
            prevCount = m.value("likes_count").toLongLong();
            break;
        }
    }
    if (forceLikeOnly && wasLiked) return;
    const bool nextLiked = forceLikeOnly ? true : !wasLiked;
    const qint64 nextCount = std::max<qint64>(0, prevCount + (nextLiked ? 1 : -1));
    mutateVideoEverywhere(videoId, [nextLiked, nextCount](QVariantMap& m) {
        m.insert("is_liked", nextLiked);
        m.insert("likes_count", nextCount);
    });

    const QByteArray verb = nextLiked ? QByteArrayLiteral("POST") : QByteArrayLiteral("DELETE");
    sendCustomJson(verb, QStringLiteral("/v1/videos/") + videoId + QStringLiteral("/like"), QByteArrayLiteral("{}"), true,
                   [this, videoId, wasLiked, prevCount](int status, const QByteArray& raw) {
        if (status >= 200 && status < 300) {
            const auto obj = QJsonDocument::fromJson(raw).object();
            mutateVideoEverywhere(videoId, [obj](QVariantMap& m) {
                m.insert("is_liked", obj.value("is_liked").toBool());
                m.insert("likes_count", obj.value("likes_count").toVariant());
            });
        } else {
            mutateVideoEverywhere(videoId, [wasLiked, prevCount](QVariantMap& m) {
                m.insert("is_liked", wasLiked);
                m.insert("likes_count", prevCount);
            });
            char safeBuf[160]{};
            telefam_sanitize_error(status, nullptr, safeBuf, sizeof(safeBuf));
            showToast(QString::fromUtf8(safeBuf));
        }
    });
}

void TelefamDesktopController::toggleVideoSave(const QString& videoId) {
    if (accessToken_.isEmpty() || videoId.isEmpty()) return;
    bool wasSaved = false;
    qint64 prevCount = 0;
    for (const auto& item : activeFeedVideos()) {
        const auto m = item.toMap();
        if (m.value("video_id").toString() == videoId) {
            wasSaved = m.value("is_saved").toBool();
            prevCount = m.value("saves_count").toLongLong();
            break;
        }
    }
    const bool nextSaved = !wasSaved;
    const qint64 nextCount = std::max<qint64>(0, prevCount + (nextSaved ? 1 : -1));
    mutateVideoEverywhere(videoId, [nextSaved, nextCount](QVariantMap& m) {
        m.insert("is_saved", nextSaved);
        m.insert("saves_count", nextCount);
    });

    const QByteArray verb = nextSaved ? QByteArrayLiteral("POST") : QByteArrayLiteral("DELETE");
    sendCustomJson(verb, QStringLiteral("/v1/videos/") + videoId + QStringLiteral("/save"), QByteArrayLiteral("{}"), true,
                   [this, videoId, wasSaved, prevCount](int status, const QByteArray& raw) {
        if (status >= 200 && status < 300) {
            const auto obj = QJsonDocument::fromJson(raw).object();
            mutateVideoEverywhere(videoId, [obj](QVariantMap& m) {
                m.insert("is_saved", obj.value("is_saved").toBool());
                m.insert("saves_count", obj.value("saves_count").toVariant());
            });
        } else {
            mutateVideoEverywhere(videoId, [wasSaved, prevCount](QVariantMap& m) {
                m.insert("is_saved", wasSaved);
                m.insert("saves_count", prevCount);
            });
        }
    });
}

void TelefamDesktopController::shareVideo(const QString& videoId, const QString& streamUrl) {
    const QString fullUrl = resolveMediaUrl(streamUrl.isEmpty() ? (QStringLiteral("/v1/videos/") + videoId) : streamUrl);
    if (auto* cb = QGuiApplication::clipboard()) {
        cb->setText(fullUrl);
    }
    showToast(QStringLiteral("Link copied"));
    mutateVideoEverywhere(videoId, [](QVariantMap& m) {
        m.insert("shares_count", m.value("shares_count").toLongLong() + 1);
    });
    if (!isOffline_ && !accessToken_.isEmpty()) {
        postJson(QStringLiteral("/v1/videos/") + videoId + QStringLiteral("/share"),
                 QJsonObject{{"channel", QStringLiteral("copy_link")}}, true,
                 [this, videoId](int status, const QByteArray& raw) {
            if (status >= 200 && status < 300) {
                const auto obj = QJsonDocument::fromJson(raw).object();
                mutateVideoEverywhere(videoId, [obj](QVariantMap& m) {
                    m.insert("shares_count", obj.value("shares_count").toVariant());
                });
            }
        });
    }
}

void TelefamDesktopController::toggleFollowCreator(const QString& creatorId) {
    if (accessToken_.isEmpty() || creatorId.isEmpty()) return;
    const qint64 nowSec = QDateTime::currentSecsSinceEpoch();
    if (telefam_follow_rate_limit_allow(engine_, userId_.toUtf8().constData(), nowSec) != 1) {
        showToast(QStringLiteral("Try again later"));
        return;
    }

    bool prevFollowing = false;
    for (const auto& item : activeFeedVideos()) {
        const auto m = item.toMap();
        if (m.value("creator_id").toString() == creatorId) {
            prevFollowing = m.value("is_following_creator").toBool();
            break;
        }
    }
    const bool nextFollow = !prevFollowing;
    mutateCreatorFollowingEverywhere(creatorId, nextFollow);

    postJson(QStringLiteral("/v1/contacts/follow"),
             QJsonObject{{"target_user_id", creatorId}, {"follow", nextFollow}},
             true,
             [this, creatorId, prevFollowing](int status, const QByteArray& raw) {
        if (status >= 200 && status < 300) {
            const auto obj = QJsonDocument::fromJson(raw).object();
            mutateCreatorFollowingEverywhere(creatorId, obj.value("is_following").toBool());
        } else {
            mutateCreatorFollowingEverywhere(creatorId, prevFollowing);
            char safeBuf[160]{};
            telefam_sanitize_error(status, nullptr, safeBuf, sizeof(safeBuf));
            showToast(QString::fromUtf8(safeBuf));
        }
    });
}

void TelefamDesktopController::toggleVideoRepost(const QString& videoId) {
    if (accessToken_.isEmpty() || videoId.isEmpty()) return;
    bool wasReposted = false;
    qint64 prevCount = 0;
    for (const auto& item : activeFeedVideos()) {
        const auto m = item.toMap();
        if (m.value("video_id").toString() == videoId) {
            wasReposted = m.value("is_reposted").toBool();
            prevCount = m.value("reposts_count").toLongLong();
            break;
        }
    }
    const bool next = !wasReposted;
    const qint64 nextCount = std::max<qint64>(0, prevCount + (next ? 1 : -1));
    mutateVideoEverywhere(videoId, [next, nextCount](QVariantMap& m) {
        m.insert("is_reposted", next);
        m.insert("reposts_count", nextCount);
    });
    const QByteArray verb = next ? QByteArrayLiteral("POST") : QByteArrayLiteral("DELETE");
    sendCustomJson(verb, QStringLiteral("/v1/videos/") + videoId + QStringLiteral("/repost"), QByteArrayLiteral("{}"), true,
                   [this, videoId, wasReposted, prevCount](int status, const QByteArray& raw) {
        if (status >= 200 && status < 300) {
            const auto obj = QJsonDocument::fromJson(raw).object();
            mutateVideoEverywhere(videoId, [obj](QVariantMap& m) {
                m.insert("is_reposted", obj.value("is_reposted").toBool());
                m.insert("reposts_count", obj.value("reposts_count").toVariant());
            });
            showToast(obj.value("is_reposted").toBool() ? QStringLiteral("Reposted") : QStringLiteral("Repost removed"));
        } else {
            mutateVideoEverywhere(videoId, [wasReposted, prevCount](QVariantMap& m) {
                m.insert("is_reposted", wasReposted);
                m.insert("reposts_count", prevCount);
            });
        }
    });
}

void TelefamDesktopController::markVideoNotInterested(const QString& videoId) {
    removeVideoEverywhere(videoId);
    showToast(QStringLiteral("We will show fewer videos like this"));
    if (!isOffline_ && !accessToken_.isEmpty()) {
        postJson(QStringLiteral("/v1/videos/") + videoId + QStringLiteral("/not-interested"), QJsonObject{}, true, [](int, const QByteArray&) {});
    }
}

void TelefamDesktopController::reportVideo(const QString& videoId, const QString& reason, const QString& details) {
    if (accessToken_.isEmpty() || isOffline_) return;
    postJson(QStringLiteral("/v1/videos/") + videoId + QStringLiteral("/report"),
             QJsonObject{{"reason", reason}, {"details", details}}, true,
             [this](int status, const QByteArray&) {
        if (status >= 200 && status < 300) {
            showToast(QStringLiteral("Report submitted"));
        } else {
            char safeBuf[160]{};
            telefam_sanitize_error(status, nullptr, safeBuf, sizeof(safeBuf));
            showToast(QString::fromUtf8(safeBuf));
        }
    });
}

void TelefamDesktopController::blockCreator(const QString& creatorId) {
    removeCreatorVideosEverywhere(creatorId);
    if (accessToken_.isEmpty() || isOffline_ || creatorId.isEmpty()) return;
    postJson(QStringLiteral("/v1/users/") + QString::fromLatin1(QUrl::toPercentEncoding(creatorId)) + QStringLiteral("/block"),
             QJsonObject{}, true, [this](int status, const QByteArray&) {
        if (status >= 200 && status < 300) {
            showToast(QStringLiteral("User blocked"));
        }
    });
}

void TelefamDesktopController::muteCreator(const QString& creatorId) {
    removeCreatorVideosEverywhere(creatorId);
    if (accessToken_.isEmpty() || isOffline_ || creatorId.isEmpty()) return;
    postJson(QStringLiteral("/v1/users/") + QString::fromLatin1(QUrl::toPercentEncoding(creatorId)) + QStringLiteral("/mute"),
             QJsonObject{}, true, [this](int status, const QByteArray&) {
        if (status >= 200 && status < 300) {
            showToast(QStringLiteral("User muted"));
        }
    });
}

void TelefamDesktopController::updateOwnerVideoDetails(
    const QString& videoId, const QString& title, const QString& description
) {
    if (accessToken_.isEmpty() || isOffline_ || videoId.isEmpty()) return;
    const QJsonObject body{
        {"title", title},
        {"description", description}
    };
    sendCustomJson(QByteArrayLiteral("PATCH"),
                   QStringLiteral("/v1/videos/") + videoId,
                   QJsonDocument(body).toJson(QJsonDocument::Compact),
                   true,
                   [this, videoId](int status, const QByteArray& raw) {
        if (status >= 200 && status < 300) {
            const auto obj = QJsonDocument::fromJson(raw).object();
            mutateVideoEverywhere(videoId, [obj](QVariantMap& m) {
                m.insert("title", obj.value("title").toString());
                m.insert("description", obj.value("description").toString());
                m.insert("visibility", obj.value("visibility").toString());
            });
            showToast(QStringLiteral("Updated"));
        } else {
            char safeBuf[160]{};
            telefam_sanitize_error(status, nullptr, safeBuf, sizeof(safeBuf));
            showToast(QString::fromUtf8(safeBuf));
        }
    });
}

void TelefamDesktopController::updateOwnerVideoVisibility(
    const QString& videoId, const QString& visibility
) {
    if (accessToken_.isEmpty() || isOffline_ || videoId.isEmpty() || visibility.isEmpty()) return;
    const QJsonObject body{
        {"visibility", visibility}
    };
    sendCustomJson(QByteArrayLiteral("PATCH"),
                   QStringLiteral("/v1/videos/") + videoId,
                   QJsonDocument(body).toJson(QJsonDocument::Compact),
                   true,
                   [this, videoId](int status, const QByteArray& raw) {
        if (status >= 200 && status < 300) {
            const auto obj = QJsonDocument::fromJson(raw).object();
            mutateVideoEverywhere(videoId, [obj](QVariantMap& m) {
                m.insert("visibility", obj.value("visibility").toString());
            });
            showToast(QStringLiteral("Updated"));
        } else {
            char safeBuf[160]{};
            telefam_sanitize_error(status, nullptr, safeBuf, sizeof(safeBuf));
            showToast(QString::fromUtf8(safeBuf));
        }
    });
}

void TelefamDesktopController::deleteOwnerVideo(const QString& videoId) {
    if (accessToken_.isEmpty() || isOffline_) return;
    sendCustomJson(QByteArrayLiteral("DELETE"), QStringLiteral("/v1/videos/") + videoId, QByteArray{}, true,
                   [this, videoId](int status, const QByteArray&) {
        if (status >= 200 && status < 300) {
            removeVideoEverywhere(videoId);
            showToast(QStringLiteral("Video deleted"));
        } else {
            char safeBuf[160]{};
            telefam_sanitize_error(status, nullptr, safeBuf, sizeof(safeBuf));
            showToast(QString::fromUtf8(safeBuf));
        }
    });
}

void TelefamDesktopController::openHashtagDiscovery(const QString& tag) {
    QString clean = tag.trimmed().toLower();
    clean.remove('#');
    if (clean.isEmpty()) return;
    activeHashtagTag_ = clean;
    hashtagDiscovery_.clear();
    emit feedDiscoveryChanged();
    loadHashtagDiscoveryInternal(clean, true);
}

void TelefamDesktopController::closeHashtagDiscovery() {
    activeHashtagTag_.clear();
    hashtagDiscovery_.clear();
    emit feedDiscoveryChanged();
}

void TelefamDesktopController::loadMoreHashtagDiscovery() {
    if (!activeHashtagTag_.isEmpty()) loadHashtagDiscoveryInternal(activeHashtagTag_, false);
}

void TelefamDesktopController::loadHashtagDiscoveryInternal(const QString& tag, bool reset) {
    if (accessToken_.isEmpty() || isOffline_) return;
    const QString cursor = reset ? QString() : hashtagDiscovery_.value("next_cursor").toString();
    const bool hasMore = hashtagDiscovery_.value("has_more").toBool(false);
    if (!reset && (hashtagLoading_ || !hasMore || cursor.isEmpty())) return;

    hashtagLoading_ = true;
    emit feedDiscoveryChanged();

    QUrlQuery q;
    if (!cursor.isEmpty()) q.addQueryItem(QStringLiteral("cursor"), cursor);
    q.addQueryItem(QStringLiteral("limit"), QStringLiteral("21"));
    getJson(QStringLiteral("/v1/hashtags/") + QString::fromLatin1(QUrl::toPercentEncoding(tag)) + QStringLiteral("/videos?") + q.toString(QUrl::FullyEncoded),
            [this, reset](int status, const QByteArray& raw) {
        hashtagLoading_ = false;
        if (status >= 200 && status < 300) {
            const auto doc = QJsonDocument::fromJson(raw).object().toVariantMap();
            if (reset || hashtagDiscovery_.isEmpty()) {
                hashtagDiscovery_ = doc;
            } else {
                QVariantList prev = hashtagDiscovery_.value("videos").toList();
                QSet<QString> seen;
                for (const auto& v : prev) seen.insert(v.toMap().value("video_id").toString());
                for (const auto& v : doc.value("videos").toList()) {
                    const QString id = v.toMap().value("video_id").toString();
                    if (!seen.contains(id)) {
                        seen.insert(id);
                        prev.append(v);
                    }
                }
                QVariantMap merged = doc;
                merged.insert("videos", prev);
                hashtagDiscovery_ = merged;
            }
        }
        emit feedDiscoveryChanged();
    });
}

void TelefamDesktopController::openAudioDiscovery(const QString& audioId) {
    if (audioId.isEmpty()) return;
    activeAudioId_ = audioId;
    audioDiscovery_.clear();
    emit feedDiscoveryChanged();
    loadAudioDiscoveryInternal(audioId, true);
}

void TelefamDesktopController::closeAudioDiscovery() {
    activeAudioId_.clear();
    audioDiscovery_.clear();
    emit feedDiscoveryChanged();
}

void TelefamDesktopController::loadMoreAudioDiscovery() {
    if (!activeAudioId_.isEmpty()) loadAudioDiscoveryInternal(activeAudioId_, false);
}

void TelefamDesktopController::loadAudioDiscoveryInternal(const QString& audioId, bool reset) {
    if (accessToken_.isEmpty() || isOffline_) return;
    const QString cursor = reset ? QString() : audioDiscovery_.value("next_cursor").toString();
    const bool hasMore = audioDiscovery_.value("has_more").toBool(false);
    if (!reset && (audioLoading_ || !hasMore || cursor.isEmpty())) return;

    audioLoading_ = true;
    emit feedDiscoveryChanged();

    QUrlQuery q;
    if (!cursor.isEmpty()) q.addQueryItem(QStringLiteral("cursor"), cursor);
    q.addQueryItem(QStringLiteral("limit"), QStringLiteral("21"));
    getJson(QStringLiteral("/v1/audios/") + QString::fromLatin1(QUrl::toPercentEncoding(audioId)) + QStringLiteral("/videos?") + q.toString(QUrl::FullyEncoded),
            [this, reset](int status, const QByteArray& raw) {
        audioLoading_ = false;
        if (status >= 200 && status < 300) {
            const auto doc = QJsonDocument::fromJson(raw).object().toVariantMap();
            if (reset || audioDiscovery_.isEmpty()) {
                audioDiscovery_ = doc;
            } else {
                QVariantList prev = audioDiscovery_.value("videos").toList();
                QSet<QString> seen;
                for (const auto& v : prev) seen.insert(v.toMap().value("video_id").toString());
                for (const auto& v : doc.value("videos").toList()) {
                    const QString id = v.toMap().value("video_id").toString();
                    if (!seen.contains(id)) {
                        seen.insert(id);
                        prev.append(v);
                    }
                }
                QVariantMap merged = doc;
                merged.insert("videos", prev);
                audioDiscovery_ = merged;
            }
        }
        emit feedDiscoveryChanged();
    });
}

void TelefamDesktopController::useSoundInPostComposer(const QVariantMap& audioObj) {
    activeAudioId_.clear();
    activeHashtagTag_.clear();
    feedSearchOpen_ = false;
    modalFeedOpen_ = false;
    emit feedDiscoveryChanged();

    const QString extId = audioObj.value("external_track_id").toString();
    const QString audId = audioObj.value("audio_id").toString();
    prefilledPostSong_ = QVariantMap{
        {QStringLiteral("track_id"), extId.isEmpty() ? audId : extId},
        {QStringLiteral("title"), audioObj.value("title").toString()},
        {QStringLiteral("artist"), audioObj.value("artist").toString()},
        {QStringLiteral("artwork_url"), audioObj.value("artwork_url").toString()},
        {QStringLiteral("preview_url"), audioObj.value("preview_url").toString()},
        {QStringLiteral("duration_sec"), std::max<int>(15, static_cast<int>(audioObj.value("duration_ms").toLongLong() / 1000))}
    };
    emit prefilledPostSongChanged();
    openPostComposer();
}

void TelefamDesktopController::clearPrefilledPostSong() {
    if (!prefilledPostSong_.isEmpty()) {
        prefilledPostSong_.clear();
        emit prefilledPostSongChanged();
    }
}

void TelefamDesktopController::openFeedSearch() {
    feedSearchOpen_ = true;
    emit feedDiscoveryChanged();
    executeFeedSearch(feedSearchQuery_, true);
}

void TelefamDesktopController::closeFeedSearch() {
    feedSearchOpen_ = false;
    emit feedDiscoveryChanged();
}

void TelefamDesktopController::updateFeedSearchQuery(const QString& query) {
    feedSearchQuery_ = query;
    emit feedDiscoveryChanged();
    if (query.trimmed().isEmpty()) {
        feedSearchTimer_.stop();
        executeFeedSearch(query, true);
    } else {
        feedSearchTimer_.start();
    }
}

void TelefamDesktopController::executeFeedSearch(const QString& query, bool reset) {
    const QString trimmed = query.trimmed();
    if (!trimmed.isEmpty() && reset) recordLocalRecentSearch(trimmed);
    if (accessToken_.isEmpty() || isOffline_) return;

    const QString cursor = reset ? QString() : feedSearchResults_.value("next_cursor").toString();
    const bool hasMore = feedSearchResults_.value("has_more").toBool(false);
    if (!reset && (feedSearching_ || !hasMore || cursor.isEmpty())) return;

    feedSearching_ = true;
    emit feedDiscoveryChanged();

    QUrlQuery q;
    q.addQueryItem(QStringLiteral("q"), trimmed);
    if (!cursor.isEmpty()) q.addQueryItem(QStringLiteral("cursor"), cursor);
    q.addQueryItem(QStringLiteral("limit"), QStringLiteral("20"));

    getJson(QStringLiteral("/v1/search?") + q.toString(QUrl::FullyEncoded), [this, reset](int status, const QByteArray& raw) {
        feedSearching_ = false;
        if (status >= 200 && status < 300) {
            const auto doc = QJsonDocument::fromJson(raw).object().toVariantMap();
            if (reset || feedSearchResults_.isEmpty()) {
                feedSearchResults_ = doc;
            } else {
                QVariantList prev = feedSearchResults_.value("videos").toList();
                QSet<QString> seen;
                for (const auto& v : prev) seen.insert(v.toMap().value("video_id").toString());
                for (const auto& v : doc.value("videos").toList()) {
                    const QString id = v.toMap().value("video_id").toString();
                    if (!seen.contains(id)) {
                        seen.insert(id);
                        prev.append(v);
                    }
                }
                QVariantMap merged = doc;
                merged.insert("videos", prev);
                feedSearchResults_ = merged;
            }
        }
        emit feedDiscoveryChanged();
    });
}

void TelefamDesktopController::recordLocalRecentSearch(const QString& query) {
    QVariantList next;
    next.append(query);
    for (const auto& item : localRecentSearches_) {
        if (item.toString().compare(query, Qt::CaseInsensitive) != 0 && next.size() < 12) {
            next.append(item);
        }
    }
    localRecentSearches_ = next;
    if (engine_) {
        QJsonArray arr;
        for (const auto& item : localRecentSearches_) arr.append(item.toString());
        const QByteArray bytes = QJsonDocument(arr).toJson(QJsonDocument::Compact);
        telefam_vault_put(engine_, "feed_recent_searches_json", reinterpret_cast<const uint8_t*>(bytes.constData()), static_cast<size_t>(bytes.size()));
    }
    emit feedDiscoveryChanged();
}

void TelefamDesktopController::clearAllSearchHistory() {
    localRecentSearches_.clear();
    if (engine_) telefam_vault_delete(engine_, "feed_recent_searches_json");
    if (!feedSearchResults_.isEmpty()) {
        feedSearchResults_.insert("recent_searches", QVariantList{});
    }
    emit feedDiscoveryChanged();
    if (!isOffline_ && !accessToken_.isEmpty()) {
        sendCustomJson(QByteArrayLiteral("DELETE"), QStringLiteral("/v1/search/history"), QByteArray{}, true, [](int, const QByteArray&) {});
    }
}

void TelefamDesktopController::deleteRecentSearch(const QString& id, const QString& query) {
    QVariantList next;
    for (const auto& item : localRecentSearches_) {
        if (item.toString().compare(query, Qt::CaseInsensitive) != 0) next.append(item);
    }
    localRecentSearches_ = next;
    if (engine_) {
        QJsonArray arr;
        for (const auto& item : localRecentSearches_) arr.append(item.toString());
        const QByteArray bytes = QJsonDocument(arr).toJson(QJsonDocument::Compact);
        telefam_vault_put(engine_, "feed_recent_searches_json", reinterpret_cast<const uint8_t*>(bytes.constData()), static_cast<size_t>(bytes.size()));
    }
    if (!feedSearchResults_.isEmpty()) {
        QVariantList filtered;
        for (const auto& item : feedSearchResults_.value("recent_searches").toList()) {
            const auto m = item.toMap();
            if (m.value("id").toString() != id && m.value("query").toString() != query) filtered.append(item);
        }
        feedSearchResults_.insert("recent_searches", filtered);
    }
    emit feedDiscoveryChanged();
    if (!isOffline_ && !accessToken_.isEmpty() && !id.isEmpty()) {
        sendCustomJson(QByteArrayLiteral("DELETE"),
                       QStringLiteral("/v1/search/history/") + QString::fromLatin1(QUrl::toPercentEncoding(id)),
                       QByteArray{}, true, [](int, const QByteArray&) {});
    }
}

void TelefamDesktopController::openModalFeedPlayer(const QVariantList& videos, int initialIndex, const QString& title) {
    if (videos.isEmpty()) return;
    modalFeedVideos_ = videos;
    modalFeedIndex_ = std::clamp<int>(initialIndex, 0, videos.size() - 1);
    modalFeedTitle_ = title;
    modalFeedOpen_ = true;
    emit feedDiscoveryChanged();
}

void TelefamDesktopController::closeModalFeedPlayer() {
    modalFeedOpen_ = false;
    modalFeedVideos_.clear();
    emit feedDiscoveryChanged();
}

void TelefamDesktopController::loadSavedVideos() {
    if (accessToken_.isEmpty() || isOffline_) return;
    savedVideosLoading_ = true;
    emit savedSafetyChanged();
    getJson(QStringLiteral("/v1/me/saved-videos?limit=30"), [this](int status, const QByteArray& raw) {
        savedVideosLoading_ = false;
        if (status >= 200 && status < 300) {
            const auto arr = QJsonDocument::fromJson(raw).object().value("videos").toArray();
            QVariantList list;
            for (const auto& v : arr) list.append(v.toObject().toVariantMap());
            savedVideos_ = list;
            if (engine_) {
                const QByteArray bytes = QJsonDocument(arr).toJson(QJsonDocument::Compact);
                telefam_vault_put(engine_, "video_feed_saved_json", reinterpret_cast<const uint8_t*>(bytes.constData()), static_cast<size_t>(bytes.size()));
            }
        }
        emit savedSafetyChanged();
    });
}

void TelefamDesktopController::loadSafetyPreferences() {
    if (accessToken_.isEmpty() || isOffline_) return;
    safetyLoading_ = true;
    emit savedSafetyChanged();
    getJson(QStringLiteral("/v1/me/safety"), [this](int status, const QByteArray& raw) {
        safetyLoading_ = false;
        if (status >= 200 && status < 300) {
            safetyPreferences_ = QJsonDocument::fromJson(raw).object().toVariantMap();
        }
        emit savedSafetyChanged();
    });
}

void TelefamDesktopController::unblockUserFromSafety(const QString& userId) {
    QVariantList blocked = safetyPreferences_.value("blocked_users").toList();
    QVariantList next;
    for (const auto& u : blocked) {
        if (u.toMap().value("user_id").toString() != userId) next.append(u);
    }
    safetyPreferences_.insert("blocked_users", next);
    emit savedSafetyChanged();
    if (!isOffline_ && !accessToken_.isEmpty()) {
        sendCustomJson(QByteArrayLiteral("DELETE"),
                       QStringLiteral("/v1/users/") + QString::fromLatin1(QUrl::toPercentEncoding(userId)) + QStringLiteral("/block"),
                       QByteArray{}, true, [](int, const QByteArray&) {});
    }
}

void TelefamDesktopController::unmuteUserFromSafety(const QString& userId) {
    QVariantList muted = safetyPreferences_.value("muted_users").toList();
    QVariantList next;
    for (const auto& u : muted) {
        if (u.toMap().value("user_id").toString() != userId) next.append(u);
    }
    safetyPreferences_.insert("muted_users", next);
    emit savedSafetyChanged();
    if (!isOffline_ && !accessToken_.isEmpty()) {
        sendCustomJson(QByteArrayLiteral("DELETE"),
                       QStringLiteral("/v1/users/") + QString::fromLatin1(QUrl::toPercentEncoding(userId)) + QStringLiteral("/mute"),
                       QByteArray{}, true, [](int, const QByteArray&) {});
    }
}

void TelefamDesktopController::mutateVideoEverywhere(const QString& videoId, const std::function<void(QVariantMap&)>& mutator) {
    auto updateList = [&](QVariantList& list) {
        bool touched = false;
        for (int i = 0; i < list.size(); ++i) {
            QVariantMap m = list[i].toMap();
            if (m.value("video_id").toString() == videoId) {
                mutator(m);
                list[i] = m;
                touched = true;
            }
        }
        return touched;
    };
    if (updateList(forYouVideos_)) persistVideoFeedCache(QStringLiteral("for_you"));
    if (updateList(followingVideos_)) persistVideoFeedCache(QStringLiteral("following"));
    updateList(modalFeedVideos_);
    updateList(savedVideos_);
    emit videoFeedChanged();
    emit feedDiscoveryChanged();
    emit savedSafetyChanged();
}

void TelefamDesktopController::mutateCreatorFollowingEverywhere(const QString& creatorId, bool following) {
    auto updateList = [&](QVariantList& list) {
        for (int i = 0; i < list.size(); ++i) {
            QVariantMap m = list[i].toMap();
            if (m.value("creator_id").toString() == creatorId) {
                m.insert("is_following_creator", following);
                list[i] = m;
            }
        }
    };
    updateList(forYouVideos_);
    updateList(followingVideos_);
    updateList(modalFeedVideos_);
    if (!feedSearchResults_.isEmpty()) {
        QVariantList creators = feedSearchResults_.value("creators").toList();
        bool changed = false;
        for (int i = 0; i < creators.size(); ++i) {
            QVariantMap cm = creators[i].toMap();
            if (cm.value("user_id").toString() == creatorId) {
                cm.insert("is_following", following);
                creators[i] = cm;
                changed = true;
            }
        }
        if (changed) {
            feedSearchResults_.insert("creators", creators);
        }
    }
    emit videoFeedChanged();
    emit feedDiscoveryChanged();
}

void TelefamDesktopController::removeVideoEverywhere(const QString& videoId) {
    auto strip = [&](QVariantList& list) {
        QVariantList next;
        for (const auto& item : list) {
            if (item.toMap().value("video_id").toString() != videoId) next.append(item);
        }
        list = next;
    };
    strip(forYouVideos_);
    strip(followingVideos_);
    strip(modalFeedVideos_);
    strip(savedVideos_);
    persistVideoFeedCache(QStringLiteral("for_you"));
    persistVideoFeedCache(QStringLiteral("following"));
    emit videoFeedChanged();
    emit feedDiscoveryChanged();
    emit savedSafetyChanged();
}

void TelefamDesktopController::removeCreatorVideosEverywhere(const QString& creatorId) {
    auto strip = [&](QVariantList& list) {
        QVariantList next;
        for (const auto& item : list) {
            if (item.toMap().value("creator_id").toString() != creatorId) next.append(item);
        }
        list = next;
    };
    strip(forYouVideos_);
    strip(followingVideos_);
    strip(modalFeedVideos_);
    persistVideoFeedCache(QStringLiteral("for_you"));
    persistVideoFeedCache(QStringLiteral("following"));
    emit videoFeedChanged();
    emit feedDiscoveryChanged();
}
