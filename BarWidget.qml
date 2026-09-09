import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root

  readonly property string folderId: String(setting("folderId", ""))
  readonly property var folderService: bar && bar.shell
    ? bar.shell.serviceFor("io.github.dlpwaters.plugin-folders") : null
  readonly property var nativeBar: findNativeBar()
  readonly property string helperPath: String(Qt.resolvedUrl("folderctl")).replace(/^file:\/\//, "")
  readonly property string stateHome: {
    var configured = Quickshell.env("XDG_STATE_HOME")
    return configured !== "" ? configured : Quickshell.env("HOME") + "/.local/state"
  }
  readonly property string stateFile: stateHome + "/omarchy-plugin-folders/state.json"
  property var folderData: ({ id: folderId, name: "Plugins", icon: "󰉋", color: "#7aa2f7", members: [] })
  property string folderOutput: ""
  property int memberRevision: 0
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened : false
  readonly property string launcherQuery: panelLoader.item
    ? String(panelLoader.item.launcherQuery || "") : ""
  readonly property int launcherVisibleCount: panelLoader.item
    ? Number(panelLoader.item.launcherVisibleCount || 0) : 0
  readonly property string launcherSelectedPluginId: panelLoader.item
    ? String(panelLoader.item.launcherSelectedPluginId || "") : ""
  readonly property bool launcherSearchFocused: panelLoader.item
    ? panelLoader.item.launcherSearchFocused === true : false

  function memberComponent(pluginId) {
    var registry = folderService ? folderService.barWidgetRegistry : null
    var widgets = registry ? registry.widgets : null
    var record = widgets ? widgets[String(pluginId)] : null
    return record ? record.component : null
  }

  function findNativeBar() {
    // Hosted widgets still belong to the real bar scene. Use its normal
    // per-widget facade factory so each member keeps its own service scope.
    var candidate = root.parent
    while (candidate) {
      if (typeof candidate.pluginBarApiFor === "function") return candidate
      candidate = candidate.parent
    }
    return null
  }

  function memberBar(pluginId) {
    return nativeBar ? nativeBar.pluginBarApiFor(pluginId, pluginId, true) : root.bar
  }

  onFolderServiceChanged: {
    if (folderService) folderService.registerFolder(root)
  }
  Component.onDestruction: {
    if (folderService) folderService.unregisterFolder(root)
  }

  function memberLoader(pluginId) {
    for (var i = 0; i < memberHosts.count; i++) {
      var loader = memberHosts.itemAt(i)
      if (loader && loader.pluginId === String(pluginId)) return loader
    }
    return null
  }

  function unavailableMembers() {
    return (folderData.members || []).filter(function(member) {
      var loader = root.memberLoader(String(member.id))
      return !loader || !loader.item
    }).map(function(member) { return String(member.id) })
  }

  function pressTarget(item, depth) {
    if (!item || depth > 4) return null
    var children = item.children || []
    for (var i = 0; i < children.length; i++) {
      var child = children[i]
      if (child && typeof child.triggerPress === "function") return child
    }
    for (var j = 0; j < children.length; j++) {
      var nested = root.pressTarget(children[j], depth + 1)
      if (nested) return nested
    }
    return null
  }

  function memberIcon(pluginId) {
    memberRevision // make this lookup reactive when a native widget loads
    var loader = memberLoader(pluginId)
    var target = loader && loader.item ? pressTarget(loader.item, 0) : null
    var icon = target && "text" in target ? String(target.text || "").trim() : ""
    return icon !== "" ? icon : "󰐱"
  }

  function launchMember(pluginId) {
    var loader = memberLoader(pluginId)
    var member = loader ? loader.item : null
    if (!member) {
      console.warn("Plugin Folders: native widget is unavailable", pluginId)
      return false
    }

    // The native instance lives under this real bar widget, so its own popup
    // anchors to the bar window rather than to our popup window. Close the
    // folder first, then launch on the next event-loop turn.
    root.close()
    Qt.callLater(function() {
      try {
        var target = root.pressTarget(member, 0)
        if (target) target.triggerPress(Qt.LeftButton)
        else if (typeof member.open === "function") member.open()
        else if (typeof member.toggle === "function") member.toggle()
        else console.warn("Plugin Folders: widget has no clickable launcher", pluginId)
      } catch (error) {
        console.warn("Plugin Folders: could not launch", pluginId, error)
      }
    })
    return true
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("folderId" in target) target.folderId = root.folderId
    if ("folderData" in target) target.folderData = root.folderData
    if ("helperPath" in target) target.helperPath = root.helperPath
  }

  function refresh() {
    if (folderId === "" || folderProc.running) return
    folderOutput = ""
    folderProc.command = [helperPath, "get-folder", folderId]
    folderProc.running = true
  }

  function applyFolderOutput() {
    try {
      var payload = JSON.parse(folderOutput)
      if (payload && payload.ok && payload.result) folderData = payload.result
    } catch (error) {
      console.warn("Plugin Folders: could not parse folder state", error)
    }
  }

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  function openManage() {
    if (!panelLoader.item) return
    panelLoader.item.open()
    panelLoader.item.setManageMode(true)
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  visible: folderId !== ""

  onBarChanged: injectPanel()
  onSettingsChanged: {
    injectPanel()
    initialRefresh.restart()
  }
  onFolderIdChanged: initialRefresh.restart()
  onFolderDataChanged: injectPanel()
  Component.onCompleted: initialRefresh.restart()

  Timer {
    id: initialRefresh
    interval: 80
    repeat: false
    onTriggered: root.refresh()
  }

  FileView {
    path: root.stateFile
    watchChanges: true
    printErrors: false
    onFileChanged: root.refresh()
  }

  Process {
    id: folderProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.folderOutput = text
        root.applyFolderOutput()
      }
    }
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  // Keep each hosted native BarWidget in the actual bar scene. Its visual
  // button is hidden behind the folder button, while its popup, IPC, timers,
  // and other normal behavior remain intact. This avoids unsupported nested
  // popup anchors when a launcher is clicked inside the folder window.
  Repeater {
    id: memberHosts
    model: Array.isArray(root.folderData.members) ? root.folderData.members : []

    Loader {
      required property var modelData
      readonly property string pluginId: String(modelData.id || "")
      anchors.fill: parent
      z: -100
      visible: false
      active: pluginId !== ""
      sourceComponent: root.memberComponent(pluginId)

      function injectMember() {
        if (!item) return
        if ("bar" in item) item.bar = root.memberBar(pluginId)
        if ("moduleName" in item) item.moduleName = pluginId
        if ("settings" in item)
          item.settings = modelData.entry && typeof modelData.entry === "object"
            ? modelData.entry : ({})
      }

      onLoaded: {
        injectMember()
        root.memberRevision++
      }
      onModelDataChanged: injectMember()
      Connections {
        target: root
        function onBarChanged() { injectMember() }
        function onNativeBarChanged() { injectMember() }
      }
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: String(root.folderData.icon || "󰉋")
    active: root.opened
    activeColor: String(root.folderData.color || "#7aa2f7")
    useActiveColor: true
    tooltipText: String(root.folderData.name || "Plugin folder")
      + " · " + String((root.folderData.members || []).length) + " plugin"
      + ((root.folderData.members || []).length === 1 ? "" : "s")
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.RightButton) root.openManage()
      else root.toggle()
    }
  }
}
