import QtCore
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins
import qs.Modals.FileBrowser

PluginComponent {
    id: root

    // --- Data properties (reactive via pluginData) ---
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

    // --- Multi-instance daemon coordination ---
    PluginGlobalVar {
        id: daemonOwnerVar
        varName: "daemonOwner"
        defaultValue: ""
    }

    PluginGlobalVar {
        id: pausedVar
        varName: "paused"
        defaultValue: false
    }

    property string instanceId: "" + Date.now() + "_" + Math.random()
    readonly property bool isDaemon: daemonOwnerVar.value === instanceId
    readonly property bool paused: pausedVar.value
    property bool _claimAttempted: false

    // --- Status properties (derived from reactive pluginData) ---
    readonly property int configuredMonitorCount: {
        if (allMonitors) return allMonitorsPath ? Quickshell.screens.length : 0
        var count = 0
        for (var m in monitorPaths) {
            if (monitorPaths[m]) count++
        }
        return count
    }

    readonly property string statusText: {
        if (paused) return "Paused"
        if (configuredMonitorCount === 0) return "No videos configured"
        if (allMonitors) return "All monitors"
        return configuredMonitorCount + " monitor(s)"
    }

    readonly property string videoPathDisplay: {
        if (allMonitors && allMonitorsPath) {
            return allMonitorsPath.split("/").pop() || allMonitorsPath
        }
        var paths = []
        for (var m in monitorPaths) {
            if (monitorPaths[m] && paths.indexOf(monitorPaths[m]) === -1) {
                paths.push(monitorPaths[m])
            }
        }
        if (paths.length === 0) return "No video selected"
        if (paths.length === 1) return paths[0].split("/").pop() || paths[0]
        return paths.length + " videos"
    }

    // --- Daemon coordination ---
    // pluginId is set AFTER creation by WidgetHost, so we must wait for it
    onPluginIdChanged: {
        if (pluginId && !_claimAttempted) {
            _claimAttempted = true
            tryClaimDaemon()
        }
    }

    function tryClaimDaemon() {
        if (daemonOwnerVar.value === "") {
            console.info("mpvpaper: Instance", instanceId, "claiming daemon")
            daemonOwnerVar.set(instanceId)
            initDaemon()
        }
    }

    function initDaemon() {
        previousScreenNames = Quickshell.screens.map(screen => screen.name)
        console.info("mpvpaper: Daemon instance starting...")
        prevGenerateStaticWallpaper = generateStaticWallpaper
        ready = true
        if (!paused) {
            syncWithData()
        }
    }

    Connections {
        target: pluginService
        function onGlobalVarChanged(changedPluginId, varName) {
            if (changedPluginId !== root.pluginId) return
            if (varName === "daemonOwner" && daemonOwnerVar.value === "") {
                root.tryClaimDaemon()
            }
        }
    }

    // --- Pause toggle ---
    function togglePause() {
        pausedVar.set(!pausedVar.value)
    }

    onPausedChanged: {
        if (!isDaemon || !ready) return
        if (paused) {
            stopAllProcesses()
        } else {
            syncWithData()
        }
    }

    // --- Data change handler (daemon only) ---
    onPluginDataChanged: {
        if (ready && isDaemon) {
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
        running: periodicRestart && ready && root.isDaemon
        onTriggered: {
            console.info("mpvpaper: Periodic restart triggered (every", restartIntervalMinutes, "minutes)")
            restartAllProcesses()
        }
    }

    onGenerateStaticWallpaperChanged: {
        if (!isDaemon) return
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
            if (!root.isDaemon) return

            const currentScreenNames = Quickshell.screens.map(screen => screen.name)

            if (allMonitors) {
                previousScreenNames = currentScreenNames
                return
            }

            const removedScreens = previousScreenNames.filter(name => !currentScreenNames.includes(name))
            for (const screenName of removedScreens) {
                if (processes[screenName]) {
                    console.info("mpvpaper: Display disconnected:", screenName, "- stopping")
                    stopMpvpaper(screenName, false)
                }
            }

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

    // --- Process management ---
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
        if (paused) return
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
        if (paused) return

        const currentOptions = buildMpvOptions()

        if (allMonitors) {
            console.info("mpvpaper: Syncing in ALL monitors mode")

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

        console.info("mpvpaper: Syncing in per-monitor mode")
        const connectedMonitors = Quickshell.screens.map(screen => screen.name)

        if (processes["ALL"]) {
            stopMpvpaper("ALL", false)
        }

        for (const monitor in processes) {
            if (monitor === "ALL") continue
            if (!monitorPaths[monitor] || !connectedMonitors.includes(monitor)) {
                stopMpvpaper(monitor, false)
            }
        }

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
        if (paused) return
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

    // --- Lifecycle ---
    Component.onCompleted: {
        // pluginId may already be set (e.g. daemon instantiation)
        if (pluginId && !_claimAttempted) {
            _claimAttempted = true
            tryClaimDaemon()
        }
    }

    Component.onDestruction: {
        if (isDaemon) {
            console.info("mpvpaper: Daemon instance stopping, cleaning up processes")

            for (const key in processes) {
                if (processes[key]) {
                    processes[key].running = false
                    processes[key].destroy()
                }
            }

            Quickshell.execDetached(["pkill", "-f", "mpvpaper"])
            daemonOwnerVar.set("")
        }
    }

    // --- File browser for popout ---
    property string browseTargetMonitor: ""

    function browseVideoPath(monitor) {
        browseTargetMonitor = monitor
        videoBrowser.open()
    }

    function clearVideoPath(monitor) {
        if (!pluginService) return
        if (allMonitors) {
            pluginService.savePluginData(pluginId, "allMonitorsPath", "")
        } else {
            var paths = monitorPaths ? Object.assign({}, monitorPaths) : {}
            delete paths[monitor]
            pluginService.savePluginData(pluginId, "monitorPaths", paths)
        }
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
                if (root.allMonitors) {
                    root.pluginService.savePluginData(root.pluginId, "allMonitorsPath", cleanPath)
                } else {
                    var paths = root.monitorPaths ? Object.assign({}, root.monitorPaths) : {}
                    paths[root.browseTargetMonitor] = cleanPath
                    root.pluginService.savePluginData(root.pluginId, "monitorPaths", paths)
                }
                close()
            }
        }
    }

    // --- Bar pills ---
    horizontalBarPill: Component {
        DankIcon {
            name: "wallpaper"
            color: root.paused ? Theme.surfaceVariantText : Theme.primary
            size: root.iconSize
        }
    }

    verticalBarPill: Component {
        DankIcon {
            name: "wallpaper"
            color: root.paused ? Theme.surfaceVariantText : Theme.primary
            size: root.iconSize
        }
    }

    // --- Popout ---
    popoutWidth: 320

    popoutContent: Component {
        PopoutComponent {
            id: popout
            headerText: "Video Wallpaper"
            detailsText: root.statusText
            showCloseButton: true

            Column {
                width: parent.width
                spacing: Theme.spacingM

                // Pause/Resume button
                Rectangle {
                    width: parent.width
                    height: 48
                    radius: Theme.cornerRadius
                    color: pauseArea.containsMouse
                        ? (root.paused ? Qt.lighter(Theme.primaryContainer, 1.1) : Theme.surfaceContainerHighest)
                        : (root.paused ? Theme.primaryContainer : Theme.surfaceContainerHigh)

                    Behavior on color {
                        ColorAnimation { duration: 150 }
                    }

                    Row {
                        anchors.centerIn: parent
                        spacing: Theme.spacingS

                        DankIcon {
                            name: root.paused ? "play_arrow" : "pause"
                            color: root.paused ? Theme.primary : Theme.surfaceText
                            size: Theme.iconSize
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            text: root.paused ? "Resume Playback" : "Pause Playback"
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Medium
                            color: root.paused ? Theme.primary : Theme.surfaceText
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    MouseArea {
                        id: pauseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.togglePause()
                    }
                }

                // Separator
                Rectangle {
                    width: parent.width
                    height: 1
                    color: Theme.outlineVariant
                }

                // Wallpapers section
                Column {
                    width: parent.width
                    spacing: Theme.spacingS

                    Item {
                        width: parent.width
                        height: 30

                        StyledText {
                            text: "WALLPAPERS"
                            font.pixelSize: Theme.fontSizeSmall - 1
                            font.weight: Font.DemiBold
                            color: Theme.surfaceVariantText
                            font.letterSpacing: 1
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            text: "All"
                            font.pixelSize: Theme.fontSizeSmall - 1
                            color: Theme.surfaceVariantText
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.right: allMonSwitch.left
                            anchors.rightMargin: Theme.spacingXS
                        }

                        DankToggle {
                            id: allMonSwitch
                            width: 52
                            height: 30
                            checked: root.allMonitors
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            onToggled: {
                                root.pluginService.savePluginData(root.pluginId, "allMonitors", checked)
                            }
                        }
                    }

                    // All monitors card
                    Rectangle {
                        width: parent.width
                        height: allMonCard.implicitHeight + Theme.spacingS * 2
                        radius: Theme.cornerRadius
                        color: Theme.surfaceContainerHigh
                        visible: root.allMonitors

                        Column {
                            id: allMonCard
                            width: parent.width - Theme.spacingS * 2
                            x: Theme.spacingS
                            y: Theme.spacingS
                            spacing: Theme.spacingXS

                            Row {
                                width: parent.width

                                StyledText {
                                    text: "All Monitors"
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: Font.Medium
                                    color: Theme.surfaceVariantText
                                    width: parent.width - allMonBrowseBtn.width
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Rectangle {
                                    id: allMonBrowseBtn
                                    width: 28
                                    height: 28
                                    radius: 14
                                    color: allMonBrowseArea.containsMouse ? Theme.surfaceContainerHighest : "transparent"

                                    DankIcon {
                                        anchors.centerIn: parent
                                        name: "folder_open"
                                        size: 18
                                        color: Theme.primary
                                    }

                                    MouseArea {
                                        id: allMonBrowseArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.browseVideoPath("ALL")
                                    }
                                }
                            }

                            StyledText {
                                text: root.allMonitorsPath ? root.allMonitorsPath.split("/").pop() : "No video set"
                                font.pixelSize: Theme.fontSizeMedium
                                color: root.allMonitorsPath ? Theme.surfaceText : Theme.surfaceVariantText
                                width: parent.width
                                elide: Text.ElideMiddle
                            }
                        }
                    }

                    // Per-monitor cards
                    Repeater {
                        model: root.allMonitors ? [] : Quickshell.screens

                        Rectangle {
                            required property var modelData
                            width: parent.width
                            height: monCard.implicitHeight + Theme.spacingS * 2
                            radius: Theme.cornerRadius
                            color: Theme.surfaceContainerHigh

                            Column {
                                id: monCard
                                width: parent.width - Theme.spacingS * 2
                                x: Theme.spacingS
                                y: Theme.spacingS
                                spacing: Theme.spacingXS

                                Row {
                                    width: parent.width

                                    StyledText {
                                        text: modelData.name
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.weight: Font.Medium
                                        color: Theme.surfaceVariantText
                                        width: parent.width - monBrowseBtn.width
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    Rectangle {
                                        id: monBrowseBtn
                                        width: 28
                                        height: 28
                                        radius: 14
                                        color: monBrowseArea.containsMouse ? Theme.surfaceContainerHighest : "transparent"

                                        DankIcon {
                                            anchors.centerIn: parent
                                            name: "folder_open"
                                            size: 18
                                            color: Theme.primary
                                        }

                                        MouseArea {
                                            id: monBrowseArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.browseVideoPath(modelData.name)
                                        }
                                    }
                                }

                                StyledText {
                                    text: {
                                        var path = root.monitorPaths[modelData.name] || ""
                                        return path ? path.split("/").pop() : "No video set"
                                    }
                                    font.pixelSize: Theme.fontSizeMedium
                                    color: (root.monitorPaths[modelData.name] || "") ? Theme.surfaceText : Theme.surfaceVariantText
                                    width: parent.width
                                    elide: Text.ElideMiddle
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
