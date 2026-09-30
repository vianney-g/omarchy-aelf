import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Vue de lecture : jour liturgique, onglets messe / offices, carrousel des
// textes. Utilisée dans le panneau de la barre et dans la fenêtre détachée.
PanelKeyCatcher {
  id: reader
  // État partagé : l'élément Panel (date, office, cache…). Le panneau et la
  // fenêtre détachée affichent chacun un Reader branché sur le même état.
  required property var s
  property bool windowed: false
  signal dismissRequested()
  signal detachRequested()

  blocked: reader.s.editingDate
  onCloseRequested: reader.dismissRequested()
  onTabRequested: function(direction) { reader.s.showOffice(reader.s.officeIndex + direction) }
  onMoveRequested: function(dx, dy) {
    if (dx !== 0) reader.s.showSection(reader.s.sectionIndex + dx)
    else flick.scrollBy(dy * 60)
  }
  onActivateRequested: flick.scrollBy(flick.height * 0.85)
  onTextKey: function(t) {
    if (t === "r" || t === "R") reader.s.reload()
    else if (t === "p" || t === "P") reader.s.setDate(Model.addDays(reader.s.date, -1))
    else if (t === "s" || t === "S") reader.s.setDate(Model.addDays(reader.s.date, 1))
    else if (t === "a" || t === "A") reader.s.setDate(reader.s.today)
    else if (t === "d" || t === "D") reader.beginEdit()
    else if (t === "w" || t === "W") reader.detachRequested()
    else if (t >= "1" && t <= "8") reader.s.showOffice(parseInt(t, 10) - 1)
    else if ((t === "m" || t === "M") && reader.s.messes.length > 1)
      reader.s.showMesse((reader.s.messeShown + 1) % reader.s.messes.length)
  }


  // Saisie de la date : chaque vue gère son propre champ.
  function beginEdit() {
    reader.s.startEditDate()
    Qt.callLater(function() {
      dateField.text = ""
      dateField.forceActiveFocus()
    })
  }
  function endEdit() {
    reader.s.stopEditDate()
    Qt.callLater(function() { reader.forceActiveFocus() })
  }
  function commitEdit() {
    if (dateField.text.trim() === "") { endEdit(); return }
    if (reader.s.goTo(dateField.text)) endEdit()
    else reader.s.dateError = "Date non comprise : essayez 25/12, 8 décembre, +7…"
  }

  // Changement de texte, d'office ou de date : petite animation de glissement.
  Connections {
    target: reader.s
    function onSlid() { slide.restart() }
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
      Item {
        width: parent.width
        height: Math.max(dateRow.implicitHeight, detachButton.implicitHeight)

        Row {
          id: dateRow
          spacing: Style.spacing.sm
  
          Button {
            anchors.verticalCenter: parent.verticalCenter
            text: "‹"
            tooltipText: "Jour précédent (p)"
            foreground: reader.s.fg
            fontFamily: reader.s.fontFamily
            fontSize: Style.font.body
            verticalPadding: Style.spacing.xxs
            onClicked: reader.s.setDate(Model.addDays(reader.s.date, -1))
          }
  
          Item {
            anchors.verticalCenter: parent.verticalCenter
            width: reader.s.editingDate ? dateField.width : dateLabel.implicitWidth
            height: reader.s.editingDate ? dateField.height : dateLabel.implicitHeight
  
            Text {
              id: dateLabel
              anchors.verticalCenter: parent.verticalCenter
              visible: !reader.s.editingDate
              text: Qt.locale("fr_FR").toString(new Date(reader.s.date + "T12:00:00"), "dddd d MMMM yyyy")
              color: dateHover.hovered ? reader.s.fg : reader.s.dim
              font.family: reader.s.fontFamily
              font.pixelSize: Style.font.caption
              font.capitalization: Font.AllUppercase
              font.letterSpacing: 1
              HoverHandler { id: dateHover; cursorShape: Qt.PointingHandCursor }
              TapHandler { onTapped: reader.beginEdit() }
            }
  
            TextField {
              id: dateField
              visible: reader.s.editingDate
              width: Style.space(220)
              placeholderText: "25/12, 8 décembre, +7, demain…"
              foreground: reader.s.fg
              font.family: reader.s.fontFamily
              font.pixelSize: Style.font.caption
              onActiveFocusChanged: if (!activeFocus && reader.s.editingDate) reader.endEdit()
              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) { reader.endEdit(); event.accepted = true }
                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { reader.commitEdit(); event.accepted = true }
              }
            }
          }
  
          Button {
            anchors.verticalCenter: parent.verticalCenter
            text: "›"
            tooltipText: "Jour suivant (s)"
            foreground: reader.s.fg
            fontFamily: reader.s.fontFamily
            fontSize: Style.font.body
            verticalPadding: Style.spacing.xxs
            onClicked: reader.s.setDate(Model.addDays(reader.s.date, 1))
          }
  
          Button {
            anchors.verticalCenter: parent.verticalCenter
            visible: reader.s.date !== reader.s.today && !reader.s.editingDate
            text: "Aujourd'hui"
            tooltipText: "Revenir à aujourd'hui (a)"
            bordered: true
            foreground: reader.s.fg
            fontFamily: reader.s.fontFamily
            fontSize: Style.font.caption
            verticalPadding: Style.spacing.xxs
            onClicked: reader.s.setDate(reader.s.today)
          }
  
          Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: reader.s.editingDate && reader.s.dateError !== ""
            text: reader.s.dateError
            color: Color.urgent
            font.family: reader.s.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        // Détacher le panneau dans une fenêtre, ou l'y rattacher (w).
        Button {
          id: detachButton
          anchors { right: parent.right; verticalCenter: parent.verticalCenter }
          iconText: reader.windowed ? "󱔓" : "󰏌"
          text: reader.windowed ? "Rattacher" : "Détacher"
          tooltipText: reader.windowed ? "Revenir au panneau de la barre (w)" : "Ouvrir dans une fenêtre (w)"
          foreground: reader.s.fg
          fontFamily: reader.s.fontFamily
          fontSize: Style.font.caption
          verticalPadding: Style.spacing.xxs
          onClicked: reader.detachRequested()
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
          color: Model.couleur(reader.s.info ? reader.s.info.couleur : "")
          border.width: Style.normalBorderWidth
          border.color: reader.s.line
          visible: reader.s.info !== null
        }
        Text {
          id: feastTitle
          width: parent.width - Style.space(12)
          text: reader.s.info ? (reader.s.info.ligne1 || reader.s.info.jour_liturgique_nom || "")
            : reader.s.dateAbsent ? "Pas de textes AELF pour ce jour"
            : (reader.s.error || "Chargement…")
          color: reader.s.fg
          font.family: reader.s.readingFont
          font.pixelSize: Style.font.display
          wrapMode: Text.Wrap
        }
      }

      Text {
        width: parent.width
        visible: text !== ""
        text: reader.s.info ? [reader.s.info.ligne2, reader.s.info.ligne3].filter(function(s) { return s }).join(" · ") : ""
        color: reader.s.dim
        font.family: reader.s.fontFamily
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
        color: reader.s.line
      }

      Row {
        anchors.fill: parent

        Repeater {
          model: Model.OFFICES
          delegate: Item {
            id: tab
            required property var modelData
            required property int index
            readonly property bool selected: index === reader.s.officeIndex
            width: parent.width / Model.OFFICES.length
            height: parent.height

            // Coins arrondis en haut seulement (si le thème en met) :
            // le bas est recouvert.
            Rectangle {
              anchors.fill: parent
              radius: Style.cornerRadius
              color: tabHover.hovered ? Style.hoverFillFor(reader.s.fg, Color.accent)
                : tab.selected ? Style.selectedFillFor(reader.s.fg, Color.accent)
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
              color: reader.s.selectedColor
              visible: tab.selected
            }
            Text {
              anchors.centerIn: parent
              text: tab.modelData.label
              color: tab.selected ? reader.s.selectedColor : reader.s.dim
              font.family: reader.s.fontFamily
              font.pixelSize: Style.font.body
              font.bold: tab.selected
            }
            HoverHandler { id: tabHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: reader.s.showOffice(tab.index) }
          }
        }
      }
    }

    // ---- Choix de la messe, les jours où il y en a plusieurs
    Flow {
      width: parent.width
      spacing: Style.spacing.md
      visible: reader.s.officeId === "messes" && reader.s.messes.length > 1

      Repeater {
        model: reader.s.officeId === "messes" ? reader.s.messes : []
        delegate: Button {
          required property var modelData
          required property int index
          text: modelData.nom
          selected: index === reader.s.messeShown
          foreground: reader.s.fg
          fontFamily: reader.s.fontFamily
          fontSize: Style.font.caption
          onClicked: reader.s.showMesse(index)
        }
      }
    }

    // ---- Carrousel des textes
    Item {
      width: parent.width
      height: Style.spacing.controlHeight
      visible: reader.s.sections.length > 0

      Button {
        id: prevArrow
        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
        text: "‹"
        foreground: reader.s.fg
        fontFamily: reader.s.fontFamily
        fontSize: Style.font.heading
        enabled: reader.s.sectionIndex > 0
        opacity: enabled ? 1 : 0.3
        onClicked: reader.s.showSection(reader.s.sectionIndex - 1)
      }
      Button {
        id: nextArrow
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        text: "›"
        foreground: reader.s.fg
        fontFamily: reader.s.fontFamily
        fontSize: Style.font.heading
        enabled: reader.s.sectionIndex < reader.s.sections.length - 1
        opacity: enabled ? 1 : 0.3
        onClicked: reader.s.showSection(reader.s.sectionIndex + 1)
      }

      ListView {
        id: chips
        anchors { left: prevArrow.right; right: nextArrow.left; top: parent.top; bottom: parent.bottom; leftMargin: Style.spacing.sm; rightMargin: Style.spacing.sm }
        orientation: ListView.Horizontal
        spacing: Style.spacing.md
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: reader.s.sections
        currentIndex: reader.s.sectionIndex

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
          selected: index === reader.s.sectionIndex
          bordered: true
          foreground: reader.s.fg
          fontFamily: reader.s.fontFamily
          fontSize: Style.font.caption
          onClicked: reader.s.showSection(index)
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
        NumberAnimation { target: page; property: "x"; from: reader.s.slideDirection * Style.space(40); to: 0; duration: 220; easing.type: Easing.OutCubic }
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
            visible: reader.s.section !== null
            text: reader.s.section ? reader.s.section.label.replace(/ \(autre\)$/, "") : ""
            color: Color.accent
            font.family: reader.s.readingFont
            font.pixelSize: Math.round(reader.s.textSize * 1.35)
            wrapMode: Text.Wrap
          }
          Text {
            width: parent.width
            visible: text !== ""
            text: reader.s.section ? reader.s.section.ref : ""
            color: reader.s.dim
            font.family: reader.s.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.Wrap
          }
          Item { width: 1; height: Style.space(8) }
          Text {
            width: parent.width
            text: reader.s.section ? reader.s.section.html
              : (reader.s.loading ? "Chargement…"
                : reader.s.current && reader.s.current.absent ? "L'AELF ne propose pas de textes pour cette date."
                : (reader.s.error || "Rien pour cet office."))
            textFormat: reader.s.section ? Text.RichText : Text.PlainText
            wrapMode: Text.Wrap
            color: reader.s.section ? reader.s.fg : reader.s.dim
            font.family: reader.s.readingFont
            font.pixelSize: reader.s.textSize
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
        model: reader.s.sections.length
        delegate: Rectangle {
          required property int index
          anchors.verticalCenter: parent.verticalCenter
          width: index === reader.s.sectionIndex ? Style.space(14) : Style.space(5)
          height: Style.space(5)
          radius: Style.cornerRadius
          color: index === reader.s.sectionIndex ? reader.s.selectedColor : reader.s.line
          Behavior on width { NumberAnimation { duration: 150 } }
        }
      }
    }
    Text {
      anchors { right: parent.right; verticalCenter: parent.verticalCenter }
      text: "← → textes · Tab offices · p s jours · d date · w fenêtre"
      color: reader.s.line
      font.family: reader.s.fontFamily
      font.pixelSize: Style.font.caption
    }
  }
}
