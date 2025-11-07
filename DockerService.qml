import QtQuick
import Quickshell
import qs.Common
import qs.Services

Item {
    id: root

    property bool systemdRunAvailable: false
    property int refreshInterval: 5000

    signal containersUpdated()

    Timer {
        interval: root.refreshInterval
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Component.onCompleted: {
        Proc.runCommand(
            "dockerManager.systemdRunCheck",
            ["which", "systemd-run"],
            (stdout, exitCode) => {
                systemdRunAvailable = exitCode === 0
            },
            100
        );
    }

    function refresh() {
        Proc.runCommand(
            "dockerManager.dockerCheck",
            ["docker", "info"],
            (stdout, exitCode) => {
                const success = exitCode === 0;
                PluginService.setGlobalVar("dockerManager", "dockerAvailable", success);
                if (success) {
                    fetchContainers();
                }
            },
            100
        );
    }

    function fetchContainers() {
        Proc.runCommand(
            "dockerManager.dockerPs",
            ["docker", "ps", "-a", "--format", "{{.ID}}|{{.Names}}|{{.Status}}|{{.State}}|{{.Image}}"],
            (stdout, exitCode) => {
                if (exitCode === 0) {
                    const lines = stdout.trim().split("\n").filter(line => line.length > 0);
                    const containers = lines.map(line => {
                        const parts = line.split("|");
                        return {
                            id: parts[0] || "",
                            name: parts[1] || "",
                            status: parts[2] || "",
                            state: parts[3] || "",
                            image: parts[4] || "",
                            isRunning: parts[3] === "running",
                            isPaused: parts[3] === "paused",
                        };
                    });
                    const runningCount = containers.filter(c => c.state === "running").length;
                    
                    PluginService.setGlobalVar("dockerManager", "containers", containers);
                    PluginService.setGlobalVar("dockerManager", "runningContainers", runningCount);
                    root.containersUpdated();
                }
            },
            100
        )
    }

    function executeAction(containerId, action) {
        const commands = {
            start: ["docker", "start", containerId],
            stop: ["docker", "stop", containerId],
            restart: ["docker", "restart", containerId],
            pause: ["docker", "pause", containerId],
            unpause: ["docker", "unpause", containerId]
        };
        
        if (commands[action]) {
            // systemd-run is used if available because if the user is using podman for some reason it
            // will "attach" the container to the dms systemd service, showing the container logs in
            // dms' service journal and will not allow dms to close until the containers started by it
            // are closed.
            const cmdArray = systemdRunAvailable 
                ? ["systemd-run", "--user", "--scope", "--", ...commands[action]]
                : commands[action];
            Quickshell.execDetached(cmdArray);
            Qt.callLater(() => { root.refresh() });
            return true;
        }
        return false;
    }

    function openLogs(containerId, terminal) {
        Quickshell.execDetached(["sh", "-c", terminal + " -e docker logs -f " + containerId]);
    }

    function openExec(containerId, terminal, shell) {
        Quickshell.execDetached(["sh", "-c", terminal + " -e docker exec -it " + containerId + " " + shell]);
    }
}
