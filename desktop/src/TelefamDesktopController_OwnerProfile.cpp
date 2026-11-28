#include "TelefamDesktopController.hpp"

#include <QBuffer>
#include <QClipboard>
#include <QDir>
#include <QFile>
#include <QGuiApplication>
#include <QHttpMultiPart>
#include <QImage>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QStandardPaths>
#include <QUrlQuery>
#include <algorithm>

void TelefamDesktopController::initOwnerProfileSubsystem() {
    const QString appDir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    ownerCacheDir_ = appDir + QStringLiteral("/owner_profile_cache");
    QDir().mkpath(ownerCacheDir_);
}

void TelefamDesktopController::restoreOwnerProfileCache() {
    if (!engine_) return;
    auto readVaultString = [&](const char* key) -> QString {
        uint8_t* ptr = nullptr;
        size_t len = 0;
        if (telefam_vault_get(engine_, key, &ptr, &len) == TELEFAM_OK && ptr) {
            const QString val = QString::fromUtf8(reinterpret_cast<const char*>(ptr), static_cast<int>(len));
            telefam_free_bytes(ptr, len);
            return val;
        }
        return QString();
    };

    const QString savedAvatar = readVaultString("owner_avatar_local_path");
    if (!savedAvatar.isEmpty() && QFile::exists(savedAvatar)) {
        ownerLocalAvatarUrl_ = QUrl::fromLocalFile(savedAvatar).toString();
    }

    const QString bgsJson = readVaultString("owner_bg_cache_json");
    if (!bgsJson.isEmpty()) {
        const auto arr = QJsonDocument::fromJson(bgsJson.toUtf8()).array();
        QStringList urls;
        for (const auto& v : arr) {
            const QString p = v.toString();
            if (!p.isEmpty() && QFile::exists(p)) {
                urls.append(QUrl::fromLocalFile(p).toString());
            }
        }
        ownerLocalBackgroundUrls_ = urls;
    }

    const QStringList tabs = {
        QStringLiteral("posts"),
        QStringLiteral("reposts"),
        QStringLiteral("locked"),
        QStringLiteral("saved")
    };
    for (const auto& t : tabs) {
        const QByteArray key = (QStringLiteral("owner_items_") + t).toUtf8();
        const QString json = readVaultString(key.constData());
        if (!json.isEmpty()) {
            const auto arr = QJsonDocument::fromJson(json.toUtf8()).array();
            QVariantList items;
            for (const auto& v : arr) items.append(v.toObject().toVariantMap());
            ownerItemsByCategory_.insert(t, items);
        }
    }
    emit ownerProfileChanged();
}

void TelefamDesktopController::clearOwnerProfileCache() {
    if (engine_) {
        telefam_vault_delete(engine_, "owner_avatar_local_path");
        telefam_vault_delete(engine_, "owner_avatar_cached_hash");
        telefam_vault_delete(engine_, "owner_bg_cache_json");
        telefam_vault_delete(engine_, "owner_items_posts");
        telefam_vault_delete(engine_, "owner_items_reposts");
        telefam_vault_delete(engine_, "owner_items_locked");
        telefam_vault_delete(engine_, "owner_items_saved");
    }
    if (!ownerCacheDir_.isEmpty()) {
        QDir(ownerCacheDir_).removeRecursively();
        QDir().mkpath(ownerCacheDir_);
    }
    ownerItemsByCategory_.clear();
    ownerLocalAvatarUrl_.clear();
    ownerLocalBackgroundUrls_.clear();
    ownerConnectionsMode_.clear();
    ownerConnectionsUsers_.clear();
    ownerActiveViewerItem_.clear();
    ownerActiveCategory_ = QStringLiteral("posts");
    emit ownerProfileChanged();
    emit ownerConnectionsChanged();
}

