import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: authRoot
    readonly property color brandRed: "#C81010"
    readonly property color pageBg: telefam.isDarkTheme ? "#121316" : "#FFFFFF"
    readonly property color cardBg: telefam.isDarkTheme ? "#1B1D22" : "#FFFFFF"
    readonly property color borderCol: telefam.isDarkTheme ? "#2B2F38" : "#E5E7EB"
    readonly property color inkCol: telefam.isDarkTheme ? "#FFFFFF" : "#111827"
    readonly property color subCol: telefam.isDarkTheme ? "#9CA3AF" : "#6B7280"

    focus: true
    Keys.onEscapePressed: {
        if (telefam.authStep === 1) {
            telefam.changeEmail()
        }
    }

    function formatTime(sec) {
        var h = Math.floor(sec / 3600)
        var m = Math.floor((sec % 3600) / 60)
        var s = sec % 60
        var pad = function(n) { return (n < 10 ? "0" : "") + n }
        return h > 0 ? pad(h) + ":" + pad(m) + ":" + pad(s) : pad(m) + ":" + pad(s)
    }

    Rectangle {
        anchors.fill: parent
        color: pageBg
    }

    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 54
        color: brandRed
    }

    Rectangle {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 54
        color: brandRed
    }

    ScrollView {
        anchors.fill: parent
        contentWidth: availableWidth

        ColumnLayout {
            width: parent.width
            spacing: 12

            Item { Layout.preferredHeight: 40 }

            Image {
                source: "qrc:/telefam/icons/telefam_logo.svg"
                sourceSize.width: 72
                sourceSize.height: 72
                Layout.alignment: Qt.AlignHCenter
            }

            Text {
                text: "Telefam"
                font.pixelSize: 30
                font.bold: true
                color: brandRed
                Layout.alignment: Qt.AlignHCenter
            }

            Text {
                text: "Stay connected. Stay together."
                font.pixelSize: 13
                color: subCol
                Layout.alignment: Qt.AlignHCenter
            }

            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: Math.min(parent.width - 48, 420)
                Layout.topMargin: 10
                implicitHeight: cardCol.implicitHeight + 48
                radius: 20
                color: cardBg
                border.color: borderCol
                border.width: 1

                ColumnLayout {
                    id: cardCol
                    anchors.fill: parent
                    anchors.margins: 24
                    spacing: 14

                    // Step 0: Enter Email
                    ColumnLayout {
                        visible: telefam.authStep === 0
                        Layout.fillWidth: true
                        spacing: 12

                        Text {
                            text: "Enter Your Email"
                            font.pixelSize: 20
                            font.bold: true
                            color: brandRed
                            Layout.alignment: Qt.AlignHCenter
                        }

                        Text {
                            text: "Enter your email to get OTP"
                            font.pixelSize: 13
                            color: subCol
                            Layout.alignment: Qt.AlignHCenter
                        }

                        Text {
                            text: "Email"
                            font.pixelSize: 13
                            font.bold: true
                            color: inkCol
                        }

                        TextField {
                            id: emailField
                            Layout.fillWidth: true
                            Layout.preferredHeight: 48
                            placeholderText: "Enter your email"
                            text: telefam.email
                            color: inkCol
                            onTextChanged: telefam.email = text
                        }

                        Text {
                            visible: telefam.errorMessage.length > 0
                            text: telefam.errorMessage
                            color: brandRed
                            font.pixelSize: 12
                            wrapMode: Text.Wrap
                            Layout.fillWidth: true
                        }

                        Button {
                            text: telefam.loading ? "Sending..." : "Send OTP"
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
                            onClicked: telefam.sendOtp(false)
                        }
                    }

                    // Step 1: Enter OTP
                    ColumnLayout {
                        visible: telefam.authStep === 1
                        Layout.fillWidth: true
                        spacing: 12

                        Text {
                            text: "Enter OTP"
                            font.pixelSize: 20
                            font.bold: true
                            color: brandRed
                            Layout.alignment: Qt.AlignHCenter
                        }

                        Text {
                            text: "We sent a verification code to\n" + telefam.email
                            font.pixelSize: 13
                            color: inkCol
                            horizontalAlignment: Text.AlignHCenter
                            Layout.alignment: Qt.AlignHCenter
                        }

                        Text {
                            text: "Enter the 6-digit code or open the verification link in your email."
                            font.pixelSize: 12
                            color: subCol
                            wrapMode: Text.Wrap
                            horizontalAlignment: Text.AlignHCenter
                            Layout.fillWidth: true
                        }

                        TextField {
                            id: otpField
                            Layout.fillWidth: true
                            Layout.preferredHeight: 50
                            maximumLength: 6
                            horizontalAlignment: Text.AlignHCenter
                            font.pixelSize: 22
                            font.letterSpacing: 12
                            color: inkCol
                            placeholderText: "••••••"
                        }

                        Text {
                            visible: telefam.errorMessage.length > 0
                            text: telefam.errorMessage
                            color: brandRed
                            font.pixelSize: 12
                            wrapMode: Text.Wrap
                            Layout.fillWidth: true
                        }

                        Button {
                            text: telefam.loading ? "Verifying..." : "Verify OTP"
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
                            onClicked: telefam.verifyOtp(otpField.text, "")
                        }

                        Text {
                            visible: telefam.cooldownSeconds > 0
                            text: "Resend code in " + formatTime(telefam.cooldownSeconds) +
                                  "\nAfter " + formatTime(telefam.cooldownSeconds) + " you can Resend code"
                            font.pixelSize: 12
                            color: subCol
                            horizontalAlignment: Text.AlignHCenter
                            Layout.alignment: Qt.AlignHCenter
                        }

                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 16

                            Button {
                                visible: telefam.cooldownSeconds === 0
                                text: "Resend code"
                                flat: true
                                contentItem: Text {
                                    text: parent.text
                                    color: brandRed
                                    font.bold: true
                                }
                                onClicked: telefam.sendOtp(true)
                            }

                            Button {
                                text: "Change email"
                                flat: true
                                contentItem: Text {
                                    text: parent.text
                                    color: brandRed
                                    font.bold: true
                                }
                                onClicked: telefam.changeEmail()
                            }
                        }
                    }
                }
            }
        }
    }
}
