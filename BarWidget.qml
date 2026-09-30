import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Icône dans la barre : clic gauche ouvre le panneau de lecture, clic droit
// recharge. L'infobulle donne le jour liturgique.
BarWidget {
  id: root
  moduleName: "io.github.vianney-g.aelf"

  readonly property var panelItem: panelLoader.item
  readonly property bool opened: panelItem ? panelItem.opened === true : false
  readonly property bool popoutSwitchClosing: panelItem ? panelItem.popoutSwitchClosing === true : false

  // Fenêtre détachée ouverte : l'icône la met au premier plan au lieu
  // d'ouvrir le panneau.
  function open() {
    if (!panelItem) return
    if (panelItem.windowed) panelItem.focusWindow()
    else panelItem.open()
  }
  function close() { if (panelItem) panelItem.close() }
  function toggle() {
    if (!panelItem) return
    if (panelItem.windowed) panelItem.focusWindow()
    else panelItem.toggle()
  }
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

  // omarchy-shell io.github.vianney-g.aelf toggle | open <office> | date <texte> | detach | status
  // office : messes, lectures, laudes, tierce, sexte, none, vepres, complies
  // Le widget existe en plusieurs exemplaires (un par écran, plus une copie
  // invisible) : on passe par la barre pour viser celui de l'écran actif.
  IpcHandler {
    target: "io.github.vianney-g.aelf"
    function widget() {
      var w = root.bar && typeof root.bar.findPanelWidget === "function"
        ? root.bar.findPanelWidget(root.moduleName) : null
      return w || root
    }
    function toggle(): void { widget().toggle() }
    function close(): void { widget().close() }
    function detach(): void { var w = widget(); if (w.panelItem) w.panelItem.detach() }
    function open(office: string): void {
      var w = widget()
      if (!w.panelItem) return
      var i = ["messes", "lectures", "laudes", "tierce", "sexte", "none", "vepres", "complies"].indexOf(office)
      if (i >= 0) w.panelItem.showOffice(i)
      w.open()
    }
    // date : 25/12, 2026-12-25, +7, demain… (voir Model.parseDate)
    function date(texte: string): string {
      var w = widget()
      if (!w.panelItem) return ""
      var iso = w.panelItem.goTo(texte)
      w.open()
      return iso
    }
    function status(): string {
      var p = widget().panelItem
      return p ? JSON.stringify({ opened: p.opened, date: p.date, office: p.officeId, section: p.section ? p.section.label : "", editingDate: p.editingDate, absent: p.dateAbsent, windowed: p.windowed, cachedDates: p.recentDates.length, cacheEntries: Object.keys(p.cache).length, loading: p.loading, error: p.error }) : "{}"
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰂢"  // nf-md-book_cross, police du thème
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

  // Pastille discrète de la couleur liturgique du jour affiché, dans le coin
  // de l'icône.
  Rectangle {
    readonly property var info: root.panelItem ? root.panelItem.info : null
    visible: info !== null
    anchors { right: button.right; bottom: button.bottom; rightMargin: Style.space(4); bottomMargin: Style.space(4) }
    width: Style.space(5)
    height: width
    radius: Style.cornerRadius
    color: Model.couleur(info ? info.couleur : "")
    border.width: Style.normalBorderWidth
    border.color: Style.normalBorderFor(root.bar ? root.bar.foreground : Color.foreground, Color.accent)
  }
}
