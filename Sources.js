.pragma library

// Pure query-building / JSON-parsing logic for the Research Consensus
// plugin. No QML deps so it's directly Node-testable.
//
// Source: Europe PMC's REST API (europepmc.org) only. It's free, keyless,
// generously rate-limited, and aggregates PubMed/MEDLINE plus PMC and
// several other curated agency sources — MEDLINE indexing is itself the
// predatory-journal filter (journals get vetted before they're indexed),
// so there is deliberately no separate blocklist/allowlist to maintain
// here: trustworthiness comes from only ever querying this one curated
// index. `resultType=core` returns title/journal/year/abstract/DOI/
// pubTypeList/citedByCount in a single response, so one request per tier
// is enough (no second call for abstracts, unlike PubMed's
// esearch->esummary->efetch three-step dance).
//
// Two tiers per search, run as two sequential requests (see Consensus.qml's
// step machine):
//   1. "reviews" - query AND (PUB_TYPE:"meta-analysis" OR PUB_TYPE:
//      "systematic review"), Europe PMC's default relevance ranking.
//      These are already-synthesized "what does the evidence say"
//      documents, so they're the actual consensus signal and always
//      shown first (citedByCount is still surfaced as a badge).
//   2. "other" - the same query with no publication-type restriction, for
//      topics that don't have (or don't yet have) dedicated reviews.
//      Deduped against tier 1 by Europe PMC's own result id.

var API_BASE = "https://www.ebi.ac.uk/europepmc/webservices/rest/search"
var UA = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"

function encodeQueryParams(params) {
  var parts = []
  for (var key in params) {
    parts.push(encodeURIComponent(key) + "=" + encodeURIComponent(params[key]))
  }
  return parts.join("&")
}

// tier: "reviews" | "other"
function searchUrl(query, tier, pageSize) {
  var q = String(query || "").trim()
  if (tier === "reviews") {
    q = q + " AND (PUB_TYPE:\"meta-analysis\" OR PUB_TYPE:\"systematic review\")"
  }
  var params = {
    query: q,
    format: "json",
    resultType: "core",
    pageSize: String(pageSize || 8)
  }
  // Deliberately left on Europe PMC's default relevance sort, not
  // citation count: sorting a broad free-text query by CITED desc was
  // empirically observed to surface globally high-cited but only weakly
  // matching reviews (e.g. a medication-adherence Cochrane review for an
  // "intermittent fasting weight loss" query) ahead of the actually
  // on-topic ones. citedByCount is still shown per result as a badge, just
  // not used to rank.
  return API_BASE + "?" + encodeQueryParams(params)
}

// curl command that fetches a URL and appends "\nHTTPSTATUS:<code>" to
// stdout, so the caller can pull the status back out of one process run.
function curlCommand(url) {
  return ["curl", "-sS", "-m", "15", "-A", UA, "-w", "\nHTTPSTATUS:%{http_code}", url]
}

// Splits curl's stdout (as produced by curlCommand) into {body, status}.
function splitCurlOutput(raw) {
  var text = String(raw || "")
  var marker = text.lastIndexOf("\nHTTPSTATUS:")
  if (marker === -1) return { body: text, status: 0 }
  return {
    body: text.slice(0, marker),
    status: parseInt(text.slice(marker + "\nHTTPSTATUS:".length).trim(), 10) || 0
  }
}

// Europe PMC abstracts carry inline HTML (<h4>Background</h4>...). Strip
// tags and decode the handful of entities that actually show up rather
// than pulling in a full HTML parser for a one-paragraph snippet.
var ENTITIES = { "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&nbsp;": " " }

function stripHtml(text) {
  var out = String(text || "").replace(/<[^>]*>/g, " ")
  out = out.replace(/&[a-zA-Z#0-9]+;/g, function(entity) {
    return ENTITIES[entity] !== undefined ? ENTITIES[entity] : entity
  })
  return out.replace(/\s+/g, " ").trim()
}

