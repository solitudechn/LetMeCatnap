import AppKit
import Sparkle

/// Thin wrapper around Sparkle's standard updater.
///
/// Everything that used to live in a hand-written updater — finding the release,
/// downloading it, verifying it, replacing the bundle, asking for an admin
/// password when `/Applications` is not writable — is now Sparkle's job. What
/// stays here is the app's own wiring: start it once the app has launched, hand
/// the menu item a target, and write the outcome into the app's log so a failed
/// check leaves a trace the user can send in.
///
/// Contract with the release pipeline (see `docs/releasing.md`): every release
/// must publish a signed `appcast.xml`, an `iCHR.zip` of the same build, and the
/// EdDSA signature in the appcast must match `SUPublicEDKey` in `Info.plist`.
@MainActor
final class Updater: NSObject, SPUUpdaterDelegate {
    static let shared = Updater()

    private var controller: SPUStandardUpdaterController?

    private override init() {
        super.init()
    }

    /// Starts the updater. Must be called from `applicationDidFinishLaunching`:
    /// Sparkle refuses to schedule checks before the app has finished launching.
    func start() {
        guard controller == nil else { return }

        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )

        let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? "<missing>"
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        Log.info("updater started (feed: \(feed), signing key: \(key == nil ? "MISSING" : "present"))")
        if key?.isEmpty != false {
            // Sparkle rejects every download without a signing key. Say so in the
            // log instead of letting the check fail with a generic error later.
            Log.error("updater: SUPublicEDKey is absent — automatic updates cannot be verified")
        }
    }

    /// `true` while Sparkle is not already busy with a check or an install.
    var canCheckForUpdates: Bool {
        controller?.updater.canCheckForUpdates ?? false
    }

    /// Menu / About-window action. Sparkle brings its own UI.
    @objc func checkForUpdates(_ sender: Any?) {
        Log.info("update check requested by user")
        controller?.checkForUpdates(sender)
    }

    // MARK: - SPUUpdaterDelegate

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        Log.info("update available: \(item.displayVersionString) (\(item.versionString))")
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        Log.info("no update available")
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: Error?
    ) {
        guard let error else {
            Log.info("update cycle finished without error")
            return
        }
        Log.error("update cycle failed: \(error.localizedDescription)")
    }

    func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        Log.info("update downloaded: \(item.displayVersionString)")
    }

    func updater(_ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: Error) {
        Log.error("update download failed: \(error.localizedDescription)")
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        Log.info("installing update \(item.displayVersionString)")
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        Log.error("updater aborted: \(error.localizedDescription)")
    }
}
