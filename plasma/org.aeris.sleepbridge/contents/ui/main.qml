import QtQuick
import QtQuick.Layouts
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.plasma.private.batterymonitor

// Inside plasmashell this shares the tray's InhibitMonitor singleton/cookies.
PlasmoidItem {
    id: root
    visible: false
    implicitWidth: 1
    implicitHeight: 1
    Layout.minimumWidth: 1
    Layout.maximumWidth: 1
    Layout.minimumHeight: 1
    Layout.maximumHeight: 1
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    Plasmoid.status: PlasmaCore.Types.HiddenStatus

    property bool initialized: false
    property string requestSerial: Plasmoid.configuration.requestSerial

    function publishState() {
        Plasmoid.configuration.active = nativeControl.isManuallyInhibited
    }

    InhibitionControl {
        id: nativeControl
        isSilent: true
        onIsManuallyInhibitedChanged: root.publishState()
    }

    onRequestSerialChanged: {
        if (!initialized)
            return
        if (Plasmoid.configuration.requested)
            nativeControl.inhibit("The battery applet has enabled suppressing sleep and screen locking")
        else
            nativeControl.uninhibit()
    }

    Component.onCompleted: {
        initialized = true
        publishState() // Never replay a saved request at login.
    }
}
