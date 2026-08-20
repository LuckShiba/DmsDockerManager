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
    property bool showPorts: pluginData.showPorts ?? true
    
    property bool autoScrollOnExpand: pluginData.autoScrollOnExpand ?? true
    property string selectedItemId: ""
    property bool selectedIsContainer: false
    property string selectedParentProject: ""
    property int selectedActionIndex: -1
    property bool keyboardNavigationActive: false
    property var containerListView: null
    property var projectListView: null
    property var currentActionsList: null
    
    Timer {
        id: scrollTimer
        interval: 16
        repeat: true
        property int iterations: 0
        property int maxIterations: Math.ceil((Theme.expressiveDurations["expressiveFastSpatial"] ?? 300) / interval) + 1
        onTriggered: {
            if (++iterations >= maxIterations) {
                stop();
                iterations = 0;
            }
            ensureVisible();
        }
        function restart() {
            iterations = 0;
            maxIterations = Math.ceil((Theme.expressiveDurations["expressiveFastSpatial"] ?? 300) / interval);
            start();
        }
    }

    onExpandedProjectsChanged: {
        if (keyboardNavigationActive && root.groupByCompose) {
            ensureValidSelection();
        }
    }

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

    function toggleContainer(containerId, parentProject) {
        const wasExpanded = root.expandedContainers[containerId] || false;
        const expanded = root.expandedContainers;
        expanded[containerId] = !expanded[containerId];
        root.expandedContainers = expanded;
        root.expandedContainersChanged();
        
        if (!wasExpanded && !keyboardNavigationActive && autoScrollOnExpand) {
            selectedItemId = containerId;
            selectedIsContainer = true;
            selectedParentProject = parentProject || "";
            scrollTimer.restart();
        }
    }

    function toggleProject(projectName) {
        const wasExpanded = root.expandedProjects[projectName] || false;
        const expanded = root.expandedProjects;
        expanded[projectName] = !expanded[projectName];
        root.expandedProjects = expanded;
        root.expandedProjectsChanged();
        
        if (!wasExpanded && !keyboardNavigationActive && autoScrollOnExpand) {
            selectedItemId = projectName;
            selectedIsContainer = false;
            selectedParentProject = "";
            scrollTimer.restart();
        }
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

    function buildNavigableList() {
        if (!groupByCompose) {
            return globalContainers.value.map(c => ({type: 'container', id: c.id, data: c}));
        }
        
        const list = [];
        globalComposeProjects.value.forEach(project => {
            list.push({type: 'project', id: project.name, data: project});
            if (expandedProjects[project.name]) {
                project.containers.forEach(container => {
                    list.push({
                        type: 'container', 
                        id: container.name, 
                        data: container, 
                        parentProject: project.name
                    });
                });
            }
        });
        return list;
    }

    function findItemIndexById(itemId) {
        return buildNavigableList().findIndex(item => item.id === itemId);
    }

    function getSelectedIndex() {
        return selectedItemId ? findItemIndexById(selectedItemId) : -1;
    }

    function ensureValidSelection() {
        const list = buildNavigableList();
        if (!list.length) {
            selectedItemId = "";
            selectedIsContainer = false;
            selectedParentProject = "";
            return;
        }

        if (!selectedItemId || findItemIndexById(selectedItemId) === -1) {
            const first = list[0];
            selectedItemId = first.id;
            selectedIsContainer = first.type === 'container';
            selectedParentProject = first.parentProject || "";
        }
    }

    function isActionEnabled(actionIndex) {
        const list = buildNavigableList();
        const idx = getSelectedIndex();
        if (idx < 0 || idx >= list.length) return false;
        
        const data = list[idx].data;
        if (selectedIsContainer) {
            switch(actionIndex) {
                case 0: return !data.isPaused;
                case 1: return data.isRunning || data.isPaused;
                case 2: return data.isRunning || data.isPaused;
                case 3: return data.isRunning;
                case 4: return true;
            }
        } else {
            switch(actionIndex) {
                case 0: return data.runningCount < data.totalCount;
                case 1: return data.runningCount > 0;
                case 2: return data.runningCount > 0;
                case 3: return true;
            }
        }
        return false;
    }

    function findNextEnabledAction(fromIndex) {
        const maxActions = selectedIsContainer ? 4 : 3;
        for (let i = fromIndex + 1; i <= maxActions; i++) {
            if (isActionEnabled(i)) return i;
        }
        return -1;
    }

    function findPreviousEnabledAction(fromIndex) {
        for (let i = fromIndex - 1; i >= 0; i--) {
            if (isActionEnabled(i)) return i;
        }
        return -1;
    }

    function selectNext() {
        const list = buildNavigableList();
        if (!list.length) return;
        
        if (!keyboardNavigationActive) {
            keyboardNavigationActive = true;
            ensureValidSelection();
            return;
        }
        
        if (selectedActionIndex >= 0) {
            const nextAction = findNextEnabledAction(selectedActionIndex);
            if (nextAction >= 0) {
                selectedActionIndex = nextAction;
                return;
            }
            selectedActionIndex = -1;
        }
        
        const currentIndex = getSelectedIndex();
        if (currentIndex >= list.length - 1) return;
        
        const nextItem = list[currentIndex + 1];
        selectedItemId = nextItem.id;
        selectedIsContainer = nextItem.type === 'container';
        selectedParentProject = nextItem.parentProject || "";
        ensureVisible();
    }

    function selectPrevious() {
        const list = buildNavigableList();
        if (!list.length) return;
        
        if (!keyboardNavigationActive) {
            keyboardNavigationActive = true;
            ensureValidSelection();
            return;
        }
        
        if (selectedActionIndex >= 0) {
            const prevAction = findPreviousEnabledAction(selectedActionIndex);
            if (prevAction >= 0) {
                selectedActionIndex = prevAction;
                return;
            }
            selectedActionIndex = -1;
            ensureVisible();
            return;
        }
        
        const currentIndex = getSelectedIndex();
        if (currentIndex <= 0) return;
        
        const prevItem = list[currentIndex - 1];
        selectedItemId = prevItem.id;
        selectedIsContainer = prevItem.type === 'container';
        selectedParentProject = prevItem.parentProject || "";
        ensureVisible();
    }

    function getExpandedState(itemId) {
        return selectedIsContainer ? (expandedContainers[itemId] || false) : (expandedProjects[itemId] || false);
    }

    function toggleItem() {
        selectedIsContainer ? toggleContainer(selectedItemId, selectedParentProject) : toggleProject(selectedItemId);
    }

    function toggleSelected() {
        if (!selectedItemId) return;
        
        if (selectedActionIndex >= 0 && currentActionsList) {
            const actionButton = currentActionsList[selectedActionIndex];
            if (actionButton?.enabled) actionButton.triggered();
            return;
        }
        
        const wasExpanded = getExpandedState(selectedItemId);
        toggleItem();
        !wasExpanded && autoScrollOnExpand ? scrollTimer.restart() : Qt.callLater(ensureVisible);
    }
    
    function ensureVisible() {
        if (!selectedItemId) return;
        
        const listView = groupByCompose ? projectListView : containerListView;
        if (!listView) return;
        
        Qt.callLater(() => {
            const index = groupByCompose ? getSelectedProjectIndex() : getSelectedIndex();
            if (index >= 0) {
                // For nested containers that are expanded, position at end to keep them visible
                if (groupByCompose && selectedIsContainer && getExpandedState(selectedItemId)) {
                    listView.positionViewAtIndex(index, ListView.End);
                } else {
                    listView.positionViewAtIndex(index, ListView.Contain);
                }
            }
        });
    }
    
    function enterActions() {
        if (!selectedItemId || selectedActionIndex >= 0) return;
        if (!getExpandedState(selectedItemId)) toggleSelected();
        selectedActionIndex = findNextEnabledAction(-1);
        if (selectedActionIndex < 0) selectedActionIndex = 0;
        ensureVisible();
    }
    
    function exitActions() {
        if (selectedActionIndex >= 0) {
            selectedActionIndex = -1;
            ensureVisible();
            return;
        }
        
        if (getExpandedState(selectedItemId)) {
            toggleItem();
            return;
        }
        
        if (groupByCompose && selectedIsContainer && selectedParentProject) {
            selectedItemId = selectedParentProject;
            selectedIsContainer = false;
            selectedParentProject = "";
            ensureVisible();
        }
    }
    
    function toggleViewMode() {
        groupByCompose = !groupByCompose;
        pluginService?.savePluginData("dockerManager", "groupByCompose", groupByCompose);
        selectedItemId = "";
        selectedIsContainer = false;
        selectedParentProject = "";
        selectedActionIndex = -1;
        ensureValidSelection();
    }
    
    function getSelectedProjectIndex() {
        if (!groupByCompose || !selectedItemId) return -1;
        
        const projectName = selectedIsContainer ? selectedParentProject : selectedItemId;
        return globalComposeProjects.value.findIndex(p => p.name === projectName);
    }

    component DockerIcon: DankNFIcon {
        name: "docker"
        size: root.iconSize
        color: {
            if (!globalDockerAvailable.value)
                return Theme.error;
            if (globalRunningContainers.value > 0)
                return Theme.primary;
            return Theme.widgetIconColor || Theme.surfaceText;
        }
    }

    component DockerCount: StyledText {
        text: globalRunningContainers.value.toString()
        font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale)
        color: Theme.widgetTextColor || Theme.surfaceText
        visible: globalRunningContainers.value > 0
    }

    component ProjectHeader: StyledRect {
        id: projectHeader
        property string projectName: ""
        property int runningCount: 0
        property int totalCount: 0
        property int serviceCount: 0
        property bool isExpanded: false
        property bool isCurrentItem: false
        signal clicked

        width: parent.width
        height: 52
        radius: Theme.cornerRadius
        color: (isCurrentItem || projectMouse.containsMouse) ? Theme.withAlpha(Theme.surfaceContainerHighest, Theme.popupTransparency) : Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
        border.width: Theme.layerOutlineWidth
        border.color: Theme.outlineLight

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
            onClicked: {
                root.keyboardNavigationActive = false;
                projectHeader.clicked();
            }
        }
    }

    component ContainerHeader: StyledRect {
        id: containerHeader
        property var containerData: null
        property bool useComposeServiceName: false
        property bool isExpanded: false
        property bool isCurrentItem: false
        property real leftIndent: Theme.spacingM
        property real iconSize: Theme.iconSize
        property real baseHeight: 48
        property color defaultColor: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
        property color hoverColor: Theme.withAlpha(Theme.surfaceContainerHighest, Theme.popupTransparency)
        signal clicked

        width: parent.width
        height: baseHeight + (isExpanded && root.showPorts && containerData?.ports?.length > 0 ? Theme.spacingS + portFlow.height + Theme.spacingXS : 0)
        radius: Theme.cornerRadius
        color: isCurrentItem ? hoverColor : (headerMouse.containsMouse ? hoverColor : defaultColor)
        border.width: Theme.layerOutlineWidth
        border.color: Theme.outlineLight

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
            // Above headerMouse (declared later = stacked on top) so the port
            // badges receive clicks; gaps still fall through to the header.
            z: 1
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
                    // TCP ports open in the browser on click; hover highlights them
                    readonly property bool isTcp: !(modelData.containerPort || "").includes("/udp")
                    color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, (isTcp && portMouse.containsMouse) ? 0.3 : 0.15)
                    border.width: 1
                    border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.3)

                    MouseArea {
                        id: portMouse
                        anchors.fill: parent
                        enabled: parent.isTcp
                        hoverEnabled: true
                        cursorShape: parent.isTcp ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            const host = (modelData.hostIp && modelData.hostIp !== "0.0.0.0") ? modelData.hostIp : "localhost";
                            Qt.openUrlExternally("http://" + host + ":" + modelData.hostPort);
                        }
                    }

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
            onClicked: {
                root.keyboardNavigationActive = false;
                containerHeader.clicked();
            }
        }
    }

    component ContainerActions: Column {
        property var containerData: null
        property real leftIndent: Theme.spacingL
        property bool isExpanded: false
        property bool isCurrentItem: false
        property var actionButtons: [action0, action1, action2, action3, action4]

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
                id: action0
                text: containerData?.isRunning ? "Restart" : "Start"
                icon: containerData?.isRunning ? "refresh" : "play_arrow"
                enabled: !containerData?.isPaused
                isSelected: parent.parent.isCurrentItem && root.selectedActionIndex === 0
                leftIndent: parent.parent.leftIndent
                onTriggered: root.executeAction(containerData.id || containerData.name, containerData.isRunning ? "restart" : "start")
            }

            ActionButton {
                id: action1
                text: containerData?.isPaused ? "Unpause" : "Pause"
                icon: "pause"
                enabled: containerData?.isRunning || containerData?.isPaused
                isSelected: parent.parent.isCurrentItem && root.selectedActionIndex === 1
                leftIndent: parent.parent.leftIndent
                onTriggered: root.executeAction(containerData.id || containerData.name, containerData.isPaused ? "unpause" : "pause")
            }

            ActionButton {
                id: action2
                text: "Stop"
                icon: "stop"
                enabled: containerData?.isRunning || containerData?.isPaused
                isSelected: parent.parent.isCurrentItem && root.selectedActionIndex === 2
                leftIndent: parent.parent.leftIndent
                onTriggered: root.executeAction(containerData.id || containerData.name, "stop")
            }

            ActionButton {
                id: action3
                text: "Shell"
                icon: "terminal"
                enabled: containerData?.isRunning
                isSelected: parent.parent.isCurrentItem && root.selectedActionIndex === 3
                leftIndent: parent.parent.leftIndent
                onTriggered: root.openExec(containerData.id || containerData.name)
            }

            ActionButton {
                id: action4
                text: "Logs"
                icon: "description"
                isSelected: parent.parent.isCurrentItem && root.selectedActionIndex === 4
                leftIndent: parent.parent.leftIndent
                onTriggered: root.openLogs(containerData.id || containerData.name)
            }
        }
    }

    component ProjectActions: Column {
        property var projectData: null
        property real leftIndent: Theme.spacingL
        property bool isExpanded: false
        property bool isCurrentItem: false
        property var actionButtons: [action0, action1, action2, action3]

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
                id: action0
                text: "Start All"
                icon: "play_arrow"
                enabled: projectData?.runningCount < projectData?.totalCount
                isSelected: parent.parent.isCurrentItem && root.selectedActionIndex === 0
                leftIndent: parent.parent.leftIndent
                onTriggered: root.executeComposeAction(projectData.workingDir, projectData.configFile, "start")
            }

            ActionButton {
                id: action1
                text: "Restart All"
                icon: "refresh"
                enabled: projectData?.runningCount > 0
                isSelected: parent.parent.isCurrentItem && root.selectedActionIndex === 1
                leftIndent: parent.parent.leftIndent
                onTriggered: root.executeComposeAction(projectData.workingDir, projectData.configFile, "restart")
            }

            ActionButton {
                id: action2
                text: "Stop All"
                icon: "stop"
                enabled: projectData?.runningCount > 0
                isSelected: parent.parent.isCurrentItem && root.selectedActionIndex === 2
                leftIndent: parent.parent.leftIndent
                onTriggered: root.executeComposeAction(projectData.workingDir, projectData.configFile, "stop")
            }

            ActionButton {
                id: action3
                text: "View Logs"
                icon: "description"
                isSelected: parent.parent.isCurrentItem && root.selectedActionIndex === 3
                leftIndent: parent.parent.leftIndent
                onTriggered: root.executeComposeAction(projectData.workingDir, projectData.configFile, "logs")
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
        FocusScope {
            implicitWidth: popoutColumn.implicitWidth
            implicitHeight: popoutColumn.implicitHeight
            focus: true

            property var parentPopout: null
            Connections {
                target: parentPopout
                function onOpened() {
                    Qt.callLater(() => {
                        forceActiveFocus();
                    });
                }
            }

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Down || (event.key === Qt.Key_J && event.modifiers & Qt.ControlModifier) || 
                    (event.key === Qt.Key_N && event.modifiers & Qt.ControlModifier)) {
                    root.selectNext();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Up || (event.key === Qt.Key_K && event.modifiers & Qt.ControlModifier) || 
                    (event.key === Qt.Key_P && event.modifiers & Qt.ControlModifier)) {
                    root.selectPrevious();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Tab) {
                    root.selectNext();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Backtab) {
                    root.selectPrevious();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                    root.toggleSelected();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Right || (event.key === Qt.Key_L && event.modifiers & Qt.ControlModifier)) {
                    root.enterActions();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Left || (event.key === Qt.Key_H && event.modifiers & Qt.ControlModifier)) {
                    root.exitActions();
                    event.accepted = true;
                } else if (event.key === Qt.Key_V) {
                    root.toggleViewMode();
                    event.accepted = true;
                }
            }

            Column {
                id: popoutColumn
                spacing: 0
                width: parent.width

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
                        font.weight: Font.Medium
                        color: Theme.surfaceText
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
                    spacing: Theme.spacingS
                    clip: true
                    visible: !root.groupByCompose
                    model: globalContainers.value
                    currentIndex: root.keyboardNavigationActive && !root.groupByCompose ? root.getSelectedIndex() : -1

                    Component.onCompleted: {
                        root.containerListView = containerList;
                    }

                    delegate: StyledRect {
                        id: containerDelegate
                        width: containerList.width - containerList.leftMargin - containerList.rightMargin
                        radius: Theme.cornerRadius
                        Component.onCompleted: height = Qt.binding(() => containerHeaderPart.height + containerActionsPart.height)
                        color: isCurrentItem ? Theme.withAlpha(Theme.surfaceContainerHighest, Theme.popupTransparency) : Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
                        border.width: 1
                        border.color: {
                            if (modelData.isRunning) return Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.5)
                            if (modelData.isPaused) return Qt.rgba(Theme.warning.r, Theme.warning.g, Theme.warning.b, 0.5)
                            return Theme.outlineLight
                        }
                        clip: true

                        property bool isExpanded: root.expandedContainers[modelData.id] || false
                        property bool isCurrentItem: root.keyboardNavigationActive && !root.groupByCompose && root.selectedItemId === modelData.id

                        ContainerHeader {
                            id: containerHeaderPart
                            width: parent.width
                            containerData: modelData
                            isExpanded: containerDelegate.isExpanded
                            isCurrentItem: containerDelegate.isCurrentItem
                            defaultColor: "transparent"
                            hoverColor: Theme.surfaceHover
                            border.width: 0
                            onClicked: root.toggleContainer(modelData.id)
                        }

                        ContainerActions {
                            id: containerActionsPart
                            width: parent.width
                            anchors.top: containerHeaderPart.bottom
                            containerData: modelData
                            leftIndent: Theme.spacingL + Theme.spacingM
                            isExpanded: containerDelegate.isExpanded
                            isCurrentItem: containerDelegate.isCurrentItem
                            onIsCurrentItemChanged: {
                                if (isCurrentItem) {
                                    root.currentActionsList = actionButtons;
                                }
                            }
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
                    spacing: Theme.spacingS
                    clip: true
                    visible: root.groupByCompose
                    model: globalComposeProjects.value
                    currentIndex: root.keyboardNavigationActive && root.groupByCompose ? root.getSelectedProjectIndex() : -1

                    Component.onCompleted: {
                        root.projectListView = projectList;
                    }

                    delegate: StyledRect {
                        id: projectDelegate
                        width: projectList.width - projectList.leftMargin - projectList.rightMargin
                        radius: Theme.cornerRadius
                        Component.onCompleted: height = Qt.binding(() => projectHeaderPart.height + projectContentPart.height)
                        color: isCurrentItem ? Theme.withAlpha(Theme.surfaceContainerHighest, Theme.popupTransparency) : Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
                        border.width: 1
                        border.color: {
                            if (modelData.runningCount === modelData.totalCount && modelData.totalCount > 0)
                                return Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.5)
                            if (modelData.runningCount > 0)
                                return Qt.rgba(Theme.warning.r, Theme.warning.g, Theme.warning.b, 0.5)
                            return Theme.outlineLight
                        }
                        clip: true

                        property bool isExpanded: root.expandedProjects[modelData.name] || false
                        property bool isCurrentItem: root.keyboardNavigationActive && root.groupByCompose && !root.selectedIsContainer && root.selectedItemId === modelData.name

                        ProjectHeader {
                            id: projectHeaderPart
                            width: parent.width
                            projectName: modelData.name
                            runningCount: modelData.runningCount
                            totalCount: modelData.totalCount
                            serviceCount: modelData.containers.length
                            isExpanded: projectDelegate.isExpanded
                            isCurrentItem: projectDelegate.isCurrentItem
                            color: "transparent"
                            border.width: 0
                            onClicked: root.toggleProject(modelData.name)
                        }

                        Column {
                            id: projectContentPart
                            width: parent.width
                            anchors.top: projectHeaderPart.bottom
                            spacing: 2
                            clip: true

                            property var project: modelData

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
                                width: parent.width - Theme.spacingS * 2
                                x: Theme.spacingS
                                spacing: Theme.spacingXS
                                topPadding: Theme.spacingXS
                                bottomPadding: Theme.spacingS

                                ProjectActions {
                                    projectData: projectContentPart.project
                                    leftIndent: Theme.spacingL
                                    isExpanded: projectDelegate.isExpanded
                                    isCurrentItem: projectDelegate.isCurrentItem
                                    onIsCurrentItemChanged: {
                                        if (isCurrentItem) {
                                            root.currentActionsList = actionButtons;
                                        }
                                    }
                                }

                                Rectangle {
                                    width: parent.width
                                    height: Theme.spacingXS
                                    color: "transparent"
                                }

                                Repeater {
                                    model: projectContentPart.project.containers

                                    StyledRect {
                                        id: serviceDelegate
                                        width: parent.width
                                        radius: Theme.cornerRadius
                                        Component.onCompleted: height = Qt.binding(() => serviceHeaderPart.height + serviceActionsPart.height)
                                        color: isCurrentItem ? Theme.withAlpha(Theme.surfaceContainerHighest, Theme.popupTransparency) : Theme.nestedSurface
                                        border.width: 1
                                        border.color: {
                                            if (container.isRunning) return Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.4)
                                            if (container.isPaused) return Qt.rgba(Theme.warning.r, Theme.warning.g, Theme.warning.b, 0.4)
                                            return Theme.outlineLight
                                        }
                                        clip: true

                                        property var container: modelData
                                        property bool isExpanded: root.expandedContainers[container.name] || false
                                        property bool isCurrentItem: root.keyboardNavigationActive && root.groupByCompose && root.selectedIsContainer && root.selectedItemId === container.name

                                        ContainerHeader {
                                            id: serviceHeaderPart
                                            width: parent.width
                                            containerData: container
                                            isExpanded: serviceDelegate.isExpanded
                                            isCurrentItem: serviceDelegate.isCurrentItem
                                            useComposeServiceName: true
                                            leftIndent: Theme.spacingM
                                            iconSize: Theme.iconSize - 2
                                            baseHeight: 38
                                            defaultColor: "transparent"
                                            hoverColor: Theme.surfaceHover
                                            border.width: 0
                                            onClicked: root.toggleContainer(container.name, projectContentPart.project.name)
                                        }

                                        ContainerActions {
                                            id: serviceActionsPart
                                            width: parent.width
                                            anchors.top: serviceHeaderPart.bottom
                                            containerData: container
                                            leftIndent: Theme.spacingM + Theme.spacingL
                                            isExpanded: serviceDelegate.isExpanded
                                            isCurrentItem: serviceDelegate.isCurrentItem
                                            onIsCurrentItemChanged: {
                                                if (isCurrentItem) {
                                                    root.currentActionsList = actionButtons;
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
        property bool isSelected: false
        property real leftIndent: Theme.spacingL + Theme.spacingM
        signal triggered

        width: parent.width
        height: 44
        radius: 0
        color: isSelected ? Theme.primaryHover : (actionMouse.containsMouse ? Theme.surfaceHover : "transparent")
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
            onClicked: {
                root.keyboardNavigationActive = false;
                actionButton.triggered();
            }
        }
    }

    popoutWidth: 400
    popoutHeight: 500
}
