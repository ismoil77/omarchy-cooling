import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "kit" as Kit
import "Model.js" as Model
import "kit/I18n.js" as I18n

// Cooling widget: the processor's temperature in the bar, coloured as it
// heats; the popup lists every fan with its speed, the temperatures by group
// (processor, graphics, SSD, board) and the power mode (power-profiles-daemon,
// no root). Works with whatever hwmon reports; says so when there is no fan.
//
// Cost: discover.py runs once (and when the popup opens); then sensor files
// are re-read in place every `interval` seconds, no process: closed, only the
// processor's. A discrete GPU is read only while the popup is open, and never
// woken up from sleep. Auto runs powerprofilesctl only when it changes the mode.
//
//   left click   - open/close the popup
//   right click  - next power mode
//   popup keys   - 1/2/3 power mode, r look for sensors again, Esc
Panel {
  id: root
  moduleName: "ismoil.fans"
  ipcTarget: "ismoil.fans"
  manageIpc: false

  readonly property var cfg: Model.config({ language: setting("language", "auto"), locale: Qt.locale().name })
  readonly property int pollSeconds: Math.max(1, Number(setting("interval", 3)) || 3)
  readonly property bool vertical: bar ? bar.vertical : false
  readonly property int barSize: bar ? bar.barSize : Style.bar.sizeHorizontal
  readonly property string tachMode: Model.tachMode(setting("tachometer", "both"))
  readonly property string tachColorSetting: String(setting("tachColor", "auto")).trim()
  readonly property string rpmFormatSetting: Model.rpmFormat(setting("rpmFormat", "full"))
  readonly property bool showRpmUnit: Model.boolSetting(setting("rpmUnit", true), true)
  readonly property bool showDivider: Model.boolSetting(setting("barDivider", false), false)
  readonly property int tachMaxSetting: Model.tachMaxValue(setting("tachMax", 0))
  readonly property bool showBarTach: tachMode !== "off"
  property bool barCustomizeOpen: false
  readonly property string icon: "󰈐"

  function tr(key, params) { return Model.tr(cfg, key, params) }
  function localPath(url) { return decodeURIComponent(String(url).replace(/^file:\/\//, "")) }

  FileView { id: manifestFile; path: root.localPath(Qt.resolvedUrl("manifest.json")); blockLoading: true }
  readonly property string version: { try { return JSON.parse(manifestFile.text()).version || "" } catch (e) { return "" } }

  // ---------- state ----------
  property var found: null
  property string foundRaw: ""
  // The first poll reads everything once, so the state is true from the start.
  property bool polledOnce: false
  property var fanValues: []
  property var tempValues: []
  property var peaks: ({})
  property real gpuTemp: -1
  property bool gpuAsleep: false
  property var profiles: ({ active: "", available: [] })
  // "auto" (the widget picks quiet or medium) or "manual" (what was clicked stays).
  readonly property string modeSetting: String(setting("mode", "auto"))
  property string platformText: ""
  property string pwmText: ""
  property real load: 0
  property int cpus: 0
  // Auto changes the mode only after its reason held for 20 s.
  property string pending: ""
  property real pendingSince: 0
  // Each bar (one per monitor) waits a little differently, so the second one
  // sees the first one's switch instead of repeating it.
  readonly property int autoHold: 20000 + Math.round(Math.random() * 6000)
  // Any installed helper is used: a newer widget never asks for the password
  // again just because the helper got a new version. Only a missing helper,
  // or one that just failed (`helperFailed` holds its text until the file
  // changes), is installed anew.
  property string helperText: ""
  property string helperFailed: ""
  readonly property bool helperOk: helperText.indexOf("ismoil-fans-max") >= 0 && helperText !== helperFailed
  // Max was clicked while the helper was missing or old: the installer is
  // open, and Max turns on by itself once it is in place.
  property bool maxAfterInstall: false
  onMaxAfterInstallChanged: if (maxAfterInstall) installGiveUp.restart()
  // The installer window closed without a password: stop waiting for it.
  Timer { id: installGiveUp; interval: 180000; onTriggered: { root.maxAfterInstall = false; root.wanted = "" } }
  readonly property bool maxOn: pwmText.trim() === "on"
  readonly property string active: Model.profileFromPlatform(platformText, profiles.available) || profiles.active
  readonly property var modes: Model.modes(profiles.available, !!(found && found.maxFan))
  // The button just clicked shows at once; the system's answer replaces it
  // as soon as it is read (at the latest after 6 s).
  property string wanted: ""
  readonly property string fromSystem: maxOn ? "max"
    : modeSetting === "auto" && modes.indexOf("auto") >= 0 ? "auto" : active
  readonly property string selected: wanted !== "" ? wanted : fromSystem
  // The system applies a mode a moment after the command returns: the click
  // stays lit until the system shows the same.
  onFromSystemChanged: if (fromSystem === wanted) wanted = ""

  Timer { id: wantedReset; interval: 6000; onTriggered: root.wanted = "" }

  readonly property var tempGroups: Model.groups(found ? found.temps : [], tempValues)
  readonly property var cpu: tempGroups.filter(function(g) { return g.group === "cpu" })[0] || tempGroups[0] || null
  readonly property var fans: Model.fanRows(cfg, found ? found.fans : [], fanValues, peaks)
  readonly property var barFan: Model.primaryFan(found ? found.fans : [], fanValues, peaks, tachMaxSetting)
  readonly property bool hasBarFan: showBarTach && barFan !== null
  readonly property bool showDial: hasBarFan && (tachMode === "both" || tachMode === "gauge")
  readonly property bool showRpmText: !vertical && hasBarFan && (tachMode === "both" || tachMode === "rpm")
  readonly property bool showVerticalRpm: vertical && hasBarFan && tachMode === "rpm"
  readonly property bool showTachGroup: showDial || showRpmText
  readonly property bool showBarDivider: !vertical && showDivider && showTachGroup
  readonly property string barTempText: cpu ? Model.deg(cpu.main) : ""
  readonly property string barRpmText: hasBarFan ? Model.formatBarRpm(cfg, barFan.rpm, rpmFormatSetting, showRpmUnit) : ""
  readonly property string heat: Model.level(cpu)
  readonly property string kitLevel: Model.kitLevel(heat)
  readonly property var nvidia: found ? found.gpus.filter(function(g) { return g.vendor === "nvidia" })[0] || null : null
  onShowBarTachChanged: if (showBarTach) Qt.callLater(poll)

  Kit.ThemePalette { id: themePalette }
  Kit.Look {
    id: skin
    textSize: String(root.setting("textSize", "Normal"))
    animations: Model.boolSetting(root.setting("animations", true), true)
    fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
    themeColors: themePalette.colors
  }
  readonly property color levelBase: heat === "hot" ? skin.themed("red", Color.urgent) : heat === "warm" ? skin.themed("yellow", "#d0a215") : Color.accent
  readonly property color hotRedColor: skin.themed("red", Color.urgent)
  readonly property color warmOrangeColor: skin.themed("orange", skin.themed("yellow", "#e0905c"))
  readonly property color coolGreenColor: skin.themed("green", "#66bb6a")

  function resolveTachColor(choice, fallback) {
    var key = String(choice || "auto").toLowerCase()
    if (key === "accent") return Color.accent
    if (Model.TACH_COLOR_FALLBACKS[key]) return skin.themed(key, Model.TACH_COLOR_FALLBACKS[key])
    if (/^#([0-9a-f]{3}|[0-9a-f]{6})$/i.test(key)) return Qt.color(key)
    return fallback
  }

  function tachSwatchColor(name) {
    if (name === "auto") return skin.ink
    if (name === "thermal") return warmOrangeColor
    return resolveTachColor(name, skin.ink)
  }

  function colorLabelKey(name) {
    return "col" + name.charAt(0).toUpperCase() + name.slice(1)
  }

  function displayLabelKey(mode) {
    return "disp" + mode.charAt(0).toUpperCase() + mode.slice(1)
  }

  function formatLabelKey(fmt) {
    return "fmt" + fmt.charAt(0).toUpperCase() + fmt.slice(1)
  }

  function barSummaryText() {
    var parts = [tr(displayLabelKey(tachMode))]
    if (tachMode === "both" || tachMode === "gauge") {
      var col = tachColorSetting.toLowerCase()
      parts.push(Model.TACH_COLOR_NAMES.indexOf(col) >= 0 ? tr(colorLabelKey(col)) : tachColorSetting)
    }
    if (tachMode === "both" || tachMode === "rpm") {
      parts.push(tr(formatLabelKey(rpmFormatSetting)))
      if (showRpmUnit) parts.push(tr("rpm", { n: "" }).trim())
    }
    return parts.join(" · ")
  }

  TextMetrics { id: valueMetrics; font.family: skin.fontFamily; font.pixelSize: skin.small; text: "0000 " + root.tr("rpm", { n: "" }) }

  // ---------- finding the sensors ----------
  Process {
    id: discoverProc
    command: ["python3", "-I", root.localPath(Qt.resolvedUrl("discover.py"))]
    running: true
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        // Same answer as before: keep the sensor files as they are.
        if (text === root.foundRaw) return
        var d = Model.parseDiscovery(text)
        if (d) { root.foundRaw = text; root.found = d; root.readProfiles(); Qt.callLater(root.poll) }
      }
    }
  }

  // One FileView per sensor file, re-read in place.
  Instantiator {
    id: fanFiles
    model: root.found ? root.found.fans : []
    delegate: FileView { required property var modelData; path: modelData.path; blockLoading: true }
  }
  Instantiator {
    id: tempFiles
    model: root.found ? root.found.temps : []
    delegate: FileView { required property var modelData; path: modelData.path; blockLoading: true }
  }
  FileView { id: gpuRuntimeFile; path: root.nvidia ? root.nvidia.runtime : ""; blockLoading: true }
  // The mode in force and the full-speed switch: readable by anyone, so the
  // popup always shows what is true, whoever changed it.
  FileView { id: platformFile; path: root.found && root.found.platform ? root.found.platform : ""; blockLoading: true }
  // Written by the helper while Max is on, whatever the hardware.
  FileView { id: pwmFile; path: root.found && root.found.maxFan ? "/run/ismoil-fans/max" : ""; blockLoading: true; printErrors: false }
  FileView { id: loadFile; path: "/proc/loadavg"; blockLoading: true }
  FileView { id: helperFile; path: "/usr/local/libexec/ismoil-fans-max"; blockLoading: true; printErrors: false }
  FileView { id: onlineFile; path: "/sys/devices/system/cpu/online"; blockLoading: true; onLoaded: root.cpus = Model.cpuCount(text()) }

  // Re-reads the files `wanted(i)` picks; the others keep their last value.
  function readSome(inst, last, wanted) {
    var out = []
    for (var i = 0; i < inst.count; i++) {
      var f = inst.objectAt(i)
      if (!f || !wanted(i)) { out.push(last[i] === undefined ? null : last[i]); continue }
      f.reload()
      out.push(Model.reading(f.text()))
    }
    return out
  }

  // Closed, the bar needs the processor only: fan, SSD and board sensors are
  // slow to read (milliseconds each, on the GUI thread) and wait for the popup.
  function poll() {
    if (!found) return
    var busy = opened || wanted !== "" || !polledOnce
    polledOnce = true
    var temps = found.temps
    tempValues = readSome(tempFiles, tempValues, function(i) { return busy || temps[i].group === "cpu" })
    if (busy || showBarTach) {
      fanValues = readSome(fanFiles, fanValues, function() { return true })
      var p = Object.assign({}, peaks)
      var changed = false
      for (var i = 0; i < found.fans.length; i++) {
        var v = fanValues[i]
        if (Model.validRpm(v) && v > (p[found.fans[i].path] || 0)) { p[found.fans[i].path] = v; changed = true }
      }
      if (changed) peaks = p
    }
    if (busy && pwmFile.path !== "") { pwmFile.reload(); pwmText = pwmFile.text() }
    // The mode in force and the load matter while Auto decides, or while seen.
    if (busy || modeSetting === "auto") {
      if (platformFile.path !== "") { platformFile.reload(); platformText = platformFile.text() }
      loadFile.reload()
      load = parseFloat(loadFile.text()) || 0
    }
    if (maxAfterInstall) {
      helperFile.reload()
      helperText = helperFile.text()
      if (helperOk) { maxAfterInstall = false; chooseMode("max") }
    }
    autoStep()
  }

  // Auto: quiet while the computer rests, medium while it works, never the
  // loudest; a change only after its reason held for 20 s.
  function autoStep() {
    if (selected !== "auto" || setProc.running) { pending = ""; return }
    var target = Model.autoTarget(cpu ? cpu.main : null, load, cpus, profiles.available)
    if (!target || target === active) { pending = ""; return }
    if (pending !== target) { pending = target; pendingSince = Date.now(); return }
    if (Date.now() - pendingSince >= autoHold) { pending = ""; setProfile(target) }
  }

  function saveSetting(key, value) {
    var patch = {}
    patch[key] = value
    settings = Object.assign({}, settings, patch)
    if (bar && bar.shell && typeof bar.shell.updateEntryInline === "function")
      bar.shell.updateEntryInline(moduleName, settings)
  }

  function saveMode(value) { saveSetting("mode", value) }

  // A button: Auto, a profile of this machine, or Max.
  function chooseMode(m) {
    if (modes.indexOf(m) < 0) return
    if (m !== "max") maxAfterInstall = false
    if (m === "max") {
      helperFile.reload()
      helperText = helperFile.text()
      if (!helperOk) { maxAfterInstall = true; wanted = "max"; installHelper(); return }
      wanted = "max"; wantedReset.restart()
      saveMode("manual")
      runHelper("max")
      if (profiles.available.indexOf("performance") >= 0) setProfile("performance")
      return
    }
    if (maxOn) runHelper("auto")
    wanted = m; wantedReset.restart()
    if (m === "auto") { saveMode("auto"); pending = ""; Qt.callLater(poll); return }
    saveMode("manual")
    setProfile(m)
  }

  property string helperArg: ""
  function runHelper(arg) {
    if (helperProc.running) return
    helperArg = arg
    helperProc.command = ["pkexec", "/usr/local/libexec/ismoil-fans-max", arg]
    helperProc.running = true
  }

  Process {
    id: helperProc
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: if (text.trim() !== "") console.warn("ismoil.fans: helper:", text.trim()) }
    onExited: function(code) {
      // Max was clicked and the helper failed (an old one without the polkit
      // rule): put the current one in place once, then Max turns on. A failed
      // "auto" only logs: nothing is installed without a click on Max.
      if (code !== 0) {
        root.wanted = ""
        if (root.helperArg === "max" && root.helperFailed !== root.helperText) {
          root.helperFailed = root.helperText
          root.maxAfterInstall = true
          root.wanted = "max"
          root.installHelper()
        }
      }
      root.poll()
    }
  }

  function installHelper() {
    // No shell parses this argv; the launcher gives its one argument to bash -c: quoted for that.
    Util.execArgv(["omarchy-launch-floating-terminal-with-presentation", Model.shellQuote(root.localPath(Qt.resolvedUrl("helper/install.sh")))])
  }

  // The discrete GPU only while open, and only when it is awake: asking a
  // sleeping one wakes it, and it then drains the battery.
  function readGpu() {
    gpuRuntimeFile.reload()
    gpuAsleep = gpuRuntimeFile.text().trim() === "suspended"
    if (gpuAsleep || gpuProc.running) return
    gpuProc.running = true
  }

  Process {
    id: gpuProc
    command: ["nvidia-smi", "--query-gpu=temperature.gpu", "--format=csv,noheader,nounits"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: { var n = parseInt(text, 10); root.gpuTemp = isFinite(n) ? n : -1 }
    }
  }

  // ---------- power mode ----------
  function readProfiles() {
    if (!profilesProc.running) profilesProc.running = true
  }

  Process {
    id: profilesProc
    command: ["powerprofilesctl", "list"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.profiles = Model.parseProfiles(text) }
  }

  // powerprofilesctl says itself whether the mode exists: an instance that
  // never opened (the bar on another monitor) has no list yet and must still work.
  property string queued: ""
  function setProfile(name) {
    if (profiles.available.length > 0 && profiles.available.indexOf(name) < 0) return
    profiles = Object.assign({}, profiles, { active: name })
    // One at a time: the last choice made meanwhile runs next.
    if (setProc.running) { queued = name; return }
    setProc.command = ["powerprofilesctl", "set", name]
    setProc.running = true
  }

  // Right click: the next mode, Max left out (it may ask for a password).
  function nextProfile() {
    var list = modes.filter(function(m) { return m !== "max" })
    if (list.length === 0) return
    chooseMode(list[(list.indexOf(selected) + 1) % list.length])
  }

  Process {
    id: setProc
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: if (text.trim() !== "") console.warn("ismoil.fans: powerprofilesctl:", text.trim()) }
    onExited: function(code) {
      if (code !== 0) { console.warn("ismoil.fans: powerprofilesctl set failed", code); root.wanted = "" }
      if (root.queued !== "") { var next = root.queued; root.queued = ""; root.setProfile(next) }
      else if (root.opened) root.readProfiles()
    }
  }

  // ---------- timers ----------
  Timer {
    // Fast for the moment a click waits for the system; not while an installer is open.
    interval: root.wanted !== "" && !root.maxAfterInstall ? 500 : root.opened ? Math.min(2000, root.pollSeconds * 1000) : root.pollSeconds * 1000
    running: root.found !== null
    repeat: true
    onTriggered: root.poll()
  }

  Timer {
    interval: 5000
    running: root.opened && root.nvidia !== null
    repeat: true
    triggeredOnStart: true
    onTriggered: root.readGpu()
  }

  onOpenedChanged: {
    if (!opened) return
    discoverProc.running = true
    readProfiles()
    poll()
  }

  IpcHandler {
    target: "ismoil.fans"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function mode(name: string): void { root.chooseMode(name) }
    function nextMode(): void { root.nextProfile() }
    // What the widget sees, for checking it without opening the popup.
    function state(): string {
      return JSON.stringify({ modes: root.modes, selected: root.selected, active: root.active, maxOn: root.maxOn,
                              mode: root.modeSetting, cpu: root.cpu ? Math.round(root.cpu.main) : null, load: root.load, cpus: root.cpus,
                              fans: root.fans.map(function(f) { return { label: f.label, rpm: f.rpm, max: f.max } }),
                              barFan: root.barFan })
    }
  }

  // ---------- bar ----------
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  FontMetrics {
    id: barFontMetrics
    font.family: button.fontFamily
    font.pixelSize: button.fontSize
  }

  TextMetrics {
    id: barTempMetrics
    font.family: button.fontFamily
    font.pixelSize: button.fontSize
    font.features: { "tnum": 1 }
    text: root.barTempText
  }

  TextMetrics {
    id: barRpmMetrics
    font.family: button.fontFamily
    font.pixelSize: button.fontSize
    font.features: { "tnum": 1 }
    text: root.barRpmText
  }

  readonly property real barTextOffsetY: (barFontMetrics.descent - barFontMetrics.ascent + barFontMetrics.tightBoundingRect("0").height) / 2
  readonly property real tachSize: Math.min(Math.max(Style.bar.iconCanvas, Math.round(Style.bar.iconCanvas * 1.125)), Math.max(Style.bar.iconCanvas, root.barSize - Style.space(6)))
  readonly property real tempGroupWidth: Style.bar.iconCanvas + (root.barTempText !== "" ? Style.space(4) + barTempMetrics.width : 0)
  readonly property real tachGroupWidth: (root.showDial ? root.tachSize : 0)
    + (root.showDial && root.showRpmText ? Style.space(4) : 0)
    + (root.showRpmText ? barRpmMetrics.width : 0)
  readonly property real barGapWidth: root.showTachGroup ? (root.showBarDivider ? Style.space(12) + 1 : Style.space(8)) : 0
  readonly property string barVerticalRpmText: root.showVerticalRpm && root.barFan ? Model.formatRpmNumber(root.barFan.rpm, "compact") : ""
  readonly property string tachColorKey: root.tachColorSetting.toLowerCase()
  readonly property bool tachUsesRedline: tachColorKey === "auto" || tachColorKey === "thermal"
  readonly property color tachActiveColor: {
    if (tachColorKey === "auto") return button.foreground
    if (tachColorKey === "thermal") {
      var frac = root.barFan ? root.barFan.fraction : 0
      return frac >= 0.85 ? root.hotRedColor : frac >= 0.5 ? root.warmOrangeColor : root.coolGreenColor
    }
    return root.resolveTachColor(root.tachColorSetting, button.foreground)
  }
  property color tempColor: root.heat !== "calm" ? root.levelBase : button.foreground
  Behavior on tempColor {
    enabled: !root.bar || root.bar.foregroundAnimationEnabled
    ColorAnimation { duration: Style.duration(160) }
  }

  TextMetrics {
    id: verticalRpmMetrics
    font.family: button.fontFamily
    font.pixelSize: Style.font.caption
    text: root.barVerticalRpmText
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: true
    fontSize: Style.bar.iconFont
    active: root.heat !== "calm"
    activeColor: root.levelBase
    fixedWidth: root.vertical ? -1 : Math.ceil(barContent.width) + Style.space(14)
    fixedHeight: root.vertical
      ? (root.showDial ? Math.ceil(Style.bar.iconCanvas + root.tachSize + Style.space(4)) + Style.space(12)
         : root.showVerticalRpm ? Math.ceil(Style.bar.iconCanvas + verticalRpmMetrics.height + Style.space(2)) + Style.space(12)
         : Style.bar.iconSlot)
      : -1
    tooltipText: root.opened ? "" : Model.tooltip(root.cfg, root.cpu, root.hasBarFan ? root.barFan : null)
    onPressed: function(b) {
      if (b === Qt.RightButton) { root.readProfiles(); root.nextProfile() }
      else root.toggle()
    }

    Item {
      id: barContent
      x: (button.width - width) / 2
      y: (button.height - height) / 2
      scale: button.pressScale
      width: root.vertical
        ? Math.max(Style.bar.iconCanvas, root.showDial ? root.tachSize : verticalRpmMetrics.width)
        : (root.tempGroupWidth + root.barGapWidth + root.tachGroupWidth)
      height: root.vertical
        ? (Style.bar.iconCanvas
           + (root.showDial ? Style.space(4) + root.tachSize
              : root.showVerticalRpm ? Style.space(2) + verticalRpmMetrics.height : 0))
        : Math.max(Style.bar.iconCanvas, root.showDial ? root.tachSize : 0)

      // Horizontal bar: [fan icon] [temp°]  |  [tachometer dial] [rpm]
      Row {
        visible: !root.vertical
        anchors.centerIn: parent
        height: barContent.height
        spacing: root.showBarDivider ? Style.space(6) : Style.space(8)

        Row {
          height: barContent.height
          spacing: Style.space(4)

          OpticalGlyph {
            width: Style.bar.iconCanvas
            height: barContent.height
            text: root.icon
            fontFamily: button.fontFamily
            fontSize: button.fontSize
            paintedSize: Style.bar.iconSize
            color: root.tempColor
          }

          Item {
            visible: root.barTempText !== ""
            width: barTempMetrics.width
            height: barContent.height

            Text {
              anchors.verticalCenter: parent.verticalCenter
              anchors.verticalCenterOffset: root.barTextOffsetY
              textFormat: Text.PlainText
              text: root.barTempText
              font.family: button.fontFamily
              font.pixelSize: button.fontSize
              font.features: { "tnum": 1 }
              color: root.tempColor
              renderType: Text.NativeRendering
            }
          }
        }

        Rectangle {
          visible: root.showBarDivider
          width: 1
          height: Style.bar.iconSize
          anchors.verticalCenter: parent.verticalCenter
          color: Util.alpha(button.foreground, 0.22)
        }

        Row {
          visible: root.showTachGroup
          height: barContent.height
          spacing: Style.space(4)

          Tachometer {
            visible: root.showDial
            width: root.tachSize
            height: root.tachSize
            anchors.verticalCenter: parent.verticalCenter
            fraction: root.barFan ? root.barFan.fraction : 0
            showRedline: root.tachUsesRedline
            color: root.tachActiveColor
            trackColor: Util.alpha(button.foreground, 0.24)
            accentColor: root.tachActiveColor
            dangerColor: root.hotRedColor
            animations: skin.motion
          }

          Item {
            visible: root.showRpmText
            width: barRpmMetrics.width
            height: barContent.height

            Text {
              anchors.verticalCenter: parent.verticalCenter
              anchors.verticalCenterOffset: root.barTextOffsetY
              textFormat: Text.PlainText
              text: root.barRpmText
              font.family: button.fontFamily
              font.pixelSize: button.fontSize
              font.features: { "tnum": 1 }
              color: button.foreground
              renderType: Text.NativeRendering
              Behavior on color {
                enabled: !root.bar || root.bar.foregroundAnimationEnabled
                ColorAnimation { duration: Style.duration(160) }
              }
            }
          }
        }
      }

      // Vertical bar: [fan icon] over [tachometer dial or compact rpm]
      Column {
        visible: root.vertical
        anchors.centerIn: parent
        spacing: root.showDial ? Style.space(4) : Style.space(2)

        OpticalGlyph {
          anchors.horizontalCenter: parent.horizontalCenter
          width: Style.bar.iconCanvas
          height: Style.bar.iconCanvas
          text: root.icon
          fontFamily: button.fontFamily
          fontSize: button.fontSize
          paintedSize: Style.bar.iconSize
          color: root.tempColor
        }

        Tachometer {
          visible: root.showDial
          anchors.horizontalCenter: parent.horizontalCenter
          width: root.tachSize
          height: root.tachSize
          fraction: root.barFan ? root.barFan.fraction : 0
          showRedline: root.tachUsesRedline
          color: root.tachActiveColor
          trackColor: Util.alpha(button.foreground, 0.24)
          accentColor: root.tachActiveColor
          dangerColor: root.hotRedColor
          animations: skin.motion
        }

        Text {
          visible: root.showVerticalRpm
          anchors.horizontalCenter: parent.horizontalCenter
          textFormat: Text.PlainText
          text: root.barVerticalRpmText
          font.family: button.fontFamily
          font.pixelSize: Style.font.caption
          font.features: { "tnum": 1 }
          color: button.foreground
          renderType: Text.NativeRendering
        }
      }
    }
  }

  // ---------- popup ----------
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Math.round(Style.space(380) * skin.textScale))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight + skin.bottomPad)

    // Built the first time the popup opens, not at shell start on every monitor.
    content: Component {
      PanelKeyCatcher {
        id: keyCatcher
        anchors.fill: parent
        implicitHeight: column.implicitHeight
        onCloseRequested: root.close()
        onTabRequested: function(direction) { root.switchPanel(direction) }
        onTextKey: function(t) {
          t = I18n.latinKey(t)
          if (t === "r") discoverProc.running = true
          else if (t >= "1" && t <= "9" && Number(t) <= root.modes.length) root.chooseMode(root.modes[Number(t) - 1])
        }

        Flickable {
          id: scroller
          anchors.fill: parent
          contentWidth: width
          contentHeight: column.implicitHeight + skin.bottomPad
          interactive: contentHeight > height
          boundsBehavior: Flickable.StopAtBounds
          clip: true

          Column {
            id: column
            width: scroller.width
            spacing: Style.space(12)

            Kit.Header {
              width: parent.width
              look: skin
              glyph: root.icon
              name: root.tr("title")
              value: root.cpu ? Model.deg(root.cpu.main) : "—"
              say: !root.found ? root.tr("reading") : Model.headerSay(root.cfg, root.fans)
              chip: root.cpu ? root.tr(root.heat) : ""
              tone: skin.levelFill(root.kitLevel)
              toneText: skin.levelText(root.kitLevel)
            }

            // ---------- Fans ----------
            Kit.Section {
              id: fanList
              visible: root.found !== null
              width: parent.width
              look: skin
              caption: root.tr("sectionFans")

              Text {
                visible: root.fans.length === 0
                width: parent.width
                textFormat: Text.PlainText
                text: root.tr("noFans")
                color: skin.dim
                font.family: skin.fontFamily
                font.pixelSize: skin.small
                wrapMode: Text.WordWrap
              }

              Repeater {
                model: root.fans.length  // a count: rows stay, only their numbers change, so the icon keeps spinning

                delegate: Item {
                  required property int index
                  readonly property var fan: root.fans[index] || ({ label: "", rpm: 0, text: "", fraction: 0 })
                  width: fanList.width - fanList.padding * 2
                  implicitHeight: fanLine.implicitHeight + Style.space(10)

                  Row {
                    id: fanLine
                    width: parent.width
                    spacing: Style.space(10)
                    anchors.verticalCenter: parent.verticalCenter

                    // Spins at a pace that follows the speed, only while it is seen.
                    Kit.Glyph {
                      id: blade
                      // Centred on its ink, so it spins in place instead of wobbling.
                      width: 2 * Math.round(skin.strong * 0.7)
                      height: width
                      text: root.icon
                      color: skin.accentText
                      fontFamily: skin.fontFamily
                      pixelSize: 2 * Math.round(skin.strong / 2)
                      anchors.verticalCenter: parent.verticalCenter
                      RotationAnimator on rotation {
                        running: root.opened && skin.motion && fan.rpm > 0
                        from: 0; to: 360; loops: Animation.Infinite
                        duration: Math.max(350, Math.min(3000, 3000000 / Math.max(1, fan.rpm)))
                      }
                    }

                    Column {
                      width: parent.width - blade.width - fanValue.width - parent.spacing * 2
                      spacing: Style.space(4)
                      anchors.verticalCenter: parent.verticalCenter

                      Text {
                        textFormat: Text.PlainText
                        text: fan.label
                        color: skin.ink
                        font.family: skin.fontFamily
                        font.pixelSize: skin.small
                      }
                      Kit.Meter { width: parent.width; look: skin; fraction: fan.fraction }
                    }

                    Text {
                      id: fanValue
                      width: valueMetrics.width
                      horizontalAlignment: Text.AlignRight
                      anchors.verticalCenter: parent.verticalCenter
                      textFormat: Text.PlainText
                      text: fan.text
                      color: skin.ink
                      font.family: skin.fontFamily
                      font.pixelSize: skin.small
                      font.bold: true
                      font.features: { "tnum": 1 }
                    }
                  }
                }
              }
            }

            // ---------- Temperatures ----------
            Kit.Section {
              id: tempList
              visible: root.found !== null
              width: parent.width
              look: skin
              caption: root.tr("sectionTemps")
              spacing: Style.spacing.labelGap

              Text {
                visible: root.tempGroups.length === 0 && !root.nvidia
                textFormat: Text.PlainText
                text: root.tr("noSensors")
                color: skin.dim
                font.family: skin.fontFamily
                font.pixelSize: skin.small
              }

              Repeater {
                model: root.tempGroups
                delegate: Kit.InfoPair {
                  required property var modelData
                  look: skin
                  label: Model.groupLabel(root.cfg, modelData.group)
                         + (modelData.group === "cpu" && modelData.hottest > modelData.main + 1 ? " · " + root.tr("hottest", { t: Model.deg(modelData.hottest) }) : "")
                  value: Model.deg(modelData.main)
                  valueColor: modelData.group === "cpu" ? skin.levelText(root.kitLevel) : skin.ink
                }
              }

              Kit.InfoPair {
                visible: root.nvidia !== null && (root.gpuAsleep || root.gpuTemp >= 0)
                look: skin
                label: root.tr("groupGpu") + " · NVIDIA"
                value: root.gpuAsleep ? root.tr("gpuAsleep") : Model.deg(root.gpuTemp)
                valueColor: root.gpuAsleep ? skin.dim : skin.ink
              }
            }

            // ---------- Mode: whatever this computer offers ----------
            Kit.Section {
              visible: root.found !== null
              width: parent.width
              look: skin
              caption: root.tr("sectionMode")
              hint: root.modes.length > 0 ? root.tr("modeHint") : ""

              Text {
                visible: root.modes.length === 0
                width: parent.width
                textFormat: Text.PlainText
                text: root.tr("noModes")
                color: skin.dim
                font.family: skin.fontFamily
                font.pixelSize: skin.small
                wrapMode: Text.WordWrap
              }

              Flow {
                visible: root.modes.length > 0
                width: parent.width
                spacing: Style.space(6)

                Repeater {
                  model: root.modes
                  delegate: Kit.ActionButton {
                    required property var modelData
                    look: skin
                    compact: true
                    text: Model.modeLabel(root.cfg, modelData)
                    selected: root.selected === modelData
                    danger: modelData === "max" && root.maxOn
                    onClicked: root.chooseMode(modelData)
                  }
                }
              }

              Text {
                visible: text !== ""
                width: parent.width
                textFormat: Text.PlainText
                text: root.maxOn ? root.tr("maxNow")
                    : root.selected === "auto" && root.active !== "" ? root.tr("autoNow", { mode: Model.modeLabel(root.cfg, root.active).toLowerCase() }) : ""
                color: root.maxOn ? skin.badText : skin.dim
                font.family: skin.fontFamily
                font.pixelSize: skin.small
                wrapMode: Text.WordWrap
              }

              Text {
                visible: root.maxAfterInstall
                width: parent.width
                textFormat: Text.PlainText
                text: root.tr("installing")
                color: skin.warnText
                font.family: skin.fontFamily
                font.pixelSize: skin.small
                wrapMode: Text.WordWrap
              }
            }

            // ---------- Bar customization ----------
            Kit.Section {
              visible: root.found !== null
              width: parent.width
              look: skin
              caption: root.tr("sectionBar")
              trailing: Kit.MoreButton {
                look: skin
                text: root.barCustomizeOpen ? root.tr("collapse") : root.tr("customize")
                onClicked: root.barCustomizeOpen = !root.barCustomizeOpen
              }

              Text {
                visible: !root.barCustomizeOpen
                width: parent.width
                textFormat: Text.PlainText
                text: root.barSummaryText()
                color: skin.dim
                font.family: skin.fontFamily
                font.pixelSize: skin.small
                elide: Text.ElideRight
              }

              Column {
                visible: root.barCustomizeOpen
                width: parent.width
                spacing: Style.space(8)

                // Display mode
                Column {
                  width: parent.width
                  spacing: Style.space(4)

                  Text {
                    textFormat: Text.PlainText
                    text: root.tr("optDisplay")
                    color: skin.dim
                    font.family: skin.fontFamily
                    font.pixelSize: skin.small
                  }

                  Flow {
                    width: parent.width
                    spacing: Style.space(6)

                    Repeater {
                      model: Model.TACH_MODES
                      delegate: Kit.ActionButton {
                        required property string modelData
                        look: skin
                        compact: true
                        text: root.tr(root.displayLabelKey(modelData))
                        selected: root.tachMode === modelData
                        onClicked: root.saveSetting("tachometer", modelData)
                      }
                    }
                  }
                }

                // Tachometer color
                Column {
                  visible: root.tachMode === "both" || root.tachMode === "gauge"
                  width: parent.width
                  spacing: Style.space(4)

                  Text {
                    textFormat: Text.PlainText
                    text: root.tr("optColor")
                    color: skin.dim
                    font.family: skin.fontFamily
                    font.pixelSize: skin.small
                  }

                  Flow {
                    width: parent.width
                    spacing: Style.space(6)

                    Repeater {
                      model: Model.TACH_COLOR_NAMES
                      delegate: Rectangle {
                        id: swatchBtn
                        required property string modelData
                        readonly property bool isSelected: root.tachColorKey === modelData
                        readonly property color swatch: root.tachSwatchColor(modelData)

                        implicitWidth: swatchRow.implicitWidth + Style.space(14)
                        implicitHeight: swatchRow.implicitHeight + Style.space(4)
                        radius: Math.round(Style.space(6))
                        color: swatchArea.containsMouse && !isSelected ? skin.surfaceHover : (isSelected ? skin.ink : "transparent")
                        border.width: 1.5
                        border.color: isSelected ? skin.ink : Util.alpha(skin.ink, 0.75)

                        Behavior on color { ColorAnimation { duration: skin.motion ? Style.duration(120) : 0 } }

                        Row {
                          id: swatchRow
                          anchors.centerIn: parent
                          spacing: Style.space(5)

                          Rectangle {
                            width: Style.space(8)
                            height: width
                            radius: width / 2
                            anchors.verticalCenter: parent.verticalCenter
                            color: swatchBtn.swatch
                            border.width: swatchBtn.isSelected ? 1 : 0
                            border.color: swatchBtn.isSelected ? skin.background : "transparent"
                          }

                          Text {
                            anchors.verticalCenter: parent.verticalCenter
                            textFormat: Text.PlainText
                            text: root.tr(root.colorLabelKey(swatchBtn.modelData))
                            color: swatchBtn.isSelected ? skin.background : skin.ink
                            font.family: skin.fontFamily
                            font.pixelSize: skin.small
                            font.bold: true
                          }
                        }

                        MouseArea {
                          id: swatchArea
                          anchors.fill: parent
                          hoverEnabled: true
                          cursorShape: Qt.PointingHandCursor
                          onClicked: root.saveSetting("tachColor", swatchBtn.modelData)
                        }
                      }
                    }
                  }
                }

                // Number length
                Column {
                  visible: root.tachMode === "both" || root.tachMode === "rpm"
                  width: parent.width
                  spacing: Style.space(4)

                  Text {
                    textFormat: Text.PlainText
                    text: root.tr("optFormat")
                    color: skin.dim
                    font.family: skin.fontFamily
                    font.pixelSize: skin.small
                  }

                  Flow {
                    width: parent.width
                    spacing: Style.space(6)

                    Repeater {
                      model: Model.RPM_FORMATS
                      delegate: Kit.ActionButton {
                        required property string modelData
                        look: skin
                        compact: true
                        text: root.tr(root.formatLabelKey(modelData))
                        selected: root.rpmFormatSetting === modelData
                        onClicked: root.saveSetting("rpmFormat", modelData)
                      }
                    }
                  }
                }

                // Toggles: RPM word + bar divider
                Column {
                  visible: root.tachMode !== "off"
                  width: parent.width
                  spacing: Style.space(4)

                  Text {
                    textFormat: Text.PlainText
                    text: root.tr("optDetails")
                    color: skin.dim
                    font.family: skin.fontFamily
                    font.pixelSize: skin.small
                  }

                  Flow {
                    width: parent.width
                    spacing: Style.space(6)

                    Kit.ActionButton {
                      visible: root.tachMode === "both" || root.tachMode === "rpm"
                      look: skin
                      compact: true
                      text: root.tr("optRpmWord")
                      selected: root.showRpmUnit
                      onClicked: root.saveSetting("rpmUnit", !root.showRpmUnit)
                    }

                    Kit.ActionButton {
                      look: skin
                      compact: true
                      text: root.tr("optDivider")
                      selected: root.showDivider
                      onClicked: root.saveSetting("barDivider", !root.showDivider)
                    }
                  }
                }

                // Dial scale (max RPM)
                Column {
                  visible: root.tachMode === "both" || root.tachMode === "gauge"
                  width: parent.width
                  spacing: Style.space(4)

                  Text {
                    textFormat: Text.PlainText
                    text: root.tr("optScale")
                    color: skin.dim
                    font.family: skin.fontFamily
                    font.pixelSize: skin.small
                  }

                  Flow {
                    width: parent.width
                    spacing: Style.space(6)

                    Repeater {
                      model: Model.TACH_SCALES
                      delegate: Kit.ActionButton {
                        required property int modelData
                        look: skin
                        compact: true
                        text: modelData === 0 ? root.tr("scaleAuto") : String(modelData)
                        selected: root.tachMaxSetting === modelData
                        onClicked: root.saveSetting("tachMax", modelData)
                      }
                    }
                  }
                }
              }
            }

            Kit.Signature {
              width: parent.width
              look: skin
              widget: "cooling"
              extra: root.found ? root.tr("sensors").toLowerCase() + " " + (root.found.fans.length + root.found.temps.length) : ""
              version: root.version
            }
          }
        }
      }
    }
  }
}
