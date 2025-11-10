import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    property var expandedContainers: ({})
    property var expandedProjects: ({})
    property bool groupByCompose: pluginData.groupByCompose || false
    property bool showPorts: pluginData.showPorts !== undefined ? pluginData.showPorts : true

    Component.onCompleted: {
        // Note: the import of DockerService here is necessary because Singletons are lazy-loaded in QML.
        console.log(DockerService.pluginId, "loaded.");
    }

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

    PluginGlobalVar {
        id: globalComposeProjects
        varName: "composeProjects"
        defaultValue: []
        onValueChanged: {
            if (globalComposeProjects.value.length === 0 && root.groupByCompose) {
                root.groupByCompose = false;
                root.pluginService?.savePluginData("dockerManager", "groupByCompose", false);
            }
        }
    }

    function toggleContainer(containerId) {
        let expanded = root.expandedContainers;
        expanded[containerId] = !expanded[containerId];
        root.expandedContainers = expanded;
        root.expandedContainersChanged();
    }

    function toggleProject(projectName) {
        let expanded = root.expandedProjects;
        expanded[projectName] = !expanded[projectName];
        root.expandedProjects = expanded;
        root.expandedProjectsChanged();
    }

    function toggleGroupMode() {
        root.groupByCompose = !root.groupByCompose;
        pluginService?.savePluginData("dockerManager", "groupByCompose", root.groupByCompose);
    }

    function executeAction(containerId, action) {
        if (DockerService.executeAction(containerId, action)) {
            ToastService.showInfo("Executing " + action + " on container");
        }
    }

    function executeComposeAction(workingDir, configFile, action) {
        if (DockerService.executeComposeAction(workingDir, configFile, action)) {
            ToastService.showInfo("Executing " + action + " on project");
        }
    }

    function openLogs(containerId) {
        DockerService.openLogs(containerId);
    }

    function openExec(containerId) {
        DockerService.openExec(containerId);
    }

    component DockerIcon: DankNFIcon {
        name: "docker"
        size: Theme.barIconSize(root.barThickness, -4)
        color: {
            if (!globalDockerAvailable.value)
                return Theme.error;
            if (globalRunningContainers.value > 0)
                return Theme.primary;
            return Theme.surfaceText;
        }
    }

    component DockerCount: StyledText {
        text: globalRunningContainers.value.toString()
        font.pixelSize: Theme.fontSizeMedium
        color: Theme.surfaceText
        visible: globalRunningContainers.value > 0
    }

    component ProjectHeader: StyledRect {
        id: projectHeader
        property string projectName: ""
        property int runningCount: 0
        property int totalCount: 0
        property int serviceCount: 0
        property bool isExpanded: false
        signal clicked

        width: parent.width
        height: 52
        radius: Theme.cornerRadius
        color: projectMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
        border.width: 0

        DankIcon {
            name: "account_tree"
            size: Theme.iconSize + 2
            color: {
                if (projectHeader.runningCount === projectHeader.totalCount && projectHeader.totalCount > 0)
                    return Theme.primary;
                if (projectHeader.runningCount > 0)
                    return Theme.warning;
                return Theme.surfaceText;
            }
            anchors.left: parent.left
            anchors.leftMargin: Theme.spacingM
            anchors.verticalCenter: parent.verticalCenter
        }

        Column {
            anchors.left: parent.left
            anchors.leftMargin: Theme.spacingM * 2 + Theme.iconSize + 2
            anchors.right: parent.right
            anchors.rightMargin: Theme.spacingM * 2 + Theme.iconSize
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3

            StyledText {
                text: projectHeader.projectName
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Bold
                color: Theme.surfaceText
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
                width: parent.width
            }

            Row {
                spacing: Theme.spacingS

                StyledText {
                    text: `${projectHeader.runningCount}/${projectHeader.totalCount} running`
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                }

                StyledText {
                    text: "•"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    visible: projectHeader.serviceCount > 0
                }

                StyledText {
                    text: `${projectHeader.serviceCount} service${projectHeader.serviceCount !== 1 ? 's' : ''}`
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    visible: projectHeader.serviceCount > 0
                }
            }
        }

        DankIcon {
            name: isExpanded ? "expand_less" : "expand_more"
            size: Theme.iconSize
            color: Theme.surfaceText
            anchors.right: parent.right
            anchors.rightMargin: Theme.spacingM
            anchors.verticalCenter: parent.verticalCenter
        }

        MouseArea {
            id: projectMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: projectHeader.clicked()
        }
    }

    component ContainerHeader: StyledRect {
        id: containerHeader
        property var containerData: null
        property bool useComposeServiceName: false
        property bool isExpanded: false
        property real leftIndent: Theme.spacingM
        property real iconSize: Theme.iconSize
        property real baseHeight: 48
        property color defaultColor: Theme.surfaceContainerHigh
        property color hoverColor: Theme.surfaceContainerHighest
        signal clicked

        width: parent.width
        height: baseHeight + (isExpanded && root.showPorts && containerData?.ports?.length > 0 ? Theme.spacingS + portFlow.height + Theme.spacingXS : 0)
        radius: Theme.cornerRadius
        color: headerMouse.containsMouse ? hoverColor : defaultColor
        border.width: 0

        Behavior on height {
            NumberAnimation {
                duration: Theme.expressiveDurations["expressiveFastSpatial"]
                easing.type: Theme.standardEasing
            }
        }

        DankIcon {
            id: containerIcon
            name: "deployed_code"
            size: containerHeader.iconSize
            color: {
                if (containerData?.isPaused)
                    return Theme.warning;
                if (containerData?.isRunning)
                    return Theme.primary;
                return Theme.surfaceText;
            }
            anchors.left: parent.left
            anchors.leftMargin: containerHeader.leftIndent
            anchors.top: parent.top
            anchors.topMargin: (containerHeader.baseHeight - containerIcon.height) / 2
        }

        Column {
            id: headerTextColumn
            anchors.left: parent.left
            anchors.leftMargin: containerHeader.leftIndent + containerHeader.iconSize + Theme.spacingM
            anchors.right: expandIcon.left
            anchors.rightMargin: Theme.spacingM
            anchors.top: parent.top
            anchors.topMargin: (containerHeader.baseHeight - headerTextColumn.height) / 2
            spacing: 2

            StyledText {
                text: (useComposeServiceName && containerData?.composeService ? containerData?.composeService : containerData?.name) || ""
                font.pixelSize: containerHeader.baseHeight >= 48 ? Theme.fontSizeMedium : Theme.fontSizeSmall
                font.weight: Font.Medium
                color: Theme.surfaceText
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
                width: parent.width
            }

            StyledText {
                text: containerData?.image || ""
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
                width: parent.width
            }
        }

        Flow {
            id: portFlow
            anchors.left: parent.left
            anchors.leftMargin: containerHeader.leftIndent
            anchors.right: parent.right
            anchors.rightMargin: containerHeader.leftIndent
            anchors.top: headerTextColumn.bottom
            anchors.topMargin: Theme.spacingS
            spacing: Theme.spacingXS
            visible: isExpanded && root.showPorts && containerData?.ports?.length > 0
            opacity: isExpanded && root.showPorts && containerData?.ports?.length > 0 ? 1 : 0

            Behavior on opacity {
                NumberAnimation {
                    duration: Theme.expressiveDurations["expressiveEffects"]
                    easing.type: Theme.standardEasing
                }
            }

            Repeater {
                model: containerData?.ports || []

                StyledRect {
                    height: 24
                    width: portContent.width + Theme.spacingM
                    radius: 12
                    color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                    border.width: 1
                    border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.3)

                    Row {
                        id: portContent
                        anchors.centerIn: parent
                        spacing: Theme.spacingXS

                        DankIcon {
                            name: "cloud"
                            size: 13
                            color: Theme.primary
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            text: modelData.hostPort
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Medium
                            color: Theme.primary
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            text: "→"
                            font.pixelSize: Theme.fontSizeSmall
                            color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.6)
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        DankIcon {
                            name: "deployed_code"
                            size: 13
                            color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.8)
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            text: modelData.containerPort.replace("/tcp", "").replace("/udp", "")
                            font.pixelSize: Theme.fontSizeSmall
                            color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.8)
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }
            }
        }

        DankIcon {
            id: expandIcon
            name: isExpanded ? "expand_less" : "expand_more"
            size: containerHeader.iconSize
            color: Theme.surfaceText
            anchors.right: parent.right
            anchors.rightMargin: containerHeader.leftIndent
            anchors.top: parent.top
            anchors.topMargin: (containerHeader.baseHeight - expandIcon.height) / 2
        }

        MouseArea {
            id: headerMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: containerHeader.clicked()
        }
    }

    component ContainerActions: Column {
        property var containerData: null
        property real leftIndent: Theme.spacingL
        property bool isExpanded: false

        width: parent.width
        spacing: 0
        clip: true

        height: isExpanded ? actionsColumn.height : 0
        opacity: isExpanded ? 1 : 0

        Behavior on height {
            NumberAnimation {
                duration: Theme.expressiveDurations["expressiveFastSpatial"]
                easing.type: Theme.standardEasing
            }
        }

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.expressiveDurations["expressiveEffects"]
                easing.type: Theme.standardEasing
            }
        }

        Column {
            id: actionsColumn
            width: parent.width
            spacing: 0

            ActionButton {
                text: containerData?.isRunning ? "Restart" : "Start"
                icon: containerData?.isRunning ? "refresh" : "play_arrow"
                enabled: !containerData?.isPaused
                leftIndent: parent.parent.leftIndent
                onTriggered: root.executeAction(containerData.id, containerData.isRunning ? "restart" : "start")
            }

            ActionButton {
                text: containerData?.isPaused ? "Unpause" : "Pause"
                icon: "pause"
                enabled: containerData?.isRunning || containerData?.isPaused
                leftIndent: parent.parent.leftIndent
                onTriggered: root.executeAction(containerData.id, containerData.isPaused ? "unpause" : "pause")
            }

            ActionButton {
                text: "Stop"
                icon: "stop"
                enabled: containerData?.isRunning || containerData?.isPaused
                leftIndent: parent.parent.leftIndent
                onTriggered: root.executeAction(containerData.id, "stop")
            }

            ActionButton {
                text: "Shell"
                icon: "terminal"
                enabled: containerData?.isRunning
                leftIndent: parent.parent.leftIndent
                onTriggered: root.openExec(containerData.id)
            }

            ActionButton {
                text: "Logs"
                icon: "description"
                leftIndent: parent.parent.leftIndent
                onTriggered: root.openLogs(containerData.id)
            }
        }
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
        Column {
            id: popoutColumn
            spacing: 0

            Rectangle {
                width: parent.width
                height: 46
                color: "transparent"

                StyledText {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacingM
                    anchors.verticalCenter: parent.verticalCenter
                    text: globalDockerAvailable.value ? `${globalRunningContainers.value} running containers` : "Docker not available"
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.surfaceVariantText
                }

                Row {
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.spacingS
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingXS
                    visible: globalComposeProjects.value.length > 0

                    ViewToggleButton {
                        iconName: "view_list"
                        isActive: !root.groupByCompose
                        onClicked: {
                            root.groupByCompose = false;
                            root.pluginService?.savePluginData("dockerManager", "groupByCompose", false);
                        }
                    }

                    ViewToggleButton {
                        iconName: "account_tree"
                        isActive: root.groupByCompose
                        onClicked: {
                            root.groupByCompose = true;
                            root.pluginService?.savePluginData("dockerManager", "groupByCompose", true);
                        }
                    }
                }
            }

            DankListView {
                id: containerList
                width: parent.width
                height: root.popoutHeight - 46 - Theme.spacingXL
                topMargin: 0
                bottomMargin: Theme.spacingS
                leftMargin: Theme.spacingM
                rightMargin: Theme.spacingM
                spacing: 2
                clip: true
                visible: !root.groupByCompose
                model: globalContainers.value

                delegate: Column {
                    id: containerDelegate
                    width: containerList.width - containerList.leftMargin - containerList.rightMargin
                    spacing: 0

                    property bool isExpanded: root.expandedContainers[modelData.id] || false

                    ContainerHeader {
                        containerData: modelData
                        isExpanded: containerDelegate.isExpanded
                        onClicked: root.toggleContainer(modelData.id)
                    }

                    ContainerActions {
                        containerData: modelData
                        leftIndent: Theme.spacingL + Theme.spacingM
                        isExpanded: containerDelegate.isExpanded
                    }
                }
            }

            DankListView {
                id: projectList
                width: parent.width
                height: root.popoutHeight - 46 - Theme.spacingXL
                topMargin: 0
                bottomMargin: Theme.spacingS
                leftMargin: Theme.spacingM
                rightMargin: Theme.spacingM
                spacing: 2
                clip: true
                visible: root.groupByCompose
                model: globalComposeProjects.value

                delegate: Column {
                    id: projectDelegate
                    width: projectList.width - projectList.leftMargin - projectList.rightMargin
                    spacing: 0

                    property bool isExpanded: root.expandedProjects[modelData.name] || false

                    ProjectHeader {
                        projectName: modelData.name
                        runningCount: modelData.runningCount
                        totalCount: modelData.totalCount
                        serviceCount: modelData.containers.length
                        isExpanded: projectDelegate.isExpanded
                        onClicked: root.toggleProject(modelData.name)
                    }

                    Column {
                        id: projectContent
                        width: parent.width
                        spacing: 2
                        clip: true

                        height: projectDelegate.isExpanded ? projectContentInner.height : 0
                        opacity: projectDelegate.isExpanded ? 1 : 0

                        Behavior on height {
                            NumberAnimation {
                                duration: Theme.expressiveDurations["expressiveFastSpatial"]
                                easing.type: Theme.standardEasing
                            }
                        }

                        Behavior on opacity {
                            NumberAnimation {
                                duration: 200
                                easing.type: Easing.OutCubic
                            }
                        }

                        Column {
                            id: projectContentInner
                            width: parent.width
                            spacing: 2
                            topPadding: Theme.spacingXS

                            Column {
                                id: projectActionsColumn
                                width: parent.width
                                spacing: 0

                                ActionButton {
                                    text: "Start All"
                                    icon: "play_arrow"
                                    enabled: modelData.runningCount < modelData.totalCount
                                    leftIndent: Theme.spacingL
                                    onTriggered: root.executeComposeAction(modelData.workingDir, modelData.configFile, "start")
                                }

                                ActionButton {
                                    text: "Restart All"
                                    icon: "refresh"
                                    enabled: modelData.runningCount > 0
                                    leftIndent: Theme.spacingL
                                    onTriggered: root.executeComposeAction(modelData.workingDir, modelData.configFile, "restart")
                                }

                                ActionButton {
                                    text: "Stop All"
                                    icon: "stop"
                                    enabled: modelData.runningCount > 0
                                    leftIndent: Theme.spacingL
                                    onTriggered: root.executeComposeAction(modelData.workingDir, modelData.configFile, "stop")
                                }

                                ActionButton {
                                    text: "View Logs"
                                    icon: "description"
                                    leftIndent: Theme.spacingL
                                    onTriggered: root.executeComposeAction(modelData.workingDir, modelData.configFile, "logs")
                                }
                            }

                            Rectangle {
                                width: parent.width
                                height: Theme.spacingXS
                                color: "transparent"
                            }

                            Repeater {
                                model: modelData.containers

                                Column {
                                    id: serviceDelegate
                                    width: parent.width
                                    spacing: 0

                                    property var container: modelData
                                    property bool isExpanded: root.expandedContainers[container.name] || false

                                    ContainerHeader {
                                        containerData: container
                                        isExpanded: serviceDelegate.isExpanded
                                        useComposeServiceName: true
                                        leftIndent: Theme.spacingL
                                        iconSize: Theme.iconSize - 2
                                        baseHeight: 38
                                        defaultColor: Theme.surfaceContainer
                                        hoverColor: Theme.surfaceContainerHigh
                                        onClicked: root.toggleContainer(container.name)
                                    }

                                    ContainerActions {
                                        containerData: container
                                        leftIndent: Theme.spacingL * 2
                                        isExpanded: serviceDelegate.isExpanded
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    component ViewToggleButton: Rectangle {
        property string iconName: ""
        property bool isActive: false
        signal clicked

        width: 36
        height: 36
        radius: Theme.cornerRadius
        color: isActive ? Theme.primaryHover : mouseArea.containsMouse ? Theme.surfaceHover : "transparent"

        DankIcon {
            anchors.centerIn: parent
            name: iconName
            size: 18
            color: isActive ? Theme.primary : Theme.surfaceText
        }

        MouseArea {
            id: mouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.clicked()
        }
    }

    component ActionButton: Rectangle {
        id: actionButton
        property string text: ""
        property string icon: ""
        property bool enabled: true
        property real leftIndent: Theme.spacingL + Theme.spacingM
        signal triggered

        width: parent.width
        height: 44
        radius: 0
        color: actionMouse.containsMouse ? Theme.surfaceContainerHighest : "transparent"
        border.width: 0
        opacity: enabled ? 1.0 : 0.5

        Row {
            anchors.fill: parent
            anchors.leftMargin: actionButton.leftIndent
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
                font.weight: Font.Normal
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

    popoutWidth: 400
    popoutHeight: 500
}
