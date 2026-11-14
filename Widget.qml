import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "kit" as Kit
import "Model.js" as Model

// Cooling widget: the processor's temperature in the bar, coloured as it
// heats; the popup lists every fan with its speed, the temperatures by group
// (processor, graphics, SSD, board) and the power mode (power-profiles-daemon,
// no root). Works with whatever hwmon reports; says so when there is no fan.
//
// Cost: discover.py runs once (and when the popup opens); then the sensor
// files are re-read in place every `interval` seconds, no process. A discrete
// GPU is read only while the popup is open, and never woken up from sleep.
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
  readonly property string icon: "󰈐"

  function tr(key, params) { return Model.tr(cfg, key, params) }
  function localPath(url) { return decodeURIComponent(String(url).replace(/^file:\/\//, "")) }

  FileView { id: manifestFile; path: root.localPath(Qt.resolvedUrl("manifest.json")); blockLoading: true }
  readonly property string version: { try { return JSON.parse(manifestFile.text()).version || "" } catch (e) { return "" } }

  // ---------- state ----------
  property var found: null
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
  property bool showInstall: false
  property bool helperBroken: false
  readonly property bool maxOn: pwmText.trim() === "0"
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
  readonly property string heat: Model.level(cpu)
  readonly property string kitLevel: Model.kitLevel(heat)
  readonly property var nvidia: found ? found.gpus.filter(function(g) { return g.vendor === "nvidia" })[0] || null : null

  Kit.ThemePalette { id: themePalette }
  Kit.Look {
    id: skin
    textSize: String(root.setting("textSize", "Normal"))
    animations: root.setting("animations", true) !== false
    fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
    themeColors: themePalette.colors
  }
  readonly property color levelBase: heat === "hot" ? skin.themed("red", Color.urgent) : heat === "warm" ? skin.themed("yellow", "#d0a215") : Color.accent

  TextMetrics { id: valueMetrics; font.family: skin.fontFamily; font.pixelSize: skin.small; text: "0000 " + root.tr("rpm", { n: "" }) }

  // ---------- finding the sensors ----------
  Process {
    id: discoverProc
    command: ["python3", "-I", root.localPath(Qt.resolvedUrl("discover.py"))]
    running: true
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var d = Model.parseDiscovery(text)
        if (d) { root.found = d; root.readProfiles(); Qt.callLater(root.poll) }
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
  FileView { id: pwmFile; path: root.found && root.found.maxFan ? root.found.maxFan : ""; blockLoading: true }
  FileView { id: loadFile; path: "/proc/loadavg"; blockLoading: true }
  FileView { id: onlineFile; path: "/sys/devices/system/cpu/online"; blockLoading: true; onLoaded: root.cpus = Model.cpuCount(text()) }

  function readAll(inst) {
    var out = []
    for (var i = 0; i < inst.count; i++) {
      var f = inst.objectAt(i)
      if (!f) { out.push(null); continue }
      f.reload()
      out.push(Model.reading(f.text()))
    }
    return out
  }

  function poll() {
    if (!found) return
    fanValues = readAll(fanFiles)
    tempValues = readAll(tempFiles)
    var p = Object.assign({}, peaks)
    var changed = false
    for (var i = 0; i < found.fans.length; i++) {
      var v = fanValues[i]
      if (v !== null && v > (p[found.fans[i].path] || 0)) { p[found.fans[i].path] = v; changed = true }
    }
    if (changed) peaks = p
    if (platformFile.path !== "") { platformFile.reload(); platformText = platformFile.text() }
    if (pwmFile.path !== "") { pwmFile.reload(); pwmText = pwmFile.text() }
    loadFile.reload()
    load = parseFloat(loadFile.text()) || 0
    if (opened && nvidia) readGpu()
    autoStep()
  }

  // Auto: quiet while the computer rests, medium while it works, never the
  // loudest; a change only after its reason held for 20 s.
  function autoStep() {
    if (selected !== "auto" || setProc.running) { pending = ""; return }
    var target = Model.autoTarget(cpu ? cpu.main : null, load, cpus, profiles.available)
    if (!target || target === active) { pending = ""; return }
    if (pending !== target) { pending = target; pendingSince = Date.now(); return }
    if (Date.now() - pendingSince >= 20000) { pending = ""; setProfile(target) }
  }

  function saveMode(value) {
    settings = Object.assign({}, settings, { mode: value })
    if (bar && bar.shell && typeof bar.shell.updateEntryInline === "function")
      bar.shell.updateEntryInline(moduleName, settings)
  }

  // A button: Auto, a profile of this machine, or Max.
  function chooseMode(m) {
    console.log("ismoil.fans: clicked", m, "helper", !!(found && found.helper))
    showInstall = false
    if (m === "max") {
      if (!found || !found.helper) { showInstall = true; return }
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

  function runHelper(arg) {
    if (helperProc.running) return
    helperProc.command = ["pkexec", "/usr/local/libexec/ismoil-fans-max", arg]
    helperProc.running = true
  }

  Process {
    id: helperProc
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: if (text.trim() !== "") console.warn("ismoil.fans: helper:", text.trim()) }
    // Without an agent in reach polkit cannot ask: the rule from helper/install.sh is missing.
    onExited: function(code) {
      if (code !== 0) { root.wanted = ""; root.helperBroken = true; root.showInstall = true }
      root.poll()
    }
  }

  function installHelper() {
    showInstall = false
    close()
    if (bar) bar.run("omarchy-launch-floating-terminal-with-presentation " + Model.shellQuote(root.localPath(Qt.resolvedUrl("helper/install.sh"))))
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
  function setProfile(name) {
    if (profiles.available.length > 0 && profiles.available.indexOf(name) < 0) return
    profiles = Object.assign({}, profiles, { active: name })
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
      if (code !== 0) console.warn("ismoil.fans: powerprofilesctl set failed", code)
      if (code !== 0) root.wanted = ""
      root.readProfiles()
    }
  }

  // ---------- timers ----------
  Timer {
    interval: root.wanted !== "" ? 500 : root.opened ? Math.min(2000, root.pollSeconds * 1000) : root.pollSeconds * 1000
    running: root.found !== null
    repeat: true
    onTriggered: root.poll()
  }

  Timer {
    interval: 5000
    running: root.opened && root.nvidia !== null
    repeat: true
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
                              mode: root.modeSetting, cpu: root.cpu ? Math.round(root.cpu.main) : null, load: root.load, cpus: root.cpus })
    }
  }

  // ---------- bar ----------
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  TextMetrics {
    id: barLabelMetrics
    font.family: button.fontFamily
    font.pixelSize: button.fontSize
    text: button.labelText
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.icon
    labelText: root.vertical || !root.cpu ? "" : Model.deg(root.cpu.main)
    active: root.heat !== "calm"
    activeColor: root.levelBase
    slotSize: labelText === "" ? Style.bar.iconSlot : Math.ceil(button.canvasSize + barLabelMetrics.width + Style.space(4)) + Style.space(14)
    tooltipText: root.opened ? "" : Model.tooltip(root.cfg, root.cpu, root.fans)
    onPressed: function(b) {
      if (b === Qt.RightButton) { root.readProfiles(); root.nextProfile() }
      else root.toggle()
    }
  }

  // ---------- popup ----------
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Math.round(Style.space(380) * skin.textScale))
    contentHeight: panel.fittedContentHeight(column.implicitHeight + skin.bottomPad)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
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
              model: root.fans

              delegate: Item {
                required property var modelData
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
                      running: root.opened && skin.motion && modelData.rpm > 0
                      from: 0; to: 360; loops: Animation.Infinite
                      duration: Math.max(350, Math.min(3000, 3000000 / Math.max(1, modelData.rpm)))
                    }
                  }

                  Column {
                    width: parent.width - blade.width - fanValue.width - parent.spacing * 2
                    spacing: Style.space(4)
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                      textFormat: Text.PlainText
                      text: modelData.label
                      color: skin.ink
                      font.family: skin.fontFamily
                      font.pixelSize: skin.small
                    }
                    Kit.Meter { width: parent.width; look: skin; fraction: modelData.fraction }
                  }

                  Text {
                    id: fanValue
                    width: valueMetrics.width
                    horizontalAlignment: Text.AlignRight
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    text: modelData.text
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
                  text: Model.modeLabel(root.cfg, modelData) + (modelData === "max" && !(root.found && root.found.helper) ? " 󰌾" : "")
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
              visible: root.showInstall
              width: parent.width
              textFormat: Text.PlainText
              text: root.helperBroken ? root.tr("helperUpdate") : root.tr("maxNeedsHelper")
              color: skin.ink
              font.family: skin.fontFamily
              font.pixelSize: skin.small
              wrapMode: Text.WordWrap
            }

            Kit.ActionButton {
              visible: root.showInstall
              look: skin
              primary: true
              iconText: "󰏗"
              text: root.helperBroken ? root.tr("helperUpdateButton") : root.tr("install")
              onClicked: root.installHelper()
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
