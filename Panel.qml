import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Panneau de lecture : en-tête du jour liturgique, onglets messe / offices,
// texte défilant. Les réponses de l'API sont gardées en mémoire par date.
Panel {
  id: root
  moduleName: "vianney.aelf"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property string zone: setting("zone", "afrique")
  readonly property int textSize: parseInt(setting("fontSize", Math.round(Style.font.title * 1.15)), 10)
  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(fg, 1.45)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  property string today: Model.isoDate(new Date())
  property string date: today
  property int officeIndex: 0
  property int messeIndex: -1
  property var cache: ({})
  property bool loading: false
  property string error: ""

  readonly property string officeId: Model.OFFICES[officeIndex].id
  readonly property var current: cache[date + "/" + officeId] || null
  readonly property var info: {
    var d = cache[date + "/informations"] || current
    return d && d.informations ? d.informations : null
  }
  readonly property var messes: current && current.messes ? current.messes : []
  readonly property int messeShown: {
    if (messeIndex >= 0 && messeIndex < messes.length) return messeIndex
    for (var i = 0; i < messes.length; i++) if (messes[i].nom === "Messe du jour") return i
    return 0
  }
  readonly property string html: {
    if (!current) return ""
    var a = String(Color.accent), d = String(root.dim)
    if (officeId === "messes") return Model.messeHtml(messes[messeShown], a, d)
    return Model.officeHtml(current[officeId], a, d)
  }

  function open() {
    root.controller.show()
    root.ensure(root.officeId)
  }
  function toggle() { root.opened ? root.close() : root.open() }
  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function showOffice(i) {
    officeIndex = (i + Model.OFFICES.length) % Model.OFFICES.length
    messeIndex = -1
    flick.contentY = 0
    ensure(officeId)
  }

  function reload() {
    var c = {}
    for (var k in cache) if (k.indexOf(date + "/") !== 0) c[k] = cache[k]
    cache = c
    ensure("informations")
    ensure(officeId)
  }

  // Un seul curl à la fois ; ce qui arrive entre-temps est rejoué à la fin.
  property var queue: []
  function ensure(office) {
    var key = date + "/" + office
    if (cache[key] || queue.indexOf(key) >= 0 || fetchProc.key === key) return
    queue = queue.concat([key])
    next()
  }
  function next() {
    if (fetchProc.running || queue.length === 0) return
    var key = queue[0]
    queue = queue.slice(1)
    var parts = key.split("/")
    fetchProc.key = key
    fetchProc.command = ["curl", "-fsS", "--max-time", "15", Model.url(parts[1], parts[0], root.zone)]
    root.loading = true
    fetchProc.running = true
  }

  onZoneChanged: { cache = {}; ensure("informations") }
  Component.onCompleted: ensure("informations")

  // Passage à minuit : on suit la date du jour.
  Timer {
    interval: 60000
    running: true
    repeat: true
    onTriggered: {
      var t = Model.isoDate(new Date())
      if (t === root.today) return
      var follow = root.date === root.today
      root.today = t
      if (follow) { root.date = t; root.ensure("informations"); if (root.opened) root.ensure(root.officeId) }
    }
  }

  Process {
    id: fetchProc
    property string key: ""
    stdout: StdioCollector { id: out; waitForEnd: true }
    onExited: function(code) {
      var key = fetchProc.key
      fetchProc.key = ""
      root.loading = false
      if (code === 0) {
        try {
          var c = Object.assign({}, root.cache)
          c[key] = JSON.parse(out.text)
          root.cache = c
          root.error = ""
        } catch (e) { root.error = "Réponse illisible de l'API AELF." }
      } else {
        root.error = "Impossible de joindre api.aelf.org (r pour réessayer)."
      }
      root.next()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(640))
    contentHeight: panel.fittedContentHeight(Style.space(1200), panel.availableCardHeight * 0.9)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) {
        if (dx !== 0) root.showOffice(root.officeIndex + dx)
        else flick.scrollBy(dy * 60)
      }
      onActivateRequested: flick.scrollBy(flick.height * 0.85)
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.reload()
        else if (t >= "1" && t <= "8") root.showOffice(parseInt(t, 10) - 1)
        else if ((t === "m" || t === "M") && root.messes.length > 1)
          root.messeIndex = (root.messeShown + 1) % root.messes.length
      }

      Column {
        id: header
        anchors { left: parent.left; right: parent.right; top: parent.top }
        spacing: Style.space(4)

        Text {
          text: Qt.locale("fr_FR").toString(new Date(root.date + "T12:00:00"), "dddd d MMMM yyyy")
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.capitalization: Font.AllUppercase
          font.letterSpacing: 1
        }

        Row {
          width: parent.width
          spacing: Style.space(8)

          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(10); height: width; radius: width / 2
            color: Model.couleur(root.info ? root.info.couleur : "")
            visible: root.info !== null
          }
          Text {
            width: parent.width - Style.space(18)
            text: root.info ? (root.info.ligne1 || root.info.jour_liturgique_nom || "") : (root.error || "Chargement…")
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            font.bold: true
            wrapMode: Text.Wrap
          }
        }

        Text {
          width: parent.width
          visible: text !== ""
          text: root.info ? [root.info.ligne2, root.info.ligne3].filter(function(s) { return s }).join(" · ") : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          wrapMode: Text.Wrap
        }

        Item { width: 1; height: Style.space(6) }

        Flow {
          width: parent.width
          spacing: Style.space(12)

          Repeater {
            model: Model.OFFICES
            delegate: Text {
              required property var modelData
              required property int index
              text: modelData.label
              color: index === root.officeIndex ? Color.accent : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: index === root.officeIndex
              font.underline: index === root.officeIndex
              TapHandler { onTapped: root.showOffice(index) }
              HoverHandler { cursorShape: Qt.PointingHandCursor }
            }
          }
        }

        Flow {
          width: parent.width
          spacing: Style.space(10)
          visible: root.officeId === "messes" && root.messes.length > 1

          Repeater {
            model: root.officeId === "messes" ? root.messes : []
            delegate: Text {
              required property var modelData
              required property int index
              text: modelData.nom
              color: index === root.messeShown ? root.fg : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: index === root.messeShown
              TapHandler { onTapped: { root.messeIndex = index; flick.contentY = 0 } }
              HoverHandler { cursorShape: Qt.PointingHandCursor }
            }
          }
        }

        PanelSeparator { width: parent.width }
      }

      Flickable {
        id: flick
        anchors { left: parent.left; right: parent.right; top: header.bottom; bottom: parent.bottom; topMargin: Style.space(4) }
        contentWidth: width
        contentHeight: body.implicitHeight + Style.space(24)
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        function scrollBy(dy) {
          contentY = Math.max(0, Math.min(contentHeight - height, contentY + dy))
        }

        ScrollBar.vertical: ScrollBar {
          policy: flick.contentHeight > flick.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
        }

        Text {
          id: body
          width: flick.width - Style.space(14)
          text: root.html !== "" ? root.html
            : (root.loading ? "Chargement…" : (root.error || "Rien pour cet office."))
          textFormat: root.html !== "" ? Text.RichText : Text.PlainText
          wrapMode: Text.Wrap
          color: root.fg
          font.family: "serif"
          font.pixelSize: root.textSize
          lineHeight: 1.15
        }
      }
    }
  }
}
