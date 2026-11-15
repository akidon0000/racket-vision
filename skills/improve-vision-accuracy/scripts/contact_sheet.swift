// 画像を格子状に並べた 1 枚の JPEG を作る（検出の結果を、まとめて目で確かめるため）。
// ビルド: xcrun swiftc -O contact_sheet.swift -o <置き場所>/contact_sheet（`swift contact_sheet.swift` で直接動かすと、Xcode 27 の環境では失敗する）
// 使い方: contact_sheet <出力.jpg> <列の数> <1 枚の幅> <画像...>
// 1 枚の高さは、幅の 9/16。縦長の動画のときは、環境変数 TILE_HEIGHT で高さを指定する（例: 幅 216、高さ 384）。
// 読めない画像は、黒いまま空けておく（並びがずれないように）。
import CoreGraphics
import Foundation
import ImageIO

let arguments = CommandLine.arguments

guard arguments.count >= 5, let columns = Int(arguments[2]), let tileWidth = Int(arguments[3]) else {
    FileHandle.standardError.write(Data("使い方: contact_sheet <出力.jpg> <列の数> <1 枚の幅> <画像...>\n".utf8))
    exit(1)
}

let output = arguments[1]
let files = Array(arguments.dropFirst(4))
let tileHeight = Int(ProcessInfo.processInfo.environment["TILE_HEIGHT"] ?? "") ?? tileWidth * 9 / 16
let rows = (files.count + columns - 1) / columns
let width = columns * tileWidth
let height = rows * tileHeight

guard let context = CGContext(
    data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { exit(1) }
context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: width, height: height))
for (index, file) in files.enumerated() {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: file) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { continue }
    let x = (index % columns) * tileWidth
    // CGContext は左下が原点。1 行目を上に置く。
    let y = (rows - 1 - index / columns) * tileHeight
    context.draw(image, in: CGRect(x: x, y: y, width: tileWidth, height: tileHeight))
}

guard let sheet = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: output) as CFURL, "public.jpeg" as CFString, 1, nil) else { exit(1) }
CGImageDestinationAddImage(destination, sheet, [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary)
exit(CGImageDestinationFinalize(destination) ? 0 : 1)
