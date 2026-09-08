import AppKit
import ScreenCaptureKit
import SnipCore

enum SnipError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

struct DisplaySnapshot {
    let screen: NSScreen
    let display: SCDisplay
    let image: CGImage
}

@MainActor
final class CaptureService {
    func content() async throws -> SCShareableContent {
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            throw SnipError.message("请在系统设置 → 隐私与安全性 → 屏幕与系统音频录制中允许 SnipX，然后重新打开应用。")
        }
        return try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    }

    func capture(display: SCDisplay, content: SCShareableContent, region: CGRect? = nil) async throws -> CGImage {
        let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
        let config = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        let size = region?.size ?? filter.contentRect.size
        config.width = max(1, Int((size.width * scale).rounded()))
        config.height = max(1, Int((size.height * scale).rounded()))
        if let region { config.sourceRect = region }
        config.showsCursor = false
        config.captureResolution = .best
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    func snapshots(content: SCShareableContent) async throws -> [DisplaySnapshot] {
        var result: [DisplaySnapshot] = []
        for screen in NSScreen.screens {
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
                  let display = content.displays.first(where: { $0.displayID == id }) else { continue }
            let image = try await capture(display: display, content: content)
            result.append(DisplaySnapshot(screen: screen, display: display, image: image))
        }
        guard !result.isEmpty else { throw SnipError.message("没有可截图的屏幕。") }
        return result
    }

    func capture(window: SCWindow) async throws -> CGImage {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        config.width = max(1, Int(filter.contentRect.width * CGFloat(filter.pointPixelScale)))
        config.height = max(1, Int(filter.contentRect.height * CGFloat(filter.pointPixelScale)))
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        config.captureResolution = .best
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }
}
