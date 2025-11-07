import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    property var expandedContainers: ({})
    property int refreshInterval: pluginData.refreshInterval || 5000
    property string terminalApp: pluginData.terminalApp || "alacritty --hold"
    property string shellPath: pluginData.shellPath || "/bin/sh"

    PluginGlobalVar {
        id: globalDockerAvailable
        varName: "dockerAvailable"
        defaultValue: false
    }

    PluginGlobalVar {
        id: globalContainers
        varName: "containers"
        defaultValue: []
    }

    PluginGlobalVar {
        id: globalRunningContainers
        varName: "runningContainers"
        defaultValue: 0
    }

    DockerService {
        id: dockerService
        refreshInterval: root.refreshInterval
    }

    function toggleContainer(containerName) {
        let expanded = root.expandedContainers;
        expanded[containerName] = !expanded[containerName];
        root.expandedContainers = expanded;
        root.expandedContainersChanged();
    }

    function executeAction(containerId, action) {
        if (dockerService.executeAction(containerId, action)) {
            ToastService.showInfo("Executing " + action + " on container");
        }
    }

    function openLogs(containerId) {
        dockerService.openLogs(containerId, root.terminalApp);
    }

    function openExec(containerId) {
        dockerService.openExec(containerId, root.terminalApp, root.shellPath);
    }

    component DockerIcon: DankNFIcon {
        name: "docker"
        size: Theme.barIconSize(root.barThickness, -4)
        color: {
            if (!globalDockerAvailable.value) return Theme.error;
            if (globalRunningContainers.value > 0) return Theme.primary;
            return Theme.surfaceText;
        }
    }

    component DockerCount: StyledText {
        text: globalRunningContainers.value.toString()
        font.pixelSize: Theme.fontSizeMedium
        color: Theme.surfaceText
        visible: globalRunningContainers.value > 0
    }

    horizontalBarPill: Row {
        spacing: Theme.spacingXS

        DockerIcon {
            anchors.verticalCenter: parent.verticalCenter
        }

        DockerCount {
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    verticalBarPill: Column {
        spacing: Theme.spacingXS

        DockerIcon {
            anchors.horizontalCenter: parent.horizontalCenter
        }

        DockerCount {
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }
    
    popoutContent: Component {
        PopoutComponent {
            id: popoutColumn

            headerText: "Docker Manager"
            detailsText: globalDockerAvailable.value ? `${globalRunningContainers.value} running containers` : "Docker not available"
            showCloseButton: true

            DankListView {
                id: containerList
                width: parent.width - 2 * Theme.spacingM
                height: root.popoutHeight - popoutColumn.headerHeight - popoutColumn.detailsHeight - Theme.spacingXL
                topMargin: Theme.spacingS
                bottomMargin: Theme.spacingS
                leftMargin: Theme.spacingM
                rightMargin: Theme.spacingM
                spacing: 2
                clip: true
                model: globalContainers.value

                delegate: Column {
                        id: containerDelegate
                        width: containerList.width
                        spacing: 0

                        property bool isExpanded: root.expandedContainers[modelData.name] || false

                        StyledRect {
                            width: parent.width
                            height: 48
                            radius: isExpanded ? Theme.cornerRadius : Theme.cornerRadius
                            color: containerHeaderMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
                            border.width: 0

                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: Theme.spacingM
                                anchors.rightMargin: Theme.spacingM
                                spacing: Theme.spacingM

                                DankIcon {
                                    name: "deployed_code"
                                    size: Theme.iconSize
                                    color: {
                                        if (modelData.isRunning) return Theme.primary;
                                        if (modelData.isPaused) return Theme.warning;
                                        return Theme.surfaceText;
                                    }
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Column {
                                  width: parent.width - 100
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 2

                                    StyledText {
                                        text: modelData.name
                                        font.pixelSize: Theme.fontSizeMedium
                                        font.weight: Font.Medium
                                        color: Theme.surfaceText
                                    }

                                    StyledText {
                                        text: modelData.image
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.surfaceVariantText
                                        elide: Text.ElideRight
                                        width: parent.width
                                    }
                                }

                                DankIcon {
                                    name: isExpanded ? "expand_less" : "expand_more"
                                    size: Theme.iconSize
                                    color: Theme.surfaceText
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            MouseArea {
                                id: containerHeaderMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.toggleContainer(modelData.name)
                            }
                        }

                        Column {
                            width: parent.width
                            visible: isExpanded
                            spacing: 0

                            ActionButton {
                                text: modelData.isRunning ? "Restart" : "Start"
                                icon: modelData.isRunning ? "refresh" : "play_arrow"
                                enabled: !modelData.isPaused
                                onTriggered: root.executeAction(modelData.id, modelData.isRunning ? "restart" : "start")
                            }

                            ActionButton {
                                text: modelData.isPaused ? "Unpause" : "Pause"
                                icon: "pause"
                                enabled: modelData.isRunning || modelData.isPaused
                                onTriggered: root.executeAction(modelData.id, modelData.isPaused ? "unpause" : "pause")
                            }

                            ActionButton {
                                text: "Stop"
                                icon: "stop"
                                enabled: modelData.isRunning || modelData.isPaused
                                onTriggered: root.executeAction(modelData.id, "stop")
                            }

                            ActionButton {
                                text: "Shell"
                                icon: "terminal"
                                enabled: modelData.isRunning
                                onTriggered: root.openExec(modelData.id)
                            }

                            ActionButton {
                                text: "Logs"
                                icon: "description"
                                onTriggered: root.openLogs(modelData.id)
                            }
                        }
                    }
                }

            component ActionButton: Rectangle {
                id: actionButton
                property string text: ""
                property string icon: ""
                property bool enabled: true
                signal triggered()

                width: parent.width
                height: 44
                radius: 0
                color: actionMouse.containsMouse ? Theme.surfaceContainerHighest : "transparent"
                border.width: 0
                opacity: enabled ? 1.0 : 0.5

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.spacingL + Theme.spacingM
                    spacing: Theme.spacingM

                    DankIcon {
                        name: actionButton.icon
                        size: Theme.iconSize
                        color: Theme.surfaceText
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: actionButton.text
                        font.pixelSize: Theme.fontSizeMedium
                        color: Theme.surfaceText
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
                    id: actionMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: actionButton.enabled ? Qt.PointingHandCursor : Qt.ForbiddenCursor
                    enabled: actionButton.enabled
                    onClicked: actionButton.triggered()
                }
            }
        }
    }

    popoutWidth: 400
    popoutHeight: 500
}
