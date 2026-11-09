/// Privacy is free and enabled unless the user explicitly switches it off.
enum WatchDisplayPolicy {
    static func shouldConceal(protectScreenPreviews: Bool, isActive: Bool, isLuminanceReduced: Bool) -> Bool {
        protectScreenPreviews && (!isActive || isLuminanceReduced)
    }
}

/// A value snapshot keeps incoming captures independent from the text being read.
struct WatchReadingSnapshot<Line> {
    let lines: [Line]
    let sessionLabel: String
}
