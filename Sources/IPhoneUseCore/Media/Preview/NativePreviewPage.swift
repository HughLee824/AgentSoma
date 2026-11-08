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
            iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAYAAACqaXHeAAAACXBIWXMAACxLAAAsSwGlPZapAAAC4UlEQVR4nO2bv2sUQRTHx9+i\
            wnma/X5nluMO4UA9OAUL7QQxKWz8UYjahYAmaBGTxtbCqJVNAiI2sbMQ/Q9EsLKzsRBDTquIRRQbf3DxZGAPlmUv5vbunNmb+cJr\
            jux7+z55M7e3854QXl5eXn1UEAR7AIxJKa+TvAXgfi+mfWhfAEa1b2GrlFIjABYA/CDZGoRp3zpGGIb7hU2SUh4G0BhU4ikgGjqm\
            sEHlcrlIcul/JR+zpUKhsNd0/gLAPQPJt23OdP5bAKx2edPPSV6WUl6Mm/6M5Isul8KqEGKzseyDIDja7X+tWCwWOvnTJZ1hP6gL\
            UwJwIcMNX9WV06GarmXwd06YEskJg+u/bePGAACYNA0gqigzInnDNAD9lGgMAICbpgEAmDYJYNYCALMegCnBVwD8EqDfA+g3QQ5u\
            h/+pzclvAQCL1Wp1R6VS2UnyiXMAlFIj7ThSysA1AN/jcXQlOAUAQCPltZtTAN7E44RheNApACSfJeKMOgUAwEwizrRTAEgeT8RZ\
            dAnANyHE1kSchjMAACxsdAMcVgD1eAySd5wBAOBVIsQ2kiuuAFgjeSLuPzoxarkC4HHSP8nXrgBY0T94Eslf2uCyyT2A31LKk3G/\
            SqldAD66AmC8lyP3PANYSzvUkFKeIdkcagAAfgG4kvQXPfR87dJXvgAAWE6uea1SqbSP5PsM/nID4A/JR2mtbvqFh34HkLGarAfQ\
            BPBUKXUszQfJAwDeZd1LbAbQJPlQJ7jO9WMAvvSwkVoN4Han60juJvkgWhatYQVwKuWSTfr5HsCnXhO3BcD0Ojc23/67Wq22PWqD\
            e9uvxK1okOA/WmQAvIxOdT73O3FbWmQmB5VYXpqkJlxvkztvGgCAsyYBHLEAQD1vzdKtPiZvtllaC8Bdl9vlRdThbWJg4oMVAxOG\
            RmaWlVKHhKNDU/PWDU2ljM2dBjClR970Ou1hZG4uGr2b0j6tHpvz8vISedRfIYEaK/bwTTwAAAAASUVORK5CYII=
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
