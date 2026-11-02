import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "cinco.batteries"
  ipcTarget: "cinco.batteries"
  // manageIpc: false so this panel owns its handlers outright — the base one
  // has no togglePercentage, and a target permits only a single handler.
  manageIpc: false
  property var batteryInfo: ({})
  // Per-pack sysfs metadata keyed by battery name, from the bundled
  // battery-packs helper. UPower covers the live values; this covers what its
  // QML API leaves out (cycle count, design capacity, charge thresholds).
  property var packMeta: ({})
  property var systemInfo: ({})
  property var profiles: []
  property string activeProfile: ""
  property int profileIndex: 0
  property bool cursorActive: false
  readonly property bool showPercentage: setting("showPercentage", false) === true
  // Several packs on a horizontal bar get one BarIconButton each (packRow);
  // a single pack or a vertical bar keeps the one aggregate button.
  readonly property bool perPack: multiBattery && !button.vertical
  // The open-panel mark, instead of the icon-sized fraction of the slot the
  // bar falls back to: a single pack with the percentage takes the glyph
  // width, as omarchy.power does; several packs take packRow's painted extent,
  // labels included.
  readonly property real openPanelIndicatorWidth: button.vertical ? 0
    : (perPack ? packRow.paintedExtent : (showPercentage ? button.glyphPaintedWidth : 0))
  readonly property bool batteryPresent: {
    var device = UPower.displayDevice
    return !!(device && device.isPresent)
  }

  // The physical packs, sorted by sysfs name (BAT0 internal, BAT1 bay on a
  // ThinkPad Power Bridge). UPower.displayDevice is the composite and is
  // excluded so it cannot show up twice.
  readonly property var batteries: {
    var model = UPower.devices
    var all = model && model.values ? model.values : []
    var out = []
    for (var i = 0; i < all.length; i++) {
      var d = all[i]
      if (!d || d === UPower.displayDevice) continue
      if (!d.isPresent || !d.isLaptopBattery) continue
      out.push(d)
    }
    out.sort(function(a, b) { return String(a.nativePath).localeCompare(String(b.nativePath)) })
    return out
  }
  readonly property bool multiBattery: batteries.length > 1

  function handlePress(b) {
    if (!batteryPresent) return
    if (b === Qt.RightButton) togglePercentage()
    else toggle()
  }

  function deviceIcon(device) {
    return Model.deviceIcon(device, upowerStates())
  }

  function devicePercentage(device) {
    return Model.devicePercentage(device)
  }

  function packInfo(device) {
    return packMeta[Model.batteryLabel(device)] || {}
  }

  function packSize(device) {
    var wh = Number((device && device.energyCapacity) || 0)
    if (wh <= 0) wh = Number(packInfo(device).full || 0)
    return wh > 0 ? Math.round(wh) + "Wh" : "—"
  }

  function packCycles(device) {
    var cycles = packInfo(device).cycles
    return cycles ? String(cycles) : "—"
  }

  function packHealth(device) {
    var info = packInfo(device)
    var full = Number(info.full || (device && device.energyCapacity) || 0)
    var design = Number(info.design || 0)
    if (full <= 0 || design <= 0) return "—"
    return Math.round((full / design) * 100) + "%"
  }

  function packThreshold(device) {
    var info = packInfo(device)
    var stop = info.stop
    if (!stop) return "—"
    var start = info.start
    return start && start !== stop ? start + "-" + stop + "%" : stop + "%"
  }

  // A pack moving no current is idle regardless of what state it advertises —
  // on a Power Bridge machine only one pack charges or drains at a time.
  function packIdle(device) {
    var d = device || {}
    return Math.abs(Number(d.changeRate || 0)) <= 0.05
  }

  function packFlowLabel(device) {
    var d = device || {}
    var states = upowerStates()
    if (packIdle(d)) return "State"
    if (d.state === states.Discharging) return "Time left"
    if (d.state === states.Charging) return "Time to full"
    return "Draw"
  }

  function packFlowValue(device) {
    var d = device || {}
    var states = upowerStates()

    if (packIdle(d)) {
      if (d.state === states.FullyCharged) return "Full"
      if (d.state === states.PendingCharge) return "Holding"
      return "Idle"
    }

    var time = ""
    if (d.state === states.Discharging) time = formatDuration(d.timeToEmpty)
    else if (d.state === states.Charging) time = formatDuration(d.timeToFull)
    return time || packRate(d)
  }

  function packRate(device) {
    var d = device || {}
    var rate = Math.abs(Number(d.changeRate || 0))
    return (Math.round(rate * 10) / 10) + "W"
  }

  function packFlowRateLabel(device) {
    var d = device || {}
    var states = upowerStates()
    if (packIdle(d)) return "Draw"
    return d.state === states.Charging ? "Charging" : "Discharging"
  }

  // Health across every pack, weighted by design capacity rather than averaged.
  readonly property string aggregateHealth: {
    var full = 0
    var design = 0
    var packs = batteries
    for (var i = 0; i < packs.length; i++) {
      var info = packInfo(packs[i])
      full += Number(info.full || packs[i].energyCapacity || 0)
      design += Number(info.design || 0)
    }
    return design > 0 && full > 0 ? Math.round((full / design) * 100) + "%" : "—"
  }

  function deviceLabel(device) {
    return Model.batteryLabel(device)
  }

  // omarchy-battery-status reads `upower -e | grep BAT | head -n 1`, so on a
  // dual-battery machine every number it returns describes BAT0 alone while the
  // icon and progress bar come from the UPower aggregate — the panel ends up
  // reporting 5% next to a half-full bar. Read the aggregate device directly for
  // the hero row instead, and keep the script's values for single-pack laptops.
  function formatDuration(seconds) {
    var total = Math.max(0, Math.round(Number(seconds) || 0))
    if (total <= 0) return ""
    var hours = Math.floor(total / 3600)
    var minutes = Math.round((total % 3600) / 60)
    if (minutes === 60) { hours += 1; minutes = 0 }
    if (hours <= 0) return minutes + "m"
    return minutes > 0 ? hours + "h " + minutes + "m" : hours + "h"
  }

  readonly property string aggregatePercentage: Math.round(batteryFraction * 100) + "%"

  readonly property string aggregateSize: {
    var d = UPower.displayDevice
    var wh = d && d.isPresent ? Number(d.energyCapacity || 0) : 0
    return wh > 0 ? Math.round(wh) + "Wh" : ""
  }

  readonly property string aggregateRate: {
    var d = UPower.displayDevice
    if (!d || !d.isPresent) return ""
    return (Math.round(Math.abs(Number(d.changeRate || 0)) * 10) / 10) + "W"
  }

  readonly property string aggregateTime: {
    var d = UPower.displayDevice
    if (!d || !d.isPresent) return ""
    return formatDuration(root.discharging ? d.timeToEmpty : d.timeToFull)
  }

  function upowerStates() {
    return {
      Charging: UPowerDeviceState.Charging,
      Discharging: UPowerDeviceState.Discharging,
      FullyCharged: UPowerDeviceState.FullyCharged,
      PendingCharge: UPowerDeviceState.PendingCharge
    }
  }

  function selectProfileByDelta(delta) {
    profileIndex = Model.selectProfileIndex(profileIndex, delta, profiles)
  }

  function activateSelectedProfile() {
    if (profileIndex < 0 || profileIndex >= profiles.length) return
    setProfile(profiles[profileIndex])
  }

  function batteryIcon() {
    var device = UPower.displayDevice
    return Model.batteryIcon(device, root.discharging, upowerStates())
  }

  function modeLabel() {
    var device = UPower.displayDevice
    return Model.modeLabel(device, root.discharging, upowerStates())
  }

  function profileIcon(name) {
    return Model.profileIcon(name)
  }

  readonly property bool fullyCharged: {
    var device = UPower.displayDevice
    return device && device.isPresent && device.state === UPowerDeviceState.FullyCharged && !root.chargeThresholdActive
  }
  readonly property bool discharging: {
    var device = UPower.displayDevice
    return !!(device && device.isPresent && UPower.onBattery)
  }
  readonly property bool chargeThresholdActive: {
    var device = UPower.displayDevice
    return Model.chargeThresholdActive(device, root.discharging, upowerStates())
  }
  readonly property bool batteryFull: fullyCharged || (!root.discharging && batteryFraction >= 1)
  readonly property bool batteryFlowIdle: batteryFull || chargeThresholdActive

  // 0..1 charge level, used by the visual progress bar.
  readonly property real batteryFraction: {
    var d = UPower.displayDevice
    return Model.batteryFraction(d)
  }

  readonly property bool charging: {
    var d = UPower.displayDevice
    return d && d.isPresent && !UPower.onBattery && !root.batteryFlowIdle
  }

  readonly property color batteryFillColor: {
    return root.bar ? root.bar.foreground : Color.foreground
  }

  // Cute agent-flavored phrases shown in the hero status line, rotated on a
  // timer so the panel feels alive when current is flowing (either direction).
  readonly property var chargingPhrases: [
    "Pumping power",
    "Injecting electrons",
    "Pouring juice",
    "Amassing watts",
    "Hoarding joules",
    "Sucking volts",
    "Topping reserves",
    "Soaking amps",
    "Inhaling kilowatts"
  ]
  readonly property var onBatteryPhrases: [
    "Slurping power",
    "Spending joules",
    "Draining watts",
    "Burning electrons",
    "Sipping juice",
    "Spending coulombs",
    "Bleeding amps",
    "Guzzling volts",
    "Munching reserves"
  ]
  property int phraseIndex: 0

  // Whichever list is "active" given the current power state.
  readonly property var activePhrases: {
    if (fullyCharged) return []
    if (charging) return chargingPhrases
    if (discharging) return onBatteryPhrases
    return []
  }
  readonly property bool rotatingPhrases: activePhrases.length > 0

  readonly property string heroStatusText: {
    if (fullyCharged) return "Fully charged"
    if (rotatingPhrases) return activePhrases[phraseIndex % activePhrases.length]
    return modeLabel()
  }

  function refresh() {
    if (!batteryPresent) return

    if (!batteryProc.running) batteryProc.running = true
    if (!packsProc.running) packsProc.running = true
    if (!profilesProc.running) profilesProc.running = true
    if (!systemProc.running) systemProc.running = true
  }

  function updateKeyValue(raw, targetName) {
    var next = Model.parseKeyValue(raw)
    // Keep last known good data if a refresh briefly returns nothing — happens
    // around AC plug/unplug events. Avoids the section collapsing mid-transition.
    if (Object.keys(next).length === 0) return
    if (targetName === "battery") batteryInfo = next
    else systemInfo = next
  }

  function updatePackMeta(raw) {
    var next = Model.parsePackMeta(raw)
    // Same guard as the other refreshes: a transient empty read must not blank
    // the section out mid-transition.
    if (Object.keys(next).length === 0) return
    packMeta = next
  }

  function updateProfiles(raw) {
    var parsed = Model.parseProfiles(raw, profileIndex)
    // Same guard as battery: preserve the last known profile list across
    // transient empty payloads so the buttons don't blink out.
    if (parsed.profiles.length === 0) return
    profiles = parsed.profiles
    activeProfile = parsed.activeProfile
    profileIndex = parsed.profileIndex
    if (opened && !cursorActive) {
      var idx = profiles.indexOf(activeProfile)
      if (idx >= 0) profileIndex = idx
    }
  }

  function setProfile(profile) {
    if (!profile || actionProc.running) return
    actionProc.command = ["omarchy-powerprofiles-set", root.discharging ? "battery" : "ac", profile]
    actionProc.running = true
  }

  function togglePercentage() {
    root.settings = Object.assign({}, root.settings, { showPercentage: !root.showPercentage })
    if (root.bar && root.bar.shell) root.bar.shell.updateEntryInline(root.moduleName, root.settings)
  }

  IpcHandler {
    target: "cinco.batteries"

    function open() { root.open() }
    function close() { root.close() }
    function show() { root.open() }
    function hide() { root.close() }
    function toggle() { root.toggle() }
    function togglePercentage() { root.togglePercentage() }
  }

  // Compatibility handler. Omarchy's own menu entry and any user script still
  // address the power panel as "omarchy.power"; answering to it keeps those
  // working after this plugin takes the built-in widget's place. Claiming the
  // target is safe because clonedFrom makes the two mutually exclusive: the
  // built-in is disabled whenever this plugin is enabled.
  IpcHandler {
    target: "omarchy.power"

    function open() { root.open() }
    function close() { root.close() }
    function show() { root.open() }
    function hide() { root.close() }
    function toggle() { root.toggle() }
    function togglePercentage() { root.togglePercentage() }
  }

  onOpenedChanged: {
    if (opened) {
      if (!batteryPresent) {
        close()
        return
      }

      refresh()
      var idx = profiles.indexOf(activeProfile)
      profileIndex = idx >= 0 ? idx : 0
      cursorActive = false
    }
  }

  onBatteryPresentChanged: if (!batteryPresent) close()

  visible: batteryPresent
  implicitWidth: batteryPresent ? (perPack ? packRow.implicitWidth : button.implicitWidth) : 0
  implicitHeight: batteryPresent ? (perPack ? packRow.implicitHeight : button.implicitHeight) : 0

  Process {
    id: batteryProc
    command: ["omarchy-battery-status", "--shell"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateKeyValue(text, "battery") }
  }

  Process {
    id: packsProc
    command: [String(Qt.resolvedUrl("battery-packs")).replace(/^file:\/\//, "")]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updatePackMeta(text) }
  }

  Process {
    id: profilesProc
    command: ["omarchy-powerprofiles-list", "--active-state"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateProfiles(text) }
  }

  Process {
    id: systemProc
    command: ["omarchy-system-stats"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateKeyValue(text, "system") }
  }

  Process {
    id: actionProc
    onExited: root.refresh()
  }

  Timer { interval: 5000; running: root.opened; repeat: true; onTriggered: root.refresh() }

  // Rotate the status phrase while the panel is open and we're in a
  // rotating state (charging or on battery). The text swap is wrapped in a
  // fade so the changeover reads as one organism rather than a hard cut.
  Timer {
    id: phraseTimer
    interval: 2800
    running: root.opened && root.rotatingPhrases
    repeat: true
    triggeredOnStart: false
    onTriggered: phraseSwap.restart()
  }

  SequentialAnimation {
    id: phraseSwap
    PropertyAnimation {
      target: heroStatus; property: "opacity"
      to: 0.0; duration: 180; easing.type: Easing.OutQuad
    }
    ScriptAction {
      script: {
        var n = root.activePhrases.length
        if (n > 0) root.phraseIndex = (root.phraseIndex + 1) % n
      }
    }
    PropertyAnimation {
      target: heroStatus; property: "opacity"
      to: 1.0; duration: 260; easing.type: Easing.InQuad
    }
  }

  // If we leave a rotating state mid-swap, halt the animation and snap back
  // to full opacity so "FULLY CHARGED" is legible immediately rather than
  // appearing dimmed.
  Connections {
    target: root
    function onRotatingPhrasesChanged() {
      if (!root.rotatingPhrases) {
        phraseSwap.stop()
        heroStatus.opacity = 1.0
      }
    }
  }

  // A single pack, or any vertical bar, uses one BarIconButton exactly like
  // the built-in omarchy.power widget: `text` is the glyph, `labelText` the
  // percentage.
  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    visible: !root.perPack
    text: root.batteryIcon()
    labelText: root.showPercentage && !vertical ? Math.round(root.batteryFraction * 100) + "%" : ""
    slotSize: Style.bar.iconSlot * (root.showPercentage && !vertical ? 2 : 1)
    tooltipText: ""
    onPressed: function(b) { root.handlePress(b) }
  }

  // Several packs on a horizontal bar: one BarIconButton per pack, each with
  // its own glyph and percentage, so every pack is drawn, sized and aligned by
  // Omarchy's own button instead of a reimplementation of its internals.
  // Each button takes its own hover and press feedback.
  Row {
    id: packRow
    anchors.centerIn: parent
    visible: root.perPack
    spacing: 0

    // Length of the open-panel mark: it covers the first pack's painted
    // content to the last one's. The bar centres the mark on the slot, so the
    // span is made symmetric about the row's centre; packs with labels of
    // different widths (100% and 9%) would otherwise leave it off-centre.
    readonly property real paintedExtent: {
      var first = null, last = null
      for (var i = 0; i < children.length; i++) {
        var c = children[i]
        if (!c || !c.visible || c.contentWidth === undefined) continue
        if (!first) first = c
        last = c
      }
      if (!first) return 0
      var left = first.x + (first.width - first.contentWidth) / 2
      var right = last.x + (last.width + last.contentWidth) / 2
      var mid = width / 2
      return 2 * Math.max(mid - left, right - mid)
    }

    Repeater {
      model: root.perPack ? root.batteries : []

      BarIconButton {
        id: packButton
        required property var modelData
        bar: root.bar
        text: root.deviceIcon(modelData)
        labelText: root.showPercentage ? root.devicePercentage(modelData) + "%" : ""
        slotSize: Style.bar.iconSlot * (root.showPercentage ? 2 : 1)
        tooltipText: ""
        // Width of what BarIconButton paints. Mirrors its content.width
        // (canvasSize + label + Style.space(4)), which it does not expose:
        // keep in sync with Ui/BarIconButton.qml.
        readonly property real contentWidth: canvasSize
          + (labelText !== "" ? pctMetrics.advanceWidth + Style.space(4) : 0)
        onPressed: function(b) { root.handlePress(b) }

        TextMetrics {
          id: pctMetrics
          font.family: packButton.fontFamily
          font.pixelSize: packButton.fontSize
          text: packButton.labelText
        }
      }
    }
  }

  KeyboardPanel {
    id: panel
    // button spans the whole widget even while hidden, so it anchors the
    // panel in both layouts and a pack hot-swap never moves the anchor.
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened && root.batteryPresent
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dx !== 0) root.selectProfileByDelta(dx)
        else if (dy !== 0) root.selectProfileByDelta(dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateSelectedProfile()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        // ---------- Hero: battery icon · title/status · percentage ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, heroPercent.implicitHeight)

          Text {
            id: heroIcon
            text: root.batteryIcon()
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter

            Behavior on color { ColorAnimation { duration: 200 } }
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: heroPercent.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: "Battery"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              id: heroStatus
              text: root.heroStatusText.toUpperCase()
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
              width: parent.width
            }
          }

          Text {
            id: heroPercent
            text: root.multiBattery ? root.aggregatePercentage : (root.batteryInfo.percentage || "—")
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.displayLarge
            font.bold: true
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            Behavior on color { ColorAnimation { duration: 200 } }
          }
        }

        // ---------- Battery progress bar ----------
        Item {
          width: parent.width
          implicitHeight: Style.space(8)

          Rectangle {
            id: barTrack
            anchors.fill: parent
            radius: height / 2
            color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.12)
          }

          Rectangle {
            id: barFill
            anchors.left: barTrack.left
            anchors.verticalCenter: barTrack.verticalCenter
            height: barTrack.height
            radius: barTrack.radius
            color: root.batteryFillColor
            width: Math.max(barTrack.height, barTrack.width * root.batteryFraction)

            Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: 220 } }

            // Subtle pulse while charging — visible signal that energy is flowing in.
            SequentialAnimation on opacity {
              running: root.charging && !root.fullyCharged && root.opened
              loops: Animation.Infinite
              alwaysRunToEnd: true
              NumberAnimation { from: 1.0; to: 0.55; duration: 950; easing.type: Easing.InOutSine }
              NumberAnimation { from: 0.55; to: 1.0; duration: 950; easing.type: Easing.InOutSine }
            }
          }
        }

        // ---------- Stats ----------
        // Visibility is intentionally only gated by "we've ever loaded data" so
        // the section never collapses mid-transition. fullyCharged is *not* part
        // of the condition: UPower briefly reports FullyCharged on plug-in when
        // the battery sits above the charge-control start threshold, and we
        // refuse to flicker the whole panel for that ~1s window.
        Row {
          visible: root.batteryInfo.percentage !== undefined || root.multiBattery
          width: parent.width
          spacing: Style.space(20)

          Column {
            width: (parent.width - parent.spacing) / 2
            spacing: Style.spacing.labelGap
            InfoPair { label: "Battery size"; value: root.multiBattery ? root.aggregateSize : (root.batteryInfo.size || "") }
            InfoPair {
              label: root.multiBattery ? "Health" : "Charge cycles"
              value: root.multiBattery ? root.aggregateHealth : (root.batteryInfo.cycles || "—")
            }
          }

          Column {
            width: (parent.width - parent.spacing) / 2
            spacing: Style.spacing.labelGap
            InfoPair {
              label: root.chargeThresholdActive ? "Charge limit" : (root.discharging ? "Time left" : "Time to full")
              value: root.chargeThresholdActive
                ? (root.batteryInfo.threshold || "-")
                : (root.batteryFlowIdle ? "-" : ((root.multiBattery ? root.aggregateTime : root.batteryInfo.time) || "—"))
            }
            InfoPair {
              label: root.chargeThresholdActive ? "Battery state" : (root.discharging ? "Discharging" : "Charging")
              value: root.chargeThresholdActive
                ? "Holding"
                : (root.batteryFull ? "-" : ((root.multiBattery ? root.aggregateRate : root.batteryInfo.rate) || ""))
            }
          }
        }

        // ---------- Per-pack breakdown (dual-battery ThinkPads) ----------
        Column {
          visible: root.multiBattery
          width: parent.width
          spacing: Style.space(10)

          PanelSeparator {
            foreground: root.bar.foreground
          }

          PanelSectionHeader {
            text: "BATTERIES"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Repeater {
            model: root.batteries

            Column {
              required property var modelData
              width: parent.width
              spacing: Style.space(6)
              topPadding: index > 0 ? Style.space(6) : 0

              required property int index

              // Pack header: name on the left, level and icon on the right.
              Item {
                width: parent.width
                implicitHeight: Math.max(packName.implicitHeight, packLevel.implicitHeight)

                Text {
                  id: packName
                  text: root.deviceLabel(modelData)
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  id: packLevel
                  text: root.devicePercentage(modelData) + "%  " + root.deviceIcon(modelData)
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              Row {
                width: parent.width
                spacing: Style.space(20)

                Column {
                  width: (parent.width - parent.spacing) / 2
                  spacing: Style.spacing.labelGap
                  InfoPair { label: "Size"; value: root.packSize(modelData) }
                  InfoPair { label: "Cycles"; value: root.packCycles(modelData) }
                  InfoPair { label: "Health"; value: root.packHealth(modelData) }
                }

                Column {
                  width: (parent.width - parent.spacing) / 2
                  spacing: Style.spacing.labelGap
                  InfoPair { label: root.packFlowLabel(modelData); value: root.packFlowValue(modelData) }
                  InfoPair { label: root.packFlowRateLabel(modelData); value: root.packRate(modelData) }
                  InfoPair { label: "Charge limit"; value: root.packThreshold(modelData) }
                }
              }
            }
          }
        }

        // ---------- Power profile picker ----------
        PanelSeparator {
          foreground: root.bar.foreground
        }

        Column {
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: "POWER PROFILE"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Row {
            id: profileRow
            width: parent.width
            spacing: Style.space(6)

            readonly property real cellWidth: root.profiles.length > 0
              ? (width - spacing * (root.profiles.length - 1)) / root.profiles.length
              : 0

            Repeater {
              model: root.profiles
              Button {
                required property var modelData
                required property int index
                width: profileRow.cellWidth
                iconText: root.profileIcon(String(modelData))
                iconSize: Style.font.title
                text: String(modelData).charAt(0).toUpperCase() + String(modelData).slice(1)
                fontSize: Style.font.bodySmall
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
                bordered: true
                active: root.activeProfile === modelData
                hasCursor: root.cursorActive && root.profileIndex === index
                onClicked: root.setProfile(modelData)
                onHovered: function(h) {
                  if (h) {
                    root.cursorActive = true
                    root.profileIndex = index
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  component InfoPair: Row {
    property string label: ""
    property string value: ""

    width: parent.width
    spacing: Style.space(8)

    InfoLabel { text: label }
    Item { width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth - parent.spacing * 2); height: 1 }
    InfoValue { text: value }
  }

  component InfoLabel: Text {
    color: root.bar.foreground
    opacity: 0.6
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  component InfoValue: Text {
    color: root.bar.foreground
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.bodySmall
  }
}
