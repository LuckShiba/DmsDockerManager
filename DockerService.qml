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
            shellPath: "/bin/sh",
            pollingInterval: 0,
            runtimeMode: "auto",
            colimaProfile: "default"
        })

    readonly property string pluginId: "dockerManager"

    property bool systemdRunAvailable: false
    property bool dockerAvailable: false
    property int debounceDelay: defaults.debounceDelay
    property string dockerBinary: defaults.dockerBinary
    property string terminalApp: defaults.terminalApp
    property string shellPath: defaults.shellPath
    property int pollingInterval: defaults.pollingInterval

    property string runtimeMode: defaults.runtimeMode
    property string activeRuntime: "None"
    property bool colimaAvailable: false
    property bool colimaRunning: false
    property string colimaProfile: defaults.colimaProfile
    property string colimaTransitioning: ""
    property int colimaPollCount: 0
    property string serviceTransitioning: ""
    property int servicePollCount: 0

    function loadSettings() {
        const load = key => PluginService.loadPluginData(pluginId, key) || defaults[key];
        debounceDelay = load("debounceDelay");
        dockerBinary = load("dockerBinary");
        terminalApp = load("terminalApp");
        shellPath = load("shellPath");
        pollingInterval = load("pollingInterval");
        runtimeMode = load("runtimeMode");
        colimaProfile = load("colimaProfile");

        PluginService.setGlobalVar(pluginId, "runtimeMode", runtimeMode);
        PluginService.setGlobalVar(pluginId, "colimaProfile", colimaProfile);
        PluginService.setGlobalVar(pluginId, "activeRuntime", activeRuntime);
        PluginService.setGlobalVar(pluginId, "serviceTransitioning", serviceTransitioning);

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
        const binary = activeRuntime === "Podman" && dockerBinary === "docker" ? "podman" : dockerBinary;
        const cmd = [binary, "events", "--format", "json", "--filter", "type=container"];
        return wrapDockerCommand(cmd);
    }

    function updateEventsProcess() {
        eventsProcess.running = false;
        if (dockerAvailable) {
            eventsProcess.command = getDockerEventCommand();
            eventsProcess.running = true;
        }
    }

    onActiveRuntimeChanged: Qt.callLater(updateEventsProcess)
    onDockerBinaryChanged: Qt.callLater(updateEventsProcess)
    onDockerAvailableChanged: Qt.callLater(updateEventsProcess)

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
                if (dockerAvailable) {
                    root.refresh();
                }
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

    property var pollingTimer: Timer {
        interval: root.pollingInterval
        running: root.dockerAvailable && root.pollingInterval > 0
        repeat: true
        onTriggered: {
            console.log("DockerManager: Polling for container state updates");
            fetchContainers();
        }
    }

    property var retryTimer: Timer {
        interval: 10000
        running: !root.dockerAvailable
        repeat: true
        onTriggered: {
            console.log("DockerManager: Docker not available, retrying/refreshing status...");
            root.refresh();
        }
    }

    function getColimaEnvCheck(escapeQuotes = false) {
        const profile = colimaProfile || "default";
        const quote = escapeQuotes ? '\\"' : '"';
        return `if [ -S ${quote}$HOME/.colima/${profile}/docker.sock${quote} ]; then export DOCKER_HOST=${quote}unix://$HOME/.colima/${profile}/docker.sock${quote}; elif [ -S ${quote}$HOME/.config/colima/${profile}/docker.sock${quote} ]; then export DOCKER_HOST=${quote}unix://$HOME/.config/colima/${profile}/docker.sock${quote}; fi; `;
    }

    function getWrappedCommand(cmdArray, forceColima = false) {
        const useColima = forceColima || (runtimeMode === "colima") || (runtimeMode === "auto" && activeRuntime === "Colima");
        if (!useColima) {
            return cmdArray;
        }
        const cmdStr = cmdArray.join(" ");
        const envCheck = getColimaEnvCheck(false);
        return ["sh", "-c", `${envCheck}${cmdStr}`];
    }

    function wrapDockerCommand(cmdArray) {
        return getWrappedCommand(cmdArray, false);
    }

    function initialize() {
        Proc.runCommand(`${pluginId}.systemdRunCheck`, ["which", "systemd-run"], (stdout, exitCode) => {
            systemdRunAvailable = exitCode === 0;
        }, 100);

        Proc.runCommand(`${pluginId}.colimaCheck`, ["which", "colima"], (stdout, exitCode) => {
            root.colimaAvailable = exitCode === 0;
            PluginService.setGlobalVar(pluginId, "colimaAvailable", colimaAvailable);
            refresh();
        }, 100);
    }

    function refresh() {
        if (runtimeMode === "native") {
            checkNativeDocker();
        } else if (runtimeMode === "colima") {
            checkColima(true);
        } else if (runtimeMode === "podman") {
            checkPodman();
        } else { // "auto"
            checkNativeDocker((success) => {
                if (!success) {
                    if (colimaAvailable) {
                        checkColima(false, (colimaSuccess) => {
                            if (!colimaSuccess) {
                                checkPodman();
                            }
                        });
                    } else {
                        checkPodman();
                    }
                }
            });
        }
    }

    function checkNativeDocker(callback = null) {
        Proc.runCommand(`${pluginId}.dockerCheckNative`, [dockerBinary, "info"], (stdout, exitCode) => {
            const success = exitCode === 0;
            if (success) {
                const stdoutLower = stdout.toLowerCase();
                const isColima = stdoutLower.includes("context: colima") || stdoutLower.includes("name: colima");
                if (isColima && colimaAvailable) {
                    root.activeRuntime = "Colima";
                    root.colimaRunning = true;
                    root.dockerAvailable = true;
                    PluginService.setGlobalVar(pluginId, "activeRuntime", "Colima");
                    PluginService.setGlobalVar(pluginId, "colimaRunning", true);
                    PluginService.setGlobalVar(pluginId, "dockerAvailable", true);
                } else {
                    root.activeRuntime = "Docker";
                    root.dockerAvailable = true;
                    PluginService.setGlobalVar(pluginId, "activeRuntime", "Docker");
                    PluginService.setGlobalVar(pluginId, "dockerAvailable", true);
                }
                fetchContainers();
            } else if (runtimeMode === "native") {
                root.activeRuntime = "None";
                root.dockerAvailable = false;
                PluginService.setGlobalVar(pluginId, "activeRuntime", "None");
                PluginService.setGlobalVar(pluginId, "dockerAvailable", false);
                updateContainers();
            }
            if (callback) callback(success);
        }, 100);
    }

    function checkColima(isForced, callback = null) {
        const cmd = getColimaCommand("status");
        Proc.runCommand(`${pluginId}.colimaStatus`, cmd, (stdout, exitCode) => {
            const isRunning = exitCode === 0;
            root.colimaRunning = isRunning;
            PluginService.setGlobalVar(pluginId, "colimaRunning", colimaRunning);

            if (isRunning) {
                const colimaDockerCmd = getWrappedCommand([dockerBinary, "info"], true);
                Proc.runCommand(`${pluginId}.colimaDockerCheck`, colimaDockerCmd, (stdout, exitCode) => {
                    const dockerWorks = exitCode === 0;
                    root.activeRuntime = "Colima";
                    root.dockerAvailable = dockerWorks;
                    PluginService.setGlobalVar(pluginId, "activeRuntime", "Colima");
                    PluginService.setGlobalVar(pluginId, "dockerAvailable", dockerAvailable);
                    
                    if (dockerWorks) {
                        fetchContainers();
                    } else {
                        updateContainers();
                    }
                    if (callback) callback(true);
                }, 100);
            } else {
                if (isForced || colimaAvailable) {
                    root.activeRuntime = "Colima";
                    root.dockerAvailable = false;
                    PluginService.setGlobalVar(pluginId, "activeRuntime", "Colima");
                    PluginService.setGlobalVar(pluginId, "dockerAvailable", false);
                    updateContainers();
                }
                if (callback) callback(false);
            }
        }, 100);
    }

    function checkPodman(callback = null) {
        const binary = dockerBinary === "docker" ? "podman" : dockerBinary;
        Proc.runCommand(`${pluginId}.podmanCheck`, [binary, "info"], (stdout, exitCode) => {
            const success = exitCode === 0;
            if (success) {
                root.activeRuntime = "Podman";
                root.dockerAvailable = true;
                PluginService.setGlobalVar(pluginId, "activeRuntime", "Podman");
                PluginService.setGlobalVar(pluginId, "dockerAvailable", true);
                fetchContainers();
            } else {
                root.activeRuntime = "None";
                root.dockerAvailable = false;
                PluginService.setGlobalVar(pluginId, "activeRuntime", "None");
                PluginService.setGlobalVar(pluginId, "dockerAvailable", false);
                updateContainers();
            }
            if (callback) callback(success);
        }, 100);
    }

    function fetchContainers() {
        const useColima = (runtimeMode === "colima") || (runtimeMode === "auto" && activeRuntime === "Colima");
        const envCheck = useColima ? getColimaEnvCheck(false) : "";
        const binary = activeRuntime === "Podman" && dockerBinary === "docker" ? "podman" : dockerBinary;
        const cmdStr = `${envCheck}${binary} container inspect $(${binary} container ls -aq)`;
        Proc.runCommand(`${pluginId}.dockerInspect`, ["sh", "-c", cmdStr], (stdout, exitCode) => {
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
        const binary = activeRuntime === "Podman" && dockerBinary === "docker" ? "podman" : dockerBinary;
        const commands = {
            start: [binary, "start", containerId],
            stop: [binary, "stop", containerId],
            restart: [binary, "restart", containerId],
            pause: [binary, "pause", containerId],
            unpause: [binary, "unpause", containerId]
        };

        if (commands[action]) {
            const wrapped = wrapDockerCommand(commands[action]);
            const cmdArray = systemdRunAvailable ? ["systemd-run", "--user", "--scope", "--", ...wrapped] : wrapped;
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

        const binary = activeRuntime === "Podman" && dockerBinary === "docker" ? "podman" : dockerBinary;
        const composeCommands = {
            up: [binary, "compose", "-f", configFile, "up", "-d"],
            down: [binary, "compose", "-f", configFile, "down"],
            restart: [binary, "compose", "-f", configFile, "restart"],
            stop: [binary, "compose", "-f", configFile, "stop"],
            start: [binary, "compose", "-f", configFile, "start"],
            pull: [binary, "compose", "-f", configFile, "pull"],
            logs: null
        };

        if (action === "logs") {
            const envCheck = getColimaEnvCheck(false);
            const cmd = `cd "${workingDir}" && ${envCheck}${binary} compose -f ${configFile} logs -f`;
            Quickshell.execDetached(["sh", "-c", `${terminalApp} -e sh -c '${cmd}'`]);
            return true;
        }

        if (composeCommands[action]) {
            const envCheck = getColimaEnvCheck(false);
            const cmd = ["sh", "-c", `${envCheck}cd "${workingDir}" && ${composeCommands[action].join(" ")}`];
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
        const envCheck = getColimaEnvCheck(false);
        const binary = activeRuntime === "Podman" && dockerBinary === "docker" ? "podman" : dockerBinary;
        Quickshell.execDetached(["sh", "-c", `${terminalApp} -e sh -c '${envCheck}${binary} logs -f ${containerId}'`]);
    }

    function openExec(containerId) {
        const envCheck = getColimaEnvCheck(false);
        const binary = activeRuntime === "Podman" && dockerBinary === "docker" ? "podman" : dockerBinary;
        Quickshell.execDetached(["sh", "-c", `${terminalApp} -e sh -c '${envCheck}${binary} exec -it ${containerId} ${shellPath}'`]);
    }

    function getColimaCommand(action) {
        const cmd = ["colima", action];
        if (colimaProfile && colimaProfile !== "default") {
            cmd.push("-p", colimaProfile);
        }
        return cmd;
    }

    function checkColimaStatus() {
        const cmd = getColimaCommand("status");
        Proc.runCommand(`${pluginId}.colimaStatus`, cmd, (stdout, exitCode) => {
            root.colimaRunning = exitCode === 0;
            PluginService.setGlobalVar(pluginId, "colimaRunning", colimaRunning);
        }, 100);
    }

    property var colimaPollTimer: Timer {
        interval: 2000
        running: false
        repeat: true
        onTriggered: {
            colimaPollCount++;
            const cmd = getColimaCommand("status");
            Proc.runCommand(`${pluginId}.colimaPollStatus`, cmd, (stdout, exitCode) => {
                const isRunning = exitCode === 0;
                
                if (colimaTransitioning === "starting") {
                    if (isRunning) {
                        colimaTransitioning = "";
                        colimaRunning = true;
                        colimaPollTimer.stop();
                        PluginService.setGlobalVar(pluginId, "colimaTransitioning", "");
                        PluginService.setGlobalVar(pluginId, "colimaRunning", true);
                        root.refresh();
                    } else if (colimaPollCount >= 15) { // 30 seconds timeout
                        colimaTransitioning = "";
                        colimaPollTimer.stop();
                        PluginService.setGlobalVar(pluginId, "colimaTransitioning", "");
                        root.refresh();
                    }
                } else if (colimaTransitioning === "stopping") {
                    if (!isRunning) {
                        colimaTransitioning = "";
                        colimaRunning = false;
                        colimaPollTimer.stop();
                        PluginService.setGlobalVar(pluginId, "colimaTransitioning", "");
                        PluginService.setGlobalVar(pluginId, "colimaRunning", false);
                        root.refresh();
                    } else if (colimaPollCount >= 15) {
                        colimaTransitioning = "";
                        colimaPollTimer.stop();
                        PluginService.setGlobalVar(pluginId, "colimaTransitioning", "");
                        root.refresh();
                    }
                } else if (colimaTransitioning === "restarting") {
                    if (isRunning && colimaPollCount > 2) {
                        colimaTransitioning = "";
                        colimaRunning = true;
                        colimaPollTimer.stop();
                        PluginService.setGlobalVar(pluginId, "colimaTransitioning", "");
                        PluginService.setGlobalVar(pluginId, "colimaRunning", true);
                        root.refresh();
                    } else if (colimaPollCount >= 20) { // 40 seconds timeout
                        colimaTransitioning = "";
                        colimaPollTimer.stop();
                        PluginService.setGlobalVar(pluginId, "colimaTransitioning", "");
                        root.refresh();
                    }
                }
            }, 100);
        }
    }

    function executeColimaAction(action) {
        if (!colimaAvailable) return false;

        const cmd = getColimaCommand(action);

        if (cmd) {
            const cmdArray = systemdRunAvailable ? ["systemd-run", "--user", "--scope", "--", ...cmd] : cmd;
            Quickshell.execDetached(cmdArray);
            
            colimaTransitioning = action === "start" ? "starting" : (action === "stop" ? "stopping" : "restarting");
            PluginService.setGlobalVar(pluginId, "colimaTransitioning", colimaTransitioning);
            colimaPollCount = 0;
            colimaPollTimer.start();
            return true;
        }
        return false;
    }

    property var servicePollTimer: Timer {
        interval: 2000
        running: false
        repeat: true
        onTriggered: {
            servicePollCount++;
            root.refresh();
            if (serviceTransitioning === "starting" && root.dockerAvailable) {
                serviceTransitioning = "";
                PluginService.setGlobalVar(pluginId, "serviceTransitioning", "");
                servicePollTimer.stop();
            } else if (serviceTransitioning === "stopping" && !root.dockerAvailable) {
                serviceTransitioning = "";
                PluginService.setGlobalVar(pluginId, "serviceTransitioning", "");
                servicePollTimer.stop();
            } else if (servicePollCount >= 10) {
                serviceTransitioning = "";
                PluginService.setGlobalVar(pluginId, "serviceTransitioning", "");
                servicePollTimer.stop();
            }
        }
    }

    function executeServiceAction(action) {
        let cmd = [];
        const runtime = (activeRuntime === "None" || activeRuntime === "") ? (runtimeMode === "podman" ? "Podman" : "Docker") : activeRuntime;
        
        if (runtime === "Podman") {
            if (action === "start") {
                cmd = ["sh", "-c", "systemctl --user start podman.socket || systemctl start podman.socket"];
            } else if (action === "stop") {
                cmd = ["sh", "-c", "systemctl --user stop podman.socket || systemctl stop podman.socket"];
            } else if (action === "restart") {
                cmd = ["sh", "-c", "systemctl --user restart podman.socket || systemctl restart podman.socket"];
            }
        } else {
            if (action === "start") {
                cmd = ["sh", "-c", "systemctl --user start docker.service || systemctl start docker.service"];
            } else if (action === "stop") {
                cmd = ["sh", "-c", "systemctl --user stop docker.service || systemctl stop docker.service"];
            } else if (action === "restart") {
                cmd = ["sh", "-c", "systemctl --user restart docker.service || systemctl restart docker.service"];
            }
        }

        if (cmd.length > 0) {
            const cmdArray = systemdRunAvailable ? ["systemd-run", "--user", "--scope", "--", ...cmd] : cmd;
            Quickshell.execDetached(cmdArray);
            
            serviceTransitioning = action === "start" ? "starting" : (action === "stop" ? "stopping" : "restarting");
            PluginService.setGlobalVar(pluginId, "serviceTransitioning", serviceTransitioning);
            servicePollCount = 0;
            servicePollTimer.start();
            return true;
        }
        return false;
    }
}
