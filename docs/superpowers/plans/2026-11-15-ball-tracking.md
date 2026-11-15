# ボール追跡（BallTracking）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 連続するフレームから球の位置を返し、ラリーごとの軌跡を点で表示できるライブラリ `BallTracking` を足し、サンプル動画で評価できる状態にする。

**Architecture:** 画素の処理（動き・色・塊）と、候補を時間でつなぐ処理（追跡）を別の型に分け、`MotionColorBallDetector` が 2 つをつなぐ。ラリーの区切りと色は `BallRallyTrajectory` と `BallRallyPalette` が持ち、`DemoApp` と評価用の書き出しが同じものを使う。

**Tech Stack:** Swift 6.2（ルートのパッケージは Swift 6 の言語モード）、CoreVideo、simd、AVFoundation（テストと DemoApp だけ）、Swift Testing、SwiftUI（DemoApp だけ）。外部への依存は足さない。

**Spec:** `docs/superpowers/specs/2026-11-15-ball-tracking-design.md`

## Global Constraints

- 対応する OS は iOS 18 と macOS 14（`Package.swift` の `platforms` は変えない）。
- 外部のパッケージを足さない。学習済みモデルを使わない。
- 入力は 32BGRA の `CVPixelBuffer` と時刻（秒）。向きは上向きだけ。
- 座標は映像の大きさに対する 0〜1 の正規化座標で、原点は左下（`DetectedQuad` と同じ）。型の内側（`BallCandidate` など）だけ、画素の座標（左上が原点）を使う。
- 時間のしきい値は、フレームの数ではなく秒で持つ（サンプル動画は毎秒 30 コマと 60 コマが混じる）。最初の値は、球として出し始めるまで 0.08 秒、見失って追跡を捨てるまで 0.3 秒、ラリーの終わりは 2 秒。
- 大きさのしきい値は、映像の幅に対する割合で持つ（球の直径は幅の 0.2〜2%）。
- `BallTracking` は、`CourtFit` と同じく Debug でも最適化する（`unsafeFlags(["-O"], .when(configuration: .debug))`）。
- テストは `xcrun swift test` で呼ぶ（`xcrun` を付けないと Xcode 27 で失敗する）。サンプル動画で測るときは `-c release -Xswiftc -enable-testing` を付ける。
- 各タスクの最後に `swiftformat .` と `swiftlint lint --strict` を通す。`--strict` は警告も失敗にする。関数の本体は 40 行まで、循環的複雑度は 10 まで、ファイルは 400 行まで、3 要素以上のタプルは使わない。
- コメントとコミットメッセージは日本語で、既存のコードの書き方に合わせる（「〜する。」で終える）。
- 作業はブランチ `ball-tracking` で行う。コミットメッセージの最後に `Co-Authored-By: Claude Fable 5.2 <noreply@anthropic.com>` を付ける。push はしない。`.serena/` はコミットしない。
- `Tests/CourtFitTests/` と `Sources/CourtFit/` は変えない。

## Review Focus

仕様が黙っているが、使う人が踏みそうな入力。それぞれ、持ち主のタスクにテストを足してある。

1. 32BGRA でない画素バッファ（カメラの既定の 420f など）を渡す → 落ちずに、球なしの結果を返す（Task 4）。
2. 途中でフレームの大きさが変わる（カメラの切り替え、解像度の変更）→ 範囲外を読まずに、追跡をやり直す（Task 4）。
3. 時刻が戻る、または同じ時刻が続く（再生のシーク、ループ）→ 0 で割らずに、追跡をやり直す（Task 3）。
4. 画面全体が球の色で動く（黄色い壁をカメラが横切る）→ 塊の処理に入らずに、場面の切り替わりとして扱う（Task 4）。
5. 球が止まったまま光がちらつく（置いてある球、黄色いロゴ）→ 球として出さない（Task 3）。

---

### Task 1: パッケージの土台と、公開する型、球の色

**Files:**
- Modify: `Package.swift`
- Create: `Sources/BallTracking/BallObservation.swift`
- Create: `Sources/BallTracking/BallDetector.swift`
- Create: `Sources/BallTracking/BallColor.swift`
- Test: `Tests/BallTrackingTests/BallColorTests.swift`

**Interfaces:**
- Consumes: なし
- Produces:
  - `public struct BallObservation { center: CGPoint; radius: CGFloat; confidence: Float }`
  - `public struct BallDetectionMethod { rawValue: String; label: String; static let motionColor }`
  - `public struct BallFrameOutcome { method; time: TimeInterval; ball: BallObservation?; candidates: [BallObservation]; sceneChanged: Bool; durationMilliseconds: Double; imageSize: CGSize }`
  - `public protocol BallDetector: Sendable { var method: BallDetectionMethod { get }; func detect(in: CVPixelBuffer, at: TimeInterval) -> BallFrameOutcome; func reset() }`
  - `public struct BallColor { hueRange: ClosedRange<Double>; minimumSaturation: Double; minimumBrightness: Double; static let yellowGreen }` と、モジュールの中だけで使う `func matches(red: UInt8, green: UInt8, blue: UInt8) -> Bool`

- [ ] **Step 1: ブランチを切る**

```bash
git switch -c ball-tracking
```

- [ ] **Step 2: `Package.swift` に、ライブラリとテストのターゲットを足す**

`products` の配列に 1 行足す。

```swift
        .library(name: "CourtOverlay", targets: ["CourtOverlay"]),
        .library(name: "BallTracking", targets: ["BallTracking"])
```

`targets` の配列で、`CourtFitTests` の行を次に置き換える。

```swift
        // 球の追跡。全画素を回すので、CourtFit と同じく Debug でも最適化する。
        .target(name: "BallTracking", swiftSettings: [.unsafeFlags(["-O"], .when(configuration: .debug))]),
        .testTarget(name: "CourtFitTests", dependencies: ["CourtFit"]),
        .testTarget(name: "BallTrackingTests", dependencies: ["BallTracking"])
```

- [ ] **Step 3: 落ちるテストを書く**

`Tests/BallTrackingTests/BallColorTests.swift`:

```swift
@testable import BallTracking
import Testing

struct BallColorTests {
    @Test func yellowGreenMatchesBallColor() {
        #expect(BallColor.yellowGreen.matches(red: 210, green: 230, blue: 80))
        // 少し暗く写った球。
        #expect(BallColor.yellowGreen.matches(red: 150, green: 170, blue: 60))
    }

    @Test func yellowGreenRejectsCourtAndPeople() {
        // 青いコート、白線、灰色、肌、暗い黄色。
        #expect(!BallColor.yellowGreen.matches(red: 40, green: 80, blue: 200))
        #expect(!BallColor.yellowGreen.matches(red: 255, green: 255, blue: 255))
        #expect(!BallColor.yellowGreen.matches(red: 120, green: 120, blue: 120))
        #expect(!BallColor.yellowGreen.matches(red: 220, green: 170, blue: 140))
        #expect(!BallColor.yellowGreen.matches(red: 60, green: 70, blue: 20))
    }

    @Test func customHueRangeMatchesOrange() {
        let orange = BallColor(hueRange: 15...40, minimumSaturation: 0.4, minimumBrightness: 0.5)
        #expect(orange.matches(red: 240, green: 130, blue: 30))
        #expect(!orange.matches(red: 210, green: 230, blue: 80))
    }
}
```

- [ ] **Step 4: テストが落ちることを確かめる**

Run: `xcrun swift test --filter BallColorTests`
Expected: コンパイルエラー（`BallColor` が無い）。

- [ ] **Step 5: 公開する型を書く**

`Sources/BallTracking/BallObservation.swift`:

```swift
import CoreGraphics
import Foundation

/// 映像から見つけた球 1 個。
public struct BallObservation: Equatable, Sendable {
    /// 中心。映像の大きさに対する 0〜1 の正規化座標で、原点は左下（`CourtFit` の `DetectedQuad` と同じ）。
    public var center: CGPoint
    /// 半径。映像の幅に対する割合。
    public var radius: CGFloat
    /// 確からしさ（0〜1）。
    public var confidence: Float

    public init(center: CGPoint, radius: CGFloat, confidence: Float) {
        self.center = center
        self.radius = radius
        self.confidence = confidence
    }
}

/// 球の検出の方式。使う側が自前の方式を足せるよう、列挙ではなく値で表す。
public struct BallDetectionMethod: Hashable, Sendable {
    public let rawValue: String
    /// 画面に出す名前。
    public let label: String

    public init(rawValue: String, label: String) {
        self.rawValue = rawValue
        self.label = label
    }

    /// 動きと色で拾い、軌跡でつなぐ方式（`MotionColorBallDetector`）。
    public static let motionColor = BallDetectionMethod(rawValue: "motionColor", label: "動きと色")
}

/// 1 フレームぶんの、球の検出の結果。
public struct BallFrameOutcome: Equatable, Sendable {
    public var method: BallDetectionMethod
    /// 検出器に渡した、フレームの時刻（秒）。
    public var time: TimeInterval
    /// 球。見つからなければ nil。
    public var ball: BallObservation?
    /// 球の候補（追跡で絞る前）。確認用に描くためのもの。
    public var candidates: [BallObservation]
    /// 場面が切り替わったとみなして、追跡を捨てたか。
    public var sceneChanged: Bool
    /// 検出にかかった時間（ミリ秒）。
    public var durationMilliseconds: Double
    /// 検出に使った映像の大きさ（ピクセル）。
    public var imageSize: CGSize

    public init(
        method: BallDetectionMethod,
        time: TimeInterval,
        ball: BallObservation?,
        candidates: [BallObservation] = [],
        sceneChanged: Bool = false,
        durationMilliseconds: Double,
        imageSize: CGSize
    ) {
        self.method = method
        self.time = time
        self.ball = ball
        self.candidates = candidates
        self.sceneChanged = sceneChanged
        self.durationMilliseconds = durationMilliseconds
        self.imageSize = imageSize
    }
}
```

`Sources/BallTracking/BallDetector.swift`:

```swift
import CoreVideo
import Foundation

/// 連続するフレームから、球を探す。
///
/// 方式ごとに実装を分け、同じ入出力にする。実装は前のフレームを覚えるので、フレームは時刻の順に渡す。
/// 動画 1 本（撮影 1 回）ごとに作り直すか、`reset()` を呼ぶ。
public protocol BallDetector: Sendable {
    /// この実装の方式。
    var method: BallDetectionMethod { get }
    /// 1 フレームから球を探す。`pixelBuffer` は上向きの 32BGRA、`time` はそのフレームの時刻（秒）。
    func detect(in pixelBuffer: CVPixelBuffer, at time: TimeInterval) -> BallFrameOutcome
    /// 覚えているフレームと追跡を捨てる。
    func reset()
}
```

`Sources/BallTracking/BallColor.swift`:

```swift
/// 球の色。色相・鮮やかさ・明るさの範囲で表す。
public struct BallColor: Equatable, Sendable {
    /// 色相の範囲（度、0〜360）。赤をまたぐ範囲（350〜10 など）は表せない。
    public var hueRange: ClosedRange<Double>
    /// 鮮やかさ（彩度）の下限（0〜1）。
    public var minimumSaturation: Double
    /// 明るさの下限（0〜1）。
    public var minimumBrightness: Double

    public init(hueRange: ClosedRange<Double>, minimumSaturation: Double, minimumBrightness: Double) {
        self.hueRange = hueRange
        self.minimumSaturation = minimumSaturation
        self.minimumBrightness = minimumBrightness
    }

    /// 黄緑の球（屋内外でよく使われる色）。
    public static let yellowGreen = BallColor(hueRange: 40...110, minimumSaturation: 0.3, minimumBrightness: 0.45)

    /// 画素が、この色に入るか。
    func matches(red: UInt8, green: UInt8, blue: UInt8) -> Bool {
        let red = Int(red)
        let green = Int(green)
        let blue = Int(blue)
        let high = max(red, green, blue)
        let chroma = high - min(red, green, blue)
        guard chroma > 0, Double(high) >= minimumBrightness * 255, Double(chroma) >= minimumSaturation * Double(high) else {
            return false
        }
        let hue: Double = if high == red {
            60 * Double(green - blue) / Double(chroma)
        } else if high == green {
            60 * Double(blue - red) / Double(chroma) + 120
        } else {
            60 * Double(red - green) / Double(chroma) + 240
        }
        return hueRange.contains(hue < 0 ? hue + 360 : hue)
    }
}
```

