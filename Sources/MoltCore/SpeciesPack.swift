import Foundation

public struct SpeciesPack {
  public let definition: PetDefinition
  public let definitionData: Data
  public let atlas: Data?
  public static func load(at url: URL) throws -> SpeciesPack {
    let resource = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    guard resource.isSymbolicLink != true else {
      throw MoltError.invalid("Species files cannot be symbolic links.")
    }
    let root = resource.isDirectory == true ? url : url.deletingLastPathComponent()
    let file = resource.isDirectory == true ? root.appendingPathComponent("definition.json") : url
    guard
      (try file.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey])).isSymbolicLink != true,
      (try file.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? Int.max <= 256_000
    else { throw MoltError.invalid("Definition must be a regular JSON file smaller than 256 KB.") }
    let data = try Data(contentsOf: file)
    let d = try JSONDecoder().decode(PetDefinition.self, from: data)
    try d.validate()
    var atlas: Data?
    if let name = d.spriteAtlas {
      let path = root.appendingPathComponent(name)
      let attributes = try path.resourceValues(forKeys: [
        .fileSizeKey, .isSymbolicLinkKey, .isRegularFileKey,
      ])
      guard attributes.isSymbolicLink != true, attributes.isRegularFile == true,
        attributes.fileSize ?? Int.max <= 8_000_000
      else { throw MoltError.invalid("Atlas must be a regular PNG smaller than 8 MB.") }
      let bytes = try Data(contentsOf: path)
      try validateAtlas(bytes)
      atlas = bytes
    }
    return SpeciesPack(definition: d, definitionData: data, atlas: atlas)
  }
  public static func validateAtlas(_ bytes: Data) throws {
    guard bytes.count <= 8_000_000 else { throw MoltError.invalid("Atlas is too large.") }
    guard bytes.prefix(8) == Data([137, 80, 78, 71, 13, 10, 26, 10]), bytes.count >= 24 else {
      throw MoltError.invalid("Atlas must be a PNG image.")
    }
    func integer(_ offset: Int) -> UInt32 {
      bytes[offset..<offset + 4].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }
    let width = integer(16)
    let height = integer(20)
    guard
      width >= 64 && height >= 64 && width <= 4096 && height <= 4096 && width % 4 == 0
        && height % 4 == 0
    else {
      throw MoltError.invalid(
        "Atlas must be a 4 by 4 grid, at most 4096 pixels per side, with dimensions divisible by four."
      )
    }
  }

}
