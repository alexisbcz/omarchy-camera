import QtQuick
import QtQuick.Effects
import QtMultimedia
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

// Iris for Omarchy: a floating, always-on-top circular webcam mirror.
//
// The window is a full-screen, click-through layer surface whose input region
// is only the circle, so moving and resizing are plain item geometry changes
// instead of compositor window moves. keepLoaded lets the plugin restore the
// bubble at login; the camera itself only runs while the bubble is shown.
//
// Interaction:
//   drag inside                   move
//   drag the rim / wheel          resize
//   hover button at the bottom    framing mode: drag moves the image, wheel
//                                 zooms it (at the pointer); ✓ or right click exits
//   right-drag (or middle-drag)   move the image without entering framing mode
//   hold right button + wheel     zoom the image without entering framing mode
//   right click                   menu (camera, mirror, framing, show at login, hide)
//   double click                  toggle mirror
//
// IPC (omarchy-shell shell call alex.iris <method> ""):
//   toggleMirror, nextCamera, toggleMenu, toggleFraming, resetFraming
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  readonly property string pluginId: (manifest && manifest.id) || "alex.iris"

  property bool opened: false
  property bool menuOpen: false

  // Persisted state.
  property bool mirrored: true
  property bool showAtLogin: false
  property string cameraName: ""
  property string screenName: ""
  property real size: 240
  property real centerX: -1
  property real centerY: -1
  // Framing: which part of the camera image fills the circle. offsetX/Y move
  // the image center away from the circle center, in circle diameters, so
  // they survive bubble resizes. zoom is the user's zoom; the rendered scale
  // grows past it when an offset would otherwise uncover the circle's edge.
  property real zoom: 1
  property real offsetX: 0
  property real offsetY: 0

  property bool stateLoaded: false
  readonly property real maxZoom: 4
  readonly property real minSize: 120
  readonly property real maxSize: 900
  readonly property real rimWidth: 18

  readonly property string statePath:
    (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy/iris.json"

  readonly property var targetScreen: {
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++)
      if (screens[i].name === screenName) return screens[i]
    return screens.length > 0 ? screens[0] : null
  }

  readonly property var selectedDevice: {
    var inputs = mediaDevices.videoInputs
    for (var i = 0; i < inputs.length; i++)
      if (inputs[i].description === cameraName) return inputs[i]
    return mediaDevices.defaultVideoInput
  }

  // ------------------------------------------------------------ host contract

  function open(payloadJson) {
    var payload = {}
    try { payload = JSON.parse(payloadJson || "{}") || {} } catch (e) {}
    if (payload.mirror !== undefined) mirrored = payload.mirror === true
    if (payload.camera !== undefined) cameraName = String(payload.camera)
    opened = true
    menuOpen = payload.menu === true
    save()
  }

  function close() {
    opened = false
    menuOpen = false
    framingMode = false
    save()
  }

  // Close through the host so its open-state bookkeeping stays in sync.
  function dismiss() {
    if (shell && typeof shell.hide === "function") shell.hide(pluginId)
    else close()
  }

  // ------------------------------------------------------------ IPC methods

  function toggleMirror() {
    mirrored = !mirrored
    save()
  }

  function nextCamera() {
    var inputs = mediaDevices.videoInputs
    if (inputs.length === 0) return ""
    var index = 0
    for (var i = 0; i < inputs.length; i++)
      if (inputs[i].description === selectedDevice.description) index = (i + 1) % inputs.length
    cameraName = inputs[index].description
    save()
    return cameraName
  }

  function toggleMenu() {
    menuOpen = !menuOpen
  }

  function resetFraming() {
    menuOpen = false
    animateFraming = true
    zoom = 1
    offsetX = 0
    offsetY = 0
    animateTimer.restart()
  }

  // ------------------------------------------------------------ framing

  // Free framing: zoom and offset are applied as-is, so zooming out or
  // pushing the image aside shows the background around it. Bounds only keep
  // the image from being lost: zoom from "whole frame fits" (1 / long side)
  // up to maxZoom, and the image center may travel to its own edge.
  property bool framingMode: false
  property bool animateFraming: false

  function minZoom() {
    return 1 / Math.max(video.baseWr, video.baseHr)
  }

  function clampOffset(value, baseRel) {
    var limit = Math.max(0.5, baseRel * zoom / 2)
    return Math.max(-limit, Math.min(limit, value))
  }

  // Zoom by factor, keeping the image point under (px, py) fixed; px/py are
  // relative to the circle center, in circle diameters.
  function zoomAt(factor, px, py) {
    var next = Math.max(minZoom(), Math.min(maxZoom, zoom * factor))
    var k = next / zoom
    zoom = next
    offsetX = clampOffset(px - (px - offsetX) * k, video.baseWr)
    offsetY = clampOffset(py - (py - offsetY) * k, video.baseHr)
    save()
  }

  function toggleFraming() {
    menuOpen = false
    framingMode = !framingMode
    if (!framingMode) save()
  }

  Timer {
    id: animateTimer
    interval: 450
    onTriggered: {
      root.animateFraming = false
      root.save()
    }
  }

  Behavior on zoom { enabled: root.animateFraming; NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
  Behavior on offsetX { enabled: root.animateFraming; NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
  Behavior on offsetY { enabled: root.animateFraming; NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }

  // ------------------------------------------------------------ persistence

  function applyState(raw) {
    var s = {}
    try { s = JSON.parse(raw || "{}") || {} } catch (e) {}
    if (typeof s.mirrored === "boolean") mirrored = s.mirrored
    if (typeof s.showAtLogin === "boolean") showAtLogin = s.showAtLogin
    if (typeof s.cameraName === "string") cameraName = s.cameraName
    if (typeof s.screenName === "string") screenName = s.screenName
    if (typeof s.size === "number") size = clampSize(s.size)
    if (typeof s.centerX === "number") centerX = s.centerX
    if (typeof s.centerY === "number") centerY = s.centerY
    if (typeof s.zoom === "number") zoom = Math.max(1, Math.min(maxZoom, s.zoom))
    if (typeof s.offsetX === "number") offsetX = s.offsetX
    if (typeof s.offsetY === "number") offsetY = s.offsetY
    stateLoaded = true
    if (showAtLogin && s.open === true && !opened) opened = true
  }

  function save() {
    if (stateLoaded) saveTimer.restart()
  }

  Timer {
    id: saveTimer
    interval: 400
    onTriggered: stateFile.setText(JSON.stringify({
      open: root.opened,
      mirrored: root.mirrored,
      showAtLogin: root.showAtLogin,
      cameraName: root.cameraName,
      screenName: root.screenName,
      size: root.size,
      centerX: root.centerX,
      centerY: root.centerY,
      zoom: root.zoom,
      offsetX: root.offsetX,
      offsetY: root.offsetY
    }, null, 2) + "\n")
  }

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: false
    printErrors: false
    onLoaded: root.applyState(text())
    onLoadFailed: root.applyState("")
  }

  function clampSize(value) {
    return Math.max(minSize, Math.min(maxSize, value))
  }

  // ------------------------------------------------------------ camera

  MediaDevices { id: mediaDevices }

  CaptureSession {
    camera: Camera {
      id: camera
      active: root.opened
      cameraDevice: root.selectedDevice
    }
    videoOutput: video
  }

  // ------------------------------------------------------------ window

  PanelWindow {
    id: win
    visible: root.opened
    screen: root.targetScreen
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-iris"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.menuOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    // Only the circle takes input; the rest of the screen stays clickable.
    mask: Region { item: bubble; shape: RegionShape.Ellipse }

    // Default placement: bottom-right corner, clear of the edges.
    readonly property real defaultCenterX: width - root.size / 2 - 48
    readonly property real defaultCenterY: height - root.size / 2 - 48

    Item {
      id: bubble
      width: root.size
      height: root.size
      x: Math.max(0, Math.min(win.width - width, (root.centerX < 0 ? win.defaultCenterX : root.centerX) - width / 2))
      y: Math.max(0, Math.min(win.height - height, (root.centerY < 0 ? win.defaultCenterY : root.centerY) - height / 2))

      Item {
        id: feed
        anchors.fill: parent
        layer.enabled: true
        layer.smooth: true
        layer.effect: MultiEffect {
          maskEnabled: true
          maskSource: circleMask
          maskThresholdMin: 0.5
          maskSpreadAtMin: 1.0
        }

        Rectangle {
          anchors.fill: parent
          color: Color.background
        }

        // The video item is sized so that at zoom 1 its short side matches the
        // circle (the whole circle is covered); zoom scales it from there.
        VideoOutput {
          id: video

          readonly property real aspect: sourceRect.width > 0 && sourceRect.height > 0
            ? sourceRect.width / sourceRect.height : 16 / 9
          // Base size in circle diameters at scale 1 (the short side is 1).
          readonly property real baseWr: Math.max(aspect, 1)
          readonly property real baseHr: Math.max(1 / aspect, 1)
          width: bubble.width * baseWr * root.zoom
          height: bubble.height * baseHr * root.zoom
          x: (bubble.width - width) / 2 + root.offsetX * bubble.width
          y: (bubble.height - height) / 2 + root.offsetY * bubble.height
          fillMode: VideoOutput.Stretch
          transform: Scale {
            origin.x: video.width / 2
            xScale: root.mirrored ? -1 : 1
          }
        }
      }

      Item {
        id: circleMask
        anchors.fill: parent
        layer.enabled: true
        visible: false

        Rectangle {
          anchors.fill: parent
          radius: width / 2
          color: "black"
          antialiasing: true
        }
      }

      Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: "transparent"
        antialiasing: true
        // A thick accent rim marks framing mode.
        border.width: root.framingMode ? 3 : (dragArea.containsMouse ? 2 : 1)
        border.color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b,
          root.framingMode || dragArea.containsMouse ? 0.9 : 0.4)
      }

      Text {
        anchors.centerIn: parent
        width: parent.width * 0.7
        visible: root.opened && (camera.error !== Camera.NoError || mediaDevices.videoInputs.length === 0)
        text: mediaDevices.videoInputs.length === 0 ? "No camera found" : camera.errorString
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: 13
        wrapMode: Text.Wrap
        horizontalAlignment: Text.AlignHCenter
      }

      MouseArea {
        id: dragArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

        // Modifier keys never reach this surface (it takes no keyboard focus,
        // so Wayland sends it no modifier state); every gesture is mouse-only.
        property string mode: ""
        property bool rightDragged: false
        property bool rightZoomed: false
        property point pressPoint
        property real pressCenterX
        property real pressCenterY
        property real pressOffsetX
        property real pressOffsetY

        function distanceFromCenter(mx, my) {
          return Math.hypot(mx - width / 2, my - height / 2)
        }

        function onRim(mx, my) {
          return distanceFromCenter(mx, my) > width / 2 - root.rimWidth
        }

        cursorShape: mode === "pan" || root.framingMode ? Qt.SizeAllCursor
          : mode === "resize" || (mode === "" && containsMouse && onRim(mouseX, mouseY))
          ? Qt.SizeFDiagCursor
          : (mode === "move" ? Qt.ClosedHandCursor : Qt.OpenHandCursor)

        onPressed: function(mouse) {
          pressPoint = mapToItem(win.contentItem, mouse.x, mouse.y)
          pressCenterX = bubble.x + bubble.width / 2
          pressCenterY = bubble.y + bubble.height / 2
          pressOffsetX = root.offsetX
          pressOffsetY = root.offsetY
          rightDragged = false
          rightZoomed = false
          if (mouse.button === Qt.RightButton || mouse.button === Qt.MiddleButton) {
            // Right press arms a pan; a release without movement opens the menu.
            mode = "pan"
            return
          }
          if (root.menuOpen) return
          if (root.framingMode) mode = "pan"
          else mode = onRim(mouse.x, mouse.y) ? "resize" : "move"
        }

        onPositionChanged: function(mouse) {
          if (mode === "") return
          var p = mapToItem(win.contentItem, mouse.x, mouse.y)
          if (mode === "pan") {
            if (Math.hypot(p.x - pressPoint.x, p.y - pressPoint.y) < 4 && !rightDragged) return
            rightDragged = true
            root.menuOpen = false
            // The image follows the pointer.
            root.offsetX = root.clampOffset(pressOffsetX + (p.x - pressPoint.x) / bubble.width, video.baseWr)
            root.offsetY = root.clampOffset(pressOffsetY + (p.y - pressPoint.y) / bubble.height, video.baseHr)
          } else if (mode === "move") {
            root.centerX = pressCenterX + p.x - pressPoint.x
            root.centerY = pressCenterY + p.y - pressPoint.y
          } else {
            // Resize around the fixed center.
            root.centerX = pressCenterX
            root.centerY = pressCenterY
            root.size = root.clampSize(2 * Math.hypot(p.x - pressCenterX, p.y - pressCenterY))
          }
        }

        onReleased: function(mouse) {
          if (mode === "") return
          var wasPan = mode === "pan"
          mode = ""
          if (wasPan) {
            if (rightDragged || rightZoomed || mouse.button !== Qt.RightButton) root.save()
            else if (root.framingMode) root.toggleFraming()
            else root.toggleMenu()
            return
          }
          root.centerX = bubble.x + bubble.width / 2
          root.centerY = bubble.y + bubble.height / 2
          if (win.screen) root.screenName = win.screen.name
          root.save()
        }

        onDoubleClicked: function(mouse) {
          if (mouse.button === Qt.LeftButton && !root.menuOpen && !root.framingMode) root.toggleMirror()
        }

        onWheel: function(wheel) {
          if (root.framingMode || (pressedButtons & Qt.RightButton)) {
            // Framing mode, or right button held: the wheel zooms the image
            // toward the pointer.
            rightZoomed = true
            root.menuOpen = false
            root.zoomAt(wheel.angleDelta.y > 0 ? 1.1 : 1 / 1.1,
              (wheel.x - width / 2) / width, (wheel.y - height / 2) / height)
            return
          }
          var cx = bubble.x + bubble.width / 2
          var cy = bubble.y + bubble.height / 2
          root.size = root.clampSize(root.size + (wheel.angleDelta.y > 0 ? 20 : -20))
          root.centerX = cx
          root.centerY = cy
          root.save()
        }
      }

      // Zoom readout while framing.
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: framingButton.top
        anchors.bottomMargin: 6
        visible: root.framingMode
        text: root.zoom.toFixed(1) + "×"
        color: "white"
        style: Text.Outline
        styleColor: Qt.rgba(0, 0, 0, 0.6)
        font.family: Style.font.family
        font.pixelSize: 12
      }

      // Framing toggle: shown while hovering the bubble, and always while
      // framing so there is a visible way out.
      Rectangle {
        id: framingButton
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Math.max(10, parent.height * 0.06)
        width: 30
        height: 30
        radius: 15
        visible: !root.menuOpen && (root.framingMode || dragArea.containsMouse || framingMouse.containsMouse)
        color: root.framingMode
          ? Color.accent
          : Qt.rgba(Color.popups.background.r, Color.popups.background.g, Color.popups.background.b,
              framingMouse.containsMouse ? 0.95 : 0.75)
        border.width: 1
        border.color: Color.popups.border

        Text {
          anchors.centerIn: parent
          text: root.framingMode ? "✓" : "\uDB80\uDC41" // nf-md-arrow_all
          color: root.framingMode ? Color.background : Color.popups.text
          font.family: Style.font.family
          font.pixelSize: 16
        }

        MouseArea {
          id: framingMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.toggleFraming()
        }
      }

      // ---------------------------------------------------------- menu

      Rectangle {
        id: menu
        visible: root.menuOpen
        anchors.centerIn: parent
        width: Math.min(parent.width * 0.78, menuColumn.implicitWidth + 24)
        height: menuColumn.implicitHeight + 16
        radius: 8
        color: Qt.rgba(Color.popups.background.r, Color.popups.background.g, Color.popups.background.b, 0.92)
        border.width: 1
        border.color: Color.popups.border

        Keys.onEscapePressed: root.menuOpen = false
        focus: root.menuOpen

        Column {
          id: menuColumn
          anchors.centerIn: parent
          width: parent.width - 16
          spacing: 2

          Repeater {
            model: mediaDevices.videoInputs

            MenuRow {
              required property var modelData
              label: modelData.description
              checked: root.selectedDevice && modelData.description === root.selectedDevice.description
              onActivated: {
                root.cameraName = modelData.description
                root.save()
              }
            }
          }

          Rectangle { width: parent.width; height: 1; color: Color.muted; opacity: 0.5 }

          MenuRow {
            label: "Mirror view"
            checked: root.mirrored
            onActivated: root.toggleMirror()
          }

          MenuRow {
            label: "Adjust framing"
            checked: root.framingMode
            onActivated: root.toggleFraming()
          }

          MenuRow {
            label: "Reset framing"
            onActivated: root.resetFraming()
          }

          MenuRow {
            label: "Show at login"
            checked: root.showAtLogin
            onActivated: {
              root.showAtLogin = !root.showAtLogin
              root.save()
            }
          }

          Rectangle { width: parent.width; height: 1; color: Color.muted; opacity: 0.5 }

          MenuRow {
            label: "Hide"
            onActivated: root.dismiss()
          }
        }
      }
    }
  }

  component MenuRow: Rectangle {
    id: row

    property string label: ""
    property bool checked: false
    signal activated()

    width: parent ? parent.width : implicitWidth
    implicitWidth: rowText.implicitWidth + 36
    height: 24
    radius: 4
    color: rowMouse.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.12) : "transparent"

    Text {
      anchors.left: parent.left
      anchors.leftMargin: 6
      anchors.verticalCenter: parent.verticalCenter
      width: 14
      text: row.checked ? "✓" : ""
      color: Color.accent
      font.family: Style.font.family
      font.pixelSize: 12
    }

    Text {
      id: rowText
      anchors.left: parent.left
      anchors.leftMargin: 24
      anchors.right: parent.right
      anchors.rightMargin: 6
      anchors.verticalCenter: parent.verticalCenter
      text: row.label
      elide: Text.ElideRight
      color: Color.popups.text
      font.family: Style.font.family
      font.pixelSize: 12
    }

    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      onClicked: row.activated()
    }
  }
}
