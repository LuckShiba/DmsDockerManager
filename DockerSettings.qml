import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: DockerService.pluginId

    StyledText {
        width: parent.width
        text: "Docker Manager Settings"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Configure how Docker containers are monitored and managed from your bar."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    StringSetting {
        settingKey: "dockerBinary"
        label: "Container Runtime Binary"
        description: "Path or name of the container runtime binary to use (e.g., 'docker' or 'podman')."
        defaultValue: DockerService.defaults.dockerBinary
        placeholder: DockerService.defaults.dockerBinary
    }

    SliderSetting {
        settingKey: "debounceDelay"
        label: "Debounce Delay"
        description: "Delay before refreshing container list after Docker events (prevents excessive updates during rapid changes)."
        defaultValue: DockerService.defaults.debounceDelay
        minimum: 100
        maximum: 2000
        unit: "ms"
        leftIcon: "schedule"
    }

    StringSetting {
        settingKey: "terminalApp"
        label: "Terminal Application"
        description: "Command used to launch terminal windows for exec and logs."
        defaultValue: DockerService.defaults.terminalApp
        placeholder: DockerService.defaults.terminalApp
    }

    StringSetting {
        settingKey: "shellPath"
        label: "Shell Path"
        description: "Shell to use when executing commands in containers (note: many containers will only have /bin/sh installed.)"
        defaultValue: DockerService.defaults.shellPath
        placeholder: DockerService.defaults.shellPath
    }

    ToggleSetting {
        settingKey: "showPorts"
        label: "Show Port Mappings"
        description: "Display container port mappings when expanding containers in the widget."
        defaultValue: true
    }
}