function truncate(text, maxLen) {
  var t = String(text || "")
  if (t.length <= maxLen) return t
  return t.slice(0, maxLen - 1).trim() + "…"
}

var REVIEW_TYPES = { "meta-analysis": true, "systematic review": true, "network meta-analysis": true }
var BADGE_PRIORITY = ["Network Meta-Analysis", "Meta-Analysis", "Systematic Review"]

function isReviewType(pubTypeList) {
  if (!pubTypeList || !pubTypeList.length) return false
  for (var i = 0; i < pubTypeList.length; i++) {
    if (REVIEW_TYPES[String(pubTypeList[i]).toLowerCase()]) return true
  }
  return false
}

// One badge label per result, or "" for a plain (non-review) study. Checked
// in specificity order so a network meta-analysis reads as that rather
// than the more generic "Meta-Analysis".
function reviewBadge(pubTypeList) {
  if (!pubTypeList || !pubTypeList.length) return ""
  var lower = pubTypeList.map(function(t) { return String(t).toLowerCase() })
  for (var i = 0; i < BADGE_PRIORITY.length; i++) {
    if (lower.indexOf(BADGE_PRIORITY[i].toLowerCase()) !== -1) return BADGE_PRIORITY[i]
  }
  return ""
}

// The best URL to send the user to: DOI resolver first (works regardless
// of source and lands on the publisher/open-access copy), then Europe
// PMC's own article page, which always exists for anything the search
// returned.
function resultUrl(item) {
  if (item.doi) return "https://doi.org/" + item.doi
  return "https://europepmc.org/article/" + (item.source || "MED") + "/" + item.id
}

// Normalizes one raw Europe PMC `core` result into the plugin's flat
// result shape and tags it with which tier it was fetched under.
function normalizeResult(raw, tier) {
  var pubTypes = raw.pubTypeList && raw.pubTypeList.pubType ? raw.pubTypeList.pubType : []
  var journal = raw.journalInfo && raw.journalInfo.journal ? raw.journalInfo.journal.title : (raw.journalTitle || "")
  var item = {
    id: String(raw.id || raw.pmid || ""),
    source: raw.source || "MED",
    pmid: raw.pmid || "",
    doi: raw.doi || "",
    title: stripHtml(raw.title || "(untitled)"),
    journal: journal || "",
    year: String(raw.pubYear || ""),
    authors: raw.authorString || "",
    citedByCount: Number(raw.citedByCount || 0),
    abstract: truncate(stripHtml(raw.abstractText || ""), 320),
    isReview: tier === "reviews" || isReviewType(pubTypes),
    badge: reviewBadge(pubTypes),
    pubTypes: pubTypes
  }
  item.url = resultUrl(item)
  return item
}

// Parses one Europe PMC search response body into {hitCount, results}.
function parseSearchResponse(jsonText, tier) {
  var data = JSON.parse(jsonText)
  var raw = (data.resultList && data.resultList.result) || []
  var results = []
  for (var i = 0; i < raw.length; i++) results.push(normalizeResult(raw[i], tier))
  return { hitCount: Number(data.hitCount || 0), results: results }
}

// Merges tier-2 ("other studies") results after tier-1 ("reviews"),
// dropping anything tier-2 already surfaced in tier-1.
function mergeTiers(reviews, other) {
  var seen = {}
  for (var i = 0; i < reviews.length; i++) seen[reviews[i].id] = true
  var filteredOther = []
  for (var j = 0; j < other.length; j++) {
    if (!seen[other[j].id]) filteredOther.push(other[j])
  }
  return { reviews: reviews, other: filteredOther }
}

if (typeof module !== "undefined") {
  module.exports = {
    searchUrl: searchUrl,
    curlCommand: curlCommand,
    splitCurlOutput: splitCurlOutput,
    stripHtml: stripHtml,
    truncate: truncate,
    isReviewType: isReviewType,
    reviewBadge: reviewBadge,
    resultUrl: resultUrl,
    normalizeResult: normalizeResult,
    parseSearchResponse: parseSearchResponse,
    mergeTiers: mergeTiers
  }
}
