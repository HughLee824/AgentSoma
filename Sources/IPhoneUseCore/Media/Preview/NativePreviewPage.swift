import Foundation

private final class NativePreviewAssetAnchor: NSObject {}

// Artwork is loaded once, outside the video encoder. No network fetch, source
// path embedded in the binary, or dependency on the caller's working directory.
enum NativePreviewPage {
    // A symlink-launched CLI can have no executable URL on its class bundle.
    // Keep the class bundle for XCTest, then resolve the CLI's main entry point.
    static func assetDirectory(
        executable: URL? = Bundle(for: NativePreviewAssetAnchor.self).executableURL
            ?? Bundle.main.executableURL
    ) -> URL? {
        guard let executable else { return nil }
        let binary = executable.resolvingSymlinksInPath()
        let installed = binary.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("libexec/iphone-use/preview")
        if FileManager.default.fileExists(atPath: installed.appendingPathComponent("catalog.json").path) {
            return installed
        }
        var directory = binary.deletingLastPathComponent()
        // SwiftPM CLI and XCTest layouts have different depths under .build.
        for _ in 0..<8 {
            if directory.lastPathComponent == ".build" {
                return directory.deletingLastPathComponent().appendingPathComponent("assets/preview")
            }
            directory.deleteLastPathComponent()
        }
        return nil
    }

    #if DEBUG
        static let appearanceComparisonEnabled = true
    #else
        static let appearanceComparisonEnabled = false
    #endif

    // Byte-for-byte copy of assets/brand/favicon-64.png, embedded for relocatable/offline previews.
    static let faviconPNG = Data(
        base64Encoded:
            """
            iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAIAAAAlC+aJAAAACXBIWXMAACxLAAAsSwGlPZapAAADJ0lEQVRoge2asU/qUBTG+1+U\
            hsdi7GBg0RKMiYsTEzH+BRgTti7GmLK4PK2DY4erHSjYhDBZk0ZkIQFi4qSDUQZkYQdtTTVWrd6X6HtNnwhUfZf25vFthHO+nF+5\
            kHDPR0DMRUDMRUDMRcD/GcAwjEqlIkmSIAg/PylBECRJqlarhmF4ANDpdDiOC4VC5LcVCoU4jru6uhoeQKPRYBiG/KdiGKbRaAwD\
            QNf1WCxGIlAsFtM0DTnA+vo6iUw8z6MFsCyLpumBcywuLiqKojqkKEoymRzYSNP08/MzQoDz83M3D/Lm5qa7V9M0N731eh0hwMHB\
            gZshZFm2LMvZaFnW7u6um97Dw0OEAPl8nkSsQqGAECCXy6EGkGUZIUAmk0ENIEkSQoCdnR3UAKIoIgQAAKAGAACMAHpr9AkMFhgd\
            oX4aHaHf+vGqP69wO0Isy5qmeX9/z7IslgCdTufNrd1u4wcwNjZmu5mmiR8AwzC2m67r+AHE43Hbrdls4gewtLRku1WrVfwAtre3\
            bTdRFPEDOD09td3w+xkdHx9/enqy3T68HfM1AMdx/b/BpM8BnFcmm5ubmAHMz8/bPo+Pj5FIBCeAQCBwcnJi+6iq2qsS+BNgeXnZ\
            6ZNIJHACiEQi7XbbNtnf3+9TDPwGEAwGj4+PbYe7u7upqSmcAAp/XxUOvJ0H/gEIBALvbqnK5TJFUXgABIPBvb09Z2+z2XSzWwB+\
            AIhGo85zDyG8vr6emZlx0ws8B1hZWXm3OdV1PR6Pu5me9BCAoqhUKnV2dvaupdVqzc7Oupye9ASAoqjV1dVWq9VdX6lUJiYm3E9P\
            egKwtbXVXXl7e7u2tvap0T0DODo6cta8vLyoqjo5OUl+SQApwId/AtPp9Nu7Dw8PiqLMzc2Rvl1wZHqsmBYWFliWDYfDpM9XTDnc\
            l3x53NesxWIRNUCpVEIIcHFxgRqgjjRq4DLs8WXRqMMeEMKNjQ2M4zbwNXSCKPA0PT09jMAToshZNBq9vLzENfSXTqeHGvqzZRhG\
            rVbLZrOCIPA87z5zyfO8IAjZbLZWq3kTu/SPCIi5CIi5CK8H+K5+AUFutmg0+UHcAAAAAElFTkSuQmCC
            """
    )!

    static let html = [
        documentMarkup,
        setupScript,
        duoScript,
        foldSurfaceScript,
        foldScript,
        motionScript,
        layoutScript,
        interactionScript,
        streamScript
    ].joined(separator: "\n")
}