- [ ] **Step 6: テストが通ることを確かめる**

Run: `xcrun swift test --filter BallColorTests`
Expected: 3 件とも PASS。

- [ ] **Step 7: 整形と Lint**

Run: `swiftformat . && swiftlint lint --strict`
Expected: どちらもエラーなし。`swiftformat` がファイルを直したら、テストを通し直す。

- [ ] **Step 8: コミット**

```bash
git add Package.swift Sources/BallTracking Tests/BallTrackingTests docs/superpowers
git commit -m "球の追跡のライブラリ（BallTracking）の土台と、球の色の判定を足す

Co-Authored-By: Claude Fable 5.2 <noreply@anthropic.com>"
```

---

### Task 2: 画素から球の候補を拾う（動き・色・塊）

**Files:**
- Create: `Sources/BallTracking/FrameImage.swift`
- Create: `Sources/BallTracking/BallBlob.swift`
- Create: `Sources/BallTracking/BallCandidateFinder.swift`
- Create: `Tests/BallTrackingTests/SyntheticFrame.swift`
- Test: `Tests/BallTrackingTests/BallCandidateFinderTests.swift`

**Interfaces:**
- Consumes: `BallColor.matches(red:green:blue:)`（Task 1）
- Produces（どれもモジュールの中だけで使う）:
  - `struct FrameImage { let width: Int; let height: Int; let bytes: [UInt8] }`（BGRA、行の詰め物なし）と `init?(bgraPixelBuffer: CVPixelBuffer)`
  - `struct BallCandidate: Equatable { var center: SIMD2<Double>; var radius: Double; var score: Double }`（画素の座標、左上が原点）
  - `struct BallCandidateFinder { var color: BallColor; var diameterRange: ClosedRange<Double>; var sceneChangeRatio: Double; func find(current:previous:beforePrevious:) -> Result }`、`Result { var candidates: [BallCandidate]; var movingRatio: Double }`
  - テスト用: `struct SyntheticColor`、`struct SyntheticFrame`（`fillRect`、`fillCircle`、`image`、`pixelBuffer()`）

- [ ] **Step 1: 合成フレームの部品を書く**

`Tests/BallTrackingTests/SyntheticFrame.swift`:

```swift
@testable import BallTracking
import CoreVideo
import Testing

/// 合成フレームの色。
struct SyntheticColor {
    var red: UInt8
    var green: UInt8
    var blue: UInt8

    /// 青いコート。
    static let court = SyntheticColor(red: 40, green: 80, blue: 200)
    /// 黄緑の球。
    static let ball = SyntheticColor(red: 210, green: 230, blue: 80)
    static let gray = SyntheticColor(red: 120, green: 120, blue: 120)
}

/// 合成したフレーム（1 色の背景に、円や四角を置く）。座標は画素で、左上が原点。
struct SyntheticFrame {
    let width: Int
    let height: Int
    /// BGRA の画素（行の詰め物なし）。
    private(set) var bytes: [UInt8]

    init(width: Int = 640, height: Int = 360, background: SyntheticColor = .court) {
        self.width = width
        self.height = height
        bytes = [UInt8](repeating: 255, count: width * height * 4)
        fillRect(x: 0, y: 0, width: width, height: height, color: background)
    }

    mutating func fillRect(x: Int, y: Int, width rectWidth: Int, height rectHeight: Int, color: SyntheticColor) {
        for row in max(0, y)..<min(height, y + rectHeight) {
            for column in max(0, x)..<min(width, x + rectWidth) {
                set(column, row, color)
            }
        }
    }

    /// 円を塗る。画素の中心（番号 + 0.5）が円の中にある画素を塗る。
    mutating func fillCircle(centerX: Double, centerY: Double, radius: Double, color: SyntheticColor) {
        for row in 0..<height {
            for column in 0..<width {
                let dx = Double(column) + 0.5 - centerX
                let dy = Double(row) + 0.5 - centerY
                if dx * dx + dy * dy <= radius * radius {
                    set(column, row, color)
                }
            }
        }
    }

    private mutating func set(_ x: Int, _ y: Int, _ color: SyntheticColor) {
        let offset = (y * width + x) * 4
        bytes[offset] = color.blue
        bytes[offset + 1] = color.green
        bytes[offset + 2] = color.red
        bytes[offset + 3] = 255
    }

    var image: FrameImage {
        FrameImage(width: width, height: height, bytes: bytes)
    }

    /// 32BGRA の画素バッファにする。
    func pixelBuffer() throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, nil, &buffer)
        let created = try #require(buffer)
        CVPixelBufferLockBaseAddress(created, [])
        defer { CVPixelBufferUnlockBaseAddress(created, []) }
        let base = try #require(CVPixelBufferGetBaseAddress(created))
        let stride = CVPixelBufferGetBytesPerRow(created)
        bytes.withUnsafeBytes { source in
            guard let start = source.baseAddress else { return }
            for row in 0..<height {
                (base + row * stride).copyMemory(from: start + row * width * 4, byteCount: width * 4)
            }
        }
        return created
    }
}
```

- [ ] **Step 2: 落ちるテストを書く**

`Tests/BallTrackingTests/BallCandidateFinderTests.swift`:

```swift
@testable import BallTracking
import simd
import Testing

struct BallCandidateFinderTests {
    /// 球が 1 フレームに (12, 4) 画素ずつ動く、3 枚のフレーム。`decorate` で、各フレームに物を足す。
    private func frames(decorate: (inout SyntheticFrame, Int) -> Void = { _, _ in }) -> [SyntheticFrame] {
        (0..<3).map { index in
            var frame = SyntheticFrame()
            decorate(&frame, index)
            frame.fillCircle(centerX: 76 + 12 * Double(index), centerY: 92 + 4 * Double(index), radius: 4, color: .ball)
            return frame
        }
    }

    private func find(_ frames: [SyntheticFrame]) -> BallCandidateFinder.Result {
        BallCandidateFinder().find(current: frames[2].image, previous: frames[1].image, beforePrevious: frames[0].image)
    }

    @Test func findsMovingBall() throws {
        let result = find(frames())
        let candidate = try #require(result.candidates.first)
        #expect(result.candidates.count == 1)
        #expect(simd_distance(candidate.center, SIMD2(100, 100)) <= 0.5)
        #expect(abs(candidate.radius - 4) <= 0.5)
        #expect(result.movingRatio < 0.01)
    }

    @Test func ignoresStillBallColoredThings() {
        let result = find(frames { frame, _ in
            // 止まった黄色（ロゴ）と、止まった球。
            frame.fillRect(x: 500, y: 40, width: 30, height: 30, color: .ball)
            frame.fillCircle(centerX: 300, centerY: 200, radius: 4, color: .ball)
        })
        #expect(result.candidates.count == 1)
    }

    @Test func ignoresMovingThingsOfOtherColorsAndSizes() {
        let result = find(frames { frame, index in
            // 動く灰色の塊（選手）と、動く大きな黄色の塊（黄色い服）。どちらも 1 フレームに 20 画素動く。
            frame.fillRect(x: 200 + 20 * index, y: 200, width: 60, height: 120, color: .gray)
            frame.fillRect(x: 400 + 20 * index, y: 150, width: 80, height: 80, color: .ball)
        })
        #expect(result.candidates.count == 1)
    }

    @Test func reportsSceneChangeWithoutCandidates() {
        var frames = frames()
        frames[2] = SyntheticFrame(background: .gray)
        frames[2].fillCircle(centerX: 100, centerY: 100, radius: 4, color: .ball)
        let result = find(frames)
        #expect(result.movingRatio > 0.9)
        #expect(result.candidates.isEmpty)
    }

    @Test func survivesWholeFrameOfMovingBallColor() {
        // 画面全体が球の色に変わる（黄色い壁をカメラが横切る）。
        let frames = [SyntheticFrame(), SyntheticFrame(), SyntheticFrame(background: .ball)]
        let result = find(frames)
        #expect(result.candidates.isEmpty)
    }
}
```

- [ ] **Step 3: テストが落ちることを確かめる**

Run: `xcrun swift test --filter BallCandidateFinderTests`
Expected: コンパイルエラー（`FrameImage`、`BallCandidateFinder` が無い）。

- [ ] **Step 4: `FrameImage` を書く**

`Sources/BallTracking/FrameImage.swift`:

```swift
import CoreVideo

/// 1 フレームの画素を写したもの。前のフレームと比べるために、検出器が 2 枚まで覚える。
struct FrameImage {
    let width: Int
    let height: Int
    /// BGRA の画素。行の詰め物は無く、1 行は `width * 4` バイト。
    let bytes: [UInt8]
}

extension FrameImage {
    /// 32BGRA の画素バッファを写す。32BGRA でないとき、縦か横が 8 画素より小さいときは nil。
    init?(bgraPixelBuffer buffer: CVPixelBuffer) {
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA else { return nil }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        guard width >= 8, height >= 8, let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let rowBytes = width * 4
        let bytes = [UInt8](unsafeUninitializedCapacity: rowBytes * height) { destination, count in
            if let start = destination.baseAddress {
                for row in 0..<height {
                    UnsafeMutableRawPointer(start + row * rowBytes).copyMemory(from: base + row * stride, byteCount: rowBytes)
                }
            }
            count = rowBytes * height
        }
        self.init(width: width, height: height, bytes: bytes)
    }
}
```

- [ ] **Step 5: `BallBlob` を書く**

`Sources/BallTracking/BallBlob.swift`:

```swift
/// つながった画素の塊（8 方向でつながるものを 1 つにする）。
struct BallBlob {
    var minX: Int
    var maxX: Int
    var minY: Int
    var maxY: Int
    var count = 0
    var sumX = 0
    var sumY = 0

    private init(x: Int, y: Int) {
        minX = x
        maxX = x
        minY = y
        maxY = y
    }

    private mutating func add(x: Int, y: Int) {
        minX = min(minX, x)
        maxX = max(maxX, x)
        minY = min(minY, y)
        maxY = max(maxY, y)
        count += 1
        sumX += x
        sumY += y
    }

    /// `mask` の立っている画素を、塊にまとめる。`seeds` は、立っている画素の番号。`mask` は使い終わると全部倒れる。
    static func collect(from mask: inout [Bool], seeds: [Int], width: Int, height: Int) -> [BallBlob] {
        var blobs = [BallBlob]()
        var stack = [Int]()
        for seed in seeds where mask[seed] {
            mask[seed] = false
            stack.append(seed)
            var blob = BallBlob(x: seed % width, y: seed / width)
            while let index = stack.popLast() {
                let x = index % width
                let y = index / width
                blob.add(x: x, y: y)
                for neighborY in max(0, y - 1)...min(height - 1, y + 1) {
                    for neighborX in max(0, x - 1)...min(width - 1, x + 1) where mask[neighborY * width + neighborX] {
                        mask[neighborY * width + neighborX] = false
                        stack.append(neighborY * width + neighborX)
                    }
                }
            }
            blobs.append(blob)
        }
        return blobs
    }
}
```

- [ ] **Step 6: `BallCandidateFinder` を書く**

`Sources/BallTracking/BallCandidateFinder.swift`:

