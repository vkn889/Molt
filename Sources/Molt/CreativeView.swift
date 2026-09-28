import MoltCore
import SwiftUI

struct CreativeView: View {
  @ObservedObject var controller: PetController
  @State private var pixels = Array(repeating: 0, count: 64)
  @State private var color = 1
  @State private var melody: [Int] = []
  @State private var style = "Pixel garden"
  private let colors: [Color] = [.clear, MoltTheme.green, .orange, .yellow, .cyan, .purple]
  var body: some View {
    MoltCard(title: "Make something small") {
      Picker("Create", selection: $style) {
        Text("Pixel garden").tag("Pixel garden")
        Text("Little melody").tag("Little melody")
      }.pickerStyle(.segmented)
      if style == "Pixel garden" {
        HStack(alignment: .top, spacing: 24) {
          LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(24), spacing: 2), count: 8), spacing: 2
          ) {
            ForEach(0..<64) { index in
              Button {
                pixels[index] = color
              } label: {
                Rectangle().fill(pixels[index] == 0 ? .white : colors[pixels[index]]).frame(
                  width: 24, height: 24)
              }.buttonStyle(.plain).accessibilityLabel("Pixel \(index + 1), color \(pixels[index])")
            }
          }
          VStack(alignment: .leading, spacing: 12) {
            Picker("Paint", selection: $color) {
              Text("Eraser").tag(0)
              Text("Moss").tag(1)
              Text("Sunset").tag(2)
              Text("Sunshine").tag(3)
              Text("Water").tag(4)
              Text("Lilac").tag(5)
            }
            Button("Add Molt’s pattern") {
              for index in stride(from: 9, to: 55, by: 9) { pixels[index] = color }
            }
            Button("Save drawing…") { saveDrawing() }
            Text(
              "Create freely. Saving asks where to put the image. No desktop screenshot is taken."
            ).font(.caption).foregroundStyle(.secondary)
          }
        }
      } else {
        Text(
          melody.isEmpty
            ? "Choose notes to build a melody."
            : melody.map { ["C", "D", "E", "G", "A"][$0] }.joined(separator: " · ")
        ).font(MoltTheme.display(20))
        HStack {
          ForEach(0..<5) { note in
            Button(["C", "D", "E", "G", "A"][note]) { if melody.count < 16 { melody.append(note) } }
          }
          Button("Undo") { if !melody.isEmpty { melody.removeLast() } }
          Button("Save score…") { saveScore() }
        }
        Text(
          "A visual score you can enjoy without sound. Sixteen notes is plenty for a little tune."
        ).font(.caption).foregroundStyle(.secondary)
      }
    }
  }
  func saveDrawing() {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.png]
    panel.nameFieldStringValue = "molt-pixel-garden.png"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    let picture = LazyVGrid(
      columns: Array(repeating: GridItem(.fixed(40), spacing: 0), count: 8), spacing: 0
    ) {
      ForEach(0..<64) { i in
        Rectangle().fill(pixels[i] == 0 ? MoltTheme.paper : colors[pixels[i]]).frame(
          width: 40, height: 40)
      }
    }.frame(width: 320, height: 320)
    let renderer = ImageRenderer(content: picture)
    guard let tiff = renderer.nsImage?.tiffRepresentation, let image = NSBitmapImageRep(data: tiff),
      let bytes = image.representation(using: .png, properties: [:])
    else { return }
    do { try bytes.write(to: url, options: .atomic) } catch {
      controller.error = error.localizedDescription
    }
  }
  func saveScore() {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.plainText]
    panel.nameFieldStringValue = "molt-melody.txt"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      try melody.map { ["C", "D", "E", "G", "A"][$0] }.joined(separator: " ").write(
        to: url, atomically: true, encoding: .utf8)
    } catch { controller.error = error.localizedDescription }
  }
}
