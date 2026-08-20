import QtQuick
import Quickshell.Io

Item {
  id: root

  property var shell: null
  readonly property string pluginId: "io.github.dlpwaters.plugin-folders"

  function folderWidget(folderId) {
    var bar = shell ? shell.bar : null
    var slots = bar && Array.isArray(bar.moduleSlots) ? bar.moduleSlots : []
    var requested = String(folderId || "")
    for (var i = 0; i < slots.length; i++) {
      var slot = slots[i]
      var item = slot ? slot.activeItem : null
      if (!item || slot.moduleName !== pluginId) continue
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
        opened: item.opened === true
      })
    }
  }
}
