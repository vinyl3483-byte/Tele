import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts

Item {
    id: ownerRoot

    readonly property color brandRed: "#C81010"
    readonly property color brandRedDeep: "#9B0A0A"
    readonly property color bodyBg: telefam.isDarkTheme ? "#121316" : "#FFFFFF"
    readonly property color cardBg: telefam.isDarkTheme ? "#1B1D22" : "#FFFFFF"
    readonly property color subtleBg: telefam.isDarkTheme ? "#22252C" : "#F3F4F6"
    readonly property color borderCol: telefam.isDarkTheme ? "#2B2F38" : "#E5E7EB"
    readonly property color inkCol: telefam.isDarkTheme ? "#FFFFFF" : "#111827"
    readonly property color subCol: telefam.isDarkTheme ? "#9CA3AF" : "#6B7280"

    property int bgSlideIndex: 0
    property url pendingAvatarUrl: ""
    property bool armedPullRefresh: false
    property int viewerPhotoIndex: 0
    property string comingSoonTitle: "Coming Soon"

    readonly property var slideList: telefam.ownerBackgroundSlides || []
    readonly property string fullNameVal: (telefam.myProfile.full_name || telefam.profileFullName || "Telefam User")
    readonly property string usernameVal: (telefam.myProfile.username || telefam.profileUsername || "")
    readonly property string bioVal: (telefam.myProfile.bio || "")
    readonly property string locationVal: (telefam.myProfile.location || telefam.profileLocation || "")

    function computeInitials(name) {
        if (!name) return "TF"
        var parts = name.trim().split(/\s+/).filter(function(p) { return p.length > 0 })
        if (parts.length >= 2) return (parts[0][0] + parts[1][0]).toUpperCase()
        if (parts.length === 1) return parts[0].substring(0, 2).toUpperCase()
        return "TF"
    }

    onSlideListChanged: {
        if (slideList.length === 0) {
            bgSlideIndex = 0
        } else if (bgSlideIndex >= slideList.length) {
            bgSlideIndex = 0
        }
    }

    Connections {
        target: telefam
        function onOwnerProfileChanged() {
            viewerPhotoIndex = 0
        }
    }

    Timer {
        id: bgSlideshowTimer
        interval: 5000
        repeat: true
        running: ownerRoot.visible && ownerRoot.slideList.length > 1
        onTriggered: {
            if (ownerRoot.slideList.length > 1) {
                ownerRoot.bgSlideIndex = (ownerRoot.bgSlideIndex + 1) % ownerRoot.slideList.length
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: bodyBg
    }

    Flickable {
        id: profileFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: mainColumn.implicitHeight + 48
        clip: true
        boundsBehavior: Flickable.DragAndOverscrollBounds
        flickableDirection: Flickable.VerticalFlick

        readonly property real scrollOffset: Math.max(0, contentY)
        readonly property real collapseProgress: Math.min(1.0, scrollOffset / 180.0)

        onContentYChanged: {
            if (dragging && contentY < -58) {
                ownerRoot.armedPullRefresh = true
            }
        }

        onDraggingChanged: {
            if (!dragging && ownerRoot.armedPullRefresh) {
                ownerRoot.armedPullRefresh = false
                telefam.refreshOwnerProfile(true)
            }
        }

        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
        }

        Column {
            id: mainColumn
            width: profileFlick.width
            spacing: 0

            // Top Cover Hero with 5-photo Crossfade Slideshow, Crimson Wave, Arched Cutout & Change Background
            Item {
                id: heroContainer
                width: parent.width
                readonly property real baseCoverHeight: 280
                height: Math.max(150, baseCoverHeight - profileFlick.collapseProgress * 95)
                clip: true

                // Fallback scenic gradient if user hasn't uploaded backgrounds yet
                Rectangle {
                    anchors.fill: parent
                    visible: ownerRoot.slideList.length === 0
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "#521426" }
                        GradientStop { position: 0.55; color: "#9E2A2B" }
                        GradientStop { position: 1.0; color: "#1A2238" }
                    }

                    // Subtle mountain & sun ambient highlights when no background uploaded
                    Canvas {
                        anchors.fill: parent
                        opacity: 0.45
                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.clearRect(0, 0, width, height)
                            var grad = ctx.createRadialGradient(width * 0.36, height * 0.54, 10, width * 0.36, height * 0.54, width * 0.45)
                            grad.addColorStop(0.0, "rgba(255, 200, 90, 0.78)")
                            grad.addColorStop(0.45, "rgba(245, 110, 60, 0.32)")
                            grad.addColorStop(1.0, "rgba(0, 0, 0, 0)")
                            ctx.fillStyle = grad
                            ctx.fillRect(0, 0, width, height)
                        }
                        onWidthChanged: requestPaint()
                        onHeightChanged: requestPaint()
                    }
                }

                // Up to 5 Background Photos with 5s Animated Crossfade
                Repeater {
                    model: ownerRoot.slideList
                    delegate: Image {
                        anchors.fill: parent
                        source: modelData.url || ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: false
                        opacity: index === ownerRoot.bgSlideIndex ? 1.0 : 0.0
                        y: -profileFlick.scrollOffset * 0.18
                        Behavior on opacity {
                            NumberAnimation {
                                duration: 900
                                easing.type: Easing.InOutQuad
                            }
                        }
                    }
                }

                // Subtle bottom dark scrim so Change Background stays legible
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 92
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 1.0; color: "#70000000" }
                    }
                }

                // Top Layered Crimson Wave matching reference image
                Canvas {
                    id: topWaveCanvas
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 68
                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)

                        // Back lighter crimson wave
                        ctx.beginPath()
                        ctx.moveTo(0, 0)
                        ctx.lineTo(width, 0)
                        ctx.lineTo(width, height * 0.48)
                        ctx.bezierCurveTo(width * 0.72, height * 0.92, width * 0.42, height * 0.14, 0, height * 0.78)
                        ctx.closePath()
                        ctx.fillStyle = "#E01B1B"
                        ctx.fill()

                        // Front primary crimson wave
                        ctx.beginPath()
                        ctx.moveTo(0, 0)
                        ctx.lineTo(width, 0)
                        ctx.lineTo(width, height * 0.66)
                        ctx.bezierCurveTo(width * 0.68, height * 0.16, width * 0.34, height * 1.02, 0, height * 0.46)
                        ctx.closePath()
                        ctx.fillStyle = "#C81010"
                        ctx.fill()
                    }
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()
                }

                // Arched Surface Cutout at bottom of Cover Banner
                Canvas {
                    id: archCutoutCanvas
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 36
                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)
                        ctx.beginPath()
                        ctx.moveTo(0, height)
                        ctx.lineTo(0, height * 0.42)
                        ctx.quadraticCurveTo(width * 0.48, -height * 0.22, width, height * 0.68)
                        ctx.lineTo(width, height)
                        ctx.closePath()
                        ctx.fillStyle = ownerRoot.bodyBg
                        ctx.fill()
                    }
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()
                    Connections {
                        target: telefam
                        function onThemeChanged() { archCutoutCanvas.requestPaint() }
                    }
                }

                // Top-right 3-Dash Menu Button (Coming Soon)
                Button {
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.topMargin: 14
                    anchors.rightMargin: 20
                    width: 48
                    height: 48
                    hoverEnabled: true
                    ToolTip.visible: hovered
                    ToolTip.text: "Menu"
                    background: Rectangle {
                        radius: 24
                        color: parent.hovered ? "#44000000" : "#26000000"
                    }
                    contentItem: Image {
                        anchors.centerIn: parent
                        source: "qrc:/telefam/icons/ic_menu_dashes.svg"
                        sourceSize.width: 22
                        sourceSize.height: 22
                        fillMode: Image.PreserveAspectFit
                    }
                    onClicked: {
                        ownerRoot.comingSoonTitle = "Menu"
                        comingSoonDialog.open()
                    }
                }

                // Slide dot indicators when > 1 background uploaded
                Row {
                    visible: ownerRoot.slideList.length > 1
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 32
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 6
                    Repeater {
                        model: ownerRoot.slideList.length
                        delegate: Rectangle {
                            width: index === ownerRoot.bgSlideIndex ? 18 : 6
                            height: 6
                            radius: 3
                            color: index === ownerRoot.bgSlideIndex ? "#FFFFFF" : "#80FFFFFF"
                            Behavior on width { NumberAnimation { duration: 220 } }
                        }
                    }
                }

                // Translucent "Change Background" Pill bottom-right
                Button {
                    id: changeBgBtn
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.rightMargin: Math.max(20, (parent.width - Math.min(parent.width, 1020)) / 2 + 20)
                    anchors.bottomMargin: 28
                    height: 44
                    width: bgBtnRow.implicitWidth + 28
                    hoverEnabled: true
                    enabled: !telefam.ownerUploadingBackgrounds
                    opacity: 1.0 - profileFlick.collapseProgress * 0.85
                    visible: opacity > 0.1

                    background: Rectangle {
                        radius: 14
                        color: changeBgBtn.hovered ? "#B811151B" : "#9611151B"
                        border.width: 1
                        border.color: "#36FFFFFF"
                    }

                    contentItem: Row {
                        id: bgBtnRow
                        anchors.centerIn: parent
                        spacing: 9

                        BusyIndicator {
                            visible: telefam.ownerUploadingBackgrounds
                            running: telefam.ownerUploadingBackgrounds
                            width: 18
                            height: 18
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Image {
                            visible: !telefam.ownerUploadingBackgrounds
                            source: "qrc:/telefam/icons/ic_camera.svg"
                            sourceSize.width: 20
                            sourceSize.height: 20
                            fillMode: Image.PreserveAspectFit
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 0
                            Text {
                                text: "Change"
                                color: "#FFFFFF"
                                font.pixelSize: 11
                                font.bold: true
                            }
                            Text {
                                text: ownerRoot.slideList.length > 0
                                      ? ("Background (" + ownerRoot.slideList.length + "/5)")
                                      : "Background"
                                color: "#F3F4F6"
                                font.pixelSize: 11
                                font.bold: true
                            }
                        }
                    }

                    onClicked: {
                        if (ownerRoot.slideList.length === 0) {
                            bgFileDialog.open()
                        } else {
                            backgroundManagerDialog.open()
                        }
                    }
                }
            }

            // Pull-to-refresh status indicator pill
            Rectangle {
                visible: telefam.ownerRefreshing || ownerRoot.armedPullRefresh
                anchors.horizontalCenter: parent.horizontalCenter
                width: refreshRow.implicitWidth + 28
                height: 32
                radius: 16
                color: cardBg
                border.color: borderCol
                border.width: 1
                Row {
                    id: refreshRow
                    anchors.centerIn: parent
                    spacing: 8
                    BusyIndicator {
                        running: true
                        width: 16
                        height: 16
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: telefam.ownerRefreshing ? "Refreshing..." : "Release to refresh"
                        color: inkCol
                        font.pixelSize: 12
                        font.bold: true
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            // Centered Desktop-Adapted Profile Body Container
            Column {
                id: contentSheet
                width: Math.min(parent.width - 40, 980)
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 14

                // Overlapping Avatar + Edit Profile & Settings Row
                Item {
                    width: parent.width
                    height: 74

                    // Circular Avatar overlapping cover banner seam
                    Item {
                        id: avatarGroup
                        readonly property real avatarScale: 1.0 - profileFlick.collapseProgress * 0.25
                        width: 132
                        height: 132
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        transform: Scale {
                            origin.x: 66
                            origin.y: 132
                            xScale: avatarGroup.avatarScale
                            yScale: avatarGroup.avatarScale
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: 66
                            color: bodyBg
                        }

                        Rectangle {
                            id: avatarClip
                            anchors.fill: parent
                            anchors.margins: 4
                            radius: 62
                            color: telefam.isDarkTheme ? "#2B1517" : "#FCE8E8"
                            clip: true

                            Image {
                                anchors.fill: parent
                                visible: telefam.ownerLocalAvatarUrl.length > 0
                                source: telefam.ownerLocalAvatarUrl
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: false
                            }

                            Text {
                                visible: telefam.ownerLocalAvatarUrl.length === 0
                                anchors.centerIn: parent
                                text: ownerRoot.computeInitials(ownerRoot.fullNameVal)
                                color: brandRed
                                font.bold: true
                                font.pixelSize: 34
                            }
                        }

                        // Camera badge on Avatar bottom-right
                        Button {
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.rightMargin: 2
                            anchors.bottomMargin: 2
                            width: 40
                            height: 40
                            hoverEnabled: true
                            ToolTip.visible: hovered
                            ToolTip.text: "Update profile photo"
                            background: Rectangle {
                                radius: 20
                                color: cardBg
                                border.width: 2
                                border.color: bodyBg
                            }
                            contentItem: Canvas {
                                id: avatarCamCanvas
                                anchors.centerIn: parent
                                width: 18
                                height: 18
                                onPaint: {
                                    var ctx = getContext("2d")
                                    ctx.clearRect(0, 0, width, height)
                                    ctx.fillStyle = ownerRoot.inkCol
                                    ctx.beginPath()
                                    ctx.roundedRect(1.5, 4.5, 15, 11, 2.5, 2.5)
                                    ctx.fill()
                                    ctx.beginPath()
                                    ctx.moveTo(5.5, 4.5)
                                    ctx.lineTo(7, 2)
                                    ctx.lineTo(11, 2)
                                    ctx.lineTo(12.5, 4.5)
                                    ctx.closePath()
                                    ctx.fill()
                                    ctx.fillStyle = ownerRoot.cardBg
                                    ctx.beginPath()
                                    ctx.arc(9, 10, 3, 0, Math.PI * 2)
                                    ctx.fill()
                                }
                                Connections {
                                    target: telefam
                                    function onThemeChanged() { avatarCamCanvas.requestPaint() }
                                }
                            }
                            onClicked: avatarFileDialog.open()
                        }
                    }

                    // Action Buttons Row (Edit Profile + Settings)
                    Row {
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 8
                        spacing: 10

                        Button {
                            id: editProfileBtn
                            height: 44
                            width: editBtnRow.implicitWidth + 32
                            hoverEnabled: true
                            background: Rectangle {
                                radius: 22
                                color: editProfileBtn.hovered ? subtleBg : cardBg
                                border.width: 1
                                border.color: borderCol
                            }
                            contentItem: Row {
                                id: editBtnRow
                                anchors.centerIn: parent
                                spacing: 8
                                Canvas {
                                    id: editIconCanvas
                                    width: 16
                                    height: 16
                                    anchors.verticalCenter: parent.verticalCenter
                                    onPaint: {
                                        var ctx = getContext("2d")
                                        ctx.clearRect(0, 0, width, height)
                                        ctx.strokeStyle = ownerRoot.inkCol
                                        ctx.lineWidth = 1.8
                                        ctx.lineCap = "round"
                                        ctx.lineJoin = "round"
                                        ctx.beginPath()
                                        ctx.moveTo(2.5, 13.5)
                                        ctx.lineTo(5.5, 12.8)
                                        ctx.lineTo(13.5, 4.8)
                                        ctx.lineTo(11.2, 2.5)
                                        ctx.lineTo(3.2, 10.5)
                                        ctx.closePath()
                                        ctx.stroke()
                                    }
                                    Connections {
                                        target: telefam
                                        function onThemeChanged() { editIconCanvas.requestPaint() }
                                    }
                                }
                                Text {
                                    text: "Edit Profile"
                                    color: inkCol
                                    font.bold: true
                                    font.pixelSize: 14
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                            onClicked: telefam.openEditProfile()
                        }

                        Button {
                            id: settingsBtn
                            height: 44
                            width: settingsBtnRow.implicitWidth + 32
                            hoverEnabled: true
                            background: Rectangle {
                                radius: 22
                                color: settingsBtn.hovered ? subtleBg : cardBg
                                border.width: 1
                                border.color: borderCol
                            }
                            contentItem: Row {
                                id: settingsBtnRow
                                anchors.centerIn: parent
                                spacing: 8
                                Canvas {
                                    id: settingsIconCanvas
                                    width: 17
                                    height: 17
                                    anchors.verticalCenter: parent.verticalCenter
                                    onPaint: {
                                        var ctx = getContext("2d")
                                        ctx.clearRect(0, 0, width, height)
                                        ctx.strokeStyle = ownerRoot.inkCol
                                        ctx.lineWidth = 1.7
                                        ctx.beginPath()
                                        ctx.arc(8.5, 8.5, 2.4, 0, Math.PI * 2)
                                        ctx.stroke()
                                        ctx.beginPath()
                                        ctx.arc(8.5, 8.5, 5.4, 0, Math.PI * 2)
                                        ctx.stroke()
                                        for (var i = 0; i < 8; i++) {
                                            var ang = i * Math.PI / 4
                                            ctx.beginPath()
                                            ctx.moveTo(8.5 + Math.cos(ang) * 5.6, 8.5 + Math.sin(ang) * 5.6)
                                            ctx.lineTo(8.5 + Math.cos(ang) * 7.6, 8.5 + Math.sin(ang) * 7.6)
                                            ctx.stroke()
                                        }
                                    }
                                    Connections {
                                        target: telefam
                                        function onThemeChanged() { settingsIconCanvas.requestPaint() }
                                    }
                                }
                                Text {
                                    text: "Settings"
                                    color: inkCol
                                    font.bold: true
                                    font.pixelSize: 14
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                            onClicked: {
                                ownerRoot.comingSoonTitle = "Settings"
                                comingSoonDialog.open()
                            }
                        }
                    }
                }

                // Name (no verification badge) & Click-to-Copy @username + Quoted Bio
                Column {
                    width: parent.width
                    spacing: 4

                    Text {
                        text: ownerRoot.fullNameVal
                        color: inkCol
                        font.pixelSize: 24
                        font.bold: true
                        elide: Text.ElideRight
                        width: parent.width
                    }

                    Row {
                        visible: ownerRoot.usernameVal.length > 0
                        spacing: 10

                        Rectangle {
                            height: 28
                            width: unText.implicitWidth + 14
                            radius: 8
                            color: unMouse.containsMouse ? subtleBg : "transparent"

                            Text {
                                id: unText
                                anchors.centerIn: parent
                                text: "@" + ownerRoot.usernameVal
                                color: subCol
                                font.pixelSize: 15
                                font.weight: Font.Medium
                            }

                            MouseArea {
                                id: unMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: telefam.copyToClipboard("@" + ownerRoot.usernameVal, "Username copied")
                            }
                        }

                        Text {
                            visible: ownerRoot.locationVal.length > 0
                            anchors.verticalCenter: parent.verticalCenter
                            text: "• " + ownerRoot.locationVal
                            color: subCol
                            font.pixelSize: 13
                        }
                    }

                    RowLayout {
                        visible: ownerRoot.bioVal.length > 0
                        width: Math.min(parent.width, 640)
                        spacing: 8

                        Text {
                            text: "\u201C"
                            color: inkCol
                            font.pixelSize: 30
                            font.bold: true
                            Layout.alignment: Qt.AlignTop
                            topPadding: -6
                        }

                        Text {
                            text: ownerRoot.bioVal
                            color: inkCol
                            font.pixelSize: 14
                            lineHeight: 1.3
                            wrapMode: Text.Wrap
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                        }
                    }
                }

                // Stats (Followers | Following clickable, Posts & Views directly below) + Crimson Share Profile Pill
                RowLayout {
                    width: parent.width
                    spacing: 16

                    Column {
                        spacing: 8
                        Layout.alignment: Qt.AlignVCenter

                        Row {
                            spacing: 18

                            // Followers Clickable Counter
                            Column {
                                spacing: 1
                                width: Math.max(flwCount.implicitWidth, flwLbl.implicitWidth)
                                Text {
                                    id: flwCount
                                    text: telefam.formatFeedCount(Number(telefam.myProfile.followers_count || 0))
                                    color: inkCol
                                    font.bold: true
                                    font.pixelSize: 19
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                                Text {
                                    id: flwLbl
                                    text: "Followers"
                                    color: subCol
                                    font.pixelSize: 13
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: telefam.openOwnerConnections("followers")
                                }
                            }

                            Rectangle {
                                width: 1
                                height: 34
                                color: borderCol
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            // Following Clickable Counter
                            Column {
                                spacing: 1
                                width: Math.max(flgCount.implicitWidth, flgLbl.implicitWidth)
                                Text {
                                    id: flgCount
                                    text: telefam.formatFeedCount(Number(telefam.myProfile.following_count || 0))
                                    color: inkCol
                                    font.bold: true
                                    font.pixelSize: 19
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                                Text {
                                    id: flgLbl
                                    text: "Following"
                                    color: subCol
                                    font.pixelSize: 13
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: telefam.openOwnerConnections("following")
                                }
                            }
                        }

                        // Posts & Views counts directly below Followers & Following
                        Row {
                            spacing: 14
                            Row {
                                spacing: 4
                                Text {
                                    text: telefam.formatFeedCount(Number(telefam.myProfile.posts_count || 0))
                                    color: inkCol
                                    font.bold: true
                                    font.pixelSize: 13
                                }
                                Text {
                                    text: "Posts"
                                    color: subCol
                                    font.pixelSize: 13
                                }
                            }
                            Text {
                                text: "·"
                                color: subCol
                                font.pixelSize: 13
                            }
                            Row {
                                spacing: 4
                                Text {
                                    text: telefam.formatFeedCount(Number(telefam.myProfile.total_views_count || 0))
                                    color: inkCol
                                    font.bold: true
                                    font.pixelSize: 13
                                }
                                Text {
                                    text: "Views"
                                    color: subCol
                                    font.pixelSize: 13
                                }
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Button {
                        id: shareProfileBtn
                        Layout.preferredHeight: 46
                        Layout.preferredWidth: shareRow.implicitWidth + 40
                        hoverEnabled: true
                        background: Rectangle {
                            radius: 23
                            color: shareProfileBtn.hovered ? brandRedDeep : brandRed
                        }
                        contentItem: Row {
                            id: shareRow
                            anchors.centerIn: parent
                            spacing: 9
                            Image {
                                source: "qrc:/telefam/icons/ic_feed_share_white.svg"
                                sourceSize.width: 18
                                sourceSize.height: 18
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: "Share Profile"
                                color: "#FFFFFF"
                                font.bold: true
                                font.pixelSize: 14
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                        onClicked: {
                            var handle = ownerRoot.usernameVal.length > 0 ? ownerRoot.usernameVal : "profile"
                            telefam.copyToClipboard("https://telefam.app/@" + handle, "Profile link copied")
                        }
                    }
                }

                // 4 Category Pills: Posts, Reposts, Locked, Saved
                Row {
                    width: parent.width
                    spacing: 10
                    topPadding: 4

                    Repeater {
                        model: [
                            { key: "posts", label: "Posts" },
                            { key: "reposts", label: "Reposts" },
                            { key: "locked", label: "Locked" },
                            { key: "saved", label: "Saved" }
                        ]
                        delegate: Button {
                            id: catPill
                            readonly property bool isSelected: telefam.ownerActiveCategory === modelData.key
                            height: 42
                            width: Math.max(106, catRow.implicitWidth + 32)
                            hoverEnabled: true

                            background: Rectangle {
                                radius: 21
                                color: catPill.isSelected ? brandRed : (catPill.hovered ? subtleBg : cardBg)
                                border.width: catPill.isSelected ? 0 : 1
                                border.color: borderCol
                            }

                            contentItem: Row {
                                id: catRow
                                anchors.centerIn: parent
                                spacing: 7

                                Canvas {
                                    id: catIconCanvas
                                    width: 16
                                    height: 16
                                    anchors.verticalCenter: parent.verticalCenter
                                    onPaint: {
                                        var ctx = getContext("2d")
                                        ctx.clearRect(0, 0, width, height)
                                        var c = catPill.isSelected ? "#FFFFFF" : ownerRoot.inkCol
                                        ctx.strokeStyle = c
                                        ctx.fillStyle = c
                                        ctx.lineWidth = 1.6
                                        ctx.lineCap = "round"
                                        ctx.lineJoin = "round"

                                        if (modelData.key === "posts") {
                                            ctx.beginPath()
                                            ctx.roundedRect(1.5, 1.5, 5.2, 5.2, 1.4, 1.4)
                                            ctx.roundedRect(9.3, 1.5, 5.2, 5.2, 1.4, 1.4)
                                            ctx.roundedRect(1.5, 9.3, 5.2, 5.2, 1.4, 1.4)
                                            ctx.roundedRect(9.3, 9.3, 5.2, 5.2, 1.4, 1.4)
                                            ctx.fill()
                                        } else if (modelData.key === "reposts") {
                                            ctx.beginPath()
                                            ctx.moveTo(11, 2); ctx.lineTo(13.5, 4.5); ctx.lineTo(11, 7)
                                            ctx.moveTo(2.5, 7.5); ctx.lineTo(2.5, 5.5); ctx.arcTo(2.5, 4.5, 3.5, 4.5, 1.2); ctx.lineTo(13, 4.5)
                                            ctx.moveTo(5, 14); ctx.lineTo(2.5, 11.5); ctx.lineTo(5, 9)
                                            ctx.moveTo(13.5, 8.5); ctx.lineTo(13.5, 10.5); ctx.arcTo(13.5, 11.5, 12.5, 11.5, 1.2); ctx.lineTo(3, 11.5)
                                            ctx.stroke()
                                        } else if (modelData.key === "locked") {
                                            ctx.beginPath()
                                            ctx.roundedRect(3, 7, 10, 7, 1.8, 1.8)
                                            ctx.fill()
                                            ctx.beginPath()
                                            ctx.arc(8, 6.8, 3.1, Math.PI, 0)
                                            ctx.stroke()
                                        } else {
                                            ctx.beginPath()
                                            ctx.moveTo(3.5, 2.2)
                                            ctx.lineTo(12.5, 2.2)
                                            ctx.lineTo(12.5, 14)
                                            ctx.lineTo(8, 10.6)
                                            ctx.lineTo(3.5, 14)
                                            ctx.closePath()
                                            ctx.fill()
                                        }
                                    }
                                    Connections {
                                        target: telefam
                                        function onOwnerProfileChanged() { catIconCanvas.requestPaint() }
                                        function onThemeChanged() { catIconCanvas.requestPaint() }
                                    }
                                }

                                Text {
                                    text: modelData.label
                                    color: catPill.isSelected ? "#FFFFFF" : inkCol
                                    font.bold: catPill.isSelected
                                    font.pixelSize: 13
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            onClicked: telefam.selectOwnerCategory(modelData.key)
                        }
                    }
                }

                // Loading indicator while category refreshes on empty cache
                BusyIndicator {
                    visible: telefam.ownerItemsLoading && telefam.ownerActiveItems.length === 0
                    running: visible
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                // Empty State
                Column {
                    visible: !telefam.ownerItemsLoading && telefam.ownerActiveItems.length === 0
                    width: parent.width
                    topPadding: 36
                    bottomPadding: 36
                    spacing: 8

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: {
                            if (telefam.ownerActiveCategory === "reposts") return "No reposts yet"
                            if (telefam.ownerActiveCategory === "locked") return "No locked posts"
                            if (telefam.ownerActiveCategory === "saved") return "No saved posts"
                            return "No posts yet"
                        }
                        color: inkCol
                        font.bold: true
                        font.pixelSize: 16
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Your " + telefam.ownerActiveCategory + " items will appear here."
                        color: subCol
                        font.pixelSize: 13
                    }
                }

                // Responsive Desktop Grid (3–4 columns)
                GridLayout {
                    id: mediaGrid
                    visible: telefam.ownerActiveItems.length > 0
                    width: parent.width
                    columns: width >= 820 ? 4 : (width >= 540 ? 3 : 2)
                    columnSpacing: 10
                    rowSpacing: 10

                    readonly property real tileWidth: (width - columnSpacing * (columns - 1)) / columns

                    Repeater {
                        model: telefam.ownerActiveItems
                        delegate: Rectangle {
                            id: gridTile
                            Layout.preferredWidth: mediaGrid.tileWidth
                            Layout.preferredHeight: Math.round(mediaGrid.tileWidth * 1.15)
                            radius: 12
                            color: telefam.isDarkTheme ? "#1D2028" : "#ECEEF2"
                            clip: true

                            readonly property string thumbSrc: {
                                if (modelData.resolved_thumbnail_url && modelData.resolved_thumbnail_url.length > 0) {
                                    return modelData.resolved_thumbnail_url
                                }
                                if (modelData.resolved_media_urls && modelData.resolved_media_urls.length > 0) {
                                    return modelData.resolved_media_urls[0]
                                }
                                return ""
                            }
                            readonly property bool isVideoItem: modelData.post_type === "video" || (modelData.video && modelData.video.video_id)

                            // Thumbnail image (Video / Photo posts)
                            Image {
                                anchors.fill: parent
                                visible: gridTile.thumbSrc.length > 0
                                source: gridTile.thumbSrc
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                            }

                            // Styled text-post preview when no thumbnail image
                            Rectangle {
                                anchors.fill: parent
                                visible: gridTile.thumbSrc.length === 0
                                color: modelData.bg_color_hex && modelData.bg_color_hex.length > 0 ? modelData.bg_color_hex : "#C81010"

                                Text {
                                    anchors.centerIn: parent
                                    width: parent.width - 24
                                    text: modelData.body || ""
                                    color: "#FFFFFF"
                                    font.bold: true
                                    font.pixelSize: 14
                                    horizontalAlignment: Text.AlignHCenter
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 4
                                    elide: Text.ElideRight
                                }
                            }

                            // Bottom dark scrim
                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                height: 56
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: "transparent" }
                                    GradientStop { position: 1.0; color: "#A6000000" }
                                }
                            }

                            // Top-right type icon (Video play / Photo frame)
                            Image {
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.margins: 10
                                source: gridTile.isVideoItem
                                        ? "qrc:/telefam/icons/ic_play.svg"
                                        : "qrc:/telefam/icons/ic_photos_tab.svg"
                                sourceSize.width: 18
                                sourceSize.height: 18
                                fillMode: Image.PreserveAspectFit
                            }

                            // Bottom-left white heart + likes count
                            Row {
                                anchors.left: parent.left
                                anchors.bottom: parent.bottom
                                anchors.margins: 10
                                spacing: 5

                                Image {
                                    source: "qrc:/telefam/icons/ic_heart_white.svg"
                                    sourceSize.width: 15
                                    sourceSize.height: 15
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Text {
                                    text: telefam.formatFeedCount(Number(modelData.likes_count || 0))
                                    color: "#FFFFFF"
                                    font.bold: true
                                    font.pixelSize: 13
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: telefam.openOwnerGridItem(modelData)
                                onEntered: gridTile.border.color = brandRed
                                onExited: gridTile.border.color = "transparent"
                            }
                            border.width: 2
                            border.color: "transparent"
                        }
                    }
                }
            }
        }
    }

    // Sticky compact header when scrolled down past cover
    Rectangle {
        visible: profileFlick.collapseProgress > 0.72
        opacity: Math.min(1.0, (profileFlick.collapseProgress - 0.72) / 0.28)
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 58
        color: cardBg
        z: 5

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: borderCol
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 20
            anchors.rightMargin: 20
            spacing: 10

            Rectangle {
                Layout.preferredWidth: 34
                Layout.preferredHeight: 34
                radius: 17
                color: telefam.isDarkTheme ? "#2B1517" : "#FCE8E8"
                clip: true
                Image {
                    anchors.fill: parent
                    visible: telefam.ownerLocalAvatarUrl.length > 0
                    source: telefam.ownerLocalAvatarUrl
                    fillMode: Image.PreserveAspectCrop
                }
                Text {
                    visible: telefam.ownerLocalAvatarUrl.length === 0
                    anchors.centerIn: parent
                    text: ownerRoot.computeInitials(ownerRoot.fullNameVal)
                    color: brandRed
                    font.bold: true
                    font.pixelSize: 12
                }
            }

            Column {
                Layout.fillWidth: true
                Text {
                    text: ownerRoot.fullNameVal
                    color: inkCol
                    font.bold: true
                    font.pixelSize: 15
                    elide: Text.ElideRight
                }
                Text {
                    visible: ownerRoot.usernameVal.length > 0
                    text: "@" + ownerRoot.usernameVal
                    color: subCol
                    font.pixelSize: 11
                }
            }

            Button {
                Layout.preferredHeight: 34
                Layout.preferredWidth: 88
                flat: true
                contentItem: Text {
                    text: "Refresh"
                    color: brandRed
                    font.bold: true
                    font.pixelSize: 13
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                onClicked: telefam.refreshOwnerProfile(true)
            }

            Button {
                Layout.preferredWidth: 44
                Layout.preferredHeight: 44
                flat: true
                contentItem: Canvas {
                    id: stickyMenuCanvas
                    anchors.centerIn: parent
                    width: 20
                    height: 18
                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)
                        ctx.strokeStyle = ownerRoot.inkCol
                        ctx.lineWidth = 2.0
                        ctx.lineCap = "round"
                        ctx.beginPath()
                        ctx.moveTo(2, 3); ctx.lineTo(18, 3)
                        ctx.moveTo(2, 9); ctx.lineTo(18, 9)
                        ctx.moveTo(2, 15); ctx.lineTo(18, 15)
                        ctx.stroke()
                    }
                    Connections {
                        target: telefam
                        function onThemeChanged() { stickyMenuCanvas.requestPaint() }
                    }
                }
                onClicked: {
                    ownerRoot.comingSoonTitle = "Menu"
                    comingSoonDialog.open()
                }
            }
        }
    }

    // File Dialogs
    FileDialog {
        id: avatarFileDialog
        title: "Choose Profile Photo"
        nameFilters: ["Images (*.png *.jpg *.jpeg *.webp)"]
        onAccepted: {
            ownerRoot.pendingAvatarUrl = selectedFile
            avatarCropDialog.offX = 0
            avatarCropDialog.offY = 0
            zoomSlider.value = 1.0
            avatarCropDialog.open()
        }
    }

    FileDialog {
        id: bgFileDialog
        title: "Select up to 5 Background Photos"
        fileMode: FileDialog.OpenFiles
        nameFilters: ["Images (*.png *.jpg *.jpeg *.webp)"]
        onAccepted: {
            telefam.uploadOwnerBackgroundPhotos(selectedFiles)
        }
    }

    // 1. Coming Soon Dialog (Settings & 3-Dash Menu)
    Dialog {
        id: comingSoonDialog
        title: ownerRoot.comingSoonTitle
        modal: true
        anchors.centerIn: parent
        width: 340
        standardButtons: Dialog.Ok

        Text {
            width: parent.width
            text: "Coming Soon"
            color: inkCol
            font.pixelSize: 16
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            padding: 12
        }
    }

    // 2. Avatar Circular Crop Dialog
    Dialog {
        id: avatarCropDialog
        title: "Adjust Profile Photo"
        modal: true
        anchors.centerIn: parent
        width: 340
        standardButtons: Dialog.Ok | Dialog.Cancel

        property real offX: 0
        property real offY: 0

        ColumnLayout {
            spacing: 14
            width: parent.width

            Rectangle {
                width: 240
                height: 240
                radius: 12
                color: "#000000"
                clip: true
                Layout.alignment: Qt.AlignHCenter

                Image {
                    source: ownerRoot.pendingAvatarUrl
                    width: 240 * zoomSlider.value
                    height: 240 * zoomSlider.value
                    x: (parent.width - width) / 2 + avatarCropDialog.offX
                    y: (parent.height - height) / 2 + avatarCropDialog.offY
                    fillMode: Image.PreserveAspectCrop
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: 216
                    height: 216
                    radius: 108
                    color: "transparent"
                    border.color: "#FFFFFF"
                    border.width: 2
                }

                MouseArea {
                    anchors.fill: parent
                    property real lastX: 0
                    property real lastY: 0
                    onPressed: function(mouse) { lastX = mouse.x; lastY = mouse.y }
                    onPositionChanged: function(mouse) {
                        avatarCropDialog.offX += (mouse.x - lastX)
                        avatarCropDialog.offY += (mouse.y - lastY)
                        lastX = mouse.x
                        lastY = mouse.y
                    }
                }
            }

            Slider {
                id: zoomSlider
                from: 1.0
                to: 3.0
                value: 1.0
                Layout.fillWidth: true
            }
        }

        onAccepted: {
            telefam.cropAndUploadAvatar(ownerRoot.pendingAvatarUrl, zoomSlider.value, avatarCropDialog.offX / 240.0, avatarCropDialog.offY / 240.0)
        }
    }

    // 3. Background Photos Manager Dialog (up to 5)
    Dialog {
        id: backgroundManagerDialog
        title: "Background Photos (" + ownerRoot.slideList.length + "/5)"
        modal: true
        anchors.centerIn: parent
        width: 520
        height: 440
        standardButtons: Dialog.Close

        ColumnLayout {
            anchors.fill: parent
            spacing: 12

            Text {
                text: "Background photos animate with a fade every 5 seconds."
                color: subCol
                font.pixelSize: 12
                Layout.fillWidth: true
            }

            GridView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                cellWidth: Math.max(140, width / 3)
                cellHeight: cellWidth * 0.68
                model: ownerRoot.slideList
                delegate: Item {
                    width: GridView.view.cellWidth
                    height: GridView.view.cellHeight
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 5
                        radius: 10
                        color: "#16181D"
                        clip: true

                        Image {
                            anchors.fill: parent
                            source: modelData.url || ""
                            fillMode: Image.PreserveAspectCrop
                            cache: false
                        }

                        Button {
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.margins: 6
                            width: 30
                            height: 30
                            background: Rectangle {
                                radius: 15
                                color: "#B8000000"
                            }
                            contentItem: Image {
                                anchors.centerIn: parent
                                source: "qrc:/telefam/icons/ic_trash_red.svg"
                                sourceSize.width: 15
                                sourceSize.height: 15
                            }
                            onClicked: telefam.deleteOwnerBackgroundPhoto(modelData.id || "")
                        }
                    }
                }
            }

            Button {
                enabled: ownerRoot.slideList.length < 5 && !telefam.ownerUploadingBackgrounds
                text: ownerRoot.slideList.length < 5 ? ("Add Photos (" + (5 - ownerRoot.slideList.length) + " remaining)") : "Maximum 5 photos reached"
                Layout.fillWidth: true
                Layout.preferredHeight: 44
                background: Rectangle {
                    radius: 10
                    color: parent.enabled ? brandRed : borderCol
                }
                contentItem: Text {
                    text: parent.text
                    color: "#FFFFFF"
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                onClicked: bgFileDialog.open()
            }
        }
    }

    // 4. Followers / Following Modal List
    Dialog {
        id: connectionsDialog
        visible: telefam.ownerConnectionsMode.length > 0
        title: telefam.ownerConnectionsMode === "following" ? "Following" : "Followers"
        modal: true
        anchors.centerIn: parent
        width: 460
        height: 480
        standardButtons: Dialog.Close
        onRejected: telefam.closeOwnerConnections()
        onAccepted: telefam.closeOwnerConnections()
        onClosed: telefam.closeOwnerConnections()

        Item {
            anchors.fill: parent

            BusyIndicator {
                anchors.centerIn: parent
                visible: telefam.ownerConnectionsLoading && telefam.ownerConnectionsUsers.length === 0
                running: visible
            }

            Text {
                anchors.centerIn: parent
                visible: !telefam.ownerConnectionsLoading && telefam.ownerConnectionsUsers.length === 0
                text: telefam.ownerConnectionsMode === "following" ? "Not following anyone yet" : "No followers yet"
                color: subCol
                font.pixelSize: 14
            }

            ListView {
                anchors.fill: parent
                visible: telefam.ownerConnectionsUsers.length > 0
                clip: true
                spacing: 8
                model: telefam.ownerConnectionsUsers
                delegate: Rectangle {
                    width: ListView.view.width
                    height: 68
                    radius: 12
                    color: cardBg
                    border.width: 1
                    border.color: borderCol

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 12

                        Rectangle {
                            Layout.preferredWidth: 42
                            Layout.preferredHeight: 42
                            radius: 21
                            color: telefam.isDarkTheme ? "#162B3D" : "#EAF2FA"
                            Text {
                                anchors.centerIn: parent
                                text: ownerRoot.computeInitials(modelData.full_name)
                                color: telefam.isDarkTheme ? "#5FA8E8" : "#1D4ED8"
                                font.bold: true
                                font.pixelSize: 13
                            }
                        }

                        Column {
                            Layout.fillWidth: true
                            spacing: 2
                            Text {
                                text: modelData.full_name || ""
                                color: inkCol
                                font.bold: true
                                font.pixelSize: 14
                                elide: Text.ElideRight
                                width: parent.width
                            }
                            Text {
                                text: "@" + (modelData.username || "")
                                color: subCol
                                font.pixelSize: 12
                                elide: Text.ElideRight
                                width: parent.width
                            }
                        }

                        Button {
                            id: connFollowBtn
                            readonly property string rel: modelData.relationship || "follow"
                            Layout.preferredHeight: 34
                            Layout.preferredWidth: Math.max(90, relTxt.implicitWidth + 24)
                            background: Rectangle {
                                radius: 17
                                color: connFollowBtn.rel === "friends"
                                       ? (telefam.isDarkTheme ? "#1E1315" : "#FFF5F5")
                                       : (connFollowBtn.rel === "following" ? "transparent" : brandRed)
                                border.width: (connFollowBtn.rel === "friends" || connFollowBtn.rel === "following") ? 1 : 0
                                border.color: connFollowBtn.rel === "friends" ? brandRed : borderCol
                            }
                            contentItem: Text {
                                id: relTxt
                                text: {
                                    if (connFollowBtn.rel === "friends") return "Friends"
                                    if (connFollowBtn.rel === "following") return "Following"
                                    if (connFollowBtn.rel === "follow_back") return "Follow back"
                                    return "Follow"
                                }
                                color: connFollowBtn.rel === "friends" ? brandRed : (connFollowBtn.rel === "following" ? subCol : "#FFFFFF")
                                font.bold: true
                                font.pixelSize: 12
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            onClicked: telefam.toggleOwnerConnectionFollow(modelData.user_id || "")
                        }
                    }
                }
            }
        }
    }

    // 5. Photo / Text Post Viewer Modal
    Dialog {
        id: ownerViewerDialog
        readonly property var curItem: telefam.ownerActiveViewerItem || ({})
        readonly property bool hasItem: !!(curItem && curItem.post_id && curItem.post_id.length > 0)
        readonly property var mediaUrls: (curItem && curItem.resolved_media_urls) ? curItem.resolved_media_urls : []
        visible: hasItem
        title: ownerRoot.fullNameVal
        modal: true
        anchors.centerIn: parent
        width: 560
        height: 540
        standardButtons: Dialog.Close
        onRejected: telefam.closeOwnerGridViewer()
        onClosed: telefam.closeOwnerGridViewer()

        ColumnLayout {
            anchors.fill: parent
            spacing: 10

            // Photo preview or styled text card
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 12
                color: ownerViewerDialog.mediaUrls.length > 0
                       ? "#000000"
                       : (ownerViewerDialog.curItem.bg_color_hex || "#C81010")
                clip: true

                Image {
                    anchors.fill: parent
                    visible: ownerViewerDialog.mediaUrls.length > 0
                    source: {
                        if (ownerViewerDialog.mediaUrls.length === 0) return ""
                        var idx = Math.max(0, Math.min(ownerRoot.viewerPhotoIndex, ownerViewerDialog.mediaUrls.length - 1))
                        return ownerViewerDialog.mediaUrls[idx]
                    }
                    fillMode: Image.PreserveAspectFit
                }

                Text {
                    anchors.centerIn: parent
                    visible: ownerViewerDialog.mediaUrls.length === 0
                    width: parent.width - 40
                    text: ownerViewerDialog.curItem.body || ""
                    color: "#FFFFFF"
                    font.bold: true
                    font.pixelSize: 20
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                }

                // Multi-photo carousel controls
                Row {
                    visible: ownerViewerDialog.mediaUrls.length > 1
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottomMargin: 10
                    spacing: 10
                    Button {
                        text: "<"
                        enabled: ownerRoot.viewerPhotoIndex > 0
                        onClicked: ownerRoot.viewerPhotoIndex--
                    }
                    Text {
                        text: (ownerRoot.viewerPhotoIndex + 1) + " / " + ownerViewerDialog.mediaUrls.length
                        color: "#FFFFFF"
                        font.bold: true
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Button {
                        text: ">"
                        enabled: ownerRoot.viewerPhotoIndex < ownerViewerDialog.mediaUrls.length - 1
                        onClicked: ownerRoot.viewerPhotoIndex++
                    }
                }
            }

            Text {
                visible: ownerViewerDialog.mediaUrls.length > 0 && (ownerViewerDialog.curItem.body || "").length > 0
                text: ownerViewerDialog.curItem.body || ""
                color: inkCol
                font.pixelSize: 13
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Button {
                    text: (ownerViewerDialog.curItem.is_liked ? "Liked (" : "Like (") + telefam.formatFeedCount(Number(ownerViewerDialog.curItem.likes_count || 0)) + ")"
                    onClicked: telefam.toggleOwnerPostLike(ownerViewerDialog.curItem.post_id || "")
                }

                Button {
                    text: ownerViewerDialog.curItem.is_saved ? "Saved" : "Save"
                    onClicked: telefam.toggleOwnerPostSave(ownerViewerDialog.curItem.post_id || "")
                }

                Button {
                    text: ownerViewerDialog.curItem.visibility === "private" ? "Unlock" : "Lock"
                    onClicked: telefam.toggleOwnerPostLock(ownerViewerDialog.curItem.post_id || "")
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: telefam.formatFeedCount(Number(ownerViewerDialog.curItem.views_count || 0)) + " views"
                    color: subCol
                    font.pixelSize: 12
                }
            }
        }
    }
}
