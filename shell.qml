import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Shapes
import QtCore
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Wayland
import "rofi-search.js" as RofiSearch

ShellRoot {
    id: root

    property var launcherConfig: ({})
    property string configPath: ""
    property string loadedConfigText: ""

    function configValue(name, fallback) {
        const value = launcherConfig[name];
        return value === undefined || value === null ? fallback : value;
    }

    function loadConfig() {
        const text = configFile.text();
        if (text === loadedConfigText)
            return;
        loadedConfigText = text;

        try {
            launcherConfig = JSON.parse(text);
        } catch (error) {
            console.warn("wave-launcher: could not parse " + configPath + ": " + error);
        }
    }

    function refreshConfig() {
        const located = StandardPaths.locate(StandardPaths.GenericConfigLocation, "wave-launcher/config.json");
        if (located !== configPath) {
            configPath = located;
            loadedConfigText = "";
            if (located.length === 0)
                launcherConfig = ({});
            return;
        }

        if (located.length > 0)
            configFile.reload();
    }

    readonly property string bgHex: String(configValue("background", "#100e1c"))
    readonly property string fgHex: String(configValue("foreground", "#f4ebfc"))
    readonly property string accentHex: String(configValue("accent", "#c084fc"))
    readonly property string customNamespace: String(configValue("namespace", "wave-launcher"))
    readonly property string fontFamily: String(configValue("font", "BigBlueTermPlus Nerd Font"))
    readonly property bool waveEnabled: configValue("waveEnabled", true) === true
    readonly property bool scrambleEnabled: configValue("scrambleEnabled", true) === true
    readonly property bool backgroundEnabled: configValue("backgroundEnabled", true) === true
    readonly property int maxCharacters: {
        const configured = parseInt(configValue("maxCharacters", 25), 10);
        return isNaN(configured) || configured < 1 ? 25 : configured;
    }
    readonly property string matchingMethod: String(configValue("matching", "normal"))
    readonly property bool normalizeMatch: configValue("normalize", false) === true
    readonly property bool sortMatches: configValue("sort", false) === true
    readonly property string sortingMethod: String(configValue("sortingMethod", "normal"))
    readonly property string matchFieldsSpec: String(configValue("matchFields", "name,generic,exec,categories,keywords"))
    readonly property bool useDrunHistory: configValue("useDrunHistory", true) === true
    readonly property bool preferNameMatch: configValue("preferNameMatch", true) === true
    readonly property int displayDebounceMs: Math.max(0, parseInt(configValue("displayDebounceMs", 150), 10) || 0)

    function colorWithAlpha(hex, alpha) {
        let value = hex.startsWith("#") ? hex.slice(1) : hex;
        const r = parseInt(value.slice(0, 2), 16);
        const g = parseInt(value.slice(2, 4), 16);
        const b = parseInt(value.slice(4, 6), 16);
        return Qt.rgba(r / 255, g / 255, b / 255, alpha);
    }

    function waveOffset(index, amplitude) {
        if (!waveEnabled)
            return 0;
        return Math.sin(wavePhase + index * 0.45)
            * (amplitude === undefined ? 10 : amplitude);
    }

    function optionVerticalOffset(optionIndex) {
        if (optionIndex === 0)
            return -60;
        return 60 + (optionIndex - 1) * 30;
    }

    function entryDisplayName(entry) {
        if (!entry)
            return "";
        return entry.displayName !== undefined ? entry.displayName : (entry.name || "");
    }

    function externalDisplayColumn(line) {
        const columns = String(line).split("\t");
        return columns.length > 1 ? columns[1] : columns[0];
    }

    function truncateDisplayText(text, maxCharacters) {
        const characters = Array.from(String(text));
        if (characters.length <= maxCharacters)
            return characters.join("");
        return characters.slice(0, maxCharacters - 1).join("") + "…";
    }

    property bool commandFallEnabled: false
    readonly property bool fallLettersEnabled: commandFallEnabled
                                               || configValue("fallLettersEnabled", false) === true

    property bool launcherOpen: false
    property bool windowShown: false
    property bool centerQuitAnimating: false
    property bool vignetteOpen: false
    property string query: ""
    property string displayAppName: ""
    property bool showResults: false
    property bool showOptionResults: false
    property bool backspaceHeld: false
    property int selectedIndex: 0
    property int appReloadCounter: 0
    property int drunHistoryReloadCounter: 0
    property real wavePhase: 0
    property bool resultTransitionRunning: false
    property real resultTransitionProgress: 0
    property int resultTransitionSourceRow: 0
    property int resultTransitionDirection: 1
    property real resultTransitionStartBlurWidth: 120
    property int pendingSelectedIndex: 0
    property string outgoingResultName: ""
    property string incomingResultName: ""
    property bool externalMenuMode: false
    property bool externalMenuCompleting: false
    property string externalMenuInputPath: ""
    property string externalMenuResultPath: ""
    property var externalMenuEntries: []
    readonly property real smallResultScale: 16 / 44
    readonly property real smallWaveAmplitude: 10 * smallResultScale

    FileView {
        id: configFile
        path: root.configPath
        preload: root.configPath.length > 0
        watchChanges: true
        printErrors: false
        onLoaded: root.loadConfig()
        onFileChanged: reload()
    }

    Timer {
        interval: 500
        running: true
        repeat: true
        onTriggered: root.refreshConfig()
    }

    Component.onCompleted: refreshConfig()

    readonly property string drunCachePath: {
        const custom = String(root.configValue("drunCache", ""));
        const cacheDir = StandardPaths.writableLocation(StandardPaths.GenericCacheLocation);
        const fileName = custom || "wave-launcher.druncache";
        if (fileName.startsWith("/"))
            return "file://" + fileName;
        return cacheDir ? "file://" + cacheDir + "/" + fileName : "";
    }

    FileView {
        id: drunCacheFile
        path: root.drunCachePath
        preload: true
        onLoadedChanged: {
            if (loaded)
                root.drunHistoryReloadCounter++;
        }
    }

    FileView {
        id: externalMenuInputFile
        path: root.externalMenuInputPath
        preload: root.externalMenuInputPath.length > 0
        onLoaded: root.loadExternalMenuEntries()
    }

    FileView {
        id: externalMenuResultFile
        path: root.externalMenuResultPath
        atomicWrites: true
    }

    readonly property var drunHistory: {
        root.drunHistoryReloadCounter;
        if (!drunCacheFile.loaded)
            return {};
        return RofiSearch.parseDrunHistory(drunCacheFile.text());
    }

    function recordDrunLaunch(entry) {
        if (!entry || !entry.id)
            return;

        const cacheText = drunCacheFile.loaded ? drunCacheFile.text() : "";
        const updated = RofiSearch.recordDrunLaunch(cacheText, entry.id);
        drunCacheFile.setText(updated);
        drunCacheFile.reload();
        drunHistoryReloadCounter++;
    }

    NumberAnimation on wavePhase {
        from: 0
        to: Math.PI * 2
        duration: 1600
        loops: Animation.Infinite
        running: root.windowShown && root.waveEnabled
    }

    NumberAnimation {
        id: resultSwitchAnimation
        target: root
        property: "resultTransitionProgress"
        from: 0
        to: 1
        duration: 260
        easing.type: Easing.OutCubic
        onFinished: root.finishResultTransition()
    }

    Connections {
        target: DesktopEntries
        function onApplicationsChanged() {
            root.appReloadCounter++;
        }
    }

    readonly property var applications: {
        root.appReloadCounter;
        const entries = Array.from(DesktopEntries.applications.values);
        return entries.filter((entry, index, all) =>
            !entry.noDisplay && index === all.findIndex(candidate => candidate.id === entry.id)
        );
    }

    readonly property var preparedApplications: applications.map(entry => RofiSearch.prepareApplication(entry))

    readonly property var results: externalMenuMode
        ? externalMenuEntries
        : searchApplications(query)
    readonly property var topResult: results.length > 0
        ? (results[Math.min(selectedIndex, results.length - 1)] || results[0])
        : null
    readonly property var optionResults: {
        if (!showOptionResults || results.length < 2)
            return [];

        const options = [];
        const activeIndex = Math.min(selectedIndex, results.length - 1);
        const offsets = [-1, 1, 2, 3];
        for (let i = 0; i < offsets.length; i++) {
            const optionIndex = activeIndex + offsets[i];
            options.push(optionIndex >= 0 && optionIndex < results.length
                ? results[optionIndex]
                : null);
        }
        return options;
    }

    function cancelResultTransition() {
        resultSwitchAnimation.stop();
        resultTransitionRunning = false;
        resultTransitionProgress = 0;
    }

    function switchSelection(delta) {
        if (results.length === 0)
            return;

        if (resultTransitionRunning) {
            resultSwitchAnimation.stop();
            finishResultTransition();
        }

        const nextIndex = selectedIndex + delta;
        if (nextIndex < 0 || nextIndex >= results.length)
            return;

        if (!showResults) {
            selectedIndex = nextIndex;
            return;
        }

        const incomingEntry = results[nextIndex];
        const options = optionResults;
        let sourceRow = 0;
        for (let i = 0; i < options.length; i++) {
            if (options[i]
                    && (options[i] === incomingEntry || options[i].id === incomingEntry.id)) {
                sourceRow = i;
                break;
            }
        }

        outgoingResultName = displayAppName;
        resultTransitionStartBlurWidth = launcherShadow.width;
        incomingResultName = entryDisplayName(incomingEntry);
        pendingSelectedIndex = nextIndex;
        resultTransitionSourceRow = sourceRow;
        resultTransitionDirection = delta;
        resultTransitionProgress = 0;
        resultTransitionRunning = true;
        resultSwitchAnimation.restart();
    }

    function finishResultTransition() {
        if (!resultTransitionRunning)
            return;

        selectedIndex = pendingSelectedIndex;
        displayAppName = incomingResultName;
        appNameContainer.setTextImmediately(incomingResultName);
        resultTransitionRunning = false;
        resultTransitionProgress = 0;
    }

    function loadExternalMenuEntries() {
        if (!externalMenuMode || !externalMenuInputFile.loaded)
            return;

        const lines = externalMenuInputFile.text().split(/\r?\n/);
        if (lines.length > 0 && lines[lines.length - 1] === "")
            lines.pop();

        externalMenuEntries = lines.map((line, index) => {
            const displayColumn = externalDisplayColumn(line);
            return {
                id: "external-menu-" + index,
                name: displayColumn,
                displayName: truncateDisplayText(displayColumn, root.maxCharacters),
                value: line,
                genericName: "",
                execString: "",
                categories: [],
                keywords: [],
                comment: ""
            };
        });

        if (externalMenuEntries.length === 0) {
            finishExternalMenu("cancelled", "");
            return;
        }

        open();
        showResults = true;
        showOptionResults = true;
        resultsShowDelay.stop();
        optionResultsShowDelay.stop();
        selectedIndex = 0;
        updateDisplayAppName();
    }

    function showExternalMenu(inputPath, resultPath) {
        if (externalMenuMode)
            finishExternalMenu("cancelled", "");

        externalMenuEntries = [];
        externalMenuResultPath = resultPath;
        externalMenuMode = true;
        externalMenuCompleting = false;
        externalMenuInputPath = inputPath;
    }

    function finishExternalMenu(status, value) {
        if (!externalMenuMode)
            return;

        externalMenuCompleting = true;
        externalMenuResultFile.setText(status + "\n" + (status === "selected" ? value + "\n" : ""));
        close();
        externalMenuMode = false;
        externalMenuEntries = [];
        externalMenuCompleting = false;
    }

    function updateDisplayAppName() {
        if (externalMenuMode) {
            displayAppName = topResult ? entryDisplayName(topResult) : query.trim();
            return;
        }

        if (query.trim().length === 0) {
            displayAppName = "";
            return;
        }
        if (!showResults) {
            displayAppName = query.trim();
            return;
        }
        if (topResult)
            displayAppName = entryDisplayName(topResult);
        else
            displayAppName = query.trim();
    }

    Timer {
        id: resultsShowDelay
        interval: root.displayDebounceMs
        onTriggered: {
            root.showResults = true;
            updateDisplayAppName();
        }
    }

    Timer {
        id: optionResultsShowDelay
        interval: 500
        onTriggered: root.showOptionResults = true
    }

    onQueryChanged: {
        if (resultTransitionRunning)
            cancelResultTransition();

        if (externalMenuMode) {
            showResults = true;
            showOptionResults = true;
            resultsShowDelay.stop();
            optionResultsShowDelay.stop();
            selectedIndex = 0;
            updateDisplayAppName();
            return;
        }

        if (query.trim().length === 0) {
            resultsShowDelay.stop();
            optionResultsShowDelay.stop();
            showResults = false;
            showOptionResults = false;
            displayAppName = "";
            selectedIndex = 0;
            return;
        }

        showResults = false;
        showOptionResults = false;
        displayAppName = query.trim();
        if (!backspaceHeld) {
            resultsShowDelay.restart();
            optionResultsShowDelay.restart();
        }
        selectedIndex = 0;
    }

    onSelectedIndexChanged: {
        if (resultTransitionRunning)
            return;
        if (selectedIndex === 0)
            return;
        showResults = true;
        showOptionResults = true;
        resultsShowDelay.stop();
        optionResultsShowDelay.stop();
        updateDisplayAppName();
    }

    function searchApplications(text) {
        if (text.trim().length === 0)
            return [];

        return RofiSearch.search(text, preparedApplications, {
            matchingMethod: root.matchingMethod,
            normalizeMatch: root.normalizeMatch,
            sort: root.sortMatches,
            sortingMethod: root.sortingMethod,
            matchFieldsSpec: root.matchFieldsSpec,
            drunHistory: root.drunHistory,
            useDrunHistory: root.useDrunHistory,
            preferNameMatch: root.preferNameMatch
        });
    }

    function open() {
        cancelResultTransition();
        hideDelay.stop();
        physicsLayer.fallingOffScreen = false;
        physicsLayer.resetAllLetters();
        query = "";
        displayAppName = "";
        showResults = false;
        showOptionResults = false;
        backspaceHeld = false;
        resultsShowDelay.stop();
        optionResultsShowDelay.stop();
        selectedIndex = 0;
        windowShown = true;
        launcherOpen = true;
        vignetteOpen = false;
        vignetteFadeInDelay.restart();
        focusDelay.restart();
    }

    function close() {
        if (externalMenuMode && !externalMenuCompleting) {
            finishExternalMenu("cancelled", "");
            return;
        }

        cancelResultTransition();
        vignetteFadeInDelay.stop();
        vignetteOpen = false;
        launcherOpen = false;
        backspaceHeld = false;
        if (root.fallLettersEnabled)
            physicsLayer.triggerFallThrough();
        hideDelay.restart();
    }

    function toggle() {
        if (launcherOpen)
            close();
        else
            open();
    }

    function launchSelected() {
        if (resultTransitionRunning) {
            resultSwitchAnimation.stop();
            finishResultTransition();
        }

        const entry = topResult;
        if (externalMenuMode) {
            if (entry)
                finishExternalMenu("selected", entry.value);
            return;
        }

        if (entry) {
            recordDrunLaunch(entry);
            close();
            entry.execute();
            return;
        }

        const command = query.trim();
        if (command.length === 0)
            return;

        const shell = Quickshell.env("SHELL") || "/bin/sh";
        close();
        Quickshell.execDetached([shell, "-lc", command]);
    }

    IpcHandler {
        target: "launcher"

        function toggle(): void {
            root.commandFallEnabled = false;
            root.toggle();
        }
        function toggleFall(): void {
            root.commandFallEnabled = true;
            root.toggle();
        }
        function open(): void {
            root.commandFallEnabled = false;
            root.open();
        }
        function openFall(): void {
            root.commandFallEnabled = true;
            root.open();
        }
        function close(): void { root.close(); }
        function showMenu(inputPath: string, resultPath: string): void {
            root.showExternalMenu(inputPath, resultPath);
        }
        function accept(): void { root.launchSelected(); }
    }

    Timer {
        id: vignetteFadeInDelay
        interval: 16
        onTriggered: root.vignetteOpen = true
    }

    Timer {
        id: focusDelay
        interval: 40
        onTriggered: {
            if (root.launcherOpen) {
                hiddenInput.text = "";
                hiddenInput.forceActiveFocus();
            }
        }
    }

    Timer {
        id: hideDelay
        interval: 1500
        onTriggered: {
            if (!root.launcherOpen) {
                root.windowShown = false;
                root.query = "";
                root.displayAppName = "";
                root.showResults = false;
                root.showOptionResults = false;
                resultsShowDelay.stop();
                optionResultsShowDelay.stop();
                root.selectedIndex = 0;
                physicsLayer.resetAllLetters();
                physicsLayer.fallingOffScreen = false;
            }
        }
    }

    PanelWindow {
        id: window

        visible: root.windowShown
        color: "transparent"
        surfaceFormat.opaque: false
        aboveWindows: true
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: root.customNamespace
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.launcherOpen
                                     ? WlrKeyboardFocus.Exclusive
                                     : WlrKeyboardFocus.None
        mask: root.launcherOpen ? null : clickThroughMask
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        Region {
            id: clickThroughMask
        }

        ShortcutInhibitor {
            window: window
            enabled: root.launcherOpen
        }

        Item {
            id: vignette
            anchors.centerIn: parent
            z: 0
            opacity: root.vignetteOpen ? 1 : 0
            visible: opacity > 0.001

            readonly property real blobBaseWidth: 120
            readonly property real blobHeight: 110
            readonly property real blobPadding: 88
            readonly property real transitionTextScale:
                Math.max(root.smallResultScale, incomingTransitionLabel.fontSize / 44)
            readonly property real transitionFinalWidth: Math.max(
                blobBaseWidth,
                incomingTransitionRow.width / transitionTextScale + blobPadding
            )
            readonly property real targetWidth: root.resultTransitionRunning
                ? root.resultTransitionStartBlurWidth
                  + (transitionFinalWidth - root.resultTransitionStartBlurWidth)
                    * root.resultTransitionProgress
                : Math.max(blobBaseWidth, centerMenu.width + blobPadding)

            Behavior on opacity {
                NumberAnimation {
                    duration: root.vignetteOpen ? 320 : 340
                    easing.type: root.vignetteOpen ? Easing.OutCubic : Easing.InCubic
                }
            }

            RectangularShadow {
                id: launcherShadow
                visible: root.backgroundEnabled
                anchors.centerIn: parent
                width: vignette.targetWidth
                height: vignette.blobHeight
                radius: vignette.blobHeight / 2
                blur: 88
                spread: 8
                offset.x: 0
                offset.y: 0
                color: root.colorWithAlpha(root.bgHex, 0.72)

                Behavior on width {
                    enabled: !root.resultTransitionRunning
                    NumberAnimation {
                        duration: 260
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }

        // Invisible text input capturing keystrokes
        TextInput {
            id: hiddenInput
            anchors.fill: parent
            opacity: 0
            focus: true
            readOnly: root.externalMenuMode
            text: root.query

            onTextEdited: {
                if (text.length > root.query.length) {
                    const newChars = text.slice(root.query.length);
                    if (root.fallLettersEnabled) {
                        for (let i = 0; i < newChars.length; i++)
                            physicsLayer.spawnLetter(newChars[i]);
                    }
                } else if (text.length < root.query.length) {
                    if (root.fallLettersEnabled) {
                        const deleteCount = root.query.length - text.length;
                        for (let i = 0; i < deleteCount; i++)
                            physicsLayer.dropLastLetter();
                    }
                }
                root.query = text;
            }

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    event.accepted = true;
                    root.close();
                } else if (event.key === Qt.Key_Backspace) {
                    if (!event.isAutoRepeat)
                        root.backspaceHeld = true;
                    if (root.fallLettersEnabled && hiddenInput.text.length === 0) {
                        physicsLayer.dropLastLetter();
                    }
                } else if (event.key === Qt.Key_Up
                           || event.key === Qt.Key_Backtab
                           || (event.key === Qt.Key_Tab
                               && (event.modifiers & Qt.ShiftModifier) !== 0)) {
                    root.switchSelection(-1);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) {
                    root.switchSelection(1);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    root.launchSelected();
                    event.accepted = true;
                }
            }

            Keys.onReleased: event => {
                if (event.key !== Qt.Key_Backspace || event.isAutoRepeat)
                    return;

                root.backspaceHeld = false;
                if (!root.externalMenuMode && root.query.trim().length > 0) {
                    resultsShowDelay.restart();
                    optionResultsShowDelay.restart();
                }
            }
        }

        // Click transparent area to close
        MouseArea {
            anchors.fill: parent
            z: 1
            onClicked: root.close()
        }

        // Optional physics layer, controlled by fallLettersEnabled in config.json.
        Item {
            id: physicsLayer
            anchors.fill: parent
            z: 5
            visible: root.fallLettersEnabled

            readonly property int poolSize: 100
            property var letterPool: []
            property int nextPoolIndex: 0
            property real lastTime: Date.now()

            Component {
                id: letterDelegate
                Item {
                    id: letterItem
                    width: 140
                    height: 140
                    visible: active

                    property bool active: false
                    property bool droppingOut: false
                    property string letter: ""
                    property color letterColor: root.fgHex
                    property real px: 0
                    property real py: -150
                    property real vx: 0
                    property real vy: 0
                    property real prot: 0
                    property real vrot: 0
                    property real restitution: 0.62
                    property bool settled: false

                    x: px - width / 2
                    y: py - height / 2
                    rotation: prot

                    // 3D Shadow layers (darker shade shifted horizontally)
                    Text {
                        anchors.centerIn: parent
                        anchors.horizontalCenterOffset: 6
                        anchors.verticalCenterOffset: 2
                        text: letterItem.letter
                        color: Qt.darker(root.accentHex, 3.0)
                        font.family: root.fontFamily
                        font.pixelSize: 128
                        font.bold: true
                    }

                    Text {
                        anchors.centerIn: parent
                        anchors.horizontalCenterOffset: 3
                        anchors.verticalCenterOffset: 1
                        text: letterItem.letter
                        color: Qt.darker(root.accentHex, 2.0)
                        font.family: root.fontFamily
                        font.pixelSize: 128
                        font.bold: true
                    }

                    // Foreground Letter
                    Text {
                        anchors.centerIn: parent
                        text: letterItem.letter
                        color: letterItem.letterColor
                        font.family: root.fontFamily
                        font.pixelSize: 128
                        font.bold: true
                    }

                    MouseArea {
                        anchors.fill: parent
                        onPressed: {
                            letterItem.settled = false;
                            letterItem.vy = -350 - Math.random() * 200;
                            letterItem.vx = (Math.random() - 0.5) * 450;
                            letterItem.vrot = (Math.random() - 0.5) * 600;
                        }
                    }
                }
            }

            property var letterStack: []

            function spawnLetter(char) {
                if (letterPool.length === 0) return;
                const item = letterPool[nextPoolIndex];
                nextPoolIndex = (nextPoolIndex + 1) % poolSize;

                const startX = Math.random() * (window.width - 280) + 140;

                item.letter = char;
                item.letterColor = root.fgHex;
                item.px = startX;
                item.py = -100 - Math.random() * 60;
                item.vx = (Math.random() - 0.5) * 350;
                item.vy = Math.random() * 250 + 350;
                item.prot = (Math.random() - 0.5) * 60;
                item.vrot = (Math.random() - 0.5) * 500;
                item.settled = false;
                item.droppingOut = false;
                item.active = true;

                letterStack.push(item);
            }

            function dropLastLetter() {
                while (letterStack.length > 0) {
                    const item = letterStack.pop();
                    if (item && item.active && !item.droppingOut) {
                        item.droppingOut = true;
                        item.settled = false;
                        item.vy = Math.max(item.vy, 450) + 600 + Math.random() * 300;
                        item.vrot = (item.vrot || 0) + (Math.random() - 0.5) * 500;
                        break;
                    }
                }
            }

            property bool fallingOffScreen: false

            function triggerFallThrough() {
                fallingOffScreen = true;
                let activeCount = 0;
                for (let i = 0; i < letterPool.length; i++) {
                    const item = letterPool[i];
                    if (item.active) {
                        item.settled = false;
                        item.vy = Math.max(item.vy, 500) + 600 + Math.random() * 400;
                        item.vx = (item.vx || 0) + (Math.random() - 0.5) * 150;
                        item.vrot = (item.vrot || 0) + (Math.random() - 0.5) * 500;
                        activeCount++;
                    }
                }
                if (activeCount === 0) {
                    root.windowShown = false;
                    fallingOffScreen = false;
                }
            }

            function resetAllLetters() {
                letterStack = [];
                for (let i = 0; i < letterPool.length; i++) {
                    letterPool[i].active = false;
                    letterPool[i].droppingOut = false;
                    letterPool[i].py = -200;
                    letterPool[i].settled = true;
                }
            }

            Timer {
                id: physicsTimer
                interval: 8
                running: root.windowShown && root.fallLettersEnabled
                repeat: true

                onTriggered: {
                    const now = Date.now();
                    const dt = Math.min((now - physicsLayer.lastTime) / 1000, 0.033);
                    physicsLayer.lastTime = now;

                    if (dt <= 0) return;

                    const floorY = window.height - 15;
                    const pool = physicsLayer.letterPool;
                    const poolLen = pool.length;

                    // Circular Center Collider
                    const centerX = centerMenu.x + centerMenu.width / 2;
                    const centerY = centerMenu.y + centerMenu.height / 2;
                    const centerRadius = 60;

                    let anyLetterOnScreen = false;

                    for (let i = 0; i < poolLen; i++) {
                        const b = pool[i];
                        if (!b.active) continue;

                        const half = b.width / 2;

                        if ((physicsLayer.fallingOffScreen || b.droppingOut) && (b.py - half > window.height + 60)) {
                            b.active = false;
                            b.droppingOut = false;
                            continue;
                        }

                        if (b.active) {
                            anyLetterOnScreen = true;
                        }

                        if (b.settled) continue;

                        const gravity = (physicsLayer.fallingOffScreen || b.droppingOut) ? 5500 : 3800;
                        b.vy += gravity * dt;
                        b.vx *= Math.pow(0.993, dt * 60);
                        b.vrot *= Math.pow(0.978, dt * 60);

                        b.px += b.vx * dt;
                        b.py += b.vy * dt;
                        b.prot += b.vrot * dt;

                        // 1. Floor collision (only active while launcher is open and letter is not dropping out)
                        if (!physicsLayer.fallingOffScreen && !b.droppingOut && b.py + half >= floorY) {
                            b.py = floorY - half;
                            b.vy = -b.vy * b.restitution;
                            b.vx *= 0.82;
                            b.vrot = -b.vx * 2.0 + (Math.random() - 0.5) * 30;

                            if (Math.abs(b.vy) < 25 && Math.abs(b.vx) < 15) {
                                b.vy = 0;
                                b.vx = 0;
                                b.vrot = 0;
                                b.settled = true;
                            }
                        }

                        // 2. Wall collisions
                        if (b.px - half <= 20) {
                            b.px = 20 + half;
                            b.vx = Math.abs(b.vx) * b.restitution;
                            b.vrot += b.vy * 0.3;
                        } else if (b.px + half >= window.width - 20) {
                            b.px = window.width - 20 - half;
                            b.vx = -Math.abs(b.vx) * b.restitution;
                            b.vrot -= b.vy * 0.3;
                        }

                        // 3. Center Circle Deflection (only active while launcher is open)
                        if (!physicsLayer.fallingOffScreen) {
                            const dx = b.px - centerX;
                            const dy = b.py - centerY;
                            const dist = Math.sqrt(dx * dx + dy * dy);
                            const targetDist = centerRadius + half;

                            if (dist < targetDist && dist > 0.001) {
                                const nx = dx / dist;
                                const ny = dy / dist;
                                b.px = centerX + nx * targetDist;
                                b.py = centerY + ny * targetDist;

                                const velAlongNorm = b.vx * nx + b.vy * ny;
                                if (velAlongNorm < 0) {
                                    b.vx -= (1 + b.restitution) * velAlongNorm * nx;
                                    b.vy -= (1 + b.restitution) * velAlongNorm * ny;
                                    b.vrot += (nx < 0 ? -1 : 1) * 200;
                                }
                            }
                        }
                    }

                    // Once all letters have fallen below the window, hide the window
                    if (physicsLayer.fallingOffScreen && !anyLetterOnScreen && !root.launcherOpen
                            && !root.centerQuitAnimating) {
                        root.windowShown = false;
                        physicsLayer.resetAllLetters();
                        physicsLayer.fallingOffScreen = false;
                    }

                    // 4. Pairwise Letter Collisions
                    for (let i = 0; i < poolLen; i++) {
                        const bi = pool[i];
                        if (!bi.active) continue;

                        for (let j = i + 1; j < poolLen; j++) {
                            const bj = pool[j];
                            if (!bj.active) continue;
                            if (bi.settled && bj.settled) continue;

                            const dx = bj.px - bi.px;
                            const dy = bj.py - bi.py;
                            const distSq = dx * dx + dy * dy;
                            const minDist = 100;

                            if (distSq < minDist * minDist && distSq > 0.001) {
                                const dist = Math.sqrt(distSq);
                                const nx = dx / dist;
                                const ny = dy / dist;
                                const overlap = minDist - dist;

                                bi.px -= nx * overlap * 0.5;
                                bi.py -= ny * overlap * 0.5;
                                bj.px += nx * overlap * 0.5;
                                bj.py += ny * overlap * 0.5;

                                bi.settled = false;
                                bj.settled = false;

                                const rvx = bj.vx - bi.vx;
                                const rvy = bj.vy - bi.vy;
                                const velAlongNormal = rvx * nx + rvy * ny;

                                if (velAlongNormal < 0) {
                                    const impulse = -(1 + 0.6) * velAlongNormal / 2;
                                    bi.vx -= nx * impulse;
                                    bi.vy -= ny * impulse;
                                    bj.vx += nx * impulse;
                                    bj.vy += ny * impulse;
                                }
                            }
                        }
                    }
                }
            }

            Component.onCompleted: {
                const arr = [];
                for (let i = 0; i < poolSize; i++) {
                    const item = letterDelegate.createObject(physicsLayer);
                    arr.push(item);
                }
                letterPool = arr;
            }
        }

        // Center Menu: Wavy Center App Name
        Item {
            id: centerMenu
            anchors.centerIn: parent
            width: waveRow.width
            height: 64
            z: 10

            readonly property string appNameStr: root.displayAppName

            // Center App Name Display with individual wavy up/down letters
            Item {
                id: appNameContainer
                anchors.centerIn: parent
                anchors.verticalCenterOffset: root.resultTransitionRunning
                    ? root.optionVerticalOffset(root.resultTransitionDirection > 0 ? 0 : 1)
                      * root.resultTransitionProgress
                    : 0
                width: waveRow.width
                height: 64
                transformOrigin: Item.Center
                opacity: root.resultTransitionRunning
                         ? 1 - 0.62 * root.resultTransitionProgress : 1
                scale: root.resultTransitionRunning
                       ? 1 - (1 - root.smallResultScale) * root.resultTransitionProgress : 1

                readonly property string scrambleCharset: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
                readonly property int scrambleTickMs: 20
                readonly property int revealStaggerMs: 24
                readonly property real transitionWaveIndexOffset:
                    root.resultTransitionRunning
                    ? (root.incomingResultName.length - root.outgoingResultName.length)
                      / 2 * root.resultTransitionProgress
                    : 0

                property int scrambleClock: 0
                property string pendingScrambleTarget: ""
                property string committedScrambleTarget: ""
                property int pendingRevealIndex: -1
                property int nextRevealAt: 0
                property int pendingRetractIndex: -1
                property int retractTargetLen: 0
                property int nextRetractAt: 0
                property bool retractingTail: false
                property bool quitAnimating: false
                property int quitScrambleClock: 0
                property real quitProgress: 0
                property int quitAnimDurationMs: 300
                readonly property int quitStaggerStepMs: 20
                readonly property int quitLetterFadeMs: 240

                ListModel {
                    id: charScrambleModel
                }

                function scrambleDurationForIndex(index) {
                    return scrambleTickMs * (3 + Math.min(index, 4));
                }

                function settleTimeForIndex(index, now) {
                    return now + scrambleDurationForIndex(index);
                }

                function randomScrambleChar(exclude) {
                    const charset = appNameContainer.scrambleCharset;
                    if (!exclude || exclude === " " || charset.length <= 1)
                        return charset.charAt(Math.floor(Math.random() * charset.length));

                    let candidate;
                    do {
                        candidate = charset.charAt(Math.floor(Math.random() * charset.length));
                    } while (candidate === exclude);
                    return candidate;
                }

                function appendScrambleSlot(index, ch, now) {
                    charScrambleModel.append({
                        displayChar: ch === " " ? " " : randomScrambleChar(ch),
                        targetChar: ch,
                        settleAt: ch === " " ? 0 : settleTimeForIndex(index, now)
                    });
                }

                function hasActiveScrambles(now) {
                    const clock = now !== undefined ? now : Date.now();
                    for (let i = 0; i < charScrambleModel.count; i++) {
                        if (charScrambleModel.get(i).settleAt > clock)
                            return true;
                    }
                    return false;
                }

                function hasPendingReveal() {
                    return pendingRevealIndex >= 0
                        && pendingRevealIndex < committedScrambleTarget.length;
                }

                function hasPendingRetract() {
                    return pendingRetractIndex >= retractTargetLen;
                }

                function tryRetractNext(now) {
                    if (!hasPendingRetract())
                        return;

                    if (now < nextRetractAt)
                        return;

                    pendingRetractIndex = Math.min(pendingRetractIndex, charScrambleModel.count - 1);
                    if (!hasPendingRetract())
                        return;

                    const slot = charScrambleModel.get(pendingRetractIndex);
                    if (slot.targetChar !== "") {
                        charScrambleModel.setProperty(pendingRetractIndex, "targetChar", "");
                        charScrambleModel.setProperty(
                            pendingRetractIndex,
                            "settleAt",
                            now + revealStaggerMs
                        );
                    }

                    pendingRetractIndex--;
                    nextRetractAt = now + revealStaggerMs;

                    if (pendingRetractIndex < retractTargetLen)
                        pendingRetractIndex = -1;
                }

                function tryRevealNext(now) {
                    if (!hasPendingReveal())
                        return;

                    if (now < nextRevealAt)
                        return;

                    appendScrambleSlot(
                        pendingRevealIndex,
                        committedScrambleTarget.charAt(pendingRevealIndex),
                        now
                    );
                    pendingRevealIndex++;
                    nextRevealAt = now + revealStaggerMs;

                    if (pendingRevealIndex >= committedScrambleTarget.length)
                        pendingRevealIndex = -1;
                }

                function scheduleScramble(target) {
                    if (!root.scrambleEnabled) {
                        setTextImmediately(target);
                        return;
                    }
                    pendingScrambleTarget = target;
                    scrambleScheduleTimer.restart();
                }

                function clearScramble() {
                    scrambleScheduleTimer.stop();
                    scrambleTimer.stop();
                    quitScrambleTimer.stop();
                    quitProgressAnim.stop();
                    quitAnimating = false;
                    root.centerQuitAnimating = false;
                    quitProgress = 0;
                    pendingScrambleTarget = "";
                    committedScrambleTarget = "";
                    pendingRevealIndex = -1;
                    pendingRetractIndex = -1;
                    retractTargetLen = 0;
                    retractingTail = false;
                    charScrambleModel.clear();
                }

                function setTextImmediately(target) {
                    scrambleScheduleTimer.stop();
                    scrambleTimer.stop();
                    pendingScrambleTarget = target;
                    committedScrambleTarget = target;
                    pendingRevealIndex = -1;
                    pendingRetractIndex = -1;
                    retractTargetLen = target.length;
                    retractingTail = false;
                    scrambleClock = Date.now();
                    charScrambleModel.clear();

                    for (let i = 0; i < target.length; i++) {
                        const ch = target.charAt(i);
                        charScrambleModel.append({
                            displayChar: ch,
                            targetChar: ch,
                            settleAt: 0
                        });
                    }
                }

                function quitEase(t) {
                    return t * t * t;
                }

                function beginQuitScramble() {
                    if (charScrambleModel.count === 0)
                        return;

                    quitAnimating = true;
                    root.centerQuitAnimating = true;
                    scrambleTimer.stop();
                    scrambleScheduleTimer.stop();
                    const now = Date.now();
                    scrambleClock = now;
                    quitScrambleClock = now;
                    quitProgress = 0;

                    const centerIdx = (charScrambleModel.count - 1) / 2;
                    quitAnimDurationMs = Math.round(centerIdx * quitStaggerStepMs + quitLetterFadeMs);

                    for (let i = 0; i < charScrambleModel.count; i++) {
                        const slot = charScrambleModel.get(i);
                        charScrambleModel.setProperty(i, "settleAt", now + 999999999);
                        if (root.scrambleEnabled && slot.targetChar !== " ")
                            charScrambleModel.setProperty(i, "displayChar", randomScrambleChar(slot.targetChar));
                    }

                    if (root.scrambleEnabled)
                        quitScrambleTimer.start();
                    quitProgressAnim.duration = quitAnimDurationMs;
                    quitProgressAnim.restart();
                }

                function tickQuitScramble() {
                    const now = Date.now();
                    quitScrambleClock = now;
                    scrambleClock = now;

                    for (let i = 0; i < charScrambleModel.count; i++) {
                        const slot = charScrambleModel.get(i);
                        if (slot.targetChar === " ")
                            continue;
                        charScrambleModel.setProperty(i, "displayChar", randomScrambleChar(slot.targetChar));
                    }
                }

                function sharedPrefixLength(a, b) {
                    const n = Math.min(a.length, b.length);
                    for (let i = 0; i < n; i++) {
                        if (a.charAt(i) !== b.charAt(i))
                            return i;
                    }
                    return n;
                }

                function isMorphHoldSettleAt(settleAt, now) {
                    return settleAt > now + 86400000;
                }

                function releaseMorphHoldSlots(now) {
                    for (let i = 0; i < charScrambleModel.count; i++) {
                        const slot = charScrambleModel.get(i);
                        if (slot.targetChar === "" || slot.targetChar === " ")
                            continue;
                        if (!isMorphHoldSettleAt(slot.settleAt, now))
                            continue;
                        charScrambleModel.setProperty(i, "settleAt", settleTimeForIndex(i, now));
                    }
                }

                function schedulePrefixSettleAfterRetract(now) {
                    const targetLen = committedScrambleTarget.length;
                    for (let i = 0; i < targetLen && i < charScrambleModel.count; i++) {
                        const slot = charScrambleModel.get(i);
                        if (slot.targetChar === "" || slot.targetChar === " ")
                            continue;
                        if (slot.displayChar === slot.targetChar && !isMorphHoldSettleAt(slot.settleAt, now))
                            continue;
                        charScrambleModel.setProperty(i, "settleAt", now + scrambleDurationForIndex(i));
                    }
                }

                function isRetractingTail() {
                    return hasPendingRetract() || charScrambleModel.count > committedScrambleTarget.length;
                }

                function beginScramble(target) {
                    if (target === committedScrambleTarget) {
                        const now = Date.now();
                        if (!isRetractingTail())
                            releaseMorphHoldSlots(now);
                        if (hasActiveScrambles(now) || hasPendingReveal() || isRetractingTail())
                            scrambleTimer.start();
                        return;
                    }

                    const previousTarget = committedScrambleTarget;
                    committedScrambleTarget = target;
                    pendingRevealIndex = -1;
                    pendingRetractIndex = -1;
                    retractTargetLen = 0;
                    const stablePrefix = sharedPrefixLength(previousTarget, target);
                    const now = Date.now();
                    scrambleClock = now;
                    const targetLen = target.length;
                    const currentLen = charScrambleModel.count;
                    const overlap = Math.min(currentLen, targetLen);
                    const isShrinking = targetLen < currentLen;

                    for (let i = 0; i < overlap; i++) {
                        const ch = target.charAt(i);
                        const slot = charScrambleModel.get(i);
                        const morphDuringRetract = isShrinking && i >= stablePrefix;

                        if (slot.targetChar === ch && slot.settleAt <= now && slot.displayChar === ch && !morphDuringRetract)
                            continue;

                        if (isShrinking) {
                            if (i < stablePrefix && slot.targetChar === ch)
                                continue;
                        } else if (slot.targetChar === ch && slot.settleAt > now && i < stablePrefix) {
                            continue;
                        }

                        charScrambleModel.setProperty(i, "targetChar", ch);
                        if (ch === " ") {
                            charScrambleModel.setProperty(i, "displayChar", " ");
                            charScrambleModel.setProperty(i, "settleAt", morphDuringRetract ? now + 999999999 : 0);
                            continue;
                        }

                        if (morphDuringRetract) {
                            charScrambleModel.setProperty(i, "settleAt", now + 999999999);
                            charScrambleModel.setProperty(i, "displayChar", randomScrambleChar(ch));
                        } else {
                            charScrambleModel.setProperty(i, "settleAt", settleTimeForIndex(i, now));
                            if (slot.displayChar === ch)
                                charScrambleModel.setProperty(i, "displayChar", randomScrambleChar(ch));
                        }
                    }

                    if (targetLen > currentLen) {
                        pendingRevealIndex = currentLen;
                        nextRevealAt = now;
                    } else if (isShrinking) {
                        retractTargetLen = targetLen;
                        pendingRetractIndex = currentLen - 1;
                        nextRetractAt = now + revealStaggerMs;
                    }

                    retractingTail = isShrinking;
                    if (!isShrinking && !hasPendingRetract())
                        schedulePrefixSettleAfterRetract(now);
                    scrambleTimer.start();
                    tryRetractNext(now);
                    tryRevealNext(now);
                }

                function tickScramble() {
                    const now = Date.now();
                    scrambleClock = now;
                    const tailRetracting = isRetractingTail();

                    for (let i = 0; i < charScrambleModel.count; i++) {
                        const slot = charScrambleModel.get(i);

                        if (isMorphHoldSettleAt(slot.settleAt, now) && !tailRetracting && slot.targetChar !== "") {
                            charScrambleModel.setProperty(i, "settleAt", settleTimeForIndex(i, now));
                        }

                        if (slot.settleAt <= now) {
                            if (tailRetracting && slot.targetChar !== "" && slot.displayChar !== slot.targetChar) {
                                charScrambleModel.setProperty(i, "displayChar", randomScrambleChar(slot.targetChar));
                                continue;
                            }

                            if (slot.targetChar !== "" && slot.displayChar !== slot.targetChar)
                                charScrambleModel.setProperty(i, "displayChar", slot.targetChar);
                            continue;
                        }

                        if (slot.targetChar === " ") {
                            charScrambleModel.setProperty(i, "displayChar", " ");
                        } else if (slot.targetChar === "") {
                            continue;
                        } else {
                            charScrambleModel.setProperty(i, "displayChar", randomScrambleChar(slot.targetChar));
                        }
                    }

                    for (let i = charScrambleModel.count - 1; i >= 0; i--) {
                        const slot = charScrambleModel.get(i);
                        if (slot.targetChar === "" && slot.settleAt <= now)
                            charScrambleModel.remove(i);
                    }

                    tryRetractNext(now);

                    const tailStillRetracting = isRetractingTail();
                    if (retractingTail && !tailStillRetracting)
                        schedulePrefixSettleAfterRetract(now);
                    retractingTail = tailStillRetracting;

                    tryRevealNext(now);

                    if (!hasActiveScrambles(now) && !hasPendingReveal() && !isRetractingTail())
                        scrambleTimer.stop();
                }

                Timer {
                    id: scrambleScheduleTimer
                    interval: 10
                    onTriggered: appNameContainer.beginScramble(appNameContainer.pendingScrambleTarget)
                }

                Timer {
                    id: scrambleTimer
                    interval: appNameContainer.scrambleTickMs
                    repeat: true
                    onTriggered: appNameContainer.tickScramble()
                }

                Timer {
                    id: quitScrambleTimer
                    interval: appNameContainer.scrambleTickMs
                    repeat: true
                    onTriggered: appNameContainer.tickQuitScramble()
                }

                NumberAnimation {
                    id: quitProgressAnim
                    target: appNameContainer
                    property: "quitProgress"
                    from: 0
                    to: 1
                    easing.type: Easing.Linear
                    onFinished: appNameContainer.clearScramble()
                }

                Connections {
                    target: centerMenu
                    function onAppNameStrChanged() {
                        appNameContainer.scheduleScramble(centerMenu.appNameStr);
                    }
                }

                Connections {
                    target: root
                    function onLauncherOpenChanged() {
                        if (root.launcherOpen) {
                            appNameContainer.clearScramble();
                            appNameContainer.scheduleScramble(centerMenu.appNameStr);
                        } else if (charScrambleModel.count > 0) {
                            appNameContainer.beginQuitScramble();
                        }
                    }
                }

                Component.onCompleted: scheduleScramble(centerMenu.appNameStr)

                Row {
                    id: waveRow
                    anchors.centerIn: parent
                    spacing: 0

                    Repeater {
                        model: charScrambleModel

                        Item {
                            id: charDelegate
                            required property string displayChar
                            required property string targetChar
                            required property int settleAt
                            required property int index

                            readonly property bool isScrambling: root.scrambleEnabled
                                    && (charDelegate.settleAt > appNameContainer.scrambleClock
                                        || appNameContainer.quitAnimating)

                            readonly property real yOffset: root.waveOffset(
                                charDelegate.index + appNameContainer.transitionWaveIndexOffset
                            )
                            readonly property real centerIdx: (charScrambleModel.count - 1) / 2
                            readonly property real distFromCenter: Math.abs(charDelegate.index - centerIdx)
                            readonly property int quitStaggerMs: (charDelegate.centerIdx - charDelegate.distFromCenter) * appNameContainer.quitStaggerStepMs
                            readonly property real quitLinearProgress: {
                                if (!appNameContainer.quitAnimating)
                                    return 0;
                                const elapsed = appNameContainer.quitProgress * appNameContainer.quitAnimDurationMs;
                                const local = elapsed - charDelegate.quitStaggerMs;
                                if (local <= 0)
                                    return 0;
                                return Math.min(1, local / appNameContainer.quitLetterFadeMs);
                            }
                            readonly property real quitEasedProgress: appNameContainer.quitEase(charDelegate.quitLinearProgress)

                            width: charDelegate.displayChar === " " ? 20 : (charForeground.paintedWidth || 20)
                            height: 64
                            opacity: root.launcherOpen ? 1 : (1 - charDelegate.quitEasedProgress)

                            // 3D Shadow layer (wavy + offset)
                            Text {
                                anchors.centerIn: parent
                                anchors.horizontalCenterOffset: 4
                                anchors.verticalCenterOffset: charDelegate.yOffset + 2
                                text: charDelegate.displayChar
                                opacity: charDelegate.isScrambling ? 0.72 : 1
                                color: Qt.darker(root.accentHex, 3.0)
                                font.family: root.fontFamily
                                font.pixelSize: 44
                                font.bold: true
                            }

                            // Foreground Letter (wavy)
                            Text {
                                id: charForeground
                                anchors.centerIn: parent
                                anchors.verticalCenterOffset: charDelegate.yOffset
                                text: charDelegate.displayChar
                                opacity: charDelegate.isScrambling ? 0.82 : 1
                                color: root.fgHex
                                font.family: root.fontFamily
                                font.pixelSize: 44
                                font.bold: true
                            }
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.launchSelected()
                }
            }

            Item {
                id: optionList
                anchors.centerIn: parent
                width: Math.max(waveRow.width, 220)
                height: parent.height
                readonly property real rowHeight: 28
                opacity: root.launcherOpen && root.showOptionResults ? 1 : 0
                visible: opacity > 0.001 && root.results.length > 1

                Behavior on opacity {
                    NumberAnimation {
                        duration: 140
                        easing.type: Easing.OutCubic
                    }
                }

                Repeater {
                    model: root.optionResults

                    Item {
                        id: optionDelegate
                        required property var modelData
                        required property int index
                        readonly property string optionName: root.entryDisplayName(modelData)
                        readonly property real centeredWaveIndexOffset:
                            (root.displayAppName.length - optionName.length) / 2

                        width: optionList.width
                        height: optionList.rowHeight
                        anchors.horizontalCenter: optionList.horizontalCenter
                        anchors.verticalCenter: optionList.verticalCenter
                        anchors.verticalCenterOffset: root.optionVerticalOffset(index)
                        opacity: root.resultTransitionRunning
                                 && (index === root.resultTransitionSourceRow
                                     || index === (root.resultTransitionDirection > 0 ? 0 : 1))
                                 ? 0 : 0.38

                        Row {
                            anchors.centerIn: parent
                            spacing: 0

                            Repeater {
                                model: optionDelegate.optionName.length

                                Item {
                                    id: optionCharDelegate
                                    required property int index

                                    readonly property string optionChar: optionDelegate.optionName.charAt(index)
                                    readonly property real yOffset: root.waveOffset(
                                        index + optionDelegate.centeredWaveIndexOffset,
                                        root.smallWaveAmplitude
                                    )

                                    width: optionChar === " "
                                           ? 20 * root.smallResultScale
                                           : (optionCharForeground.paintedWidth || 8)
                                    height: optionList.rowHeight

                                    Text {
                                        anchors.centerIn: parent
                                        anchors.horizontalCenterOffset: 4 * root.smallResultScale
                                        anchors.verticalCenterOffset: optionCharDelegate.yOffset
                                            + 2 * root.smallResultScale
                                        text: optionCharDelegate.optionChar
                                        color: Qt.darker(root.accentHex, 3.0)
                                        font.family: root.fontFamily
                                        font.pixelSize: 16
                                        font.bold: true
                                    }

                                    Text {
                                        id: optionCharForeground
                                        anchors.centerIn: parent
                                        anchors.verticalCenterOffset: optionCharDelegate.yOffset
                                        text: optionCharDelegate.optionChar
                                        color: root.fgHex
                                        font.family: root.fontFamily
                                        font.pixelSize: 16
                                        font.bold: true
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Item {
                id: incomingTransitionLabel
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset:
                    root.optionVerticalOffset(root.resultTransitionSourceRow)
                    * (1 - root.resultTransitionProgress)
                width: incomingTransitionRow.width
                height: 64
                z: 20
                visible: root.resultTransitionRunning
                opacity: 0.38 + 0.62 * root.resultTransitionProgress

                readonly property real fontSize: 16 + 28 * root.resultTransitionProgress
                readonly property real waveAmplitude: root.smallWaveAmplitude
                    + (10 - root.smallWaveAmplitude) * root.resultTransitionProgress
                readonly property real centeredWaveIndexOffset:
                    (root.outgoingResultName.length - root.incomingResultName.length)
                    / 2 * (1 - root.resultTransitionProgress)

                Row {
                    id: incomingTransitionRow
                    anchors.centerIn: parent
                    spacing: 0

                    Repeater {
                        model: root.incomingResultName.length

                        Item {
                            id: incomingCharDelegate
                            required property int index

                            readonly property string transitionChar: root.incomingResultName.charAt(index)
                            readonly property real yOffset: root.waveOffset(
                                index + incomingTransitionLabel.centeredWaveIndexOffset,
                                incomingTransitionLabel.waveAmplitude
                            )

                            width: transitionChar === " "
                                   ? 20 * (root.smallResultScale
                                       + (1 - root.smallResultScale) * root.resultTransitionProgress)
                                   : (incomingCharForeground.paintedWidth || 8)
                            height: 64

                            Text {
                                anchors.centerIn: parent
                                anchors.horizontalCenterOffset: 4 * (root.smallResultScale
                                    + (1 - root.smallResultScale) * root.resultTransitionProgress)
                                anchors.verticalCenterOffset: incomingCharDelegate.yOffset
                                    + 2 * (root.smallResultScale
                                        + (1 - root.smallResultScale) * root.resultTransitionProgress)
                                text: incomingCharDelegate.transitionChar
                                color: Qt.darker(root.accentHex, 3.0)
                                font.family: root.fontFamily
                                font.pixelSize: incomingTransitionLabel.fontSize
                                font.bold: true
                            }

                            Text {
                                id: incomingCharForeground
                                anchors.centerIn: parent
                                anchors.verticalCenterOffset: incomingCharDelegate.yOffset
                                text: incomingCharDelegate.transitionChar
                                color: root.fgHex
                                font.family: root.fontFamily
                                font.pixelSize: incomingTransitionLabel.fontSize
                                font.bold: true
                            }
                        }
                    }
                }
            }
        }
    }
}
