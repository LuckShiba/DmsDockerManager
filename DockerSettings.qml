import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "dockerManager"

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

    SliderSetting {
        settingKey: "debounceDelay"
        label: "Debounce Delay"
        description: "Delay before refreshing container list after Docker events (prevents excessive updates during rapid changes)."
        defaultValue: 300
        minimum: 100
        maximum: 2000
        unit: "ms"
        leftIcon: "schedule"
    }

    StringSetting {
        settingKey: "terminalApp"
        label: "Terminal Application"
        description: "Command used to launch terminal windows for exec and logs."
        defaultValue: "alacritty --hold"
        placeholder: "alacritty --hold"
    }

    StringSetting {
        settingKey: "shellPath"
        label: "Shell Path"
        description: "Shell to use when executing commands in containers (note: many containers will only have /bin/sh installed.)"
        defaultValue: "/bin/sh"
        placeholder: "/bin/sh"
    }
}