void TelefamDesktopController::saveOwnerAvatarBytesLocally(const QByteArray& jpegBytes) {
    if (ownerCacheDir_.isEmpty() || jpegBytes.isEmpty()) return;
    const QString path = ownerCacheDir_ + QStringLiteral("/owner_avatar.jpg");
    QFile f(path);
    if (f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        f.write(jpegBytes);
        f.close();
        ownerLocalAvatarUrl_ = QUrl::fromLocalFile(path).toString();
        if (engine_) {
            const QByteArray pBytes = path.toUtf8();
            telefam_vault_put(engine_, "owner_avatar_local_path",
                              reinterpret_cast<const uint8_t*>(pBytes.constData()),
                              static_cast<size_t>(pBytes.size()));
        }
        emit ownerProfileChanged();
    }
}

void TelefamDesktopController::syncOwnerMediaToLocalCache(const QJsonObject& profileObj) {
    if (accessToken_.isEmpty() || isOffline_ || ownerCacheDir_.isEmpty()) return;

    // 1. Download avatar locally if hash changed or local file missing
    const QString avHash = profileObj.value("avatar_fingerprint_hash").toString();
    const QString avLocalPath = ownerCacheDir_ + QStringLiteral("/owner_avatar.jpg");
    QString cachedHash;
    if (engine_) {
        uint8_t* ptr = nullptr;
        size_t len = 0;
        if (telefam_vault_get(engine_, "owner_avatar_cached_hash", &ptr, &len) == TELEFAM_OK && ptr) {
            cachedHash = QString::fromUtf8(reinterpret_cast<const char*>(ptr), static_cast<int>(len));
            telefam_free_bytes(ptr, len);
        }
    }
    if (!avHash.isEmpty() && (!QFile::exists(avLocalPath) || cachedHash != avHash)) {
        QString urlPath = profileObj.value("avatar_url").toString();
        if (urlPath.isEmpty()) urlPath = QStringLiteral("/v1/profile/avatar");
        QNetworkRequest req(QUrl(resolveMediaUrl(urlPath)));
        req.setTransferTimeout(15000);
        req.setRawHeader("Authorization", QByteArray("Bearer ") + accessToken_.toUtf8());
        auto* reply = nam_.get(req);
        connect(reply, &QNetworkReply::finished, this, [this, reply, avHash]() {
            const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
            const QByteArray data = reply->readAll();
            reply->deleteLater();
            if (status >= 200 && status < 300 && !data.isEmpty()) {
                saveOwnerAvatarBytesLocally(data);
                if (engine_) {
                    const QByteArray hb = avHash.toUtf8();
                    telefam_vault_put(engine_, "owner_avatar_cached_hash",
                                      reinterpret_cast<const uint8_t*>(hb.constData()),
                                      static_cast<size_t>(hb.size()));
                }
            }
        });
    }

    // 2. Download up to 5 background slides locally
    const auto bgs = profileObj.value("background_photos").toArray();
    QStringList cachedPaths;
    QStringList cachedUrls;
    const int limit = std::min<int>(5, static_cast<int>(bgs.size()));
    for (int i = 0; i < limit; ++i) {
        const auto obj = bgs[i].toObject();
        const QString bgId = obj.value("id").toString();
        if (bgId.isEmpty()) continue;
        const QString dest = ownerCacheDir_ + QStringLiteral("/bg_%1.jpg").arg(bgId);
        if (QFile::exists(dest)) {
            cachedPaths.append(dest);
            cachedUrls.append(QUrl::fromLocalFile(dest).toString());
        } else {
            QString remote = obj.value("url").toString();
            if (remote.isEmpty()) remote = QStringLiteral("/v1/profile/backgrounds/") + bgId;
            QNetworkRequest req(QUrl(resolveMediaUrl(remote)));
            req.setTransferTimeout(15000);
            req.setRawHeader("Authorization", QByteArray("Bearer ") + accessToken_.toUtf8());
            auto* reply = nam_.get(req);
            connect(reply, &QNetworkReply::finished, this, [this, reply, dest]() {
                const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
                const QByteArray data = reply->readAll();
                reply->deleteLater();
                if (status >= 200 && status < 300 && !data.isEmpty()) {
                    QFile f(dest);
                    if (f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
                        f.write(data);
                        f.close();
                    }
                    syncOwnerMediaToLocalCache(QJsonObject::fromVariantMap(myProfile_));
                }
            });
        }
    }
    ownerLocalBackgroundUrls_ = cachedUrls;
    if (engine_) {
        QJsonArray arr;
        for (const auto& p : cachedPaths) arr.append(p);
        const QByteArray jb = QJsonDocument(arr).toJson(QJsonDocument::Compact);
        telefam_vault_put(engine_, "owner_bg_cache_json",
                          reinterpret_cast<const uint8_t*>(jb.constData()),
                          static_cast<size_t>(jb.size()));
    }
    emit ownerProfileChanged();
}