```swift
import simd

/// 球の候補（画素の座標、左上が原点）。
struct BallCandidate: Equatable {
    var center: SIMD2<Double>
    var radius: Double
    /// 塊が、囲む四角形をどれだけ埋めているか（0〜1）。円は約 0.79。
    var score: Double
}

/// 動いていて、球の色をしていて、球の大きさの塊を探す。
struct BallCandidateFinder {
    struct Result {
        var candidates: [BallCandidate]
        /// 1 つ前のフレームから動いた画素の割合（0〜1。8 画素おきに数える）。
        var movingRatio: Double
    }

    var color = BallColor.yellowGreen
    /// 球の直径の範囲（映像の幅に対する割合）。
    var diameterRange: ClosedRange<Double> = 0.002...0.02
    /// 動いた画素の割合がこれを超えたら、場面の切り替わりとみなして候補を出さない。
    var sceneChangeRatio = 0.2
    /// 「動いた」とみなす、青・緑・赤の差の合計。
    var differenceThreshold = 45
    /// 塊の長い辺が、短い辺の何倍まで許すか（ぶれて伸びた球を通す）。
    var maximumElongation = 3.0
    /// 塊が、囲む四角形を埋める割合の下限。
    var minimumFill = 0.3

    /// 3 枚は同じ大きさであること。
    func find(current: FrameImage, previous: FrameImage, beforePrevious: FrameImage) -> Result {
        let ratio = movingRatio(current: current, previous: previous)
        guard ratio <= sceneChangeRatio else { return Result(candidates: [], movingRatio: ratio) }
        var mask = [Bool](repeating: false, count: current.width * current.height)
        let seeds = fillMask(&mask, current: current, previous: previous, beforePrevious: beforePrevious)
        let blobs = BallBlob.collect(from: &mask, seeds: seeds, width: current.width, height: current.height)
        return Result(candidates: blobs.compactMap { candidate(from: $0, imageWidth: current.width) }, movingRatio: ratio)
    }

    private func movingRatio(current: FrameImage, previous: FrameImage) -> Double {
        var sampled = 0
        var moved = 0
        current.bytes.withUnsafeBufferPointer { now in
            previous.bytes.withUnsafeBufferPointer { before in
                for y in stride(from: 0, to: current.height, by: 8) {
                    for x in stride(from: 0, to: current.width, by: 8) {
                        sampled += 1
                        if difference(now, before, at: (y * current.width + x) * 4) > differenceThreshold {
                            moved += 1
                        }
                    }
                }
            }
        }
        return sampled == 0 ? 0 : Double(moved) / Double(sampled)
    }

    /// 1 つ前とも 2 つ前とも違い、球の色をしている画素を立てる。立てた画素の番号を返す。
    private func fillMask(_ mask: inout [Bool], current: FrameImage, previous: FrameImage, beforePrevious: FrameImage) -> [Int] {
        var seeds = [Int]()
        current.bytes.withUnsafeBufferPointer { now in
            previous.bytes.withUnsafeBufferPointer { before in
                beforePrevious.bytes.withUnsafeBufferPointer { older in
                    for index in 0..<(current.width * current.height) {
                        let offset = index * 4
                        // 大半の画素は止まっているので、軽い「動き」を先に見る。
                        guard difference(now, before, at: offset) > differenceThreshold,
                              color.matches(red: now[offset + 2], green: now[offset + 1], blue: now[offset]),
                              difference(now, older, at: offset) > differenceThreshold else { continue }
                        mask[index] = true
                        seeds.append(index)
                    }
                }
            }
        }
        return seeds
    }

    private func difference(_ first: UnsafeBufferPointer<UInt8>, _ second: UnsafeBufferPointer<UInt8>, at offset: Int) -> Int {
        abs(Int(first[offset]) - Int(second[offset]))
            + abs(Int(first[offset + 1]) - Int(second[offset + 1]))
            + abs(Int(first[offset + 2]) - Int(second[offset + 2]))
    }

    /// 塊が球の大きさと形なら、候補にする。直径は、ぶれで伸びない短い辺で見る。
    private func candidate(from blob: BallBlob, imageWidth: Int) -> BallCandidate? {
        let width = Double(blob.maxX - blob.minX + 1)
        let height = Double(blob.maxY - blob.minY + 1)
        let short = min(width, height)
        let minimum = max(2, diameterRange.lowerBound * Double(imageWidth))
        let maximum = diameterRange.upperBound * Double(imageWidth)
        let fill = Double(blob.count) / (width * height)
        guard short >= minimum, short <= maximum, max(width, height) <= short * maximumElongation, fill >= minimumFill else {
            return nil
        }
        // 画素の中心は、番号に 0.5 を足した位置。
        let center = SIMD2(Double(blob.sumX) / Double(blob.count) + 0.5, Double(blob.sumY) / Double(blob.count) + 0.5)
        return BallCandidate(center: center, radius: short / 2, score: min(1, fill))
    }
}
```

- [ ] **Step 7: テストが通ることを確かめる**

Run: `xcrun swift test --filter BallCandidateFinderTests`
Expected: 5 件とも PASS。

- [ ] **Step 8: 整形と Lint**

Run: `swiftformat . && swiftlint lint --strict`
Expected: どちらもエラーなし。

- [ ] **Step 9: コミット**

```bash
git add Sources/BallTracking Tests/BallTrackingTests
git commit -m "動き・色・塊の大きさで、球の候補を拾う

Co-Authored-By: Claude Fable 5.2 <noreply@anthropic.com>"
```

---

### Task 3: 候補を時間でつないで、球を 1 つに決める

**Files:**
- Create: `Sources/BallTracking/BallTrack.swift`
- Create: `Sources/BallTracking/BallTrackState.swift`
- Test: `Tests/BallTrackingTests/BallTrackStateTests.swift`

**Interfaces:**
- Consumes: `BallCandidate`（Task 2）
- Produces（モジュールの中だけで使う）:
  - `struct BallTrackState { var confirmSeconds = 0.08; var loseSeconds = 0.3; var maximumSpeed = 2.0; mutating func update(candidates: [BallCandidate], time: Double, imageWidth: Double) -> Output?; mutating func reset() }`
  - `BallTrackState.Output: Equatable { var center: SIMD2<Double>; var radius: Double; var confidence: Double }`

- [ ] **Step 1: 落ちるテストを書く**

`Tests/BallTrackingTests/BallTrackStateTests.swift`:

```swift
@testable import BallTracking
import simd
import Testing

struct BallTrackStateTests {
    private let frame = 1.0 / 60

    private func candidate(_ x: Double, _ y: Double) -> BallCandidate {
        BallCandidate(center: SIMD2(x, y), radius: 4, score: 0.8)
    }

    /// 球を 1 フレームに `step` ずつ、`count` フレーム動かす。フレームごとの結果を返す。
    private func run(
        _ state: inout BallTrackState, from start: SIMD2<Double>, step: SIMD2<Double>, frames: Range<Int>
    ) -> [BallTrackState.Output?] {
        frames.map { index in
            let center = start + step * Double(index - frames.lowerBound)
            return state.update(candidates: [candidate(center.x, center.y)], time: Double(index) * frame, imageWidth: 640)
        }
    }

    @Test func confirmsBallMovingInALine() throws {
        var state = BallTrackState()
        let outputs = run(&state, from: SIMD2(100, 100), step: SIMD2(12, 0), frames: 0..<8)
        // 0.08 秒たつ 6 枚目（番号 5）から出す。
        #expect(outputs[0..<5].allSatisfy { $0 == nil })
        let first = try #require(outputs[5])
        #expect(first.center == SIMD2(160, 100))
        #expect(outputs[6] != nil && outputs[7] != nil)
    }

    @Test func ignoresCandidateThatStaysInPlace() {
        var state = BallTrackState()
        let outputs = run(&state, from: SIMD2(300, 200), step: SIMD2(0, 0), frames: 0..<40)
        #expect(outputs.allSatisfy { $0 == nil })
    }

    @Test func followsBallAfterBounce() {
        var state = BallTrackState()
        _ = run(&state, from: SIMD2(100, 100), step: SIMD2(6, 10), frames: 0..<6)
        // 向きが変わっても、追い続ける。
        let after = run(&state, from: SIMD2(136, 140), step: SIMD2(6, -10), frames: 6..<12)
        #expect(after.allSatisfy { $0 != nil })
        #expect(after.last??.center == SIMD2(166, 90))
    }

    @Test func prefersCandidateNearPrediction() {
        var state = BallTrackState()
        _ = run(&state, from: SIMD2(100, 100), step: SIMD2(12, 0), frames: 0..<6)
        // 見込みの位置 (172, 100) の候補と、近くの別の候補。
        let output = state.update(candidates: [candidate(150, 110), candidate(172, 100)], time: 6 * frame, imageWidth: 640)
        #expect(output?.center == SIMD2(172, 100))
    }

    @Test func keepsTrackThroughShortGap() {
        var state = BallTrackState()
        _ = run(&state, from: SIMD2(100, 100), step: SIMD2(12, 0), frames: 0..<6)
        // 5 フレーム（0.083 秒）隠れる。
        for index in 6..<11 {
            #expect(state.update(candidates: [], time: Double(index) * frame, imageWidth: 640) == nil)
        }
        let output = state.update(candidates: [candidate(232, 100)], time: 11 * frame, imageWidth: 640)
        #expect(output?.center == SIMD2(232, 100))
    }

    @Test func dropsTrackAfterLoseSeconds() {
        var state = BallTrackState()
        _ = run(&state, from: SIMD2(100, 100), step: SIMD2(12, 0), frames: 0..<6)
        // 0.35 秒あとに、近くに候補が出ても、追跡は捨ててあるので、すぐには出さない。
        let output = state.update(candidates: [candidate(170, 100)], time: 5 * frame + 0.35, imageWidth: 640)
        #expect(output == nil)
    }

    @Test func restartsWhenTimeDoesNotAdvance() {
        var state = BallTrackState()
        _ = run(&state, from: SIMD2(100, 100), step: SIMD2(12, 0), frames: 0..<6)
        // 同じ時刻と、戻った時刻。どちらも落ちずに、追跡をやり直す。
        #expect(state.update(candidates: [candidate(172, 100)], time: 5 * frame, imageWidth: 640) == nil)
        #expect(state.update(candidates: [candidate(184, 100)], time: 1 * frame, imageWidth: 640) == nil)
        let outputs = run(&state, from: SIMD2(196, 100), step: SIMD2(12, 0), frames: 2..<8)
        #expect(outputs.last??.center == SIMD2(256, 100))
    }
}
```

- [ ] **Step 2: テストが落ちることを確かめる**

Run: `xcrun swift test --filter BallTrackStateTests`
Expected: コンパイルエラー（`BallTrackState` が無い）。

- [ ] **Step 3: `BallTrack` を書く**

`Sources/BallTracking/BallTrack.swift`:

```swift
import simd

/// 候補を時間の向きにつないだ、1 本の軌跡。座標は画素（左上が原点）、速さは画素/秒。
struct BallTrack {
    var position: SIMD2<Double>
    var velocity = SIMD2<Double>(0, 0)
    var radius: Double
    var score: Double
    var lastTime: Double
    let startTime: Double
    let startPosition: SIMD2<Double>
    /// つないだ候補の数。
    var hits = 1

    init(startingAt candidate: BallCandidate, time: Double) {
        position = candidate.center
        radius = candidate.radius
        score = candidate.score
        lastTime = time
        startTime = time
        startPosition = candidate.center
    }

    /// 候補が、届く距離の中にあり、大きさが近いか。
    func accepts(_ candidate: BallCandidate, within reach: Double) -> Bool {
        simd_distance(candidate.center, position) <= reach
            && candidate.radius <= radius * 2.5
            && candidate.radius >= radius / 2.5
    }

    /// 速さから見込んだ、`time` での位置。
    func predictedPosition(at time: Double) -> SIMD2<Double> {
        position + velocity * (time - lastTime)
    }

    /// 候補をつなぐ。`time` は `lastTime` より後であること。
    mutating func extend(with candidate: BallCandidate, at time: Double) {
        let measured = (candidate.center - position) / (time - lastTime)
        // 打たれた直後やバウンドの直後に遅れないよう、新しい速さを重く見る。
        velocity = hits >= 2 ? velocity * 0.3 + measured * 0.7 : measured
        position = candidate.center
        radius = (radius + candidate.radius) / 2
        score = candidate.score
        lastTime = time
        hits += 1
    }

    var output: BallTrackState.Output {
        BallTrackState.Output(center: position, radius: radius, confidence: min(1, Double(hits) / 10) * score)
    }
}
```

- [ ] **Step 4: `BallTrackState` を書く**

`Sources/BallTracking/BallTrackState.swift`:

