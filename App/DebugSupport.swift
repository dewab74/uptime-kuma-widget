#if DEBUG
    import Foundation
    import KumaKit

    /// Debug-build launch arguments, for development without clicking through
    /// Settings (the App Group container is closed to other processes):
    ///
    ///     open "Kuma Status.app" --args -KumaServer http://127.0.0.1:3901 -KumaSlug home -KumaInterval 30
    ///
    /// Add `-KumaVerifyCertificate NO` for a self-signed certificate.
    enum DebugSupport {
        static var launchConfiguration: KumaConfiguration? {
            let defaults = UserDefaults.standard
            guard let server = defaults.string(forKey: "KumaServer") else { return nil }
            let interval = defaults.double(forKey: "KumaInterval")
            let verify =
                defaults.object(forKey: "KumaVerifyCertificate") == nil
                || defaults.bool(forKey: "KumaVerifyCertificate")
            return try? KumaConfiguration.parse(
                address: server, slug: defaults.string(forKey: "KumaSlug") ?? "",
                pollInterval: interval > 0 ? interval : KumaConfiguration.defaultPollInterval,
                verifyCertificate: verify)
        }
    }
#endif
