import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Wayland
import "rofi-search.js" as RofiSearch

ShellRoot {
    id: root

    readonly property string bgHex: Quickshell.env("HAZE_LAUNCHER_BG") || "#100e1c"
    readonly property string fgHex: Quickshell.env("HAZE_LAUNCHER_FG") || "#f4ebfc"
    readonly property string accentHex: Quickshell.env("HAZE_LAUNCHER_ACCENT") || "#c084fc"
    readonly property string customNamespace: Quickshell.env("WAVE_LAUNCHER_NAMESPACE")
                                           || Quickshell.env("HAZE_LAUNCHER_NAMESPACE")
                                           || "wave-launcher"
    readonly property string fontFamily: Quickshell.env("WAVE_LAUNCHER_FONT")
                                        || "BigBlueTermPlus Nerd Font"

    function colorWithAlpha(hex, alpha) {
        let value = hex.startsWith("#") ? hex.slice(1) : hex;
        const r = parseInt(value.slice(0, 2), 16);
        const g = parseInt(value.slice(2, 4), 16);
        const b = parseInt(value.slice(4, 6), 16);
        return Qt.rgba(r / 255, g / 255, b / 255, alpha);
    }

    readonly property bool fallLettersEnabled: Quickshell.env("WAVE_LAUNCHER_FALL") === "1"

    property bool launcherOpen: false
    property bool windowShown: false
    property bool centerQuitAnimating: false
    property bool vignetteOpen: false
    property string query: ""
    property string displayAppName: ""
    property bool showResults: false
    property int selectedIndex: 0
    property int appReloadCounter: 0
    property int drunHistoryReloadCounter: 0
    property real wavePhase: 0

    readonly property string drunCachePath: {
        const custom = Quickshell.env("WAVE_LAUNCHER_DRUN_CACHE");
        const home = Quickshell.env("HOME") || "";
        const cacheDir = Quickshell.env("XDG_CACHE_HOME") || (home ? home + "/.cache" : "");
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
        running: root.windowShown
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

    readonly property var results: searchApplications(query)
    readonly property var topResult: results.length > 0
        ? (results[Math.min(selectedIndex, results.length - 1)] || results[0])
        : null

    function updateDisplayAppName() {
        if (query.trim().length === 0) {
            displayAppName = "";
            return;
        }
        if (!showResults) {
            displayAppName = query.trim();
            return;
        }
        if (topResult)
            displayAppName = topResult.name;
        else
            displayAppName = query.trim();
    }

    Timer {
        id: resultsShowDelay
        interval: Math.max(0, parseInt(Quickshell.env("WAVE_LAUNCHER_DISPLAY_DEBOUNCE_MS") || "150", 10))
        onTriggered: {
            root.showResults = true;
            updateDisplayAppName();
        }
    }

    onQueryChanged: {
        if (query.trim().length === 0) {
            resultsShowDelay.stop();
            showResults = false;
            displayAppName = "";
            selectedIndex = 0;
            return;
        }

        showResults = false;
        displayAppName = query.trim();
        resultsShowDelay.restart();
        selectedIndex = 0;
    }

    onSelectedIndexChanged: {
        if (selectedIndex === 0)
            return;
        showResults = true;
        resultsShowDelay.stop();
        updateDisplayAppName();
    }

    function searchApplications(text) {
        if (text.trim().length === 0)
            return [];

        return RofiSearch.search(text, preparedApplications, {
            matchingMethod: Quickshell.env("WAVE_LAUNCHER_MATCHING") || "normal",
            normalizeMatch: Quickshell.env("WAVE_LAUNCHER_NORMALIZE") === "true",
            sort: Quickshell.env("WAVE_LAUNCHER_SORT") === "true",
            sortingMethod: Quickshell.env("WAVE_LAUNCHER_SORTING") || "normal",
            matchFieldsSpec: Quickshell.env("WAVE_LAUNCHER_MATCH_FIELDS") || undefined,
            drunHistory: root.drunHistory,
            useDrunHistory: Quickshell.env("WAVE_LAUNCHER_DRUN_HISTORY") !== "false",
            preferNameMatch: Quickshell.env("WAVE_LAUNCHER_PREFER_NAME_MATCH") !== "false"
        });
    }

    function open() {
        hideDelay.stop();
        physicsLayer.fallingOffScreen = false;
        physicsLayer.resetAllLetters();
        query = "";
        displayAppName = "";
        showResults = false;
        resultsShowDelay.stop();
        selectedIndex = 0;
        windowShown = true;
        launcherOpen = true;
        vignetteOpen = false;
        vignetteFadeInDelay.restart();
        focusDelay.restart();
    }

    function close() {
        vignetteFadeInDelay.stop();
        vignetteOpen = false;
        launcherOpen = false;
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
        const entry = topResult;
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

        function toggle(): void { root.toggle(); }
        function open(): void { root.open(); }
        function close(): void { root.close(); }
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
                resultsShowDelay.stop();
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
        anchors {
            top: true
            bottom: true
            left: true
            right: true
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
            readonly property real targetWidth: Math.max(blobBaseWidth, centerMenu.width + blobPadding)

            Behavior on opacity {
                NumberAnimation {
                    duration: root.vignetteOpen ? 320 : 340
                    easing.type: root.vignetteOpen ? Easing.OutCubic : Easing.InCubic
                }
            }

            RectangularShadow {
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
                    if (root.fallLettersEnabled && hiddenInput.text.length === 0) {
                        physicsLayer.dropLastLetter();
                    }
                } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) {
                    if (root.results.length > 0) {
                        root.selectedIndex = (root.selectedIndex + 1) % root.results.length;
                    }
                    event.accepted = true;
                } else if (event.key === Qt.Key_Up) {
                    if (root.results.length > 0) {
                        root.selectedIndex = (root.selectedIndex - 1 + root.results.length) % root.results.length;
                    }
                    event.accepted = true;
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    root.launchSelected();
                    event.accepted = true;
                }
            }
        }

        // Click transparent area to close
        MouseArea {
            anchors.fill: parent
            z: 1
            onClicked: root.close()
        }

        // Optional physics layer (enable with WAVE_LAUNCHER_FALL=1)
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
                width: waveRow.width
                height: 64

                readonly property string scrambleCharset: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
                readonly property int scrambleTickMs: 20
                readonly property int revealStaggerMs: 24

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
                        if (slot.targetChar !== " ")
                            charScrambleModel.setProperty(i, "displayChar", randomScrambleChar(slot.targetChar));
                    }

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
                            quitProgressAnim.stop();
                            quitScrambleTimer.stop();
                            appNameContainer.quitAnimating = false;
                            root.centerQuitAnimating = false;
                            appNameContainer.quitProgress = 0;
                            appNameContainer.committedScrambleTarget = "";
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

                            readonly property bool isScrambling: charDelegate.settleAt > appNameContainer.scrambleClock
                                    || appNameContainer.quitAnimating

                            readonly property real yOffset: Math.sin(root.wavePhase + charDelegate.index * 0.45) * 10
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
        }
    }
}
