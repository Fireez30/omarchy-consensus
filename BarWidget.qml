import QtQuick
import qs.Ui

// Bar icon that toggles the Research Consensus overlay open/closed.
// Deliberately bar-only — this plugin has no MenuRegistrar.qml and is not
// registered in the root Omarchy menu, per request. Icon is the Nerd Font
// "flask" glyph (verified to render correctly in the bar's default
// JetBrainsMono Nerd Font via a throwaway PanelWindow harness — a plain
// emoji ("\U0001F52C" etc.) did not render at all under Text.NativeRendering
// with that font).
BarWidget {
  id: root
  moduleName: "omarchy-consensus"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uf0c3"
    horizontalMargin: 7.5
    tooltipText: "Research Consensus"
    onPressed: function(button) {
      if (!root.bar) return
      root.bar.run("omarchy-shell shell toggle omarchy-consensus")
    }
  }
}
