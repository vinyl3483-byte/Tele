import QtQuick
import QtQuick.Controls

ApplicationWindow {
    id: root
    visible: true
    width: 1120
    height: 760
    minimumWidth: 520
    minimumHeight: 680
    title: "Telefam"
    color: telefam.isDarkTheme ? "#121316" : "#FFFFFF"

    Loader {
        anchors.fill: parent
        sourceComponent: !telefam.authenticated
            ? authComp
            : ((!telefam.profileCompleted || telefam.isEditingProfile) ? profileComp : workspaceComp)
    }

    Component {
        id: authComp
        AuthView {}
    }

    Component {
        id: profileComp
        ProfileSetupView {}
    }

    Component {
        id: workspaceComp
        WorkspaceView {}
    }
}
