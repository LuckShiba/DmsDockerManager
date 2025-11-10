pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services

Item {
    id: root

    readonly property var defaults: ({
            debounceDelay: 300,
            dockerBinary: "docker",
            terminalApp: "alacritty --hold",
            shellPath: "/bin/sh"
        })

    readonly property string pluginId: "dockerManager"

    property bool systemdRunAvailable: false
    property bool dockerAvailable: false
    property int debounceDelay: defaults.debounceDelay
    property string dockerBinary: defaults.dockerBinary
    property string terminalApp: defaults.terminalApp
    property string shellPath: defaults.shellPath

    function loadSettings() {
        const load = key => PluginService.loadPluginData(pluginId, key) || defaults[key];
        debounceDelay = load("debounceDelay");
        dockerBinary = load("dockerBinary");
        terminalApp = load("terminalApp");
        shellPath = load("shellPath");

        refresh();
    }

    Component.onCompleted: {
        loadSettings();
        initialize();
    }

    Connections {
        target: PluginService
        function onPluginDataChanged(pluginId) {
            if (pluginId === root.pluginId) {
                loadSettings();
            }
        }
    }

    function getDockerEventCommand() {
        return [dockerBinary, "events", "--format", "json", "--filter", "type=container"];
    }

    onDockerBinaryChanged: {
        eventsProcess.running = false;
        eventsProcess.command = getDockerEventCommand();
        eventsProcess.running = true;
    }

    property var debounceTimer: Timer {
        interval: root.debounceDelay
        running: false
        repeat: false
        onTriggered: fetchContainers()
    }

    property var eventsProcess: Process {
        command: getDockerEventCommand()
        running: false

        stdout: SplitParser {
            onRead: data => {
                try {
                    const event = JSON.parse(data);
                    const action = event.Status || event.status;

                    if (["start", "stop", "die", "died", "kill", "restart", "pause", "unpause", "create", "destroy", "remove", "cleanup"].includes(action)) {
                        console.log(`DockerManager: Container event detected - ${action}`);
                        debounceTimer.restart();
                    }
                } catch (e) {
                    console.error("DockerManager: Failed to parse docker event:", e, data);
                }
            }
        }

        onRunningChanged: {
            if (!running) {
                console.log("DockerManager: Docker events process not running");
                restartTimer.start();
            }
        }
    }

    property var restartTimer: Timer {
        interval: 5000
        running: false
        repeat: false
        onTriggered: {
            if (dockerAvailable) {
                console.log("DockerManager: Attempting to restart events listener...");
                eventsProcess.running = true;
            }
        }
    }

    function initialize() {
        Proc.runCommand(`${pluginId}.systemdRunCheck`, ["which", "systemd-run"], (stdout, exitCode) => {
            systemdRunAvailable = exitCode === 0;
        }, 100);

        refresh();

        eventsProcess.running = true;
    }

    function refresh() {
        Proc.runCommand(`${pluginId}.dockerCheck`, [dockerBinary, "info"], (stdout, exitCode) => {
            root.dockerAvailable = exitCode === 0;
            PluginService.setGlobalVar("dockerManager", "dockerAvailable", dockerAvailable);
            if (dockerAvailable) {
                fetchContainers();
            } else {
                updateContainers();
            }
        }, 100);
    }

    function fetchContainers() {
        Proc.runCommand(`${pluginId}.dockerInspect`, ["sh", "-c", `${dockerBinary} container inspect $(${dockerBinary} container ls -aq)`], (stdout, exitCode) => {
            if (exitCode === 0) {
                try {
                    const containers = JSON.parse(stdout).map(container => {
                        try {
                            const labels = container.Config?.Labels || {};
                            const state = container.State?.Status || "";
                            const startedAt = new Date(container.State?.StartedAt || 0).getTime();
                            const finishedAt = new Date(container.State?.FinishedAt || 0).getTime();
                            const lastActivity = Math.max(startedAt, finishedAt);
                            
                            const ports = [];
                            const portBindings = container.NetworkSettings?.Ports || {};
                            for (const [containerPort, hostBindings] of Object.entries(portBindings)) {
                                if (hostBindings && hostBindings.length > 0) {
                                    hostBindings.forEach(binding => {
                                        const hostPort = binding.HostPort;
                                        const hostIp = binding.HostIp || "0.0.0.0";
                                        if (hostPort) {
                                            ports.push({
                                                containerPort: containerPort,
                                                hostPort: hostPort,
                                                hostIp: hostIp
                                            });
                                        }
                                    });
                                }
                            }

                            return {
                                id: container.Id || "",
                                name: container.Name?.replace(/^\//, "") || "",
                                status: `${state.charAt(0).toUpperCase() + state.slice(1)}`,
                                state: state,
                                image: container.Config?.Image || container.ImageName || "",
                                isRunning: container.State?.Running || false,
                                isPaused: container.State?.Paused || false,
                                created: container.Created || "",
                                lastActivity: lastActivity,
                                ports: ports,
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
                        if (a.lastActivity !== b.lastActivity)
                            return b.lastActivity - a.lastActivity;
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
        PluginService.setGlobalVar(pluginId, "containers", containers);
        PluginService.setGlobalVar(pluginId, "runningContainers", runningContainers);
        PluginService.setGlobalVar(pluginId, "composeProjects", composeProjects);
    }

    function executeAction(containerId, action) {
        const commands = {
            start: [dockerBinary, "start", containerId],
            stop: [dockerBinary, "stop", containerId],
            restart: [dockerBinary, "restart", containerId],
            pause: [dockerBinary, "pause", containerId],
            unpause: [dockerBinary, "unpause", containerId]
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

    function executeComposeAction(workingDir, configFile, action) {
        if (!workingDir) {
            console.error("DockerManager: Cannot execute compose action without working directory");
            return false;
        }

        const composeCommands = {
            up: [dockerBinary, "compose", "-f", configFile, "up", "-d"],
            down: [dockerBinary, "compose", "-f", configFile, "down"],
            restart: [dockerBinary, "compose", "-f", configFile, "restart"],
            stop: [dockerBinary, "compose", "-f", configFile, "stop"],
            start: [dockerBinary, "compose", "-f", configFile, "start"],
            pull: [dockerBinary, "compose", "-f", configFile, "pull"],
            logs: null
        };

        if (action === "logs") {
            const cmd = `cd "${workingDir}" && ${dockerBinary} compose -f ${configFile} logs -f`;
            Quickshell.execDetached(["sh", "-c", `${terminalApp} -e sh -c '${cmd}'`]);
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

    function openLogs(containerId) {
        Quickshell.execDetached(["sh", "-c", terminalApp + " -e " + dockerBinary + " logs -f " + containerId]);
    }

    function openExec(containerId) {
        Quickshell.execDetached(["sh", "-c", terminalApp + " -e " + dockerBinary + " exec -it " + containerId + " " + shellPath]);
    }
}
