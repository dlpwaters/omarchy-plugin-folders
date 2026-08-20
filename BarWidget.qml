import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root

  readonly property string folderId: String(setting("folderId", ""))
  readonly property string helperPath: String(Qt.resolvedUrl("folderctl")).replace(/^file:\/\//, "")
  readonly property string stateHome: {
    var configured = Quickshell.env("XDG_STATE_HOME")
    return configured !== "" ? configured : Quickshell.env("HOME") + "/.local/state"
  }
  readonly property string stateFile: stateHome + "/omarchy-plugin-folders/state.json"
  property var folderData: ({ id: folderId, name: "Plugins", icon: "󰉋", color: "#7aa2f7", members: [] })
  property string folderOutput: ""
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened : false

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
    if ("barWidgetRegistry" in target)
      target.barWidgetRegistry = root.bar ? root.bar.barWidgetRegistry : null
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
