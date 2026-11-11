import Foundation

/// Lightweight helper for the in-app language picker. Persists the user's
/// choice and writes the AppleLanguages override so the next app launch
/// resolves strings in the chosen locale. We deliberately do NOT swap
/// bundles at runtime — that requires fragile swizzling.
enum LanguageManager {
    static let preferredLanguageKey = "preferredLanguage"

    /// Possible values stored under `preferredLanguage`:
    /// - `""`     : follow system
    /// - `"en"`   : English
    /// - `"ja"`   : Japanese
    static func apply(_ code: String) {
        let defaults = UserDefaults.standard
        defaults.set(code, forKey: preferredLanguageKey)
        if code.isEmpty {
            defaults.removeObject(forKey: "AppleLanguages")
        } else {
            defaults.set([code], forKey: "AppleLanguages")
        }
    }

    /// On first launch, default JP-region devices to Japanese so the
    /// onboarding flow is presented in Japanese without any setup.
    static func bootstrapForFirstLaunchIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: preferredLanguageKey) == nil else { return }
        let region: String? = {
            if #available(iOS 16.0, *) {
                return Locale.current.region?.identifier
            } else {
                return Locale.current.regionCode
            }
        }()
        if region == "JP" {
            apply("ja")
        }
    }
}
