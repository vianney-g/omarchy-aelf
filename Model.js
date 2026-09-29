.pragma library

// Mise en forme des réponses de l'API AELF (https://api.aelf.org) en HTML
// simple, lisible par un Text QML en RichText.

var API = "https://api.aelf.org/v1/"

var OFFICES = [
  { id: "messes",   label: "Messe" },
  { id: "lectures", label: "Lectures" },
  { id: "laudes",   label: "Laudes" },
  { id: "tierce",   label: "Tierce" },
  { id: "sexte",    label: "Sexte" },
  { id: "none",     label: "None" },
  { id: "vepres",   label: "Vêpres" },
  { id: "complies", label: "Complies" }
]

// Couleurs liturgiques renvoyées par informations.couleur.
var COULEURS = {
  blanc: "#f2efe6", vert: "#5a9e5a", violet: "#8e62c0",
  rouge: "#c8413a", rose: "#e592b4", noir: "#6b6b6b"
}

var LECTURES = {
  lecture_1: "Première lecture", lecture_2: "Deuxième lecture",
  lecture_3: "Troisième lecture", lecture_4: "Quatrième lecture",
  lecture_5: "Cinquième lecture", lecture_6: "Sixième lecture",
  lecture_7: "Septième lecture", psaume: "Psaume", cantique: "Cantique",
  sequence: "Séquence", epitre: "Épître", evangile: "Évangile"
}

var RUBRIQUES = {
  introduction: "Introduction", antienne_invitatoire: "Antienne invitatoire",
  psaume_invitatoire: "Psaume invitatoire", hymne: "Hymne",
  pericope: "Parole de Dieu", lecture: "Lecture", repons: "Répons",
  repons_lecture: "Répons", verset_psaume: "Verset",
  titre_patristique: "", texte_patristique: "Lecture patristique",
  repons_patristique: "Répons", te_deum: "Te Deum",
  cantique_zacharie: "Cantique de Zacharie", cantique_mariale: "Cantique de Marie",
  cantique_symeon: "Cantique de Syméon", intercession: "Intercession",
  notre_pere: "Notre Père", oraison: "Oraison", benediction: "Bénédiction",
  hymne_mariale: "Antienne mariale"
}

function isoDate(d) {
  function pad(n) { return n < 10 ? "0" + n : "" + n }
  return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate())
}

function url(office, date, zone) {
  return API + office + "/" + date + "/" + zone
}

function couleur(nom) {
  return COULEURS[nom] || "#9a9a9a"
}

// Numéros de verset en exposant discret, R/ et V/ en couleur.
function nettoie(html, accent, dim) {
  if (!html) return ""
  return String(html)
    .replace(/<span class="verse_number">\s*([^<]*)<\/span>/g,
             '<sup><font color="' + dim + '">$1</font></sup>&nbsp;')
    .replace(/\b([RV])\/\s?/g, '<font color="' + accent + '"><b>$1/</b></font>&nbsp;')
}

function titre(texte, ref, accent, dim) {
  var h = '<p style="margin-top:18px"><font color="' + accent + '"><b>' + texte + '</b></font>'
  if (ref) h += '&nbsp;&nbsp;<font color="' + dim + '">' + ref + '</font>'
  return h + '</p>'
}

function italique(texte, dim) {
  return texte ? '<p><i><font color="' + dim + '">' + texte + '</font></i></p>' : ""
}

function messeHtml(messe, accent, dim) {
  if (!messe || !messe.lectures) return ""
  var h = ""
  for (var i = 0; i < messe.lectures.length; i++) {
    var l = messe.lectures[i]
    var nom = LECTURES[l.type] || l.type
    if (l.type === "evangile" && l.verset_evangile) {
      h += titre("Acclamation", l.ref_verset, accent, dim)
      h += nettoie(l.verset_evangile, accent, dim)
    }
    h += titre(nom, l.ref, accent, dim)
    if (l.refrain_psalmique)
      h += '<p><font color="' + accent + '"><b>R/</b></font>&nbsp;<b>'
         + String(l.refrain_psalmique).replace(/<\/?p>/g, "") + '</b></p>'
    h += italique(l.intro_lue, dim)
    if (l.titre) h += '<p><b>' + l.titre + '</b></p>'
    h += nettoie(l.contenu, accent, dim)
  }
  return h
}

// Un office est un objet ordonné : chaque clé est une rubrique, sa valeur une
// chaîne HTML ou un objet { reference, titre, auteur, texte }.
function officeHtml(office, accent, dim) {
  if (!office) return ""
  var h = ""
  for (var cle in office) {
    var v = office[cle]
    if (v === null || v === undefined || v === "") continue
    if (/^antienne_\d$/.test(cle) || /^antienne_(zacharie|magnificat|symeon)$/.test(cle)) {
      h += '<p style="margin-top:14px"><font color="' + accent + '"><b>Ant.</b></font>&nbsp;<i>'
         + String(v).replace(/<\/?p>/g, "") + '</i></p>'
      continue
    }
    if (cle === "titre_patristique") { h += '<p style="margin-top:18px"><b>' + v + '</b></p>'; continue }
    if (cle === "notre_pere") { h += titre("Notre Père", "", accent, dim); continue }
    var nom = RUBRIQUES[cle]
    if (nom === undefined) nom = /^psaume_\d$/.test(cle) ? "Psaume" : cle
    if (typeof v === "string") {
      if (nom) h += titre(nom, "", accent, dim)
      h += nettoie(v, accent, dim)
    } else {
      var ref = v.reference ? (/^\d/.test(v.reference) ? "Ps " + v.reference : v.reference) : ""
      h += titre(nom || v.titre || "", ref, accent, dim)
      if (v.titre && nom) h += '<p><b>' + v.titre + '</b></p>'
      h += nettoie(v.texte, accent, dim)
      if (v.auteur) h += italique(v.auteur + (v.editeur ? " — " + v.editeur : ""), dim)
    }
  }
  return h
}
