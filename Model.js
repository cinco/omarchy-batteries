function clampIndex(index, length) {
  if (length <= 0) return 0
  return Math.max(0, Math.min(length - 1, index))
}

function selectProfileIndex(index, delta, profiles) {
  var values = Array.isArray(profiles) ? profiles : []
  if (values.length === 0) return 0
  return clampIndex(index + delta, values.length)
}

function parseKeyValue(raw) {
  var next = {}
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var idx = lines[i].indexOf("\t")
    if (idx <= 0) continue
    next[lines[i].substring(0, idx)] = lines[i].substring(idx + 1).trim()
  }
  return next
}

function parseProfiles(raw, previousIndex) {
  var lines = String(raw || "").split("\n")
  var list = []
  var active = ""
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (!line) continue
    var parts = line.split("\t")
    list.push(parts[0])
    if (parts[1] === "1") active = parts[0]
  }
  return {
    profiles: list,
    activeProfile: active,
    profileIndex: clampIndex(previousIndex || 0, list.length)
  }
}

function profileIcon(name) {
  if (name === "power-saver") return "󰌪"
  if (name === "balanced") return "󰊚"
  if (name === "performance") return "󰓅"
  return "󰂄"
}

function batteryFraction(device) {
  return device && device.isPresent ? Math.max(0, Math.min(1, device.percentage)) : 0
}

function chargeThresholdActive(device, onBattery, states) {
  var d = device || {}
  var s = states || {}
  if (!(d && d.isPresent && !onBattery)) return false

  var fraction = batteryFraction(d)
  if (d.state === s.Discharging) return false
  if (d.state === s.PendingCharge) return true
  if (d.state === s.FullyCharged && fraction < 0.99) return true
  if (d.state !== s.Charging || fraction >= 0.99) return false

  return Number(d.changeRate || 0) <= 0.2 || Number(d.timeToFull || 0) >= 8 * 60 * 60
}

// --- dual-battery additions (ThinkPad Power Bridge) ---------------------------
// UPower.displayDevice only reports the aggregate across every pack, which hides
// the case this machine actually hits: one battery at 5% while the other is at
// 76%. These helpers render a single physical device instead of the composite.

var CHARGING_ICONS = ["󰢜", "󰂆", "󰂇", "󰂈", "󰢝", "󰂉", "󰢞", "󰂊", "󰂋", "󰂅"]
var DEFAULT_ICONS = ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]

// Parses the battery-packs helper output: one TSV row per pack, fixed columns
// name/cycles/design_wh/full_wh/start_thresh/stop_thresh, with "-" for anything
// the kernel does not report.
function parsePackMeta(raw) {
  var out = {}
  var lines = String(raw || "").split("\n")

  function field(value) {
    var text = String(value || "").trim()
    return text === "-" ? "" : text
  }

  for (var i = 0; i < lines.length; i++) {
    if (!lines[i]) continue
    var parts = lines[i].split("\t")
    if (parts.length < 6) continue

    out[parts[0]] = {
      cycles: field(parts[1]),
      design: field(parts[2]),
      full: field(parts[3]),
      start: field(parts[4]),
      stop: field(parts[5])
    }
  }
  return out
}

function batteryLabel(device) {
  var d = device || {}
  var name = String(d.nativePath || "").split("/").pop()
  return name || String(d.model || "Battery")
}

function devicePercentage(device) {
  return Math.round(batteryFraction(device) * 100)
}

// Per-device icon. Unlike batteryIcon() this keys off the device's own state
// rather than the global on-AC flag, so an idle pack on a Power Bridge laptop
// does not get painted as if it were charging.
function deviceIcon(device, states) {
  var d = device || {}
  if (!d.isPresent) return ""

  var index = Math.max(0, Math.min(9, Math.floor(batteryFraction(d) * 10)))
  var s = states || {}

  if (d.state === s.FullyCharged) return CHARGING_ICONS[9]
  if (d.state === s.Charging) return CHARGING_ICONS[index]
  return DEFAULT_ICONS[index]
}

function batteryIcon(device, onBattery, states) {
  var d = device || {}
  if (!d.isPresent) return ""

  var chargingIcons = CHARGING_ICONS
  var defaultIcons = DEFAULT_ICONS
  var index = Math.max(0, Math.min(9, Math.floor(d.percentage * 10)))
  var threshold = chargeThresholdActive(d, onBattery, states)

  if (threshold) return defaultIcons[index]
  if (d.state === states.FullyCharged) return "󰂅"
  if (!onBattery) return chargingIcons[index]
  return defaultIcons[index]
}

function modeLabel(device, onBattery, states) {
  var d = device || {}
  if (!d.isPresent) return ""

  var percentage = d.isPresent ? d.percentage : 0
  if (chargeThresholdActive(d, onBattery, states)) return "Threshold"
  if (onBattery) return "On battery"
  if (!onBattery && percentage >= 1) return "Fully charged"
  return "Charging"
}

// --- charge reminder (unplug notifier) --------------------------------------
// For machines without kernel charge_control_* files there is no hardware
// cutoff, so this is a reminder, not a limiter. The panel stores the choice
// in shell.json (reminderEnabled / reminderThreshold) for external monitors
// to read.
//
// NOTE: QML only sees top-level names in this file (`Model.foo`), NOT
// anything under `module.exports` (Node-only). Keep the option list and
// default as top-level `var`s so Panel.qml can bind to them.

var reminderOptions = [80, 85, 90, 95];
var reminderDefault = 80;

function normalizeReminderThreshold(value) {
  var n = Math.round(Number(value));
  if (isNaN(n)) return reminderDefault;
  var best = reminderOptions[0];
  for (var i = 1; i < reminderOptions.length; i++) {
    if (Math.abs(reminderOptions[i] - n) < Math.abs(best - n)) best = reminderOptions[i];
  }
  return best;
}

function normalizeReminderEnabled(value) {
  // Default ON so a fresh install reminds at 80% without any setup.
  if (value === undefined || value === null) return true;
  return value === true || value === "true" || value === 1;
}

if (typeof module !== "undefined") {
  module.exports = {
    clampIndex: clampIndex,
    selectProfileIndex: selectProfileIndex,
    parseKeyValue: parseKeyValue,
    parseProfiles: parseProfiles,
    profileIcon: profileIcon,
    batteryFraction: batteryFraction,
    chargeThresholdActive: chargeThresholdActive,
    batteryIcon: batteryIcon,
    modeLabel: modeLabel,
    batteryLabel: batteryLabel,
    devicePercentage: devicePercentage,
    deviceIcon: deviceIcon,
    parsePackMeta: parsePackMeta,
    reminderOptions: reminderOptions,
    reminderDefault: reminderDefault,
    normalizeReminderThreshold: normalizeReminderThreshold,
    normalizeReminderEnabled: normalizeReminderEnabled
  }
}
