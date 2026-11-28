import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts

Item {
    id: root
    readonly property color brandRed: "#C81010"
    readonly property color bodyBg: telefam.isDarkTheme ? "#121316" : "#FFFFFF"
    readonly property color cardBg: telefam.isDarkTheme ? "#1B1D22" : "#F6F7F9"
    readonly property color borderCol: telefam.isDarkTheme ? "#2B2F38" : "#E5E7EB"
    readonly property color inkCol: telefam.isDarkTheme ? "#FFFFFF" : "#111827"
    readonly property color subCol: telefam.isDarkTheme ? "#9CA3AF" : "#6B7280"

    property string postMode: "text"
    property string textBody: ""
    property string captionBody: ""
    property bool showImageThemes: false
    property string selectedBgColorHex: "#C81010"
    property string selectedImageThemeId: ""
    property string selectedFontId: "classic"
    property bool muteOriginalAudio: false

    property var selectedSong: null
    property var taggedContacts: []
    property var selectedHashtags: []

    readonly property var bgColors: [
        { hex: "#C81010", darkText: false },
        { hex: "#FF9E5E", darkText: false },
        { hex: "#169AE6", darkText: false },
        { hex: "#149A5A", darkText: false },
        { hex: "#8B5CF6", darkText: false },
        { hex: "#232B38", darkText: false },
        { hex: "#F5EEDC", darkText: true  },
        { hex: "#E11D48", darkText: false },
        { hex: "#0D9488", darkText: false },
        { hex: "#4338CA", darkText: false },
        { hex: "#D97706", darkText: false },
        { hex: "#BE185D", darkText: false },
        { hex: "#0F172A", darkText: false },
        { hex: "#10B981", darkText: false }
    ]

    readonly property var imageThemes: [
        { id: "aurora", name: "Aurora", primary: "#081C24", secondary: "#10B981", accent: "#38BDF8" },
        { id: "sunset_peaks", name: "Sunset Peaks", primary: "#7C2D12", secondary: "#FB7185", accent: "#FBBF24" },
        { id: "starry_night", name: "Starry Night", primary: "#0B1026", secondary: "#1E3A8A", accent: "#FDE047" },
        { id: "ocean_waves", name: "Ocean Waves", primary: "#042F4B", secondary: "#0284C7", accent: "#7DD3FC" },
        { id: "desert_dunes", name: "Desert Dunes", primary: "#9A3412", secondary: "#F59E0B", accent: "#FED7AA" },
        { id: "sakura_blossom", name: "Sakura", primary: "#831843", secondary: "#F472B6", accent: "#FCE7F3" },
        { id: "cyber_grid", name: "Cyber Grid", primary: "#090D16", secondary: "#9333EA", accent: "#22D3EE" },
        { id: "forest_mist", name: "Forest Mist", primary: "#064E3B", secondary: "#059669", accent: "#A7F3D0" },
        { id: "marble_gold", name: "Marble Gold", primary: "#1C1917", secondary: "#44403C", accent: "#FBBF24" },
        { id: "neon_horizon", name: "Neon Horizon", primary: "#311042", secondary: "#EC4899", accent: "#FACC15" },
        { id: "abstract_prism", name: "Prism", primary: "#1E1B4B", secondary: "#6366F1", accent: "#F43F5E" },
        { id: "rainy_glass", name: "Rainy Glass", primary: "#1E293B", secondary: "#475569", accent: "#93C5FD" },
        { id: "warm_bokeh", name: "Warm Bokeh", primary: "#450A0A", secondary: "#DC2626", accent: "#FDBA74" },
        { id: "midnight_clouds", name: "Midnight Clouds", primary: "#0F172A", secondary: "#334155", accent: "#C084FC" },
        { id: "coral_reef", name: "Coral Reef", primary: "#134E4A", secondary: "#FB7185", accent: "#2DD4BF" }
    ]

    readonly property var fontStyles: [
        { id: "classic", badge: "Aa", label: "Classic", family: "Sans", bold: false, italic: false },
        { id: "serif", badge: "Aa", label: "Serif", family: "Serif", bold: false, italic: false },
        { id: "hand", badge: "Aa", label: "Hand", family: "Cursive", bold: false, italic: true },
        { id: "typewriter", badge: "Aa", label: "Typewriter", family: "Monospace", bold: false, italic: false },
        { id: "bold", badge: "AA", label: "Bold", family: "Sans", bold: true, italic: false },
        { id: "mono", badge: "Aa", label: "Mono", family: "Monospace", bold: false, italic: false },
        { id: "display", badge: "Aa", label: "Display", family: "Sans", bold: true, italic: false },
        { id: "rounded", badge: "Aa", label: "Rounded", family: "Sans", bold: false, italic: false },
        { id: "italic", badge: "Aa", label: "Italic", family: "Serif", bold: false, italic: true },
        { id: "script", badge: "Aa", label: "Script", family: "Cursive", bold: true, italic: true },
        { id: "slab", badge: "Aa", label: "Slab", family: "Serif", bold: true, italic: false },
        { id: "condensed", badge: "Aa", label: "Condensed", family: "Sans", bold: true, italic: false }
    ]

    readonly property var activeFontObj: {
        for (var i = 0; i < fontStyles.length; ++i) {
            if (fontStyles[i].id === selectedFontId) return fontStyles[i]
        }
        return fontStyles[0]
    }

    readonly property var activeThemeObj: {
        if (selectedImageThemeId.length === 0) return null
        for (var i = 0; i < imageThemes.length; ++i) {
            if (imageThemes[i].id === selectedImageThemeId) return imageThemes[i]
        }
        return null
    }

    readonly property color textCardFg: {
        if (activeThemeObj !== null) return "#FFFFFF"
        for (var i = 0; i < bgColors.length; ++i) {
            if (bgColors[i].hex === selectedBgColorHex && bgColors[i].darkText) return "#1C1E22"
        }
        return "#FFFFFF"
    }

    readonly property bool canShare: {
        if (telefam.postUploadStatus === "uploading") return false
        if (postMode === "text") return textBody.trim().length > 0
        if (postMode === "photos") return telefam.postPhotos.length > 0
        if (postMode === "video") return telefam.postVideoPath.length > 0
        return false
    }

    function formatMs(ms) {
        var secs = Math.max(0, Math.floor(ms / 1000))
        var m = Math.floor(secs / 60)
        var s = secs % 60
        return m + ":" + (s < 10 ? "0" + s : s)
    }

    function isContactTagged(uid) {
        for (var i = 0; i < taggedContacts.length; ++i) {
            if (taggedContacts[i].user_id === uid) return true
        }
        return false
    }

    function toggleContactTag(contact) {
        var next = taggedContacts.slice()
        for (var i = 0; i < next.length; ++i) {
            if (next[i].user_id === contact.user_id) {
                next.splice(i, 1)
                taggedContacts = next
                return
            }
        }
        next.push(contact)
        taggedContacts = next
    }

    function toggleHashtagItem(raw) {
        var clean = raw.trim().replace(/^#/, "").toLowerCase().replace(/[^a-z0-9_]/g, "")
        if (clean.length === 0) return
        var next = selectedHashtags.slice()
        var idx = next.indexOf(clean)
        if (idx >= 0) {
            next.splice(idx, 1)
        } else if (next.length < 20) {
            next.push(clean)
        }
        selectedHashtags = next
    }

    focus: true
    Keys.onEscapePressed: telefam.closePostComposer()

    Connections {
        target: telefam
        function onPrefilledPostSongChanged() {
            if (telefam.prefilledPostSong && (telefam.prefilledPostSong.title || "").length > 0) {
                root.postMode = "video"
                root.selectedSong = telefam.prefilledPostSong
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Crimson Top Header matching uploaded design
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: telefam.postUploadStatus === "uploading" || telefam.postUploadStatus === "uploaded" ? 142 : 112
            color: brandRed

            ColumnLayout {
                anchors.fill: parent
                anchors.leftMargin: 18
                anchors.rightMargin: 18
                anchors.topMargin: 10
                anchors.bottomMargin: 10
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    Button {
                        Layout.preferredWidth: 44
                        Layout.preferredHeight: 44
                        flat: true
                        contentItem: Image {
                            source: "qrc:/telefam/icons/ic_close_white.svg"
                            sourceSize.width: 20
                            sourceSize.height: 20
                            fillMode: Image.PreserveAspectFit
                        }
                        onClicked: telefam.closePostComposer()
                    }

                    Text {
                        text: "New post"
                        color: "#FFFFFF"
                        font.pixelSize: 20
                        font.bold: true
                        Layout.fillWidth: true
                    }

                    Button {
                        enabled: root.canShare
                        Layout.preferredHeight: 38
                        Layout.preferredWidth: 88
                        background: Rectangle {
                            radius: 19
                            color: root.canShare ? "#FFFFFF" : "#A6FFFFFF"
                        }
                        contentItem: Text {
                            text: "Share"
                            color: brandRed
                            opacity: root.canShare ? 1.0 : 0.55
                            font.bold: true
                            font.pixelSize: 14
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        onClicked: {
                            var tagIds = []
                            for (var i = 0; i < root.taggedContacts.length; ++i) {
                                tagIds.push(root.taggedContacts[i].user_id)
                            }
                            telefam.submitPost(
                                root.postMode,
                                root.postMode === "text" ? root.textBody : root.captionBody,
                                root.selectedBgColorHex,
                                root.selectedImageThemeId,
                                root.selectedFontId,
                                root.selectedSong ? root.selectedSong.track_id : "",
                                root.selectedSong ? root.selectedSong.title : "",
                                root.selectedSong ? root.selectedSong.artist : "",
                                root.selectedSong ? root.selectedSong.preview_url : "",
                                root.muteOriginalAudio,
                                tagIds,
                                root.selectedHashtags
                            )
                        }
                    }
                }

                // Mode Tabs Row: Text | Photos | Video
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Repeater {
                        model: [
                            { key: "text", label: "Text", icon: "" },
                            { key: "photos", label: "Photos", icon: "qrc:/telefam/icons/ic_photos_tab.svg" },
                            { key: "video", label: "Video", icon: "qrc:/telefam/icons/ic_video_tab.svg" }
                        ]
                        delegate: Button {
                            readonly property bool selected: root.postMode === modelData.key
                            Layout.preferredHeight: 38
                            Layout.preferredWidth: tabRow.implicitWidth + 32
                            background: Rectangle {
                                radius: 19
                                color: selected ? "#FFFFFF" : "transparent"
                            }
                            contentItem: Row {
                                id: tabRow
                                anchors.centerIn: parent
                                spacing: 8
                                Text {
                                    visible: modelData.key === "text"
                                    text: "T"
                                    font.bold: true
                                    font.pixelSize: 16
                                    color: selected ? "#121316" : "#FFFFFF"
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Image {
                                    visible: modelData.icon.length > 0
                                    source: modelData.icon
                                    sourceSize.width: 17
                                    sourceSize.height: 17
                                    anchors.verticalCenter: parent.verticalCenter
                                    opacity: selected ? 0.9 : 1.0
                                }
                                Text {
                                    text: modelData.label
                                    color: selected ? "#121316" : "#FFFFFF"
                                    font.bold: true
                                    font.pixelSize: 14
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                            onClicked: root.postMode = modelData.key
                        }
                    }

                    Item { Layout.fillWidth: true }
                }

                // Clean Progress Header: Uploading XX% / Uploaded only
                RowLayout {
                    visible: telefam.postUploadStatus === "uploading" || telefam.postUploadStatus === "uploaded"
                    Layout.fillWidth: true
                    spacing: 12

                    Text {
                        text: telefam.postUploadStatus === "uploaded"
                            ? "Uploaded"
                            : ("Uploading " + telefam.postUploadProgress + "%")
                        color: "#FFFFFF"
                        font.bold: true
                        font.pixelSize: 13
                    }

                    ProgressBar {
                        visible: telefam.postUploadStatus === "uploading"
                        Layout.fillWidth: true
                        from: 0
                        to: 100
                        value: telefam.postUploadProgress
                    }
                }
            }
        }

        // Body Surface: 2-column responsive layout on wide desktops, stacked on compact windows
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: bodyBg

            ScrollView {
                anchors.fill: parent
                contentWidth: availableWidth

                GridLayout {
                    width: Math.min(parent.width, 1140)
                    anchors.horizontalCenter: parent.horizontalCenter
                    columns: root.width >= 760 ? 2 : 1
                    columnSpacing: 24
                    rowSpacing: 18

                    // LEFT / PRIMARY COLUMN
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.preferredWidth: root.width >= 760 ? 540 : parent.width - 32
                        Layout.margins: 18
                        Layout.alignment: Qt.AlignTop
                        spacing: 14

                        // TEXT COMPOSER CARD
                        Rectangle {
                            visible: root.postMode === "text"
                            Layout.fillWidth: true
                            Layout.preferredHeight: 310
                            radius: 20
                            color: root.selectedBgColorHex
                            clip: true

                            PostThemeCanvas {
                                visible: root.activeThemeObj !== null
                                anchors.fill: parent
                                themeId: root.activeThemeObj ? root.activeThemeObj.id : "aurora"
                                primaryColor: root.activeThemeObj ? root.activeThemeObj.primary : "#081C24"
                                secondaryColor: root.activeThemeObj ? root.activeThemeObj.secondary : "#10B981"
                                accentColor: root.activeThemeObj ? root.activeThemeObj.accent : "#38BDF8"
                            }

                            TextArea {
                                anchors.fill: parent
                                anchors.margins: 28
                                text: root.textBody
                                placeholderText: "What's on your mind?"
                                placeholderTextColor: Qt.rgba(textCardFg.r, textCardFg.g, textCardFg.b, 0.72)
                                color: root.textCardFg
                                font.family: root.activeFontObj.family
                                font.bold: root.activeFontObj.bold
                                font.italic: root.activeFontObj.italic
                                font.pixelSize: 24
                                horizontalAlignment: TextEdit.AlignHCenter
                                verticalAlignment: TextEdit.AlignVCenter
                                wrapMode: TextEdit.Wrap
                                background: Item {}
                                onTextChanged: {
                                    if (text.length > 280) text = text.slice(0, 280)
                                    root.textBody = text
                                }
                            }

                            Text {
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.margins: 16
                                text: root.textBody.length + "/280"
                                color: Qt.rgba(textCardFg.r, textCardFg.g, textCardFg.b, 0.78)
                                font.pixelSize: 13
                            }
                        }

                        // PHOTOS COMPOSER CARD
                        Rectangle {
                            visible: root.postMode === "photos"
                            Layout.fillWidth: true
                            Layout.preferredHeight: 300
                            radius: 20
                            color: cardBg
                            border.width: 1
                            border.color: borderCol

                            ColumnLayout {
                                visible: telefam.postPhotos.length === 0
                                anchors.centerIn: parent
                                spacing: 10
                                Rectangle {
                                    width: 58; height: 58; radius: 29
                                    color: telefam.isDarkTheme ? "#2C1618" : "#FCE8E8"
                                    Layout.alignment: Qt.AlignHCenter
                                    Image {
                                        anchors.centerIn: parent
                                        source: "qrc:/telefam/icons/ic_photos_tab.svg"
                                        sourceSize.width: 26; sourceSize.height: 26
                                    }
                                }
                                Text {
                                    text: "Add photos"
                                    color: inkCol
                                    font.bold: true
                                    font.pixelSize: 16
                                    Layout.alignment: Qt.AlignHCenter
                                }
                                Text {
                                    text: "Up to 10"
                                    color: subCol
                                    font.pixelSize: 13
                                    Layout.alignment: Qt.AlignHCenter
                                }
                            }

                            MouseArea {
                                visible: telefam.postPhotos.length === 0
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: photoDialog.open()
                            }

                            ListView {
                                visible: telefam.postPhotos.length > 0
                                anchors.fill: parent
                                anchors.margins: 12
                                orientation: ListView.Horizontal
                                spacing: 10
                                clip: true
                                model: telefam.postPhotos
                                delegate: Rectangle {
                                    width: 190; height: 270; radius: 14
                                    color: "#000000"
                                    clip: true
                                    Image {
                                        anchors.fill: parent
                                        source: modelData.previewDataUrl
                                        fillMode: Image.PreserveAspectCrop
                                    }
                                    Button {
                                        anchors.top: parent.top
                                        anchors.right: parent.right
                                        anchors.margins: 8
                                        width: 30; height: 30
                                        background: Rectangle { radius: 15; color: "#A6000000" }
                                        contentItem: Image {
                                            source: "qrc:/telefam/icons/ic_close_white.svg"
                                            sourceSize.width: 14; sourceSize.height: 14
                                            fillMode: Image.PreserveAspectFit
                                        }
                                        onClicked: telefam.removePostPhoto(index)
                                    }
                                }
                                footer: Item {
                                    width: telefam.postPhotos.length < 10 ? 120 : 0
                                    height: 270
                                    visible: telefam.postPhotos.length < 10
                                    Rectangle {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        radius: 14
                                        color: bodyBg
                                        border.width: 1; border.color: borderCol
                                        Column {
                                            anchors.centerIn: parent
                                            spacing: 6
                                            Text { text: "+"; font.pixelSize: 28; color: brandRed; anchors.horizontalCenter: parent.horizontalCenter }
                                            Text { text: telefam.postPhotos.length + "/10"; font.pixelSize: 12; color: subCol }
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: photoDialog.open()
                                        }
                                    }
                                }
                            }
                        }

                        // VIDEO COMPOSER CARD
                        ColumnLayout {
                            visible: root.postMode === "video"
                            Layout.fillWidth: true
                            spacing: 12

                            Rectangle {
                                visible: telefam.postVideoPath.length === 0
                                Layout.fillWidth: true
                                Layout.preferredHeight: 300
                                radius: 20
                                color: cardBg
                                border.width: 1; border.color: borderCol

                                ColumnLayout {
                                    anchors.centerIn: parent
                                    spacing: 10
                                    Rectangle {
                                        width: 58; height: 58; radius: 29
                                        color: telefam.isDarkTheme ? "#2C1618" : "#FCE8E8"
                                        Layout.alignment: Qt.AlignHCenter
                                        Image {
                                            anchors.centerIn: parent
                                            source: "qrc:/telefam/icons/ic_clapperboard.svg"
                                            sourceSize.width: 26; sourceSize.height: 26
                                        }
                                    }
                                    Text {
                                        text: "Add video"
                                        color: inkCol
                                        font.bold: true
                                        font.pixelSize: 16
                                        Layout.alignment: Qt.AlignHCenter
                                    }
                                    Text {
                                        text: telefam.postErrorMessage.length > 0 ? telefam.postErrorMessage : "Up to 200 MB"
                                        color: telefam.postErrorMessage.length > 0 ? brandRed : subCol
                                        font.pixelSize: 13
                                        Layout.alignment: Qt.AlignHCenter
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: videoDialog.open()
                                }
                            }

                            // Selected Video Thumbnail Preview + Frames + Trim
                            Rectangle {
                                visible: telefam.postVideoPath.length > 0
                                Layout.fillWidth: true
                                Layout.preferredHeight: 240
                                radius: 18
                                color: "#000000"
                                clip: true

                                Image {
                                    anchors.fill: parent
                                    visible: telefam.postSelectedThumbIndex >= 0 && telefam.postSelectedThumbIndex < telefam.postVideoFrames.length
                                    source: (telefam.postSelectedThumbIndex >= 0 && telefam.postSelectedThumbIndex < telefam.postVideoFrames.length)
                                        ? telefam.postVideoFrames[telefam.postSelectedThumbIndex].previewDataUrl : ""
                                    fillMode: Image.PreserveAspectCrop
                                }

                                Row {
                                    anchors.top: parent.top
                                    anchors.right: parent.right
                                    anchors.margins: 10
                                    spacing: 8

                                    Button {
                                        height: 32
                                        width: autoRow.implicitWidth + 20
                                        background: Rectangle { radius: 16; color: "#A6000000" }
                                        contentItem: Row {
                                            id: autoRow
                                            anchors.centerIn: parent
                                            spacing: 5
                                            Image { source: "qrc:/telefam/icons/ic_sparkle.svg"; sourceSize.width: 13; sourceSize.height: 13; anchors.verticalCenter: parent.verticalCenter }
                                            Text { text: "Auto"; color: "#FFFFFF"; font.bold: true; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
                                        }
                                        onClicked: telefam.autoSelectPostVideoThumb()
                                    }

                                    Button {
                                        width: 32; height: 32
                                        background: Rectangle { radius: 16; color: "#A6000000" }
                                        contentItem: Image { source: "qrc:/telefam/icons/ic_close_white.svg"; sourceSize.width: 15; sourceSize.height: 15; fillMode: Image.PreserveAspectFit }
                                        onClicked: telefam.clearPostVideo()
                                    }
                                }

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.bottom: parent.bottom
                                    anchors.margins: 10
                                    radius: 10
                                    color: "#A6000000"
                                    width: durText.implicitWidth + 18
                                    height: 26
                                    Text {
                                        id: durText
                                        anchors.centerIn: parent
                                        color: "#FFFFFF"
                                        font.pixelSize: 12
                                        text: root.formatMs(telefam.postTrimStartMs) + " – " + root.formatMs(telefam.postTrimEndMs)
                                    }
                                }
                            }

                            ListView {
                                visible: telefam.postVideoPath.length > 0 && telefam.postVideoFrames.length > 0
                                Layout.fillWidth: true
                                Layout.preferredHeight: 56
                                orientation: ListView.Horizontal
                                spacing: 4
                                clip: true
                                model: telefam.postVideoFrames
                                delegate: Rectangle {
                                    width: 66; height: 54; radius: 8
                                    border.width: index === telefam.postSelectedThumbIndex ? 2.5 : 1
                                    border.color: index === telefam.postSelectedThumbIndex ? brandRed : borderCol
                                    clip: true
                                    Image { anchors.fill: parent; source: modelData.previewDataUrl; fillMode: Image.PreserveAspectCrop }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: telefam.selectPostVideoThumb(index)
                                    }
                                }
                            }

                            RangeSlider {
                                visible: telefam.postVideoPath.length > 0 && telefam.postVideoDurationMs > 500
                                Layout.fillWidth: true
                                from: 0
                                to: Math.max(1000, telefam.postVideoDurationMs)
                                first.value: telefam.postTrimStartMs
                                second.value: telefam.postTrimEndMs
                                first.onMoved: telefam.updatePostVideoTrim(Math.round(first.value), telefam.postTrimEndMs)
                                second.onMoved: telefam.updatePostVideoTrim(telefam.postTrimStartMs, Math.round(second.value))
                            }

                            Rectangle {
                                visible: telefam.postVideoPath.length > 0
                                Layout.fillWidth: true
                                Layout.preferredHeight: 48
                                radius: 14
                                color: cardBg
                                border.width: 1; border.color: borderCol
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 14
                                    anchors.rightMargin: 10
                                    spacing: 10
                                    Image {
                                        source: root.muteOriginalAudio ? "qrc:/telefam/icons/ic_volume_off.svg" : "qrc:/telefam/icons/ic_volume_on.svg"
                                        sourceSize.width: 18; sourceSize.height: 18
                                    }
                                    Text {
                                        text: "Mute audio"
                                        color: inkCol
                                        font.pixelSize: 14
                                        Layout.fillWidth: true
                                    }
                                    Switch {
                                        checked: root.muteOriginalAudio
                                        onToggled: root.muteOriginalAudio = checked
                                    }
                                }
                            }
                        }
                    }

                    // RIGHT / SECONDARY CONTROLS COLUMN
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.preferredWidth: root.width >= 760 ? 500 : parent.width - 32
                        Layout.margins: 18
                        Layout.alignment: Qt.AlignTop
                        spacing: 14

                        // Colors / Image Themes + 12 Fonts when Text mode
                        ColumnLayout {
                            visible: root.postMode === "text"
                            Layout.fillWidth: true
                            spacing: 14

                            RowLayout {
                                spacing: 8
                                Button {
                                    Layout.preferredHeight: 34
                                    Layout.preferredWidth: colTabRow.implicitWidth + 24
                                    background: Rectangle {
                                        radius: 17
                                        color: !root.showImageThemes ? "#24C81010" : cardBg
                                        border.width: 1
                                        border.color: !root.showImageThemes ? brandRed : borderCol
                                    }
                                    contentItem: Row {
                                        id: colTabRow
                                        anchors.centerIn: parent
                                        spacing: 6
                                        Image { source: "qrc:/telefam/icons/ic_palette.svg"; sourceSize.width: 15; sourceSize.height: 15; anchors.verticalCenter: parent.verticalCenter }
                                        Text { text: "Colors"; color: !root.showImageThemes ? brandRed : subCol; font.bold: true; font.pixelSize: 13; anchors.verticalCenter: parent.verticalCenter }
                                    }
                                    onClicked: root.showImageThemes = false
                                }
                                Button {
                                    Layout.preferredHeight: 34
                                    Layout.preferredWidth: thTabRow.implicitWidth + 24
                                    background: Rectangle {
                                        radius: 17
                                        color: root.showImageThemes ? "#24C81010" : cardBg
                                        border.width: 1
                                        border.color: root.showImageThemes ? brandRed : borderCol
                                    }
                                    contentItem: Row {
                                        id: thTabRow
                                        anchors.centerIn: parent
                                        spacing: 6
                                        Image { source: "qrc:/telefam/icons/ic_image_theme.svg"; sourceSize.width: 15; sourceSize.height: 15; anchors.verticalCenter: parent.verticalCenter }
                                        Text { text: "Themes"; color: root.showImageThemes ? brandRed : subCol; font.bold: true; font.pixelSize: 13; anchors.verticalCenter: parent.verticalCenter }
                                    }
                                    onClicked: root.showImageThemes = true
                                }
                            }

                            ListView {
                                visible: !root.showImageThemes
                                Layout.fillWidth: true
                                Layout.preferredHeight: 46
                                orientation: ListView.Horizontal
                                spacing: 10
                                clip: true
                                model: root.bgColors
                                delegate: Rectangle {
                                    readonly property bool sel: root.selectedImageThemeId.length === 0 && root.selectedBgColorHex === modelData.hex
                                    width: 44; height: 44; radius: 22
                                    color: modelData.hex
                                    border.width: sel ? 2.5 : 1
                                    border.color: sel ? "#FFFFFF" : borderCol
                                    Image {
                                        visible: sel
                                        anchors.centerIn: parent
                                        source: "qrc:/telefam/icons/ic_check.svg"
                                        sourceSize.width: 16; sourceSize.height: 16
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.selectedBgColorHex = modelData.hex
                                            root.selectedImageThemeId = ""
                                        }
                                    }
                                }
                            }

                            ListView {
                                visible: root.showImageThemes
                                Layout.fillWidth: true
                                Layout.preferredHeight: 50
                                orientation: ListView.Horizontal
                                spacing: 10
                                clip: true
                                model: root.imageThemes
                                delegate: Rectangle {
                                    readonly property bool sel: root.selectedImageThemeId === modelData.id
                                    width: 48; height: 48; radius: 24
                                    border.width: sel ? 2.5 : 1
                                    border.color: sel ? "#FFFFFF" : borderCol
                                    clip: true
                                    PostThemeCanvas {
                                        anchors.fill: parent
                                        themeId: modelData.id
                                        primaryColor: modelData.primary
                                        secondaryColor: modelData.secondary
                                        accentColor: modelData.accent
                                    }
                                    Image {
                                        visible: sel
                                        anchors.centerIn: parent
                                        source: "qrc:/telefam/icons/ic_check.svg"
                                        sourceSize.width: 16; sourceSize.height: 16
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.selectedImageThemeId = modelData.id
                                    }
                                }
                            }

                            Flow {
                                Layout.fillWidth: true
                                spacing: 10
                                Repeater {
                                    model: root.fontStyles
                                    delegate: Button {
                                        readonly property bool sel: root.selectedFontId === modelData.id
                                        height: 38
                                        width: fontRow.implicitWidth + 24
                                        background: Rectangle {
                                            radius: 10
                                            color: sel ? "#24C81010" : cardBg
                                            border.width: 1
                                            border.color: sel ? brandRed : borderCol
                                        }
                                        contentItem: Row {
                                            id: fontRow
                                            anchors.centerIn: parent
                                            spacing: 6
                                            Text {
                                                text: modelData.badge
                                                font.family: modelData.family
                                                font.bold: modelData.bold
                                                font.italic: modelData.italic
                                                font.pixelSize: 13
                                                color: sel ? brandRed : inkCol
                                            }
                                            Text {
                                                text: modelData.label
                                                font.pixelSize: 13
                                                color: sel ? brandRed : inkCol
                                            }
                                        }
                                        onClicked: root.selectedFontId = modelData.id
                                    }
                                }
                            }
                        }

                        // CAPTION CARD (Photos / Video)
                        Rectangle {
                            visible: root.postMode !== "text"
                            Layout.fillWidth: true
                            Layout.preferredHeight: 120
                            radius: 16
                            color: cardBg
                            border.width: 1; border.color: borderCol

                            TextArea {
                                anchors.fill: parent
                                anchors.margins: 12
                                anchors.bottomMargin: 28
                                text: root.captionBody
                                placeholderText: "Write a caption..."
                                placeholderTextColor: subCol
                                color: inkCol
                                font.pixelSize: 15
                                wrapMode: TextEdit.Wrap
                                background: Item {}
                                onTextChanged: {
                                    if (text.length > 2200) text = text.slice(0, 2200)
                                    root.captionBody = text
                                }
                            }

                            Text {
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.margins: 12
                                text: root.captionBody.length + "/2200"
                                color: subCol
                                font.pixelSize: 12
                            }
                        }

                        // OPTIONS CARD: Song | Tag people | Hashtags
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: root.postMode === "text" ? 110 : 165
                            radius: 16
                            color: cardBg
                            border.width: 1; border.color: borderCol

                            ColumnLayout {
                                anchors.fill: parent
                                spacing: 0

                                // Song Row
                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 54
                                    Layout.leftMargin: 14
                                    Layout.rightMargin: 14
                                    spacing: 12

                                    Rectangle {
                                        width: 34; height: 34; radius: 17
                                        color: telefam.isDarkTheme ? "#2C1618" : "#FCE8E8"
                                        Image { anchors.centerIn: parent; source: "qrc:/telefam/icons/ic_music_note.svg"; sourceSize.width: 17; sourceSize.height: 17 }
                                    }
                                    Text {
                                        text: root.selectedSong ? root.selectedSong.title : "Song"
                                        color: inkCol
                                        font.bold: true
                                        font.pixelSize: 15
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                    Button {
                                        visible: root.selectedSong !== null && root.selectedSong.preview_url.length > 0
                                        Layout.preferredWidth: 34; Layout.preferredHeight: 34
                                        background: Rectangle { radius: 17; color: brandRed }
                                        contentItem: Image {
                                            source: (root.selectedSong && telefam.postPlayingPreviewTrackId === root.selectedSong.track_id)
                                                ? "qrc:/telefam/icons/ic_pause.svg" : "qrc:/telefam/icons/ic_play.svg"
                                            sourceSize.width: 14; sourceSize.height: 14
                                            fillMode: Image.PreserveAspectFit
                                        }
                                        onClicked: if (root.selectedSong) telefam.toggleSongPreview(root.selectedSong.track_id, root.selectedSong.preview_url)
                                    }
                                    Row {
                                        visible: root.selectedSong === null
                                        spacing: 4
                                        Text { text: "Add"; color: subCol; font.pixelSize: 14; anchors.verticalCenter: parent.verticalCenter }
                                        Image { source: "qrc:/telefam/icons/ic_chevron_right.svg"; sourceSize.width: 15; sourceSize.height: 15; anchors.verticalCenter: parent.verticalCenter }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        anchors.rightMargin: (root.selectedSong && root.selectedSong.preview_url.length > 0) ? 46 : 0
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: songDialog.open()
                                    }
                                }

                                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: borderCol }

                                // Tag people Row
                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 54
                                    Layout.leftMargin: 14
                                    Layout.rightMargin: 14
                                    spacing: 12

                                    Rectangle {
                                        width: 34; height: 34; radius: 17
                                        color: telefam.isDarkTheme ? "#2C1618" : "#FCE8E8"
                                        Image { anchors.centerIn: parent; source: "qrc:/telefam/icons/ic_contacts_red.svg"; sourceSize.width: 17; sourceSize.height: 17 }
                                    }
                                    Text {
                                        text: "Tag people"
                                        color: inkCol
                                        font.bold: true
                                        font.pixelSize: 15
                                        Layout.fillWidth: true
                                    }
                                    Text {
                                        text: root.taggedContacts.length === 0 ? "Add" : String(root.taggedContacts.length)
                                        color: subCol
                                        font.pixelSize: 14
                                    }
                                    Image { source: "qrc:/telefam/icons/ic_chevron_right.svg"; sourceSize.width: 15; sourceSize.height: 15 }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: tagDialog.open()
                                    }
                                }

                                Rectangle { visible: root.postMode !== "text"; Layout.fillWidth: true; Layout.preferredHeight: 1; color: borderCol }

                                // Hashtags Row
                                RowLayout {
                                    visible: root.postMode !== "text"
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 54
                                    Layout.leftMargin: 14
                                    Layout.rightMargin: 14
                                    spacing: 12

                                    Rectangle {
                                        width: 34; height: 34; radius: 17
                                        color: telefam.isDarkTheme ? "#2C1618" : "#FCE8E8"
                                        Image { anchors.centerIn: parent; source: "qrc:/telefam/icons/ic_hashtag.svg"; sourceSize.width: 17; sourceSize.height: 17 }
                                    }
                                    Text {
                                        text: "Hashtags"
                                        color: inkCol
                                        font.bold: true
                                        font.pixelSize: 15
                                        Layout.fillWidth: true
                                    }
                                    Text {
                                        text: root.selectedHashtags.length === 0 ? "Add" : String(root.selectedHashtags.length)
                                        color: subCol
                                        font.pixelSize: 14
                                    }
                                    Image { source: "qrc:/telefam/icons/ic_chevron_right.svg"; sourceSize.width: 15; sourceSize.height: 15 }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: hashtagDialog.open()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    FileDialog {
        id: photoDialog
        title: "Select up to 10 photos"
        fileMode: FileDialog.OpenFiles
        nameFilters: ["Images (*.png *.jpg *.jpeg *.webp)"]
        onAccepted: telefam.addPostPhotos(selectedFiles)
    }

    FileDialog {
        id: videoDialog
        title: "Select video (Up to 200 MB)"
        fileMode: FileDialog.OpenFile
        nameFilters: ["Videos (*.mp4 *.mov *.mkv *.webm *.avi)"]
        onAccepted: telefam.selectPostVideo(selectedFile)
    }

    // SONG PICKER DIALOG
    Dialog {
        id: songDialog
        title: "Song"
        modal: true
        anchors.centerIn: parent
        width: 440
        height: 480
        standardButtons: Dialog.Close

        ColumnLayout {
            anchors.fill: parent
            spacing: 10
            RowLayout {
                Layout.fillWidth: true
                TextField {
                    Layout.fillWidth: true
                    placeholderText: "Search songs or artists"
                    onTextEdited: telefam.searchMusic(text)
                }
                Button {
                    visible: root.selectedSong !== null
                    text: "Clear"
                    onClicked: {
                        telefam.stopAudioPreview()
                        root.selectedSong = null
                        songDialog.close()
                    }
                }
            }
            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: telefam.postMusicResults
                spacing: 6
                delegate: Rectangle {
                    width: ListView.view.width
                    height: 58
                    radius: 10
                    color: (root.selectedSong && root.selectedSong.track_id === modelData.track_id) ? "#22C81010" : cardBg
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 10
                        Column {
                            Layout.fillWidth: true
                            Text { text: modelData.title; color: inkCol; font.bold: true; elide: Text.ElideRight; width: parent.width }
                            Text { text: modelData.artist + " · " + modelData.duration_sec + "s"; color: subCol; font.pixelSize: 12 }
                        }
                        Button {
                            visible: modelData.preview_url && modelData.preview_url.length > 0
                            Layout.preferredWidth: 36; Layout.preferredHeight: 36
                            background: Rectangle { radius: 18; color: brandRed }
                            contentItem: Image {
                                source: telefam.postPlayingPreviewTrackId === modelData.track_id
                                    ? "qrc:/telefam/icons/ic_pause.svg" : "qrc:/telefam/icons/ic_play.svg"
                                sourceSize.width: 15; sourceSize.height: 15
                                fillMode: Image.PreserveAspectFit
                            }
                            onClicked: telefam.toggleSongPreview(modelData.track_id, modelData.preview_url)
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        anchors.rightMargin: 48
                        onClicked: {
                            telefam.stopAudioPreview()
                            root.selectedSong = modelData
                            songDialog.close()
                        }
                    }
                }
            }
        }
    }

    // TAG PEOPLE DIALOG
    Dialog {
        id: tagDialog
        title: "Tag people"
        modal: true
        anchors.centerIn: parent
        width: 420
        height: 460
        standardButtons: Dialog.Ok

        ColumnLayout {
            anchors.fill: parent
            spacing: 10
            TextField {
                id: tagQueryField
                Layout.fillWidth: true
                placeholderText: "Search people"
            }
            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: telefam.contacts
                spacing: 4
                delegate: Rectangle {
                    readonly property bool match: tagQueryField.text.length === 0 ||
                        modelData.full_name.toLowerCase().indexOf(tagQueryField.text.toLowerCase()) >= 0 ||
                        modelData.username.toLowerCase().indexOf(tagQueryField.text.toLowerCase()) >= 0
                    visible: match
                    width: ListView.view.width
                    height: match ? 52 : 0
                    radius: 10
                    color: root.isContactTagged(modelData.user_id) ? "#22C81010" : cardBg
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        Column {
                            Layout.fillWidth: true
                            Text { text: modelData.full_name; color: inkCol; font.bold: true }
                            Text { text: "@" + modelData.username; color: subCol; font.pixelSize: 12 }
                        }
                        Rectangle {
                            visible: root.isContactTagged(modelData.user_id)
                            width: 24; height: 24; radius: 12; color: brandRed
                            Image { anchors.centerIn: parent; source: "qrc:/telefam/icons/ic_check.svg"; sourceSize.width: 13; sourceSize.height: 13 }
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.toggleContactTag(modelData)
                    }
                }
            }
        }
    }

    // HASHTAGS PICKER DIALOG
    Dialog {
        id: hashtagDialog
        title: "Hashtags"
        modal: true
        anchors.centerIn: parent
        width: 420
        height: 480
        standardButtons: Dialog.Ok

        ColumnLayout {
            anchors.fill: parent
            spacing: 10

            Flow {
                visible: root.selectedHashtags.length > 0
                Layout.fillWidth: true
                spacing: 8
                Repeater {
                    model: root.selectedHashtags
                    delegate: Button {
                        text: "#" + modelData + " ×"
                        onClicked: root.toggleHashtagItem(modelData)
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                TextField {
                    id: hashQueryField
                    Layout.fillWidth: true
                    placeholderText: "Search hashtags"
                    onTextEdited: telefam.searchHashtags(text)
                }
                Button {
                    visible: hashQueryField.text.trim().length > 0
                    text: "Add"
                    onClicked: {
                        root.toggleHashtagItem(hashQueryField.text)
                        hashQueryField.text = ""
                    }
                }
            }

            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: telefam.postHashtagResults
                spacing: 4
                delegate: Rectangle {
                    readonly property bool active: root.selectedHashtags.indexOf(modelData.tag) >= 0
                    width: ListView.view.width
                    height: 46
                    radius: 8
                    color: active ? "#22C81010" : "transparent"
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        Text { text: "#" + modelData.tag; color: active ? brandRed : inkCol; font.bold: true; Layout.fillWidth: true }
                        Text { text: modelData.post_count + " posts"; color: subCol; font.pixelSize: 12 }
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.toggleHashtagItem(modelData.tag)
                    }
                }
            }
        }
    }
}
