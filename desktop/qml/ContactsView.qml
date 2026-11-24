import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: contactsRoot

    readonly property color brandRed: "#C81010"
    readonly property color bodyBg: telefam.isDarkTheme ? "#121316" : "#FFFFFF"
    readonly property color cardBg: telefam.isDarkTheme ? "#1B1D22" : "#FFFFFF"
    readonly property color borderCol: telefam.isDarkTheme ? "#2B2F38" : "#E5E7EB"
    readonly property color inkCol: telefam.isDarkTheme ? "#FFFFFF" : "#111827"
    readonly property color subCol: telefam.isDarkTheme ? "#9CA3AF" : "#6B7280"

    readonly property int gridColumns: width >= 980 ? 3 : (width >= 560 ? 2 : 1)

    function computeInitials(fullName) {
        if (!fullName) return "?"
        var parts = fullName.trim().split(/\s+/).filter(function(p) { return p.length > 0 })
        if (parts.length >= 2) return (parts[0][0] + parts[1][0]).toUpperCase()
        if (parts.length === 1) return parts[0].substring(0, 2).toUpperCase()
        return "?"
    }

    function formatHandle(username, location) {
        var h = "@" + (username || "")
        if (location && location.trim().length > 0) return h + " · " + location.trim()
        return h
    }

    Rectangle {
        anchors.fill: parent
        color: bodyBg
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 14

        Text {
            text: telefam.contactFilter.toUpperCase()
            font.pixelSize: 12
            font.bold: true
            font.letterSpacing: 0.8
            color: subCol
            Layout.fillWidth: true
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            BusyIndicator {
                anchors.centerIn: parent
                running: telefam.contactsLoading && telefam.contacts.length === 0
                visible: running
            }

            Text {
                anchors.centerIn: parent
                visible: !telefam.contactsLoading && telefam.contacts.length === 0
                text: "No contacts found"
                font.pixelSize: 15
                color: subCol
            }

            GridView {
                id: contactsGrid
                anchors.fill: parent
                visible: telefam.contacts.length > 0
                clip: true
                model: telefam.contacts
                cellWidth: Math.floor(width / contactsRoot.gridColumns)
                cellHeight: 92

                onAtYEndChanged: {
                    if (atYEnd && telefam.hasMoreContacts && !telefam.contactsLoading) {
                        telefam.loadMoreContacts()
                    }
                }

                delegate: Item {
                    width: contactsGrid.cellWidth
                    height: contactsGrid.cellHeight

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 6
                        radius: 16
                        color: cardBg
                        border.width: 1
                        border.color: borderCol

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16
                            spacing: 12

                            Rectangle {
                                Layout.preferredWidth: 48
                                Layout.preferredHeight: 48
                                radius: 24
                                color: telefam.isDarkTheme ? "#162B3D" : "#EAF2FA"

                                Text {
                                    anchors.centerIn: parent
                                    text: contactsRoot.computeInitials(modelData.full_name)
                                    font.pixelSize: 15
                                    font.bold: true
                                    color: telefam.isDarkTheme ? "#5FA8E8" : "#1D4ED8"
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                Text {
                                    text: modelData.full_name || ""
                                    font.pixelSize: 15
                                    font.bold: true
                                    color: inkCol
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                Text {
                                    text: contactsRoot.formatHandle(modelData.username, modelData.location)
                                    font.pixelSize: 13
                                    color: subCol
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }

                            Button {
                                readonly property string rel: modelData.relationship || "follow"
                                Layout.preferredHeight: 38
                                Layout.preferredWidth: Math.max(96, btnRow.implicitWidth + 32)
                                hoverEnabled: true

                                background: Rectangle {
                                    radius: 19
                                    color: parent.rel === "friends"
                                           ? (telefam.isDarkTheme ? "#1E1315" : "#FFF5F5")
                                           : (parent.rel === "following" ? "transparent" : brandRed)
                                    border.width: (parent.rel === "friends" || parent.rel === "following") ? 1 : 0
                                    border.color: parent.rel === "friends"
                                                  ? (telefam.isDarkTheme ? "#7D2323" : brandRed)
                                                  : borderCol
                                }

                                contentItem: Row {
                                    id: btnRow
                                    anchors.centerIn: parent
                                    spacing: 6

                                    Image {
                                        visible: modelData.relationship === "friends" || modelData.relationship === "follow" || modelData.relationship === "follow_back" || !modelData.relationship
                                        source: modelData.relationship === "friends"
                                                ? "qrc:/telefam/icons/ic_friends_red.svg"
                                                : "qrc:/telefam/icons/ic_person_add_white.svg"
                                        sourceSize.width: 15
                                        sourceSize.height: 15
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: {
                                            var r = modelData.relationship || "follow"
                                            if (r === "friends") return "Friends"
                                            if (r === "following") return "Following"
                                            if (r === "follow_back") return "Follow back"
                                            return "Follow"
                                        }
                                        font.pixelSize: 13
                                        font.bold: modelData.relationship !== "following"
                                        color: {
                                            var r = modelData.relationship || "follow"
                                            if (r === "friends") return telefam.isDarkTheme ? "#E05252" : brandRed
                                            if (r === "following") return subCol
                                            return "#FFFFFF"
                                        }
                                    }
                                }

                                onClicked: telefam.toggleFollow(modelData.user_id)
                            }
                        }
                    }
                }
            }
        }
    }
}
