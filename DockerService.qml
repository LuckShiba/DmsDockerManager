import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services

Item {
    id: root

    property bool systemdRunAvailable: false
    property int debounceDelay: 300

    Timer {
        id: debounceTimer
        interval: root.debounceDelay
        running: false
        repeat: false
        onTriggered: fetchContainers()
    }

    Process {
        id: eventsProcess
        command: ["docker", "events", "--format", "json", "--filter", "type=container"]
        running: false

        stdout: SplitParser {
            onRead: data => {
                try {
                    const event = JSON.parse(data);
                    const action = event.Action || event.action || event.status;

                    if (["start", "stop", "die", "kill", "restart", "pause", "unpause", "create", "destroy", "remove"].includes(action)) {
                        console.log(`DockerManager: Container event detected - ${action}`);
                        debounceTimer.restart();
                    }
                } catch (e) {
                    console.error("DockerManager: Failed to parse docker event:", e, data);
                }
            }
        }

        onRunningChanged: {
            if (!running && root.visible) {
                console.warn("DockerManager: Docker events process stopped");
                restartTimer.start();
            }
        }
    }

    Timer {
        id: restartTimer
        interval: 5000
        running: false
        repeat: false
        onTriggered: {
            console.log("DockerManager: Attempting to restart events listener...");
            eventsProcess.running = true;
        }
    }

    Component.onCompleted: {
        Proc.runCommand("dockerManager.systemdRunCheck", ["which", "systemd-run"], (stdout, exitCode) => {
            systemdRunAvailable = exitCode === 0;
        }, 100);

        refresh();

        eventsProcess.running = true;
    }

    Component.onDestruction: {
        eventsProcess.running = false;
    }

    function refresh() {
        Proc.runCommand("dockerManager.dockerCheck", ["docker", "info"], (stdout, exitCode) => {
            const success = exitCode === 0;
            PluginService.setGlobalVar("dockerManager", "dockerAvailable", success);
            if (success) {
                fetchContainers();
            } else {
                updateContainers();
            }
        }, 100);
    }

    function fetchContainers() {
        Proc.runCommand("dockerManager.dockerInspect", ["sh", "-c", "docker container inspect $(docker container ls -aq)"], (stdout, exitCode) => {
            if (exitCode === 0) {
                try {
                    const containers = JSON.parse(stdout).map(container => {
                        try {
                            const labels = container.Config?.Labels || {};
                            const state = container.State?.Status || "";

                            return {
                                id: container.Id || "",
                                name: container.Name?.replace(/^\//, "") || "",
                                status: `${state.charAt(0).toUpperCase() + state.slice(1)}`,
                                state: state,
                                image: container.Config?.Image || container.ImageName || "",
                                isRunning: container.State?.Running || false,
                                isPaused: container.State?.Paused || false,
                                created: container.Created || "",
                                composeProject: labels["com.docker.compose.project"] || labels["io.podman.compose.project"] || "",
                                composeService: labels["com.docker.compose.service"] || labels["io.podman.compose.service"] || "",
                                composeWorkingDir: labels["com.docker.compose.project.working_dir"] || "",
                                composeConfigFiles: labels["com.docker.compose.project.config_files"] || "compose.yaml"
                            };
                        } catch (e) {
                            console.error("DockerManager: Failed to parse container data:", e, container);
                            return null;
                        }
                    }).filter(c => c !== null).sort((a, b) => {
                        const priority = {
                            running: 1,
                            paused: 2,
                            default: 3
                        };
                        const aPriority = priority[a.state] || priority.default;
                        const bPriority = priority[b.state] || priority.default;
                        if (aPriority !== bPriority)
                            return aPriority - bPriority;
                        return a.name.localeCompare(b.name);
                    });

                    const projectMap = {};
                    containers.forEach(container => {
                        if (container.composeProject) {
                            if (!projectMap[container.composeProject]) {
                                projectMap[container.composeProject] = {
                                    name: container.composeProject,
                                    containers: [],
                                    runningCount: 0,
                                    totalCount: 0,
                                    workingDir: container.composeWorkingDir,
                                    configFile: container.composeConfigFiles
                                };
                            }
                            projectMap[container.composeProject].containers.push(container);
                            projectMap[container.composeProject].totalCount++;
                            if (container.isRunning) {
                                projectMap[container.composeProject].runningCount++;
                            }
                        }
                    });

                    updateContainers(containers, containers.filter(c => c.isRunning).length, Object.values(projectMap).sort((a, b) => {
                        if (a.runningCount !== b.runningCount)
                            return b.runningCount - a.runningCount;
                        return a.name.localeCompare(b.name);
                    }));
                } catch (e) {
                    console.error("DockerManager: Failed to parse docker inspect output:", e);
                    updateContainers();
                }
            } else {
                updateContainers();
            }
        }, 100);
    }

    function updateContainers(containers = [], runningContainers = 0, composeProjects = []) {
        PluginService.setGlobalVar("dockerManager", "containers", containers);
        PluginService.setGlobalVar("dockerManager", "runningContainers", runningContainers);
        PluginService.setGlobalVar("dockerManager", "composeProjects", composeProjects);
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
            const cmdArray = systemdRunAvailable ? ["systemd-run", "--user", "--scope", "--", ...commands[action]] : commands[action];
            Quickshell.execDetached(cmdArray);
            Qt.callLater(() => {
                root.refresh();
            });
            return true;
        }
        return false;
    }

    function executeComposeAction(workingDir, configFile, action, terminal) {
        if (!workingDir) {
            console.error("DockerManager: Cannot execute compose action without working directory");
            return false;
        }

        const composeCommands = {
            up: ["docker", "compose", "-f", configFile, "up", "-d"],
            down: ["docker", "compose", "-f", configFile, "down"],
            restart: ["docker", "compose", "-f", configFile, "restart"],
            stop: ["docker", "compose", "-f", configFile, "stop"],
            start: ["docker", "compose", "-f", configFile, "start"],
            pull: ["docker", "compose", "-f", configFile, "pull"],
            logs: null
        };

        if (action === "logs") {
            const cmd = `cd "${workingDir}" && docker compose -f ${configFile} logs -f`;
            Quickshell.execDetached(["sh", "-c", `${terminal} -e sh -c '${cmd}'`]);
            return true;
        }

        if (composeCommands[action]) {
            const cmd = ["sh", "-c", `cd "${workingDir}" && ${composeCommands[action].join(" ")}`];
            const cmdArray = systemdRunAvailable ? ["systemd-run", "--user", "--scope", "--", ...cmd] : cmd;
            Quickshell.execDetached(cmdArray);
            Qt.callLater(() => {
                root.refresh();
            });
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