QVariantList TelefamDesktopController::ownerActiveItems() const {
    return ownerItemsByCategory_.value(ownerActiveCategory_);
}

QString TelefamDesktopController::ownerLocalAvatarUrl() const {
    if (!ownerLocalAvatarUrl_.isEmpty()) return ownerLocalAvatarUrl_;
    if (!avatarDataUrl_.isEmpty()) return avatarDataUrl_;
    return resolveMediaUrl(myProfile_.value("avatar_url").toString());
}

QVariantList TelefamDesktopController::ownerBackgroundSlides() const {
    QVariantList out;
    const auto bgs = myProfile_.value("background_photos").toList();
    const int n = std::max(static_cast<int>(ownerLocalBackgroundUrls_.size()), static_cast<int>(bgs.size()));
    for (int i = 0; i < n && i < 5; ++i) {
        QVariantMap slide;
        const QVariantMap remoteMap = i < bgs.size() ? bgs[i].toMap() : QVariantMap{};
        const QString bgId = remoteMap.value("id").toString();
        const QString remoteUrl = resolveMediaUrl(remoteMap.value("url").toString());
        const QString localFile = ownerCacheDir_ + QStringLiteral("/bg_%1.jpg").arg(bgId);
        QString urlToUse;
        if (!bgId.isEmpty() && QFile::exists(localFile)) {
            urlToUse = QUrl::fromLocalFile(localFile).toString();
        } else if (i < ownerLocalBackgroundUrls_.size()) {
            urlToUse = ownerLocalBackgroundUrls_[i];
        } else {
            urlToUse = remoteUrl;
        }
        if (!urlToUse.isEmpty()) {
            slide.insert("id", bgId);
            slide.insert("url", urlToUse);
            out.append(slide);
        }
    }
    return out;
}

void TelefamDesktopController::copyToClipboard(const QString& text, const QString& toastMsg) {
    if (auto* cb = QGuiApplication::clipboard()) {
        cb->setText(text);
    }
    if (!toastMsg.isEmpty()) {
        showToast(toastMsg);
    }
}

void TelefamDesktopController::refreshOwnerProfile(bool isPullGesture) {
    if (accessToken_.isEmpty() || !profileCompleted_) return;
    if (isPullGesture) {
        ownerRefreshing_ = true;
        emit ownerProfileChanged();
    }
    refreshMyProfile();
    loadOwnerProfileItemsInternal(ownerActiveCategory_);
    if (isPullGesture) {
        QTimer::singleShot(450, this, [this]() {
            ownerRefreshing_ = false;
            emit ownerProfileChanged();
        });
    }
}

void TelefamDesktopController::selectOwnerCategory(const QString& category) {
    const QString norm = category.trimmed().toLower();
    if (norm.isEmpty()) return;
    if (ownerActiveCategory_ != norm) {
        ownerActiveCategory_ = norm;
        emit ownerProfileChanged();
    }
    loadOwnerProfileItemsInternal(norm);
}

