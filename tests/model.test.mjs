import test from "node:test"
import assert from "node:assert/strict"
import { load } from "./loader.mjs"

const M = load("Model.js")
const en = M.config({ language: "en" })
const ru = M.config({ language: "ru" })
const plain = x => JSON.parse(JSON.stringify(x))
const temps = [
  { group: "cpu", label: "Package id 0", crit: 100 }, { group: "cpu", label: "Core 0", crit: 100 },
  { group: "ssd", label: "Composite", crit: null }, { group: "board", label: "acpitz", crit: null }
]

test("groups: package leads the processor, the hottest core beside it, fixed order", () => {
  const g = plain(M.groups(temps, [80000, 91000, 58850, null]))
  assert.deepEqual(g.map(x => x.group), ["cpu", "ssd"])
  assert.equal(g[0].main, 80)
  assert.equal(g[0].hottest, 91)
  assert.equal(g[0].crit, 100)
  assert.equal(g[1].main, 58.85)
})

test("level: hot near the limit or a hot core, warm from 75", () => {
  assert.equal(M.level({ main: 60, hottest: 62, crit: 100 }), "calm")
  assert.equal(M.level({ main: 78, hottest: 80, crit: 100 }), "warm")
  assert.equal(M.level({ main: 85, hottest: 91, crit: 100 }), "hot")
  assert.equal(M.level({ main: 82, hottest: 82, crit: 90 }), "hot")
  assert.equal(M.level(null), "calm")
  assert.equal(M.kitLevel("hot"), "bad")
})

test("fan rows: share of the fastest speed seen, words for a stopped fan", () => {
  const fans = [{ path: "/a" }, { path: "/b" }, { path: "/c" }]
  const rows = plain(M.fanRows(ru, fans, [5000, 0, null], { "/a": 6000 }))
  assert.equal(rows.length, 2)
  assert.equal(rows[0].text, "5000 об/мин")
  assert.equal(rows[0].fraction, 5000 / 6000)
  assert.equal(rows[1].label, "Вентилятор 2")
  assert.equal(rows[1].text, "стоит")
  const two = plain(M.fanRows(en, fans.slice(0, 2), [5000, 4000], {}))
  assert.equal(two[1].fraction, 0.8, "the slower fan is measured against the faster one")
  assert.equal(M.headerSay(ru, rows), "2 вентилятора · 5000 об/мин")
  assert.equal(M.headerSay(en, []), "Linux sees no fans on this computer")
  assert.equal(M.headerSay(en, [rows[1]]), "1 fan · stopped")
})

test("profiles: whatever the daemon offers, quietest first", () => {
  const p = plain(M.parseProfiles("* performance:\n    CpuDriver: intel_pstate\n    Degraded:   no\n\n  balanced:\n  power-saver:\n"))
  assert.deepEqual(p, { active: "performance", available: ["power-saver", "balanced", "performance"] })
  assert.deepEqual(plain(M.parseProfiles("  balanced:\n* low-power:\n")).available, ["low-power", "balanced"])
  assert.deepEqual(plain(M.parseProfiles("")), { active: "", available: [] })
})

test("modes follow the machine: Auto from two profiles, Max only with a switch", () => {
  assert.deepEqual(plain(M.modes(["power-saver", "balanced", "performance"], true)), ["auto", "power-saver", "balanced", "performance", "max"])
  assert.deepEqual(plain(M.modes(["balanced"], false)), ["balanced"])
  assert.deepEqual(plain(M.modes([], false)), [])
  assert.equal(M.modeLabel(ru, "power-saver"), "Тихо")
  assert.equal(M.modeLabel(ru, "cool"), "Прохладно")
  assert.equal(M.modeLabel(en, "turbo-ludicrous"), "Turbo-ludicrous")
})

test("the mode in force comes from platform_profile", () => {
  const av = ["power-saver", "balanced", "performance"]
  assert.equal(M.profileFromPlatform("quiet\n", av), "power-saver")
  assert.equal(M.profileFromPlatform("cool", av), "power-saver")
  assert.equal(M.profileFromPlatform("performance", av), "performance")
  assert.equal(M.profileFromPlatform("", av), "")
})

test("auto: quiet at rest, medium at work, never the loudest", () => {
  const av = ["power-saver", "balanced", "performance"]
  assert.equal(M.autoTarget(50, 1, 16, av), "power-saver")
  assert.equal(M.autoTarget(65, 12, 16, av), "balanced")
  assert.equal(M.autoTarget(80, 1, 16, av), "balanced")
  assert.equal(M.autoTarget(62, 6, 16, av), null, "in between: keep what is")
  assert.equal(M.autoTarget(50, 1, 16, ["balanced"]), null)
  assert.equal(M.cpuCount("0-15"), 16)
  assert.equal(M.cpuCount("0,2-5"), 5)
})

test("readings and discovery parsing", () => {
  assert.equal(M.reading("5085\n"), 5085)
  assert.equal(M.reading(""), null)
  assert.equal(M.deg(88.4), "88°")
  assert.equal(M.deg(null), "—")
  assert.equal(M.parseDiscovery("x"), null)
  assert.equal(M.parseDiscovery('{"fans":[],"temps":[],"profiles":true}').profiles, true)
  const d = M.parseDiscovery('{"fans":[],"temps":[],"platform":"/p","maxFan":"/m","helper":true}')
  assert.deepEqual([d.platform, d.maxFan, d.helper], ["/p", "/m", true])
})

test("helper version read from the installed file", () => {
  assert.equal(M.helperVersion("#!/bin/bash\n# helper-version: 2\n"), 2)
  assert.equal(M.helperVersion("#!/bin/bash\n"), 0)
  assert.equal(M.helperVersion(""), 0)
  assert.ok(M.HELPER_VERSION >= 2)
})
