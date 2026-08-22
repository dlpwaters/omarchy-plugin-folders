import QtQuick
import QtQuick.Controls as QQC
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.dlpwaters.plugin-folders"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property string folderId: ""
  property var folderData: ({ id: "", name: "Plugins", icon: "󰉋", color: "#7aa2f7", members: [] })
  property string helperPath: ""
  property var catalog: ({ folders: [], plugins: [] })
  property var pendingSelection: ({})
  property bool selectionDirty: false

  readonly property var barIdentity: hostWidget || root
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color muted: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.58)
  readonly property color subtle: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.08)
  readonly property color folderColor: String(folderData.color || "#7aa2f7")
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property int desiredWidth: Style.space(530)
  readonly property int maximumHeight: Style.space(720)
  readonly property var iconOptions: ["󰉋", "󰕰", "󰖷", "󰛨", "󰈸", "󰂺", "󰝚", "󰅴", "󰇮", "󰏖", "󰘳", "󰒓"]
  readonly property var colorOptions: [
    "#7aa2f7", "#bb9af7", "#f7768e", "#ff9e64", "#e0af68",
    "#9ece6a", "#73daca", "#2ac3de", "#7dcfff", "#c0caf5"
  ]

  property bool manageMode: false
  property bool busy: false
  property bool membershipAction: false
  property bool confirmDelete: false
  property string statusText: ""
  property bool statusError: false
  property string catalogOutput: ""
  property string actionOutput: ""
  property string actionLabel: ""
  property string selectedIcon: String(folderData.icon || "󰉋")
  property string selectedColor: String(folderData.color || "#7aa2f7")
  property int launcherIndex: -1

  readonly property int launcherColumns: 3

  function members() {
    return Array.isArray(folderData.members) ? folderData.members : []
  }

  function refreshCatalog() {
    if (helperPath === "" || catalogProc.running) return
    catalogOutput = ""
    catalogProc.command = [helperPath, "catalog"]
    catalogProc.running = true
  }

  function parseCatalog() {
    try {
      var payload = JSON.parse(catalogOutput)
      if (payload && payload.ok && payload.result) {
        catalog = payload.result
        if (manageMode && !selectionDirty) resetPendingSelection()
      }
      else if (payload && payload.error) showStatus(payload.error, true)
    } catch (error) {
      showStatus("Could not read the plugin catalog.", true)
    }
  }

  function visiblePlugins() {
    var source = catalog && Array.isArray(catalog.plugins) ? catalog.plugins : []
    var query = pluginSearch.text.trim().toLowerCase()
    var result = []
    for (var i = 0; i < source.length; i++) {
      var plugin = source[i]
      if (plugin.protected) continue
      var assignedHere = plugin.assignedFolderId === folderId
      var available = plugin.inBar && plugin.assignedFolderId === ""
      if (!assignedHere && !available) continue
      if (query !== "") {
        var haystack = (String(plugin.name) + " " + String(plugin.id) + " "
          + String(plugin.category || "")).toLowerCase()
        if (haystack.indexOf(query) === -1) continue
      }
      result.push(plugin)
    }
    return result
  }

  function showStatus(message, isError) {
    statusText = String(message || "")
    statusError = isError === true
    statusTimer.restart()
  }

  function resetPendingSelection() {
    var next = ({})
    var current = members()
    for (var i = 0; i < current.length; i++) next[String(current[i].id)] = true
    pendingSelection = next
    selectionDirty = false
  }

  function isPendingSelected(pluginId) {
    return pendingSelection[String(pluginId)] === true
  }

  function togglePending(pluginId) {
    var id = String(pluginId)
    var next = ({})
    for (var key in pendingSelection) next[key] = pendingSelection[key]
    next[id] = next[id] !== true
    pendingSelection = next
    selectionDirty = membershipChangeCount() > 0
  }

  function setVisibleSelection(selected) {
    var next = ({})
    for (var key in pendingSelection) next[key] = pendingSelection[key]
    var visible = visiblePlugins()
    for (var i = 0; i < visible.length; i++) next[String(visible[i].id)] = selected === true
    pendingSelection = next
    selectionDirty = membershipChangeCount() > 0
  }

  function selectedPluginIds() {
    var source = catalog && Array.isArray(catalog.plugins) ? catalog.plugins : []
    var result = []
    for (var i = 0; i < source.length; i++) {
      if (isPendingSelected(source[i].id)) result.push(String(source[i].id))
    }
    return result
  }

  function membershipChangeCount() {
    var source = catalog && Array.isArray(catalog.plugins) ? catalog.plugins : []
    var changes = 0
    for (var i = 0; i < source.length; i++) {
      var currentlySelected = source[i].assignedFolderId === folderId
      if (isPendingSelected(source[i].id) !== currentlySelected) changes++
    }
    return changes
  }

  function applyMembership() {
    var changes = membershipChangeCount()
    if (changes === 0) return
    membershipAction = true
    runAction(["set-members", folderId].concat(selectedPluginIds()),
      changes + " plugin change" + (changes === 1 ? "" : "s") + " applied")
  }

  function launchMember(plugin) {
    if (!hostWidget || typeof hostWidget.launchMember !== "function"
        || !hostWidget.launchMember(String(plugin.id))) {
      showStatus(String(plugin.name || plugin.id) + " could not be loaded.", true)
    }
  }

  function resetLauncherCursor() {
    launcherIndex = members().length > 0 ? 0 : -1
  }

  function moveLauncherCursor(dx, dy) {
    var count = members().length
    if (count === 0) {
      launcherIndex = -1
      return
    }

    var current = launcherIndex >= 0 && launcherIndex < count ? launcherIndex : 0
    if (dx !== 0) {
      launcherIndex = Math.max(0, Math.min(count - 1, current + dx))
      return
    }

    var column = current % launcherColumns
    var row = Math.floor(current / launcherColumns)
    var lastRow = Math.floor((count - 1) / launcherColumns)
    var nextRow = Math.max(0, Math.min(lastRow, row + dy))
    launcherIndex = Math.min(count - 1, nextRow * launcherColumns + column)
  }

  function activateLauncherCursor() {
    var items = members()
    if (launcherIndex < 0 || launcherIndex >= items.length) return
    launchMember(items[launcherIndex])
  }

  function runAction(argumentsList, label) {
    if (busy || helperPath === "") return
    busy = true
    actionOutput = ""
    actionLabel = label
    actionProc.command = [helperPath].concat(argumentsList)
    actionProc.running = true
  }

  function finishAction(exitCode) {
    busy = false
    var payload = null
    try { payload = JSON.parse(actionOutput) } catch (error) {}
    if (exitCode !== 0 || !payload || !payload.ok) {
      membershipAction = false
      showStatus(payload && payload.error ? payload.error : actionLabel + " failed.", true)
      return
    }
    if (membershipAction) selectionDirty = false
    membershipAction = false
    confirmDelete = false
    showStatus(actionLabel, false)
    if (hostWidget && typeof hostWidget.refresh === "function") hostWidget.refresh()
    refreshCatalog()
  }

  function saveAppearance() {
    var name = folderName.text.trim()
    if (name === "") {
      showStatus("Give the folder a name first.", true)
      return
    }
    runAction(["update", folderId, "--name", name, "--icon", selectedIcon,
      "--color", selectedColor], "Folder updated")
  }

  function open() {
    manageMode = false
    confirmDelete = false
    resetLauncherCursor()
    selectedIcon = String(folderData.icon || "󰉋")
    selectedColor = String(folderData.color || "#7aa2f7")
    resetPendingSelection()
    root.controller.show()
    refreshCatalog()
  }

  function setManageMode(value) {
    manageMode = value
    confirmDelete = false
    if (!value) resetLauncherCursor()
    if (value) {
      folderName.text = String(folderData.name || "Plugins")
      selectedIcon = String(folderData.icon || "󰉋")
      selectedColor = String(folderData.color || "#7aa2f7")
      resetPendingSelection()
      refreshCatalog()
      Qt.callLater(function() { pluginSearch.forceActiveFocus() })
    }
  }

  onFolderDataChanged: {
    selectedIcon = String(folderData.icon || "󰉋")
    selectedColor = String(folderData.color || "#7aa2f7")
    if (manageMode) folderName.text = String(folderData.name || "Plugins")
    if (!manageMode) resetLauncherCursor()
  }

  Process {
    id: catalogProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.catalogOutput = text }
    onExited: root.parseCatalog()
  }

  Process {
    id: actionProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.actionOutput = text }
    onExited: function(exitCode) { root.finishAction(exitCode) }
  }

  Timer {
    id: statusTimer
    interval: 3200
    onTriggered: root.statusText = ""
  }

  KeyboardPanel {
    id: folderPanel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: keyCatcher
    contentWidth: folderPanel.fittedContentWidth(root.desiredWidth)
    contentHeight: folderPanel.fittedContentHeight(contentColumn.implicitHeight, root.maximumHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: folderName.activeFocus || pluginSearch.activeFocus
      onCloseRequested: root.close()
      onMoveRequested: function(dx, dy) {
        if (!root.manageMode) root.moveLauncherCursor(dx, dy)
      }
      onActivateRequested: {
        if (!root.manageMode) root.activateLauncherCursor()
      }

      Column {
        id: contentColumn
        width: parent.width
        spacing: Style.space(12)

        Row {
          width: parent.width
          height: Math.max(Style.space(52), headerCopy.implicitHeight)
          spacing: Style.space(12)

          BorderSurface {
            width: Style.space(48)
            height: width
            anchors.verticalCenter: parent.verticalCenter
            radius: Style.cornerRadius
            color: Qt.rgba(root.folderColor.r, root.folderColor.g, root.folderColor.b, 0.16)
            borderSpec: Border.flat(root.folderColor, 1)

            Text {
              anchors.centerIn: parent
              text: String(root.folderData.icon || "󰉋")
              color: root.folderColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
          }

          Column {
            id: headerCopy
            width: parent.width - Style.space(48) - editButton.width - parent.spacing * 2
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              width: parent.width
              text: String(root.folderData.name || "Plugins")
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              text: root.manageMode ? "CUSTOMIZE & ORGANIZE" : String(root.members().length)
                + " PLUGIN" + (root.members().length === 1 ? "" : "S")
                + (root.members().length > 0 ? "  ·  ARROWS + ENTER" : "")
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.05
            }
          }

          PanelActionButton {
            id: editButton
            anchors.verticalCenter: parent.verticalCenter
            iconText: root.manageMode ? "󰅖" : "󰒓"
            tooltipText: root.manageMode ? "Back to folder" : "Manage folder"
            foreground: root.foreground
            hoverColor: root.folderColor
            bordered: true
            focusable: true
            onClicked: root.setManageMode(!root.manageMode)
          }
        }

        Rectangle {
          width: parent.width
          height: 1
          color: root.subtle
        }

        Item {
          visible: !root.manageMode
          width: parent.width
          height: visible ? launcherContent.implicitHeight : 0

          Column {
            id: launcherContent
            width: parent.width
            spacing: Style.space(12)

            Text {
              visible: root.members().length === 0
              width: parent.width
              topPadding: Style.space(26)
              bottomPadding: Style.space(26)
              text: "This folder is ready. Open Manage to add plugins from your bar."
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
            }

            Flow {
              visible: root.members().length > 0
              width: parent.width
              spacing: Style.space(8)

              Repeater {
                model: root.members()

                BorderSurface {
                  id: memberTile
                  required property var modelData
                  required property int index
                  readonly property bool keyboardSelected: !root.manageMode
                    && root.launcherIndex === index
                  width: Math.floor((launcherContent.width - Style.space(16)) / 3)
                  height: Style.space(94)
                  radius: Style.cornerRadius
                  color: tileHover.hovered || keyboardSelected
                    ? Style.hoverFillFor(root.foreground, root.folderColor) : root.subtle
                  borderSpec: tileHover.hovered || keyboardSelected
                    ? Border.controlSpec(keyboardSelected ? "keyboard-cursor" : "hover-cursor",
                        root.foreground, root.folderColor)
                    : Border.none()
                  clip: true

                  Column {
                    anchors.fill: parent
                    anchors.margins: Style.space(8)
                    spacing: Style.space(5)

                    Item {
                      width: parent.width
                      height: Style.space(52)

                      Text {
                        anchors.centerIn: parent
                        text: root.hostWidget && typeof root.hostWidget.memberIcon === "function"
                          ? root.hostWidget.memberIcon(memberTile.modelData.id) : "󰐱"
                        color: root.folderColor
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.iconLarge
                      }
                    }

                    Text {
                      width: parent.width
                      text: String(memberTile.modelData.name || memberTile.modelData.id)
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                      horizontalAlignment: Text.AlignHCenter
                      elide: Text.ElideRight
                    }
                  }

                  HoverHandler {
                    id: tileHover
                    onHoveredChanged: if (hovered) root.launcherIndex = memberTile.index
                  }
                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      root.launcherIndex = memberTile.index
                      root.launchMember(memberTile.modelData)
                    }
                  }
                }
              }
            }

            Button {
              visible: root.members().length === 0
              anchors.horizontalCenter: parent.horizontalCenter
              text: "Add plugins"
              iconText: "󰐕"
              foreground: root.foreground
              accent: root.folderColor
              bordered: true
              focusable: true
              onClicked: root.setManageMode(true)
            }
          }
        }

        Item {
          visible: root.manageMode
          width: parent.width
          height: visible ? manageContent.implicitHeight : 0

          Column {
            id: manageContent
            width: parent.width
            spacing: Style.space(12)

            Text {
              text: "FOLDER DETAILS"
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.0
            }

            TextField {
              id: folderName
              width: parent.width
              text: String(root.folderData.name || "Plugins")
              placeholderText: "Folder name"
              foreground: root.foreground
              accent: root.folderColor
              onAccepted: root.saveAppearance()
            }

            Flow {
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: root.iconOptions

                Button {
                  required property string modelData
                  width: Style.space(36)
                  height: width
                  iconText: modelData
                  foreground: root.foreground
                  accent: root.folderColor
                  selected: root.selectedIcon === modelData
                  bordered: true
                  focusable: true
                  onClicked: root.selectedIcon = modelData
                }
              }
            }

            Flow {
              width: parent.width
              spacing: Style.space(7)

              Repeater {
                model: root.colorOptions

                BorderSurface {
                  id: swatch
                  required property string modelData
                  width: Style.space(32)
                  height: width
                  radius: Style.cornerRadius
                  color: modelData
                  borderSpec: root.selectedColor === modelData
                    ? Border.flat(root.foreground, 2) : Border.flat(Qt.rgba(1, 1, 1, 0.18), 1)

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.selectedColor = swatch.modelData
                  }
                }
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(8)

              Button {
                width: (parent.width - parent.spacing) / 2
                text: "Save appearance"
                iconText: "󰆓"
                foreground: root.foreground
                accent: root.selectedColor
                bordered: true
                focusable: true
                enabled: !root.busy
                onClicked: root.saveAppearance()
              }

              Button {
                width: (parent.width - parent.spacing) / 2
                text: "New folder"
                iconText: "󰉗"
                foreground: root.foreground
                accent: root.folderColor
                bordered: true
                focusable: true
                enabled: !root.busy
                onClicked: root.runAction(["create", "New Folder", "󰉋", "#bb9af7", "--after", root.folderId], "New folder created")
              }
            }

            Rectangle { width: parent.width; height: 1; color: root.subtle }

            Row {
              width: parent.width
              spacing: Style.space(8)

              Text {
                width: parent.width - Style.space(160)
                anchors.verticalCenter: parent.verticalCenter
                text: "PLUGINS"
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.0
              }

              TextField {
                id: pluginSearch
                width: Style.space(160)
                placeholderText: "Search…"
                foreground: root.foreground
                accent: root.folderColor
              }
            }

            BorderSurface {
              width: parent.width
              height: Style.space(245)
              radius: Style.cornerRadius
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.035)
              borderSpec: Border.flat(root.subtle, 1)
              clip: true

              Flickable {
                id: pluginList
                anchors.fill: parent
                anchors.margins: Style.space(5)
                contentWidth: width
                contentHeight: pluginRows.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                clip: true

                Column {
                  id: pluginRows
                  width: pluginList.width
                  spacing: Style.space(3)

                  Repeater {
                    model: root.visiblePlugins()

                    Button {
                      id: pluginRow
                      required property var modelData
                      width: pluginRows.width
                      height: Style.space(46)
                      leftAlign: true
                      text: String(modelData.name)
                      iconText: root.isPendingSelected(modelData.id) ? "󰄬" : "󰐕"
                      tooltipText: String(modelData.id)
                      foreground: root.foreground
                      accent: root.folderColor
                      selected: root.isPendingSelected(modelData.id)
                      bordered: false
                      focusable: true
                      enabled: !root.busy
                      onClicked: root.togglePending(modelData.id)

                      Text {
                        anchors.right: parent.right
                        anchors.rightMargin: Style.space(10)
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.isPendingSelected(pluginRow.modelData.id)
                          ? "SELECTED" : String(pluginRow.modelData.category || "PLUGIN").toUpperCase()
                        color: root.isPendingSelected(pluginRow.modelData.id) ? root.folderColor : root.muted
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                      }
                    }
                  }

                  Text {
                    visible: root.visiblePlugins().length === 0
                    width: parent.width
                    topPadding: Style.space(28)
                    text: pluginSearch.text.trim() === ""
                      ? "No eligible plugins are currently on the bar."
                      : "No plugins match this search."
                    color: root.muted
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                  }
                }

                QQC.ScrollBar.vertical: QQC.ScrollBar { policy: QQC.ScrollBar.AsNeeded }
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(8)

              Button {
                id: selectShownButton
                text: "Select shown"
                iconText: "󰄬"
                foreground: root.foreground
                accent: root.folderColor
                bordered: true
                focusable: true
                enabled: !root.busy && root.visiblePlugins().length > 0
                onClicked: root.setVisibleSelection(true)
              }

              Button {
                id: clearShownButton
                text: "Clear shown"
                iconText: "󰅖"
                foreground: root.foreground
                accent: root.folderColor
                bordered: true
                focusable: true
                enabled: !root.busy && root.visiblePlugins().length > 0
                onClicked: root.setVisibleSelection(false)
              }

              Item {
                width: Math.max(0, parent.width - selectShownButton.width
                  - clearShownButton.width - applyButton.width - parent.spacing * 3)
                height: 1
              }

              Button {
                id: applyButton
                text: root.membershipChangeCount() === 0
                  ? "Up to date" : "Apply " + root.membershipChangeCount()
                iconText: root.membershipChangeCount() === 0 ? "󰄬" : "󰆓"
                foreground: root.foreground
                accent: root.folderColor
                bordered: true
                focusable: true
                enabled: !root.busy && root.membershipChangeCount() > 0
                onClicked: root.applyMembership()
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(8)

              Text {
                width: parent.width - deleteButton.width - parent.spacing
                anchors.verticalCenter: parent.verticalCenter
                text: "Removing this folder restores every member to its saved bar position."
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }

              Button {
                id: deleteButton
                text: root.confirmDelete ? "Confirm delete" : "Delete folder"
                iconText: root.confirmDelete ? "󰜺" : "󰆴"
                foreground: root.confirmDelete ? Color.urgent : root.foreground
                accent: Color.urgent
                bordered: true
                focusable: true
                enabled: !root.busy
                onClicked: {
                  if (!root.confirmDelete) root.confirmDelete = true
                  else root.runAction(["delete", root.folderId], "Folder deleted; plugins restored")
                }
              }
            }
          }
        }

        Text {
          visible: root.statusText !== ""
          width: parent.width
          text: root.statusText
          color: root.statusError ? Color.urgent : root.folderColor
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
        }
      }
    }
  }
}