```swift
import simd

/// 候補を時間の向きにつなぎ、球を 1 つに決める。画像は見ない。
///
/// 追跡が無いあいだは、候補ごとに仮の軌跡を伸ばし、続けてつながって動いたものを球とする。
/// 球が決まったあとは、その 1 本だけを追う。
struct BallTrackState {
    struct Output: Equatable {
        /// 中心（画素、左上が原点）。
        var center: SIMD2<Double>
        var radius: Double
        var confidence: Double
    }

    /// 仮の軌跡を、球として出し始めるまでの時間（秒）。
    var confirmSeconds = 0.08
    /// 候補が無いまま、追跡を捨てるまでの時間（秒）。
    var loseSeconds = 0.3
    /// 球が 1 秒に動ける距離の上限（映像の幅に対する割合）。
    var maximumSpeed = 2.0
    /// 覚えておく仮の軌跡の数の上限。
    var maximumTentatives = 32

    private var confirmed: BallTrack?
    private var tentatives = [BallTrack]()
    private var lastTime: Double?

    mutating func reset() {
        confirmed = nil
        tentatives = []
        lastTime = nil
    }

    /// 1 フレームぶんの候補を渡す。球が決まっていて、このフレームで見えていれば返す。
    mutating func update(candidates: [BallCandidate], time: Double, imageWidth: Double) -> Output? {
        // 時刻が進んでいなければ（シーク、ループ）、前の軌跡とはつながらないので、やり直す。
        if let lastTime, time <= lastTime {
            reset()
        }
        lastTime = time
        if let track = confirmed {
            if time - track.lastTime > loseSeconds {
                confirmed = nil
            } else {
                return follow(track, candidates: candidates, time: time, imageWidth: imageWidth)
            }
        }
        return grow(candidates: candidates, time: time, imageWidth: imageWidth)
    }

    private func reach(of track: BallTrack, time: Double, imageWidth: Double) -> Double {
        maximumSpeed * imageWidth * (time - track.lastTime) + 2 * track.radius
    }

    /// 決まった球を追う。打たれると向きが変わるので、前の位置から届く候補のうち、見込みの位置に一番近いものを選ぶ。
    private mutating func follow(_ track: BallTrack, candidates: [BallCandidate], time: Double, imageWidth: Double) -> Output? {
        let predicted = track.predictedPosition(at: time)
        let reach = reach(of: track, time: time, imageWidth: imageWidth)
        let near = candidates.filter { track.accepts($0, within: reach) }
        guard let best = near.min(by: { simd_distance($0.center, predicted) < simd_distance($1.center, predicted) }) else {
            return nil
        }
        var next = track
        next.extend(with: best, at: time)
        confirmed = next
        return next.output
    }

    /// 仮の軌跡を伸ばし、球と言えるものが出たら、それを追跡にする。
    private mutating func grow(candidates: [BallCandidate], time: Double, imageWidth: Double) -> Output? {
        var extended = [BallTrack]()
        for track in tentatives where time - track.lastTime <= confirmSeconds {
            let matches = matches(for: track, in: candidates, time: time, imageWidth: imageWidth)
            if matches.isEmpty {
                // このフレームでは見えなかった。confirmSeconds のあいだは残す。
                extended.append(track)
            }
            for candidate in matches {
                var next = track
                next.extend(with: candidate, at: time)
                extended.append(next)
            }
        }
        if let ball = extended.filter({ isBall($0, time: time) }).max(by: { $0.hits < $1.hits }) {
            confirmed = ball
            tentatives = []
            return ball.output
        }
        let started = candidates.map { BallTrack(startingAt: $0, time: time) }
        tentatives = Array((extended + started).sorted { $0.hits > $1.hits }.prefix(maximumTentatives))
        return nil
    }

    /// 仮の軌跡につながる候補。始まったばかり（速さが分からない）なら届く候補を全部、速さが分かれば見込みの位置の近くの 1 つ。
    private func matches(for track: BallTrack, in candidates: [BallCandidate], time: Double, imageWidth: Double) -> [BallCandidate] {
        let reach = reach(of: track, time: time, imageWidth: imageWidth)
        let near = candidates.filter { track.accepts($0, within: reach) }
        guard track.hits >= 2 else { return near }
        let predicted = track.predictedPosition(at: time)
        let tolerance = max(4 * track.radius, 0.5 * simd_distance(predicted, track.position))
        guard let nearest = near.min(by: { simd_distance($0.center, predicted) < simd_distance($1.center, predicted) }),
              simd_distance(nearest.center, predicted) <= tolerance else {
            return []
        }
        return [nearest]
    }

    /// 仮の軌跡が、球と言えるか。このフレームでつながり、十分な時間続き、その場でちらついているだけでないこと。
    private func isBall(_ track: BallTrack, time: Double) -> Bool {
        track.lastTime == time
            && track.hits >= 3
            && time - track.startTime >= confirmSeconds
            && simd_distance(track.position, track.startPosition) >= 3 * track.radius
    }
}
```

- [ ] **Step 5: テストが通ることを確かめる**

Run: `xcrun swift test --filter BallTrackStateTests`
Expected: 7 件とも PASS。

- [ ] **Step 6: 整形と Lint**

Run: `swiftformat . && swiftlint lint --strict`
Expected: どちらもエラーなし。

- [ ] **Step 7: コミット**

```bash
git add Sources/BallTracking Tests/BallTrackingTests
git commit -m "球の候補を時間でつなぎ、球を 1 つに決める

Co-Authored-By: Claude Fable 5.2 <noreply@anthropic.com>"
```

---

### Task 4: 検出器（`MotionColorBallDetector`）

**Files:**
- Create: `Sources/BallTracking/MotionColorBallDetector.swift`
- Test: `Tests/BallTrackingTests/MotionColorBallDetectorTests.swift`

**Interfaces:**
- Consumes: `BallDetector`、`BallFrameOutcome`、`BallObservation`、`BallColor`（Task 1）、`FrameImage`、`BallCandidateFinder`、`BallCandidate`（Task 2）、`BallTrackState`（Task 3）、テスト用の `SyntheticFrame`（Task 2）
- Produces: `public final class MotionColorBallDetector: BallDetector { public init(color: BallColor = .yellowGreen, diameterRange: ClosedRange<Double> = 0.002...0.02, sceneChangeRatio: Double = 0.2) }`

- [ ] **Step 1: 落ちるテストを書く**

`Tests/BallTrackingTests/MotionColorBallDetectorTests.swift`:

```swift
@testable import BallTracking
import CoreVideo
import Testing

struct MotionColorBallDetectorTests {
    private let frame = 1.0 / 60

    /// 止まった黄色の四角と、1 フレームに (12, 4) 画素ずつ動く球。
    private func ballFrame(_ index: Int, background: SyntheticColor = .court) -> SyntheticFrame {
        var frame = SyntheticFrame(background: background)
        frame.fillRect(x: 500, y: 40, width: 30, height: 30, color: .ball)
        frame.fillCircle(centerX: 100 + 12 * Double(index), centerY: 100 + 4 * Double(index), radius: 4, color: .ball)
        return frame
    }

    private func detect(_ detector: MotionColorBallDetector, _ frame: SyntheticFrame, index: Int) throws -> BallFrameOutcome {
        try detector.detect(in: frame.pixelBuffer(), at: Double(index) * self.frame)
    }

    @Test func tracksMovingBallInNormalizedCoordinates() throws {
        let detector = MotionColorBallDetector()
        let outcomes = try (0..<12).map { try detect(detector, ballFrame($0), index: $0) }
        // 最初の 2 枚は比べる相手が無い。3 枚目から候補が出て、0.08 秒たつ 8 枚目（番号 7）から球を出す。
        #expect(outcomes[0..<7].allSatisfy { $0.ball == nil })
        for index in 7..<12 {
            let ball = try #require(outcomes[index].ball)
            // 正規化座標は左下が原点。画素（左上が原点）に戻して比べる。
            #expect(abs(ball.center.x * 640 - (100 + 12 * Double(index))) <= 1.5)
            #expect(abs((1 - ball.center.y) * 360 - (100 + 4 * Double(index))) <= 1.5)
            #expect(abs(ball.radius * 640 - 4) <= 1)
            #expect(outcomes[index].imageSize == CGSize(width: 640, height: 360))
        }
    }

    @Test func dropsTrackOnSceneChange() throws {
        let detector = MotionColorBallDetector()
        for index in 0..<10 {
            _ = try detect(detector, ballFrame(index), index: index)
        }
        let cut = try detect(detector, ballFrame(10, background: .gray), index: 10)
        #expect(cut.sceneChanged)
        #expect(cut.ball == nil)
        let next = try detect(detector, ballFrame(11, background: .gray), index: 11)
        #expect(!next.sceneChanged)
        #expect(next.ball == nil)
    }

    @Test func treatsWholeFrameOfBallColorAsSceneChange() throws {
        let detector = MotionColorBallDetector()
        _ = try detect(detector, SyntheticFrame(), index: 0)
        _ = try detect(detector, SyntheticFrame(), index: 1)
        let outcome = try detect(detector, SyntheticFrame(background: .ball), index: 2)
        #expect(outcome.sceneChanged)
        #expect(outcome.ball == nil)
        #expect(outcome.candidates.isEmpty)
    }

    @Test func returnsNoBallForOtherPixelFormats() throws {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, nil, &buffer)
        let outcome = try MotionColorBallDetector().detect(in: #require(buffer), at: 0)
        #expect(outcome.ball == nil)
        #expect(outcome.imageSize == CGSize(width: 64, height: 64))
    }

    @Test func survivesChangeOfFrameSize() throws {
        let detector = MotionColorBallDetector()
        for index in 0..<3 {
            _ = try detect(detector, ballFrame(index), index: index)
        }
        // 途中で大きさが変わる。覚えているフレームとは比べずに、やり直す。
        let small = try detect(detector, SyntheticFrame(width: 320, height: 180), index: 3)
        #expect(small.ball == nil)
        #expect(small.candidates.isEmpty)
        _ = try detect(detector, SyntheticFrame(width: 320, height: 180), index: 4)
        _ = try detect(detector, ballFrame(5), index: 5)
    }

    @Test func returnsNoBallForTinyFrames() throws {
        let outcome = try MotionColorBallDetector().detect(in: SyntheticFrame(width: 2, height: 2).pixelBuffer(), at: 0)
        #expect(outcome.ball == nil)
    }

    @Test func resetForgetsFrames() throws {
        let detector = MotionColorBallDetector()
        for index in 0..<10 {
            _ = try detect(detector, ballFrame(index), index: index)
        }
        detector.reset()
        // やり直した直後は、比べる相手が無いので候補も出ない。
        let outcome = try detect(detector, ballFrame(10), index: 10)
        #expect(outcome.ball == nil)
        #expect(outcome.candidates.isEmpty)
    }
}
```

- [ ] **Step 2: テストが落ちることを確かめる**

Run: `xcrun swift test --filter MotionColorBallDetectorTests`
Expected: コンパイルエラー（`MotionColorBallDetector` が無い）。

- [ ] **Step 3: 検出器を書く**

`Sources/BallTracking/MotionColorBallDetector.swift`:

