import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

// Icône dans la barre : clic gauche ouvre le panneau de lecture, clic droit
// recharge. L'infobulle donne le jour liturgique.
BarWidget {
  id: root
  moduleName: "vianney.aelf"

  readonly property var panelItem: panelLoader.item
  readonly property bool opened: panelItem ? panelItem.opened === true : false
  readonly property bool popoutSwitchClosing: panelItem ? panelItem.popoutSwitchClosing === true : false

  function open() { if (panelItem) panelItem.open() }
  function close() { if (panelItem) panelItem.close() }
  function toggle() { if (panelItem) panelItem.toggle() }
  function closeForPopoutSwitch() { if (panelItem) panelItem.closeForPopoutSwitch() }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    target.bar = root.bar
    target.settings = root.settings
    target.anchorItem = button
    target.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: { root.injectPanel(); Qt.callLater(root.injectPanel) }
  }

  // omarchy-shell vianney.aelf toggle | open <office>
  // office : messes, lectures, laudes, tierce, sexte, none, vepres, complies
  IpcHandler {
    target: "vianney.aelf"
    function toggle(): void { root.toggle() }
    function close(): void { root.close() }
    function status(): string {
      var p = root.panelItem
      return p ? JSON.stringify({ opened: p.opened, date: p.date, office: p.officeId, loading: p.loading, error: p.error }) : "{}"
    }
    function open(office: string): void {
      if (!root.panelItem) return
      var i = ["messes", "lectures", "laudes", "tierce", "sexte", "none", "vepres", "complies"].indexOf(office)
      if (i >= 0) root.panelItem.showOffice(i)
      root.open()
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "✝"
    active: root.opened
    useActiveColor: true
    tooltipText: {
      var info = root.panelItem ? root.panelItem.info : null
      if (!info) return "AELF · lectures du jour"
      return [info.ligne1, info.ligne2].filter(function(s) { return s }).join("\n")
    }
    onPressed: function(b) {
      if (b === Qt.RightButton) { if (root.panelItem) root.panelItem.reload() }
      else root.toggle()
    }
  }
}
