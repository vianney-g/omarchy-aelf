import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Panneau de lecture : en-tête du jour liturgique, onglets messe / offices,
// puis un carrousel des textes de l'office (un texte affiché à la fois).
// Les réponses de l'API sont gardées en mémoire par date.
Panel {
  id: root
  moduleName: "io.github.vianney-g.aelf"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property string zone: setting("zone", "afrique")
  // Tout vient du thème : couleurs d'état, bordures, police. La police de
  // lecture peut être changée par "readingFont" dans shell.json.
  readonly property int textSize: parseInt(setting("fontSize", Style.font.title), 10)
  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(fg, 1.4)
  readonly property color line: Style.normalBorderFor(fg, Color.accent)
  readonly property color selectedColor: Style.selectedStateColor(fg, Color.accent)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string readingFont: setting("readingFont", fontFamily)

  property string today: Model.isoDate(new Date())
  property string date: today
  property int officeIndex: 0
  property int messeIndex: -1
  property int sectionIndex: 0
  property int slideDirection: 1
  property var cache: ({})
  property bool loading: false
  property string error: ""
  property bool editingDate: false
  property string dateError: ""

  // Émis à chaque changement de texte, d'office ou de date : les vues
  // rejouent leur animation de glissement.
  signal slid()

  readonly property string officeId: Model.OFFICES[officeIndex].id
  readonly property var current: cache[date + "/" + officeId] || null
  readonly property var info: {
    var d = cache[date + "/informations"] || current
    return d && d.informations ? d.informations : null
  }
  // L'API ne couvre qu'une plage de dates (404 au-delà) : on le retient.
  readonly property bool dateAbsent: {
    var d = cache[date + "/informations"]
    return d ? d.absent === true : false
  }
  readonly property var messes: current && current.messes ? current.messes : []
  readonly property int messeShown: {
    if (messeIndex >= 0 && messeIndex < messes.length) return messeIndex
    for (var i = 0; i < messes.length; i++) if (messes[i].nom === "Messe du jour") return i
    return 0
  }
  readonly property var sections: {
    if (!current || current.absent) return []
    var a = String(Color.accent), d = String(root.dim)
    if (officeId === "messes") return Model.messeSections(messes[messeShown], a, d)
    return Model.officeSections(current[officeId], a, d)
  }
  readonly property var section: sections.length > 0 ? sections[Math.min(sectionIndex, sections.length - 1)] : null

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
    var n = Model.OFFICES.length
    i = (i + n) % n
    if (i === officeIndex) return
    slideDirection = i > officeIndex ? 1 : -1
    officeIndex = i
    messeIndex = -1
    sectionIndex = 0
    ensure(officeId)
    root.slid()
  }

  function showMesse(i) {
    if (i === messeShown) return
    slideDirection = i > messeShown ? 1 : -1
    messeIndex = i
    sectionIndex = 0
    root.slid()
  }

  function showSection(i) {
    i = Math.max(0, Math.min(i, sections.length - 1))
    if (i === sectionIndex) return
    slideDirection = i > sectionIndex ? 1 : -1
    sectionIndex = i
    root.slid()
  }

  function setDate(iso) {
    if (!iso || iso === date) return
    slideDirection = iso > date ? 1 : -1
    date = iso
    messeIndex = -1
    sectionIndex = 0
    ensure("informations")
    ensure(officeId)
    root.slid()
  }

  // Saisie libre (voir Model.parseDate) ; renvoie la date retenue ou "".
  function goTo(texte) {
    var iso = Model.parseDate(texte, date)
    if (iso) setDate(iso)
    return iso
  }

  // La saisie elle-même (champ, focus) est gérée par la vue : voir Reader.
  function startEditDate() {
    dateError = ""
    editingDate = true
  }
  function stopEditDate() {
    editingDate = false
    dateError = ""
  }

  // ---- Fenêtre détachée : une vraie fenêtre Hyprland (en mosaïque), qui
  //      affiche la même vue sur le même état que le panneau.
  property bool windowed: false
  readonly property string windowTitle: "AELF"

  function detach() {
    root.close()
    root.ensure(root.officeId)
    if (windowed) focusWindow()
    else windowed = true
  }
  function attach() {
    windowed = false
    root.open()
  }
  // Hyprland 0.56 : les dispatchers s'écrivent en Lua.
  function focusWindow() {
    Quickshell.execDetached(["hyprctl", "dispatch",
      'hl.dsp.focus({ window = "title:^' + windowTitle + '$" })'])
  }

  function reload() {
    var c = {}
    for (var k in cache) if (k.indexOf(date + "/") !== 0) c[k] = cache[k]
    cache = c
    ensure("informations")
    ensure(officeId)
  }

  // Bornes mémoire : une réponse de l'API fait au plus ~35 Ko, on coupe à
  // 1 Mio ; le cache ne garde que les dernières dates consultées (plus la
  // date affichée et aujourd'hui).
  readonly property int maxBytes: 1048576
  readonly property int maxDates: 7
  property var recentDates: []

  function store(key, value) {
    var d = key.split("/")[0]
    var recent = [d].concat(recentDates.filter(function(x) { return x !== d }))
    var keep = recent.slice(0, maxDates).concat([date, today])
    var c = {}
    for (var k in cache) if (keep.indexOf(k.split("/")[0]) >= 0) c[k] = cache[k]
    c[key] = value
    recentDates = recent.slice(0, maxDates)
    cache = c
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
    // --max-filesize coupe dès que la taille dépasse la borne ; head -c la
    // garantit quelle que soit la version de curl, réponses en flux comprises :
    // le shell ne reçoit jamais plus de maxBytes octets.
    fetchProc.command = ["bash", "-c",
      'set -o pipefail; curl -fsS --max-time 15 --max-filesize "$2" "$1" | head -c "$2"',
      "aelf-fetch", Model.url(parts[1], parts[0], root.zone), String(root.maxBytes)]
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
      if (follow) {
        root.date = t
        root.sectionIndex = 0
        root.ensure("informations")
        if (root.opened) root.ensure(root.officeId)
      }
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
          root.store(key, JSON.parse(out.text))
          root.error = ""
        } catch (e) { root.error = "Réponse illisible de l'API AELF." }
      } else if (code === 22) {
        // Erreur HTTP (404) : pas de textes publiés pour cette date.
        root.store(key, { absent: true })
        root.error = ""
      } else if (code === 63 || code === 23 || code === 141) {
        // 63 : --max-filesize ; 23 / 141 : head -c a fermé le tube.
        root.error = "Réponse de l'API AELF anormalement volumineuse, ignorée."
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
    focusTarget: panelReader
    contentWidth: panel.fittedContentWidth(Style.space(640))
    contentHeight: panel.fittedContentHeight(Style.space(1200), panel.availableCardHeight * 0.9)

    Reader {
      id: panelReader
      anchors.fill: parent
      s: root
      onDismissRequested: root.close()
      onDetachRequested: root.detach()
    }
  }

  FloatingWindow {
    id: readerWindow
    visible: root.windowed
    title: root.windowTitle
    color: Color.background
    implicitWidth: 760
    implicitHeight: 900
    minimumSize: Qt.size(480, 480)

    // Fermée par Hyprland (SUPER + W…) : on revient au mode panneau.
    onVisibleChanged: {
      if (visible) Qt.callLater(function() { windowReader.forceActiveFocus() })
      else root.windowed = false
    }

    Reader {
      id: windowReader
      anchors.fill: parent
      anchors.margins: Style.spacing.popupPadding
      s: root
      windowed: true
      focus: true
      onDetachRequested: root.attach()
    }
  }
}