```swift
import CoreFoundation
import CoreGraphics
import CoreVideo
import Foundation

/// 動いていて、球の色をしていて、球の大きさの塊を拾い（`BallCandidateFinder`）、時間でつないで球を 1 つに決める（`BallTrackState`）。
///
/// 前の 2 フレームと追跡を覚える。映像の解析のキューから呼ばれるので、ロックで守る。
public final class MotionColorBallDetector: BallDetector, @unchecked Sendable {
    public let method = BallDetectionMethod.motionColor
    /// 球の色。
    public let color: BallColor
    /// 球の直径の範囲（映像の幅に対する割合）。
    public let diameterRange: ClosedRange<Double>
    /// 1 つ前のフレームから動いた画素の割合がこれを超えたら、場面の切り替わりとみなす。
    public let sceneChangeRatio: Double

    private let finder: BallCandidateFinder
    private let lock = NSLock()
    /// 前のフレーム（古い順、2 枚まで）。
    private var frames = [FrameImage]()
    private var state = BallTrackState()

    public init(color: BallColor = .yellowGreen, diameterRange: ClosedRange<Double> = 0.002...0.02, sceneChangeRatio: Double = 0.2) {
        self.color = color
        self.diameterRange = diameterRange
        self.sceneChangeRatio = sceneChangeRatio
        finder = BallCandidateFinder(color: color, diameterRange: diameterRange, sceneChangeRatio: sceneChangeRatio)
    }

    public func detect(in pixelBuffer: CVPixelBuffer, at time: TimeInterval) -> BallFrameOutcome {
        let started = CFAbsoluteTimeGetCurrent()
        var outcome = BallFrameOutcome(
            method: method,
            time: time,
            ball: nil,
            durationMilliseconds: 0,
            imageSize: CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
        )
        if let frame = FrameImage(bgraPixelBuffer: pixelBuffer) {
            lock.withLock { analyze(frame, into: &outcome) }
        }
        outcome.durationMilliseconds = (CFAbsoluteTimeGetCurrent() - started) * 1000
        return outcome
    }

    public func reset() {
        lock.withLock {
            frames = []
            state.reset()
        }
    }

    private func analyze(_ frame: FrameImage, into outcome: inout BallFrameOutcome) {
        // 大きさが変わったら、覚えているフレームとは比べられない。
        if let last = frames.last, last.width != frame.width || last.height != frame.height {
            frames = []
            state.reset()
        }
        defer { frames = Array((frames + [frame]).suffix(2)) }
        guard frames.count == 2 else { return }
        let found = finder.find(current: frame, previous: frames[1], beforePrevious: frames[0])
        guard found.movingRatio <= sceneChangeRatio else {
            state.reset()
            outcome.sceneChanged = true
            return
        }
        outcome.candidates = found.candidates.map {
            observation(center: $0.center, radius: $0.radius, confidence: $0.score, in: frame)
        }
        if let ball = state.update(candidates: found.candidates, time: outcome.time, imageWidth: Double(frame.width)) {
            outcome.ball = observation(center: ball.center, radius: ball.radius, confidence: ball.confidence, in: frame)
        }
    }

    /// 画素の座標（左上が原点）を、正規化座標（左下が原点）にする。
    private func observation(center: SIMD2<Double>, radius: Double, confidence: Double, in frame: FrameImage) -> BallObservation {
        BallObservation(
            center: CGPoint(x: center.x / Double(frame.width), y: 1 - center.y / Double(frame.height)),
            radius: CGFloat(radius / Double(frame.width)),
            confidence: Float(confidence)
        )
    }
}
```

- [ ] **Step 4: テストが通ることを確かめる**

Run: `xcrun swift test --filter MotionColorBallDetectorTests`
Expected: 7 件とも PASS。

- [ ] **Step 5: 全部のテスト、整形、Lint**

Run: `xcrun swift test && swiftformat . && swiftlint lint --strict`
Expected: `CourtFitTests` を含めて全部 PASS、整形と Lint はエラーなし。

- [ ] **Step 6: コミット**

```bash
git add Sources/BallTracking Tests/BallTrackingTests
git commit -m "球の検出器（MotionColorBallDetector）を足す

Co-Authored-By: Claude Fable 5.2 <noreply@anthropic.com>"
```

---

### Task 5: ラリーごとの軌跡と、色

**Files:**
- Create: `Sources/BallTracking/BallRallyTrajectory.swift`
- Create: `Sources/BallTracking/BallRallyPalette.swift`
- Test: `Tests/BallTrackingTests/BallRallyTrajectoryTests.swift`

**Interfaces:**
- Consumes: `BallFrameOutcome`、`BallObservation`（Task 1）
- Produces:
  - `public struct BallSample: Equatable, Sendable { time: TimeInterval; center: CGPoint; radius: CGFloat; confidence: Float }`
  - `public struct BallRallyTrajectory: Equatable, Sendable { public var rallyGap: TimeInterval; public private(set) var rallyIndex: Int; public private(set) var samples: [BallSample]; public init(rallyGap: TimeInterval = 2); public mutating func append(_ outcome: BallFrameOutcome); public mutating func reset() }`
  - `public enum BallRallyPalette { public static let colors: [SIMD3<Double>]; public static func color(forRally index: Int) -> SIMD3<Double> }`

- [ ] **Step 1: 落ちるテストを書く**

`Tests/BallTrackingTests/BallRallyTrajectoryTests.swift`:

```swift
@testable import BallTracking
import CoreGraphics
import Testing

struct BallRallyTrajectoryTests {
    private func outcome(at time: Double, ball: Bool = true, sceneChanged: Bool = false) -> BallFrameOutcome {
        BallFrameOutcome(
            method: .motionColor,
            time: time,
            ball: ball ? BallObservation(center: CGPoint(x: time / 10, y: 0.5), radius: 0.005, confidence: 0.8) : nil,
            sceneChanged: sceneChanged,
            durationMilliseconds: 0,
            imageSize: CGSize(width: 1920, height: 1080)
        )
    }

    @Test func keepsBallsOfCurrentRallyAsSamples() {
        var rally = BallRallyTrajectory()
        rally.append(outcome(at: 0))
        rally.append(outcome(at: 0.1, ball: false))
        rally.append(outcome(at: 0.2))
        #expect(rally.samples.map(\.time) == [0, 0.2])
        #expect(rally.samples[1].center == outcome(at: 0.2).ball?.center)
        #expect(rally.rallyIndex == 0)
    }

    @Test func keepsRallyThroughShortGap() {
        var rally = BallRallyTrajectory()
        rally.append(outcome(at: 0))
        rally.append(outcome(at: 1.9))
        #expect(rally.samples.count == 2)
        #expect(rally.rallyIndex == 0)
    }

    @Test func endsRallyWhenBallIsGoneForRallyGap() {
        var rally = BallRallyTrajectory()
        rally.append(outcome(at: 0))
        rally.append(outcome(at: 0.1))
        // 球が無いまま 2 秒を超えると、点が消えて、次のラリーの番号になる。
        rally.append(outcome(at: 2.2, ball: false))
        #expect(rally.samples.isEmpty)
        #expect(rally.rallyIndex == 1)
        rally.append(outcome(at: 2.3))
        #expect(rally.samples.map(\.time) == [2.3])
        #expect(rally.rallyIndex == 1)
    }

    @Test func startsNextRallyWithBallAfterGap() {
        var rally = BallRallyTrajectory(rallyGap: 1)
        rally.append(outcome(at: 0))
        rally.append(outcome(at: 1.5))
        #expect(rally.samples.map(\.time) == [1.5])
        #expect(rally.rallyIndex == 1)
    }

    @Test func endsRallyOnSceneChange() {
        var rally = BallRallyTrajectory()
        rally.append(outcome(at: 0))
        rally.append(outcome(at: 0.1, ball: false, sceneChanged: true))
        #expect(rally.samples.isEmpty)
        #expect(rally.rallyIndex == 1)
    }

    @Test func doesNotCountRalliesWithoutBalls() {
        var rally = BallRallyTrajectory()
        rally.append(outcome(at: 0, ball: false, sceneChanged: true))
        rally.append(outcome(at: 5, ball: false))
        rally.append(outcome(at: 10, ball: false, sceneChanged: true))
        #expect(rally.rallyIndex == 0)
    }

    @Test func endsRallyWhenTimeGoesBack() {
        var rally = BallRallyTrajectory()
        rally.append(outcome(at: 5))
        rally.append(outcome(at: 1))
        #expect(rally.samples.map(\.time) == [1])
        #expect(rally.rallyIndex == 1)
    }

    @Test func resetClearsSamplesAndIndex() {
        var rally = BallRallyTrajectory()
        rally.append(outcome(at: 0))
        rally.append(outcome(at: 3))
        rally.reset()
        #expect(rally.samples.isEmpty)
        #expect(rally.rallyIndex == 0)
    }

    @Test func paletteChangesColorForEachRallyAndCycles() {
        let count = BallRallyPalette.colors.count
        #expect(count >= 2)
        #expect(BallRallyPalette.color(forRally: 0) != BallRallyPalette.color(forRally: 1))
        #expect(BallRallyPalette.color(forRally: count) == BallRallyPalette.color(forRally: 0))
        #expect(BallRallyPalette.color(forRally: -1) == BallRallyPalette.color(forRally: count - 1))
    }
}
```

- [ ] **Step 2: テストが落ちることを確かめる**

Run: `xcrun swift test --filter BallRallyTrajectoryTests`
Expected: コンパイルエラー（`BallRallyTrajectory` が無い）。

- [ ] **Step 3: 軌跡と色を書く**

`Sources/BallTracking/BallRallyTrajectory.swift`:

```swift
import CoreGraphics
import Foundation

/// 軌跡の 1 点。
public struct BallSample: Equatable, Sendable {
    /// フレームの時刻（秒）。
    public var time: TimeInterval
    /// 球の中心（正規化座標、左下が原点）。
    public var center: CGPoint
    /// 球の半径（映像の幅に対する割合）。
    public var radius: CGFloat
    /// 確からしさ（0〜1）。
    public var confidence: Float

    public init(time: TimeInterval, center: CGPoint, radius: CGFloat, confidence: Float) {
        self.time = time
        self.center = center
        self.radius = radius
        self.confidence = confidence
    }
}

/// 今のラリーの、球の軌跡。
///
/// 球を追えているひと続きを、1 つのラリーとする。球が `rallyGap` 秒見えないか、場面が切り替わったら、ラリーの終わりとして、
/// 軌跡を消し、番号を 1 つ進める。番号は、表示の色を選ぶのに使う（`BallRallyPalette`）。
public struct BallRallyTrajectory: Equatable, Sendable {
    /// 球が見えない時間がこれを超えたら、ラリーの終わりとする（秒）。
    public var rallyGap: TimeInterval
    /// 今のラリーの番号（0 始まり）。軌跡が空のときは、次に始まるラリーの番号。
    public private(set) var rallyIndex = 0
    /// 今のラリーの軌跡（時刻の順）。ラリーが終わると空になる。
    public private(set) var samples = [BallSample]()

    public init(rallyGap: TimeInterval = 2) {
        self.rallyGap = rallyGap
    }

    /// 1 フレームぶんの結果を足す。フレームは時刻の順に渡す。球の無いフレームも渡す（ラリーの終わりを決めるのに使う）。
    public mutating func append(_ outcome: BallFrameOutcome) {
        if let last = samples.last, outcome.sceneChanged || outcome.time - last.time > rallyGap || outcome.time < last.time {
            samples = []
            rallyIndex += 1
        }
        guard let ball = outcome.ball else { return }
        samples.append(BallSample(time: outcome.time, center: ball.center, radius: ball.radius, confidence: ball.confidence))
    }

    /// 軌跡を消し、番号を 0 に戻す。
    public mutating func reset() {
        samples = []
        rallyIndex = 0
    }
}
```

`Sources/BallTracking/BallRallyPalette.swift`:

```swift
import simd

/// ラリーごとの、軌跡の色。
public enum BallRallyPalette {
    /// 色の並び（赤・緑・青、0〜1）。青いコートと木の床の両方で見え、球の黄緑と紛れない色。
    public static let colors: [SIMD3<Double>] = [
        SIMD3(1.0, 0.22, 0.2),
        SIMD3(1.0, 1.0, 1.0),
        SIMD3(1.0, 0.25, 0.85),
        SIMD3(1.0, 0.6, 0.0),
        SIMD3(0.3, 1.0, 0.9),
        SIMD3(0.65, 0.4, 1.0)
    ]

    /// ラリーの番号の色。番号が色の数を超えたら、最初の色に戻る。
    public static func color(forRally index: Int) -> SIMD3<Double> {
        colors[((index % colors.count) + colors.count) % colors.count]
    }
}
```

- [ ] **Step 4: テストが通ることを確かめる**

Run: `xcrun swift test --filter BallRallyTrajectoryTests`
Expected: 9 件とも PASS。

- [ ] **Step 5: 整形と Lint**

Run: `swiftformat . && swiftlint lint --strict`
Expected: どちらもエラーなし。

- [ ] **Step 6: コミット**

```bash
git add Sources/BallTracking Tests/BallTrackingTests
git commit -m "球の軌跡をラリーごとに持ち、ラリーごとの色を決める

Co-Authored-By: Claude Fable 5.2 <noreply@anthropic.com>"
```

---

### Task 6: サンプル動画での書き出し（画像、JSON、集計、動画）

**Files:**
- Modify: `Package.swift`
- Create: `Sources/VideoTestSupport/VideoFrameReader.swift`
- Create: `Sources/VideoTestSupport/VideoFrameWriter.swift`
- Create: `Sources/VideoTestSupport/PixelBufferImages.swift`
- Create: `Tests/BallTrackingTests/BallPreview.swift`
- Create: `Tests/BallTrackingTests/DemoVideoBallReportTests.swift`

