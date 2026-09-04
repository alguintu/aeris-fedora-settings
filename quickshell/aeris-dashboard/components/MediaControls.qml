import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts

Item {
    id: root

    readonly property var connectedPlayers: Mpris.players.values
    property string selectedPlayerName: ""
    readonly property var player: root.choosePlayer()
    readonly property bool hasPlayer: root.player !== null
    readonly property var mediaInfoPlayer: root.presentationPlayerFor(root.player)
    readonly property string playerIdentity: root.hasPlayer
            ? ((root.mediaInfoPlayer ? root.mediaInfoPlayer.identity : "")
               || root.player.identity || "MEDIA")
            : "WAITING FOR PLAYER"
    readonly property string title: root.hasPlayer
            ? ((root.mediaInfoPlayer ? root.mediaInfoPlayer.trackTitle : "")
               || root.player.trackTitle || "Unknown title")
            : "Nothing playing"
    readonly property string artist: root.hasPlayer
            ? ((root.mediaInfoPlayer ? root.mediaInfoPlayer.trackArtist : "")
               || root.player.trackArtist || "Unknown artist")
            : "Open Spotify, a browser, VLC, or another media player"
    readonly property string album: root.hasPlayer
            ? ((root.mediaInfoPlayer ? root.mediaInfoPlayer.trackAlbum : "")
               || root.player.trackAlbum || "") : ""
    readonly property string playerIcon: root.hasPlayer
            ? Quickshell.iconPath((root.mediaInfoPlayer
                                   ? root.mediaInfoPlayer.desktopEntry : "")
                                  || root.player.desktopEntry
                                  || root.player.identity.toLowerCase(),
                                  "multimedia-player")
            : ""
    readonly property string directArtUrl: root.hasPlayer
            ? ((root.mediaInfoPlayer ? root.mediaInfoPlayer.trackArtUrl : "")
               || root.player.trackArtUrl || "") : ""
    readonly property bool artFallbackEligible: root.hasPlayer
            && (String(root.player.dbusName || "").indexOf("chromium") !== -1
                || String(root.mediaInfoPlayer ? root.mediaInfoPlayer.dbusName : "")
                   .indexOf("plasma-browser-integration") !== -1)
    readonly property string artLookupKey: root.artFallbackEligible
            && (!root.directArtUrl || root.directArtFailed)
            ? root.artist + "\n" + root.title : ""
    readonly property string requestedArtUrl: root.directArtUrl && !root.directArtFailed
            ? root.directArtUrl : root.fallbackArtUrl
    property string fallbackArtUrl: ""
    property bool directArtFailed: false
    property string artLookupRunningKey: ""
    property string artAUrl: ""
    property string artBUrl: ""
    property int activeArtLayer: -1
    property int pendingArtLayer: -1
    readonly property real progress: root.hasPlayer && root.player.lengthSupported
            && root.player.length > 0
            ? Math.max(0, Math.min(1, root.player.position / root.player.length))
            : 0

    function choosePlayer() {
        const connected = root.connectedPlayers || []
        const players = []
        for (let index = 0; index < connected.length; index++) {
            if (root.playerIsUsable(connected[index], connected))
                players.push(connected[index])
        }
        let selected = null

        for (let index = 0; index < players.length; index++) {
            if (players[index].dbusName === root.selectedPlayerName) {
                selected = players[index]
                break
            }
        }

        // Keep the chosen source through play/pause transitions. Browser media
        // is often exposed twice (native Chromium plus Plasma integration),
        // and those proxies do not update their state in the same DBus frame.
        if (selected && selected.playbackState !== MprisPlaybackState.Stopped)
            return selected

        for (let index = 0; index < players.length; index++) {
            if (players[index].isPlaying) {
                root.rememberPlayer(players[index])
                return players[index]
            }
        }

        if (selected)
            return selected

        for (let index = 0; index < players.length; index++) {
            if (players[index].playbackState === MprisPlaybackState.Paused) {
                root.rememberPlayer(players[index])
                return players[index]
            }
        }

        const fallback = players.length > 0 ? players[0] : null
        root.rememberPlayer(fallback)
        return fallback
    }

    function playerIsUsable(candidate, connected) {
        if (!candidate)
            return false

        const name = String(candidate.dbusName || "")
        if (name.indexOf("plasma-browser-integration") !== -1) {
            const metadata = candidate.metadata || ({})
            const browserPid = metadata["kde:pid"]
            if (browserPid !== undefined && browserPid !== null) {
                const nativeSuffix = "instance" + browserPid
                for (let index = 0; index < connected.length; index++) {
                    const peerName = String(connected[index].dbusName || "")
                    if (connected[index] !== candidate
                            && peerName.indexOf(nativeSuffix) !== -1)
                        return false
                }
            }
        }

        return candidate.playbackState !== MprisPlaybackState.Stopped
                || candidate.canPlay || candidate.canPause
    }

    // Chromium exposes dependable transport controls, while Plasma's matching
    // browser proxy carries the artwork and richer metadata. Keep the proxy out
    // of player selection, but use it as presentation data only while its native
    // controller is still live.
    function presentationPlayerFor(controller) {
        if (!controller)
            return null

        const controllerName = String(controller.dbusName || "")
        const pidMatch = controllerName.match(/instance(\d+)$/)
        if (!pidMatch)
            return controller

        const connected = root.connectedPlayers || []
        for (let index = 0; index < connected.length; index++) {
            const candidate = connected[index]
            const candidateName = String(candidate.dbusName || "")
            if (candidateName.indexOf("plasma-browser-integration") === -1)
                continue

            const metadata = candidate.metadata || ({})
            if (String(metadata["kde:pid"]) === pidMatch[1]
                    && candidate.playbackState !== MprisPlaybackState.Stopped)
                return candidate
        }

        return controller
    }

    function rememberPlayer(candidate) {
        if (!candidate || candidate.dbusName === root.selectedPlayerName)
            return
        const name = candidate.dbusName
        Qt.callLater(function() {
            if (root.selectedPlayerName !== name)
                root.selectedPlayerName = name
        })
    }

    function beginArtLookup() {
        if (!root.artLookupKey)
            return
        if (artLookupProcess.running)
            return

        root.artLookupRunningKey = root.artLookupKey
        artLookupProcess.command = BackendService.command("artwork", [
            "--title", root.title,
            "--artist", root.artist
        ])
        artLookupProcess.running = true
    }

    function coverFailed(layer) {
        const failedUrl = layer === 0 ? root.artAUrl : root.artBUrl
        if (failedUrl && failedUrl === root.directArtUrl)
            root.directArtFailed = true
    }

    function queueCover(url) {
        if (!url) {
            root.pendingArtLayer = -1
            root.activeArtLayer = -1
            root.artAUrl = ""
            root.artBUrl = ""
            return
        }

        if ((root.activeArtLayer === 0 && root.artAUrl === url)
                || (root.activeArtLayer === 1 && root.artBUrl === url)
                || (root.pendingArtLayer === 0 && root.artAUrl === url)
                || (root.pendingArtLayer === 1 && root.artBUrl === url))
            return

        const nextLayer = root.activeArtLayer === 0 ? 1 : 0
        root.pendingArtLayer = nextLayer
        if (nextLayer === 0)
            root.artAUrl = url
        else
            root.artBUrl = url
    }

    function commitCover(layer) {
        const loadedUrl = layer === 0 ? root.artAUrl : root.artBUrl
        if (root.pendingArtLayer !== layer || loadedUrl !== root.requestedArtUrl)
            return
        root.activeArtLayer = layer
        root.pendingArtLayer = -1
    }

    onRequestedArtUrlChanged: root.queueCover(root.requestedArtUrl)
    onDirectArtUrlChanged: root.directArtFailed = false
    onArtLookupKeyChanged: {
        root.fallbackArtUrl = ""
        if (root.artLookupKey)
            artLookupDelay.restart()
    }
    Component.onCompleted: root.queueCover(root.requestedArtUrl)

    Timer {
        id: artLookupDelay
        interval: 350
        onTriggered: root.beginArtLookup()
    }

    Process {
        id: artLookupProcess
        running: false

        stdout: SplitParser {
            onRead: data => {
                try {
                    const result = JSON.parse(data)
                    if (root.artLookupRunningKey === root.artLookupKey
                            && (!root.directArtUrl || root.directArtFailed))
                        root.fallbackArtUrl = result.url || ""
                } catch (error) {
                    console.warn("Aeris media artwork lookup failure:", error)
                }
            }
        }

        onExited: {
            if (root.artLookupKey && root.artLookupRunningKey !== root.artLookupKey)
                artLookupDelay.restart()
        }
    }

    function seekToRatio(ratio) {
        if (!root.hasPlayer || !root.player.canSeek || !root.player.positionSupported
                || !root.player.lengthSupported || root.player.length <= 0)
            return
        root.player.position = Math.max(0, Math.min(1, ratio)) * root.player.length
    }

    function toggleShuffle() {
        if (root.hasPlayer && root.player.canControl && root.player.shuffleSupported)
            root.player.shuffle = !root.player.shuffle
    }

    function toggleLoop() {
        if (!root.hasPlayer || !root.player.canControl || !root.player.loopSupported)
            return
        root.player.loopState = root.player.loopState === MprisLoopState.None
                ? MprisLoopState.Playlist : MprisLoopState.None
    }

    // No scrubber/time readout in this layout: do not poll MPRIS position.
    // Metadata and transport state continue to arrive through MPRIS signals.

    ColumnLayout {
        anchors.fill: parent
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 24

            ClippingRectangle {
                id: artFrame
                readonly property real artSize: root.height
                Layout.minimumWidth: artSize
                Layout.maximumWidth: artSize
                Layout.preferredWidth: artSize
                Layout.preferredHeight: artSize
                Layout.alignment: Qt.AlignTop
                radius: Theme.radius
                color: Theme.inset
                border.width: 1
                border.color: root.hasPlayer ? Theme.inset : Theme.inset
                // Clip both crossfade layers to the same rounded frame.
                // Children already reserve their own one-pixel border inset.
                contentInsideBorder: false

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 1
                    radius: Theme.radius - 1
                    color: Theme.inset
                    ThemeIcon {
                        anchors.centerIn: parent
                        name: "music-note"
                        color: root.hasPlayer ? Theme.mauve : Theme.blue
                        width: 72
                        height: 72
                    }
                }

                Image {
                    id: coverArtA
                    anchors.fill: parent
                    anchors.margins: 1
                    z: root.activeArtLayer === 0 ? 1 : 0
                    opacity: root.activeArtLayer === 0 && status === Image.Ready ? 1 : 0
                    source: root.artAUrl
                    sourceSize.width: 384
                    sourceSize.height: 384
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true

                    onStatusChanged: {
                        if (status === Image.Ready)
                            root.commitCover(0)
                        else if (status === Image.Error)
                            root.coverFailed(0)
                    }

                    Behavior on opacity {
                        NumberAnimation { duration: 280; easing.type: Easing.InOutCubic }
                    }
                }

                Image {
                    id: coverArtB
                    anchors.fill: parent
                    anchors.margins: 1
                    z: root.activeArtLayer === 1 ? 1 : 0
                    opacity: root.activeArtLayer === 1 && status === Image.Ready ? 1 : 0
                    source: root.artBUrl
                    sourceSize.width: 384
                    sourceSize.height: 384
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true

                    onStatusChanged: {
                        if (status === Image.Ready)
                            root.commitCover(1)
                        else if (status === Image.Error)
                            root.coverFailed(1)
                    }

                    Behavior on opacity {
                        NumberAnimation { duration: 280; easing.type: Easing.InOutCubic }
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: artFrame.artSize
                Layout.alignment: Qt.AlignTop

                Text {
                    id: trackTitle
                    anchors.top: parent.top
                    anchors.topMargin: parent.height / 3 - (height + 12 + trackArtist.height) / 2
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 34
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: root.title
                    color: root.hasPlayer ? Theme.teal : Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: 24
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }

                Text {
                    id: trackArtist
                    anchors.top: trackTitle.bottom
                    anchors.topMargin: 12
                    anchors.left: parent.left
                    anchors.right: parent.right
                    horizontalAlignment: Text.AlignHCenter
                    text: root.artist
                    color: root.hasPlayer ? Theme.yellow : Theme.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: 20
                    font.weight: Font.Normal
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }

                Row {
                    id: transport
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 24
                    spacing: 6

                    MediaTransportButton {
                        symbol: "⏮"
                        available: root.hasPlayer && root.player.canGoPrevious
                        onClicked: root.player.previous()
                    }

                    MediaTransportButton {
                        symbol: root.hasPlayer && root.player.isPlaying ? "⏸" : "▶"
                        primary: true
                        accent: Theme.mauve
                        available: root.hasPlayer && root.player.canTogglePlaying
                        onClicked: root.player.togglePlaying()
                    }

                    MediaTransportButton {
                        symbol: "⏭"
                        available: root.hasPlayer && root.player.canGoNext
                        onClicked: root.player.next()
                    }

                }
            }
        }

    }

    Image {
        id: playerMark
        anchors.top: parent.top
        anchors.right: parent.right
        width: 24
        height: 24
        z: 10
        visible: root.hasPlayer
        source: root.playerIcon
        sourceSize.width: 48
        sourceSize.height: 48
        fillMode: Image.PreserveAspectFit
    }
}
