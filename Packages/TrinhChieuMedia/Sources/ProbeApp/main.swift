import AppKit
import Foundation

// Bản thử Metal (T0.4): chữ tiếng Việt, logo và hai video ra tối đa hai màn, đo khung rớt, GPU, độ trễ.
// Chạy: `swift run -c release --package-path Packages/TrinhChieuMedia ProbeApp --help`.

let parsed = ProbeOptions.parse(Array(CommandLine.arguments.dropFirst()))
switch parsed {
case .help:
    Console.out(ProbeOptions.usage)
    exit(0)
case .failure(let message):
    Console.err(message)
    Console.err(ProbeOptions.usage)
    exit(64)
case .success(let options):
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let controller = ProbeController(options: options)
    Task { @MainActor in
        let code = await controller.run()
        exit(code)
    }
    app.run()
}