**Interfaces:**
- Consumes: `MotionColorBallDetector`（Task 4）、`BallRallyTrajectory`、`BallRallyPalette`（Task 5）
- Produces（`VideoTestSupport`、残りの 3 つのライブラリのテストでも使う）:
  - `public struct VideoFrame { public let pixelBuffer: CVPixelBuffer; public let seconds: Double }`
  - `public final class VideoFrameReader { public let size: CGSize; public let frameRate: Double; public init(url: URL) async throws; public func next() -> VideoFrame? }`
  - `public final class VideoFrameWriter { public init(url: URL, width: Int, height: Int) throws; public func append(_ image: CGImage, at seconds: Double) throws; public func finish() async }`
  - `public func makeImage(from pixelBuffer: CVPixelBuffer) -> CGImage?`、`public func makePixelBuffer(from image: CGImage) throws -> CVPixelBuffer`、`public func writeJPEG(_ image: CGImage, to url: URL) throws`

- [ ] **Step 1: `Package.swift` に `VideoTestSupport` を足す**

`BallTrackingTests` の行を、次の 3 行に置き換える。

```swift
        // テスト用の共通の部品（動画を順に読む、画像と動画を書き出す）。ライブラリとしては出さない。
        .target(name: "VideoTestSupport"),
        .testTarget(name: "BallTrackingTests", dependencies: ["BallTracking", "VideoTestSupport"])
```

- [ ] **Step 2: 画素バッファと画像の変換を書く**

`Sources/VideoTestSupport/PixelBufferImages.swift`:

```swift
import CoreGraphics
import CoreVideo
import Foundation
import ImageIO

/// 32BGRA の画素バッファを、画像にする。
public func makeImage(from pixelBuffer: CVPixelBuffer) -> CGImage? {
    guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA else { return nil }
    CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
    let context = CGContext(
        data: CVPixelBufferGetBaseAddress(pixelBuffer),
        width: CVPixelBufferGetWidth(pixelBuffer),
        height: CVPixelBufferGetHeight(pixelBuffer),
        bitsPerComponent: 8,
        bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
    )
    return context?.makeImage()
}

/// 画像を、同じ大きさの 32BGRA の画素バッファにする。
public func makePixelBuffer(from image: CGImage) throws -> CVPixelBuffer {
    var buffer: CVPixelBuffer?
    let attributes: [CFString: Any] = [kCVPixelBufferCGImageCompatibilityKey: true, kCVPixelBufferCGBitmapContextCompatibilityKey: true]
    let status = CVPixelBufferCreate(
        kCFAllocatorDefault, image.width, image.height, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &buffer
    )
    guard status == kCVReturnSuccess, let buffer else {
        throw CocoaError(.fileWriteUnknown)
    }
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    guard let context = CGContext(
        data: CVPixelBufferGetBaseAddress(buffer),
        width: image.width,
        height: image.height,
        bitsPerComponent: 8,
        bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
    ) else {
        throw CocoaError(.fileWriteUnknown)
    }
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return buffer
}

/// 画像を JPEG で書き出す。
public func writeJPEG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil) else {
        throw CocoaError(.fileWriteUnknown)
    }
    CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
        throw CocoaError(.fileWriteUnknown)
    }
}
```

- [ ] **Step 3: 動画を順に読む部品を書く**

`Sources/VideoTestSupport/VideoFrameReader.swift`:

```swift
import AVFoundation
import CoreVideo

/// 動画の 1 フレーム。
public struct VideoFrame {
    /// 32BGRA の画素。次のフレームを読むと、中身が使い回されることがある。
    public let pixelBuffer: CVPixelBuffer
    /// 動画の先頭からの秒。
    public let seconds: Double
}

public enum VideoFrameReaderError: Error {
    case noVideoTrack
    /// 回して表示する動画（撮影の向きが記録されている動画）は読めない。
    case rotated
    case cannotRead
}

/// 動画のフレームを、先頭から順に、間を飛ばさずに読む。
public final class VideoFrameReader {
    /// フレームの大きさ（ピクセル）。
    public let size: CGSize
    /// 1 秒あたりのフレームの数（動画に書かれている値）。
    public let frameRate: Double
    private let reader: AVAssetReader
    private let output: AVAssetReaderTrackOutput

    public init(url: URL) async throws {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw VideoFrameReaderError.noVideoTrack
        }
        let (naturalSize, transform, rate) = try await track.load(.naturalSize, .preferredTransform, .nominalFrameRate)
        guard transform.isIdentity else {
            throw VideoFrameReaderError.rotated
        }
        size = naturalSize
        frameRate = Double(rate)
        reader = try AVAssetReader(asset: asset)
        output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw VideoFrameReaderError.cannotRead
        }
        reader.add(output)
        guard reader.startReading() else {
            throw reader.error ?? VideoFrameReaderError.cannotRead
        }
    }

    /// 次のフレーム。最後まで読んだら nil。
    public func next() -> VideoFrame? {
        while let sample = output.copyNextSampleBuffer() {
            guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            return VideoFrame(pixelBuffer: buffer, seconds: CMSampleBufferGetPresentationTimeStamp(sample).seconds)
        }
        return nil
    }
}
```

- [ ] **Step 4: 動画を書き出す部品を書く**

`Sources/VideoTestSupport/VideoFrameWriter.swift`:

```swift
import AVFoundation
import CoreGraphics

public enum VideoFrameWriterError: Error {
    case cannotWrite
}

/// 画像を 1 枚ずつ足して、動画（H.264 の mp4）にする。実時間ではなく、できるだけ速く書く。
public final class VideoFrameWriter {
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor

    /// `width` と `height` は偶数であること。同じ場所にファイルがあれば、置き換える。
    public init(url: URL, width: Int, height: Int) throws {
        try? FileManager.default.removeItem(at: url)
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ])
        input.expectsMediaDataInRealTime = false
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        guard writer.canAdd(input) else {
            throw VideoFrameWriterError.cannotWrite
        }
        writer.add(input)
        guard writer.startWriting() else {
            throw writer.error ?? VideoFrameWriterError.cannotWrite
        }
        writer.startSession(atSourceTime: .zero)
    }

    /// 1 枚足す。`image` の大きさは、`init` に渡した大きさと同じであること。`seconds` は、前に足したものより後であること。
    public func append(_ image: CGImage, at seconds: Double) throws {
        while !input.isReadyForMoreMediaData {
            Thread.sleep(forTimeInterval: 0.002)
        }
        let buffer = try makePixelBuffer(from: image)
        guard adaptor.append(buffer, withPresentationTime: CMTime(seconds: seconds, preferredTimescale: 60000)) else {
            throw writer.error ?? VideoFrameWriterError.cannotWrite
        }
    }

    /// 書き終える。
    public func finish() async {
        input.markAsFinished()
        await writer.finishWriting()
    }
}
```

- [ ] **Step 5: 軌跡の点を描く処理を書く**

`Tests/BallTrackingTests/BallPreview.swift`:

```swift
@testable import BallTracking
import CoreGraphics

/// フレームに、球の候補（白い細い輪）、今のラリーの軌跡（ラリーの色の点）、今の球（ラリーの色の輪）を描く。
/// `width` と `height` は、描いた画像の大きさ。
func renderBallPreview(_ frame: CGImage, outcome: BallFrameOutcome, rally: BallRallyTrajectory, width: Int, height: Int) -> CGImage? {
    guard let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return nil
    }
    let size = CGSize(width: width, height: height)
    context.interpolationQuality = .low
    context.draw(frame, in: CGRect(origin: .zero, size: size))
    // 正規化座標は左下が原点。画像の描画も左下が原点なので、そのまま掛ける。
    func circle(_ center: CGPoint, radius: CGFloat) -> CGRect {
        CGRect(x: center.x * size.width - radius, y: center.y * size.height - radius, width: radius * 2, height: radius * 2)
    }
    context.setLineWidth(1)
    context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.8))
    for candidate in outcome.candidates {
        context.strokeEllipse(in: circle(candidate.center, radius: candidate.radius * size.width + 3))
    }
    let color = BallRallyPalette.color(forRally: rally.rallyIndex)
    let rallyColor = CGColor(red: color.x, green: color.y, blue: color.z, alpha: 1)
    context.setFillColor(rallyColor)
    for sample in rally.samples {
        context.fillEllipse(in: circle(sample.center, radius: max(2.5, size.width / 320)))
    }
    if let ball = outcome.ball {
        context.setLineWidth(2)
        context.setStrokeColor(rallyColor)
        context.strokeEllipse(in: circle(ball.center, radius: max(8, ball.radius * size.width * 2)))
    }
    return context.makeImage()
}
```

- [ ] **Step 6: サンプル動画を流して書き出すテストを書く**

`Tests/BallTrackingTests/DemoVideoBallReportTests.swift`:

```swift
@testable import BallTracking

// サンプル動画の全フレームに球の追跡をかけ、結果を書き出す。COURT_DEMO_DIR（動画のフォルダ）と BALL_REPORT_DIR（書き出す先）を
// 指定したときだけ動く。
// 出力: <動画>.json（フレームごとの球の位置）、<動画>-<秒>s.jpg（0.5 秒ごと、軌跡の点つき）、report.md（動画ごとの集計）。
// BALL_VIDEOS（例: 1min-01,1min-04）で動画を絞る。BALL_RENDER_VIDEO=1 で、点を描いた動画 <動画>-ball.mp4 も書く。
import CoreGraphics
import Foundation
import Testing
import VideoTestSupport

/// 1 フレームぶんの書き出し。
struct BallFrameExport: Encodable {
    var video: String
    var seconds: Double
    var imageWidth: Int
    var imageHeight: Int
    /// 球の中心 [x, y]（正規化座標、左下が原点）。球が無ければ nil。
    var ball: [Double]?
    /// 球の半径（映像の幅に対する割合）。
    var radius: Double?
    var confidence: Double?
    /// ラリーの番号（0 始まり）。
    var rally: Int
    var sceneChanged: Bool
    var milliseconds: Double

    init(video: String, outcome: BallFrameOutcome, rally: Int) {
        self.video = video
        seconds = outcome.time
        imageWidth = Int(outcome.imageSize.width)
        imageHeight = Int(outcome.imageSize.height)
        ball = outcome.ball.map { [Double($0.center.x), Double($0.center.y)] }
        radius = outcome.ball.map { Double($0.radius) }
        confidence = outcome.ball.map { Double($0.confidence) }
        self.rally = rally
        sceneChanged = outcome.sceneChanged
        milliseconds = outcome.durationMilliseconds
    }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["COURT_DEMO_DIR"] != nil
        && ProcessInfo.processInfo.environment["BALL_REPORT_DIR"] != nil))
func reportsBallsOnDemoVideos() async throws {
    let environment = ProcessInfo.processInfo.environment
    let demoDirectory = URL(fileURLWithPath: environment["COURT_DEMO_DIR"] ?? "")
    let reportDirectory = URL(fileURLWithPath: environment["BALL_REPORT_DIR"] ?? "")
    try FileManager.default.createDirectory(at: reportDirectory, withIntermediateDirectories: true)
    let only = environment["BALL_VIDEOS"]?.split(separator: ",").map(String.init)
    let videos = try FileManager.default.contentsOfDirectory(at: demoDirectory, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "mp4" }
        .filter { video in only?.contains { video.lastPathComponent.contains($0) } ?? true }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    var report = "# 球の追跡の結果（サンプル動画）\n\n全フレームを流した結果。「球あり」は球を出したフレームの数で、当たっているかは画像で確かめる。\n\n"
    report += "| 動画 | 大きさ | コマ/秒 | フレーム | 球あり | 割合 | ラリー | 平均処理時間（ms） |\n"
    report += "| --- | --- | --- | --- | --- | --- | --- | --- |\n"
    for video in videos {
        report += try await measureBalls(in: video, reportDirectory: reportDirectory, rendersVideo: environment["BALL_RENDER_VIDEO"] == "1")
    }
    try report.write(to: reportDirectory.appendingPathComponent("report.md"), atomically: true, encoding: .utf8)
}

/// 1 本の動画を先頭から流し、画像と JSON（と動画）を書き出す。集計の 1 行を返す。
private func measureBalls(in video: URL, reportDirectory: URL, rendersVideo: Bool) async throws -> String {
    let name = video.deletingPathExtension().lastPathComponent
    let reader = try await VideoFrameReader(url: video)
    // 確認用の画像は、幅 960px に縮める。H.264 は偶数の大きさだけを受ける。
    let width = 960
    let height = Int(960 * reader.size.height / reader.size.width / 2) * 2
    let writer = rendersVideo
        ? try VideoFrameWriter(url: reportDirectory.appendingPathComponent("\(name)-ball.mp4"), width: width, height: height)
        : nil
    let detector = MotionColorBallDetector()
    var rally = BallRallyTrajectory()
    var exports = [BallFrameExport]()
    var nextPreview = 0.0
    while let frame = reader.next() {
        let outcome = detector.detect(in: frame.pixelBuffer, at: frame.seconds)
        rally.append(outcome)
        exports.append(BallFrameExport(video: name, outcome: outcome, rally: rally.rallyIndex))
        let isPreviewTime = frame.seconds >= nextPreview
        guard writer != nil || isPreviewTime, let image = makeImage(from: frame.pixelBuffer),
              let preview = renderBallPreview(image, outcome: outcome, rally: rally, width: width, height: height) else { continue }
        if isPreviewTime {
            nextPreview = (frame.seconds * 2).rounded(.down) / 2 + 0.5
            let seconds = String(format: "%05.1f", frame.seconds)
            try writeJPEG(preview, to: reportDirectory.appendingPathComponent("\(name)-\(seconds)s.jpg"))
        }
        try writer?.append(preview, at: frame.seconds)
    }
    await writer?.finish()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(exports).write(to: reportDirectory.appendingPathComponent("\(name).json"))
    return summaryRow(name: name, reader: reader, exports: exports)
}

private func summaryRow(name: String, reader: VideoFrameReader, exports: [BallFrameExport]) -> String {
    let found = exports.filter { $0.ball != nil }
    let ratio = exports.isEmpty ? 0 : Double(found.count) / Double(exports.count) * 100
    let rallies = Set(found.map(\.rally)).count
    let milliseconds = exports.isEmpty ? 0 : exports.reduce(0) { $0 + $1.milliseconds } / Double(exports.count)
    let size = "\(Int(reader.size.width))×\(Int(reader.size.height))"
    let rate = String(format: "%.0f", reader.frameRate)
    return "| \(name) | \(size) | \(rate) | \(exports.count) | \(found.count) | "
        + String(format: "%.0f%% | %ld | %.1f |\n", ratio, rallies, milliseconds)
}
```

