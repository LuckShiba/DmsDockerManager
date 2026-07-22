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

    SelectionSetting {
        id: runtimeModeSetting
        settingKey: "runtimeMode"
        label: "Container Runtime Mode"
        description: "Choose how the plugin connects to your container runtime."
        defaultValue: DockerService.defaults.runtimeMode
        options: [
            { label: "Auto-detect", value: "auto" },
            { label: "Native Docker", value: "native" },
            { label: "Colima VM", value: "colima" },
            { label: "Podman", value: "podman" }
        ]
    }

    StringSetting {
        settingKey: "colimaProfile"
        label: "Colima Profile"
        description: "The name of the Colima profile to use (default: 'default')."
        defaultValue: DockerService.defaults.colimaProfile
        placeholder: DockerService.defaults.colimaProfile
        visible: runtimeModeSetting.value === "colima" || runtimeModeSetting.value === "auto"
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

    SliderSetting {
        settingKey: "pollingInterval"
        label: "Background Polling Interval"
        description: "Fallback polling interval to refresh container state. Useful when event-based updates don't work reliably in the background. Set to 0 to disable polling."
        defaultValue: DockerService.defaults.pollingInterval
        minimum: 0
        maximum: 120000
        unit: "ms"
        leftIcon: "sync"
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

    ToggleSetting {
        settingKey: "autoScrollOnExpand"
        label: "Auto-scroll on Expand"
        description: "Automatically scroll to show expanded content when expanding containers or projects (smoothly follows the expansion animation)."
        defaultValue: true
    }
}
