import QtQuick
import Quickshell
import qs.Common
import qs.Services

Item {
    id: root

    property bool systemdRunAvailable: false
    property int refreshInterval: 5000

    Timer {
        interval: root.refreshInterval
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Component.onCompleted: {
        Proc.runCommand("dockerManager.systemdRunCheck", ["which", "systemd-run"], (stdout, exitCode) => {
            systemdRunAvailable = exitCode === 0;
        }, 100);
    }

    function refresh() {
        Proc.runCommand("dockerManager.dockerCheck", ["docker", "info"], (stdout, exitCode) => {
            const success = exitCode === 0;
            PluginService.setGlobalVar("dockerManager", "dockerAvailable", success);
            if (success) {
                fetchContainers();
            }
        }, 100);
    }

    function fetchContainers() {
        Proc.runCommand("dockerManager.dockerPs", ["docker", "container", "ls", "-a", "--format", "{{ json . }}"], (stdout, exitCode) => {
            if (exitCode === 0) {
                try {
                    const lines = stdout.trim().split("\n").filter(line => line.length > 0);
                    const containers = lines.map(line => {
                        try {
                            const data = JSON.parse(line);
                            const labels = data.Labels || {};
                            const composeProject = labels["com.docker.compose.project"] || labels["io.podman.compose.project"] || "";
                            const composeService = labels["com.docker.compose.service"] || labels["io.podman.compose.service"] || "";
                            const composeWorkingDir = labels["com.docker.compose.project.working_dir"] || "";
                            const composeConfigFiles = labels["com.docker.compose.project.config_files"] || "compose.yaml";
                            const isRunning = data.State === "running";
                            const isPaused = data.State === "paused";
                            const name = Array.isArray(data.Names) ? data.Names[0] : data.Names;

                            return {
                                id: data.Id || "",
                                name: name || "",
                                status: data.Status || "",
                                state: data.State || "",
                                image: data.Image || "",
                                isRunning: isRunning,
                                isPaused: isPaused,
                                created: data.Created || "",
                                composeProject: composeProject,
                                composeService: composeService,
                                composeWorkingDir: composeWorkingDir,
                                composeConfigFiles: composeConfigFiles
                            };
                        } catch (e) {
                            console.error("DockerManager: Failed to parse container JSON:", e, line);
                            return null;
                        }
                    }).filter(c => c !== null).sort((a, b) => {
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

                        return a.name.localeCompare(b.name);
                    });

                    const runningCount = containers.filter(c => c.isRunning).length;

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

                    const projects = Object.values(projectMap).sort((a, b) => {
                        if (a.runningCount !== b.runningCount) {
                            return b.runningCount - a.runningCount;
                        }
                        return a.name.localeCompare(b.name);
                    });
                    updateContainers(containers, runningCount, projects);
                } catch (e) {
                    console.error("DockerManager: Failed to parse docker ps output:", e);
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
