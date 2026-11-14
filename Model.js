.pragma library
.import "kit/I18n.js" as I18n
.import "Strings.js" as Strings

// Pure logic of the Cooling widget: discovery, readings, levels and texts.
// No QML here, so tests run it in plain Node.

var GROUP_ORDER = ["cpu", "gpu", "ssd", "board", "other"]
var GROUP_KEYS = { cpu: "groupCpu", gpu: "groupGpu", ssd: "groupSsd", board: "groupBoard", other: "groupOther" }

function config(raw) {
  return { lang: I18n.resolve(raw && raw.language, raw && raw.locale, Strings.langs, { "русский": "ru", english: "en" }) }
}
function tr(cfg, key, params) { return I18n.t(Strings.tables, cfg.lang, key, params) }
function count(cfg, key, n) { return I18n.count(Strings.tables, cfg.lang, key, n) }

// discover.py's answer; null when it is not one.
function parseDiscovery(raw) {
  var d
  try { d = JSON.parse(String(raw || "")) } catch (e) { return null }
  if (!d || !Array.isArray(d.fans) || !Array.isArray(d.temps)) return null
  return { fans: d.fans, temps: d.temps, gpus: Array.isArray(d.gpus) ? d.gpus : [], profiles: d.profiles === true,
           platform: typeof d.platform === "string" ? d.platform : null,
           maxFan: typeof d.maxFan === "string" ? d.maxFan : null,
           helper: d.helper === true }
}

// A sysfs number, or null for an empty or broken read.
function reading(text) {
  var n = parseInt(String(text || "").trim(), 10)
  return isFinite(n) ? n : null
}

// "88°"
function deg(t) { return t === null || t === undefined ? "—" : Math.round(t) + "°" }

// Temperatures by group: [{ group, main, hottest, crit, rows }] in degrees,
// in a fixed order. The CPU's main figure is its package (or Tctl), the
// hottest core beside it; other groups show their hottest sensor.
function groups(temps, values) {
  var by = {}
  for (var i = 0; i < temps.length; i++) {
    var v = values[i]
    if (v === null || v === undefined) continue
    var t = temps[i]
    var g = by[t.group] || (by[t.group] = { group: t.group, main: null, hottest: null, crit: null, rows: [] })
    var c = v / 1000
    g.rows.push({ label: t.label, t: c })
    if (g.hottest === null || c > g.hottest) g.hottest = c
    if (/^(Package id|Tctl|Tdie|Composite|edge)/.test(t.label)) g.main = c
    if (t.crit !== null && t.crit !== undefined) g.crit = g.crit === null ? t.crit : Math.min(g.crit, t.crit)
  }
  var out = []
  for (var k = 0; k < GROUP_ORDER.length; k++) {
    var gg = by[GROUP_ORDER[k]]
    if (!gg) continue
    if (gg.main === null) gg.main = gg.hottest
    out.push(gg)
  }
  return out
}

// cool / warm / hot for the processor: hot near its limit (or 90°), warm from 75°.
function level(cpu) {
  if (!cpu || cpu.main === null) return "calm"
  var hot = cpu.crit ? Math.min(90, cpu.crit - 10) : 90
  var t = Math.max(cpu.main, cpu.hottest || 0)
  return t >= hot ? "hot" : t >= 75 ? "warm" : "calm"
}

function kitLevel(l) { return l === "hot" ? "bad" : l === "warm" ? "warn" : "good" }

// Fans with their share of the fastest speed any of them reached (a fan's own
// maximum is rarely known), so a slower fan reads as slower.
function fanRows(cfg, fans, values, peaks) {
  var out = []
  var peak = 1
  for (var j = 0; j < fans.length; j++)
    peak = Math.max(peak, peaks[fans[j].path] || 0, values[j] || 0)
  for (var i = 0; i < fans.length; i++) {
    var rpm = values[i]
    if (rpm === null || rpm === undefined) continue
    out.push({ key: fans[i].path, label: tr(cfg, "fan", { n: out.length + 1 }), rpm: rpm,
               text: rpm > 0 ? tr(cfg, "rpm", { n: rpm }) : tr(cfg, "stopped"), fraction: rpm / peak })
  }
  return out
}

