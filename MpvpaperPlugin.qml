import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Modules.Plugins

PluginComponent {
    id: root

    property var monitorPaths: pluginData.monitorPaths || {}
    property bool allMonitors: pluginData.allMonitors !== undefined ? pluginData.allMonitors : false
    property string allMonitorsPath: pluginData.allMonitorsPath || ""
    property bool noAudio: pluginData.noAudio !== undefined ? pluginData.noAudio : true
    property bool loopPlaylist: pluginData.loopPlaylist !== undefined ? pluginData.loopPlaylist : true
    property bool panscanEnabled: pluginData.panscanEnabled !== undefined ? pluginData.panscanEnabled : true
    property real panscanValue: pluginData.panscanValue !== undefined ? pluginData.panscanValue : 1.0
    property string customMpvOptions: pluginData.customMpvOptions || ""
    property var processes: ({})
    property var previousScreenNames: []
    property bool ready: false
    property var pendingLaunches: ({})

    onPluginDataChanged: {
        if (ready) {
            syncDebounce.restart()
        }
    }

    Timer {
        id: syncDebounce
        interval: 50
        repeat: false
        onTriggered: syncWithData()
    }

    Connections {
        target: Quickshell

        function onScreensChanged() {
            const currentScreenNames = Quickshell.screens.map(screen => screen.name)

            // ALL mode handles monitors internally, no hotplug management needed
            if (allMonitors) {
                previousScreenNames = currentScreenNames
                return
            }

            // Stop processes for disconnected monitors
            const removedScreens = previousScreenNames.filter(name => !currentScreenNames.includes(name))
            for (const screenName of removedScreens) {
                if (processes[screenName]) {
                    console.info("mpvpaper: Display disconnected:", screenName, "- stopping")
                    stopMpvpaper(screenName, false)
                }
            }

            // Restore processes for newly connected monitors
            const newScreens = currentScreenNames.filter(name => !previousScreenNames.includes(name))
            for (const screenName of newScreens) {
                const path = monitorPaths[screenName]
                if (path) {
                    console.info("mpvpaper: Display connected:", screenName, "- restoring:", path)
                    launchMpvpaper(screenName, path)
                }
            }

            previousScreenNames = currentScreenNames
        }
    }

    function escapeRegex(str) {
        return str.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
    }

    function buildMpvOptions() {
        var parts = []
        if (noAudio) parts.push("no-audio")
        if (loopPlaylist) parts.push("--loop-playlist")
        if (panscanEnabled) parts.push("--panscan=" + panscanValue.toFixed(2))
        if (customMpvOptions.trim()) parts.push(customMpvOptions.trim())
        return parts.join(" ")
    }

    function stopAllProcesses() {
        for (const key in processes) {
            stopMpvpaper(key, false)
        }
    }

    function syncWithData() {
        const currentOptions = buildMpvOptions()

        if (allMonitors) {
            console.info("mpvpaper: Syncing in ALL monitors mode")

            // Stop any per-monitor processes from a previous mode
            for (const key in processes) {
                if (key !== "ALL") {
                    stopMpvpaper(key, false)
                }
            }

            if (!allMonitorsPath) {
                if (processes["ALL"]) {
                    stopMpvpaper("ALL", false)
                }
                return
            }

            const proc = processes["ALL"]
            const isPending = pendingLaunches["ALL"]
            const processNotRunning = !proc
            const optionsChanged = proc && proc.launchedOptions !== currentOptions
            const pathChanged = proc && proc.videoPath !== allMonitorsPath

            if ((processNotRunning || optionsChanged || pathChanged) && !isPending) {
                launchMpvpaper("ALL", allMonitorsPath)
            }
            return
        }

        // Per-monitor mode
        console.info("mpvpaper: Syncing in per-monitor mode")
        const connectedMonitors = Quickshell.screens.map(screen => screen.name)

        // Stop the ALL process if switching from all-monitors mode
        if (processes["ALL"]) {
            stopMpvpaper("ALL", false)
        }

        // Stop processes for monitors that no longer have paths
        for (const monitor in processes) {
            if (monitor === "ALL") continue
            if (!monitorPaths[monitor] || !connectedMonitors.includes(monitor)) {
                stopMpvpaper(monitor, false)
            }
        }

        // Launch or restart processes for monitors with paths
        for (const monitor of connectedMonitors) {
            const path = monitorPaths[monitor]
            if (!path) {
                if (processes[monitor]) {
                    stopMpvpaper(monitor, false)
                }
                continue
            }

            const isPending = pendingLaunches[monitor]
            const proc = processes[monitor]
            const processNotRunning = !proc
            const optionsChanged = proc && proc.launchedOptions !== currentOptions
            const pathChanged = proc && proc.videoPath !== path

            if ((processNotRunning || optionsChanged || pathChanged) && !isPending) {
                launchMpvpaper(monitor, path)
            }
        }
    }

    function launchMpvpaper(monitor, path) {
        pendingLaunches[monitor] = true
        stopMpvpaper(monitor, true, path)
    }

    function stopMpvpaper(monitor, startNew, newPath) {
        if (startNew === undefined) startNew = false
        if (newPath === undefined) newPath = ""

        if (processes[monitor]) {
            processes[monitor].running = false
            processes[monitor].destroy()
            delete processes[monitor]
        }

        var killerProc = killerComponent.createObject(root, {
            monitor: monitor,
            startNew: startNew,
            newPath: newPath
        })
        killerProc.running = true
    }

    Component {
        id: mpvpaperProcessComponent

        Process {
            property string monitor: ""
            property string videoPath: ""
            property string launchedOptions: ""

            command: ["mpvpaper", "-o", launchedOptions, monitor, videoPath]

            onExited: (code) => {
                if (code !== 0) {
                    console.warn("mpvpaper: Process exited with code:", code, "for", videoPath, "on", monitor)
                }
            }
        }
    }

    Component {
        id: killerComponent

        Process {
            property string monitor: ""
            property bool startNew: false
            property string newPath: ""

            command: [
                "pkill", "-f", "mpvpaper.*" + escapeRegex(monitor)
            ]

            onExited: () => {
                if (!startNew) {
                    delete pendingLaunches[monitor]
                }
                if (startNew) {
                    var options = buildMpvOptions()
                    var proc = mpvpaperProcessComponent.createObject(root, {
                        monitor: monitor,
                        videoPath: newPath,
                        launchedOptions: options
                    })

                    processes[monitor] = proc
                    proc.running = true
                    delete pendingLaunches[monitor]
                }

                destroy()
            }
        }
    }

    Component.onCompleted: {
        previousScreenNames = Quickshell.screens.map(screen => screen.name)
        console.info("mpvpaper: Plugin starting...")
        ready = true
        syncWithData()
    }

    Component.onDestruction: {
        console.info("mpvpaper: Plugin stopping, cleaning up processes")

        for (const key in processes) {
            if (processes[key]) {
                processes[key].running = false
                processes[key].destroy()
            }
        }

        // Kill any lingering mpvpaper processes
        Quickshell.execDetached(["pkill", "-f", "mpvpaper"])
    }
}
