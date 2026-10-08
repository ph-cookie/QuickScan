import AppKit
import ImageIO

final class ScreenCapture {
    private static let lock = NSLock()
    private static var activeProcess: Process?
    static let directory = FileManager.default.temporaryDirectory.appendingPathComponent("org.quickscan.capture", isDirectory: true)
    static func cleanup() { try? FileManager.default.removeItem(at: directory) }
    static func cancel() {
        lock.lock()
        if let process = activeProcess, process.isRunning { process.terminate() }
        lock.unlock()
        cleanup()
    }
    static func start(all: Bool, completion: @escaping (Result<[ScanCode]?, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result: Result<[ScanCode]?, Error> = Result {
                try autoreleasepool {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                    let file = directory.appendingPathComponent(UUID().uuidString + ".png")
                    defer { try? FileManager.default.removeItem(at: file); try? FileManager.default.removeItem(at: directory) }
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                    process.arguments = ["-i", "-x", "-s", file.path]
                    process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
                    lock.lock()
                    do { try process.run(); activeProcess = process; lock.unlock() }
                    catch { lock.unlock(); throw error }
                    defer { lock.lock(); activeProcess = nil; lock.unlock() }
                    process.waitUntilExit()
                    guard FileManager.default.fileExists(atPath: file.path) else {
                        if !CGPreflightScreenCaptureAccess() { throw CaptureError.permission }
                        return nil
                    }
                    guard CGPreflightScreenCaptureAccess() else { throw CaptureError.permission }
                    guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
                          let image = CGImageSourceCreateImageAtIndex(source, 0, nil), image.width > 1, image.height > 1 else { throw CaptureError.empty }
                    return try Decoder.decode(image, all: all)
                }
            }
            DispatchQueue.main.async { completion(result) }
        }
    }
    enum CaptureError: LocalizedError {
        case permission, empty
        var errorDescription: String? {
            switch self {
            case .permission: return "画面収録を許可してください。システム設定 → プライバシーとセキュリティ → 画面収録"
            case .empty: return "画面を取得できませんでした。画面収録の権限を確認してください"
            }
        }
    }
}