- [ ] **Step 7: ビルドが通り、指定が無ければ動かないことを確かめる**

Run: `xcrun swift test --filter reportsBallsOnDemoVideos`
Expected: ビルドが通り、テストは「skipped」になる。

- [ ] **Step 8: 動画 1 本で動かす**

`OUT` はセッションの一時フォルダ（scratchpad）の中に作る。

```bash
COURT_DEMO_DIR=$PWD/DemoApp/videos BALL_REPORT_DIR=$OUT/ball BALL_VIDEOS=1min-04 BALL_RENDER_VIDEO=1 \
  xcrun swift test -c release -Xswiftc -enable-testing --filter reportsBallsOnDemoVideos
```

Expected: PASS。`$OUT/ball/` に `report.md`、`pickleball-play-demo-1min-04.json`、`pickleball-play-demo-1min-04-*.jpg`（約 120 枚）、`pickleball-play-demo-1min-04-ball.mp4` ができる。画像を数枚開き、点が描かれていること、上下が逆になっていないことを目で確かめる。

- [ ] **Step 9: 全部のテスト、整形、Lint**

Run: `xcrun swift test && swiftformat . && swiftlint lint --strict`
Expected: 全部 PASS、整形と Lint はエラーなし。

- [ ] **Step 10: コミット**

```bash
git add Package.swift Sources/VideoTestSupport Tests/BallTrackingTests
git commit -m "サンプル動画の全フレームで球を追い、軌跡を描いた画像と動画を書き出すテストを足す

Co-Authored-By: Claude Fable 5.2 <noreply@anthropic.com>"
```

---

### Task 7: サンプル動画 13 本で測り、記録する

**Files:**
- Create: `docs/accuracy/ball.md`
- Create: `skills/improve-vision-accuracy/references/ball.md`
- Modify: `skills/improve-vision-accuracy/SKILL.md`（対象の表）
- Modify: `README.md`（冒頭の文と、モジュールの表、「測る」）

**Interfaces:**
- Consumes: `reportsBallsOnDemoVideos`（Task 6）
- Produces: 記録と、測る手順の文書。コードは変えない（明らかな不具合が見つかったときを除く）。

このタスクは、しきい値を動かして精度を上げる作業ではない。今の値でどう当たり、どう外れるかを数と画像で残し、ユーザーと一緒に評価する材料を作る。直すのは、評価のあとに決める。

- [ ] **Step 1: スキルを読む**

`skills/improve-vision-accuracy/SKILL.md` を読み、「測る・見る・比べる」の手順に従う。

- [ ] **Step 2: 13 本を全部測る**

```bash
COURT_DEMO_DIR=$PWD/DemoApp/videos BALL_REPORT_DIR=$OUT/ball-all \
  xcrun swift test -c release -Xswiftc -enable-testing --filter reportsBallsOnDemoVideos
```

Expected: PASS。`$OUT/ball-all/report.md` に 13 行の表ができる。数分かかるので、バックグラウンドで動かす。

- [ ] **Step 3: 画像を並べて目で見る**

```bash
xcrun swiftc -O skills/improve-vision-accuracy/scripts/contact_sheet.swift -o $OUT/contact_sheet
for n in 01 02 03 04 05 06 07 08 09 10 11 12 13; do
  $OUT/contact_sheet $OUT/sheet-$n.jpg 6 320 $(ls $OUT/ball-all/pickleball-play-demo-1min-$n-*.jpg | sort | head -60)
done
```

13 枚の一覧を 1 枚ずつ開き、動画ごとに次を書き留める。

- 球に輪と点が付いているフレームの秒（当たり）
- 球でないものに輪が付いているフレームの秒と、付いた物（外れ）
- 球が見えているのに輪が無いフレームの秒（見逃し）
- ラリーの途中で色が変わった秒、ラリーが終わっても点が残った秒

一覧で小さくて分からないフレームは、元の JPEG を開いて確かめる。

- [ ] **Step 4: ユーザーに見せる動画を書き出す**

当たりの多い動画と、少ない動画を 1 本ずつ選び、点を描いた動画を書き出す（`<a>`、`<b>` は選んだ動画の番号）。

```bash
COURT_DEMO_DIR=$PWD/DemoApp/videos BALL_REPORT_DIR=$OUT/ball-video BALL_VIDEOS=1min-<a>,1min-<b> BALL_RENDER_VIDEO=1 \
  xcrun swift test -c release -Xswiftc -enable-testing --filter reportsBallsOnDemoVideos
```

Expected: `$OUT/ball-video/` に mp4 が 2 本できる。

- [ ] **Step 5: 記録を書く**

`docs/accuracy/ball.md` を、`docs/accuracy/court.md` と同じ形で書く。節と、入れる中身は次のとおり。数と秒は、Step 2 の `report.md` と Step 3 の書き留めから写す。

```markdown
# 球の追跡の精度

- 読み手: 球の追跡を直す人（エージェントを含む）
- 目的: 方式の仕組みと、サンプル動画での結果を残す。直したら、下の「記録」に追記する

## 結論（<測った日>）

<一番よく当たった動画と、当たらなかった動画を、数つきで 2〜3 文。処理時間（Release、1080p の平均 ms）と、目標の 20ms を満たしたか>

足りないところ:

- <目で見て分かった、外れと見逃しの種類を、効く順に>

## 仕組み

<仕様書の「仕組み」の表を、段・処理・ファイルの 3 列で写す>

## 記録

### <測った日> サンプル動画 13 本、全フレーム

しきい値: <出し始めるまで、見失うまで、ラリーの終わり、直径の範囲、色、場面の切り替わりの割合>

<report.md の表を写す。「球あり」は球を出したフレームの数で、当たった数ではないと書く>

目で見た結果（0.5 秒ごとの画像）:

| 動画 | 撮り方 | 当たり | 外れ | 見逃し | ラリーの区切り |
| --- | --- | --- | --- | --- | --- |
<動画ごとに 1 行。数ではなく、どう当たりどう外れたかを書く。全フレームは見ていないことを書く>

確かめていないこと: <実機での速さ、DemoApp での見え方（Task 8 で確かめる）、見ていない動画があればその番号>

## 次の手

<外れと見逃しの種類ごとに、原因の見立てと、試す手を 1 行ずつ>
```

- [ ] **Step 6: 測る手順を書く**

`skills/improve-vision-accuracy/references/ball.md`:

```markdown
# 球の追跡

球の追跡（パッケージの `Sources/BallTracking/`）の精度を測って直すときに読む。

## 方式

方式は `BallDetectionMethod` の値で表す。今あるのは 1 つ。

| rawValue | 画面の名前 | 中身 |
| --- | --- | --- |
| `motionColor` | 動きと色 | 動いていて、球の色をしていて、球の大きさの塊を拾い、時間でつないで球を 1 つに決める（`MotionColorBallDetector`） |

## 測るコマンド

すべてパッケージの直下で実行する。`D=<サンプル動画のフォルダ>`、`OUT=<一時フォルダ>` とする。

| 何を | コマンド | 出るもの |
| --- | --- | --- |
| 全フレームの結果 | `COURT_DEMO_DIR=$D BALL_REPORT_DIR=$OUT/ball xcrun swift test -c release -Xswiftc -enable-testing --filter reportsBallsOnDemoVideos` | `<動画>.json`（フレームごとの球の位置）、`<動画>-<秒>s.jpg`（0.5 秒ごと）、`report.md`（動画ごとの集計） |
| 動画を絞る | 上に `BALL_VIDEOS=1min-01,1min-04` を足す | 名前にその文字を含む動画だけ |
| 点を描いた動画 | 上に `BALL_RENDER_VIDEO=1` を足す | `<動画>-ball.mp4`（全フレーム、幅 960px）。コマ送りで見る |

球の追跡は前のフレームと比べるので、コートの検出のように 2 秒ごとには測れない。必ず全フレームを流す。13 本で数分かかる。

画像の見方: 白い細い輪は候補（追跡で絞る前）、色の点は今のラリーの軌跡、色の輪は今の球。色はラリーの番号で変わる。

`report.md` の「球あり」は、球を出したフレームの数で、当たった数ではない。外れを出していても増えるので、必ず画像で確かめる。

画像を並べる:

    <一時フォルダ>/contact_sheet $OUT/sheet.jpg 6 320 $(ls $OUT/ball/pickleball-play-demo-1min-04-*.jpg | sort | head -60)

## 段

落ちたフレームは、画像の白い輪（候補）で、どの段で落ちたかを決める。

| 段 | 処理 | ファイル | 落ちたときの見え方 |
| --- | --- | --- | --- |
| 1. 場面の切り替わり | 動いた画素が画面の 2 割を超えたら、球を出さずに追跡を捨てる | `BallCandidateFinder.swift` | JSON の `sceneChanged` が true。手持ちの映像で続く |
| 2. 動き | 1 つ前とも 2 つ前とも違う画素を残す | `BallCandidateFinder.swift` | 球に白い輪が無い。球が遅い（頂点、ドロップ）と、前のフレームの球と重なって欠ける |
| 3. 色 | 球の色（`BallColor`）の画素を残す | `BallColor.swift` | 球に白い輪が無い。球が黄緑でない、暗い、ぶれて背景と混ざった |
| 4. 塊 | 大きさと細長さで絞る | `BallCandidateFinder.swift`、`BallBlob.swift` | 球に白い輪が無い。球が小さすぎる、選手や線とつながった |
| 5. 追跡 | 候補を時間でつなぎ、球を 1 つに決める | `BallTrackState.swift`、`BallTrack.swift` | 球に白い輪はあるが、色の輪が無い。または、別の物に色の輪が付く |
| 6. ラリー | 球が 2 秒見えないか、場面が切り替わったら、軌跡を消す | `BallRallyTrajectory.swift` | ラリーの途中で色が変わる、ラリーが終わっても点が残る |

## 正解

球の位置の正解は、まだ無い（2026-11-15 時点）。当たり外れは、画像を目で見て数える。正解を付けるときは、コートの検出と同じく `Tests/BallAnnotations/<動画>.json` に、フレームの秒と球の位置（ピクセル、左上が原点）を置く。
```

