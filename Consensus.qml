import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "Sources.js" as Sources

// Research Consensus overlay: type a topic, press Enter, and it queries
// Europe PMC in two tiers — meta-analyses/systematic reviews first (the
// actual "what does the evidence say" signal), then other studies as a
// fallback for topics without dedicated reviews yet. No predatory-journal
// blocklist: Europe PMC only indexes MEDLINE/PMC and other curated
// agency sources, so restricting the search to it *is* the quality filter
// (see Sources.js's header comment). Structurally: a PanelWindow +
// BorderSurface card driving a sequential curl step machine, but with a
// results list instead of a single terminal action.
//
// Deliberately bar-only: there is no MenuRegistrar.qml here and this
// plugin is not registered in the root Omarchy menu — it's reached only
// via its bar icon (BarWidget.qml), per request.
Item {
  id: root

  property string dataDir: ""
  property var shell: null
  property var manifest: null

  property bool opened: false
  property string queryText: ""
  property string lastExecutedQuery: ""
  property string statusMessage: "Search meta-analyses & systematic reviews (Europe PMC)."
  property bool busy: false
  property string stage: "" // "reviews" | "other"

  property var reviews: []
  property var other: []
  property var renderRows: []
  property int selectedIndex: -1
  property bool cursorActive: false
  property bool searched: false

  // TextField .text is one-way bound from this and reconciled on external
  // change only, because an imperative `text =` assignment (what typing
  // does) silently tears off a declarative `text: root.queryText` binding.
  onQueryTextChanged: if (queryField) queryField.syncFromRoot()

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  property int contentSpacing: Style.spacing.md
  property int cardWidth: Math.min(Style.space(680), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(560), panel.height - Style.gapsOut * 2)
  property int rowHeight: Style.space(84)

  function open(payloadJson) {
    root.opened = true
    Qt.callLater(function() { queryField.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "faeres.omarchy-consensus")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  // ------------------------------------------------------------ search

  function buildRenderRows() {
    var rows = []
    for (var i = 0; i < root.reviews.length; i++) rows.push({ kind: "result", item: root.reviews[i] })
    if (root.other.length > 0) {
      rows.push({ kind: "separator", label: "Other studies" })
      for (var j = 0; j < root.other.length; j++) rows.push({ kind: "result", item: root.other[j] })
    }
    root.renderRows = rows
    root.cursorActive = rows.length > 0
    root.selectedIndex = rows.length > 0 ? root.firstSelectableIndex() : -1
  }

  function firstSelectableIndex() {
    for (var i = 0; i < root.renderRows.length; i++) if (root.renderRows[i].kind === "result") return i
    return -1
  }

  function selectDelta(delta) {
    var rows = root.renderRows
    if (!rows.length) return
    var idx = root.selectedIndex
    for (var step = 0; step < rows.length; step++) {
      idx = (idx + delta + rows.length) % rows.length
      if (rows[idx].kind === "result") { root.selectedIndex = idx; root.cursorActive = true; return }
    }
  }

  function openResult(item) {
    if (!item) return
    Util.execArgv(["omarchy-launch-browser", item.url])
    root.statusMessage = "Opened “" + item.title + "” in the browser."
  }

  function openSelected() {
    if (root.selectedIndex < 0 || root.selectedIndex >= root.renderRows.length) return
    var row = root.renderRows[root.selectedIndex]
    if (row.kind === "result") root.openResult(row.item)
  }

  function summaryMessage() {
    var reviewCount = root.reviews.length
    var otherCount = root.other.length
    if (reviewCount === 0 && otherCount === 0)
      return "No results for “" + root.lastExecutedQuery + "” on Europe PMC."
    var parts = []
    if (reviewCount > 0) parts.push(reviewCount + " meta-anal" + (reviewCount === 1 ? "ysis" : "yses") + "/systematic review" + (reviewCount === 1 ? "" : "s"))
    if (otherCount > 0) parts.push(otherCount + " other stud" + (otherCount === 1 ? "y" : "ies"))
    return parts.join(" · ") + " found."
  }

  function executeSearch() {
    var raw = root.queryText.trim()
    if (!raw) return

    // Enter on an unchanged, already-completed query opens the highlighted
    // result instead of re-running the same search.
    if (raw === root.lastExecutedQuery && root.searched && !root.busy) {
      root.openSelected()
      return
    }

    root.lastExecutedQuery = raw
    root.busy = true
    root.searched = true
    root.reviews = []
    root.other = []
    root.renderRows = []
    root.selectedIndex = -1
    root.statusMessage = "Searching Europe PMC for meta-analyses & systematic reviews…"
    root.runStage("reviews", raw)
  }

  function runStage(stage, query) {
    root.stage = stage
    var url = Sources.searchUrl(query, stage, stage === "reviews" ? 8 : 6)
    fetchProc.command = Sources.curlCommand(url)
    fetchProc.running = true
  }

  function handleFetchResult(raw) {
    var parsed = Sources.splitCurlOutput(raw)
    if (parsed.status !== 200) {
      root.busy = false
      root.statusMessage = "Europe PMC returned an error (HTTP " + parsed.status + ")."
      return
    }

    var parsedBody
    try {
      parsedBody = Sources.parseSearchResponse(parsed.body, root.stage)
    } catch (e) {
      root.busy = false
      root.statusMessage = "Couldn't read Europe PMC's response."
      return
    }

    if (root.stage === "reviews") {
      root.reviews = parsedBody.results
      root.statusMessage = "Searching Europe PMC for other studies…"
      root.runStage("other", root.lastExecutedQuery)
      return
    }

    // stage === "other"
    var merged = Sources.mergeTiers(root.reviews, parsedBody.results)
    root.reviews = merged.reviews
    root.other = merged.other
    root.busy = false
    root.buildRenderRows()
    root.statusMessage = root.summaryMessage()
  }

  Process {
    id: fetchProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.handleFetchResult(text)
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 && root.busy) {
        root.busy = false
        root.statusMessage = "Couldn't reach Europe PMC — check your connection."
      }
    }
  }

  PanelWindow {
    id: panel

    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-consensus"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: root.contentSpacing

        // -------------------------------------------------- header

        Item {
          width: parent.width
          height: root.headerHeight

          Text {
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            text: "Research Consensus"
          }
        }

        // --------------------------------------------------- query

        TextField {
          id: queryField
          width: parent.width
          foreground: root.foreground
          property bool syncingText: false
          placeholderText: "Search a topic (e.g. “vitamin D supplementation”)…"

          function syncFromRoot() {
            if (text === root.queryText) return
            syncingText = true
            text = root.queryText
            syncingText = false
          }

          Component.onCompleted: syncFromRoot()
          onTextChanged: if (!syncingText) root.queryText = text
          onAccepted: root.executeSearch()

          Keys.onEscapePressed: root.dismiss()
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Up) {
              root.selectDelta(-1)
              event.accepted = true
            } else if (event.key === Qt.Key_Down) {
              root.selectDelta(1)
              event.accepted = true
            }
          }
        }

        Text {
          width: parent.width
          visible: root.statusMessage !== ""
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
          text: root.statusMessage
          color: root.foreground
          opacity: 0.75
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        // ---------------------------------------------------- results

        ListView {
          id: resultsList
          width: parent.width
          height: parent.height - root.headerHeight - queryField.height - Style.space(20) - root.contentSpacing * 3
          visible: root.renderRows.length > 0
          model: root.renderRows
          clip: true
          spacing: Style.space(4)
          boundsBehavior: Flickable.StopAtBounds
          currentIndex: root.selectedIndex
          highlightMoveDuration: 80
          onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)

          delegate: Loader {
            required property int index
            required property var modelData
            width: resultsList.width - Style.space(10)
            sourceComponent: modelData.kind === "separator" ? separatorComponent : resultComponent

            property var rowModelData: modelData
            property int rowIndex: index

            onLoaded: {
              item.rowModelData = rowModelData
              item.rowIndex = rowIndex
            }
          }
        }
      }
    }
  }

  Component {
    id: separatorComponent

    Item {
      property var rowModelData: null
      property int rowIndex: -1
      height: Style.space(28)
      width: parent ? parent.width : 0

      Text {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        textFormat: Text.PlainText
        text: rowModelData ? rowModelData.label : ""
        color: root.foreground
        opacity: 0.6
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }
    }
  }

  Component {
    id: resultComponent

    Rectangle {
      id: rowDelegate
      property var rowModelData: null
      property int rowIndex: -1
      readonly property var resultItem: rowModelData ? rowModelData.item : null
      readonly property bool hasCursor: root.cursorActive && rowIndex === root.selectedIndex

      width: parent ? parent.width : 0
      height: root.rowHeight
      radius: root.cornerRadius
      color: hasCursor ? root.selectedBackground : "transparent"

      Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.space(10)
        anchors.rightMargin: Style.space(10)
        spacing: Style.space(2)

        Row {
          width: parent.width
          spacing: Style.space(6)

          Rectangle {
            visible: rowDelegate.resultItem && rowDelegate.resultItem.badge !== ""
            radius: Style.space(4)
            color: Style.normalFillFor(rowDelegate.hasCursor ? root.selectedText : root.foreground, Color.accent)
            width: badgeText.implicitWidth + Style.space(10)
            height: badgeText.implicitHeight + Style.space(4)
            anchors.verticalCenter: parent.verticalCenter

            Text {
              id: badgeText
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: rowDelegate.resultItem ? rowDelegate.resultItem.badge : ""
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              color: rowDelegate.hasCursor ? root.selectedText : root.foreground
            }
          }

          Text {
            width: parent.width - (rowDelegate.resultItem && rowDelegate.resultItem.badge !== "" ? badgeText.implicitWidth + Style.space(16) : 0)
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            elide: Text.ElideRight
            text: rowDelegate.resultItem ? rowDelegate.resultItem.title : ""
            color: rowDelegate.hasCursor ? root.selectedText : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          elide: Text.ElideRight
          text: rowDelegate.resultItem
            ? [rowDelegate.resultItem.journal, rowDelegate.resultItem.year, rowDelegate.resultItem.citedByCount > 0 ? (rowDelegate.resultItem.citedByCount + " citations") : ""].filter(function(s) { return s !== "" }).join(" · ")
            : ""
          color: rowDelegate.hasCursor ? root.selectedText : root.foreground
          opacity: 0.65
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          maximumLineCount: 2
          elide: Text.ElideRight
          text: rowDelegate.resultItem ? rowDelegate.resultItem.abstract : ""
          color: rowDelegate.hasCursor ? root.selectedText : root.foreground
          opacity: 0.6
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onContainsMouseChanged: if (containsMouse) {
          root.cursorActive = true
          root.selectedIndex = rowDelegate.rowIndex
        }
        onClicked: root.openResult(rowDelegate.resultItem)
      }
    }
  }
}
