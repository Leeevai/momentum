import Foundation

/// The categories a macOS Focus asks Momentum to show (System Settings → Focus → Focus filters).
///
/// Stored per Mac, beside the data file, since a Focus belongs to the device rather than the data.
public struct FocusFilter: Codable, Equatable, Sendable {
    /// Categories to show; uncategorized goals are named "Goals".
    public var categories: Set<String>
    /// The Focus's name, for the banner ("Work Focus").
    public var focusName: String?

    public init(categories: Set<String>, focusName: String? = nil) {
        self.categories = categories
        self.focusName = focusName
    }

    /// The name a goal's category goes by in a filter.
    public static func categoryName(of goal: Goal) -> String {
        goal.category.isEmpty ? "Goals" : goal.category
    }

    public func includes(_ goal: Goal) -> Bool {
        categories.isEmpty || categories.contains(Self.categoryName(of: goal))
    }

    /// The goals that pass the filter, keeping a running timer's goal visible whatever it is.
    public func apply(to goals: [Goal], session: FocusSession?) -> [Goal] {
        goals.filter { includes($0) || $0.id == session?.goalID }
    }
}

extension AppData {
    /// Every category in use, in goal order, for filter and editor choices.
    public var categoryNames: [String] {
        var names: [String] = []
        for goal in goals where !goal.isArchived {
            let name = FocusFilter.categoryName(of: goal)
            if !names.contains(name) { names.append(name) }
        }
        return names
    }
}
