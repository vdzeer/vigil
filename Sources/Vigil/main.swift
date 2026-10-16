import AppKit

// Development and build helpers: draw artwork to files and exit, no menu bar item.
//   Vigil --make-iconset <folder>   the app icon, used by scripts/build-app.sh
//   Vigil --render-glyphs <folder>  the menu bar glyphs, for checking them by eye
let arguments = CommandLine.arguments
if arguments.count == 3, arguments[1] == "--make-iconset" || arguments[1] == "--render-glyphs" {
    let folder = URL(fileURLWithPath: arguments[2])
    do {
        if arguments[1] == "--make-iconset" {
            try Artwork.writeIconset(to: folder)
        } else {
            try Artwork.writeGlyphs(to: folder)
        }
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("Could not write to \(folder.path): \(error)\n".utf8))
        exit(1)
    }
}

let app = NSApplication.shared

// One copy is enough: a second would only fight the first over the same settings.
if let id = Bundle.main.bundleIdentifier, NSRunningApplication.runningApplications(withBundleIdentifier: id).count > 1 {
    exit(0)
}

let controller = AppController()
app.delegate = controller
app.setActivationPolicy(.accessory)

// A plain `kill` should leave the Mac's sleep settings as tidy as choosing Quit does.
signal(SIGTERM, SIG_IGN)
let terminated = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
terminated.setEventHandler {
    MainActor.assumeIsolated { NSApplication.shared.terminate(nil) }
}
terminated.resume()

app.run()
