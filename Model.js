.pragma library
.import "kit/I18n.js" as I18n
.import "Strings.js" as Strings

// Pure logic of the Cooling widget: discovery, readings, levels and texts.
// No QML here, so tests run it in plain Node.

var GROUP_ORDER = ["cpu", "gpu", "ssd", "board", "other"]
var GROUP_KEYS = { cpu: "groupCpu", gpu: "groupGpu", ssd: "groupSsd", board: "groupBoard", other: "groupOther" }
var PROFILES = ["power-saver", "balanced", "performance"]

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
  return { fans: d.fans, temps: d.temps, gpus: Array.isArray(d.gpus) ? d.gpus : [], profiles: d.profiles === true }
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

// `powerprofilesctl list`: "* performance:" marks the active one.
function parseProfiles(text) {
  var out = { active: "", available: [] }
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var m = lines[i].match(/^(\*?)\s*([a-z-]+):\s*$/)
    if (!m || PROFILES.indexOf(m[2]) < 0) continue
    out.available.push(m[2])
    if (m[1] === "*") out.active = m[2]
  }
  out.available.sort(function(a, b) { return PROFILES.indexOf(a) - PROFILES.indexOf(b) })
  return out
}
