import AppKit
import CoreGraphics
import ImageIO
import ScreenCaptureKit
import Vision

@MainActor final class ScreenHelp: ObservableObject {
  @Published var preview: NSImage?
  @Published var imageData: Data?
  @Published var recognizedText = ""
  @Published var status =
    "Share a screen once to discuss an error, an app, or anything you are looking at."
  @Published var busy = false
  @Published var displayIndex = 0
  private var snapshotID = UUID()
  func capture() {
    guard !busy else { return }
    guard #available(macOS 14, *) else {
      status = "Screen capture requires macOS 14. Use Attach screenshot on this Mac."
      return
    }
    guard CGPreflightScreenCaptureAccess() else {
      let granted = CGRequestScreenCaptureAccess()
      status =
        granted
        ? "Permission granted. Click Capture again."
        : "Screen Recording permission is needed. Enable Molt in System Settings, then retry. macOS may require relaunching the app."
      return
    }
    busy = true
    status = "Capturing one frame. Nothing is sent automatically."
    Task {
      defer { busy = false }
      do {
        let content = try await SCShareableContent.excludingDesktopWindows(
          false, onScreenWindowsOnly: true)
        let screens = NSScreen.screens
        let selected =
          screens.indices.contains(displayIndex) ? screens[displayIndex] : screens.first
        let id =
          (selected?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
          .uint32Value
        guard
          let display = content.displays.first(where: { $0.displayID == id })
            ?? content.displays.first
        else {
          status = "No shareable display is available."
          return
        }
        let ownApps = content.applications.filter {
          $0.processID == ProcessInfo.processInfo.processIdentifier
        }
        let filter = SCContentFilter(
          display: display, excludingApplications: ownApps, exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        let ratio = min(1, 1600.0 / Double(display.width))
        configuration.width = Int(Double(display.width) * ratio)
        configuration.height = Int(Double(display.height) * ratio)
        configuration.showsCursor = false
        if #available(macOS 14, *) {
          let cgImage = try await SCScreenshotManager.captureImage(
            contentFilter: filter, configuration: configuration)
          accept(cgImage)
        } else {
          status = "One-shot screen capture requires macOS 14. Use Attach screenshot on this Mac."
        }
      } catch { status = "Capture failed: \(error.localizedDescription)" }
    }
  }
  func chooseImage() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.png, .jpeg]
    panel.canChooseDirectories = false
    if panel.runModal() == .OK, let url = panel.url {
      guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
        size <= 10_000_000,
        let source = CGImageSourceCreateWithURL(url as CFURL, nil),
        let cg = CGImageSourceCreateThumbnailAtIndex(
          source, 0,
          [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 1600,
            kCGImageSourceCreateThumbnailWithTransform: true,
          ] as CFDictionary)
      else {
        status = "Choose a PNG or JPEG smaller than 10 MB."
        return
      }
      accept(cg)
    }
  }
  private func accept(_ image: CGImage) {
    let ratio = min(1, 1600.0 / Double(image.width))
    let width = max(1, Int(Double(image.width) * ratio))
    let height = max(1, Int(Double(image.height) * ratio))
    guard
      let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let reduced = context.makeImage() else { return }
    let bitmap = NSBitmapImageRep(cgImage: reduced)
    imageData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
    preview = NSImage(cgImage: reduced, size: NSSize(width: width, height: height))
    recognizedText = ""
    let id = UUID()
    snapshotID = id
    status = "Review the captured frame. Send image or extracted text only when you choose."
    Task {
      let text = await Task.detached {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        try? VNImageRequestHandler(cgImage: reduced).perform([request])
        return request.results?.compactMap { $0.topCandidates(1).first?.string }.joined(
          separator: "\n") ?? ""
      }.value
      guard snapshotID == id else { return }
      recognizedText = String(text.prefix(12000))
    }
  }
  func clear() {
    snapshotID = UUID()
    preview = nil
    imageData = nil
    recognizedText = ""
    status = "Screen context removed."
  }
}
