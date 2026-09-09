import QtQuick
import Quickshell.Io

Item {
  id: root

  property var shell: null
  property var barWidgetRegistry: null
  property var folderWidgets: []
  readonly property string pluginId: "io.github.dlpwaters.plugin-folders"

  function registerFolder(widget) {
    if (folderWidgets.indexOf(widget) < 0) folderWidgets = folderWidgets.concat([widget])
  }

  function unregisterFolder(widget) {
    folderWidgets = folderWidgets.filter(function(item) { return item && item !== widget })
  }

  function folderWidget(folderId) {
    var requested = String(folderId || "")
    for (var i = 0; i < folderWidgets.length; i++) {
      var item = folderWidgets[i]
      if (!item) continue
      if (requested === "" || String(item.folderId || "") === requested) return item
    }
    return null
  }

  IpcHandler {
    target: "plugin-folders"

    function open(folderId: string): string {
      var item = root.folderWidget(folderId)
      if (!item) return "unknown folder"
      item.open()
      return "ok"
    }

    function close(folderId: string): string {
      var item = root.folderWidget(folderId)
      if (!item) return "unknown folder"
      item.close()
      return "ok"
    }

    function toggle(folderId: string): string {
      var item = root.folderWidget(folderId)
      if (!item) return "unknown folder"
      item.toggle()
      return "ok"
    }

    function manage(folderId: string): string {
      var item = root.folderWidget(folderId)
      if (!item) return "unknown folder"
      item.openManage()
      return "ok"
    }

    function launch(folderId: string, pluginId: string): string {
      var item = root.folderWidget(folderId)
      if (!item) return "unknown folder"
      return item.launchMember(pluginId) ? "ok" : "plugin unavailable"
    }

    function status(folderId: string): string {
      var item = root.folderWidget(folderId)
      if (!item) return "{}"
      return JSON.stringify({
        id: String(item.folderId || ""),
        name: String(item.folderData && item.folderData.name || ""),
        members: item.folderData && Array.isArray(item.folderData.members)
          ? item.folderData.members.length : 0,
        unavailableMembers: item.unavailableMembers(),
        opened: item.opened === true,
        query: String(item.launcherQuery || ""),
        visibleMembers: Number(item.launcherVisibleCount || 0),
        selectedPluginId: String(item.launcherSelectedPluginId || ""),
        searchFocused: item.launcherSearchFocused === true
      })
    }
  }
}
