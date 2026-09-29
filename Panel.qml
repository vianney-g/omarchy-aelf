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
    slide.restart()
  }

  function showMesse(i) {
    if (i === messeShown) return
    slideDirection = i > messeShown ? 1 : -1
    messeIndex = i
    sectionIndex = 0
    slide.restart()
  }

  function showSection(i) {
    i = Math.max(0, Math.min(i, sections.length - 1))
    if (i === sectionIndex) return
    slideDirection = i > sectionIndex ? 1 : -1
    sectionIndex = i
    slide.restart()
  }

  function setDate(iso) {
    if (!iso || iso === date) return
    slideDirection = iso > date ? 1 : -1
    date = iso
    messeIndex = -1
    sectionIndex = 0
    ensure("informations")
    ensure(officeId)
    slide.restart()
  }

  // Saisie libre (voir Model.parseDate) ; renvoie la date retenue ou "".
  function goTo(texte) {
    var iso = Model.parseDate(texte, date)
    if (iso) setDate(iso)
    return iso
  }

  function startEditDate() {
    dateError = ""
    editingDate = true
    Qt.callLater(function() {
      dateField.text = ""
      dateField.forceActiveFocus()
    })
  }
  function stopEditDate() {
    editingDate = false
    dateError = ""
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  function commitDate() {
    if (dateField.text.trim() === "") { stopEditDate(); return }
    if (goTo(dateField.text)) stopEditDate()
    else dateError = "Date non comprise : essayez 25/12, 8 décembre, +7…"
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
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(640))
    contentHeight: panel.fittedContentHeight(Style.space(1200), panel.availableCardHeight * 0.9)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.editingDate
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.showOffice(root.officeIndex + direction) }
      onMoveRequested: function(dx, dy) {
        if (dx !== 0) root.showSection(root.sectionIndex + dx)
        else flick.scrollBy(dy * 60)
      }
      onActivateRequested: flick.scrollBy(flick.height * 0.85)
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.reload()
        else if (t === "p" || t === "P") root.setDate(Model.addDays(root.date, -1))
        else if (t === "s" || t === "S") root.setDate(Model.addDays(root.date, 1))
        else if (t === "a" || t === "A") root.setDate(root.today)
        else if (t === "d" || t === "D") root.startEditDate()
        else if (t >= "1" && t <= "8") root.showOffice(parseInt(t, 10) - 1)
        else if ((t === "m" || t === "M") && root.messes.length > 1)
          root.showMesse((root.messeShown + 1) % root.messes.length)
      }

      Column {
        id: header
        anchors { left: parent.left; right: parent.right; top: parent.top }
        spacing: Style.space(10)

        // ---- Jour liturgique
        Column {
          width: parent.width
          spacing: Style.space(3)

          // Date : ‹ jour › ; un clic sur la date (ou d) ouvre la saisie.
          Row {
            width: parent.width
            spacing: Style.spacing.sm

            Button {
              anchors.verticalCenter: parent.verticalCenter
              text: "‹"
              tooltipText: "Jour précédent (p)"
              foreground: root.fg
              fontFamily: root.fontFamily
              fontSize: Style.font.body
              verticalPadding: Style.spacing.xxs
              onClicked: root.setDate(Model.addDays(root.date, -1))
            }

            Item {
              anchors.verticalCenter: parent.verticalCenter
              width: root.editingDate ? dateField.width : dateLabel.implicitWidth
              height: root.editingDate ? dateField.height : dateLabel.implicitHeight

              Text {
                id: dateLabel
                anchors.verticalCenter: parent.verticalCenter
                visible: !root.editingDate
                text: Qt.locale("fr_FR").toString(new Date(root.date + "T12:00:00"), "dddd d MMMM yyyy")
                color: dateHover.hovered ? root.fg : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1
                HoverHandler { id: dateHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.startEditDate() }
              }

              TextField {
                id: dateField
                visible: root.editingDate
                width: Style.space(220)
                placeholderText: "25/12, 8 décembre, +7, demain…"
                foreground: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                onActiveFocusChanged: if (!activeFocus && root.editingDate) root.stopEditDate()
                Keys.onPressed: function(event) {
                  if (event.key === Qt.Key_Escape) { root.stopEditDate(); event.accepted = true }
                  else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.commitDate(); event.accepted = true }
                }
              }
            }

            Button {
              anchors.verticalCenter: parent.verticalCenter
              text: "›"
              tooltipText: "Jour suivant (s)"
              foreground: root.fg
              fontFamily: root.fontFamily
              fontSize: Style.font.body
              verticalPadding: Style.spacing.xxs
              onClicked: root.setDate(Model.addDays(root.date, 1))
            }

            Button {
              anchors.verticalCenter: parent.verticalCenter
              visible: root.date !== root.today && !root.editingDate
              text: "Aujourd'hui"
              tooltipText: "Revenir à aujourd'hui (a)"
              bordered: true
              foreground: root.fg
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              verticalPadding: Style.spacing.xxs
              onClicked: root.setDate(root.today)
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              visible: root.editingDate && root.dateError !== ""
              text: root.dateError
              color: Color.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Row {
            width: parent.width
            spacing: Style.space(8)

            // Aplat de la couleur liturgique du jour sélectionné, bordé pour
            // rester visible quand la couleur est proche du fond (blanc…).
            Rectangle {
              width: Style.space(4)
              height: feastTitle.height
              radius: Style.cornerRadius
              color: Model.couleur(root.info ? root.info.couleur : "")
              border.width: Style.normalBorderWidth
              border.color: root.line
              visible: root.info !== null
            }
            Text {
              id: feastTitle
              width: parent.width - Style.space(12)
              text: root.info ? (root.info.ligne1 || root.info.jour_liturgique_nom || "")
                : root.dateAbsent ? "Pas de textes AELF pour ce jour"
                : (root.error || "Chargement…")
              color: root.fg
              font.family: root.readingFont
              font.pixelSize: Style.font.display
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
        }

        // ---- Onglets : messe et offices. Remplissages et couleurs suivent
        //      les états du thème (hover-cursor, selected).
        Item {
          width: parent.width
          height: Style.spacing.controlHeight + Style.space(6)

          Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: Math.max(1, Style.normalBorderWidth)
            color: root.line
          }

          Row {
            anchors.fill: parent

            Repeater {
              model: Model.OFFICES
              delegate: Item {
                id: tab
                required property var modelData
                required property int index
                readonly property bool selected: index === root.officeIndex
                width: parent.width / Model.OFFICES.length
                height: parent.height

                // Coins arrondis en haut seulement (si le thème en met) :
                // le bas est recouvert.
                Rectangle {
                  anchors.fill: parent
                  radius: Style.cornerRadius
                  color: tabHover.hovered ? Style.hoverFillFor(root.fg, Color.accent)
                    : tab.selected ? Style.selectedFillFor(root.fg, Color.accent)
                    : "transparent"
                  Rectangle {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: parent.radius
                    color: parent.color
                  }
                }
                Rectangle {
                  anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                  height: Math.max(2, Style.selectedBorderWidth)
                  color: root.selectedColor
                  visible: tab.selected
                }
                Text {
                  anchors.centerIn: parent
                  text: tab.modelData.label
                  color: tab.selected ? root.selectedColor : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: tab.selected
                }
                HoverHandler { id: tabHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.showOffice(tab.index) }
              }
            }
          }
        }

        // ---- Choix de la messe, les jours où il y en a plusieurs
        Flow {
          width: parent.width
          spacing: Style.spacing.md
          visible: root.officeId === "messes" && root.messes.length > 1

          Repeater {
            model: root.officeId === "messes" ? root.messes : []
            delegate: Button {
              required property var modelData
              required property int index
              text: modelData.nom
              selected: index === root.messeShown
              foreground: root.fg
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              onClicked: root.showMesse(index)
            }
          }
        }

        // ---- Carrousel des textes
        Item {
          width: parent.width
          height: Style.spacing.controlHeight
          visible: root.sections.length > 0

          Button {
            id: prevArrow
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            text: "‹"
            foreground: root.fg
            fontFamily: root.fontFamily
            fontSize: Style.font.heading
            enabled: root.sectionIndex > 0
            opacity: enabled ? 1 : 0.3
            onClicked: root.showSection(root.sectionIndex - 1)
          }
          Button {
            id: nextArrow
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            text: "›"
            foreground: root.fg
            fontFamily: root.fontFamily
            fontSize: Style.font.heading
            enabled: root.sectionIndex < root.sections.length - 1
            opacity: enabled ? 1 : 0.3
            onClicked: root.showSection(root.sectionIndex + 1)
          }

          ListView {
            id: chips
            anchors { left: prevArrow.right; right: nextArrow.left; top: parent.top; bottom: parent.bottom; leftMargin: Style.spacing.sm; rightMargin: Style.spacing.sm }
            orientation: ListView.Horizontal
            spacing: Style.spacing.md
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: root.sections
            currentIndex: root.sectionIndex

            // La pastille active glisse vers le centre.
            function center() {
              var item = itemAtIndex(currentIndex)
              if (!item) { positionViewAtIndex(currentIndex, ListView.Center); return }
              var target = item.x + item.width / 2 - width / 2
              target = Math.max(originX, Math.min(target, originX + contentWidth - width))
              if (contentWidth <= width) target = originX
              scrollAnim.to = target
              scrollAnim.restart()
            }
            onCurrentIndexChanged: Qt.callLater(center)
            onCountChanged: Qt.callLater(center)
            onWidthChanged: Qt.callLater(center)

            NumberAnimation { id: scrollAnim; target: chips; property: "contentX"; duration: 220; easing.type: Easing.OutCubic }

            delegate: Button {
              required property var modelData
              required property int index
              anchors.verticalCenter: parent ? parent.verticalCenter : undefined
              text: modelData.label
              selected: index === root.sectionIndex
              bordered: true
              foreground: root.fg
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              onClicked: root.showSection(index)
            }
          }
        }
      }

      // ---- Texte affiché
      Item {
        id: stage
        anchors { left: parent.left; right: parent.right; top: header.bottom; bottom: footer.top; topMargin: Style.space(14); bottomMargin: Style.space(6) }
        clip: true

        Item {
          id: page
          width: parent.width
          height: parent.height

          ParallelAnimation {
            id: slide
            NumberAnimation { target: page; property: "x"; from: root.slideDirection * Style.space(40); to: 0; duration: 220; easing.type: Easing.OutCubic }
            NumberAnimation { target: page; property: "opacity"; from: 0; to: 1; duration: 220; easing.type: Easing.OutCubic }
            onStarted: flick.contentY = 0
          }

          Flickable {
            id: flick
            anchors.fill: parent
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

            Column {
              id: body
              width: flick.width - Style.space(16)
              spacing: Style.space(4)

              Text {
                width: parent.width
                visible: root.section !== null
                text: root.section ? root.section.label.replace(/ \(autre\)$/, "") : ""
                color: Color.accent
                font.family: root.readingFont
                font.pixelSize: Math.round(root.textSize * 1.35)
                wrapMode: Text.Wrap
              }
              Text {
                width: parent.width
                visible: text !== ""
                text: root.section ? root.section.ref : ""
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                wrapMode: Text.Wrap
              }
              Item { width: 1; height: Style.space(8) }
              Text {
                width: parent.width
                text: root.section ? root.section.html
                  : (root.loading ? "Chargement…"
                    : root.current && root.current.absent ? "L'AELF ne propose pas de textes pour cette date."
                    : (root.error || "Rien pour cet office."))
                textFormat: root.section ? Text.RichText : Text.PlainText
                wrapMode: Text.Wrap
                color: root.section ? root.fg : root.dim
                font.family: root.readingFont
                font.pixelSize: root.textSize
                lineHeight: 1.15
              }
            }
          }
        }
      }

      // ---- Pied : position et raccourcis
      Item {
        id: footer
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: Style.space(18)

        Row {
          anchors { left: parent.left; verticalCenter: parent.verticalCenter }
          spacing: Style.space(5)
          Repeater {
            model: root.sections.length
            delegate: Rectangle {
              required property int index
              anchors.verticalCenter: parent.verticalCenter
              width: index === root.sectionIndex ? Style.space(14) : Style.space(5)
              height: Style.space(5)
              radius: Style.cornerRadius
              color: index === root.sectionIndex ? root.selectedColor : root.line
              Behavior on width { NumberAnimation { duration: 150 } }
            }
          }
        }
        Text {
          anchors { right: parent.right; verticalCenter: parent.verticalCenter }
          text: "← → textes · Tab offices · p s jours · d date"
          color: root.line
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