void TelefamDesktopController::loadOwnerProfileItemsInternal(const QString& tab) {
    if (accessToken_.isEmpty() || isOffline_) return;
    ownerItemsLoading_ = true;
    emit ownerProfileChanged();

    QUrlQuery q;
    q.addQueryItem(QStringLiteral("tab"), tab);
    q.addQueryItem(QStringLiteral("cursor"), QString());
    q.addQueryItem(QStringLiteral("limit"), QStringLiteral("30"));
    getJson(QStringLiteral("/v1/profile/me/items?") + q.toString(QUrl::FullyEncoded), [this, tab](int status, const QByteArray& raw) {
        ownerItemsLoading_ = false;
        if (status >= 200 && status < 300) {
            const auto arr = QJsonDocument::fromJson(raw).object().value("items").toArray();
            QVariantList items;
            for (const auto& v : arr) {
                QVariantMap m = v.toObject().toVariantMap();
                const QString thumb = resolveMediaUrl(m.value("thumbnail_url").toString());
                m.insert("resolved_thumbnail_url", thumb);
                QStringList resolvedUrls;
                for (const auto& mu : m.value("media_urls").toStringList()) {
                    resolvedUrls.append(resolveMediaUrl(mu));
                }
                m.insert("resolved_media_urls", resolvedUrls);
                items.append(m);
            }
            ownerItemsByCategory_.insert(tab, items);
            if (engine_) {
                const QByteArray bytes = QJsonDocument(arr).toJson(QJsonDocument::Compact);
                const QByteArray key = (QStringLiteral("owner_items_") + tab).toUtf8();
                telefam_vault_put(engine_, key.constData(),
                                  reinterpret_cast<const uint8_t*>(bytes.constData()),
                                  static_cast<size_t>(bytes.size()));
            }
        }
        emit ownerProfileChanged();
    });
}

void TelefamDesktopController::uploadOwnerBackgroundPhotos(const QList<QUrl>& fileUrls) {
    if (fileUrls.isEmpty() || accessToken_.isEmpty()) return;
    if (isOffline_) {
        showToast(QStringLiteral("No internet"));
        return;
    }
    const int existingCount = static_cast<int>(myProfile_.value("background_photos").toList().size());
    const int remaining = std::max(0, 5 - existingCount);
    if (remaining == 0) {
        showToast(QStringLiteral("Maximum 5 background photos allowed"));
        return;
    }
    if (fileUrls.size() > remaining) {
        showToast(QStringLiteral("Only %1 more background photo(s) allowed").arg(remaining));
    }

    auto* multiPart = new QHttpMultiPart(QHttpMultiPart::FormDataType);
    int added = 0;
    for (int i = 0; i < fileUrls.size() && added < remaining; ++i) {
        const QString local = fileUrls[i].isLocalFile() ? fileUrls[i].toLocalFile() : fileUrls[i].toString();
        QImage img(local);
        if (img.isNull()) continue;
        if (img.width() > 1920 || img.height() > 1920) {
            img = img.scaled(1920, 1920, Qt::KeepAspectRatio, Qt::SmoothTransformation);
        }
        QByteArray jpeg;
        QBuffer buf(&jpeg);
        buf.open(QIODevice::WriteOnly);
        if (!img.save(&buf, "JPEG", 86) || jpeg.isEmpty()) continue;

        QHttpPart part;
        part.setHeader(QNetworkRequest::ContentDispositionHeader,
                       QStringLiteral("form-data; name=\"photos\"; filename=\"bg_%1.jpg\"").arg(added));
        part.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("image/jpeg"));
        part.setBody(jpeg);
        multiPart->append(part);
        ++added;
    }

    if (added == 0) {
        multiPart->deleteLater();
        return;
    }

    ownerUploadingBackgrounds_ = true;
    emit ownerProfileChanged();

    QNetworkRequest req(QUrl(apiBase_ + QStringLiteral("/v1/profile/backgrounds")));
    req.setTransferTimeout(60000);
    req.setRawHeader("Authorization", QByteArray("Bearer ") + accessToken_.toUtf8());
    auto* reply = nam_.post(req, multiPart);
    multiPart->setParent(reply);

    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        ownerUploadingBackgrounds_ = false;
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const QByteArray raw = reply->readAll();
        reply->deleteLater();
        if (status >= 200 && status < 300) {
            const auto bgsArr = QJsonDocument::fromJson(raw).object().value("background_photos").toArray();
            QVariantList bgsList;
            for (const auto& v : bgsArr) bgsList.append(v.toObject().toVariantMap());
            myProfile_.insert("background_photos", bgsList);
            const QJsonObject profObj = QJsonObject::fromVariantMap(myProfile_);
            if (engine_) {
                const QByteArray bytes = QJsonDocument(profObj).toJson(QJsonDocument::Compact);
                telefam_vault_put(engine_, "my_profile_json",
                                  reinterpret_cast<const uint8_t*>(bytes.constData()),
                                  static_cast<size_t>(bytes.size()));
            }
            emit myProfileChanged();
            syncOwnerMediaToLocalCache(profObj);
            showToast(QStringLiteral("Background updated"));
        } else {
            char safeBuf[160]{};
            telefam_sanitize_error(status, nullptr, safeBuf, sizeof(safeBuf));
            showToast(QString::fromUtf8(safeBuf));
        }
        emit ownerProfileChanged();
    });
}

