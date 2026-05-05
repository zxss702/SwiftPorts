#if canImport(Compression) || os(Linux) || os(Windows)
import XzCommand

@main
struct Entry {
    static func main() async {
        await Xz.main()
    }
}
#else
// Empty stub for iOS / tvOS / watchOS / visionOS / Android — the
// underlying compression CLIs need libbz2 / liblzma / libzstd, which
// these platforms either don't ship or don't expose. The executable
// is still declared as a target so SwiftPM resolves; xcodebuild simply
// builds an unused @main stub on Apple-mobile.
@main struct Entry { static func main() {} }
#endif // platform gate
