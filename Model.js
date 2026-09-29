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

function parseIso(iso) {
  var m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso)
  return m ? new Date(+m[1], +m[2] - 1, +m[3], 12) : null
}

function addDays(iso, n) {
  var d = parseIso(iso)
  d.setDate(d.getDate() + n)
  return isoDate(d)
}

var MOIS = ["janvier", "février", "mars", "avril", "mai", "juin", "juillet",
            "août", "septembre", "octobre", "novembre", "décembre"]

function sansAccents(t) {
  if (typeof t.normalize === "function") return t.normalize("NFD").replace(/[\u0300-\u036f]/g, "")
  return t.replace(/[éèêë]/g, "e").replace(/[àâ]/g, "a").replace(/[ûüù]/g, "u")
          .replace(/[îï]/g, "i").replace(/ô/g, "o").replace(/ç/g, "c")
}

// Date saisie à la main, relative à `ref` (date ISO) :
// « 25/12 », « 25/12/2026 », « 25-12-26 », « 2026-12-25 », « 25 décembre »,
// « 1er mai 2027 », « +3 », « -7 », « demain », « hier », « auj ».
// Renvoie une date ISO, ou "" si la saisie n'est pas comprise.
function parseDate(texte, ref) {
  var t = sansAccents(String(texte).trim().toLowerCase())
  if (t === "") return ""
  if (/^auj/.test(t)) return isoDate(new Date())
  if (t === "demain") return addDays(isoDate(new Date()), 1)
  if (t === "hier") return addDays(isoDate(new Date()), -1)
  var m = /^([+-])\s*(\d+)$/.exec(t)
  if (m) return addDays(ref, (m[1] === "-" ? -1 : 1) * parseInt(m[2], 10))

  var an = parseIso(ref).getFullYear(), mois = -1, jour = -1
  if ((m = /^(\d{4})-(\d{1,2})-(\d{1,2})$/.exec(t))) {
    an = +m[1]; mois = +m[2]; jour = +m[3]
  } else if ((m = /^(\d{1,2})[\/.\-](\d{1,2})(?:[\/.\-](\d{2}|\d{4}))?$/.exec(t))) {
    jour = +m[1]; mois = +m[2]
    if (m[3]) an = m[3].length === 2 ? 2000 + +m[3] : +m[3]
  } else if ((m = /^(\d{1,2})(?:er)?\s+([a-z]+)(?:\s+(\d{4}))?$/.exec(t))) {
    jour = +m[1]
    for (var i = 0; i < MOIS.length; i++)
      if (sansAccents(MOIS[i]).indexOf(m[2]) === 0 && m[2].length >= 3) { mois = i + 1; break }
    if (m[3]) an = +m[3]
  }
  if (mois < 1 || mois > 12 || jour < 1) return ""
  var d = new Date(an, mois - 1, jour, 12)
  if (d.getMonth() !== mois - 1 || d.getDate() !== jour) return ""
  return isoDate(d)
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
    .replace(/<\/p>\s*(<br\s*\/?>\s*)+/g, "</p>")
    .replace(/<span class="verse_number">\s*([^<]*)<\/span>/g,
             '<sup><font color="' + dim + '">$1</font></sup>&nbsp;')
    .replace(/\b([RV])\/\s?/g, '<font color="' + accent + '"><b>$1/</b></font>&nbsp;')
}

function sousTitre(texte, ref, accent, dim) {
  var h = '<p style="margin-top:14px"><font color="' + accent + '"><b>' + texte + '</b></font>'
  if (ref) h += '&nbsp;&nbsp;<font color="' + dim + '">' + ref + '</font>'
  return h + '</p>'
}

function italique(texte, dim) {
  return texte ? '<p><i><font color="' + dim + '">' + texte + '</font></i></p>' : ""
}

function sansP(html) {
  return String(html).replace(/<\/?p>/g, "")
}

function nomLecture(type) {
  var m = /^lecture_(\d)$/.exec(type)
  if (m) return m[1] === "1" ? "1re lecture" : m[1] + "e lecture"
  return LECTURES[type] || type
}