void TelefamDesktopController::deleteOwnerBackgroundPhoto(const QString& bgId) {
    if (bgId.isEmpty() || accessToken_.isEmpty() || isOffline_) return;
    ownerUploadingBackgrounds_ = true;
    emit ownerProfileChanged();

    sendCustomJson("DELETE", QStringLiteral("/v1/profile/backgrounds/") + bgId, QByteArray(), true, [this, bgId](int status, const QByteArray& raw) {
        ownerUploadingBackgrounds_ = false;
        if (status >= 200 && status < 300) {
            QFile::remove(ownerCacheDir_ + QStringLiteral("/bg_%1.jpg").arg(bgId));
            const auto bgsArr = QJsonDocument::fromJson(raw).object().value("background_photos").toArray();
            QVariantList bgsList;
            for (const auto& v : bgsArr) bgsList.append(v.toObject().toVariantMap());
            myProfile_.insert("background_photos", bgsList);
            const QJsonObject profObj = QJsonObject::fromVariantMap(myProfile_);
            if (engine_) {
                const QByteArray bytes = QJsonDocument(profObj).toJson(QJsonDocument::Compact);
                telefam_vault_put(engine_, "my_profile_json",
                                  reinterpret_cast<const uint8_t*>(bytes.constData()),
                                  static_cast<size_t>(bytes.size()));
            }
            emit myProfileChanged();
            syncOwnerMediaToLocalCache(profObj);
        }
        emit ownerProfileChanged();
    });
}

void TelefamDesktopController::openOwnerConnections(const QString& mode) {
    ownerConnectionsMode_ = mode;
    ownerConnectionsUsers_.clear();
    ownerConnectionsLoading_ = true;
    emit ownerConnectionsChanged();

    if (isOffline_ || accessToken_.isEmpty()) {
        for (const auto& c : cachedContacts_) {
            const auto m = c.toMap();
            if ((mode == QStringLiteral("followers") && m.value("follows_me").toBool()) ||
                (mode == QStringLiteral("following") && m.value("is_following").toBool())) {
                ownerConnectionsUsers_.append(m);
            }
        }
        ownerConnectionsLoading_ = false;
        emit ownerConnectionsChanged();
        return;
    }

    QUrlQuery q;
    q.addQueryItem(QStringLiteral("filter"), mode);
    q.addQueryItem(QStringLiteral("limit"), QStringLiteral("50"));
    getJson(QStringLiteral("/v1/contacts?") + q.toString(QUrl::FullyEncoded), [this](int status, const QByteArray& raw) {
        ownerConnectionsLoading_ = false;
        if (status >= 200 && status < 300) {
            const auto arr = QJsonDocument::fromJson(raw).object().value("contacts").toArray();
            QVariantList list;
            for (const auto& v : arr) list.append(v.toObject().toVariantMap());
            ownerConnectionsUsers_ = list;
        }
        emit ownerConnectionsChanged();
    });
}

