import QtQuick
import QtQuick.Controls
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
        settingKey: "refreshInterval"
        label: "Refresh Interval"
        description: "How often to check Docker container status."
        defaultValue: 5000
        minimum: 1000
        maximum: 30000
        unit: "ms"
        leftIcon: "refresh"
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
