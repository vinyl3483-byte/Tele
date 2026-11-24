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

    property string toastText: ""

    function showComingSoon() {
        toastText = "Coming soon"
        toastTimer.restart()
    }

    Timer {
        id: toastTimer
        interval: 1700
        onTriggered: toastText = ""
    }

    focus: true
    Keys.onEscapePressed: {
        if (telefam.selectedConversationId.length > 0) {
            telefam.selectConversation("")
        } else if (telefam.activeTab === 1) {
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

        // Top Red Bar: Chats bar OR Contacts bar with Search + Filters
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 62
                Layout.leftMargin: 18
                Layout.rightMargin: 18
                spacing: 12

                // Chats search bar placeholder (Coming soon)
                Rectangle {
                    visible: telefam.activeTab === 0
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
                        Text {
                            text: "Search chats, people, groups..."
                            color: "#D1D5DB"
                            font.pixelSize: 13
                            Layout.fillWidth: true
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: showComingSoon()
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

                // Theme Switcher Pill (Working Now)
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
                    visible: telefam.activeTab === 0
                    Layout.preferredWidth: 48
                    Layout.preferredHeight: 48
                    flat: true
                    contentItem: Image {
                        source: "qrc:/telefam/icons/ic_bell.svg"
                        sourceSize.width: 22
                        sourceSize.height: 22
                        fillMode: Image.PreserveAspectFit
                    }
                    onClicked: showComingSoon()
                }

                Button {
                    visible: telefam.activeTab === 0
                    Layout.preferredWidth: 48
                    Layout.preferredHeight: 48
                    flat: true
                    contentItem: Image {
                        source: "qrc:/telefam/icons/ic_more.svg"
                        sourceSize.width: 22
                        sourceSize.height: 22
                        fillMode: Image.PreserveAspectFit
                    }
                    onClicked: showComingSoon()
                }
            }

            // Contacts Filter Tabs Row matching reference screenshot
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

                // Left Navigation Rail with cleanly positioned buttons
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
                                Text { text: "Feeds"; color: subCol; font.pixelSize: 11; anchors.horizontalCenter: parent.horizontalCenter }
                            }
                            onClicked: showComingSoon()
                        }

                        Button {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: 74
                            Layout.preferredHeight: 54
                            flat: true
                            contentItem: Column {
                                spacing: 4
                                Image { source: "qrc:/telefam/icons/ic_profile.svg"; sourceSize.width: 20; sourceSize.height: 20; anchors.horizontalCenter: parent.horizontalCenter }
                                Text { text: "Profile"; color: subCol; font.pixelSize: 11; anchors.horizontalCenter: parent.horizontalCenter }
                            }
                            onClicked: showComingSoon()
                        }

                        Item { Layout.fillHeight: true }
                    }
                }

                Rectangle {
                    Layout.preferredWidth: 1
                    Layout.fillHeight: true
                    color: borderCol
                }

                // Contacts Grid OR Empty State OR Split-Pane Chats
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    ContactsView {
                        visible: telefam.activeTab === 1
                        anchors.fill: parent
                    }

                    // Empty Home matching Image 2
                    ColumnLayout {
                        visible: telefam.activeTab === 0 && telefam.conversations.length === 0
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
                        visible: telefam.activeTab === 0 && telefam.conversations.length > 0
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
                                    model: telefam.conversations
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
                }
            }
        }
    }

    Rectangle {
        readonly property string activeToast: telefam.toastMessage.length > 0 ? telefam.toastMessage : toastText
        visible: activeToast.length > 0
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
            text: parent.activeToast
            color: "#FFFFFF"
            font.bold: true
            font.pixelSize: 13
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