void TelefamDesktopController::closeOwnerConnections() {
    ownerConnectionsMode_.clear();
    emit ownerConnectionsChanged();
}

void TelefamDesktopController::toggleOwnerConnectionFollow(const QString& targetUserId) {
    toggleFollow(targetUserId);
    for (int i = 0; i < ownerConnectionsUsers_.size(); ++i) {
        QVariantMap m = ownerConnectionsUsers_[i].toMap();
        if (m.value("user_id").toString() == targetUserId) {
            const bool next = !m.value("is_following").toBool();
            const bool followsMe = m.value("follows_me").toBool();
            m.insert("is_following", next);
            QString rel = QStringLiteral("follow");
            if (next && followsMe) rel = QStringLiteral("friends");
            else if (next) rel = QStringLiteral("following");
            else if (followsMe) rel = QStringLiteral("follow_back");
            m.insert("relationship", rel);
            ownerConnectionsUsers_[i] = m;

            const qint64 curFollowing = myProfile_.value("following_count").toLongLong();
            myProfile_.insert("following_count", std::max<qint64>(0, curFollowing + (next ? 1 : -1)));
            emit myProfileChanged();
            emit ownerProfileChanged();
            break;
        }
    }
    emit ownerConnectionsChanged();
}

void TelefamDesktopController::openOwnerGridItem(const QVariantMap& item) {
    const QVariantMap vid = item.value("video").toMap();
    if (!vid.isEmpty() && !vid.value("video_id").toString().isEmpty()) {
        const auto all = ownerActiveItems();
        QVariantList vids;
        int targetIdx = 0;
        for (const auto& entry : all) {
            const QVariantMap em = entry.toMap();
            const QVariantMap ev = em.value("video").toMap();
            if (!ev.isEmpty() && !ev.value("video_id").toString().isEmpty()) {
                if (ev.value("video_id").toString() == vid.value("video_id").toString()) {
                    targetIdx = static_cast<int>(vids.size());
                }
                vids.append(ev);
            }
        }
        const QString title = ownerActiveCategory_.left(1).toUpper() + ownerActiveCategory_.mid(1);
        openModalFeedPlayer(vids, targetIdx, title);
        return;
    }

    ownerActiveViewerItem_ = item;
    emit ownerProfileChanged();

    const QString postId = item.value("post_id").toString();
    if (!postId.isEmpty() && !isOffline_ && !accessToken_.isEmpty()) {
        const QByteArray payload = QJsonDocument(QJsonObject{{"action", "view"}, {"active", true}}).toJson(QJsonDocument::Compact);
        sendCustomJson("POST", QStringLiteral("/v1/profile/posts/") + postId + QStringLiteral("/engage"), payload, true, [this, postId](int status, const QByteArray& raw) {
            if (status >= 200 && status < 300) {
                const auto obj = QJsonDocument::fromJson(raw).object();
                patchOwnerItemEverywhere(postId, [&](QVariantMap& cur) {
                    cur.insert("likes_count", obj.value("likes_count").toVariant());
                    cur.insert("views_count", obj.value("views_count").toVariant());
                });
            }
        });
    }
}

void TelefamDesktopController::closeOwnerGridViewer() {
    ownerActiveViewerItem_.clear();
    emit ownerProfileChanged();
}

