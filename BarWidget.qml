import QtQuick
import qs.Commons
import qs.Ui

// Bar icon for Iris. Left click toggles the camera bubble, right click opens
// the bubble with its menu showing (camera picker, mirror, show at login).
BarWidget {
  id: root

  readonly property string pluginId: moduleName || "alex.iris"
  readonly property var pluginShell: bar ? bar.shell : null
  property bool cameraOpen: false

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function syncOpen() {
    cameraOpen = !!(pluginShell && pluginShell.isPluginOpen(pluginId))
  }

  // isPluginOpen is a plain call, not a bindable property, so poll it.
  Timer {
    interval: 1000
    running: root.visible
    repeat: true
    triggeredOnStart: true
    onTriggered: root.syncOpen()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰄀" // nf-md-camera
    active: root.cameraOpen
    slotSize: Style.bar.statusSlot
    tooltipText: root.cameraOpen ? "Hide camera" : "Show camera"

    onPressed: function(b) {
      if (!root.pluginShell) return
      if (b === Qt.RightButton) root.pluginShell.summon(root.pluginId, JSON.stringify({ menu: true }))
      else root.pluginShell.toggle(root.pluginId, "{}")
      Qt.callLater(root.syncOpen)
    }
  }
}
