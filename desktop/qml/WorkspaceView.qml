import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: workspace
    readonly property color brandRed: "#C81010"
    readonly property color bodyBg: telefam.isDarkTheme ? "#121316" : "#FFFFFF"
    readonly property color cardBg: telefam.isDarkTheme ? "#1B1D22" : "#F9FAFB"
    readonly property color railBg: telefam.isDarkTheme ? "#16181C" : "#F3F4F6"
    readonly property color pillBg: telefam.isDarkTheme ? "#1E1F24" : "#A60B0B"
    readonly property color borderCol: telefam.isDarkTheme ? "#2B2F38" : "#E5E7EB"
    readonly property color inkCol: telefam.isDarkTheme ? "#FFFFFF" : "#111827"
    readonly property color subCol: telefam.isDarkTheme ? "#9CA3AF" : "#6B7280"

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
        color: brandRed
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Top Red Bar: Home search (Chats/Feeds/Profile) OR Contacts bar with Search + Filters
        ColumnLayout {
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
            topLeftRadius: telefam.activeTab === 1 ? 0 : 24
            topRightRadius: telefam.activeTab === 1 ? 0 : 24
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
                    Item {
                        visible: telefam.activeTab === 2
                        anchors.fill: parent

                        ColumnLayout {
                            visible: telefam.feedPosts.length === 0
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
                                    source: "qrc:/telefam/icons/ic_feeds.svg"
                                    sourceSize.width: 30
                                    sourceSize.height: 30
                                }
                            }
                            Text {
                                text: "No posts yet"
                                font.pixelSize: 20
                                font.bold: true
                                color: inkCol
                                Layout.alignment: Qt.AlignHCenter
                            }
                            Button {
                                text: "Create post"
                                Layout.alignment: Qt.AlignHCenter
                                Layout.preferredWidth: 160
                                Layout.preferredHeight: 46
                                background: Rectangle { color: brandRed; radius: 23 }
                                contentItem: Text {
                                    text: parent.text
                                    color: "#FFFFFF"
                                    font.bold: true
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                onClicked: telefam.openPostComposer()
                            }
                        }

                        ListView {
                            visible: telefam.feedPosts.length > 0
                            anchors.fill: parent
                            anchors.margins: 20
                            spacing: 12
                            clip: true
                            model: telefam.feedPosts
                            delegate: Rectangle {
                                width: Math.min(ListView.view.width, 680)
                                anchors.horizontalCenter: parent ? parent.horizontalCenter : undefined
                                height: feedCardCol.implicitHeight + 28
                                radius: 16
                                color: cardBg
                                border.color: borderCol
                                border.width: 1

                                ColumnLayout {
                                    id: feedCardCol
                                    anchors.fill: parent
                                    anchors.margins: 14
                                    spacing: 8

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 10
                                        Rectangle {
                                            width: 38
                                            height: 38
                                            radius: 19
                                            color: telefam.isDarkTheme ? "#2C1618" : "#FCE8E8"
                                            Text {
                                                anchors.centerIn: parent
                                                text: ((modelData.author_name || "T").slice(0, 1)).toUpperCase()
                                                color: brandRed
                                                font.bold: true
                                            }
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 1
                                            Text {
                                                text: modelData.author_name || modelData.author_handle || "User"
                                                color: inkCol
                                                font.bold: true
                                                font.pixelSize: 14
                                            }
                                            Text {
                                                visible: (modelData.author_handle || "").length > 0
                                                text: "@" + (modelData.author_handle || "")
                                                color: subCol
                                                font.pixelSize: 12
                                            }
                                        }
                                        Rectangle {
                                            height: 24
                                            width: typeLbl.implicitWidth + 18
                                            radius: 12
                                            color: telefam.isDarkTheme ? "#2C1618" : "#FCE8E8"
                                            Text {
                                                id: typeLbl
                                                anchors.centerIn: parent
                                                text: modelData.post_type || "text"
                                                color: brandRed
                                                font.bold: true
                                                font.pixelSize: 11
                                            }
                                        }
                                    }

                                    Text {
                                        visible: (modelData.body || "").length > 0
                                        Layout.fillWidth: true
                                        text: modelData.body || ""
                                        color: inkCol
                                        font.pixelSize: 14
                                        wrapMode: Text.Wrap
                                    }

                                    Text {
                                        visible: (modelData.song_title || "").length > 0
                                        text: (modelData.song_title || "") + ((modelData.song_artist || "").length > 0 ? " - " + modelData.song_artist : "")
                                        color: brandRed
                                        font.pixelSize: 12
                                        font.bold: true
                                    }
                                }
                            }
                        }
                    }

                    // Profile Overview Tab (activeTab === 3)
                    ScrollView {
                        visible: telefam.activeTab === 3
                        anchors.fill: parent
                        contentWidth: availableWidth

                        ColumnLayout {
                            width: Math.min(parent.width - 48, 520)
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 16

                            Item { Layout.preferredHeight: 16 }

                            Rectangle {
                                Layout.fillWidth: true
                                height: profileCardCol.implicitHeight + 40
                                radius: 18
                                color: cardBg
                                border.color: borderCol
                                border.width: 1

                                ColumnLayout {
                                    id: profileCardCol
                                    anchors.fill: parent
                                    anchors.margins: 20
                                    spacing: 10

                                    Rectangle {
                                        Layout.alignment: Qt.AlignHCenter
                                        width: 80
                                        height: 80
                                        radius: 40
                                        color: telefam.isDarkTheme ? "#2C1618" : "#FCE8E8"
                                        border.color: brandRed
                                        border.width: 2
                                        Text {
                                            anchors.centerIn: parent
                                            readonly property string dn: telefam.myProfile.full_name || telefam.profileFullName || telefam.email || "TF"
                                            text: dn.slice(0, 2).toUpperCase()
                                            color: brandRed
                                            font.bold: true
                                            font.pixelSize: 22
                                        }
                                    }

                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: telefam.myProfile.full_name || telefam.profileFullName || "Telefam User"
                                        color: inkCol
                                        font.bold: true
                                        font.pixelSize: 20
                                    }

                                    Text {
                                        visible: (telefam.myProfile.username || telefam.profileUsername || "").length > 0
                                        Layout.alignment: Qt.AlignHCenter
                                        text: "@" + (telefam.myProfile.username || telefam.profileUsername || "")
                                        color: subCol
                                        font.pixelSize: 14
                                    }

                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: telefam.myProfile.email || telefam.email
                                        color: subCol
                                        font.pixelSize: 13
                                    }

                                    Text {
                                        visible: (telefam.myProfile.bio || "").length > 0
                                        Layout.fillWidth: true
                                        horizontalAlignment: Text.AlignHCenter
                                        text: telefam.myProfile.bio || ""
                                        color: inkCol
                                        font.pixelSize: 14
                                        wrapMode: Text.Wrap
                                    }

                                    Text {
                                        visible: (telefam.myProfile.location || "").length > 0
                                        Layout.alignment: Qt.AlignHCenter
                                        text: telefam.myProfile.location || ""
                                        color: subCol
                                        font.pixelSize: 13
                                    }
                                }
                            }

                            Button {
                                text: "Edit profile"
                                Layout.fillWidth: true
                                Layout.preferredHeight: 48
                                background: Rectangle { color: brandRed; radius: 12 }
                                contentItem: Text {
                                    text: parent.text
                                    color: "#FFFFFF"
                                    font.bold: true
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                onClicked: telefam.openEditProfile()
                            }

                            Button {
                                text: "Sync"
                                Layout.fillWidth: true
                                Layout.preferredHeight: 48
                                background: Rectangle {
                                    color: cardBg
                                    radius: 12
                                    border.color: borderCol
                                    border.width: 1
                                }
                                contentItem: Text {
                                    text: parent.text
                                    color: inkCol
                                    font.bold: true
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                onClicked: telefam.syncNow()
                            }

                            Button {
                                text: "Sign out"
                                Layout.fillWidth: true
                                Layout.preferredHeight: 48
                                background: Rectangle {
                                    color: cardBg
                                    radius: 12
                                    border.color: brandRed
                                    border.width: 1
                                }
                                contentItem: Text {
                                    text: parent.text
                                    color: brandRed
                                    font.bold: true
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                onClicked: telefam.signOut()
                            }
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        visible: telefam.toastMessage.length > 0
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

    PostCreatorView {
        anchors.fill: parent
        visible: telefam.postComposerOpen
        z: 10
    }
}
