import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: feedRoot
    readonly property color coral: "#FF2D55"
    readonly property color sheetBg: "#121316"
    property bool isStandaloneModal: false
    property var customVideosModel: null
    property int customInitialIndex: 0
    property string customTitle: ""
    signal requestCloseModal()

    readonly property var currentVideos: isStandaloneModal
        ? (customVideosModel || [])
        : telefam.activeFeedVideos
    readonly property int currentIdx: isStandaloneModal
        ? telefam.modalFeedIndex
        : telefam.activeVideoIndex
    readonly property var currentVideo: (currentIdx >= 0 && currentIdx < currentVideos.length)
        ? currentVideos[currentIdx]
        : null
    property bool userPaused: false
    property bool captionExpanded: false
    property real playbackPosMs: 0
    property real playbackDurMs: 0
    property bool isBuffering: false
    property bool hasPlaybackError: false
    property bool triedFallbackMp4: false
    property bool triedUrlRefresh: false
    property bool viewPingSentForCurrent: false
    property qreal watchAccumulatedMs: 0
    property int rewatchDelta: 0
    property string activeVideoId: ""
    property var playerObj: null
    property var videoOutputObj: null
    property var activeOptionsVideo: null
    property var activeReportVideo: null
    property string selectedReportReason: ""
    property var activeOwnerEditVideo: null
    property var activeOwnerVisibilityVideo: null
    property var pendingConfirmAction: null
    property string pendingConfirmTitle: ""
    property string pendingConfirmButton: ""

    readonly property var reportReasons: [
        { key: "spam", label: "Spam or misleading" },
        { key: "harassment", label: "Harassment or bullying" },
        { key: "nudity", label: "Nudity or sexual content" },
        { key: "violence", label: "Violence or dangerous acts" },
        { key: "misinformation", label: "False information" },
        { key: "hate_speech", label: "Hate speech" },
        { key: "copyright", label: "Intellectual property" },
        { key: "other", label: "Other" }
    ]

    function navigateDelta(delta) {
        if (currentVideos.length === 0) return
        var next = Math.max(0, Math.min(currentVideos.length - 1, currentIdx + delta))
        if (next === currentIdx) return
        if (isStandaloneModal) {
            telefam.setModalFeedIndex(next)
        } else {
            telefam.onFeedVideoSettled(next)
        }
    }

    function loadActiveVideoSource() {
        var v = currentVideo
        if (!v) {
            if (playerObj) playerObj.stop()
            activeVideoId = ""
            return
        }
        var vid = v.video_id || ""
        var isNew = (vid !== activeVideoId)
        activeVideoId = vid
        if (isNew) {
            userPaused = false
            captionExpanded = false
            hasPlaybackError = false
            triedFallbackMp4 = false
            triedUrlRefresh = false
            viewPingSentForCurrent = false
            watchAccumulatedMs = 0
            rewatchDelta = 0
            playbackPosMs = 0
            playbackDurMs = Number(v.duration_ms || 0)
        }

        var rawStream = (triedFallbackMp4 && (v.fallback_mp4_url || "").length > 0)
            ? v.fallback_mp4_url
            : ((v.stream_url || "").length > 0 ? v.stream_url : (v.fallback_mp4_url || ""))
        var fullUrl = telefam.resolveMediaUrl(rawStream)
        if (!playerObj || fullUrl.length === 0) return
        if (playerObj.source.toString() !== fullUrl) {
            isBuffering = true
            playerObj.source = fullUrl
        }
        var shouldPlay = visible && !userPaused && (isStandaloneModal || (!telefam.feedSearchOpen && telefam.activeHashtagTag.length === 0 && telefam.activeAudioId.length === 0 && !telefam.modalFeedOpen && !telefam.liveComingSoonOpen))
        if (shouldPlay) {
            playerObj.play()
        } else {
            playerObj.pause()
        }
    }

    function escapeHtml(s) {
        return (s || "")
            .replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;")
    }

    function formatCaptionRichText(desc, hashtags) {
        var base = (desc || "").trim()
        var extra = []
        if (hashtags && hashtags.length) {
            for (var i = 0; i < hashtags.length; ++i) {
                var tag = (hashtags[i] || "").replace(/^#/, "")
                if (tag.length > 0 && base.toLowerCase().indexOf("#" + tag.toLowerCase()) < 0) {
                    extra.push("#" + tag)
                }
            }
        }
        var joined = (base + (extra.length > 0 ? (base.length > 0 ? " " : "") + extra.join(" ") : "")).trim()
        var safe = escapeHtml(joined)
        return safe.replace(/#([A-Za-z0-9_]{1,40})/g, '<a href="tag:$1" style="color:#FF2D55; text-decoration:none; font-weight:600;">#$1</a>')
    }

    focus: visible
    Keys.onUpPressed: navigateDelta(-1)
    Keys.onDownPressed: navigateDelta(1)
    Keys.onSpacePressed: {
        if (!playerObj) return
        userPaused = !userPaused
        if (userPaused) playerObj.pause()
        else playerObj.play()
    }
    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_M) {
            telefam.feedMuted = !telefam.feedMuted
            event.accepted = true
        }
    }

    onVisibleChanged: {
        if (!visible && playerObj) {
            playerObj.pause()
        } else if (visible) {
            if (isStandaloneModal) forceActiveFocus()
            loadActiveVideoSource()
        }
    }
    onCurrentVideoChanged: loadActiveVideoSource()

    Connections {
        target: telefam
        function onFeedAudioStateChanged() {
            if (playerObj && playerObj.audioOutput) {
                playerObj.audioOutput.muted = telefam.feedMuted
            }
        }
        function onFeedDiscoveryChanged() {
            if (!feedRoot.isStandaloneModal && playerObj) {
                var blockedByOverlay = telefam.feedSearchOpen || telefam.activeHashtagTag.length > 0 || telefam.activeAudioId.length > 0 || telefam.modalFeedOpen || telefam.liveComingSoonOpen
                if (blockedByOverlay) playerObj.pause()
                else if (feedRoot.visible && !feedRoot.userPaused) playerObj.play()
            }
        }
    }

    Component.onCompleted: {
        if (telefam.hasMultimedia) {
            try {
                var vo = Qt.createQmlObject(
                    'import QtQuick; import QtMultimedia; VideoOutput { anchors.fill: parent; fillMode: VideoOutput.PreserveAspectFit }',
                    videoSurfaceHolder,
                    "TelefamFeedVideoOutput"
                )
                var mp = Qt.createQmlObject(
                    'import QtQuick; import QtMultimedia; MediaPlayer { loops: MediaPlayer.Infinite; audioOutput: AudioOutput { volume: 1.0 } }',
                    feedRoot,
                    "TelefamFeedMediaPlayer"
                )
                mp.videoOutput = vo
                mp.audioOutput.muted = telefam.feedMuted
                mp.playbackStateChanged.connect(function() {
                    if (!mp) return
                    if (mp.mediaStatus === 3 || mp.mediaStatus === 4) { // Buffering/Stalled
                        feedRoot.isBuffering = true
                    } else if (mp.mediaStatus === 6 || mp.mediaStatus === 2) { // Buffered/Loaded
                        feedRoot.isBuffering = false
                    }
                })
                mp.mediaStatusChanged.connect(function() {
                    if (!mp) return
                    feedRoot.isBuffering = (mp.mediaStatus === 3 || mp.mediaStatus === 4 || mp.mediaStatus === 1)
                    if (mp.mediaStatus === 7 && feedRoot.currentVideo) { // EndOfMedia
                        feedRoot.rewatchDelta += 1
                    }
                })
                mp.positionChanged.connect(function() {
                    if (feedRoot.playbackPosMs > 3000 && mp.position < 500) {
                        feedRoot.rewatchDelta += 1
                    }
                    feedRoot.playbackPosMs = mp.position
                    if (mp.duration > 0) feedRoot.playbackDurMs = mp.duration
                })
                mp.durationChanged.connect(function() {
                    if (mp.duration > 0) feedRoot.playbackDurMs = mp.duration
                })
                mp.errorOccurred.connect(function(err, errStr) {
                    var v = feedRoot.currentVideo
                    if (!v) return
                    if (!feedRoot.triedFallbackMp4 && (v.fallback_mp4_url || "").length > 0 && (v.fallback_mp4_url !== v.stream_url)) {
                        feedRoot.triedFallbackMp4 = true
                        feedRoot.loadActiveVideoSource()
                    } else if (!feedRoot.triedUrlRefresh) {
                        feedRoot.triedUrlRefresh = true
                        telefam.refreshSignedStreamUrl(v.video_id)
                    } else {
                        feedRoot.isBuffering = false
                        feedRoot.hasPlaybackError = true
                    }
                })
                videoOutputObj = vo
                playerObj = mp
                loadActiveVideoSource()
            } catch (e) {
                playerObj = null
            }
        }
    }

    Timer {
        interval: 2500
        running: feedRoot.visible && feedRoot.currentVideo !== null && !feedRoot.userPaused && (!feedRoot.isStandaloneModal ? !telefam.modalFeedOpen : true)
        repeat: true
        onTriggered: {
            var v = feedRoot.currentVideo
            if (!v || telefam.isOffline) return
            feedRoot.watchAccumulatedMs += 2500
            var dur = Math.max(1, feedRoot.playbackDurMs)
            var pct = Math.min(1.0, feedRoot.playbackPosMs / dur)
            var isView = !feedRoot.viewPingSentForCurrent
            feedRoot.viewPingSentForCurrent = true
            telefam.sendWatchProgress(
                v.video_id,
                Math.round(feedRoot.watchAccumulatedMs),
                Math.round(feedRoot.playbackPosMs),
                pct,
                feedRoot.rewatchDelta,
                isView
            )
            feedRoot.rewatchDelta = 0
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "#000000"
    }

    // Center Stage Canvas + Adaptive Aspect Fit
    Item {
        id: stageArea
        anchors.fill: parent

        readonly property var fitted: currentVideo
            ? telefam.computeFeedFit(width, height, Number(currentVideo.original_width || 0), Number(currentVideo.original_height || 0), Number(currentVideo.aspect_ratio || 0))
            : ({ width: width, height: height, needsAmbientBackdrop: false })
        readonly property string thumbUrl: currentVideo ? telefam.resolveMediaUrl(currentVideo.thumbnail_url || "") : ""

        // Ambient Backdrop when video aspect ratio leaves side/top bands
        Image {
            visible: stageArea.fitted.needsAmbientBackdrop && stageArea.thumbUrl.length > 0
            anchors.fill: parent
            source: stageArea.thumbUrl
            fillMode: Image.PreserveAspectCrop
            opacity: 0.35
        }
        Rectangle {
            visible: stageArea.fitted.needsAmbientBackdrop
            anchors.fill: parent
            color: "#73000000"
        }

        // Aspect-preserving Video Container
        Item {
            id: videoFrameBox
            anchors.centerIn: parent
            width: Math.max(1, stageArea.fitted.width)
            height: Math.max(1, stageArea.fitted.height)

            Image {
                anchors.fill: parent
                visible: stageArea.thumbUrl.length > 0
                source: stageArea.thumbUrl
                fillMode: Image.PreserveAspectFit
            }

            Item {
                id: videoSurfaceHolder
                anchors.fill: parent
            }
        }

        // Mouse & Wheel Gestures
        MouseArea {
            anchors.fill: parent
            onClicked: function(mouse) {
                feedRoot.forceActiveFocus()
                if (playerObj) {
                    feedRoot.userPaused = !feedRoot.userPaused
                    if (feedRoot.userPaused) playerObj.pause()
                    else playerObj.play()
                }
            }
            onDoubleClicked: function(mouse) {
                if (!feedRoot.currentVideo) return
                heartBurst.x = mouse.x - 42
                heartBurst.y = mouse.y - 42
                heartBurstAnim.restart()
                telefam.toggleVideoLike(feedRoot.currentVideo.video_id, true)
            }
            onWheel: function(wheel) {
                if (wheelTimer.running) return
                if (wheel.angleDelta.y < -20) {
                    feedRoot.navigateDelta(1)
                    wheelTimer.start()
                } else if (wheel.angleDelta.y > 20) {
                    feedRoot.navigateDelta(-1)
                    wheelTimer.start()
                }
            }
        }
        Timer { id: wheelTimer; interval: 260 }

        // Heart burst overlay on double-click
        Image {
            id: heartBurst
            source: "qrc:/telefam/icons/ic_heart_red.svg"
            sourceSize.width: 84
            sourceSize.height: 84
            opacity: 0
            scale: 0.5
            SequentialAnimation {
                id: heartBurstAnim
                ParallelAnimation {
                    NumberAnimation { target: heartBurst; property: "opacity"; from: 0; to: 1; duration: 140 }
                    NumberAnimation { target: heartBurst; property: "scale"; from: 0.5; to: 1.25; duration: 220; easing.type: Easing.OutBack }
                }
                PauseAnimation { duration: 280 }
                NumberAnimation { target: heartBurst; property: "opacity"; from: 1; to: 0; duration: 200 }
            }
        }

        // Paused Indicator
        Rectangle {
            visible: feedRoot.userPaused && feedRoot.currentVideo !== null && !feedRoot.hasPlaybackError
            anchors.centerIn: parent
            width: 70
            height: 70
            radius: 35
            color: "#73000000"
            Image {
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: 2
                source: "qrc:/telefam/icons/ic_play.svg"
                sourceSize.width: 28
                sourceSize.height: 28
            }
        }

        // Red / White / Green 3-Dot Orbital Spinner
        Canvas {
            id: triDotSpinner
            visible: (feedRoot.isBuffering || (telefam.videoFeedLoading && feedRoot.currentVideos.length === 0)) && !feedRoot.hasPlaybackError
            anchors.centerIn: parent
            width: 68
            height: 30
            property real phase: 0

            Timer {
                interval: 16
                running: triDotSpinner.visible
                repeat: true
                onTriggered: {
                    triDotSpinner.phase = (triDotSpinner.phase + 0.095) % (Math.PI * 2)
                    triDotSpinner.requestPaint()
                }
            }

            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                var colors = ["#FF2D55", "#FFFFFF", "#22C55E"]
                var cx = width / 2
                var cy = height / 2
                var orbitRx = width * 0.34
                var dots = []
                for (var i = 0; i < 3; ++i) {
                    var ang = phase + i * ((Math.PI * 2) / 3)
                    var depth = Math.sin(ang)
                    dots.push({
                        x: cx + Math.cos(ang) * orbitRx,
                        r: 4.5 * (0.72 + 0.42 * ((depth + 1) / 2)),
                        alpha: 0.65 + 0.35 * ((depth + 1) / 2),
                        depth: depth,
                        col: colors[i]
                    })
                }
                dots.sort(function(a, b) { return a.depth - b.depth })
                for (var j = 0; j < dots.length; ++j) {
                    var d = dots[j]
                    ctx.globalAlpha = d.alpha
                    ctx.fillStyle = d.col
                    ctx.beginPath()
                    ctx.arc(d.x, cy, d.r, 0, Math.PI * 2)
                    ctx.fill()
                }
                ctx.globalAlpha = 1.0
            }
        }

        // Playback Error / Empty / Offline State
        Rectangle {
            visible: (feedRoot.currentVideos.length === 0 && !telefam.videoFeedLoading) || feedRoot.hasPlaybackError
            anchors.centerIn: parent
            width: Math.min(340, parent.width - 48)
            height: emptyCol.implicitHeight + 36
            radius: 16
            color: "#CC0B0C0E"
            border.width: 1
            border.color: "#22FFFFFF"

            ColumnLayout {
                id: emptyCol
                anchors.fill: parent
                anchors.margins: 18
                spacing: 12

                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: telefam.isOffline ? "No internet." : (telefam.videoFeedError.length > 0 ? telefam.videoFeedError : (feedRoot.hasPlaybackError ? "An error has occurred. Try again later." : "No videos yet"))
                    color: "#FFFFFF"
                    font.pixelSize: 15
                    font.bold: true
                    wrapMode: Text.Wrap
                }

                Button {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: 132
                    Layout.preferredHeight: 42
                    background: Rectangle { color: coral; radius: 21 }
                    contentItem: Text {
                        text: "Retry"
                        color: "#FFFFFF"
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    onClicked: {
                        if (feedRoot.hasPlaybackError) {
                            feedRoot.hasPlaybackError = false
                            feedRoot.triedFallbackMp4 = false
                            feedRoot.triedUrlRefresh = false
                            feedRoot.loadActiveVideoSource()
                        } else {
                            telefam.refreshVideoFeed(telefam.videoFeedTab, true)
                        }
                    }
                }
            }
        }
    }

    // Bottom Gradient Scrim
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 240
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#00000000" }
            GradientStop { position: 1.0; color: "#BA000000" }
        }
    }

    // Top Bar (Standard: LIVE | Following | For You | Search  OR  Modal: Back + Title)
    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 76
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#99000000" }
            GradientStop { position: 1.0; color: "#00000000" }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            visible: !feedRoot.isStandaloneModal

            Button {
                Layout.preferredWidth: 48
                Layout.preferredHeight: 48
                flat: true
                contentItem: Item {
                    Image {
                        anchors.centerIn: parent
                        source: "qrc:/telefam/icons/ic_live_tv.svg"
                        sourceSize.width: 24
                        sourceSize.height: 24
                    }
                    Text {
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: 2
                        text: "LIVE"
                        color: "#FFFFFF"
                        font.pixelSize: 7
                        font.bold: true
                    }
                }
                onClicked: telefam.liveComingSoonOpen = true
            }

            Item { Layout.fillWidth: true }

            Row {
                spacing: 24
                Button {
                    height: 44
                    flat: true
                    readonly property bool sel: telefam.videoFeedTab === "following"
                    contentItem: Column {
                        spacing: 4
                        Text {
                            text: "Following"
                            color: parent.parent.sel ? "#FFFFFF" : "#ADFFFFFF"
                            font.pixelSize: 16
                            font.bold: parent.parent.sel
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                        Rectangle {
                            width: 26; height: 3; radius: 1.5
                            color: parent.parent.sel ? "#FFFFFF" : "transparent"
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }
                    onClicked: telefam.selectVideoFeedTab("following")
                }
                Button {
                    height: 44
                    flat: true
                    readonly property bool sel: telefam.videoFeedTab === "for_you"
                    contentItem: Column {
                        spacing: 4
                        Text {
                            text: "For You"
                            color: parent.parent.sel ? "#FFFFFF" : "#ADFFFFFF"
                            font.pixelSize: 16
                            font.bold: parent.parent.sel
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                        Rectangle {
                            width: 26; height: 3; radius: 1.5
                            color: parent.parent.sel ? "#FFFFFF" : "transparent"
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }
                    onClicked: telefam.selectVideoFeedTab("for_you")
                }
            }

            Item { Layout.fillWidth: true }

            Button {
                Layout.preferredWidth: 48
                Layout.preferredHeight: 48
                flat: true
                contentItem: Image {
                    anchors.centerIn: parent
                    source: "qrc:/telefam/icons/ic_search.svg"
                    sourceSize.width: 22
                    sourceSize.height: 22
                }
                onClicked: telefam.openFeedSearch()
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 16
            visible: feedRoot.isStandaloneModal
            spacing: 8

            Button {
                Layout.preferredWidth: 48
                Layout.preferredHeight: 48
                flat: true
                contentItem: Image {
                    anchors.centerIn: parent
                    source: "qrc:/telefam/icons/ic_back_white.svg"
                    sourceSize.width: 22
                    sourceSize.height: 22
                }
                onClicked: feedRoot.requestCloseModal()
            }

            Text {
                text: feedRoot.customTitle
                color: "#FFFFFF"
                font.pixelSize: 16
                font.bold: true
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
        }
    }

    // Desktop Up / Down Theater Controls (Left edge center)
    Column {
        visible: feedRoot.currentVideos.length > 1
        anchors.right: rightRailCol.left
        anchors.rightMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        spacing: 10

        Button {
            width: 40; height: 40
            enabled: feedRoot.currentIdx > 0
            opacity: enabled ? 1.0 : 0.35
            background: Rectangle { color: "#4DFFFFFF"; radius: 20 }
            contentItem: Image {
                anchors.centerIn: parent
                source: "qrc:/telefam/icons/ic_chevron_up_white.svg"
                sourceSize.width: 20; sourceSize.height: 20
            }
            onClicked: feedRoot.navigateDelta(-1)
        }
        Button {
            width: 40; height: 40
            enabled: feedRoot.currentIdx < feedRoot.currentVideos.length - 1
            opacity: enabled ? 1.0 : 0.35
            background: Rectangle { color: "#4DFFFFFF"; radius: 20 }
            contentItem: Image {
                anchors.centerIn: parent
                source: "qrc:/telefam/icons/ic_chevron_down_white.svg"
                sourceSize.width: 20; sourceSize.height: 20
            }
            onClicked: feedRoot.navigateDelta(1)
        }
    }

    // Right Interaction Column
    Column {
        id: rightRailCol
        visible: feedRoot.currentVideo !== null
        anchors.right: parent.right
        anchors.rightMargin: 16
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 28
        spacing: 14

        // 1. Creator Avatar + Red Follow (+)
        Item {
            width: 50
            height: 58
            anchors.horizontalCenter: parent.horizontalCenter

            Rectangle {
                width: 48; height: 48; radius: 24
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                color: "#24262C"
                border.color: "#FFFFFF"
                border.width: 1.5
                Text {
                    anchors.centerIn: parent
                    readonly property string rawN: feedRoot.currentVideo ? (feedRoot.currentVideo.creator_username || feedRoot.currentVideo.creator_name || "TF") : "TF"
                    text: rawN.slice(0, 2).toUpperCase()
                    color: "#FFFFFF"
                    font.bold: true
                    font.pixelSize: 15
                }
            }

            Button {
                visible: feedRoot.currentVideo && !feedRoot.currentVideo.is_owner && !feedRoot.currentVideo.is_following_creator
                width: 22; height: 22
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                background: Rectangle { color: coral; radius: 11 }
                contentItem: Image {
                    anchors.centerIn: parent
                    source: "qrc:/telefam/icons/ic_plus_white.svg"
                    sourceSize.width: 12; sourceSize.height: 12
                }
                onClicked: telefam.toggleFollowCreator(feedRoot.currentVideo.creator_id)
            }
        }

        // 2. Heart Like
        Column {
            spacing: 2
            anchors.horizontalCenter: parent.horizontalCenter
            Button {
                width: 48; height: 44
                flat: true
                contentItem: Image {
                    anchors.centerIn: parent
                    source: (feedRoot.currentVideo && feedRoot.currentVideo.is_liked)
                        ? "qrc:/telefam/icons/ic_heart_red.svg"
                        : "qrc:/telefam/icons/ic_heart_white.svg"
                    sourceSize.width: 30; sourceSize.height: 30
                }
                onClicked: telefam.toggleVideoLike(feedRoot.currentVideo.video_id, false)
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: telefam.formatFeedCount(feedRoot.currentVideo ? Number(feedRoot.currentVideo.likes_count || 0) : 0)
                color: "#FFFFFF"; font.pixelSize: 12; font.bold: true
            }
        }

        // 3. Comments (Coming Soon)
        Column {
            spacing: 2
            anchors.horizontalCenter: parent.horizontalCenter
            Button {
                width: 48; height: 44
                flat: true
                contentItem: Image {
                    anchors.centerIn: parent
                    source: "qrc:/telefam/icons/ic_feed_comment.svg"
                    sourceSize.width: 29; sourceSize.height: 29
                }
                onClicked: commentsDialog.open()
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: telefam.formatFeedCount(feedRoot.currentVideo ? Number(feedRoot.currentVideo.comments_count || 0) : 0)
                color: "#FFFFFF"; font.pixelSize: 12; font.bold: true
            }
        }

        // 4. Share
        Column {
            spacing: 2
            anchors.horizontalCenter: parent.horizontalCenter
            Button {
                width: 48; height: 44
                flat: true
                contentItem: Image {
                    anchors.centerIn: parent
                    source: (feedRoot.currentVideo && feedRoot.currentVideo.is_liked)
                        ? "qrc:/telefam/icons/ic_feed_share_white.svg"
                        : "qrc:/telefam/icons/ic_feed_share_red.svg"
                    sourceSize.width: 27; sourceSize.height: 27
                }
                onClicked: telefam.shareVideo(feedRoot.currentVideo.video_id, feedRoot.currentVideo.stream_url || "")
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: telefam.formatFeedCount(feedRoot.currentVideo ? Number(feedRoot.currentVideo.shares_count || 0) : 0)
                color: "#FFFFFF"; font.pixelSize: 12; font.bold: true
            }
        }

        // 5. Bookmark / Save
        Column {
            spacing: 2
            anchors.horizontalCenter: parent.horizontalCenter
            Button {
                width: 48; height: 44
                flat: true
                contentItem: Image {
                    anchors.centerIn: parent
                    source: (feedRoot.currentVideo && feedRoot.currentVideo.is_saved)
                        ? "qrc:/telefam/icons/ic_bookmark_filled.svg"
                        : "qrc:/telefam/icons/ic_bookmark_red.svg"
                    sourceSize.width: 26; sourceSize.height: 28
                }
                onClicked: telefam.toggleVideoSave(feedRoot.currentVideo.video_id)
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: telefam.formatFeedCount(feedRoot.currentVideo ? Number(feedRoot.currentVideo.saves_count || 0) : 0)
                color: "#FFFFFF"; font.pixelSize: 12; font.bold: true
            }
        }

        // 6. More Options
        Button {
            width: 48; height: 40
            anchors.horizontalCenter: parent.horizontalCenter
            flat: true
            contentItem: Image {
                anchors.centerIn: parent
                source: "qrc:/telefam/icons/ic_more_horiz.svg"
                sourceSize.width: 26; sourceSize.height: 26
            }
            onClicked: {
                feedRoot.activeOptionsVideo = feedRoot.currentVideo
                optionsDialog.open()
            }
        }
    }

    // Bottom-Left Information Overlay
    ColumnLayout {
        visible: feedRoot.currentVideo !== null
        anchors.left: parent.left
        anchors.right: rightRailCol.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: 18
        anchors.rightMargin: 20
        anchors.bottomMargin: 28
        spacing: 8

        // Recommendation Pill
        Rectangle {
            visible: feedRoot.currentVideo && (feedRoot.currentVideo.recommendation_label || "").length > 0
            height: 28
            width: recRow.implicitWidth + 20
            radius: 14
            color: "#73000000"
            border.width: 1
            border.color: "#2EFFFFFF"

            Row {
                id: recRow
                anchors.centerIn: parent
                spacing: 6
                Image {
                    anchors.verticalCenter: parent.verticalCenter
                    source: "qrc:/telefam/icons/ic_sparkle.svg"
                    sourceSize.width: 13; sourceSize.height: 13
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: feedRoot.currentVideo ? (feedRoot.currentVideo.recommendation_label || "") : ""
                    color: "#EBFFFFFF"
                    font.pixelSize: 12
                    font.medium: true
                }
            }
        }

        // Creator username
        Text {
            text: feedRoot.currentVideo
                ? (feedRoot.currentVideo.creator_username || feedRoot.currentVideo.creator_name || "")
                : ""
            color: "#FFFFFF"
            font.pixelSize: 16
            font.bold: true
        }

        // Expandable Caption + Clickable #Hashtags
        ColumnLayout {
            visible: feedRoot.currentVideo && ((feedRoot.currentVideo.description || "").length > 0 || (feedRoot.currentVideo.hashtags && feedRoot.currentVideo.hashtags.length > 0))
            Layout.fillWidth: true
            spacing: 4

            Text {
                id: captionRichText
                Layout.fillWidth: true
                Layout.maximumWidth: 520
                textFormat: Text.RichText
                text: feedRoot.currentVideo
                    ? feedRoot.formatCaptionRichText(feedRoot.currentVideo.description, feedRoot.currentVideo.hashtags)
                    : ""
                color: "#FFFFFF"
                font.pixelSize: 14
                wrapMode: Text.Wrap
                maximumLineCount: feedRoot.captionExpanded ? 10 : 2
                elide: Text.ElideRight
                onLinkActivated: function(link) {
                    if (link.indexOf("tag:") === 0) {
                        var tag = link.slice(4)
                        if (feedRoot.isStandaloneModal) feedRoot.requestCloseModal()
                        telefam.openHashtagDiscovery(tag)
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.NoButton
                    cursorShape: captionRichText.hoveredLink.length > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                }
            }

            Button {
                visible: feedRoot.currentVideo && ((feedRoot.currentVideo.description || "").length > 75 || (feedRoot.currentVideo.hashtags || []).length > 2)
                flat: true
                padding: 0
                contentItem: Text {
                    text: feedRoot.captionExpanded ? "Read less" : "Read more"
                    color: "#BFFFFFFF"
                    font.pixelSize: 13
                    font.bold: true
                }
                onClicked: feedRoot.captionExpanded = !feedRoot.captionExpanded
            }
        }

        // Audio Row + Mute Toggle
        RowLayout {
            spacing: 10
            Button {
                flat: true
                padding: 0
                Layout.preferredHeight: 34
                contentItem: Row {
                    spacing: 6
                    Image {
                        anchors.verticalCenter: parent.verticalCenter
                        source: "qrc:/telefam/icons/ic_music_note.svg"
                        sourceSize.width: 15; sourceSize.height: 15
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: feedRoot.currentVideo && feedRoot.currentVideo.audio && (feedRoot.currentVideo.audio.title || "").length > 0
                            ? feedRoot.currentVideo.audio.title
                            : "Original sound"
                        color: "#FFFFFF"
                        font.pixelSize: 13
                        font.medium: true
                        elide: Text.ElideRight
                        width: Math.min(implicitWidth, 240)
                    }
                    Image {
                        anchors.verticalCenter: parent.verticalCenter
                        source: "qrc:/telefam/icons/ic_equalizer.svg"
                        sourceSize.width: 14; sourceSize.height: 14
                    }
                }
                onClicked: {
                    var audId = feedRoot.currentVideo && feedRoot.currentVideo.audio ? (feedRoot.currentVideo.audio.audio_id || "") : ""
                    if (audId.length > 0) {
                        if (feedRoot.isStandaloneModal) feedRoot.requestCloseModal()
                        telefam.openAudioDiscovery(audId)
                    }
                }
            }

            Button {
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                background: Rectangle { color: "#73000000"; radius: 16 }
                contentItem: Image {
                    anchors.centerIn: parent
                    source: telefam.feedMuted ? "qrc:/telefam/icons/ic_volume_off.svg" : "qrc:/telefam/icons/ic_volume_on.svg"
                    sourceSize.width: 15; sourceSize.height: 15
                }
                onClicked: telefam.feedMuted = !telefam.feedMuted
            }
        }
    }

    // Bottom Progress Bar & Interactive Scrubber
    Item {
        visible: feedRoot.playbackDurMs > 0
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 10

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 3
            color: "#38FFFFFF"
            Rectangle {
                height: parent.height
                width: parent.width * Math.min(1.0, Math.max(0.0, feedRoot.playbackPosMs / Math.max(1.0, feedRoot.playbackDurMs)))
                color: "#EBFFFFFF"
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: function(mouse) {
                if (playerObj && feedRoot.playbackDurMs > 0) {
                    var ratio = Math.min(1.0, Math.max(0.0, mouse.x / width))
                    playerObj.position = Math.round(ratio * feedRoot.playbackDurMs)
                }
            }
        }
    }

    // Comments Coming Soon Dialog
    Dialog {
        id: commentsDialog
        modal: true
        anchors.centerIn: parent
        width: 340
        background: Rectangle { color: sheetBg; radius: 16; border.color: "#22FFFFFF"; border.width: 1 }
        ColumnLayout {
            width: parent.width
            spacing: 14
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                width: 64; height: 64; radius: 32; color: "#29FF2D55"
                Image { anchors.centerIn: parent; source: "qrc:/telefam/icons/ic_feed_comment.svg"; sourceSize.width: 28; sourceSize.height: 28 }
            }
            Text { Layout.alignment: Qt.AlignHCenter; text: "Comments Coming Soon"; color: "#FFFFFF"; font.pixelSize: 17; font.bold: true }
            Text { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; text: "Video comments are not open yet."; color: "#ADFFFFFF"; font.pixelSize: 13; wrapMode: Text.Wrap }
            Button {
                Layout.fillWidth: true; Layout.preferredHeight: 44
                background: Rectangle { color: "#24FFFFFF"; radius: 10 }
                contentItem: Text { text: "Close"; color: "#FFFFFF"; font.bold: true; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                onClicked: commentsDialog.close()
            }
        }
    }

    // Options Dialog (Owner vs Viewer)
    Dialog {
        id: optionsDialog
        modal: true
        anchors.centerIn: parent
        width: 360
        background: Rectangle { color: sheetBg; radius: 16; border.color: "#22FFFFFF"; border.width: 1 }

        ColumnLayout {
            width: parent.width
            spacing: 6

            // Owner controls
            Button {
                visible: feedRoot.activeOptionsVideo && feedRoot.activeOptionsVideo.is_owner
                Layout.fillWidth: true; Layout.preferredHeight: 46; flat: true
                contentItem: RowLayout {
                    spacing: 12
                    Image { source: "qrc:/telefam/icons/ic_edit_white.svg"; sourceSize.width: 20; sourceSize.height: 20 }
                    Text { text: "Edit details"; color: "#FFFFFF"; font.pixelSize: 15; Layout.fillWidth: true }
                }
                onClicked: {
                    optionsDialog.close()
                    feedRoot.activeOwnerEditVideo = feedRoot.activeOptionsVideo
                    editTitleField.text = feedRoot.activeOwnerEditVideo.title || ""
                    editDescArea.text = feedRoot.activeOwnerEditVideo.description || ""
                    ownerEditDialog.open()
                }
            }
            Button {
                visible: feedRoot.activeOptionsVideo && feedRoot.activeOptionsVideo.is_owner
                Layout.fillWidth: true; Layout.preferredHeight: 46; flat: true
                contentItem: RowLayout {
                    spacing: 12
                    Image { source: "qrc:/telefam/icons/ic_lock_white.svg"; sourceSize.width: 20; sourceSize.height: 20 }
                    Text {
                        text: (feedRoot.activeOptionsVideo && feedRoot.activeOptionsVideo.visibility === "private") ? "Private" : "Mark as private"
                        color: "#FFFFFF"; font.pixelSize: 15; Layout.fillWidth: true
                    }
                }
                onClicked: {
                    var vid = feedRoot.activeOptionsVideo.video_id
                    optionsDialog.close()
                    telefam.updateOwnerVideoVisibility(vid, "private")
                }
            }
            Button {
                visible: feedRoot.activeOptionsVideo && feedRoot.activeOptionsVideo.is_owner
                Layout.fillWidth: true; Layout.preferredHeight: 46; flat: true
                contentItem: RowLayout {
                    spacing: 12
                    Image { source: "qrc:/telefam/icons/ic_visibility_white.svg"; sourceSize.width: 20; sourceSize.height: 20 }
                    Text { text: "Change visibility"; color: "#FFFFFF"; font.pixelSize: 15; Layout.fillWidth: true }
                }
                onClicked: {
                    optionsDialog.close()
                    feedRoot.activeOwnerVisibilityVideo = feedRoot.activeOptionsVideo
                    ownerVisibilityDialog.open()
                }
            }
            Button {
                visible: feedRoot.activeOptionsVideo && feedRoot.activeOptionsVideo.is_owner
                Layout.fillWidth: true; Layout.preferredHeight: 46; flat: true
                contentItem: RowLayout {
                    spacing: 12
                    Image { source: "qrc:/telefam/icons/ic_trash_red.svg"; sourceSize.width: 20; sourceSize.height: 20 }
                    Text { text: "Delete video"; color: coral; font.pixelSize: 15; Layout.fillWidth: true }
                }
                onClicked: {
                    var vid = feedRoot.activeOptionsVideo.video_id
                    optionsDialog.close()
                    feedRoot.pendingConfirmTitle = "Delete video?"
                    feedRoot.pendingConfirmButton = "Delete"
                    feedRoot.pendingConfirmAction = function() { telefam.deleteOwnerVideo(vid) }
                    confirmActionDialog.open()
                }
            }

            // Viewer controls
            Button {
                visible: feedRoot.activeOptionsVideo && !feedRoot.activeOptionsVideo.is_owner
                Layout.fillWidth: true; Layout.preferredHeight: 46; flat: true
                contentItem: RowLayout {
                    spacing: 12
                    Image { source: "qrc:/telefam/icons/ic_repost.svg"; sourceSize.width: 20; sourceSize.height: 20 }
                    Text {
                        text: (feedRoot.activeOptionsVideo && feedRoot.activeOptionsVideo.is_reposted) ? "Remove repost" : "Repost"
                        color: "#FFFFFF"; font.pixelSize: 15; Layout.fillWidth: true
                    }
                }
                onClicked: {
                    var vid = feedRoot.activeOptionsVideo.video_id
                    optionsDialog.close()
                    telefam.toggleVideoRepost(vid)
                }
            }
            Button {
                visible: feedRoot.activeOptionsVideo && !feedRoot.activeOptionsVideo.is_owner
                Layout.fillWidth: true; Layout.preferredHeight: 46; flat: true
                contentItem: RowLayout {
                    spacing: 12
                    Image { source: "qrc:/telefam/icons/ic_close_white.svg"; sourceSize.width: 18; sourceSize.height: 18 }
                    Text { text: "Not interested"; color: "#FFFFFF"; font.pixelSize: 15; Layout.fillWidth: true }
                }
                onClicked: {
                    var vid = feedRoot.activeOptionsVideo.video_id
                    optionsDialog.close()
                    telefam.markVideoNotInterested(vid)
                }
            }
            Button {
                visible: feedRoot.activeOptionsVideo && !feedRoot.activeOptionsVideo.is_owner
                Layout.fillWidth: true; Layout.preferredHeight: 46; flat: true
                contentItem: RowLayout {
                    spacing: 12
                    Image { source: "qrc:/telefam/icons/ic_volume_off.svg"; sourceSize.width: 20; sourceSize.height: 20 }
                    Text {
                        text: "Mute @" + (feedRoot.activeOptionsVideo ? (feedRoot.activeOptionsVideo.creator_username || "") : "")
                        color: "#FFFFFF"; font.pixelSize: 15; Layout.fillWidth: true
                    }
                }
                onClicked: {
                    var cid = feedRoot.activeOptionsVideo.creator_id
                    optionsDialog.close()
                    feedRoot.pendingConfirmTitle = "Mute creator?"
                    feedRoot.pendingConfirmButton = "Mute"
                    feedRoot.pendingConfirmAction = function() { telefam.muteCreator(cid) }
                    confirmActionDialog.open()
                }
            }
            Button {
                visible: feedRoot.activeOptionsVideo && !feedRoot.activeOptionsVideo.is_owner
                Layout.fillWidth: true; Layout.preferredHeight: 46; flat: true
                contentItem: RowLayout {
                    spacing: 12
                    Image { source: "qrc:/telefam/icons/ic_block.svg"; sourceSize.width: 20; sourceSize.height: 20 }
                    Text {
                        text: "Block @" + (feedRoot.activeOptionsVideo ? (feedRoot.activeOptionsVideo.creator_username || "") : "")
                        color: coral; font.pixelSize: 15; Layout.fillWidth: true
                    }
                }
                onClicked: {
                    var cid = feedRoot.activeOptionsVideo.creator_id
                    optionsDialog.close()
                    feedRoot.pendingConfirmTitle = "Block creator?"
                    feedRoot.pendingConfirmButton = "Block"
                    feedRoot.pendingConfirmAction = function() { telefam.blockCreator(cid) }
                    confirmActionDialog.open()
                }
            }
            Button {
                visible: feedRoot.activeOptionsVideo && !feedRoot.activeOptionsVideo.is_owner
                Layout.fillWidth: true; Layout.preferredHeight: 46; flat: true
                contentItem: RowLayout {
                    spacing: 12
                    Image { source: "qrc:/telefam/icons/ic_flag_report.svg"; sourceSize.width: 20; sourceSize.height: 20 }
                    Text { text: "Report video"; color: coral; font.pixelSize: 15; Layout.fillWidth: true }
                }
                onClicked: {
                    optionsDialog.close()
                    feedRoot.activeReportVideo = feedRoot.activeOptionsVideo
                    feedRoot.selectedReportReason = ""
                    reportDetailsArea.text = ""
                    reportDialog.open()
                }
            }
        }
    }

    // Report Dialog (2-step: 8 reasons -> optional details)
    Dialog {
        id: reportDialog
        modal: true
        anchors.centerIn: parent
        width: 400
        background: Rectangle { color: sheetBg; radius: 16; border.color: "#22FFFFFF"; border.width: 1 }

        ColumnLayout {
            width: parent.width
            spacing: 10
            Text { text: "Report video"; color: "#FFFFFF"; font.pixelSize: 17; font.bold: true }

            Repeater {
                model: feedRoot.selectedReportReason.length === 0 ? feedRoot.reportReasons : []
                delegate: Button {
                    Layout.fillWidth: true; Layout.preferredHeight: 40; flat: true
                    contentItem: RowLayout {
                        Text { text: modelData.label; color: "#FFFFFF"; font.pixelSize: 14; Layout.fillWidth: true }
                        Image { source: "qrc:/telefam/icons/ic_chevron_right.svg"; sourceSize.width: 14; sourceSize.height: 14 }
                    }
                    onClicked: feedRoot.selectedReportReason = modelData.key
                }
            }

            ColumnLayout {
                visible: feedRoot.selectedReportReason.length > 0
                Layout.fillWidth: true
                spacing: 10
                TextArea {
                    id: reportDetailsArea
                    Layout.fillWidth: true; Layout.preferredHeight: 100
                    color: "#FFFFFF"
                    placeholderText: "Details (optional)"
                    placeholderTextColor: "#70FFFFFF"
                    background: Rectangle { color: "#14FFFFFF"; radius: 10 }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Button {
                        Layout.fillWidth: true; Layout.preferredHeight: 42
                        background: Rectangle { color: "#20FFFFFF"; radius: 10 }
                        contentItem: Text { text: "Back"; color: "#FFFFFF"; font.bold: true; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                        onClicked: feedRoot.selectedReportReason = ""
                    }
                    Button {
                        Layout.fillWidth: true; Layout.preferredHeight: 42
                        background: Rectangle { color: coral; radius: 10 }
                        contentItem: Text { text: "Submit"; color: "#FFFFFF"; font.bold: true; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                        onClicked: {
                            telefam.reportVideo(feedRoot.activeReportVideo.video_id, feedRoot.selectedReportReason, reportDetailsArea.text)
                            reportDialog.close()
                        }
                    }
                }
            }
        }
    }

    // Owner Edit Dialog
    Dialog {
        id: ownerEditDialog
        modal: true
        anchors.centerIn: parent
        width: 400
        background: Rectangle { color: sheetBg; radius: 16; border.color: "#22FFFFFF"; border.width: 1 }

        ColumnLayout {
            width: parent.width
            spacing: 10
            Text { text: "Edit details"; color: "#FFFFFF"; font.pixelSize: 17; font.bold: true }
            TextField {
                id: editTitleField
                Layout.fillWidth: true
                color: "#FFFFFF"
                placeholderText: "Title"
                placeholderTextColor: "#70FFFFFF"
                background: Rectangle { color: "#14FFFFFF"; radius: 10 }
            }
            TextArea {
                id: editDescArea
                Layout.fillWidth: true; Layout.preferredHeight: 110
                color: "#FFFFFF"
                placeholderText: "Description"
                placeholderTextColor: "#70FFFFFF"
                background: Rectangle { color: "#14FFFFFF"; radius: 10 }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Button {
                    Layout.fillWidth: true; Layout.preferredHeight: 42
                    background: Rectangle { color: "#20FFFFFF"; radius: 10 }
                    contentItem: Text { text: "Cancel"; color: "#FFFFFF"; font.bold: true; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    onClicked: ownerEditDialog.close()
                }
                Button {
                    Layout.fillWidth: true; Layout.preferredHeight: 42
                    background: Rectangle { color: coral; radius: 10 }
                    contentItem: Text { text: "Save"; color: "#FFFFFF"; font.bold: true; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    onClicked: {
                        telefam.updateOwnerVideoDetails(feedRoot.activeOwnerEditVideo.video_id, editTitleField.text, editDescArea.text)
                        ownerEditDialog.close()
                    }
                }
            }
        }
    }

    // Owner Visibility Dialog
    Dialog {
        id: ownerVisibilityDialog
        modal: true
        anchors.centerIn: parent
        width: 340
        background: Rectangle { color: sheetBg; radius: 16; border.color: "#22FFFFFF"; border.width: 1 }

        ColumnLayout {
            width: parent.width
            spacing: 8
            Text { text: "Change visibility"; color: "#FFFFFF"; font.pixelSize: 17; font.bold: true }
            Repeater {
                model: [
                    { key: "public", label: "Public" },
                    { key: "followers", label: "Followers only" },
                    { key: "private", label: "Private" }
                ]
                delegate: Button {
                    Layout.fillWidth: true; Layout.preferredHeight: 44
                    background: Rectangle { color: "#14FFFFFF"; radius: 10 }
                    contentItem: RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12
                        Text { text: modelData.label; color: "#FFFFFF"; font.pixelSize: 14; Layout.fillWidth: true }
                        Image {
                            visible: feedRoot.activeOwnerVisibilityVideo && feedRoot.activeOwnerVisibilityVideo.visibility === modelData.key
                            source: "qrc:/telefam/icons/ic_check.svg"
                            sourceSize.width: 16; sourceSize.height: 16
                        }
                    }
                    onClicked: {
                        telefam.updateOwnerVideoVisibility(feedRoot.activeOwnerVisibilityVideo.video_id, modelData.key)
                        ownerVisibilityDialog.close()
                    }
                }
            }
        }
    }

    // Confirm Destructive Action Dialog
    Dialog {
        id: confirmActionDialog
        modal: true
        anchors.centerIn: parent
        width: 320
        background: Rectangle { color: sheetBg; radius: 16; border.color: "#22FFFFFF"; border.width: 1 }
        ColumnLayout {
            width: parent.width
            spacing: 14
            Text { text: feedRoot.pendingConfirmTitle; color: "#FFFFFF"; font.pixelSize: 16; font.bold: true; Layout.alignment: Qt.AlignHCenter }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Button {
                    Layout.fillWidth: true; Layout.preferredHeight: 42
                    background: Rectangle { color: "#20FFFFFF"; radius: 10 }
                    contentItem: Text { text: "Cancel"; color: "#FFFFFF"; font.bold: true; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    onClicked: confirmActionDialog.close()
                }
                Button {
                    Layout.fillWidth: true; Layout.preferredHeight: 42
                    background: Rectangle { color: coral; radius: 10 }
                    contentItem: Text { text: feedRoot.pendingConfirmButton; color: "#FFFFFF"; font.bold: true; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    onClicked: {
                        if (feedRoot.pendingConfirmAction) feedRoot.pendingConfirmAction()
                        confirmActionDialog.close()
                    }
                }
            }
        }
    }
}
