import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Services
import qs.Modals.FileBrowser
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "mpvpaperWallpaper"

    property var monitors: Quickshell.screens.map(screen => screen.name)
    property string selectedMonitor: monitors.length > 0 ? monitors[0] : ""

    onSelectedMonitorChanged: {
        pathField.text = getCurrentPath() || ""
    }

    StyledText {
        text: "mpvpaper Video Wallpaper"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
    }

    StyledText {
        text: "Video wallpapers using mpvpaper"
        font.pixelSize: Theme.fontSizeMedium
        opacity: 0.7
        wrapMode: Text.Wrap
    }

    Rectangle {
        width: parent.width
        height: 1
        color: Theme.outlineStrong
    }

    StyledText {
        text: "Monitor"
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.Medium
    }

    Column {
        width: parent.width
        spacing: 2

        Row {
            width: parent.width
            spacing: Theme.spacingM

            StyledText {
                text: "All Monitors"
                font.pixelSize: Theme.fontSizeSmall
                width: 180
                anchors.verticalCenter: parent.verticalCenter
            }

            DankToggle {
                id: allMonitorsToggle
                anchors.verticalCenter: parent.verticalCenter

                Binding {
                    target: allMonitorsToggle
                    property: "checked"
                    value: loadValue("allMonitors", false)
                }

                onToggled: {
                    saveValue("allMonitors", checked)
                    pathField.text = getCurrentPath() || ""
                }
            }
        }
        StyledText {
            text: "Use the same wallpaper on all monitors with synced playback"
            font.pixelSize: Theme.fontSizeSmall * 0.9
            opacity: 0.5
            width: parent.width
            wrapMode: Text.Wrap
        }
    }

    DankDropdown {
        width: parent.width
        options: root.monitors
        currentValue: root.selectedMonitor || "No monitors"
        enabled: root.monitors.length > 1
        compactMode: true
        visible: !loadValue("allMonitors", false)

        onValueChanged: (value) => {
            root.selectedMonitor = value
        }
    }

    StyledText {
        text: "Current Path: " + (getCurrentPath() || "None")
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.Medium
        wrapMode: Text.Wrap
        width: parent.width
    }

    StyledText {
        text: "Video / Directory Path"
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.Medium
    }

    StyledText {
        text: "Enter a path to a video file or directory of videos"
        font.pixelSize: Theme.fontSizeSmall
        opacity: 0.7
        wrapMode: Text.Wrap
    }

    Row {
        width: parent.width
        spacing: Theme.spacingM

        DankTextField {
            id: pathField
            width: parent.width - browseButton.width - applyButton.width - clearButton.width - Theme.spacingM * 3
            placeholderText: "/home/user/Videos/wallpaper.mp4"
            text: getCurrentPath() || ""
        }

        DankButton {
            id: browseButton
            text: "Browse"
            onClicked: {
                videoBrowser.open()
            }
        }

        DankButton {
            id: applyButton
            text: "Apply"
            enabled: pathField.text.trim() !== ""
            onClicked: {
                setPath(pathField.text.trim())
            }
        }

        DankButton {
            id: clearButton
            text: "Clear"
            enabled: getCurrentPath() !== ""
            onClicked: {
                clearPath()
            }
        }
    }

    Rectangle {
        width: parent.width
        height: 1
        color: Theme.outlineStrong
    }

    StyledText {
        text: "Playback Options"
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.Medium
    }

    Column {
        width: parent.width
        spacing: 2

        Row {
            width: parent.width
            spacing: Theme.spacingM

            StyledText {
                text: "No Audio"
                font.pixelSize: Theme.fontSizeSmall
                width: 180
                anchors.verticalCenter: parent.verticalCenter
            }

            DankToggle {
                id: noAudioToggle
                anchors.verticalCenter: parent.verticalCenter

                Binding {
                    target: noAudioToggle
                    property: "checked"
                    value: loadValue("noAudio", true)
                }

                onToggled: {
                    saveValue("noAudio", checked)
                }
            }
        }
        StyledText {
            text: "Mute audio playback"
            font.pixelSize: Theme.fontSizeSmall * 0.9
            opacity: 0.5
            width: parent.width
            wrapMode: Text.Wrap
        }
    }

    Column {
        width: parent.width
        spacing: 2

        Row {
            width: parent.width
            spacing: Theme.spacingM

            StyledText {
                text: "Loop Playlist"
                font.pixelSize: Theme.fontSizeSmall
                width: 180
                anchors.verticalCenter: parent.verticalCenter
            }

            DankToggle {
                id: loopToggle
                anchors.verticalCenter: parent.verticalCenter

                Binding {
                    target: loopToggle
                    property: "checked"
                    value: loadValue("loopPlaylist", true)
                }

                onToggled: {
                    saveValue("loopPlaylist", checked)
                }
            }
        }
        StyledText {
            text: "Loop video or directory playlist"
            font.pixelSize: Theme.fontSizeSmall * 0.9
            opacity: 0.5
            width: parent.width
            wrapMode: Text.Wrap
        }
    }

    Column {
        width: parent.width
        spacing: 2

        Row {
            width: parent.width
            spacing: Theme.spacingM

            StyledText {
                text: "Scale to Fill"
                font.pixelSize: Theme.fontSizeSmall
                width: 180
                anchors.verticalCenter: parent.verticalCenter
            }

            DankToggle {
                id: panscanToggle
                anchors.verticalCenter: parent.verticalCenter

                Binding {
                    target: panscanToggle
                    property: "checked"
                    value: loadValue("panscanEnabled", true)
                }

                onToggled: {
                    saveValue("panscanEnabled", checked)
                }
            }
        }
        StyledText {
            text: "Scale video to fill the screen using panscan"
            font.pixelSize: Theme.fontSizeSmall * 0.9
            opacity: 0.5
            width: parent.width
            wrapMode: Text.Wrap
        }
    }

    Timer {
        id: panscanDebounceTimer
        interval: 500
        repeat: false
        onTriggered: {
            saveValue("panscanValue", panscanSlider.value / 100)
        }
    }

    Column {
        width: parent.width
        spacing: 2
        visible: loadValue("panscanEnabled", true)

        Row {
            width: parent.width
            height: 24
            spacing: Theme.spacingM

            StyledText {
                text: "Panscan Amount"
                font.pixelSize: Theme.fontSizeSmall
                width: 180
                anchors.verticalCenter: parent.verticalCenter
            }

            DankSlider {
                id: panscanSlider
                width: parent.width - 180 - Theme.spacingM - panscanValueText.width - Theme.spacingM
                minimum: 0
                maximum: 100
                showValue: false
                anchors.verticalCenter: parent.verticalCenter

                Binding {
                    target: panscanSlider
                    property: "value"
                    value: loadValue("panscanValue", 1.0) * 100
                }

                onSliderValueChanged: (newValue) => {
                    panscanDebounceTimer.restart()
                }
            }

            StyledText {
                id: panscanValueText
                text: (panscanSlider.value / 100).toFixed(2)
                font.pixelSize: Theme.fontSizeSmall
                width: 40
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        StyledText {
            text: "0.0 = no crop, 1.0 = fully fill screen"
            font.pixelSize: Theme.fontSizeSmall * 0.9
            opacity: 0.5
            width: parent.width
            wrapMode: Text.Wrap
        }
    }

    Rectangle {
        width: parent.width
        height: 1
        color: Theme.outlineStrong
    }

    StyledText {
        text: "Advanced"
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.Medium
    }

    StyledText {
        text: "Custom mpv Options"
        font.pixelSize: Theme.fontSizeSmall
        font.weight: Font.Medium
    }

    StyledText {
        text: "Additional options appended to the -o string (e.g., --hwdec=auto)"
        font.pixelSize: Theme.fontSizeSmall
        opacity: 0.7
        wrapMode: Text.Wrap
    }

    Row {
        width: parent.width
        spacing: Theme.spacingM

        DankTextField {
            id: customOptionsField
            width: parent.width - applyOptionsButton.width - Theme.spacingM
            placeholderText: "--hwdec=auto"
            text: loadValue("customMpvOptions", "")
        }

        DankButton {
            id: applyOptionsButton
            text: "Apply"
            onClicked: {
                saveValue("customMpvOptions", customOptionsField.text)
            }
        }
    }

    Rectangle {
        width: parent.width
        height: 1
        color: Theme.outlineStrong
    }

    StyledText {
        text: "About"
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.Medium
        width: parent.width
    }

    StyledText {
        text: "This plugin uses mpvpaper to play video files as animated wallpapers.\n\nEach monitor can have its own video path. Directories are supported — mpvpaper will play all videos in the directory when loop playlist is enabled.\n\nRequires mpvpaper to be installed."
        font.pixelSize: Theme.fontSizeSmall
        opacity: 0.7
        wrapMode: Text.Wrap
        width: parent.width
    }

    function getCurrentPath() {
        if (loadValue("allMonitors", false)) {
            return loadValue("allMonitorsPath", "")
        }
        var paths = loadValue("monitorPaths", {})
        return paths[selectedMonitor] || ""
    }

    function setPath(path) {
        if (loadValue("allMonitors", false)) {
            saveValue("allMonitorsPath", path)
        } else {
            var paths = loadValue("monitorPaths", {})
            paths[selectedMonitor] = path
            saveValue("monitorPaths", paths)
        }
        pathField.text = path
    }

    function clearPath() {
        if (loadValue("allMonitors", false)) {
            saveValue("allMonitorsPath", "")
        } else {
            var paths = loadValue("monitorPaths", {})
            delete paths[selectedMonitor]
            saveValue("monitorPaths", paths)
        }
        pathField.text = ""
    }

    Item {
        width: 0
        height: 0
        visible: false

        FileBrowserSurfaceModal {
            id: videoBrowser

            browserTitle: "Select Video"
            browserIcon: "movie"
            browserType: "mpvpaper_video"
            showHiddenFiles: false
            fileExtensions: ["*.mp4", "*.mkv", "*.webm", "*.avi", "*.mov", "*.wmv", "*.flv", "*.m4v", "*.ts", "*.gif"]

            onFileSelected: path => {
                const cleanPath = path.replace(/^file:\/\//, '')
                pathField.text = cleanPath
                setPath(cleanPath)
                close()
            }
        }
    }
}
