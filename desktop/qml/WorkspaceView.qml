import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: workspace
    readonly property color brandRed: "#C81010"
    readonly property color bodyBg: telefam.activeTab === 2 ? "#000000" : (telefam.isDarkTheme ? "#121316" : "#FFFFFF")
    readonly property color cardBg: telefam.isDarkTheme ? "#1B1D22" : "#F9FAFB"
    readonly property color railBg: telefam.activeTab === 2 ? "#090A0D" : (telefam.isDarkTheme ? "#16181C" : "#F3F4F6")
    readonly property color pillBg: telefam.isDarkTheme ? "#1E1F24" : "#A60B0B"
    readonly property color borderCol: telefam.activeTab === 2 ? "#1EFFFFFF" : (telefam.isDarkTheme ? "#2B2F38" : "#E5E7EB")
    readonly property color inkCol: telefam.isDarkTheme ? "#FFFFFF" : "#111827"
    readonly property color subCol: telefam.activeTab === 2 ? "#A8FFFFFF" : (telefam.isDarkTheme ? "#9CA3AF" : "#6B7280")

    focus: true
    Keys.onEscapePressed: {
        if (telefam.selectedConversationId.length > 0) {
            telefam.selectConversation("")
        } else if (telefam.activeTab !== 0) {
            telefam.selectTab(0)
        }
    }

    Rectangle {
        anchors.fill: parent
        color: telefam.activeTab === 2 ? "#000000" : (telefam.activeTab === 3 ? bodyBg : brandRed)
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Top Red Bar: hidden during immersive Feeds & Owner Profile tabs
        ColumnLayout {
            visible: telefam.activeTab !== 2 && telefam.activeTab !== 3
            Layout.fillWidth: true
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 62
                Layout.leftMargin: 18
                Layout.rightMargin: 18
                spacing: 12

                // Live Search Input for Chats / Feeds / Profile
                Rectangle {
                    visible: telefam.activeTab !== 1
                    Layout.fillWidth: true
                    Layout.maximumWidth: 480
                    Layout.preferredHeight: 46
                    radius: 23
                    color: pillBg
                    border.width: 1
                    border.color: "#14FFFFFF"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 8
                        Image { source: "qrc:/telefam/icons/ic_search.svg"; sourceSize.width: 18; sourceSize.height: 18 }
                        TextField {
                            Layout.fillWidth: true
                            text: telefam.homeSearchQuery
                            placeholderText: "Search chats, people, groups"
                            placeholderTextColor: "#B3FFFFFF"
                            color: "#FFFFFF"
                            font.pixelSize: 13
                            background: Item {}
                            onTextEdited: telefam.setHomeSearchQuery(text)
                        }
                    }
                }

                // Independent Contacts search input
                Rectangle {
                    visible: telefam.activeTab === 1
                    Layout.fillWidth: true
                    Layout.maximumWidth: 520
                    Layout.preferredHeight: 46
                    radius: 23
                    color: telefam.isDarkTheme ? "#1A2029" : "#A60B0B"
                    border.width: 1
                    border.color: "#22FFFFFF"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 8
                        Image { source: "qrc:/telefam/icons/ic_search.svg"; sourceSize.width: 18; sourceSize.height: 18 }
                        TextField {
                            Layout.fillWidth: true
                            text: telefam.contactSearchQuery
                            placeholderText: "Search by name or username"
                            placeholderTextColor: "#B3FFFFFF"
                            color: "#FFFFFF"
                            font.pixelSize: 13
                            background: Item {}
                            onTextEdited: telefam.setContactSearchQuery(text)
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                // Theme Switcher Pill
                Button {
                    Layout.preferredHeight: 38
                    Layout.preferredWidth: 96
                    background: Rectangle {
                        color: pillBg
                        radius: 19
                        border.width: 1
                        border.color: "#22FFFFFF"
                    }
                    contentItem: Row {
                        anchors.centerIn: parent
                        spacing: 6
                        Image {
                            source: telefam.isDarkTheme ? "qrc:/telefam/icons/ic_moon.svg" : "qrc:/telefam/icons/ic_sun.svg"
                            sourceSize.width: 14
                            sourceSize.height: 14
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: telefam.isDarkTheme ? "Dark" : "Light"
                            color: "#FFFFFF"
                            font.bold: true
                            font.pixelSize: 12
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    onClicked: telefam.toggleTheme()
                }

                Button {
                    visible: telefam.activeTab !== 1
                    Layout.preferredWidth: 48
                    Layout.preferredHeight: 48
                    flat: true
                    contentItem: Item {
                        Image {
                            anchors.centerIn: parent
                            source: "qrc:/telefam/icons/ic_bell.svg"
                            sourceSize.width: 22
                            sourceSize.height: 22
                            fillMode: Image.PreserveAspectFit
                        }
                        Rectangle {
                            visible: telefam.unreadNotificationCount > 0
                            width: 8
                            height: 8
                            radius: 4
                            color: "#FFFFFF"
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.topMargin: 8
                            anchors.rightMargin: 8
                        }
                    }
                    onClicked: {
                        telefam.refreshNotifications()
                        notificationsDialog.open()
                    }
                }

                Button {
                    id: moreMenuBtn
                    visible: telefam.activeTab !== 1
                    Layout.preferredWidth: 48
                    Layout.preferredHeight: 48
                    flat: true
                    contentItem: Image {
                        source: "qrc:/telefam/icons/ic_more.svg"
                        sourceSize.width: 22
                        sourceSize.height: 22
                        fillMode: Image.PreserveAspectFit
                    }
                    onClicked: moreMenu.open()

                    Menu {
                        id: moreMenu
                        y: moreMenuBtn.height
                        MenuItem {
                            text: "Sync"
                            onTriggered: telefam.syncNow()
                        }
                        MenuItem {
                            text: "Edit profile"
                            onTriggered: telefam.openEditProfile()
                        }
                        MenuSeparator {}
                        MenuItem {
                            text: "Sign out"
                            onTriggered: telefam.signOut()
                        }
                    }
                }
            }

            // Contacts Filter Tabs Row
            RowLayout {
                visible: telefam.activeTab === 1
                Layout.fillWidth: true
                Layout.leftMargin: 18
                Layout.rightMargin: 18
                Layout.bottomMargin: 10
                spacing: 8

                Repeater {
                    model: [
                        { key: "all", label: "All" },
                        { key: "suggestions", label: "Suggestions" },
                        { key: "followers", label: "Followers" },
                        { key: "following", label: "Following" },
                        { key: "friends", label: "Friends" }
                    ]
                    delegate: Button {
                        readonly property bool isSelected: telefam.contactFilter === modelData.key
                        Layout.preferredHeight: 36
                        Layout.preferredWidth: filterLbl.implicitWidth + 36
                        background: Rectangle {
                            radius: 18
                            color: isSelected ? "#FFFFFF" : "transparent"
                        }
                        contentItem: Text {
                            id: filterLbl
                            text: modelData.label
                            color: isSelected ? "#111827" : "#FFFFFF"
                            font.bold: isSelected
                            font.pixelSize: 13
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        onClicked: telefam.selectContactFilter(modelData.key)
                    }
                }

                Item { Layout.fillWidth: true }
            }
        }

        // Rounded-top workspace surface
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: bodyBg
            topLeftRadius: (telefam.activeTab === 1 || telefam.activeTab === 2 || telefam.activeTab === 3) ? 0 : 24
            topRightRadius: (telefam.activeTab === 1 || telefam.activeTab === 2 || telefam.activeTab === 3) ? 0 : 24
            clip: true

            RowLayout {
                anchors.fill: parent
                spacing: 0

                // Left Navigation Rail
                Rectangle {
                    Layout.preferredWidth: 84
                    Layout.fillHeight: true
                    color: railBg

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.topMargin: 20
                        anchors.bottomMargin: 20
                        spacing: 16

                        Button {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: 74
                            Layout.preferredHeight: 54
                            flat: true
                            contentItem: Column {
                                spacing: 4
                                Image {
                                    source: telefam.activeTab === 0 ? "qrc:/telefam/icons/ic_chats_red.svg" : "qrc:/telefam/icons/ic_chats_outline.svg"
                                    sourceSize.width: 20
                                    sourceSize.height: 20
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                                Text {
                                    text: "Chats"
                                    color: telefam.activeTab === 0 ? brandRed : subCol
                                    font.bold: telefam.activeTab === 0
                                    font.pixelSize: 11
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                            }
                            onClicked: {
                                telefam.selectTab(0)
                                telefam.selectConversation("")
                            }
                        }

                        Button {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: 74
                            Layout.preferredHeight: 54
                            flat: true
                            contentItem: Column {
                                spacing: 4
                                Image {
                                    source: telefam.activeTab === 1 ? "qrc:/telefam/icons/ic_contacts_red.svg" : "qrc:/telefam/icons/ic_contacts.svg"
                                    sourceSize.width: 20
                                    sourceSize.height: 20
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                                Text {
                                    text: "Contacts"
                                    color: telefam.activeTab === 1 ? brandRed : subCol
                                    font.bold: telefam.activeTab === 1
                                    font.pixelSize: 11
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                            }
                            onClicked: telefam.selectTab(1)
                        }

                        Button {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: 48
                            Layout.preferredHeight: 48
                            background: Rectangle { color: brandRed; radius: 24 }
                            contentItem: Image {
                                source: "qrc:/telefam/icons/ic_plus_white.svg"
                                sourceSize.width: 22
                                sourceSize.height: 22
                                fillMode: Image.PreserveAspectFit
                            }
                            onClicked: telefam.openPostComposer()
                        }

                        Button {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: 74
                            Layout.preferredHeight: 54
                            flat: true
                            contentItem: Column {
                                spacing: 4
                                Image { source: "qrc:/telefam/icons/ic_feeds.svg"; sourceSize.width: 20; sourceSize.height: 20; anchors.horizontalCenter: parent.horizontalCenter }
                                Text {
                                    text: "Feeds"
                                    color: telefam.activeTab === 2 ? brandRed : subCol
                                    font.bold: telefam.activeTab === 2
                                    font.pixelSize: 11
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                            }
                            onClicked: telefam.selectTab(2)
                        }

                        Button {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: 74
                            Layout.preferredHeight: 54
                            flat: true
                            contentItem: Column {
                                spacing: 4
                                Image { source: "qrc:/telefam/icons/ic_profile.svg"; sourceSize.width: 20; sourceSize.height: 20; anchors.horizontalCenter: parent.horizontalCenter }
                                Text {
                                    text: "Profile"
                                    color: telefam.activeTab === 3 ? brandRed : subCol
                                    font.bold: telefam.activeTab === 3
                                    font.pixelSize: 11
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                            }
                            onClicked: telefam.selectTab(3)
                        }

                        Item { Layout.fillHeight: true }
                    }
                }

                Rectangle {
                    Layout.preferredWidth: 1
                    Layout.fillHeight: true
                    color: borderCol
                }

                // Main Content Area
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    ContactsView {
                        visible: telefam.activeTab === 1
                        anchors.fill: parent
                    }

                    // Empty Chats
                    ColumnLayout {
                        visible: telefam.activeTab === 0 && telefam.filteredConversations.length === 0
                        anchors.centerIn: parent
                        spacing: 14

                        Rectangle {
                            width: 72
                            height: 72
                            radius: 36
                            color: telefam.isDarkTheme ? "#2C1618" : "#FCE8E8"
                            Layout.alignment: Qt.AlignHCenter
                            Image {
                                anchors.centerIn: parent
                                source: "qrc:/telefam/icons/ic_chats_red.svg"
                                sourceSize.width: 30
                                sourceSize.height: 30
                            }
                        }

                        Text {
                            text: "Start a conversation"
                            font.pixelSize: 22
                            font.bold: true
                            color: inkCol
                            Layout.alignment: Qt.AlignHCenter
                        }

                        Text {
                            text: "Tap the button below to chat with your friends, family or groups"
                            font.pixelSize: 14
                            color: subCol
                            Layout.alignment: Qt.AlignHCenter
                        }

                        Button {
                            text: "Start chat"
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: 168
                            Layout.preferredHeight: 48
                            background: Rectangle { color: brandRed; radius: 24 }
                            contentItem: Text {
                                text: parent.text
                                color: "#FFFFFF"
                                font.bold: true
                                font.pixelSize: 15
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            onClicked: newChatDialog.open()
                        }
                    }

                    // Active Conversations Split-Pane
                    SplitView {
                        visible: telefam.activeTab === 0 && telefam.filteredConversations.length > 0
                        anchors.fill: parent
                        orientation: Qt.Horizontal

                        Rectangle {
                            SplitView.preferredWidth: 300
                            SplitView.minimumWidth: 240
                            color: bodyBg

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 10

                                Button {
                                    text: "+ Start chat"
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 42
                                    background: Rectangle { color: brandRed; radius: 10 }
                                    contentItem: Text {
                                        text: parent.text
                                        color: "#FFFFFF"
                                        font.bold: true
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    onClicked: newChatDialog.open()
                                }

                                ListView {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    model: telefam.filteredConversations
                                    spacing: 6
                                    delegate: ItemDelegate {
                                        width: ListView.view.width
                                        highlighted: modelData.id === telefam.selectedConversationId
                                        contentItem: Text {
                                            text: modelData.title
                                            color: inkCol
                                            font.bold: true
                                        }
                                        onClicked: telefam.selectConversation(modelData.id)
                                    }
                                }
                            }
                        }

                        Rectangle {
                            SplitView.fillWidth: true
                            color: bodyBg

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 16
                                spacing: 10

                                ListView {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    model: telefam.messages
                                    spacing: 8
                                    delegate: Rectangle {
                                        width: Math.min(parent ? parent.width * 0.75 : 400, 460)
                                        height: msgCol.implicitHeight + 16
                                        radius: 14
                                        color: cardBg
                                        Column {
                                            id: msgCol
                                            anchors.fill: parent
                                            anchors.margins: 10
                                            Text { text: modelData.body; color: inkCol; wrapMode: Text.Wrap; width: parent.width }
                                            Text {
                                                text: modelData.pending ? "Queued" : "Sent"
                                                font.pixelSize: 10
                                                color: subCol
                                            }
                                        }
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    visible: telefam.selectedConversationId.length > 0
                                    spacing: 10
                                    TextField {
                                        id: msgInput
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 44
                                        placeholderText: "Write a message"
                                        color: inkCol
                                        onAccepted: {
                                            telefam.sendMessageOfflineFirst(text)
                                            text = ""
                                        }
                                    }
                                    Button {
                                        text: "Send"
                                        Layout.preferredWidth: 92
                                        Layout.preferredHeight: 44
                                        background: Rectangle { color: brandRed; radius: 10 }
                                        contentItem: Text {
                                            text: parent.text
                                            color: "#FFFFFF"
                                            font.bold: true
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                        onClicked: {
                                            telefam.sendMessageOfflineFirst(msgInput.text)
                                            msgInput.text = ""
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Feeds Tab (activeTab === 2)
                    FeedView {
                        visible: telefam.activeTab === 2
                        anchors.fill: parent
                    }

                    // Owner Profile Tab (activeTab === 3)
                    OwnerProfileView {
                        visible: telefam.activeTab === 3
                        anchors.fill: parent
                    }
                }
            }
        }
    }

    Rectangle {
        visible: telefam.toastMessage.length > 0
        z: 50
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 28
        width: toastLbl.implicitWidth + 32
        height: 40
        radius: 20
        color: "#111827"
        Text {
            id: toastLbl
            anchors.centerIn: parent
            text: telefam.toastMessage
            color: "#FFFFFF"
            font.bold: true
            font.pixelSize: 13
        }
    }

    Dialog {
        id: notificationsDialog
        title: "Notifications"
        modal: true
        anchors.centerIn: parent
        width: 420
        height: 360
        standardButtons: Dialog.Close

        ColumnLayout {
            anchors.fill: parent
            spacing: 10

            Button {
                visible: telefam.unreadNotificationCount > 0
                text: "Mark all read"
                Layout.alignment: Qt.AlignRight
                onClicked: telefam.markNotificationsRead()
            }

            Text {
                visible: telefam.notifications.length === 0
                text: "No notifications"
                color: subCol
                Layout.alignment: Qt.AlignHCenter
            }

            ListView {
                visible: telefam.notifications.length > 0
                Layout.fillWidth: true
                Layout.fillHeight: true
                model: telefam.notifications
                spacing: 8
                clip: true
                delegate: Rectangle {
                    width: ListView.view.width
                    height: notifCol.implicitHeight + 16
                    radius: 10
                    color: cardBg
                    border.color: borderCol
                    border.width: 1
                    Column {
                        id: notifCol
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 2
                        Text {
                            visible: (modelData.actor_name || "").length > 0
                            text: modelData.actor_name || ""
                            color: inkCol
                            font.bold: true
                            font.pixelSize: 13
                        }
                        Text {
                            text: modelData.message || ""
                            color: subCol
                            font.pixelSize: 12
                            wrapMode: Text.Wrap
                            width: parent.width
                        }
                    }
                }
            }
        }
    }

    Dialog {
        id: newChatDialog
        title: "Start chat"
        modal: true
        anchors.centerIn: parent
        width: 360
        standardButtons: Dialog.Ok | Dialog.Cancel

        TextField {
            id: newChatField
            width: parent.width
            placeholderText: "Recipient name or email"
        }

        onAccepted: {
            telefam.createConversation(newChatField.text)
            newChatField.text = ""
        }
    }

    Dialog {
        id: savedVideosDialog
        title: "Saved videos"
        modal: true
        anchors.centerIn: parent
        width: 560
        height: 480
        standardButtons: Dialog.Close

        GridView {
            anchors.fill: parent
            clip: true
            cellWidth: Math.max(130, width / 3)
            cellHeight: cellWidth * 1.33
            model: telefam.savedVideos
            delegate: Item {
                width: GridView.view.cellWidth; height: GridView.view.cellHeight
                Rectangle {
                    anchors.fill: parent; anchors.margins: 4; radius: 8; color: "#16181D"; clip: true
                    Image { anchors.fill: parent; source: telefam.resolveMediaUrl(modelData.thumbnail_url || ""); fillMode: Image.PreserveAspectCrop }
                    Row {
                        anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: 6; spacing: 4
                        Image { source: "qrc:/telefam/icons/ic_play.svg"; sourceSize.width: 11; sourceSize.height: 11; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: telefam.formatFeedCount(Number(modelData.views_count || 0)); color: "#FFFFFF"; font.pixelSize: 11; font.bold: true }
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            savedVideosDialog.close()
                            telefam.openModalFeedPlayer(telefam.savedVideos, index, "Saved videos")
                        }
                    }
                }
            }
        }
    }

    Dialog {
        id: safetyPrefsDialog
        title: "Muted & Blocked"
        modal: true
        anchors.centerIn: parent
        width: 440
        height: 440
        standardButtons: Dialog.Close

        ColumnLayout {
            anchors.fill: parent
            spacing: 10

            Text { text: "Muted"; color: inkCol; font.bold: true; font.pixelSize: 14 }
            ListView {
                Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: 6
                model: telefam.safetyPreferences.muted_users || []
                delegate: Rectangle {
                    width: ListView.view.width; height: 48; radius: 10; color: cardBg
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10
                        Text { text: (modelData.full_name || modelData.username || "") + " (@" + (modelData.username || "") + ")"; color: inkCol; Layout.fillWidth: true; elide: Text.ElideRight }
                        Button { text: "Unmute"; onClicked: telefam.unmuteUserFromSafety(modelData.user_id || "") }
                    }
                }
            }

            Text { text: "Blocked"; color: inkCol; font.bold: true; font.pixelSize: 14 }
            ListView {
                Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: 6
                model: telefam.safetyPreferences.blocked_users || []
                delegate: Rectangle {
                    width: ListView.view.width; height: 48; radius: 10; color: cardBg
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10
                        Text { text: (modelData.full_name || modelData.username || "") + " (@" + (modelData.username || "") + ")"; color: inkCol; Layout.fillWidth: true; elide: Text.ElideRight }
                        Button { text: "Unblock"; onClicked: telefam.unblockUserFromSafety(modelData.user_id || "") }
                    }
                }
            }
        }
    }

    FeedDiscoveryView {
        anchors.fill: parent
        z: 9
    }

    PostCreatorView {
        anchors.fill: parent
        visible: telefam.postComposerOpen
        z: 10
    }
}
