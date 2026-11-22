import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("usage: make_icns.swift <iconset-dir> <output.icns>\n", stderr)
    exit(1)
}

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let output = URL(fileURLWithPath: CommandLine.arguments[2])
let entries: [(type: String, file: String)] = [
    ("icp4", "icon_16x16.png"),
    ("icp5", "icon_32x32.png"),
    ("icp6", "icon_32x32@2x.png"),
    ("ic07", "icon_128x128.png"),
    ("ic08", "icon_256x256.png"),
    ("ic09", "icon_512x512.png"),
    ("ic10", "icon_512x512@2x.png")
]

var payload = Data()

for entry in entries {
    let png = try Data(contentsOf: directory.appendingPathComponent(entry.file))
    payload.append(contentsOf: entry.type.utf8)

    var length = UInt32(png.count + 8).bigEndian
    withUnsafeBytes(of: &length) { payload.append(contentsOf: $0) }
    payload.append(png)
}

var icns = Data("icns".utf8)
var totalLength = UInt32(payload.count + 8).bigEndian
withUnsafeBytes(of: &totalLength) { icns.append(contentsOf: $0) }
icns.append(payload)

try icns.write(to: output, options: .atomic)
