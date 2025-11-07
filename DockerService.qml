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
            ["docker", "ps", "-a", "--format", "{{ json . }}"],
            (stdout, exitCode) => {
                if (exitCode === 0) {
                    const lines = stdout.trim().split("\n").filter(line => line.length > 0);
                    const containers = lines.map(line => {
                        try {
                            const data = JSON.parse(line);
                            const name = Array.isArray(data.Names) ? data.Names[0] : data.Names;
                            return {
                                id: data.Id || data.ID || "",
                                name: name || "<unnamed>",
                                status: data.Status || "",
                                state: data.State || "",
                                image: data.Image || "",
                                isRunning: data.State === "running",
                                isPaused: data.State === "paused",
                                created: data.Created || "",
                                ports: data.Ports || [],
                                startedAt: data.StartedAt || 0,
                                exitedAt: data.ExitedAt || 0
                            };
                        } catch (e) {
                            console.error("Failed to parse container JSON:", e, line);
                            return null;
                        }
                    }).filter(c => c !== null)
                    .sort((a, b) => {
                        const priority = {
                            running: 1,
                            paused: 2,
                            default: 3
                        };
                        const getP = x => priority[x.state] || priority.default;
                        const aPriority = getP(a);
                        const bPriority = getP(b);
                        
                        if (aPriority !== bPriority) {
                            return aPriority - bPriority;
                        }
                        
                        const aTime = Math.max(a.startedAt, a.exitedAt);
                        const bTime = Math.max(b.startedAt, b.exitedAt);
                        return bTime - aTime;
                    });
                    const runningCount = containers.filter(c => c.isRunning).length;
                    
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
