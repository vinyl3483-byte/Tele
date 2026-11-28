import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: discoveryRoot
    readonly property color coral: "#FF2D55"

    // 1. Feed Search Overlay
    Rectangle {
        visible: telefam.feedSearchOpen
        anchors.fill: parent
        color: "#000000"
        z: 10

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // Header + Search Input
            RowLayout {
                Layout.fillWidth: true
                Layout.margins: 14
                spacing: 10

                Button {
                    Layout.preferredWidth: 44; Layout.preferredHeight: 44
                    flat: true
                    contentItem: Image { anchors.centerIn: parent; source: "qrc:/telefam/icons/ic_back_white.svg"; sourceSize.width: 20; sourceSize.height: 20 }
                    onClicked: telefam.closeFeedSearch()
                }

                Rectangle {
                    Layout.fillWidth: true; Layout.preferredHeight: 44; radius: 22
                    color: "#1AFFFFFF"
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 10; spacing: 8
                        Image { source: "qrc:/telefam/icons/ic_search.svg"; sourceSize.width: 17; sourceSize.height: 17 }
                        TextField {
                            id: feedSearchField
                            Layout.fillWidth: true
                            text: telefam.feedSearchQuery
                            color: "#FFFFFF"
                            placeholderText: "Search videos, hashtags, creators, sounds"
                            placeholderTextColor: "#80FFFFFF"
                            background: Item {}
                            onTextEdited: telefam.updateFeedSearchQuery(text)
                            onAccepted: telefam.executeFeedSearch(text, true)
                        }
                        Button {
                            visible: telefam.feedSearchQuery.length > 0
                            Layout.preferredWidth: 32; Layout.preferredHeight: 32
                            flat: true
                            contentItem: Image { anchors.centerIn: parent; source: "qrc:/telefam/icons/ic_close_white.svg"; sourceSize.width: 13; sourceSize.height: 13 }
                            onClicked: telefam.updateFeedSearchQuery("")
                        }
                    }
                }
            }

            // 4 Sub-Tabs: Videos, Hashtags, Creators, Sounds
            RowLayout {
                Layout.fillWidth: true
                spacing: 0
                Repeater {
                    model: ["Videos", "Hashtags", "Creators", "Sounds"]
                    delegate: Button {
                        readonly property bool sel: telefam.feedSearchTab === index
                        Layout.fillWidth: true; Layout.preferredHeight: 44
                        flat: true
                        contentItem: Column {
                            spacing: 6
                            Text {
                                text: modelData
                                color: sel ? "#FFFFFF" : "#99FFFFFF"
                                font.bold: sel; font.pixelSize: 14
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                            Rectangle {
                                width: 42; height: 2.5; radius: 1.25
                                color: sel ? coral : "transparent"
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                        }
                        onClicked: telefam.feedSearchTab = index
                    }
                }
            }
            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: "#1AFFFFFF" }

            // Recent Searches + Trending when query is blank
            ColumnLayout {
                visible: telefam.feedSearchQuery.trim().length === 0 && (telefam.localRecentSearches.length > 0 || (telefam.feedSearchResults.recent_searches || []).length > 0 || (telefam.feedSearchResults.trending || []).length > 0)
                Layout.fillWidth: true
                Layout.margins: 16
                spacing: 8

                RowLayout {
                    visible: telefam.localRecentSearches.length > 0 || (telefam.feedSearchResults.recent_searches || []).length > 0
                    Layout.fillWidth: true
                    Text { text: "Recent"; color: "#BFFFFFFF"; font.pixelSize: 13; font.bold: true; Layout.fillWidth: true }
                    Button {
                        flat: true; padding: 0
                        contentItem: Text { text: "Clear"; color: coral; font.pixelSize: 12; font.bold: true }
                        onClicked: telefam.clearAllSearchHistory()
                    }
                }

                Flow {
                    visible: (telefam.feedSearchResults.recent_searches || []).length > 0 || telefam.localRecentSearches.length > 0
                    Layout.fillWidth: true
                    spacing: 8
                    Repeater {
                        model: (telefam.feedSearchResults.recent_searches || []).length > 0
                            ? telefam.feedSearchResults.recent_searches
                            : telefam.localRecentSearches
                        delegate: Rectangle {
                            readonly property string itemQuery: (typeof modelData === "string") ? modelData : (modelData.query || "")
                            readonly property string itemId: (typeof modelData === "string") ? "" : (modelData.id || "")
                            height: 32; width: chipRow.implicitWidth + 20; radius: 16; color: "#1AFFFFFF"
                            Row {
                                id: chipRow
                                anchors.centerIn: parent; spacing: 8
                                Text {
                                    text: itemQuery; color: "#FFFFFF"; font.pixelSize: 12
                                    MouseArea { anchors.fill: parent; onClicked: telefam.updateFeedSearchQuery(itemQuery) }
                                }
                                Image {
                                    source: "qrc:/telefam/icons/ic_close_white.svg"; sourceSize.width: 10; sourceSize.height: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    MouseArea { anchors.fill: parent; onClicked: telefam.deleteRecentSearch(itemId, itemQuery) }
                                }
                            }
                        }
                    }
                }

                Text {
                    visible: (telefam.feedSearchResults.trending || []).length > 0
                    text: "Trending"; color: "#BFFFFFFF"; font.pixelSize: 13; font.bold: true
                }
                Flow {
                    visible: (telefam.feedSearchResults.trending || []).length > 0
                    Layout.fillWidth: true
                    spacing: 8
                    Repeater {
                        model: telefam.feedSearchResults.trending || []
                        delegate: Button {
                            height: 32
                            background: Rectangle { color: "#14FFFFFF"; radius: 16 }
                            contentItem: Text { text: modelData; color: "#FFFFFF"; font.pixelSize: 12; leftPadding: 10; rightPadding: 10; verticalAlignment: Text.AlignVCenter }
                            onClicked: telefam.updateFeedSearchQuery(modelData)
                        }
                    }
                }
            }

            // Tab 0: Videos Grid
            GridView {
                visible: telefam.feedSearchTab === 0
                Layout.fillWidth: true; Layout.fillHeight: true; Layout.margins: 10
                clip: true
                cellWidth: Math.max(150, width / Math.max(2, Math.floor(width / 170)))
                cellHeight: cellWidth * 1.33
                model: telefam.feedSearchResults.videos || []
                onAtYEndChanged: {
                    if (atYEnd && telefam.feedSearchResults.has_more) telefam.executeFeedSearch(telefam.feedSearchQuery, false)
                }
                delegate: Item {
                    width: GridView.view.cellWidth; height: GridView.view.cellHeight
                    Rectangle {
                        anchors.fill: parent; anchors.margins: 4; radius: 8; color: "#16181D"; clip: true
                        Image {
                            anchors.fill: parent
                            source: telefam.resolveMediaUrl(modelData.thumbnail_url || "")
                            fillMode: Image.PreserveAspectCrop
                        }
                        Rectangle {
                            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 48
                            gradient: Gradient { GradientStop { position: 0; color: "#00000000" } GradientStop { position: 1; color: "#B3000000" } }
                        }
                        Row {
                            anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: 8; spacing: 4
                            Image { source: "qrc:/telefam/icons/ic_play.svg"; sourceSize.width: 11; sourceSize.height: 11; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: telefam.formatFeedCount(Number(modelData.views_count || 0)); color: "#FFFFFF"; font.pixelSize: 11; font.bold: true }
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: telefam.openModalFeedPlayer(telefam.feedSearchResults.videos || [], index, telefam.feedSearchQuery.length > 0 ? telefam.feedSearchQuery : "Videos")
                        }
                    }
                }
            }

            // Tab 1: Hashtags List
            ListView {
                visible: telefam.feedSearchTab === 1
                Layout.fillWidth: true; Layout.fillHeight: true; Layout.margins: 14; spacing: 8; clip: true
                model: telefam.feedSearchResults.hashtags || []
                delegate: Button {
                    width: ListView.view.width; height: 60; flat: true
                    contentItem: RowLayout {
                        spacing: 12
                        Rectangle {
                            width: 42; height: 42; radius: 21; color: "#29FF2D55"
                            Text { anchors.centerIn: parent; text: "#"; color: coral; font.bold: true; font.pixelSize: 18 }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 2
                            Text { text: "#" + (modelData.tag || ""); color: "#FFFFFF"; font.bold: true; font.pixelSize: 15 }
                            Text { text: telefam.formatFeedCount(Number(modelData.post_count || 0)) + " videos"; color: "#99FFFFFF"; font.pixelSize: 12 }
                        }
                        Image { source: "qrc:/telefam/icons/ic_chevron_right.svg"; sourceSize.width: 14; sourceSize.height: 14 }
                    }
                    onClicked: telefam.openHashtagDiscovery(modelData.tag || "")
                }
            }

            // Tab 2: Creators List
            ListView {
                visible: telefam.feedSearchTab === 2
                Layout.fillWidth: true; Layout.fillHeight: true; Layout.margins: 14; spacing: 8; clip: true
                model: telefam.feedSearchResults.creators || []
                delegate: Rectangle {
                    width: ListView.view.width; height: 64; color: "transparent"
                    RowLayout {
                        anchors.fill: parent; spacing: 12
                        Rectangle {
                            width: 44; height: 44; radius: 22; color: "#24262C"
                            Text {
                                anchors.centerIn: parent
                                readonly property string dn: modelData.full_name || modelData.username || "U"
                                text: dn.slice(0, 2).toUpperCase(); color: "#FFFFFF"; font.bold: true
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 2
                            Text { text: modelData.full_name || modelData.username || ""; color: "#FFFFFF"; font.bold: true; font.pixelSize: 15 }
                            Text { text: "@" + (modelData.username || ""); color: "#99FFFFFF"; font.pixelSize: 12 }
                        }
                        Button {
                            Layout.preferredHeight: 34; Layout.preferredWidth: 96
                            background: Rectangle { color: modelData.is_following ? "#24FFFFFF" : coral; radius: 17 }
                            contentItem: Text {
                                text: modelData.is_following ? "Following" : "Follow"
                                color: "#FFFFFF"; font.bold: true; font.pixelSize: 13
                                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                            }
                            onClicked: {
                                telefam.toggleFollowCreator(modelData.user_id || "")
                            }
                        }
                    }
                }
            }

            // Tab 3: Sounds List
            ListView {
                visible: telefam.feedSearchTab === 3
                Layout.fillWidth: true; Layout.fillHeight: true; Layout.margins: 14; spacing: 8; clip: true
                model: telefam.feedSearchResults.audios || []
                delegate: Button {
                    width: ListView.view.width; height: 62; flat: true
                    contentItem: RowLayout {
                        spacing: 12
                        Rectangle {
                            width: 44; height: 44; radius: 10; color: "#29FF2D55"
                            Image { anchors.centerIn: parent; source: "qrc:/telefam/icons/ic_music_note.svg"; sourceSize.width: 20; sourceSize.height: 20 }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 2
                            Text { text: modelData.title || "Original sound"; color: "#FFFFFF"; font.bold: true; font.pixelSize: 15; elide: Text.ElideRight }
                            Text {
                                text: (modelData.artist || "Creator") + " · " + telefam.formatFeedCount(Number(modelData.usage_count || 0)) + " videos"
                                color: "#99FFFFFF"; font.pixelSize: 12
                            }
                        }
                        Image { source: "qrc:/telefam/icons/ic_chevron_right.svg"; sourceSize.width: 14; sourceSize.height: 14 }
                    }
                    onClicked: telefam.openAudioDiscovery(modelData.audio_id || "")
                }
            }
        }
    }

    // 2. Hashtag Discovery Overlay
    Rectangle {
        visible: telefam.activeHashtagTag.length > 0
        anchors.fill: parent
        color: "#000000"
        z: 11

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            RowLayout {
                Layout.fillWidth: true; Layout.margins: 14; spacing: 10
                Button {
                    Layout.preferredWidth: 44; Layout.preferredHeight: 44; flat: true
                    contentItem: Image { anchors.centerIn: parent; source: "qrc:/telefam/icons/ic_back_white.svg"; sourceSize.width: 20; sourceSize.height: 20 }
                    onClicked: telefam.closeHashtagDiscovery()
                }
                Text { text: "#" + telefam.activeHashtagTag; color: "#FFFFFF"; font.pixelSize: 18; font.bold: true; Layout.fillWidth: true }
            }

            RowLayout {
                Layout.fillWidth: true; Layout.leftMargin: 18; Layout.rightMargin: 18; Layout.bottomMargin: 14; spacing: 16
                Rectangle {
                    width: 64; height: 64; radius: 14; color: "#29FF2D55"
                    Text { anchors.centerIn: parent; text: "#"; color: coral; font.pixelSize: 30; font.bold: true }
                }
                ColumnLayout {
                    spacing: 4
                    Text { text: "#" + (telefam.hashtagDiscovery.tag || telefam.activeHashtagTag); color: "#FFFFFF"; font.pixelSize: 20; font.bold: true }
                    Text {
                        text: telefam.formatFeedCount(Number(telefam.hashtagDiscovery.video_count || 0)) + " videos · " +
                              telefam.formatFeedCount(Number(telefam.hashtagDiscovery.views_count || 0)) + " views"
                        color: "#B3FFFFFF"; font.pixelSize: 13
                    }
                }
            }

            GridView {
                Layout.fillWidth: true; Layout.fillHeight: true; Layout.margins: 10; clip: true
                cellWidth: Math.max(150, width / Math.max(2, Math.floor(width / 170)))
                cellHeight: cellWidth * 1.33
                model: telefam.hashtagDiscovery.videos || []
                onAtYEndChanged: {
                    if (atYEnd && telefam.hashtagDiscovery.has_more) telefam.loadMoreHashtagDiscovery()
                }
                delegate: Item {
                    width: GridView.view.cellWidth; height: GridView.view.cellHeight
                    Rectangle {
                        anchors.fill: parent; anchors.margins: 4; radius: 8; color: "#16181D"; clip: true
                        Image { anchors.fill: parent; source: telefam.resolveMediaUrl(modelData.thumbnail_url || ""); fillMode: Image.PreserveAspectCrop }
                        Row {
                            anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: 8; spacing: 4
                            Image { source: "qrc:/telefam/icons/ic_play.svg"; sourceSize.width: 11; sourceSize.height: 11; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: telefam.formatFeedCount(Number(modelData.views_count || 0)); color: "#FFFFFF"; font.pixelSize: 11; font.bold: true }
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: telefam.openModalFeedPlayer(telefam.hashtagDiscovery.videos || [], index, "#" + telefam.activeHashtagTag)
                        }
                    }
                }
            }
        }
    }

    // 3. Audio Discovery Overlay + "Use this sound"
    Rectangle {
        id: audioOverlay
        visible: telefam.activeAudioId.length > 0
        anchors.fill: parent
        color: "#000000"
        z: 12

        readonly property var aud: telefam.audioDiscovery.audio || ({})

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            RowLayout {
                Layout.fillWidth: true; Layout.margins: 14; spacing: 10
                Button {
                    Layout.preferredWidth: 44; Layout.preferredHeight: 44; flat: true
                    contentItem: Image { anchors.centerIn: parent; source: "qrc:/telefam/icons/ic_back_white.svg"; sourceSize.width: 20; sourceSize.height: 20 }
                    onClicked: telefam.closeAudioDiscovery()
                }
                Text { text: "Sound"; color: "#FFFFFF"; font.pixelSize: 18; font.bold: true; Layout.fillWidth: true }
            }

            ColumnLayout {
                Layout.fillWidth: true; Layout.leftMargin: 18; Layout.rightMargin: 18; Layout.bottomMargin: 14; spacing: 14
                RowLayout {
                    spacing: 14
                    Rectangle {
                        width: 72; height: 72; radius: 14; color: "#29FF2D55"; clip: true
                        Image {
                            visible: (audioOverlay.aud.artwork_url || "").length > 0
                            anchors.fill: parent
                            source: audioOverlay.aud.artwork_url || ""
                            fillMode: Image.PreserveAspectCrop
                        }
                        Image {
                            visible: (audioOverlay.aud.artwork_url || "").length === 0
                            anchors.centerIn: parent; source: "qrc:/telefam/icons/ic_music_note.svg"; sourceSize.width: 28; sourceSize.height: 28
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 4
                        Text { text: audioOverlay.aud.title || "Original sound"; color: "#FFFFFF"; font.pixelSize: 18; font.bold: true; wrapMode: Text.Wrap }
                        Text { visible: (audioOverlay.aud.artist || "").length > 0; text: audioOverlay.aud.artist || ""; color: "#B8FFFFFF"; font.pixelSize: 14 }
                        Text { text: telefam.formatFeedCount(Number(audioOverlay.aud.usage_count || 0)) + " videos"; color: "#99FFFFFF"; font.pixelSize: 12 }
                    }
                }

                Button {
                    Layout.fillWidth: true; Layout.maximumWidth: 320; Layout.preferredHeight: 46
                    background: Rectangle { color: coral; radius: 23 }
                    contentItem: Row {
                        anchors.centerIn: parent; spacing: 8
                        Image { anchors.verticalCenter: parent.verticalCenter; source: "qrc:/telefam/icons/ic_music_note.svg"; sourceSize.width: 16; sourceSize.height: 16 }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "Use this sound"; color: "#FFFFFF"; font.bold: true; font.pixelSize: 15 }
                    }
                    onClicked: telefam.useSoundInPostComposer(telefam.audioDiscovery.audio || ({}))
                }
            }

            GridView {
                Layout.fillWidth: true; Layout.fillHeight: true; Layout.margins: 10; clip: true
                cellWidth: Math.max(150, width / Math.max(2, Math.floor(width / 170)))
                cellHeight: cellWidth * 1.33
                model: telefam.audioDiscovery.videos || []
                onAtYEndChanged: {
                    if (atYEnd && telefam.audioDiscovery.has_more) telefam.loadMoreAudioDiscovery()
                }
                delegate: Item {
                    width: GridView.view.cellWidth; height: GridView.view.cellHeight
                    Rectangle {
                        anchors.fill: parent; anchors.margins: 4; radius: 8; color: "#16181D"; clip: true
                        Image { anchors.fill: parent; source: telefam.resolveMediaUrl(modelData.thumbnail_url || ""); fillMode: Image.PreserveAspectCrop }
                        Row {
                            anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: 8; spacing: 4
                            Image { source: "qrc:/telefam/icons/ic_play.svg"; sourceSize.width: 11; sourceSize.height: 11; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: telefam.formatFeedCount(Number(modelData.views_count || 0)); color: "#FFFFFF"; font.pixelSize: 11; font.bold: true }
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: telefam.openModalFeedPlayer(telefam.audioDiscovery.videos || [], index, (telefam.audioDiscovery.audio || ({})).title || "Sound")
                        }
                    }
                }
            }
        }
    }

    // 4. Full-Screen Modal Video Player
    FeedView {
        visible: telefam.modalFeedOpen
        anchors.fill: parent
        z: 13
        isStandaloneModal: true
        customVideosModel: telefam.modalFeedVideos
        customInitialIndex: telefam.modalFeedIndex
        customTitle: telefam.modalFeedTitle
        onRequestCloseModal: telefam.closeModalFeedPlayer()
    }

    // 5. LIVE Coming Soon Overlay
    Rectangle {
        visible: telefam.liveComingSoonOpen
        anchors.fill: parent
        color: "#000000"
        z: 14

        ColumnLayout {
            anchors.fill: parent
            RowLayout {
                Layout.fillWidth: true; Layout.margins: 14
                Button {
                    Layout.preferredWidth: 48; Layout.preferredHeight: 48; flat: true
                    contentItem: Image { anchors.centerIn: parent; source: "qrc:/telefam/icons/ic_back_white.svg"; sourceSize.width: 22; sourceSize.height: 22 }
                    onClicked: telefam.liveComingSoonOpen = false
                }
                Item { Layout.fillWidth: true }
            }
            Item { Layout.fillHeight: true }
            ColumnLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 14
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    width: 84; height: 84; radius: 42; color: "#29FF2D55"
                    Image { anchors.centerIn: parent; source: "qrc:/telefam/icons/ic_live_tv.svg"; sourceSize.width: 36; sourceSize.height: 36 }
                }
                Text { Layout.alignment: Qt.AlignHCenter; text: "LIVE Coming Soon"; color: "#FFFFFF"; font.pixelSize: 20; font.bold: true }
                Text { Layout.alignment: Qt.AlignHCenter; text: "Live streaming is not available yet."; color: "#B0FFFFFF"; font.pixelSize: 14 }
                Button {
                    Layout.alignment: Qt.AlignHCenter; Layout.preferredWidth: 140; Layout.preferredHeight: 44
                    background: Rectangle { color: coral; radius: 22 }
                    contentItem: Text { text: "Back"; color: "#FFFFFF"; font.bold: true; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    onClicked: telefam.liveComingSoonOpen = false
                }
            }
            Item { Layout.fillHeight: true }
        }
    }
}