void TelefamDesktopController::toggleOwnerPostLike(const QString& postId) {
    if (postId.isEmpty()) return;
    bool next = true;
    for (const auto& it : ownerActiveItems()) {
        const auto m = it.toMap();
        if (m.value("post_id").toString() == postId) {
            next = !m.value("is_liked").toBool();
            break;
        }
    }
    patchOwnerItemEverywhere(postId, [&](QVariantMap& cur) {
        cur.insert("is_liked", next);
        cur.insert("likes_count", std::max<qint64>(0, cur.value("likes_count").toLongLong() + (next ? 1 : -1)));
    });
    if (!isOffline_ && !accessToken_.isEmpty()) {
        const QByteArray payload = QJsonDocument(QJsonObject{{"action", "like"}, {"active", next}}).toJson(QJsonDocument::Compact);
        sendCustomJson("POST", QStringLiteral("/v1/profile/posts/") + postId + QStringLiteral("/engage"), payload, true, [this, postId](int status, const QByteArray& raw) {
            if (status >= 200 && status < 300) {
                const auto obj = QJsonDocument::fromJson(raw).object();
                patchOwnerItemEverywhere(postId, [&](QVariantMap& cur) {
                    cur.insert("likes_count", obj.value("likes_count").toVariant());
                    cur.insert("views_count", obj.value("views_count").toVariant());
                });
            }
        });
    }
}

void TelefamDesktopController::toggleOwnerPostSave(const QString& postId) {
    if (postId.isEmpty()) return;
    bool next = true;
    for (const auto& it : ownerActiveItems()) {
        const auto m = it.toMap();
        if (m.value("post_id").toString() == postId) {
            next = !m.value("is_saved").toBool();
            break;
        }
    }
    patchOwnerItemEverywhere(postId, [&](QVariantMap& cur) {
        cur.insert("is_saved", next);
    });
    if (!isOffline_ && !accessToken_.isEmpty()) {
        const QByteArray payload = QJsonDocument(QJsonObject{{"action", "save"}, {"active", next}}).toJson(QJsonDocument::Compact);
        sendCustomJson("POST", QStringLiteral("/v1/profile/posts/") + postId + QStringLiteral("/engage"), payload, true, [this](int status, const QByteArray&) {
            if (status >= 200 && status < 300) {
                loadOwnerProfileItemsInternal(QStringLiteral("saved"));
            }
        });
    }
}

void TelefamDesktopController::toggleOwnerPostLock(const QString& postId) {
    if (postId.isEmpty() || isOffline_ || accessToken_.isEmpty()) return;
    QString currentVis = QStringLiteral("public");
    if (ownerActiveViewerItem_.value("post_id").toString() == postId) {
        currentVis = ownerActiveViewerItem_.value("visibility").toString();
    }
    const QString targetVis = currentVis == QStringLiteral("private") ? QStringLiteral("public") : QStringLiteral("private");
    const QByteArray payload = QJsonDocument(QJsonObject{{"visibility", targetVis}}).toJson(QJsonDocument::Compact);
    sendCustomJson("PATCH", QStringLiteral("/v1/profile/posts/") + postId + QStringLiteral("/visibility"), payload, true, [this, targetVis](int status, const QByteArray&) {
        if (status >= 200 && status < 300) {
            ownerActiveViewerItem_.clear();
            showToast(targetVis == QStringLiteral("private") ? QStringLiteral("Moved to Locked") : QStringLiteral("Made Public"));
            loadOwnerProfileItemsInternal(QStringLiteral("posts"));
            loadOwnerProfileItemsInternal(QStringLiteral("locked"));
        }
    });
}

void TelefamDesktopController::patchOwnerItemEverywhere(const QString& postId, const std::function<void(QVariantMap&)>& mutator) {
    for (auto it = ownerItemsByCategory_.begin(); it != ownerItemsByCategory_.end(); ++it) {
        QVariantList& list = it.value();
        for (int i = 0; i < list.size(); ++i) {
            QVariantMap m = list[i].toMap();
            if (m.value("post_id").toString() == postId) {
                mutator(m);
                list[i] = m;
            }
        }
    }
    if (!ownerActiveViewerItem_.isEmpty() && ownerActiveViewerItem_.value("post_id").toString() == postId) {
        mutator(ownerActiveViewerItem_);
    }
    emit ownerProfileChanged();
}
