import Foundation

// A scene for each display.
//
// macOS shows the same menu bar items, in the same order, on the menu bar of
// every display: it keeps them on the menu bar of the display in use and
// shows them on the others as well. One display cannot keep an arrangement
// while another shows a different one. What Meno can do is arrange the items
// for the display in use, so a display's scene applies whenever its menu bar
// has the items.
//
// A display's scene is an ordinary rule, "the menu bar is on this display:
// apply the scene", which the Rules pane lists as well. It is not undone when
// the items move to another display: that display's scene takes over, and
// without one the items stay as they are.
extension Array where Element == AutomationRule {
    /// The scene that applies when the menu bar of the display with this
    /// name has the items, if any.
    public func displayScene(for display: String) -> UUID? {
        for rule in self where rule.isEnabled && rule.sceneDisplay == display {
            if case .applyScene(let id) = rule.action { return id }
        }
        return nil
    }

    /// The names of the displays that have a scene, in the order of their
    /// rules.
    public var displaysWithScenes: [String] {
        var names: [String] = []
        for rule in self {
            if let display = rule.sceneDisplay, !names.contains(display) {
                names.append(display)
            }
        }
        return names
    }

    /// The rules with `scene` applying on `display`, or without a scene for
    /// that display when `scene` is nil. An existing rule for the display is
    /// changed in place; `name` names it.
    public func settingDisplayScene(_ scene: UUID?, for display: String, name: String) -> [AutomationRule] {
        guard let scene else {
            return filter { $0.sceneDisplay != display }
        }
        var rules = self
        if let index = rules.firstIndex(where: { $0.sceneDisplay == display }) {
            rules[index].name = name
            rules[index].action = .applyScene(id: scene)
            rules[index].isEnabled = true
            let kept = rules[index].id
            rules.removeAll { $0.sceneDisplay == display && $0.id != kept }
        } else {
            rules.append(AutomationRule(
                name: name,
                conditions: [.menuBarOnDisplay(name: display)],
                action: .applyScene(id: scene),
                revertsWhenInactive: false
            ))
        }
        return rules
    }
}

extension AutomationRule {
    /// The display whose scene this rule is: its only condition is that the
    /// menu bar of that display has the items, and it applies a scene.
    var sceneDisplay: String? {
        guard conditions.count == 1, case .menuBarOnDisplay(let name) = conditions[0],
              case .applyScene = action else { return nil }
        return name
    }
}
