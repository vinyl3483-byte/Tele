import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts

Item {
    id: profileRoot
    readonly property color brandRed: "#C81010"
    readonly property color sheetBg: telefam.isDarkTheme ? "#1B1D22" : "#FFFFFF"
    readonly property color borderCol: telefam.isDarkTheme ? "#2B2F38" : "#E5E7EB"
    readonly property color inkCol: telefam.isDarkTheme ? "#FFFFFF" : "#111827"
    readonly property color subCol: telefam.isDarkTheme ? "#9CA3AF" : "#6B7280"

    focus: true
    Keys.onEscapePressed: {
        if (telefam.isEditingProfile) telefam.closeEditProfile()
        else telefam.signOut()
    }

    property var countryList: [
        { iso: "KE", label: "🇰🇪 Kenya (+254)" },
        { iso: "US", label: "🇺🇸 United States (+1)" },
        { iso: "GB", label: "🇬🇧 United Kingdom (+44)" },
        { iso: "CA", label: "🇨🇦 Canada (+1)" },
        { iso: "NG", label: "🇳🇬 Nigeria (+234)" },
        { iso: "ZA", label: "🇿🇦 South Africa (+27)" },
        { iso: "TZ", label: "🇹🇿 Tanzania (+255)" },
        { iso: "UG", label: "🇺🇬 Uganda (+256)" },
        { iso: "RW", label: "🇷🇼 Rwanda (+250)" },
        { iso: "ET", label: "🇪🇹 Ethiopia (+251)" },
        { iso: "IN", label: "🇮🇳 India (+91)" },
        { iso: "DE", label: "🇩🇪 Germany (+49)" },
        { iso: "FR", label: "🇫🇷 France (+33)" },
        { iso: "AE", label: "🇦🇪 UAE (+971)" },
        { iso: "AU", label: "🇦🇺 Australia (+61)" },
        { iso: "JP", label: "🇯🇵 Japan (+81)" },
        { iso: "BR", label: "🇧🇷 Brazil (+55)" }
    ]

    property var genderKeys: ["male", "female", "non_binary", "prefer_not_to_say"]
    property url pendingImageUrl: ""

    function selectedCountryIndex() {
        for (var i = 0; i < countryList.length; i++) {
            if (countryList[i].iso === telefam.profileCountryIso) return i
        }
        return 0
    }

    Rectangle {
        anchors.fill: parent
        color: brandRed
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Top Red Header
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 68

            Button {
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                width: 48
                height: 48
                flat: true
                contentItem: Image {
                    source: "qrc:/telefam/icons/ic_back_white.svg"
                    sourceSize.width: 22
                    sourceSize.height: 22
                    fillMode: Image.PreserveAspectFit
                }
                onClicked: {
                    if (telefam.isEditingProfile) telefam.closeEditProfile()
                    else telefam.signOut()
                }
            }

            Column {
                anchors.centerIn: parent
                spacing: 2
                Text {
                    text: "Profile Setup"
                    font.pixelSize: 20
                    font.bold: true
                    color: "#FFFFFF"
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                Text {
                    text: "Tell us about yourself"
                    font.pixelSize: 13
                    color: "#FCE8E8"
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }

        // Rounded Sheet Body
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: sheetBg
            topLeftRadius: 24
            topRightRadius: 24

            ScrollView {
                anchors.fill: parent
                contentWidth: availableWidth

                ColumnLayout {
                    width: Math.min(parent.width - 48, 620)
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 14

                    Item { Layout.preferredHeight: 14 }

                    // Avatar Picker
                    Item {
                        Layout.alignment: Qt.AlignHCenter
                        width: 100
                        height: 100

                        Rectangle {
                            width: 96
                            height: 96
                            radius: 48
                            color: telefam.isDarkTheme ? "#2B1517" : "#FCE8E8"
                            border.color: brandRed
                            border.width: 2
                            clip: true

                            Image {
                                anchors.fill: parent
                                visible: telefam.avatarDataUrl.length > 0
                                source: telefam.avatarDataUrl
                                fillMode: Image.PreserveAspectCrop
                            }

                            Image {
                                visible: telefam.avatarDataUrl.length === 0
                                anchors.centerIn: parent
                                source: "qrc:/telefam/icons/ic_camera.svg"
                                sourceSize.width: 34
                                sourceSize.height: 34
                            }
                        }

                        Rectangle {
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            width: 28
                            height: 28
                            radius: 14
                            color: brandRed
                            border.color: sheetBg
                            border.width: 2
                            Image {
                                anchors.centerIn: parent
                                source: "qrc:/telefam/icons/ic_plus_white.svg"
                                sourceSize.width: 16
                                sourceSize.height: 16
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: avatarFileDialog.open()
                        }
                    }

                    Text {
                        text: "Upload Profile Photo"
                        font.pixelSize: 16
                        font.bold: true
                        color: inkCol
                        Layout.alignment: Qt.AlignHCenter
                    }

                    Text {
                        text: "Add a clear photo to help your friends recognize you."
                        font.pixelSize: 13
                        color: subCol
                        Layout.alignment: Qt.AlignHCenter
                    }

                    // Desktop Two-Column Arranged Form Grid
                    GridLayout {
                        Layout.fillWidth: true
                        columns: parent.width > 500 ? 2 : 1
                        columnSpacing: 16
                        rowSpacing: 12

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Text { text: "Full Name"; font.bold: true; color: inkCol; font.pixelSize: 13 }
                            TextField {
                                id: fullNameField
                                Layout.fillWidth: true
                                Layout.preferredHeight: 46
                                text: telefam.profileFullName
                                placeholderText: "Enter your full name"
                                color: inkCol
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Text { text: "Username"; font.bold: true; color: inkCol; font.pixelSize: 13 }
                            TextField {
                                id: usernameField
                                Layout.fillWidth: true
                                Layout.preferredHeight: 46
                                text: telefam.profileUsername
                                placeholderText: "Choose a username"
                                color: inkCol
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Text { text: "Phone Number"; font.bold: true; color: inkCol; font.pixelSize: 13 }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                ComboBox {
                                    id: countryCombo
                                    Layout.preferredWidth: 145
                                    Layout.preferredHeight: 46
                                    model: countryList
                                    textRole: "label"
                                    currentIndex: selectedCountryIndex()
                                }
                                TextField {
                                    id: phoneField
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 46
                                    text: telefam.isEditingProfile && telefam.myProfile.phone_number ? telefam.myProfile.phone_number : ""
                                    placeholderText: "Enter your phone number"
                                    color: inkCol
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Text { text: "Gender"; font.bold: true; color: inkCol; font.pixelSize: 13 }
                            ComboBox {
                                id: genderCombo
                                Layout.fillWidth: true
                                Layout.preferredHeight: 46
                                model: ["Male", "Female", "Non-binary", "Prefer not to say"]
                                currentIndex: {
                                    if (!telefam.isEditingProfile || !telefam.myProfile.gender) return 0
                                    var idx = genderKeys.indexOf(telefam.myProfile.gender)
                                    return idx >= 0 ? idx : 0
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Text { text: "Date of Birth (13+ only)"; font.bold: true; color: inkCol; font.pixelSize: 13 }
                            TextField {
                                id: dobField
                                Layout.fillWidth: true
                                Layout.preferredHeight: 46
                                text: telefam.isEditingProfile && telefam.myProfile.date_of_birth ? telefam.myProfile.date_of_birth : ""
                                placeholderText: "YYYY-MM-DD"
                                color: inkCol
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Text { text: "Location"; font.bold: true; color: inkCol; font.pixelSize: 13 }
                            TextField {
                                id: locationField
                                Layout.fillWidth: true
                                Layout.preferredHeight: 46
                                text: telefam.profileLocation
                                placeholderText: "City, Country"
                                color: inkCol
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Text { text: "Bio"; font.bold: true; color: inkCol; font.pixelSize: 13 }
                        TextArea {
                            id: bioField
                            Layout.fillWidth: true
                            Layout.preferredHeight: 92
                            text: telefam.isEditingProfile && telefam.myProfile.bio ? telefam.myProfile.bio : ""
                            placeholderText: "Tell us something about yourself..."
                            color: inkCol
                            wrapMode: Text.Wrap
                            onTextChanged: {
                                if (text.length > 150) text = text.slice(0, 150)
                            }
                        }
                        Text {
                            text: bioField.text.length + "/150"
                            font.pixelSize: 11
                            color: subCol
                            Layout.alignment: Qt.AlignRight
                        }
                    }

                    Text {
                        visible: telefam.errorMessage.length > 0
                        text: telefam.errorMessage
                        color: brandRed
                        font.pixelSize: 12
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 6
                        Layout.bottomMargin: 24
                        spacing: 12

                        Button {
                            text: "Back"
                            Layout.preferredWidth: 120
                            Layout.preferredHeight: 50
                            background: Rectangle {
                                color: "transparent"
                                border.color: borderCol
                                radius: 12
                            }
                            contentItem: Text {
                                text: parent.text
                                color: inkCol
                                font.bold: true
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            onClicked: {
                                if (telefam.isEditingProfile) telefam.closeEditProfile()
                                else telefam.signOut()
                            }
                        }

                        Button {
                            text: telefam.loading ? "Saving..." : "Continue"
                            enabled: !telefam.loading
                            Layout.fillWidth: true
                            Layout.preferredHeight: 50
                            background: Rectangle {
                                color: brandRed
                                radius: 12
                            }
                            contentItem: Text {
                                text: parent.text
                                color: "#FFFFFF"
                                font.bold: true
                                font.pixelSize: 15
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            onClicked: {
                                var cIso = countryList[countryCombo.currentIndex].iso
                                var gKey = genderKeys[genderCombo.currentIndex]
                                telefam.submitProfileSetup(
                                    fullNameField.text,
                                    usernameField.text,
                                    cIso,
                                    phoneField.text,
                                    gKey,
                                    dobField.text,
                                    locationField.text,
                                    bioField.text
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    FileDialog {
        id: avatarFileDialog
        title: "Choose Profile Photo"
        nameFilters: ["Images (*.png *.jpg *.jpeg *.webp)"]
        onAccepted: {
            pendingImageUrl = selectedFile
            cropDialog.open()
        }
    }

    Dialog {
        id: cropDialog
        title: "Adjust Photo"
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
                    id: previewImg
                    source: pendingImageUrl
                    anchors.centerIn: parent
                    width: 240 * zoomSlider.value
                    height: 240 * zoomSlider.value
                    x: (parent.width - width) / 2 + cropDialog.offX
                    y: (parent.height - height) / 2 + cropDialog.offY
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
                        cropDialog.offX += (mouse.x - lastX)
                        cropDialog.offY += (mouse.y - lastY)
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
            telefam.cropAndUploadAvatar(pendingImageUrl, zoomSlider.value, cropDialog.offX / 240.0, cropDialog.offY / 240.0)
        }
    }
}
