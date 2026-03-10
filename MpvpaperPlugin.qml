import QtCore
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
    property bool generateStaticWallpaper: pluginData.generateStaticWallpaper || false
    property int screenshotDelay: pluginData.screenshotDelay !== undefined ? pluginData.screenshotDelay : 5
    property bool periodicRestart: pluginData.periodicRestart || false
    property int restartIntervalMinutes: pluginData.restartIntervalMinutes !== undefined ? pluginData.restartIntervalMinutes : 30
    property bool prevGenerateStaticWallpaper: false
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

    Timer {
        id: restartTimer
        interval: restartIntervalMinutes * 60 * 1000
        repeat: true
        running: periodicRestart && ready
        onTriggered: {
            console.info("mpvpaper: Periodic restart triggered (every", restartIntervalMinutes, "minutes)")
            restartAllProcesses()
        }
    }

    onGenerateStaticWallpaperChanged: {
        if (prevGenerateStaticWallpaper !== generateStaticWallpaper) {
            prevGenerateStaticWallpaper = generateStaticWallpaper
            if (generateStaticWallpaper) {
                if (allMonitors && allMonitorsPath) {
                    var screenName = Quickshell.screens.length > 0 ? Quickshell.screens[0].name : ""
                    if (SettingsData.matugenTargetMonitor) {
                        screenName = SettingsData.matugenTargetMonitor
                    }
                    if (screenName) {
                        generateScreenshot(screenName, allMonitorsPath, true)
                    }
                } else {
                    for (const monitor in monitorPaths) {
                        if (monitorPaths[monitor]) {
                            generateScreenshot(monitor, monitorPaths[monitor])
                        }
                    }
                }
            }
        }
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
        parts.push("load-scripts=no")
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

    function restartAllProcesses() {
        if (allMonitors) {
            if (allMonitorsPath && processes["ALL"]) {
                launchMpvpaper("ALL", allMonitorsPath)
            }
        } else {
            for (const monitor in processes) {
                const path = monitorPaths[monitor]
                if (path) {
                    launchMpvpaper(monitor, path)
                }
            }
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

                    if (root.generateStaticWallpaper) {
                        var isAll = monitor === "ALL"
                        var screenshotMonitor = monitor
                        if (isAll) {
                            screenshotMonitor = Quickshell.screens.length > 0 ? Quickshell.screens[0].name : ""
                            if (SettingsData.matugenTargetMonitor) {
                                screenshotMonitor = SettingsData.matugenTargetMonitor
                            }
                        }
                        if (screenshotMonitor) {
                            generateScreenshot(screenshotMonitor, newPath, isAll)
                        }
                    }
                }

                destroy()
            }
        }
    }

    function generateScreenshot(monitor, videoPath, allScreens) {
        const cacheHome = StandardPaths.writableLocation(StandardPaths.GenericCacheLocation).toString()
        const baseDir = Paths.strip(cacheHome)
        const outDir = baseDir + "/DankMaterialShell/mpvpaper_screenshots"
        const outputPath = outDir + "/" + monitor + "_" + Date.now() + ".jpg"

        Quickshell.execDetached(["mkdir", "-p", outDir])

        var proc = screenshotComponent.createObject(root, {
            monitor: monitor,
            videoPath: videoPath,
            outputPath: outputPath,
            outDir: outDir,
            delay: root.screenshotDelay,
            forAllMonitors: allScreens || false
        })
        proc.running = true
    }

    Component {
        id: setWallpaperTimer

        Timer {
            property string monitor: ""
            property string screenshotPath: ""
            property bool forAllMonitors: false

            running: false
            repeat: false
            interval: 500

            onTriggered: {
                console.info("mpvpaper: Set wallpaper on", monitor, "to", screenshotPath)
                if (!SessionData.perMonitorWallpaper) {
                    SessionData.setPerMonitorWallpaper(true)
                }
                if (forAllMonitors) {
                    for (var i = 0; i < Quickshell.screens.length; i++) {
                        SessionData.setMonitorWallpaper(Quickshell.screens[i].name, screenshotPath)
                    }
                } else {
                    SessionData.setMonitorWallpaper(monitor, screenshotPath)
                }
                destroy()
            }
        }
    }

    Component {
        id: screenshotComponent

        Process {
            property string monitor: ""
            property string videoPath: ""
            property string outputPath: ""
            property string outDir: ""
            property int delay: 5
            property bool forAllMonitors: false

            command: [
                "sh", "-c",
                'video_path="$1"; output="$2"; delay="$3"; outdir="$4"; mon="$5"; ' +
                'rm -f "$outdir"/"$mon"_*.jpg 2>/dev/null; ' +
                'if [ -d "$video_path" ]; then ' +
                '  video_path=$(find "$video_path" -maxdepth 1 -type f \\( ' +
                '    -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.webm" ' +
                '    -o -iname "*.avi" -o -iname "*.mov" -o -iname "*.wmv" ' +
                '    -o -iname "*.flv" -o -iname "*.m4v" -o -iname "*.ts" ' +
                '  \\) | sort | head -1); ' +
                'fi; ' +
                'if [ -z "$video_path" ] || [ ! -f "$video_path" ]; then exit 1; fi; ' +
                'ffmpeg -y -ss "$delay" -i "$video_path" -frames:v 1 -q:v 2 "$output"',
                "_", videoPath, outputPath, String(delay), outDir, monitor
            ]

            onExited: (code) => {
                if (code === 0) {
                    console.info("mpvpaper: Screenshot captured for", monitor, "at", outputPath)
                    var timer = setWallpaperTimer.createObject(root, {
                        monitor: monitor,
                        screenshotPath: outputPath,
                        forAllMonitors: forAllMonitors
                    })
                    timer.running = true
                } else {
                    console.warn("mpvpaper: Screenshot failed for", monitor, "exit code:", code)
                }
                destroy()
            }
        }
    }

    Component.onCompleted: {
        previousScreenNames = Quickshell.screens.map(screen => screen.name)
        console.info("mpvpaper: Plugin starting...")
        prevGenerateStaticWallpaper = generateStaticWallpaper
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