function groupLabel(cfg, g) { return tr(cfg, GROUP_KEYS[g] || "groupOther") }

function headerSay(cfg, fans) {
  if (fans.length === 0) return tr(cfg, "noFans")
  var moving = fans.filter(function(f) { return f.rpm > 0 })
  var word = count(cfg, "fansN", fans.length)
  if (moving.length === 0) return tr(cfg, "fansIdle", { fans: word })
  return tr(cfg, "fansSay", { fans: word, rpm: moving.map(function(f) { return f.rpm }).join(" · ") })
}

function tooltip(cfg, cpu, fans) {
  return tr(cfg, "tipBar", { t: deg(cpu ? cpu.main : null), fans: headerSay(cfg, fans) })
}

// `powerprofilesctl list`: "* performance:" marks the active one. Every
// profile the daemon offers is kept, whatever this machine calls it.
function parseProfiles(text) {
  var out = { active: "", available: [] }
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var m = lines[i].match(/^(\*?)\s*([a-z][a-z-]*):\s*$/)
    if (!m) continue
    out.available.push(m[2])
    if (m[1] === "*") out.active = m[2]
  }
  // Quietest first: the daemon lists them loudest first.
  out.available.sort(function(a, b) { return rank(a) - rank(b) })
  return out
}

// Known names from quiet to loud; an unknown one goes in the middle.
var RANK = { "cool": 0, "low-power": 1, "power-saver": 1, "quiet": 1, "balanced": 2, "balanced-performance": 3, "performance": 4 }
function rank(name) { return RANK[name] !== undefined ? RANK[name] : 2.5 }

// The words for a mode; a name nobody taught us is shown as the system says it.
var LABELS = { "cool": "modeCool", "low-power": "modeQuiet", "power-saver": "modeQuiet", "quiet": "modeQuiet",
               "balanced": "modeBalanced", "balanced-performance": "modeBalancedPerf", "performance": "modePerformance",
               "auto": "modeAuto", "max": "modeMax" }
function modeLabel(cfg, name) {
  return LABELS[name] ? tr(cfg, LABELS[name]) : String(name).charAt(0).toUpperCase() + String(name).slice(1)
}

// The buttons this machine can have: Auto when there are two profiles to
// choose between, every profile, Max when a full-speed switch exists.
function modes(available, hasMax) {
  var out = available.length >= 2 ? ["auto"] : []
  out = out.concat(available)
  if (hasMax) out.push("max")
  return out
}

// platform_profile (readable without root) -> the daemon's name for it.
function profileFromPlatform(text, available) {
  var p = String(text || "").trim()
  if (!p) return ""
  if (available.indexOf(p) >= 0) return p
  var quiet = { "quiet": 1, "low-power": 1, "cool": 1 }
  if (quiet[p]) return available.filter(function(a) { return rank(a) <= 1 })[0] || ""
  if (p === "balanced-performance") return available.indexOf("balanced") >= 0 ? "balanced" : ""
  return ""
}

// Auto: the quietest profile while the computer rests, the middle one while it
// works, never the loudest. null = no reason to change.
//   cpu: degrees, load: 1-minute load average, cpus: how many
function autoTarget(cpu, load, cpus, available) {
  if (available.length < 2) return null
  var quiet = available[0]
  var busyOne = available.indexOf("balanced") >= 0 ? "balanced" : available[Math.min(1, available.length - 1)]
  var share = cpus > 0 ? load / cpus : 0
  if (share > 0.5 || (cpu !== null && cpu >= 70)) return busyOne
  if (share < 0.25 && (cpu === null || cpu < 60)) return quiet
  return null
}

// /sys/devices/system/cpu/online "0-15" or "0,2-5" -> how many.
function cpuCount(text) {
  var n = 0
  var parts = String(text || "").trim().split(",")
  for (var i = 0; i < parts.length; i++) {
    var r = parts[i].split("-").map(Number)
    if (r.length === 2 && isFinite(r[0]) && isFinite(r[1])) n += r[1] - r[0] + 1
    else if (r.length === 1 && isFinite(r[0]) && parts[i] !== "") n += 1
  }
  return n
}

// POSIX single-quoting: any string becomes one shell word.
function shellQuote(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }

