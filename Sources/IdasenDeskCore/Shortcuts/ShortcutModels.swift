import Foundation

public struct ShortcutModifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let command = ShortcutModifiers(rawValue: 1 << 0)
    public static let option = ShortcutModifiers(rawValue: 1 << 1)
    public static let control = ShortcutModifiers(rawValue: 1 << 2)
    public static let shift = ShortcutModifiers(rawValue: 1 << 3)
}

public enum ShortcutAction: Codable, Hashable, Sendable, Identifiable {
    case moveToSit
    case moveToStand
    case stop
    case showMenu
    case moveToCustomHeight(DeskHeight)

    public var id: String {
        switch self {
        case .moveToSit:
            return "moveToSit"
        case .moveToStand:
            return "moveToStand"
        case .stop:
            return "stop"
        case .showMenu:
            return "showMenu"
        case .moveToCustomHeight(let height):
            return "moveToCustomHeight-\(height.centimeters)"
        }
    }

    public var displayName: String {
        switch self {
        case .moveToSit:
            return "Move to sit"
        case .moveToStand:
            return "Move to stand"
        case .stop:
            return "Stop"
        case .showMenu:
            return "Show menu"
        case .moveToCustomHeight(let height):
            return "Move to \(Int(height.centimeters.rounded())) cm"
        }
    }
}

public struct ShortcutBinding: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var action: ShortcutAction
    public var keyCode: UInt32
    public var modifiers: ShortcutModifiers
    public var isEnabled: Bool

    public init(
        id: String,
        action: ShortcutAction,
        keyCode: UInt32,
        modifiers: ShortcutModifiers,
        isEnabled: Bool = false
    ) {
        self.id = id
        self.action = action
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.isEnabled = isEnabled
    }

    public static let defaults: [ShortcutBinding] = [
        ShortcutBinding(id: "move-sit", action: .moveToSit, keyCode: 1, modifiers: [.command, .option]),
        ShortcutBinding(id: "move-stand", action: .moveToStand, keyCode: 13, modifiers: [.command, .option]),
        ShortcutBinding(id: "stop", action: .stop, keyCode: 49, modifiers: [.command, .option]),
        ShortcutBinding(id: "show-menu", action: .showMenu, keyCode: 8, modifiers: [.command, .option])
    ]
}

public enum ShortcutValidation {
    public static func duplicates(in bindings: [ShortcutBinding]) -> [ShortcutBinding] {
        var seen = Set<String>()
        var duplicates = [ShortcutBinding]()

        for binding in bindings where binding.isEnabled {
            let key = "\(binding.keyCode)-\(binding.modifiers.rawValue)"
            if seen.contains(key) {
                duplicates.append(binding)
            } else {
                seen.insert(key)
            }
        }

        return duplicates
    }
}