（上の「画像を並べる」のコマンドは、文書では 3 つのバッククォートのコードブロックにする。）

- [ ] **Step 7: スキルと README の表に足す**

`skills/improve-vision-accuracy/SKILL.md` の対象の表に、1 行足す（「骨格分析」の行の前）。

```markdown
| 球の追跡（`BallTracking`） | 実装済み。全フレームの書き出しがある。正解はまだ無い | [references/ball.md](references/ball.md) |
```

`README.md` の冒頭の文を、次に置き換える。

```markdown
ラケットを使う球技（ピックルボール、テニス、バドミントンなど）の映像を解析する Swift パッケージ。今はピックルボールのコートの検出と、球の追跡がある。選手の骨格の推定（`PlayerPose`）は、これから足す。
```

`README.md` のモジュールの表に、1 行足す。

```markdown
| `BallTracking` | 連続するフレームから、球の位置を追う。ラリーごとの軌跡と、表示の色も持つ |
```

`README.md` の「使う」の最後（`CourtFit` を Debug でも最適化する段落の前）に、足す。

````markdown
```swift
import BallTracking

let detector = MotionColorBallDetector()
var rally = BallRallyTrajectory()

// フレームが届くたびに、時刻の順に呼ぶ。
let outcome = detector.detect(in: pixelBuffer, at: seconds) // 32BGRA の CVPixelBuffer と、その時刻（秒）
rally.append(outcome)
rally.samples                                      // 今のラリーの軌跡の点（正規化座標、左下が原点）
BallRallyPalette.color(forRally: rally.rallyIndex) // 今のラリーの色
```

球の追跡の仕組みと、サンプル動画での結果は [docs/accuracy/ball.md](docs/accuracy/ball.md) にある。
````

- [ ] **Step 8: コミット**

```bash
git add docs/accuracy/ball.md skills/improve-vision-accuracy README.md
git commit -m "球の追跡をサンプル動画 13 本で測った結果と、測る手順を残す

Co-Authored-By: Claude Fable 5.2 <noreply@anthropic.com>"
```

---

### Task 8: DemoApp の再生画面に、軌跡の点を重ねる

**Files:**
- Modify: `DemoApp/Library/Package.swift`
- Create: `DemoApp/Library/Sources/BallTrackOverlay/BallDotsOverlay.swift`
- Modify: `DemoApp/Library/Sources/VideoPlayback/PlayerView.swift`

**Interfaces:**
- Consumes: `MotionColorBallDetector`、`BallFrameOutcome`（Task 1、4）、`BallRallyTrajectory`、`BallSample`、`BallRallyPalette`（Task 5）、`fitRect(container:video:)`（`CourtLineOverlay`、既存）
- Produces: `public struct BallDotsOverlay: View { public init(samples: [BallSample], rallyIndex: Int, rect: CGRect) }`

`DemoApp` のターゲットは Swift 5 の言語モード（`swiftSettings: [.swiftLanguageMode(.v5)]`）。新しいターゲットも合わせる。`DemoApp` には単体テストが無いので、ビルドとシミュレーターの画面で確かめる。

- [ ] **Step 1: `DemoApp/Library/Package.swift` に、点を描く部品のターゲットを足す**

`CourtLineOverlay` のターゲットの後に足す。

```swift
        // 球の軌跡の点を描く部品
        .target(
            name: "BallTrackOverlay",
            dependencies: [.product(name: "BallTracking", package: "racket-vision")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
```

`VideoPlayback` のターゲットを、次に置き換える。

```swift
        // 動画を流しながら、コートの検出の枠と、球の軌跡の点を重ねる
        .target(
            name: "VideoPlayback",
            dependencies: [
                "CourtLineOverlay",
                "BallTrackOverlay",
                .product(name: "CourtFit", package: "racket-vision"),
                .product(name: "BallTracking", package: "racket-vision")
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
```

- [ ] **Step 2: 点を描く部品を書く**

`DemoApp/Library/Sources/BallTrackOverlay/BallDotsOverlay.swift`:

```swift
import BallTracking
import SwiftUI

/// 球の軌跡を、点で描く。色はラリーの番号で決まり、ラリーが変わると変わる。
public struct BallDotsOverlay: View {
    let samples: [BallSample]
    let rallyIndex: Int
    let rect: CGRect

    public init(samples: [BallSample], rallyIndex: Int, rect: CGRect) {
        self.samples = samples
        self.rallyIndex = rallyIndex
        self.rect = rect
    }

    public var body: some View {
        Canvas { context, _ in
            let color = BallRallyPalette.color(forRally: rallyIndex)
            let shading = GraphicsContext.Shading.color(Color(red: color.x, green: color.y, blue: color.z))
            for sample in samples {
                // BallSample は左下が原点の正規化座標。画面は左上が原点。
                let center = CGPoint(x: rect.minX + sample.center.x * rect.width, y: rect.minY + (1 - sample.center.y) * rect.height)
                context.fill(Path(ellipseIn: CGRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6)), with: shading)
            }
        }
        .allowsHitTesting(false)
    }
}
```

- [ ] **Step 3: 再生画面で、フレームを毎回取って球を追う**

`DemoApp/Library/Sources/VideoPlayback/PlayerView.swift` を直す。

import に 2 行足す（`import AVFoundation` の後）。

```swift
import BallTracking
import BallTrackOverlay
```

`body` の `ZStack` の中、`QuadsOverlay` の行の後に 1 行足す。

```swift
                BallDotsOverlay(samples: model.ballSamples, rallyIndex: model.rallyIndex, rect: rect)
```

`statusText` を、次に置き換える。

```swift
    private var statusText: String {
        let found = model.quads.isEmpty ? "検出なし" : "検出あり"
        let ball = "球 \(model.ballSamples.count) 点（ラリー \(model.rallyIndex + 1)）"
        guard let milliseconds = model.milliseconds else { return "\(found)  \(ball)" }
        return String(format: "%@  %.1f ms  %@", found, milliseconds, ball)
    }
```

`PlayerModel` を、次に置き換える（クラスの説明のコメントから、クラスの終わりまで）。タイマーをやめて、画面の更新のたびに新しいフレームを取る。球は毎フレーム、コートは今までどおり 0.2 秒ごとに検出する。

```swift
/// 検出の結果を持つ、動画の再生の状態。画面の更新のたびに新しいフレームを取り、球の追跡にかける。
/// コートの検出には、0.2 秒ごとにかける。どちらも、前の検出が終わるまで次はかけない（間に合わないフレームは飛ばす）。
@MainActor
final class PlayerModel: ObservableObject {
    let player: AVPlayer
    @Published private(set) var quads: [DetectedQuad] = []
    @Published private(set) var milliseconds: Double?
    @Published private(set) var videoSize: CGSize = .zero
    /// 今のラリーの、球の軌跡。
    @Published private(set) var ballSamples: [BallSample] = []
    @Published private(set) var rallyIndex = 0

    private let item: AVPlayerItem
    private let output: AVPlayerItemVideoOutput
    private let analyzer = CourtAnalyzer(
        detectors: [TrackingLineModelCourtRectangleDetector(searchInterval: 0)],
        switches: CourtMethodSwitches(enabled: [.lineModelTracking])
    )
    private let ballDetector = MotionColorBallDetector()
    private var rally = BallRallyTrajectory()
    private var displayLink: CADisplayLink?
    private var isAnalyzing = false
    private var isTrackingBall = false
    private var lastCourtSample: CFTimeInterval = 0

    init(url: URL) {
        item = AVPlayerItem(url: url)
        output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        item.add(output)
        player = AVPlayer(playerItem: item)
        player.isMuted = true
    }

    func load() async {
        guard let track = try? await item.asset.loadTracks(withMediaType: .video).first,
              let natural = try? await track.load(.naturalSize),
              let transform = try? await track.load(.preferredTransform) else { return }
        let size = natural.applying(transform)
        videoSize = CGSize(width: abs(size.width), height: abs(size.height))
        player.play()
        let link = CADisplayLink(target: DisplayLinkTarget { [weak self] in self?.sample() }, selector: #selector(DisplayLinkTarget.fire))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        player.pause()
    }

    private func sample() {
        let time = output.itemTime(forHostTime: CACurrentMediaTime())
        guard output.hasNewPixelBuffer(forItemTime: time),
              let buffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) else { return }
        let box = PixelBufferBox(buffer: buffer)
        trackBall(in: box, seconds: time.seconds)
        analyzeCourt(in: box)
    }

    private func trackBall(in box: PixelBufferBox, seconds: Double) {
        guard !isTrackingBall else { return }
        isTrackingBall = true
        let detector = ballDetector
        // 検出は画面の外で動かす（画面を止めないため）。結果だけ画面に出す。
        Task.detached(priority: .userInitiated) {
            let outcome = detector.detect(in: box.buffer, at: seconds)
            await MainActor.run { [weak self] in self?.show(outcome) }
        }
    }

    private func analyzeCourt(in box: PixelBufferBox) {
        let now = CACurrentMediaTime()
        guard !isAnalyzing, now - lastCourtSample >= 0.2 else { return }
        lastCourtSample = now
        isAnalyzing = true
        let analyzer = analyzer
        Task.detached(priority: .userInitiated) {
            let outcome = analyzer.analyze(box.buffer, orientation: .up).first
            await MainActor.run { [weak self] in self?.show(outcome) }
        }
    }

    private func show(_ outcome: DetectionOutcome?) {
        isAnalyzing = false
        quads = outcome?.quads ?? []
        milliseconds = outcome?.durationMilliseconds
    }

    private func show(_ outcome: BallFrameOutcome) {
        isTrackingBall = false
        rally.append(outcome)
        ballSamples = rally.samples
        rallyIndex = rally.rallyIndex
    }
}

/// `CADisplayLink` から呼ばれる相手。`CADisplayLink` は相手を強く持つので、モデルを直接渡さない。
private final class DisplayLinkTarget: NSObject {
    private let action: @MainActor () -> Void

    init(action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    @MainActor @objc func fire() {
        action()
    }
}
```

`PixelBufferBox` は、今のまま残す。

- [ ] **Step 4: シミュレーター向けにビルドする**

```bash
cd DemoApp/App && xcodegen generate
xcodebuild -project CourtDemo.xcodeproj -scheme CourtDemo -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -derivedDataPath $OUT/derived ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build
```

Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 5: シミュレーターで確かめる**

シミュレーター（iPhone 18 Pro）を起動し、`$OUT/derived/Build/Products/Debug-iphonesimulator/CourtDemo.app` を入れて起動する。一覧から、Task 7 で当たりの多かった動画を選ぶ。5 秒おきに 4 枚、画面を撮る。

Expected:
- 球の通ったところに、点が並ぶ。
- 下の表示に「球 N 点（ラリー M）」が出て、N が増える。
- ラリーが終わって 2 秒たつと、点が消え、M が 1 つ進む。次のラリーの点は、色が違う。
- コートの枠（ピンクの線）が、今までどおり出る。

確かめられなかった項目は、最後の報告に書く。

- [ ] **Step 6: ルートの整形と Lint**

Run（リポジトリの直下で）: `swiftformat . && swiftlint lint --strict`
Expected: どちらもエラーなし。

- [ ] **Step 7: コミット**

```bash
git add DemoApp/Library
git commit -m "デモの再生画面に、球の軌跡の点を重ねる（ラリーごとに色を変える）

Co-Authored-By: Claude Fable 5.2 <noreply@anthropic.com>"
```

- [ ] **Step 8: 記録に、DemoApp で確かめた結果を足す**

`docs/accuracy/ball.md` の「確かめていないこと」から DemoApp の項目を外し、「記録」の最後に、シミュレーターで見た結果（どの動画で、点がどう出たか、評価用の書き出しと比べて取りこぼしが増えたか）を 2〜3 文で足す。

```bash
git add docs/accuracy/ball.md
git commit -m "球の追跡を DemoApp で確かめた結果を、記録に足す

Co-Authored-By: Claude Fable 5.2 <noreply@anthropic.com>"
```