// Découpe d'une messe : une section { label, ref, html } par lecture.
function messeSections(messe, accent, dim) {
  var sections = []
  if (!messe || !messe.lectures) return sections
  var vus = {}
  for (var i = 0; i < messe.lectures.length; i++) {
    var l = messe.lectures[i]
    var label = nomLecture(l.type)
    vus[label] = (vus[label] || 0) + 1
    if (vus[label] > 1) label += " (autre)"
    var h = ""
    if (l.type === "evangile" && l.verset_evangile) {
      h += sousTitre("Acclamation", l.ref_verset, accent, dim)
      h += nettoie(l.verset_evangile, accent, dim)
    }
    h += italique(l.intro_lue, dim)
    if (l.refrain_psalmique)
      h += '<p><font color="' + accent + '"><b>R/</b></font>&nbsp;<b>' + sansP(l.refrain_psalmique) + '</b></p>'
    if (l.titre) h += '<p><b>' + l.titre + '</b></p>'
    h += nettoie(l.contenu, accent, dim)
    sections.push({ label: label, ref: l.ref || "", html: h })
  }
  return sections
}

// Rubriques rattachées à la section précédente (répons, Notre Père…) ou
// gardées pour la suivante (antiennes, verset, titre patristique).
var RATTACHE_AVANT = ["repons", "repons_lecture", "repons_patristique", "notre_pere", "benediction"]
var RATTACHE_APRES = /^(antienne_.*|verset_psaume|titre_patristique)$/

var ETIQUETTES = {
  introduction: "Introduction", psaume_invitatoire: "Invitatoire", hymne: "Hymne",
  pericope: "Parole de Dieu", lecture: "Lecture", texte_patristique: "Lecture patristique",
  te_deum: "Te Deum", cantique_zacharie: "Benedictus", cantique_mariale: "Magnificat",
  cantique_symeon: "Nunc dimittis", intercession: "Intercession", oraison: "Oraison",
  hymne_mariale: "Antienne mariale"
}

function rubrique(cle, v, accent, dim) {
  if (/^antienne_/.test(cle))
    return '<p><font color="' + accent + '"><b>Ant.</b></font>&nbsp;<i>' + sansP(v) + '</i></p>'
  if (cle === "titre_patristique") return '<p><b>' + v + '</b></p>'
  if (cle === "verset_psaume") return nettoie(v, accent, dim)
  if (cle === "notre_pere") return sousTitre("Notre Père", "", accent, dim)
  if (cle === "benediction") return sousTitre("Bénédiction", "", accent, dim) + nettoie(v, accent, dim)
  if (/^repons/.test(cle)) return sousTitre("Répons", "", accent, dim) + nettoie(v, accent, dim)
  if (typeof v === "string") return nettoie(v, accent, dim)
  var h = ""
  if (v.titre) h += '<p><b>' + v.titre + '</b></p>'
  h += nettoie(v.texte, accent, dim)
  if (v.auteur) h += italique(v.auteur + (v.editeur ? " — " + v.editeur : ""), dim)
  return h
}

// Découpe d'un office : chaque psaume, cantique, lecture… devient une section.
function officeSections(office, accent, dim) {
  var sections = []
  if (!office) return sections
  var enAttente = ""
  for (var cle in office) {
    var v = office[cle]
    if (v === null || v === undefined || v === "" || (typeof v === "object" && !v.texte)) continue
    if (RATTACHE_APRES.test(cle)) { enAttente += rubrique(cle, v, accent, dim); continue }
    if (RATTACHE_AVANT.indexOf(cle) >= 0 && sections.length > 0) {
      sections[sections.length - 1].html += rubrique(cle, v, accent, dim)
      continue
    }
    var label = ETIQUETTES[cle] || cle
    var ref = typeof v === "object" && v.reference ? String(v.reference) : ""
    if (/^psaume_\d$/.test(cle)) label = /^\d/.test(ref) ? "Ps " + ref : "Cantique"
    if (/^\d/.test(ref)) ref = "Psaume " + ref
    sections.push({ label: label, ref: ref, html: enAttente + rubrique(cle, v, accent, dim) })
    enAttente = ""
  }
  if (enAttente && sections.length > 0) sections[sections.length - 1].html += enAttente
  return sections
}
