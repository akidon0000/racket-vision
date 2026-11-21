# 前の 2 人のうまさの採点（PlayScoring）の実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

- 読み手: この計画で `PlayScoring` を作る人（このリポジトリを初めて触る人でも進められるように書く）
- 目的: 設計（spec）の決めたことを、テストで確かめられる小さな作業に分け、作る順・名前・型・確かめ方を決める

**Goal:** 骨格・コート・球の検出の結果から、手前のペア 2 人（`CourtPlayer.id` 0 と 1）を項目ごとに点数にし、コーチの評価の言葉で返すライブラリ `PlayScoring` を作り、Mac のテストでの採点表と、デモのアプリの採点のシートまでつなぐ。

**Architecture:** 入力は時刻つきの選手（`PlayFrame`）と球（`BallPoint`）だけ。ラリーの区間 → 打球（球の向きの変わり目＋手首）→ 打球の種類 → 項目の値（`Measurement`）→ 点（中央値を直線で 0〜100）→ 分類の点と評価の言葉、の順に、それぞれ別の型で計算する。評価の言葉と項目の結びつきは `Tools/build_rubric.py` で `rubric.json` に書き出し、パッケージの資源として読む。

**Tech Stack:** Swift 6.2（ルートのパッケージ、Swift 6 の言語モード）、Swift Testing、SwiftUI（デモのアプリ、Swift 5 の言語モード）、Python 3（言葉の表を作る道具）

**Spec:** `Docs/superpowers/specs/2026-11-20-play-scoring-design.md`（評価の文面は `Docs/superpowers/specs/2026-11-20-play-scoring-rubric.md`）

## Global Constraints

- 採点するのは `CourtPlayer.id` が 0 と 1 の 2 人だけ。奥の 2 人（2 と 3）は、相手の打球の時刻を知るためにだけ使う。
- 評価の言葉は、`2026-11-20-play-scoring-rubric.md` の文面のまま使う。言葉を作らない・直さない。
- 項目の点は、測った回数が 3 回未満なら出さない（「判定できず」）。
- 良い点は 70 点以上、悪い点・改善点は 40 点以下の言葉を、1 分類につき 3 つまで。
- 選手の検出は 1 秒に 10 回、球の検出は 1 秒に 30 回の前提（2026-11-19 の動画の書き出し）。
- ルートのパッケージは `swift-tools-version: 6.2`、`.iOS(.v18)` と `.macOS(.v14)`。デモのパッケージ（`DemoApp/Library`）は `.iOS(.v18)` と `.macOS(.v15)`、ターゲットは `.swiftLanguageMode(.v5)`。
- コードの説明のコメントは、今のコードと同じく日本語で書く。画面の文言も日本語。
- SwiftLint（`.swiftlint.yml`）: 関数の本体は 40 行まで、型の本体は 200 行まで、ファイルは 400 行まで、循環的複雑度は 10 まで、ファイル名は中の主な型の名前（拡張は `型+何か.swift`）。
- コミットは、ユーザーが頼んだときだけ。各タスクは、テストと lint が通った状態で止める。
- 署名の設定（`DEVELOPMENT_TEAM`）は `project.yml` に書かず、ビルドのコマンドで渡す。Jev の API キー（`~/.config/racket-vision/jev.key`）は表示もコミットもしない。
- シェルの `rm` と `cp` は確認を求める別名になっているので、`/bin/rm -f`、`/bin/cp -f` を使う。`sleep` は使えない。

## Review Focus

spec が触れていないが、使う人がまず出会う入力。各行のテストを、持ち主のタスクに入れてある。

1. コートが見つからない動画（2026-11-19 の 4984、4985、4993、5005）: 位置が全部 nil。落ちずに、位置を使う項目と分類は「判定できず」、構えの項目だけ点が出るのが期待。→ Task 8 `scoresWithoutCourtPositions`
2. 何も無い入力（再生してすぐ「採点」を押した）: ラリー 0 本、2 人とも全部「判定できず」で返るのが期待。→ Task 8 `emptyInputGivesNoScores`
3. 手前の 1 人しか追えていない（番号 1 が出ない）: ペアの項目とキッチンラインへの詰めは出さず、番号 0 の個人の項目は出るのが期待。→ Task 6 `oneNearPlayerSkipsPairMetrics`
4. 2 人の手首の近くで球が向きを変えた: 手首が球に近いほうの選手の打球にするのが期待。→ Task 3 `attributesToNearestWrist`
5. ラリーの外の打球と、2 本目のラリー: ラリーの外の打球は捨て、何球目かはラリーごとに 0 から数え直すのが期待。→ Task 8 `restartsShotIndexPerRally`

---

## ファイルの構成

| ファイル | 役目 |
| --- | --- |
| `Package.swift`（変更） | `PlayScoring` のライブラリとテストのターゲットを足す |
| `Sources/PlayScoring/PlayFrame.swift` | 入力の型 `PlayFrame`、`BallPoint` |
| `Sources/PlayScoring/CourtMeters.swift` | コートの面の座標（0〜1）をメートルで測る |
| `Sources/PlayScoring/PoseGeometry.swift` | 骨格から、パドルの高さ・膝の角度・スタンスの幅・体の高さを測る |
| `Sources/PlayScoring/PlayerTrack.swift` | 番号ごとの、時刻の順の検出。時刻で引く |
| `Sources/PlayScoring/Statistics.swift` | 中央値と相関 |
| `Sources/PlayScoring/Rally.swift` | ラリーの区間 `Rally` と、球からの見つけ方 |
| `Sources/PlayScoring/HitDetector.swift` | 打球 `Hit` を見つける |
| `Sources/PlayScoring/Shot.swift` | 打球の種類 `ShotKind`、場面の印 `ShotTag`、`Shot` |
| `Sources/PlayScoring/ShotClassifier.swift` | 打球に種類とアプローチの印を付ける |
| `Sources/PlayScoring/MetricID.swift` | 項目、観点、基準の値（`Threshold`） |
| `Sources/PlayScoring/Measurement.swift` | 測った値 1 つ、項目ごとの結果 `MetricResult` |
| `Sources/PlayScoring/MetricMeasurer.swift` | ラリーの全体で測る項目 |
| `Sources/PlayScoring/MetricMeasurer+Strokes.swift` | 打球の場面で測る項目 |
| `Sources/PlayScoring/Rubric.swift` | 評価の言葉の表、分類 `CategoryID` |
| `Sources/PlayScoring/Resources/rubric.json` | 評価の言葉と、結びつく項目（`Tools/build_rubric.py` が作る） |
| `Sources/PlayScoring/PlayScorer.swift` | 全部をつなぎ、`PlayScore` を返す |
| `Sources/PlayScoring/PlayScoreReport.swift` | 採点の結果を Markdown にする |
| `Tools/build_rubric.py` | 評価の文面と結びつけの表から `rubric.json` を作る |
| `Tests/PlayScoringTests/*.swift` | 単体のテストと、動画での採点表の書き出し |
| `DemoApp/Library/Package.swift`（変更） | `VideoPlayback` が `PlayScoring` を使う |
| `DemoApp/Library/Sources/VideoPlayback/PlayerView.swift`（変更） | 材料をため、「採点」ボタンと再生の終わりで採点する |
| `DemoApp/Library/Sources/VideoPlayback/PlayScoreSheet.swift` | 採点のシート |
| `Docs/accuracy/scoring.md` | 2026-11-19 の動画での採点の結果と、打球の見分けの当たり具合 |

座標の約束（全部のタスクで共通）:

- 映像の座標は正規化座標（0〜1、左下が原点、y が上）。長さを測るときは、横に `aspect`（幅 ÷ 高さ）を掛けて、縦と横を同じ尺度にする（`PoseGeometry.point`）。
- コートの面の座標（`CourtPlayer.courtPosition`）は、横 0（左のサイドライン）〜1、縦 0（手前のベースライン）〜1（奥のベースライン）。ネットは縦 0.5。
- 「キッチンラインから d m 後ろ」（`CourtMeters.behindKitchenLine`）: 手前の選手は `(13.4112 / 2 − 2.1336) − 縦 × 13.4112`、奥の選手は `縦 × 13.4112 − (13.4112 / 2 + 2.1336)`。キッチンの中は負、ベースラインで 4.572。

---

### Task 1: ターゲットと入力の型、メートルと骨格の測り方

**Files:**
- Modify: `Package.swift`
- Create: `Sources/PlayScoring/PlayFrame.swift`
- Create: `Sources/PlayScoring/CourtMeters.swift`
- Create: `Sources/PlayScoring/PoseGeometry.swift`
- Create: `Sources/PlayScoring/PlayerTrack.swift`
- Create: `Sources/PlayScoring/Statistics.swift`
- Create: `Sources/PlayScoring/Resources/rubric.json`（この時点では仮の `{"categories": []}`。Task 8 で作り直す）
- Test: `Tests/PlayScoringTests/Fixtures.swift`
- Test: `Tests/PlayScoringTests/MeasuringTests.swift`

**Interfaces:**
- Consumes: `PlayerPose` の `CourtPlayer`、`BodyPose`、`PoseJoint`、`PoseKeypoint`、`CourtSide`。`CourtFit` の `CourtModel.pickleball`（`width` 6.096、`length` 13.4112、`kitchenDepth` 2.1336）
- Produces:
  - `public struct PlayFrame { time: TimeInterval; players: [CourtPlayer]; aspect: Double }`
  - `public struct BallPoint { time: TimeInterval; center: CGPoint? }`
  - `enum CourtMeters { static func across(_:) -> Double; static func along(_:) -> Double; static func behindKitchenLine(_:side:) -> Double; static func distance(_:_:) -> Double }`
  - `struct PoseGeometry { init(pose:aspect:); func point(_:) -> SIMD2<Double>?; var bodyHeight: Double?; func paddleHeight(wrist:) -> Double?; var kneeAngle: Double?; var stanceWidth: Double? }`
  - `struct PlayerTrack { struct Sample { time; pose; court: CGPoint?; side: CourtSide }; let id: Int; let samples: [Sample]; static func tracks(from: [PlayFrame]) -> [Int: PlayerTrack]; func sample(near:tolerance:) -> Sample?; func samples(after:through:) -> ArraySlice<Sample> }`
  - `enum Statistics { static func median(_:) -> Double?; static func correlation(_:_:minimumSpread:) -> Double? }`
  - テストの部品: `standingPose(foot:height:paddle:)`、`player(_:foot:court:paddle:detected:)`、`courtPoint(across:behind:side:)`、`frames(from:through:players:)`

- [ ] **Step 1: パッケージにターゲットを足す**

`Package.swift` の `products` の最後（`SceneAdvisor` の後）に足す:

```swift
        .library(name: "SceneAdvisor", targets: ["SceneAdvisor"]),
        .library(name: "PlayScoring", targets: ["PlayScoring"])
```

`targets` の最後（`SceneAdvisorTests` の後）に足す:

```swift
        .testTarget(name: "SceneAdvisorTests", dependencies: ["SceneAdvisor", "BallTracking", "CourtFit", "VideoTestSupport"]),
        // 手前のペア 2 人のうまさの採点。骨格・コート・球の検出の結果だけから計算する。
        .target(name: "PlayScoring", dependencies: ["PlayerPose", "CourtFit"], resources: [.process("Resources")]),
        .testTarget(name: "PlayScoringTests", dependencies: ["PlayScoring", "PlayerPose"])
```

`Sources/PlayScoring/Resources/rubric.json` を、仮の中身で作る（資源のフォルダが空だとビルドが警告を出すため）:

```json
{"categories": []}
```

- [ ] **Step 2: テストの部品を書く**

`Tests/PlayScoringTests/Fixtures.swift`:

```swift
import CoreGraphics
import Foundation
@testable import PlayScoring
import PlayerPose

/// 立った人の骨格（正規化座標。aspect 1 で測る前提）。足元が foot、体の高さ（鼻から足首）が height。
/// paddle は右手首の高さ（腰 0、肩 1）。左手首は腰の高さ。脚はまっすぐ（膝の角度 180 度）、
/// 足首の間隔は 0.06、肩幅は 0.08（スタンスの幅 0.75 倍）。
func standingPose(foot: CGPoint, height: Double = 0.3, paddle: Double = 0.5) -> BodyPose {
    let x = Double(foot.x)
    let y = Double(foot.y)
    let hip = y + 0.5 * height
    let shoulder = y + 0.8 * height
    func key(_ px: Double, _ py: Double) -> PoseKeypoint {
        PoseKeypoint(position: CGPoint(x: px, y: py), confidence: 0.9)
    }
    return BodyPose(joints: [
        .nose: key(x, y + height),
        .neck: key(x, y + 0.85 * height),
        .leftShoulder: key(x - 0.04, shoulder),
        .rightShoulder: key(x + 0.04, shoulder),
        .leftWrist: key(x - 0.05, hip),
        .rightWrist: key(x + 0.06, hip + paddle * (shoulder - hip)),
        .root: key(x, hip),
        .leftHip: key(x - 0.03, hip),
        .rightHip: key(x + 0.03, hip),
        .leftKnee: key(x - 0.03, y + 0.25 * height),
        .rightKnee: key(x + 0.03, y + 0.25 * height),
        .leftAnkle: key(x - 0.03, y),
        .rightAnkle: key(x + 0.03, y)
    ])
}

/// コートの面の座標。across は左のサイドラインからの横の位置（m）、behind は自分の側のキッチンラインから後ろへの距離（m）。
func courtPoint(across: Double, behind: Double, side: CourtSide) -> CGPoint {
    let model = (width: 6.096, length: 13.4112, kitchen: 2.1336)
    let along = side == .near ? (model.length / 2 - model.kitchen) - behind : (model.length / 2 + model.kitchen) + behind
    return CGPoint(x: across / model.width, y: along / model.length)
}

/// 選手 1 人。番号が 2 未満なら手前、それ以外は奥。
func player(_ id: Int, foot: CGPoint, court: CGPoint?, paddle: Double = 0.5, detected: Bool = true) -> CourtPlayer {
    CourtPlayer(
        id: id, pose: standingPose(foot: foot, paddle: paddle), side: id < 2 ? .near : .far, courtPosition: court,
        firstSeen: 0, isDetected: detected
    )
}

/// start から end まで、0.1 秒ごとのフレーム。players は時刻から、そのときの選手を返す。
func frames(from start: Double, through end: Double, players: (Double) -> [CourtPlayer]) -> [PlayFrame] {
    stride(from: 0, through: Int(((end - start) * 10).rounded()), by: 1).map { step in
        let time = start + Double(step) / 10
        return PlayFrame(time: time, players: players(time), aspect: 1)
    }
}
```

- [ ] **Step 3: 測り方のテストを書く**

`Tests/PlayScoringTests/MeasuringTests.swift`:

```swift
import CoreGraphics
@testable import PlayScoring
import PlayerPose
import Testing

struct MeasuringTests {
    @Test func measuresDistanceBehindKitchenLine() {
        // 手前のベースラインは、キッチンラインから 4.572 m 後ろ。奥のネット際は、キッチンの中。
        #expect(abs(CourtMeters.behindKitchenLine(CGPoint(x: 0.5, y: 0), side: .near) - 4.572) < 1e-6)
        #expect(abs(CourtMeters.behindKitchenLine(CGPoint(x: 0.5, y: 1), side: .far) - 4.572) < 1e-6)
        #expect(CourtMeters.behindKitchenLine(CGPoint(x: 0.5, y: 0.49), side: .near) < 0)
        let point = courtPoint(across: 1.5, behind: 2.5, side: .far)
        #expect(abs(CourtMeters.behindKitchenLine(point, side: .far) - 2.5) < 1e-6)
        #expect(abs(CourtMeters.across(point) - 1.5) < 1e-6)
    }

    @Test func measuresStandingPose() throws {
        let geometry = PoseGeometry(pose: standingPose(foot: CGPoint(x: 0.5, y: 0.1), paddle: 0.6), aspect: 1)
        #expect(abs(try #require(geometry.paddleHeight(wrist: .rightWrist)) - 0.6) < 1e-6)
        #expect(abs(try #require(geometry.paddleHeight(wrist: .leftWrist))) < 1e-6)
        #expect(abs(try #require(geometry.kneeAngle) - 180) < 1e-6)
        #expect(abs(try #require(geometry.stanceWidth) - 0.75) < 1e-6)
        #expect(abs(try #require(geometry.bodyHeight) - 0.3) < 1e-6)
    }

    @Test func measuresBentKnee() throws {
        // 腿が横、すねが縦なら 90 度。
        let key = { (x: Double, y: Double) in PoseKeypoint(position: CGPoint(x: x, y: y), confidence: 0.9) }
        let pose = BodyPose(joints: [.leftHip: key(0.4, 0.3), .leftKnee: key(0.5, 0.3), .leftAnkle: key(0.5, 0.2)])
        #expect(abs(try #require(PoseGeometry(pose: pose, aspect: 1).kneeAngle) - 90) < 1e-6)
    }

    @Test func aspectStretchesHorizontalDistances() throws {
        // 横長の映像（aspect 2）では、横の 0.1 は縦の 0.2 と同じ長さ。
        let geometry = PoseGeometry(pose: standingPose(foot: CGPoint(x: 0.5, y: 0.1)), aspect: 2)
        #expect(abs(try #require(geometry.point(.rightAnkle)).x - 1.06) < 1e-9)
    }

    @Test func findsNearestDetectedSample() throws {
        let input = frames(from: 0, through: 1) { time in
            [player(0, foot: CGPoint(x: 0.5, y: 0.1), court: nil, detected: time < 0.55)]
        }
        let track = try #require(PlayerTrack.tracks(from: input)[0])
        // 骨格が見つからなかったフレーム（0.6 秒から後）は入れない。
        #expect(track.samples.count == 6)
        #expect(track.sample(near: 0.33)?.time == 0.3)
        #expect(track.sample(near: 0.8) == nil)
        #expect(track.samples(after: 0.2, through: 0.4).map(\.time) == [0.3, 0.4])
    }

    @Test func computesMedianAndCorrelation() throws {
        #expect(Statistics.median([3, 1, 2]) == 2)
        #expect(Statistics.median([4, 1, 2, 3]) == 2.5)
        #expect(Statistics.median([]) == nil)
        let rising = [0.1, 0.2, 0.3, 0.4]
        #expect(abs(try #require(Statistics.correlation(rising, rising.map { $0 * 2 })) - 1) < 1e-9)
        // 片方がほとんど動かないときは、相関を出さない。
        #expect(Statistics.correlation(rising, [0.5, 0.5, 0.5, 0.5]) == nil)
    }
}
```

`PlayerTrack.Sample` を `==` で比べないので、`Equatable` は要らない。`sample(near:)?.time == 0.3` は `Double` の比較（`0.1 × 3` の丸めが合うよう、`frames` は `start + step / 10` で時刻を作っている）。

- [ ] **Step 4: テストが落ちるのを確かめる**

Run: `xcrun swift test --filter PlayScoringTests 2>&1 | tail -20`
Expected: ビルドの失敗（`cannot find 'PoseGeometry' in scope` など）

- [ ] **Step 5: 入力の型を書く**

`Sources/PlayScoring/PlayFrame.swift`:

```swift
import CoreGraphics
import Foundation
import PlayerPose

/// 採点の材料の 1 フレーム（選手の検出 1 回ぶん）。
public struct PlayFrame: Sendable {
    public var time: TimeInterval
    public var players: [CourtPlayer]
    /// 映像の幅 ÷ 高さ。正規化座標の距離を、縦と横で同じ尺度にするのに使う。
    public var aspect: Double

    public init(time: TimeInterval, players: [CourtPlayer], aspect: Double) {
        self.time = time
        self.players = players
        self.aspect = aspect
    }
}

/// 球の検出 1 回ぶん。
public struct BallPoint: Equatable, Sendable {
    public var time: TimeInterval
    /// 球の中心（正規化座標、左下が原点）。見つからなければ nil。
    public var center: CGPoint?

    public init(time: TimeInterval, center: CGPoint?) {
        self.time = time
        self.center = center
    }
}
```

- [ ] **Step 6: メートルの測り方を書く**

`Sources/PlayScoring/CourtMeters.swift`:

```swift
import CoreGraphics
import CourtFit
import Foundation
import PlayerPose

/// コートの面の座標（横 0〜1、縦 0〜1。縦 0 が手前のベースライン）を、メートルで測る。
enum CourtMeters {
    static let model = CourtModel.pickleball

    /// 横の位置（m、左のサイドラインから）。
    static func across(_ point: CGPoint) -> Double {
        Double(point.x) * model.width
    }

    /// 縦の位置（m、手前のベースラインから）。
    static func along(_ point: CGPoint) -> Double {
        Double(point.y) * model.length
    }

    /// 自分の側のキッチンライン（NVZ の線）から、ベースラインの向きに何 m 後ろにいるか。キッチンの中なら負。
    static func behindKitchenLine(_ point: CGPoint, side: CourtSide) -> Double {
        let half = model.length / 2
        switch side {
        case .near:
            return (half - model.kitchenDepth) - along(point)
        case .far:
            return along(point) - (half + model.kitchenDepth)
        }
    }

    /// 2 点の距離（m）。
    static func distance(_ first: CGPoint, _ second: CGPoint) -> Double {
        hypot(across(first) - across(second), along(first) - along(second))
    }
}
```

- [ ] **Step 7: 骨格の測り方を書く**

`Sources/PlayScoring/PoseGeometry.swift`:

```swift
import Foundation
import PlayerPose
import simd

/// 骨格の点を、縦と横が同じ尺度の座標（横に aspect を掛けた座標）で測る。
struct PoseGeometry {
    let pose: BodyPose
    let aspect: Double

    func point(_ joint: PoseJoint) -> SIMD2<Double>? {
        pose.position(of: joint).map { SIMD2(Double($0.x) * aspect, Double($0.y)) }
    }

    /// 体の高さ（見つかった関節を囲む四角形の高さ）。
    var bodyHeight: Double? {
        guard let box = pose.boundingBox, box.height > 0 else { return nil }
        return Double(box.height)
    }

    /// 手首の高さ。腰の高さを 0、肩の高さを 1 とする。
    func paddleHeight(wrist: PoseJoint) -> Double? {
        guard let hand = point(wrist),
              let hip = point(.root) ?? middle(.leftHip, .rightHip),
              let shoulder = middle(.leftShoulder, .rightShoulder) ?? point(.neck) else { return nil }
        let span = shoulder.y - hip.y
        guard span > 1e-4 else { return nil }
        return (hand.y - hip.y) / span
    }

    /// 膝の角度（度。腿とすねのなす角で、伸ばしきると 180）。測れた脚の平均。
    var kneeAngle: Double? {
        let legs: [(PoseJoint, PoseJoint, PoseJoint)] = [(.leftHip, .leftKnee, .leftAnkle), (.rightHip, .rightKnee, .rightAnkle)]
        let angles = legs.compactMap { hip, knee, ankle -> Double? in
            guard let top = point(hip), let joint = point(knee), let bottom = point(ankle) else { return nil }
            let thigh = top - joint
            let shin = bottom - joint
            let lengths = simd_length(thigh) * simd_length(shin)
            guard lengths > 1e-8 else { return nil }
            return acos(max(-1, min(1, simd_dot(thigh, shin) / lengths))) * 180 / .pi
        }
        return angles.isEmpty ? nil : angles.reduce(0, +) / Double(angles.count)
    }

    /// 両足首の間隔 ÷ 肩幅。
    var stanceWidth: Double? {
        guard let leftAnkle = point(.leftAnkle), let rightAnkle = point(.rightAnkle),
              let leftShoulder = point(.leftShoulder), let rightShoulder = point(.rightShoulder) else { return nil }
        let shoulders = simd_distance(leftShoulder, rightShoulder)
        guard shoulders > 1e-4 else { return nil }
        return simd_distance(leftAnkle, rightAnkle) / shoulders
    }

    /// 2 つの関節の中点。片方だけなら、その関節。
    private func middle(_ first: PoseJoint, _ second: PoseJoint) -> SIMD2<Double>? {
        switch (point(first), point(second)) {
        case let (one?, other?):
            return (one + other) / 2
        case let (one?, nil):
            return one
        case let (nil, other?):
            return other
        case (nil, nil):
            return nil
        }
    }
}
```

- [ ] **Step 8: 選手の時刻の並びを書く**

`Sources/PlayScoring/PlayerTrack.swift`:

```swift
import CoreGraphics
import Foundation
import PlayerPose

/// 1 人の選手の、骨格が見つかったフレームを、時刻の順に並べたもの。
struct PlayerTrack {
    struct Sample {
        var time: TimeInterval
        var pose: BodyPose
        /// コートの上の位置（0〜1）。コートが分からなければ nil。
        var court: CGPoint?
        var side: CourtSide
    }

    let id: Int
    let samples: [Sample]

    /// 番号ごとに分ける。骨格が見つからずに前の骨格を出しているだけのもの（`isDetected` が false）は入れない。
    /// どちら側か分からない選手は、番号から決める（0 と 1 は手前）。
    static func tracks(from frames: [PlayFrame]) -> [Int: PlayerTrack] {
        var grouped = [Int: [Sample]]()
        for frame in frames.sorted(by: { $0.time < $1.time }) {
            for player in frame.players where player.isDetected {
                let side = player.side ?? (player.id < 2 ? .near : .far)
                grouped[player.id, default: []].append(
                    Sample(time: frame.time, pose: player.pose, court: player.courtPosition, side: side)
                )
            }
        }
        return Dictionary(uniqueKeysWithValues: grouped.map { ($0.key, PlayerTrack(id: $0.key, samples: $0.value)) })
    }

    /// time にいちばん近い検出。tolerance 秒より離れていれば nil。
    func sample(near time: TimeInterval, tolerance: TimeInterval = 0.15) -> Sample? {
        let index = firstIndex(atOrAfter: time)
        let candidates = [index - 1, index].filter { samples.indices.contains($0) }
        guard let best = candidates.min(by: { abs(samples[$0].time - time) < abs(samples[$1].time - time) }),
              abs(samples[best].time - time) <= tolerance + 1e-9 else { return nil }
        return samples[best]
    }

    /// start より後（start は含まない）で、end まで（含む）の検出。
    func samples(after start: TimeInterval, through end: TimeInterval) -> ArraySlice<Sample> {
        var low = firstIndex(atOrAfter: start)
        while low < samples.count, samples[low].time <= start {
            low += 1
        }
        var high = low
        while high < samples.count, samples[high].time <= end + 1e-9 {
            high += 1
        }
        return samples[low..<high]
    }

    /// time 以上の最初の位置。無ければ末尾。
    private func firstIndex(atOrAfter time: TimeInterval) -> Int {
        var low = 0
        var high = samples.count
        while low < high {
            let middle = (low + high) / 2
            if samples[middle].time < time {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low
    }
}
```

- [ ] **Step 9: 中央値と相関を書く**

`Sources/PlayScoring/Statistics.swift`:

```swift
import Foundation

/// 採点で使う、値の並びのまとめ方。
enum Statistics {
    /// 中央値。空なら nil。
    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    /// 2 つの並びの相関（ピアソン）。長さが違う、2 つ未満、どちらかの標準偏差が minimumSpread 未満なら nil。
    static func correlation(_ first: [Double], _ second: [Double], minimumSpread: Double = 0.02) -> Double? {
        guard first.count == second.count, first.count >= 2 else { return nil }
        let count = Double(first.count)
        let meanFirst = first.reduce(0, +) / count
        let meanSecond = second.reduce(0, +) / count
        var covariance = 0.0
        var varianceFirst = 0.0
        var varianceSecond = 0.0
        for (one, other) in zip(first, second) {
            covariance += (one - meanFirst) * (other - meanSecond)
            varianceFirst += (one - meanFirst) * (one - meanFirst)
            varianceSecond += (other - meanSecond) * (other - meanSecond)
        }
        guard (varianceFirst / count).squareRoot() >= minimumSpread,
              (varianceSecond / count).squareRoot() >= minimumSpread else { return nil }
        return covariance / (varianceFirst * varianceSecond).squareRoot()
    }
}
```

- [ ] **Step 10: テストが通るのを確かめる**

Run: `xcrun swift test --filter PlayScoringTests 2>&1 | tail -20`
Expected: `MeasuringTests` の 6 つが通る

Run: `swiftlint lint --quiet Sources/PlayScoring Tests/PlayScoringTests`
Expected: 何も出ない

---

### Task 2: ラリーの区間

**Files:**
- Create: `Sources/PlayScoring/Rally.swift`
- Test: `Tests/PlayScoringTests/RallyTests.swift`

**Interfaces:**
- Consumes: `BallPoint`（Task 1）
- Produces: `public struct Rally { start: TimeInterval; end: TimeInterval }`、`static func Rally.find(in balls: [BallPoint], activeCount: Int = 4, maxGap: Int = 3, minimumActiveSeconds: Int = 3) -> [Rally]`

- [ ] **Step 1: テストを書く**

`Tests/PlayScoringTests/RallyTests.swift`:

```swift
import CoreGraphics
@testable import PlayScoring
import Testing

struct RallyTests {
    /// seconds の各秒に、球を 1 秒に 30 回置く。
    private func balls(in seconds: [Int]) -> [BallPoint] {
        seconds.flatMap { second in
            (0..<30).map { BallPoint(time: Double(second) + Double($0) / 30, center: CGPoint(x: 0.5, y: 0.5)) }
        }
    }

    @Test func findsRallyFromActiveSeconds() {
        #expect(Rally.find(in: balls(in: [2, 3, 4, 5])) == [Rally(start: 2, end: 6)])
    }

    @Test func joinsGapsUpToThreeSeconds() {
        // 動いている秒の差が 3 以下（5 の次が 8）ならつなぎ、4 以上（8 の次が 13）なら分ける。plan_clips.py と同じ。
        let found = Rally.find(in: balls(in: [3, 4, 5, 8, 13, 14, 15]))
        #expect(found == [Rally(start: 3, end: 9), Rally(start: 13, end: 16)])
    }

    @Test func dropsShortBurstsAndSparseSeconds() {
        // 動いている秒が 2 秒だけのものは捨てる。球が 1 秒に 3 回しか無い秒は、動いている秒にしない。
        var input = balls(in: [1, 2])
        input += (0..<3).map { BallPoint(time: 20 + Double($0) / 10, center: CGPoint(x: 0.5, y: 0.5)) }
        input.append(BallPoint(time: 30, center: nil))
        #expect(Rally.find(in: input).isEmpty)
    }
}
```

- [ ] **Step 2: テストが落ちるのを確かめる**

Run: `xcrun swift test --filter RallyTests 2>&1 | tail -20`
Expected: ビルドの失敗（`cannot find 'Rally' in scope`）

- [ ] **Step 3: 書く**

`Sources/PlayScoring/Rally.swift`:

```swift
import Foundation

/// ラリーの区間（秒）。
public struct Rally: Equatable, Sendable {
    public var start: TimeInterval
    public var end: TimeInterval

    public init(start: TimeInterval, end: TimeInterval) {
        self.start = start
        self.end = end
    }

    /// 球の検出から、ラリーを見つける。切り出し（`DemoApp/Clips/plan_clips.py`）と同じ決め方。
    ///
    /// 球が 1 秒に activeCount 回以上見つかった秒を「動いている秒」とし、切れ目が maxGap 秒以内ならつなぐ。
    /// 動いている秒が minimumActiveSeconds 秒以上のものだけを、ラリーにする。
    static func find(in balls: [BallPoint], activeCount: Int = 4, maxGap: Int = 3, minimumActiveSeconds: Int = 3) -> [Rally] {
        var counts = [Int: Int]()
        for ball in balls where ball.center != nil && ball.time >= 0 {
            counts[Int(ball.time), default: 0] += 1
        }
        let active = counts.filter { $0.value >= activeCount }.map(\.key).sorted()
        var groups = [[Int]]()
        for second in active {
            if let last = groups.last?.last, second - last <= maxGap {
                groups[groups.count - 1].append(second)
            } else {
                groups.append([second])
            }
        }
        return groups.filter { $0.count >= minimumActiveSeconds }.compactMap { group in
            guard let first = group.first, let last = group.last else { return nil }
            return Rally(start: Double(first), end: Double(last + 1))
        }
    }
}
```

- [ ] **Step 4: テストが通るのを確かめる**

Run: `xcrun swift test --filter RallyTests 2>&1 | tail -20`
Expected: 3 つとも通る

---

### Task 3: 打球の見つけ方

**Files:**
- Create: `Sources/PlayScoring/HitDetector.swift`
- Test: `Tests/PlayScoringTests/HitDetectorTests.swift`

**Interfaces:**
- Consumes: `BallPoint`、`PlayerTrack`、`PoseGeometry`（Task 1）
- Produces:
  - `public struct Hit { time: TimeInterval; playerID: Int; side: CourtSide; ball: CGPoint }`（`public init(time:playerID:side:ball:)`）
  - `struct HitDetector { func hits(balls: [BallPoint], tracks: [Int: PlayerTrack], aspect: Double) -> [Hit] }`

- [ ] **Step 1: テストを書く**

`Tests/PlayScoringTests/HitDetectorTests.swift`:

```swift
import CoreGraphics
@testable import PlayScoring
import PlayerPose
import Testing

struct HitDetectorTests {
    /// 足元 (0.5, 0.1)、体の高さ 0.3 の選手の右手首は (0.56, 0.295)。
    private let wrist = CGPoint(x: 0.56, y: 0.295)

    /// 点を順に通る球（1 秒に 30 回）。waypoints は（時刻、位置）。
    private func path(_ waypoints: [(Double, CGPoint)]) -> [BallPoint] {
        var result = [BallPoint]()
        for (start, end) in zip(waypoints, waypoints.dropFirst()) {
            let steps = Int(((end.0 - start.0) * 30).rounded())
            for step in 0..<steps {
                let ratio = Double(step) / Double(steps)
                let point = CGPoint(
                    x: Double(start.1.x) + (Double(end.1.x) - Double(start.1.x)) * ratio,
                    y: Double(start.1.y) + (Double(end.1.y) - Double(start.1.y)) * ratio
                )
                result.append(BallPoint(time: start.0 + Double(step) / 30, center: point))
            }
        }
        return result
    }

    private func tracks(_ players: [CourtPlayer]) -> [Int: PlayerTrack] {
        PlayerTrack.tracks(from: frames(from: 0, through: 3) { _ in players })
    }

    @Test func findsHitWhereBallTurnsAtWrist() throws {
        let balls = path([(0.5, CGPoint(x: 0.3, y: 0.6)), (1.0, wrist), (1.5, CGPoint(x: 0.7, y: 0.7))])
        let hits = HitDetector().hits(balls: balls, tracks: tracks([player(0, foot: CGPoint(x: 0.5, y: 0.1), court: nil)]), aspect: 1)
        #expect(hits.count == 1)
        let hit = try #require(hits.first)
        #expect(hit.playerID == 0)
        #expect(hit.side == .near)
        #expect(abs(hit.time - 1.0) < 0.05)
    }

    @Test func ignoresTurnsAwayFromPlayersAndStraightFlight() {
        let players = tracks([player(0, foot: CGPoint(x: 0.5, y: 0.1), court: nil)])
        let farTurn = path([(0.5, CGPoint(x: 0.1, y: 0.5)), (1.0, CGPoint(x: 0.1, y: 0.9)), (1.5, CGPoint(x: 0.3, y: 0.5))])
        #expect(HitDetector().hits(balls: farTurn, tracks: players, aspect: 1).isEmpty)
        let straight = path([(0.5, CGPoint(x: 0.3, y: 0.6)), (1.5, CGPoint(x: 0.8, y: 0.1))])
        #expect(HitDetector().hits(balls: straight, tracks: players, aspect: 1).isEmpty)
    }

    @Test func keepsFirstOfQuickSameSideHits() throws {
        // 1.0 秒と 1.3 秒に、同じ選手の手首で向きが変わる。0.4 秒より近いので、先の 1 回だけにする。
        let balls = path([
            (0.5, CGPoint(x: 0.3, y: 0.6)), (1.0, wrist), (1.15, CGPoint(x: 0.75, y: 0.45)),
            (1.3, CGPoint(x: 0.58, y: 0.31)), (1.8, CGPoint(x: 0.8, y: 0.8))
        ])
        let hits = HitDetector().hits(balls: balls, tracks: tracks([player(0, foot: CGPoint(x: 0.5, y: 0.1), court: nil)]), aspect: 1)
        #expect(hits.count == 1)
        #expect(abs(try #require(hits.first).time - 1.0) < 0.05)
    }

    @Test func attributesToNearestWrist() throws {
        // 番号 0 の右手首で向きが変わる。番号 1 は少し離れて立つが、手首は届く範囲（体の高さの 0.6 倍）にある。
        let players = [
            player(0, foot: CGPoint(x: 0.5, y: 0.1), court: nil),
            player(1, foot: CGPoint(x: 0.6, y: 0.1), court: nil)
        ]
        let balls = path([(0.5, CGPoint(x: 0.3, y: 0.6)), (1.0, wrist), (1.5, CGPoint(x: 0.7, y: 0.7))])
        let hits = HitDetector().hits(balls: balls, tracks: tracks(players), aspect: 1)
        #expect(try #require(hits.first).playerID == 0)
    }
}
```

- [ ] **Step 2: テストが落ちるのを確かめる**

Run: `xcrun swift test --filter HitDetectorTests 2>&1 | tail -20`
Expected: ビルドの失敗（`cannot find 'HitDetector' in scope`）

- [ ] **Step 3: 書く**

`Sources/PlayScoring/HitDetector.swift`:

```swift
import CoreGraphics
import Foundation
import PlayerPose
import simd

/// 打球 1 回。
public struct Hit: Equatable, Sendable {
    public var time: TimeInterval
    public var playerID: Int
    public var side: CourtSide
    /// 打った時刻の球の位置（正規化座標）。
    public var ball: CGPoint

    public init(time: TimeInterval, playerID: Int, side: CourtSide, ball: CGPoint) {
        self.time = time
        self.playerID = playerID
        self.side = side
        self.ball = ball
    }
}

/// 球の 2D の向きが大きく変わり、そこに選手の手首がある時刻を、打球とする。
struct HitDetector {
    /// 向きの変わり目 1 つ。
    struct Turn {
        var time: TimeInterval
        var point: CGPoint
        /// 前と後の向きの差（度）。
        var angle: Double
    }

    /// 向きを測る、前後の時間（秒）。
    var window: TimeInterval = 0.1
    /// 打球とみなす、向きの変わりの大きさ（度）。
    var minimumTurn: Double = 60
    /// 向きを測る球の速さの下限（映像の高さ / 秒）。止まった球の揺れを拾わないため。
    var minimumSpeed: Double = 0.1
    /// 手首から球までの距離の上限（体の高さに対する割合）。
    var reach: Double = 0.6
    /// 同じ選手の変わり目がこれより近く続いたら、向きの差の大きいほう 1 つにまとめる（秒）。
    var mergeWithin: TimeInterval = 0.15
    /// 同じ側の打球がこれより近く続いたら、後のほうを捨てる（秒）。
    var sameSideGap: TimeInterval = 0.4

    func hits(balls: [BallPoint], tracks: [Int: PlayerTrack], aspect: Double) -> [Hit] {
        var attributed = [(hit: Hit, angle: Double)]()
        for turn in turns(in: balls, aspect: aspect) {
            guard let hit = attribute(turn, tracks: tracks, aspect: aspect) else { continue }
            if let last = attributed.last, last.hit.playerID == hit.playerID, hit.time - last.hit.time <= mergeWithin {
                if turn.angle > last.angle {
                    attributed[attributed.count - 1] = (hit, turn.angle)
                }
                continue
            }
            attributed.append((hit, turn.angle))
        }
        var result = [Hit]()
        for (hit, _) in attributed {
            if let last = result.last, last.side == hit.side, hit.time - last.time < sameSideGap { continue }
            result.append(hit)
        }
        return result
    }

    /// 球の向きが minimumTurn 度以上変わった点。前は window 秒前まででいちばん古い点、後は window 秒後まででいちばん新しい点と比べる。
    func turns(in balls: [BallPoint], aspect: Double) -> [Turn] {
        let seen = balls.compactMap { ball in ball.center.map { (time: ball.time, point: $0) } }.sorted { $0.time < $1.time }
        var result = [Turn]()
        var lower = 0
        var upper = 0
        for index in seen.indices {
            let current = seen[index]
            while lower < index, seen[lower].time < current.time - window - 1e-9 {
                lower += 1
            }
            upper = max(upper, index)
            while upper + 1 < seen.count, seen[upper + 1].time <= current.time + window + 1e-9 {
                upper += 1
            }
            guard lower < index, upper > index,
                  let angle = turnAngle(seen[lower], current, seen[upper], aspect: aspect) else { continue }
            result.append(Turn(time: current.time, point: current.point, angle: angle))
        }
        return result
    }

    /// 3 点での向きの差（度）。どちらかの速さが minimumSpeed 未満、または差が minimumTurn 未満なら nil。
    private func turnAngle(
        _ before: (time: TimeInterval, point: CGPoint), _ current: (time: TimeInterval, point: CGPoint),
        _ after: (time: TimeInterval, point: CGPoint), aspect: Double
    ) -> Double? {
        func vector(_ from: (time: TimeInterval, point: CGPoint), _ to: (time: TimeInterval, point: CGPoint)) -> SIMD2<Double> {
            let seconds = max(to.time - from.time, 1e-6)
            return SIMD2(Double(to.point.x - from.point.x) * aspect, Double(to.point.y - from.point.y)) / seconds
        }
        let incoming = vector(before, current)
        let outgoing = vector(current, after)
        guard simd_length(incoming) >= minimumSpeed, simd_length(outgoing) >= minimumSpeed else { return nil }
        let cosine = simd_dot(incoming, outgoing) / (simd_length(incoming) * simd_length(outgoing))
        let angle = acos(max(-1, min(1, cosine))) * 180 / .pi
        return angle >= minimumTurn ? angle : nil
    }

    /// 変わり目の球にいちばん近い手首の選手（体の高さの reach 倍以内）。いなければ nil。
    private func attribute(_ turn: Turn, tracks: [Int: PlayerTrack], aspect: Double) -> Hit? {
        let ball = SIMD2(Double(turn.point.x) * aspect, Double(turn.point.y))
        var best: (ratio: Double, id: Int, side: CourtSide)?
        for track in tracks.values.sorted(by: { $0.id < $1.id }) {
            guard let sample = track.sample(near: turn.time) else { continue }
            let geometry = PoseGeometry(pose: sample.pose, aspect: aspect)
            guard let height = geometry.bodyHeight,
                  let nearest = [PoseJoint.leftWrist, .rightWrist].compactMap({ geometry.point($0) })
                  .map({ simd_distance($0, ball) }).min() else { continue }
            let ratio = nearest / height
            if ratio <= reach, ratio < (best?.ratio ?? .infinity) {
                best = (ratio, track.id, sample.side)
            }
        }
        return best.map { Hit(time: turn.time, playerID: $0.id, side: $0.side, ball: turn.point) }
    }
}
```

- [ ] **Step 4: テストが通るのを確かめる**

Run: `xcrun swift test --filter HitDetectorTests 2>&1 | tail -20`
Expected: 4 つとも通る。`attributesToNearestWrist` で番号 1 の左手首（0.55, 0.25）は球の変わり目（0.56, 0.295）から 0.046、体の高さの 0.15 倍で届く範囲に入るが、番号 0 の右手首（距離 0）が近いので 0 になる。

---

### Task 4: 打球の種類

**Files:**
- Create: `Sources/PlayScoring/Shot.swift`
- Create: `Sources/PlayScoring/ShotClassifier.swift`
- Test: `Tests/PlayScoringTests/ShotClassifierTests.swift`

**Interfaces:**
- Consumes: `Hit`（Task 3）、`PlayerTrack`、`CourtMeters`（Task 1）
- Produces:
  - `public enum ShotKind: String { serve, returnShot = "return", dink, volley, drop, drive }`（`public var title: String`）
  - `public enum ShotTag: String { serve, returnShot = "return", dink, volley, drop, drive, approach }`（`init(_ kind: ShotKind)`）
  - `public struct Shot { hit: Hit; rally: Int; index: Int; kind: ShotKind?; isApproach: Bool; var tags: Set<ShotTag> }`（`public init(hit:rally:index:kind:isApproach:)`）
  - `struct ShotClassifier { func classify(_ hits: [Hit], rally: Int, tracks: [Int: PlayerTrack]) -> [Shot] }`

- [ ] **Step 1: テストを書く**

`Tests/PlayScoringTests/ShotClassifierTests.swift`:

```swift
import CoreGraphics
@testable import PlayScoring
import PlayerPose
import Testing

struct ShotClassifierTests {
    /// 4 人が、それぞれ自分の側のキッチンラインから behind[id] m 後ろに立つ（behind が nil ならコートが分からない）。
    private func tracks(behind: [Int: Double?], moving: ((Int, Double) -> Double?)? = nil) -> [Int: PlayerTrack] {
        let input = frames(from: 0, through: 10) { time in
            behind.map { id, distance in
                let side: CourtSide = id < 2 ? .near : .far
                let value = moving?(id, time) ?? distance
                let court = value.map { courtPoint(across: id.isMultiple(of: 2) ? 1.5 : 4.5, behind: $0, side: side) }
                return player(id, foot: CGPoint(x: 0.3 + 0.1 * Double(id), y: 0.1), court: court)
            }
        }
        return PlayerTrack.tracks(from: input)
    }

    private func hit(_ time: Double, _ id: Int) -> Hit {
        Hit(time: time, playerID: id, side: id < 2 ? .near : .far, ball: CGPoint(x: 0.5, y: 0.5))
    }

    @Test func namesServeReturnDinkAndVolley() {
        let everyoneAtKitchen = tracks(behind: [0: 0.5, 1: 0.5, 2: 0.5, 3: 0.5])
        let hits = [hit(1, 2), hit(2, 0), hit(3, 2), hit(4.5, 0), hit(4.8, 3)]
        let kinds = ShotClassifier().classify(hits, rally: 0, tracks: everyoneAtKitchen).map(\.kind)
        // 3 球目は、相手の打球まで 1.5 秒なのでディンク。4 球目は 0.3 秒なのでボレー。最後は相手の打球が無いのでディンク。
        #expect(kinds == [.serve, .returnShot, .dink, .volley, .dink])
    }

    @Test func namesDriveAndDropFromBehindTheKitchen() {
        let nearBack = tracks(behind: [0: 4.0, 1: 4.0, 2: 0.5, 3: 0.5])
        let quick = ShotClassifier().classify([hit(1, 2), hit(2, 1), hit(3, 2), hit(4, 0), hit(4.5, 2)], rally: 0, tracks: nearBack)
        #expect(quick[3].kind == .drive)
        let slow = ShotClassifier().classify([hit(1, 2), hit(2, 1), hit(3, 2), hit(4, 0), hit(5.5, 2)], rally: 0, tracks: nearBack)
        #expect(slow[3].kind == .drop)
    }

    @Test func callsSlowKitchenShotVolleyWhenOpponentIsBack() {
        let farBack = tracks(behind: [0: 0.5, 1: 0.5, 2: 4.0, 3: 0.5])
        let shots = ShotClassifier().classify([hit(1, 2), hit(2, 0), hit(3, 2), hit(4, 0), hit(5.5, 2)], rally: 0, tracks: farBack)
        #expect(shots[3].kind == .volley)
    }

    @Test func marksApproachWhenHitterMovesForward() {
        // 番号 0 は、4 秒までベースライン近く（4.0 m）、5 秒にはキッチンラインの 1.0 m 後ろまで出る。
        let advancing = tracks(behind: [0: 4.0, 1: 4.0, 2: 0.5, 3: 0.5]) { id, time in
            id == 0 && time > 4 ? max(1.0, 4.0 - 3.0 * (time - 4)) : nil
        }
        let shots = ShotClassifier().classify([hit(1, 2), hit(2, 1), hit(3, 2), hit(4, 0), hit(5.5, 2)], rally: 0, tracks: advancing)
        #expect(shots[3].kind == .drop)
        #expect(shots[3].isApproach)
        #expect(shots[3].tags == [.drop, .approach])
        #expect(!shots[1].isApproach)
    }

    @Test func leavesKindEmptyWithoutHitterPosition() {
        let noCourt = tracks(behind: [0: nil, 1: nil, 2: nil, 3: nil])
        let shots = ShotClassifier().classify([hit(1, 2), hit(2, 0), hit(3, 2)], rally: 3, tracks: noCourt)
        #expect(shots.map(\.kind) == [.serve, .returnShot, nil])
        #expect(shots[2].tags.isEmpty)
        #expect(shots.map(\.rally) == [3, 3, 3])
        #expect(shots.map(\.index) == [0, 1, 2])
    }
}
```

- [ ] **Step 2: テストが落ちるのを確かめる**

Run: `xcrun swift test --filter ShotClassifierTests 2>&1 | tail -20`
Expected: ビルドの失敗（`cannot find 'ShotClassifier' in scope`）

- [ ] **Step 3: 打球の型を書く**

`Sources/PlayScoring/Shot.swift`:

```swift
import Foundation

/// 打球の種類。
public enum ShotKind: String, Codable, CaseIterable, Sendable {
    case serve
    case returnShot = "return"
    case dink
    case volley
    case drop
    case drive

    public var title: String {
        switch self {
        case .serve: "サーブ"
        case .returnShot: "リターン"
        case .dink: "ディンク"
        case .volley: "ボレー"
        case .drop: "ドロップ"
        case .drive: "ドライブ"
        }
    }
}

/// 打球の場面の印。種類と、アプローチ（打ってから前に出た）の印。測った値に付け、分類ごとに選ぶのに使う。
public enum ShotTag: String, Codable, CaseIterable, Hashable, Sendable {
    case serve
    case returnShot = "return"
    case dink
    case volley
    case drop
    case drive
    case approach

    init(_ kind: ShotKind) {
        switch kind {
        case .serve: self = .serve
        case .returnShot: self = .returnShot
        case .dink: self = .dink
        case .volley: self = .volley
        case .drop: self = .drop
        case .drive: self = .drive
        }
    }
}

/// 種類を付けた打球。
public struct Shot: Equatable, Sendable {
    public var hit: Hit
    /// ラリーの番号（0 始まり）。
    public var rally: Int
    /// ラリーの中の何球目か（0 始まり）。
    public var index: Int
    /// 種類。打った選手の位置が分からないときは nil（サーブとリターンは、位置に関係なく付く）。
    public var kind: ShotKind?
    /// 打ってから前に出た打球か。
    public var isApproach: Bool

    public init(hit: Hit, rally: Int, index: Int, kind: ShotKind?, isApproach: Bool) {
        self.hit = hit
        self.rally = rally
        self.index = index
        self.kind = kind
        self.isApproach = isApproach
    }

    /// 場面の印。
    public var tags: Set<ShotTag> {
        var tags = Set<ShotTag>()
        if let kind {
            tags.insert(ShotTag(kind))
        }
        if isApproach {
            tags.insert(.approach)
        }
        return tags
    }
}
```

- [ ] **Step 4: 種類の付け方を書く**

`Sources/PlayScoring/ShotClassifier.swift`:

```swift
import Foundation
import PlayerPose

/// 打球に、種類とアプローチの印を付ける。打った選手の位置と、次の相手の打球までの間隔だけで決める（spec の表の順に当てはめる）。
struct ShotClassifier {
    /// キッチンラインから、これより後ろならキッチンライン近くではない（m）。
    var kitchenReach = 1.0
    /// 相手がこれより後ろにいたら、ゆっくりした打球でもディンクにしない（m）。
    var opponentBack = 2.0
    /// キッチンライン近くの打球を、ボレーにする間隔の上限（秒）。
    var volleyGap: TimeInterval = 1.0
    /// 後ろからの打球を、ドライブにする間隔の上限（秒）。
    var driveGap: TimeInterval = 0.9
    /// アプローチを見る、打ってからの時間（秒）と、前に出た距離（m）。
    var approachWindow: TimeInterval = 1.5
    var approachDistance = 1.5

    /// ラリーの中の打球（時刻の順）に、種類を付ける。
    func classify(_ hits: [Hit], rally: Int, tracks: [Int: PlayerTrack]) -> [Shot] {
        hits.enumerated().map { index, hit in
            let gap = hits[(index + 1)...].first { $0.side != hit.side }.map { $0.time - hit.time }
            let behind = distanceBehindKitchen(of: hit.playerID, at: hit.time, tracks: tracks)
            return Shot(
                hit: hit, rally: rally, index: index,
                kind: kind(index: index, hit: hit, behind: behind, gap: gap, tracks: tracks),
                isApproach: isApproach(hit, behind: behind, tracks: tracks)
            )
        }
    }

    private func kind(index: Int, hit: Hit, behind: Double?, gap: TimeInterval?, tracks: [Int: PlayerTrack]) -> ShotKind? {
        switch index {
        case 0:
            return .serve
        case 1:
            return .returnShot
        default:
            guard let behind else { return nil }
            if behind <= kitchenReach {
                if let gap, gap < volleyGap {
                    return .volley
                }
                return isOpponentBack(of: hit, tracks: tracks) ? .volley : .dink
            }
            return (gap.map { $0 < driveGap } ?? false) ? .drive : .drop
        }
    }

    /// 相手の誰かが、キッチンラインから opponentBack m より後ろにいるか。
    private func isOpponentBack(of hit: Hit, tracks: [Int: PlayerTrack]) -> Bool {
        tracks.values.contains { track in
            guard let sample = track.sample(near: hit.time, tolerance: 0.3), sample.side != hit.side,
                  let court = sample.court else { return false }
            return CourtMeters.behindKitchenLine(court, side: sample.side) > opponentBack
        }
    }

    /// 打ってから approachWindow 秒のうちに、approachDistance m 以上前に出たか。
    private func isApproach(_ hit: Hit, behind: Double?, tracks: [Int: PlayerTrack]) -> Bool {
        guard let behind, let track = tracks[hit.playerID] else { return false }
        let later = track.samples(after: hit.time, through: hit.time + approachWindow).compactMap { sample in
            sample.court.map { CourtMeters.behindKitchenLine($0, side: sample.side) }
        }
        guard let closest = later.min() else { return false }
        return behind - closest >= approachDistance
    }

    private func distanceBehindKitchen(of id: Int, at time: TimeInterval, tracks: [Int: PlayerTrack]) -> Double? {
        guard let sample = tracks[id]?.sample(near: time, tolerance: 0.3), let court = sample.court else { return nil }
        return CourtMeters.behindKitchenLine(court, side: sample.side)
    }
}
```

- [ ] **Step 5: テストが通るのを確かめる**

Run: `xcrun swift test --filter ShotClassifierTests 2>&1 | tail -20`
Expected: 5 つとも通る

---

### Task 5: 項目と基準の値、測った値のまとめ

**Files:**
- Create: `Sources/PlayScoring/MetricID.swift`
- Create: `Sources/PlayScoring/Measurement.swift`
- Test: `Tests/PlayScoringTests/MetricTests.swift`

**Interfaces:**
- Consumes: `ShotTag`（Task 4）、`Statistics`（Task 1）
- Produces:
  - `public enum MetricGroup: String { position, stance, pair, stroke }`（`title`）
  - `public enum Threshold { higherIsBetter(good:bad:), lowerIsBetter(good:bad:), band(low:high:badBelow:badAbove:) }`（`public func score(_:) -> Double`）
  - `public enum MetricID: String, CaseIterable { kitchenArrival, transitionZone, paddleHeight, kneeAngle, stanceWidth, pairSpacing, pairCoMovement, pairDepthOffset, reaction, recovery, formSize, rallyLength }`（`title`、`group`、`threshold`、`public func format(_:) -> String`）
  - `public enum MeasurementContext { rally, shot(Set<ShotTag>) }`
  - `public struct Measurement { metric; playerID; time; value; context }`
  - `public struct MetricResult { metric; median: Double?; score: Int?; count: Int }`（`public init(metric:values:)`、`public static let minimumCount = 3`）

- [ ] **Step 1: テストを書く**

`Tests/PlayScoringTests/MetricTests.swift`:

```swift
@testable import PlayScoring
import Testing

struct MetricTests {
    @Test func rampsBetweenGoodAndBad() {
        let lower = Threshold.lowerIsBetter(good: 2, bad: 5)
        #expect(lower.score(1) == 100)
        #expect(lower.score(3.5) == 50)
        #expect(lower.score(6) == 0)
        let higher = Threshold.higherIsBetter(good: 0.6, bad: 0.2)
        #expect(abs(higher.score(0.4) - 50) < 1e-9)
        #expect(higher.score(0.1) == 0)
    }

    @Test func scoresBandFromBothSides() {
        let band = Threshold.band(low: 0.4, high: 0.6, badBelow: 0.2, badAbove: 0.8)
        #expect(band.score(0.5) == 100)
        #expect(abs(band.score(0.3) - 50) < 1e-9)
        #expect(abs(band.score(0.7) - 50) < 1e-9)
        #expect(band.score(0.9) == 0)
    }

    @Test func needsThreeMeasurementsForScore() {
        let two = MetricResult(metric: .reaction, values: [0.3, 0.4])
        #expect(two.count == 2)
        #expect(abs((two.median ?? 0) - 0.35) < 1e-9)
        #expect(two.score == nil)
        // 中央値 0.4 秒は、0.25 秒（100 点）と 0.6 秒（0 点）の間で 57 点。
        let three = MetricResult(metric: .reaction, values: [0.3, 0.4, 0.9])
        #expect(three.score == 57)
        #expect(MetricResult(metric: .reaction, values: []).median == nil)
    }

    @Test func everyMetricHasGroupAndFormat() {
        #expect(MetricID.allCases.count == 12)
        #expect(MetricID.transitionZone.format(0.25) == "25%")
        #expect(MetricID.reaction.format(0.3) == "0.30 秒")
        #expect(MetricID.rallyLength.format(6) == "6.0 球")
        #expect(Set(MetricID.allCases.map(\.group)) == Set(MetricGroup.allCases))
    }
}
```

- [ ] **Step 2: テストが落ちるのを確かめる**

Run: `xcrun swift test --filter MetricTests 2>&1 | tail -20`
Expected: ビルドの失敗（`cannot find 'Threshold' in scope`）

- [ ] **Step 3: 項目を書く**

`Sources/PlayScoring/MetricID.swift`:

```swift
import Foundation

/// 項目の観点（ユーザーが選んだ 4 つ）。
public enum MetricGroup: String, CaseIterable, Sendable {
    case position
    case stance
    case pair
    case stroke

    public var title: String {
        switch self {
        case .position: "ポジション"
        case .stance: "構え"
        case .pair: "ペアの連動"
        case .stroke: "打球"
        }
    }
}

/// 測った値を 0〜100 の点にする基準。「よい」の値の外は 100、「よくない」の値の外は 0、その間は直線。
public enum Threshold: Equatable, Sendable {
    case higherIsBetter(good: Double, bad: Double)
    case lowerIsBetter(good: Double, bad: Double)
    /// low〜high なら 100。badBelow 以下と badAbove 以上は 0。
    case band(low: Double, high: Double, badBelow: Double, badAbove: Double)

    public func score(_ value: Double) -> Double {
        switch self {
        case let .higherIsBetter(good, bad):
            return Threshold.ramp(value, zero: bad, full: good)
        case let .lowerIsBetter(good, bad):
            return Threshold.ramp(-value, zero: -bad, full: -good)
        case let .band(low, high, badBelow, badAbove):
            if value < low {
                return Threshold.ramp(value, zero: badBelow, full: low)
            }
            if value > high {
                return Threshold.ramp(-value, zero: -badAbove, full: -high)
            }
            return 100
        }
    }

    private static func ramp(_ value: Double, zero: Double, full: Double) -> Double {
        guard full != zero else { return value >= full ? 100 : 0 }
        return min(100, max(0, (value - zero) / (full - zero) * 100))
    }
}

/// 測る項目。基準の値は spec の表のとおり。
public enum MetricID: String, Codable, CaseIterable, Sendable {
    case kitchenArrival
    case transitionZone
    case paddleHeight
    case kneeAngle
    case stanceWidth
    case pairSpacing
    case pairCoMovement
    case pairDepthOffset
    case reaction
    case recovery
    case formSize
    case rallyLength

    public var title: String {
        switch self {
        case .kitchenArrival: "キッチンラインへの詰め"
        case .transitionZone: "無人地帯に留まる時間"
        case .paddleHeight: "パドルの高さ"
        case .kneeAngle: "膝の曲げ"
        case .stanceWidth: "スタンスの幅"
        case .pairSpacing: "ペアの間隔"
        case .pairCoMovement: "一緒に動く"
        case .pairDepthOffset: "前後のずれ"
        case .reaction: "反応の速さ"
        case .recovery: "打った後の戻り"
        case .formSize: "フォームの大きさ"
        case .rallyLength: "ラリーの長さ"
        }
    }

    public var group: MetricGroup {
        switch self {
        case .kitchenArrival, .transitionZone: .position
        case .paddleHeight, .kneeAngle, .stanceWidth: .stance
        case .pairSpacing, .pairCoMovement, .pairDepthOffset: .pair
        case .reaction, .recovery, .formSize, .rallyLength: .stroke
        }
    }

    public var threshold: Threshold {
        switch self {
        case .kitchenArrival: .lowerIsBetter(good: 2.0, bad: 5.0)
        case .transitionZone: .lowerIsBetter(good: 0.10, bad: 0.50)
        case .paddleHeight: .higherIsBetter(good: 0.6, bad: 0.2)
        case .kneeAngle: .lowerIsBetter(good: 140, bad: 170)
        case .stanceWidth: .higherIsBetter(good: 1.5, bad: 0.9)
        case .pairSpacing: .band(low: 0.4, high: 0.6, badBelow: 0.2, badAbove: 0.8)
        case .pairCoMovement: .higherIsBetter(good: 0.7, bad: 0.0)
        case .pairDepthOffset: .lowerIsBetter(good: 1.0, bad: 3.0)
        case .reaction: .lowerIsBetter(good: 0.25, bad: 0.6)
        case .recovery: .lowerIsBetter(good: 0.5, bad: 1.2)
        case .formSize: .lowerIsBetter(good: 0.3, bad: 0.8)
        case .rallyLength: .higherIsBetter(good: 8, bad: 3)
        }
    }

    /// 値を、単位つきの文字にする。
    public func format(_ value: Double) -> String {
        switch self {
        case .transitionZone, .pairSpacing: String(format: "%.0f%%", value * 100)
        case .kitchenArrival, .reaction, .recovery: String(format: "%.2f 秒", value)
        case .kneeAngle: String(format: "%.0f 度", value)
        case .stanceWidth: String(format: "%.2f 倍", value)
        case .pairDepthOffset: String(format: "%.1f m", value)
        case .rallyLength: String(format: "%.1f 球", value)
        case .paddleHeight, .pairCoMovement, .formSize: String(format: "%.2f", value)
        }
    }
}
```

- [ ] **Step 4: 測った値を書く**

`Sources/PlayScoring/Measurement.swift`:

```swift
import Foundation

/// 測った場面。ラリーの全体で測った値と、打球の場面で測った値（その打球の印つき）。
public enum MeasurementContext: Equatable, Sendable {
    case rally
    case shot(Set<ShotTag>)
}

/// 測った値 1 つ。
public struct Measurement: Equatable, Sendable {
    public var metric: MetricID
    public var playerID: Int
    /// 測った場面の時刻（秒）。
    public var time: TimeInterval
    public var value: Double
    public var context: MeasurementContext

    public init(metric: MetricID, playerID: Int, time: TimeInterval, value: Double, context: MeasurementContext) {
        self.metric = metric
        self.playerID = playerID
        self.time = time
        self.value = value
        self.context = context
    }
}

/// 項目 1 つの結果。点は、測った値の中央値から出す。
public struct MetricResult: Equatable, Sendable {
    /// 点を出すのに要る、測った回数。
    public static let minimumCount = 3

    public var metric: MetricID
    public var median: Double?
    /// 0〜100。測った回数が minimumCount 未満なら nil（判定できず）。
    public var score: Int?
    public var count: Int

    public init(metric: MetricID, values: [Double]) {
        self.metric = metric
        count = values.count
        median = Statistics.median(values)
        if count >= MetricResult.minimumCount, let median {
            score = Int(metric.threshold.score(median).rounded())
        } else {
            score = nil
        }
    }
}
```

- [ ] **Step 5: テストが通るのを確かめる**

Run: `xcrun swift test --filter MetricTests 2>&1 | tail -20`
Expected: 4 つとも通る

---

### Task 6: 項目の値を測る

**Files:**
- Create: `Sources/PlayScoring/MetricMeasurer.swift`
- Create: `Sources/PlayScoring/MetricMeasurer+Strokes.swift`
- Test: `Tests/PlayScoringTests/MetricMeasurerTests.swift`

**Interfaces:**
- Consumes: `PlayerTrack`、`PoseGeometry`、`CourtMeters`、`Statistics`（Task 1）、`Rally`（Task 2）、`Shot`（Task 4）、`Measurement`、`MetricID`（Task 5）
- Produces: `struct MetricMeasurer { init(tracks:rallies:shots:aspect:); func measurements() -> [Measurement]; func paddleHands() -> [Int: PoseJoint] }`。`shots` は `rallies` と同じ順の、ラリーごとの打球。

- [ ] **Step 1: テストを書く**

`Tests/PlayScoringTests/MetricMeasurerTests.swift`:

```swift
import CoreGraphics
@testable import PlayScoring
import PlayerPose
import Testing

struct MetricMeasurerTests {
    private let rally = Rally(start: 0, end: 20)

    private func shot(_ time: Double, _ id: Int, _ index: Int, _ kind: ShotKind?) -> Shot {
        Shot(
            hit: Hit(time: time, playerID: id, side: id < 2 ? .near : .far, ball: CGPoint(x: 0.56, y: 0.295)),
            rally: 0, index: index, kind: kind, isApproach: false
        )
    }

    /// 0〜20 秒。手前の 2 人は、横 1.5 m と 4.5 m に立つ。behind と paddle は時刻から決める。
    private func measure(
        shots: [Shot], ids: [Int] = [0, 1], behind: @escaping (Int, Double) -> Double = { _, _ in 0.5 },
        across: @escaping (Int, Double) -> Double = { id, _ in id == 0 ? 1.5 : 4.5 },
        paddle: @escaping (Int, Double) -> Double = { _, _ in 0.5 }
    ) -> [Measurement] {
        let input = frames(from: 0, through: 20) { time in
            ids.map { id in
                let side: CourtSide = id < 2 ? .near : .far
                let court = courtPoint(across: across(id, time), behind: behind(id, time), side: side)
                return player(id, foot: CGPoint(x: 0.5, y: 0.1), court: court, paddle: paddle(id, time))
            }
        }
        let measurer = MetricMeasurer(tracks: PlayerTrack.tracks(from: input), rallies: [rally], shots: [shots], aspect: 1)
        return measurer.measurements()
    }

    private func values(_ metric: MetricID, _ id: Int, in measurements: [Measurement]) -> [Double] {
        measurements.filter { $0.metric == metric && $0.playerID == id }.map(\.value)
    }

    private let opening = [(1.0, 2, ShotKind.serve), (2.0, 0, .returnShot), (3.0, 2, .drop)]

    @Test func measuresKitchenArrivalAfterReturn() throws {
        // リターン（2 秒）から、2 人とも 3 秒かけて 4.0 m から 0.5 m まで出る。1.0 m 以内に着くのは 4.6 秒（2.6 秒後）。
        let shots = opening.enumerated().map { shot($0.element.0, $0.element.1, $0.offset, $0.element.2) }
        let result = measure(shots: shots, ids: [0, 1, 2, 3]) { id, time in
            id < 2 ? max(0.5, 4.0 - 3.5 * max(0, time - 2) / 3) : 0.5
        }
        let arrival = try #require(values(.kitchenArrival, 0, in: result).first)
        #expect(abs(arrival - 2.6) < 0.11)
        #expect(values(.kitchenArrival, 1, in: result) == [arrival])
        #expect(result.first { $0.metric == .kitchenArrival }?.context == .shot([.returnShot, .approach]))
    }

    @Test func measuresReactionAndStanceAtOpponentHit() throws {
        // 相手が 3 秒に打つ。番号 0 は 3.2 秒から横へ 1.2 m/秒で動く。3.4 秒で 0.24 m、3.5 秒で 0.36 m なので、
        // 0.3 m を超えるのは 3.5 秒（0.5 秒後）。
        let shots = opening.enumerated().map { shot($0.element.0, $0.element.1, $0.offset, $0.element.2) }
        let result = measure(shots: shots, ids: [0, 1, 2, 3], across: { id, time in
            id == 0 ? 1.5 + 1.2 * max(0, time - 3.2) : (id == 1 ? 4.5 : 3.0)
        }, paddle: { _, _ in 0.6 })
        let reaction = values(.reaction, 0, in: result)
        #expect(reaction.contains { abs($0 - 0.5) < 0.05 })
        #expect(values(.paddleHeight, 0, in: result).allSatisfy { abs($0 - 0.6) < 1e-6 })
        #expect(values(.stanceWidth, 0, in: result).allSatisfy { abs($0 - 0.75) < 1e-6 })
        let dropContext = result.first { $0.metric == .stanceWidth && $0.time == 3.0 }?.context
        #expect(dropContext == .shot([.drop]))
    }

    @Test func measuresRecoveryAndFormAfterOwnHit() throws {
        // 番号 0 が 4 秒にボレー。3.7〜4.0 秒はパドルが 0 で、3.9 秒だけ 1.0（打つ前に振り上げる）。
        // 打った後は 4.5 秒まで 0.2、4.6 秒から 0.7（0.6 秒で戻る）。
        let shots = [shot(1, 2, 0, .serve), shot(2, 0, 1, .returnShot), shot(3, 2, 2, .drop), shot(4, 0, 3, .volley)]
        let result = measure(shots: shots, ids: [0, 1, 2, 3], paddle: { id, time in
            guard id == 0 else { return 0.5 }
            if abs(time - 3.9) < 0.01 { return 1.0 }
            if time > 3.65 && time < 4.05 { return 0 }
            return time > 4 && time < 4.55 ? 0.2 : 0.7
        })
        #expect(values(.recovery, 0, in: result).contains { abs($0 - 0.6) < 0.05 })
        // 3.7→3.8→3.9→4.0 秒で、手首は 0、0.09 上がって 0.09 下がる（肩と腰の間は 0.09）。体の高さ 0.3 で割って 0.6。
        let form = try #require(values(.formSize, 0, in: result).first)
        #expect(abs(form - 0.6) < 0.01)
    }

    @Test func measuresPairAndRallyMetrics() throws {
        // 2 人とも同じ向きに揺れる（相関 1）。横の間隔は 3.0 m（コートの幅の 49%）、前後は同じ。
        let shots = opening.enumerated().map { shot($0.element.0, $0.element.1, $0.offset, $0.element.2) }
        let result = measure(shots: shots, behind: { _, _ in 2.5 }, across: { id, time in
            (id == 0 ? 1.5 : 4.5) + 0.5 * sin(time)
        })
        #expect(abs(try #require(values(.pairSpacing, 0, in: result).first) - 3.0 / 6.096) < 1e-3)
        #expect(abs(try #require(values(.pairDepthOffset, 1, in: result).first)) < 1e-6)
        #expect(abs(try #require(values(.pairCoMovement, 0, in: result).first) - 1) < 1e-6)
        // 3 球目（3 秒）から後、ずっとキッチンラインの 2.5 m 後ろ（無人地帯）にいる。
        #expect(values(.transitionZone, 0, in: result) == [1.0])
        #expect(values(.rallyLength, 1, in: result) == [3])
    }

    @Test func oneNearPlayerSkipsPairMetrics() {
        let shots = opening.enumerated().map { shot($0.element.0, $0.element.1, $0.offset, $0.element.2) }
        let result = measure(shots: shots, ids: [0, 2, 3])
        let pairMetrics: Set<MetricID> = [.pairSpacing, .pairDepthOffset, .pairCoMovement, .kitchenArrival]
        #expect(!result.contains { pairMetrics.contains($0.metric) })
        #expect(!values(.paddleHeight, 0, in: result).isEmpty)
        #expect(values(.paddleHeight, 1, in: result).isEmpty)
    }

    @Test func picksPaddleHandFromHits() {
        let input = frames(from: 0, through: 5) { _ in [player(0, foot: CGPoint(x: 0.5, y: 0.1), court: nil)] }
        // 球は右手首（0.56, 0.295）の位置。左手首は（0.45, 0.25）。
        let measurer = MetricMeasurer(
            tracks: PlayerTrack.tracks(from: input), rallies: [rally], shots: [[shot(2, 0, 1, .returnShot)]], aspect: 1
        )
        #expect(measurer.paddleHands()[0] == .rightWrist)
    }
}
```

- [ ] **Step 2: テストが落ちるのを確かめる**

Run: `xcrun swift test --filter MetricMeasurerTests 2>&1 | tail -20`
Expected: ビルドの失敗（`cannot find 'MetricMeasurer' in scope`）

- [ ] **Step 3: ラリーの全体で測る項目を書く**

`Sources/PlayScoring/MetricMeasurer.swift`:

```swift
import CoreGraphics
import Foundation
import PlayerPose
import simd

/// 手前の 2 人の、項目の値を測る。ラリーの全体で測る項目はここ、打球の場面で測る項目は `MetricMeasurer+Strokes.swift`。
struct MetricMeasurer {
    let tracks: [Int: PlayerTrack]
    let rallies: [Rally]
    /// ラリーごとの打球（`rallies` と同じ順）。
    let shots: [[Shot]]
    let aspect: Double
    /// 採点する 2 人の番号。
    let nearIDs = [0, 1]

    func measurements() -> [Measurement] {
        let hands = paddleHands()
        var result = [Measurement]()
        for (rally, rallyShots) in zip(rallies, shots) {
            result += kitchenArrival(in: rally, shots: rallyShots)
            result += transitionZone(in: rally, shots: rallyShots)
            result += pair(in: rally)
            result += rallyLength(shots: rallyShots)
            for shot in rallyShots {
                if shot.hit.side == .far {
                    result += atOpponentHit(shot, hands: hands)
                } else if nearIDs.contains(shot.hit.playerID) {
                    result += afterOwnHit(shot, hands: hands)
                }
            }
        }
        return result
    }

    /// パドル側の手首。打った瞬間に球に近かった手首の多いほう。打球が無い選手は入れない（使う側で右手にする）。
    func paddleHands() -> [Int: PoseJoint] {
        var votes = [Int: (left: Int, right: Int)]()
        for shot in shots.joined() {
            guard let sample = tracks[shot.hit.playerID]?.sample(near: shot.hit.time) else { continue }
            let geometry = PoseGeometry(pose: sample.pose, aspect: aspect)
            let ball = SIMD2(Double(shot.hit.ball.x) * aspect, Double(shot.hit.ball.y))
            guard let left = geometry.point(.leftWrist), let right = geometry.point(.rightWrist) else { continue }
            var vote = votes[shot.hit.playerID, default: (0, 0)]
            if simd_distance(left, ball) < simd_distance(right, ball) {
                vote.left += 1
            } else {
                vote.right += 1
            }
            votes[shot.hit.playerID] = vote
        }
        return votes.mapValues { $0.left > $0.right ? .leftWrist : .rightWrist }
    }

    func behind(_ sample: PlayerTrack.Sample) -> Double? {
        sample.court.map { CourtMeters.behindKitchenLine($0, side: sample.side) }
    }

    /// 自分たちがリターンを打ってから、2 人ともキッチンラインから 1 m 以内に着くまでの時間。
    /// ラリーが 5 秒以上続いたのに着かなければ 5.0 秒。リターンの後に位置が 1 回も分からなければ、測らない。
    private func kitchenArrival(in rally: Rally, shots: [Shot]) -> [Measurement] {
        guard shots.count >= 2, shots[1].hit.side == .near,
              let first = tracks[nearIDs[0]], let second = tracks[nearIDs[1]] else { return [] }
        let start = shots[1].hit.time
        let window = first.samples(after: start, through: rally.end)
        guard window.contains(where: { $0.court != nil }) else { return [] }
        let arrived = window.first { sample in
            guard let mine = behind(sample), mine <= 1.0,
                  let partner = second.sample(near: sample.time, tolerance: 0.3), let theirs = behind(partner) else { return false }
            return theirs <= 1.0
        }
        let value: Double
        if let arrived {
            value = arrived.time - start
        } else if rally.end - start >= 5 {
            value = 5
        } else {
            return []
        }
        return nearIDs.map {
            Measurement(metric: .kitchenArrival, playerID: $0, time: start, value: value, context: .shot([.returnShot, .approach]))
        }
    }

    /// 3 球目から後、キッチンラインから 1.5〜3.5 m 後ろに立っていた時間の割合。1 秒（10 回）以上測れた選手だけ。
    private func transitionZone(in rally: Rally, shots: [Shot]) -> [Measurement] {
        guard shots.count >= 3 else { return [] }
        let start = shots[2].hit.time
        return nearIDs.compactMap { id in
            guard let track = tracks[id] else { return nil }
            let distances = track.samples(after: start, through: rally.end).compactMap(behind)
            guard distances.count >= 10 else { return nil }
            let inside = distances.filter { (1.5...3.5).contains($0) }.count
            return Measurement(
                metric: .transitionZone, playerID: id, time: start, value: Double(inside) / Double(distances.count), context: .rally
            )
        }
    }

    /// ペアの間隔、前後のずれ（ともに中央値）、一緒に動く（相関）。2 人に同じ値を付ける。
    private func pair(in rally: Rally) -> [Measurement] {
        guard let first = tracks[nearIDs[0]], let second = tracks[nearIDs[1]] else { return [] }
        let pairs = first.samples(after: rally.start, through: rally.end).compactMap { sample -> (CGPoint, CGPoint)? in
            guard let mine = sample.court, let theirs = second.sample(near: sample.time, tolerance: 0.06)?.court else { return nil }
            return (mine, theirs)
        }
        guard pairs.count >= 10 else { return [] }
        var values = [(MetricID, Double?)]()
        values.append((.pairSpacing, Statistics.median(pairs.map { abs(Double($0.0.x - $0.1.x)) })))
        values.append((.pairDepthOffset, Statistics.median(pairs.map { abs(CourtMeters.along($0.0) - CourtMeters.along($0.1)) })))
        if pairs.count >= 20 {
            values.append((.pairCoMovement, Statistics.correlation(pairs.map { Double($0.0.x) }, pairs.map { Double($0.1.x) })))
        }
        return values.flatMap { metric, value -> [Measurement] in
            guard let value else { return [] }
            return nearIDs.map { Measurement(metric: metric, playerID: $0, time: rally.start, value: value, context: .rally) }
        }
    }

    /// 自分たちが打ったラリーの打球数。
    private func rallyLength(shots: [Shot]) -> [Measurement] {
        guard let first = shots.first, shots.contains(where: { $0.hit.side == .near }) else { return [] }
        return nearIDs.map {
            Measurement(metric: .rallyLength, playerID: $0, time: first.hit.time, value: Double(shots.count), context: .rally)
        }
    }
}
```

- [ ] **Step 4: 打球の場面で測る項目を書く**

`Sources/PlayScoring/MetricMeasurer+Strokes.swift`:

```swift
import Foundation
import PlayerPose
import simd

extension MetricMeasurer {
    /// 相手が打った瞬間の構え（パドルの高さ、膝の曲げ、スタンスの幅）と、反応の速さ。相手の打球の印を付ける。
    func atOpponentHit(_ shot: Shot, hands: [Int: PoseJoint]) -> [Measurement] {
        let time = shot.hit.time
        let context = MeasurementContext.shot(shot.tags)
        var result = [Measurement]()
        for id in nearIDs {
            guard let track = tracks[id], let sample = track.sample(near: time) else { continue }
            let geometry = PoseGeometry(pose: sample.pose, aspect: aspect)
            let values: [(MetricID, Double?)] = [
                (.paddleHeight, geometry.paddleHeight(wrist: hands[id] ?? .rightWrist)),
                (.kneeAngle, geometry.kneeAngle),
                (.stanceWidth, geometry.stanceWidth),
                (.reaction, reaction(of: track, from: sample, at: time))
            ]
            for (metric, value) in values {
                guard let value else { continue }
                result.append(Measurement(metric: metric, playerID: id, time: time, value: value, context: context))
            }
        }
        return result
    }

    /// 打った後の戻りと、フォームの大きさ（ボレー、ディンク、ドロップのときだけ）。自分の打球の印を付ける。
    func afterOwnHit(_ shot: Shot, hands: [Int: PoseJoint]) -> [Measurement] {
        let id = shot.hit.playerID
        let time = shot.hit.time
        guard let track = tracks[id] else { return [] }
        let wrist = hands[id] ?? .rightWrist
        let context = MeasurementContext.shot(shot.tags)
        var result = [Measurement]()
        if let recovery = recovery(of: track, wrist: wrist, after: time) {
            result.append(Measurement(metric: .recovery, playerID: id, time: time, value: recovery, context: context))
        }
        if let kind = shot.kind, [.volley, .dink, .drop].contains(kind), let form = formSize(of: track, wrist: wrist, at: time) {
            result.append(Measurement(metric: .formSize, playerID: id, time: time, value: form, context: context))
        }
        return result
    }

    /// 相手が打ってから、足元が 0.3 m 動くまでの時間。1 秒以内に動かなければ nil。
    private func reaction(of track: PlayerTrack, from sample: PlayerTrack.Sample, at time: TimeInterval) -> Double? {
        guard let start = sample.court else { return nil }
        let moved = track.samples(after: time, through: time + 1.0).first { later in
            later.court.map { CourtMeters.distance(start, $0) >= 0.3 } ?? false
        }
        return moved.map { $0.time - time }
    }

    /// 打ってから、パドルの高さが 0.5 以上に戻るまでの時間。2 秒以内に戻らなければ 2.0 秒。2 秒のうちに 3 回測れなければ nil。
    private func recovery(of track: PlayerTrack, wrist: PoseJoint, after time: TimeInterval) -> Double? {
        let later = track.samples(after: time, through: time + 2.0)
        guard later.count >= 3 else { return nil }
        let back = later.first { sample in
            PoseGeometry(pose: sample.pose, aspect: aspect).paddleHeight(wrist: wrist).map { $0 >= 0.5 } ?? false
        }
        return back.map { $0.time - time } ?? 2.0
    }

    /// 打つ前 0.3 秒の、パドル側の手首の動いた距離 ÷ 体の高さ。
    private func formSize(of track: PlayerTrack, wrist: PoseJoint, at time: TimeInterval) -> Double? {
        let points = track.samples(after: time - 0.31, through: time + 0.05).compactMap { sample in
            PoseGeometry(pose: sample.pose, aspect: aspect).point(wrist)
        }
        guard points.count >= 2, let hit = track.sample(near: time),
              let height = PoseGeometry(pose: hit.pose, aspect: aspect).bodyHeight else { return nil }
        let path = zip(points, points.dropFirst()).reduce(0) { $0 + simd_distance($1.0, $1.1) }
        return path / height
    }
}
```

`MetricMeasurer.swift` の `atOpponentHit` と `afterOwnHit` の呼び出しは、この拡張の関数を使う（`private` にしない。別のファイルの拡張から呼ぶため）。

- [ ] **Step 5: テストが通るのを確かめる**

Run: `xcrun swift test --filter MetricMeasurerTests 2>&1 | tail -20`
Expected: 6 つとも通る

Run: `swiftlint lint --quiet Sources/PlayScoring Tests/PlayScoringTests`
Expected: 何も出ない（`measurements()` と各関数が 40 行以内）

---

### Task 7: 評価の言葉の表

**Files:**
- Create: `Tools/build_rubric.py`
- Create（作り直す）: `Sources/PlayScoring/Resources/rubric.json`
- Create: `Sources/PlayScoring/Rubric.swift`
- Test: `Tests/PlayScoringTests/RubricTests.swift`

**Interfaces:**
- Consumes: `MetricID`、`MeasurementContext`（Task 5）、`ShotTag`（Task 4）、文面 `Docs/superpowers/specs/2026-11-20-play-scoring-rubric.md`
- Produces:
  - `public enum CategoryID: String { dink, volley, drop, drive, approach, serveReturn, physical }`（`func includes(_ context: MeasurementContext) -> Bool`）
  - `public struct Rubric { struct Phrase { text; metrics: [MetricID] }; struct Category { id; title; good; bad; fix; var metrics: Set<MetricID> }; categories: [Category]; static func standard() throws -> Rubric }`

- [ ] **Step 1: 言葉の表を作る道具を書く**

`Tools/build_rubric.py`（結びつけの表は spec の「測る項目」の表の「効く分類」と一致する。言葉はすべて文面にあることを、計画を書いたときに確かめた）:

```python
"""コーチの評価の文面（Docs/superpowers/specs/2026-11-20-play-scoring-rubric.md）から、採点の言葉の表
（Sources/PlayScoring/Resources/rubric.json）を作る。

言葉と項目の結びつき（LINKS）は、ここで手で決める。結びつかない言葉（映像から測れないもの）も表には入れるが、画面には出ない。
文面に無い言葉を結びつけていたら、止まる。
使い方: python3 Tools/build_rubric.py
"""
import json, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(ROOT, "Docs/superpowers/specs/2026-11-20-play-scoring-rubric.md")
OUTPUT = os.path.join(ROOT, "Sources/PlayScoring/Resources/rubric.json")

CATEGORIES = [
    ("dink", "ディンクの評価:", "ディンク"),
    ("volley", "ボレーボレーの評価:", "ボレーボレー"),
    ("drop", "ドロップショットの評価:", "ドロップショット"),
    ("drive", "ドライブの評価:", "ドライブ"),
    ("approach", "アプローチの評価:", "アプローチ"),
    ("serveReturn", "サーブ＆リターンの評価:", "サーブ＆リターン"),
    ("physical", "身体能力などの評価:", "身体能力"),
]
SECTIONS = [("good", "良い点:"), ("bad", "悪い点:"), ("fix", "改善点:")]

POSITION = ["pairSpacing", "pairDepthOffset", "pairCoMovement"]
BALANCE = ["kneeAngle", "stanceWidth"]

# (分類, 区分, 言葉) → 結びつく項目
LINKS = {
    ("dink", "good", "ラリーを長く続けることができる。"): ["rallyLength"],
    ("dink", "good", "ポジションの調整能力が高い。"): POSITION,
    ("dink", "good", "バランスの取り方が基本的に良い。"): BALANCE,
    ("dink", "good", "フットワークの基本が身についている。"): ["reaction"],
    ("dink", "bad", "ポジショニングの微調整が不足している。"): POSITION,
    ("dink", "bad", "フォームが不安定な時がある。"): BALANCE,
    ("dink", "bad", "守りの姿勢への切り替えが遅い場合がある。"): ["reaction", "recovery"],
    ("dink", "fix", "ボールへの入り方やフットワークを見直す。"): ["reaction", "kneeAngle"],
    ("dink", "fix", "自分のフォームを安定させ、余計なリスクを取らないことに意識を向ける。"): BALANCE,
    ("dink", "fix", "守りの姿勢への切り替えを素早く行えるよう練習する。"): ["reaction", "recovery"],

    ("volley", "good", "反射神経が良い能力を持っている。"): ["reaction"],
    ("volley", "good", "相手の打点に対して即座に反応できる能力がある。"): ["reaction", "paddleHeight"],
    ("volley", "good", "ポジショニングの基本を理解している。"): ["pairSpacing", "pairDepthOffset"],
    ("volley", "bad", "相手のボールが速い時に、フォームが大きくなりすぎる傾向がある。"): ["formSize"],
    ("volley", "bad", "ボールへの準備が不十分な場面がある。"): ["paddleHeight", "recovery"],
    ("volley", "bad", "反応が遅い場面がある。"): ["reaction"],
    ("volley", "bad", "ポジショニングが不適切な場面がある。"): ["pairSpacing", "pairDepthOffset"],
    ("volley", "fix", "コンパクトなフォームを意識することが必要である。"): ["formSize"],
    ("volley", "fix", "ボールへの準備を早めに行う習慣をつける。"): ["paddleHeight", "recovery"],
    ("volley", "fix", "反応速度を上げるトレーニングを実施する。"): ["reaction"],
    ("volley", "fix", "高速ボールに対応するための準備姿勢を改善する。"): ["paddleHeight", "kneeAngle"],

    ("drop", "good", "スイングの長さを調整できる。"): ["formSize"],
    ("drop", "bad", "フォームの大きさが一定でない。"): ["formSize"],
    ("drop", "fix", "フォームの一貫性を高める練習をする。"): ["formSize"],

    ("drive", "good", "フォロースルーが適切である。"): ["recovery"],
    ("drive", "good", "フットワークの基礎がある。"): ["reaction"],
    ("drive", "bad", "フォローアップの動きが不足している。"): ["recovery"],
    ("drive", "bad", "相手の返球を予測できていない。"): ["reaction"],
    ("drive", "fix", "フォローアップの動きを改善するドリルを行う。"): ["recovery"],
    ("drive", "fix", "相手の返球を予測する能力を高める。"): ["reaction"],

    ("approach", "good", "ボールを打った後の動きに意識がある。"): ["kitchenArrival", "recovery"],
    ("approach", "good", "前に出るタイミングの基本が分かっている。"): ["kitchenArrival"],
    ("approach", "good", "ドロップショット後の前進の意識がある。"): ["transitionZone"],
    ("approach", "good", "ポジショニングの調整がある程度できている。"): POSITION,
    ("approach", "bad", "打った後すぐに前に出ることができていない場面がある。"): ["kitchenArrival", "transitionZone"],
    ("approach", "bad", "ポジショニングが適切でない場合がある。"): POSITION,
    ("approach", "bad", "反応が遅い場面がある。"): ["reaction"],
    ("approach", "fix", "打った後すぐに前に出ることを意識する。"): ["kitchenArrival", "transitionZone"],
    ("approach", "fix", "適切なポジショニングを取る練習を行う。"): POSITION,
    ("approach", "fix", "反応速度を向上させるトレーニングを行う。"): ["reaction"],

    ("serveReturn", "good", "リターン後の素早いポジショニングができる。"): ["kitchenArrival"],
    ("serveReturn", "good", "リターン時の反応速度が速い。"): ["reaction"],
    ("serveReturn", "bad", "リターン後のポジショニングが遅れることがある。"): ["kitchenArrival"],
    ("serveReturn", "bad", "リターン時のスタンスが不安定なことがある。"): ["stanceWidth"],
    ("serveReturn", "bad", "サーブ後の準備態勢が遅れることがある。"): ["recovery"],
    ("serveReturn", "fix", "リターン後のポジショニングを素早く行う練習をする。"): ["kitchenArrival"],
    ("serveReturn", "fix", "サーブ後の素早い準備態勢の確立を練習する。"): ["recovery"],
    ("serveReturn", "fix", "リターン時のフットワークを改善する。"): ["reaction"],

    ("physical", "good", "反射神経が良く、相手の打点に対して即座に反応できる能力がある。"): ["reaction"],
    ("physical", "good", "次の動作を迅速に行うことができる。"): ["recovery"],
    ("physical", "good", "バランスを保ちながらショットを打つことができる。"): BALANCE,
    ("physical", "good", "素早いポジショニングができる。"): ["kitchenArrival"],
    ("physical", "bad", "相手のボールが速い時に、フォームが大きくなりすぎる傾向がある。"): ["formSize"],
    ("physical", "bad", "ボールを打った後の動きが遅れることがある。"): ["recovery"],
    ("physical", "bad", "バランスを崩しやすく、不安定なショットになることがある。"): BALANCE,
    ("physical", "bad", "相手の打点に対して正確に反応できないことがある。"): ["reaction"],
    ("physical", "fix", "コンパクトなフォームを意識することで、より効率的に対応できるようにする。"): ["formSize"],
    ("physical", "fix", "ボールを打った後の動きを重要視し、次の動作を迅速に行うことを意識する。"): ["recovery"],
    ("physical", "fix", "バランスを崩さないポジショニングを練習する。"): BALANCE,
}


def parse(text):
    """分類 → 区分 → 言葉の並び。見出しの前（読み手・目的の説明）は読まない。"""
    result = {}
    current = None
    section = None
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        heading = next((c for c in CATEGORIES if c[1] == line), None)
        if heading:
            current = heading[0]
            result[current] = {key: [] for key, _ in SECTIONS}
            section = None
            continue
        label = next((key for key, title in SECTIONS if title == line), None)
        if label:
            section = label
            continue
        if current and section:
            result[current][section].append(line)
    return result


def main():
    parsed = parse(open(SOURCE, encoding="utf-8").read())
    used = set()
    categories = []
    for key, _, title in CATEGORIES:
        entry = {"id": key, "title": title}
        for section, _ in SECTIONS:
            phrases = []
            for text in parsed[key][section]:
                metrics = LINKS.get((key, section, text), [])
                if metrics:
                    used.add((key, section, text))
                phrases.append({"text": text, "metrics": metrics})
            entry[section] = phrases
        categories.append(entry)
    missing = set(LINKS) - used
    if missing:
        sys.exit("文面に無い言葉を結びつけている: " + ", ".join(t for _, _, t in sorted(missing)))
    os.makedirs(os.path.dirname(OUTPUT), exist_ok=True)
    with open(OUTPUT, "w", encoding="utf-8") as f:
        json.dump({"categories": categories}, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print(f"{OUTPUT}: {len(categories)} 分類、結びつけた言葉 {len(used)}")


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: 表を作る**

Run: `python3 Tools/build_rubric.py`
Expected: `.../rubric.json: 7 分類、結びつけた言葉 59`

- [ ] **Step 3: テストを書く**

`Tests/PlayScoringTests/RubricTests.swift`:

```swift
@testable import PlayScoring
import Testing

struct RubricTests {
    @Test func loadsAllCategoriesWithPhrases() throws {
        let rubric = try Rubric.standard()
        #expect(rubric.categories.map(\.id) == CategoryID.allCases)
        for category in rubric.categories {
            #expect(category.good.count >= 20)
            #expect(category.bad.count >= 20)
            #expect(category.fix.count >= 20)
            #expect(!category.metrics.isEmpty)
        }
    }

    @Test func linksEveryMetricSomewhere() throws {
        let linked = try Rubric.standard().categories.reduce(into: Set<MetricID>()) { $0.formUnion($1.metrics) }
        #expect(linked == Set(MetricID.allCases))
    }

    @Test func categoriesPickTheirScenes() {
        #expect(CategoryID.dink.includes(.shot([.dink])))
        #expect(!CategoryID.dink.includes(.shot([.volley])))
        #expect(CategoryID.dink.includes(.rally))
        #expect(CategoryID.approach.includes(.shot([.drop, .approach])))
        #expect(CategoryID.serveReturn.includes(.shot([.returnShot, .approach])))
        // 身体能力は、印の無い打球（位置が分からなかった打球）も含めて、すべての場面。
        #expect(CategoryID.physical.includes(.shot([])))
    }
}
```

- [ ] **Step 4: テストが落ちるのを確かめる**

Run: `xcrun swift test --filter RubricTests 2>&1 | tail -20`
Expected: ビルドの失敗（`cannot find 'Rubric' in scope`）

- [ ] **Step 5: 書く**

`Sources/PlayScoring/Rubric.swift`:

```swift
import Foundation

/// 評価の分類（コーチの評価の文面の 7 つ）。
public enum CategoryID: String, Codable, CaseIterable, Sendable {
    case dink
    case volley
    case drop
    case drive
    case approach
    case serveReturn
    case physical

    /// この分類に入れる打球の場面の印。nil は、すべての場面。
    var tags: Set<ShotTag>? {
        switch self {
        case .dink: [.dink]
        case .volley: [.volley]
        case .drop: [.drop]
        case .drive: [.drive]
        case .approach: [.approach]
        case .serveReturn: [.serve, .returnShot]
        case .physical: nil
        }
    }

    /// この場面で測った値を、この分類の点に入れるか。ラリーの全体で測った値は、どの分類にも入れる。
    func includes(_ context: MeasurementContext) -> Bool {
        guard let tags else { return true }
        switch context {
        case .rally:
            return true
        case let .shot(shotTags):
            return !tags.isDisjoint(with: shotTags)
        }
    }
}

/// 評価の言葉の表（`rubric.json`）。言葉は、ユーザーが渡した文面のまま。
public struct Rubric: Decodable, Sendable {
    /// 言葉 1 つと、結びつく項目。項目が空の言葉は、画面に出さない。
    public struct Phrase: Decodable, Sendable {
        public var text: String
        public var metrics: [MetricID]
    }

    public struct Category: Decodable, Sendable {
        public var id: CategoryID
        public var title: String
        public var good: [Phrase]
        public var bad: [Phrase]
        public var fix: [Phrase]

        /// この分類の言葉に結びつく項目。分類の点は、これらの項目の点から出す。
        public var metrics: Set<MetricID> {
            Set((good + bad + fix).flatMap(\.metrics))
        }
    }

    public var categories: [Category]

    /// パッケージに入れた表。`Tools/build_rubric.py` が作る。
    public static func standard() throws -> Rubric {
        guard let url = Bundle.module.url(forResource: "rubric", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(Rubric.self, from: Data(contentsOf: url))
    }
}
```

- [ ] **Step 6: テストが通るのを確かめる**

Run: `xcrun swift test --filter RubricTests 2>&1 | tail -20`
Expected: 3 つとも通る

---

### Task 8: 全部をつなぐ採点と、Markdown の書き出し

**Files:**
- Create: `Sources/PlayScoring/PlayScorer.swift`
- Create: `Sources/PlayScoring/PlayScoreReport.swift`
- Test: `Tests/PlayScoringTests/PlayScorerTests.swift`

**Interfaces:**
- Consumes: ここまでのすべて
- Produces:
  - `public struct GroupScore { group: MetricGroup; score: Int? }`
  - `public struct CategoryScore { id: CategoryID; title: String; score: Int?; good: [String]; bad: [String]; fix: [String] }`
  - `public struct PlayerScore { id: Int; metrics: [MetricResult]; groups: [GroupScore]; categories: [CategoryScore] }`
  - `public struct PlayScore { rallies: [Rally]; shots: [Shot]; players: [PlayerScore] }`
  - `public struct PlayScorer { public init(rubric:); public func score(frames:balls:) -> PlayScore }`
  - `public enum PlayScoreReport { public static func markdown(_:title:) -> String }`

- [ ] **Step 1: テストを書く**

`Tests/PlayScoringTests/PlayScorerTests.swift`:

```swift
import CoreGraphics
import Foundation
@testable import PlayScoring
import Testing

struct PlayScorerTests {
    /// 分類 1 つ、良い点・悪い点・改善点が 1 つずつの表。
    private func rubric(_ id: CategoryID, metric: MetricID) throws -> Rubric {
        let json = """
        {"categories": [{"id": "\(id.rawValue)", "title": "分類", \
        "good": [{"text": "よい", "metrics": ["\(metric.rawValue)"]}, {"text": "結びつかない", "metrics": []}], \
        "bad": [{"text": "わるい", "metrics": ["\(metric.rawValue)"]}], \
        "fix": [{"text": "なおす", "metrics": ["\(metric.rawValue)"]}]}]}
        """
        return try JSONDecoder().decode(Rubric.self, from: Data(json.utf8))
    }

    private func reactions(_ values: [Double], tags: Set<ShotTag>) -> [Measurement] {
        values.enumerated().map { Measurement(metric: .reaction, playerID: 0, time: Double($0.offset), value: $0.element, context: .shot(tags)) }
    }

    @Test func picksGoodPhrasesForHighScores() throws {
        let scorer = PlayScorer(rubric: try rubric(.volley, metric: .reaction))
        let player = scorer.playerScore(id: 0, measurements: reactions([0.2, 0.2, 0.2], tags: [.volley]))
        let category = try #require(player.categories.first)
        #expect(category.score == 100)
        #expect(category.good == ["よい"])
        #expect(category.bad.isEmpty)
        #expect(player.groups.first { $0.group == .stroke }?.score == 100)
    }

    @Test func picksBadAndFixPhrasesForLowScores() throws {
        let scorer = PlayScorer(rubric: try rubric(.volley, metric: .reaction))
        let category = try #require(scorer.playerScore(id: 0, measurements: reactions([0.7, 0.8, 0.9], tags: [.volley])).categories.first)
        #expect(category.score == 0)
        #expect(category.bad == ["わるい"])
        #expect(category.fix == ["なおす"])
        #expect(category.good.isEmpty)
    }

    @Test func ignoresOtherScenesForCategory() throws {
        // ディンクの分類に、ボレーの場面の値は入れない。項目そのものの点は出る。
        let scorer = PlayScorer(rubric: try rubric(.dink, metric: .reaction))
        let player = scorer.playerScore(id: 0, measurements: reactions([0.2, 0.2, 0.2], tags: [.volley]))
        #expect(player.categories.first?.score == nil)
        #expect(player.metrics.first { $0.metric == .reaction }?.score == 100)
    }

    @Test func emptyInputGivesNoScores() throws {
        let score = PlayScorer(rubric: try Rubric.standard()).score(frames: [], balls: [])
        #expect(score.rallies.isEmpty)
        #expect(score.players.map(\.id) == [0, 1])
        #expect(score.players.allSatisfy { $0.categories.allSatisfy { $0.score == nil } })
        #expect(score.players.allSatisfy { $0.metrics.allSatisfy { $0.count == 0 } })
    }

    @Test func scoresWithoutCourtPositions() throws {
        // コートが分からない。相手（番号 2）が 3 回打つと、構えは測れるが、位置の項目は測れない。
        let input = frames(from: 0, through: 12) { _ in
            [player(0, foot: CGPoint(x: 0.3, y: 0.1), court: nil), player(1, foot: CGPoint(x: 0.7, y: 0.1), court: nil),
             player(2, foot: CGPoint(x: 0.5, y: 0.6), court: nil)]
        }
        let balls = rallyBalls(turningAt: [(2, CGPoint(x: 0.56, y: 0.795)), (5, CGPoint(x: 0.36, y: 0.295)),
                                            (8, CGPoint(x: 0.56, y: 0.795)), (10, CGPoint(x: 0.36, y: 0.295))])
        let score = PlayScorer(rubric: try Rubric.standard()).score(frames: input, balls: balls)
        let near = try #require(score.players.first)
        #expect(near.metrics.first { $0.metric == .kitchenArrival }?.count == 0)
        #expect(near.metrics.first { $0.metric == .pairSpacing }?.count == 0)
        #expect((near.metrics.first { $0.metric == .stanceWidth }?.count ?? 0) >= 1)
    }

    @Test func restartsShotIndexPerRally() throws {
        let input = frames(from: 0, through: 30) { _ in
            [player(0, foot: CGPoint(x: 0.3, y: 0.1), court: nil), player(2, foot: CGPoint(x: 0.5, y: 0.6), court: nil)]
        }
        // 1 本目は 1〜6 秒、2 本目は 20〜25 秒。12 秒の向きの変わり目は、どちらのラリーにも入らない。
        var balls = rallyBalls(turningAt: [(2, CGPoint(x: 0.56, y: 0.795)), (4, CGPoint(x: 0.36, y: 0.295))], from: 1, to: 6)
        balls += rallyBalls(turningAt: [(12, CGPoint(x: 0.56, y: 0.795))], from: 11.5, to: 12.5)
        balls += rallyBalls(turningAt: [(21, CGPoint(x: 0.56, y: 0.795)), (23, CGPoint(x: 0.36, y: 0.295))], from: 20, to: 25)
        let score = PlayScorer(rubric: try Rubric.standard()).score(frames: input, balls: balls)
        #expect(score.rallies.count == 2)
        #expect(score.shots.map(\.index) == [0, 1, 0, 1])
        #expect(score.shots.map(\.rally) == [0, 0, 1, 1])
    }

    @Test func writesMarkdown() throws {
        let score = PlayScorer(rubric: try Rubric.standard()).score(frames: [], balls: [])
        let text = PlayScoreReport.markdown(score, title: "テスト")
        #expect(text.contains("# テスト の採点"))
        #expect(text.contains("## 選手 0"))
        #expect(text.contains("判定できず"))
    }

    /// from〜to 秒、1 秒に 30 回の球。turns の時刻に、その位置で向きを変える（それ以外は 2 点の間をまっすぐ行き来する）。
    private func rallyBalls(turningAt turns: [(Double, CGPoint)], from start: Double = 1, to end: Double = 11) -> [BallPoint] {
        let waypoints = [(start, CGPoint(x: 0.5, y: 0.5))] + turns + [(end, CGPoint(x: 0.5, y: 0.5))]
        var result = [BallPoint]()
        for (first, second) in zip(waypoints, waypoints.dropFirst()) {
            let steps = max(1, Int(((second.0 - first.0) * 30).rounded()))
            for step in 0..<steps {
                let ratio = Double(step) / Double(steps)
                let point = CGPoint(
                    x: Double(first.1.x) + (Double(second.1.x) - Double(first.1.x)) * ratio,
                    y: Double(first.1.y) + (Double(second.1.y) - Double(first.1.y)) * ratio
                )
                result.append(BallPoint(time: first.0 + Double(step) / 30, center: point))
            }
        }
        return result
    }
}
```

`(0.56, 0.795)` は番号 2（足元 (0.5, 0.6)）の右手首、`(0.36, 0.295)` は番号 0（足元 (0.3, 0.1)）の右手首。`(0.5, 0.5)` から手首へ行って戻るので、向きは 180 度近く変わる。

- [ ] **Step 2: テストが落ちるのを確かめる**

Run: `xcrun swift test --filter PlayScorerTests 2>&1 | tail -20`
Expected: ビルドの失敗（`cannot find 'PlayScorer' in scope`）

- [ ] **Step 3: 採点を書く**

`Sources/PlayScoring/PlayScorer.swift`:

```swift
import Foundation

/// 観点 1 つの点（その観点の項目の点の平均）。
public struct GroupScore: Equatable, Sendable {
    public var group: MetricGroup
    public var score: Int?
}

/// 分類 1 つの点と、評価の言葉。
public struct CategoryScore: Equatable, Sendable {
    public var id: CategoryID
    public var title: String
    /// 点の出せる項目が 1 つも無ければ nil（判定できず）。
    public var score: Int?
    public var good: [String]
    public var bad: [String]
    public var fix: [String]
}

/// 選手 1 人の採点。
public struct PlayerScore: Equatable, Sendable {
    public var id: Int
    public var metrics: [MetricResult]
    public var groups: [GroupScore]
    public var categories: [CategoryScore]
}

/// 動画 1 本の採点。
public struct PlayScore: Equatable, Sendable {
    public var rallies: [Rally]
    public var shots: [Shot]
    /// 手前の 2 人（番号 0 と 1 の順）。
    public var players: [PlayerScore]
}

/// 選手と球の検出から、手前の 2 人を採点する。
public struct PlayScorer: Sendable {
    public var rubric: Rubric

    public init(rubric: Rubric) {
        self.rubric = rubric
    }

    public func score(frames: [PlayFrame], balls: [BallPoint]) -> PlayScore {
        let aspect = frames.first?.aspect ?? 16.0 / 9.0
        let tracks = PlayerTrack.tracks(from: frames)
        let rallies = Rally.find(in: balls)
        let hits = HitDetector().hits(balls: balls, tracks: tracks, aspect: aspect)
        let shots = rallies.enumerated().map { index, rally in
            ShotClassifier().classify(hits.filter { $0.time >= rally.start && $0.time <= rally.end }, rally: index, tracks: tracks)
        }
        let measurements = MetricMeasurer(tracks: tracks, rallies: rallies, shots: shots, aspect: aspect).measurements()
        let players = [0, 1].map { id in playerScore(id: id, measurements: measurements.filter { $0.playerID == id }) }
        return PlayScore(rallies: rallies, shots: shots.flatMap { $0 }, players: players)
    }

    func playerScore(id: Int, measurements: [Measurement]) -> PlayerScore {
        let metrics = MetricID.allCases.map { metric in
            MetricResult(metric: metric, values: measurements.filter { $0.metric == metric }.map(\.value))
        }
        let groups = MetricGroup.allCases.map { group in
            GroupScore(group: group, score: Self.mean(metrics.filter { $0.metric.group == group }.compactMap(\.score)))
        }
        let categories = rubric.categories.map { category(of: $0, measurements: measurements) }
        return PlayerScore(id: id, metrics: metrics, groups: groups, categories: categories)
    }

    /// 分類の点は、結びつく項目の、その分類の場面での点の平均。
    private func category(of category: Rubric.Category, measurements: [Measurement]) -> CategoryScore {
        var scores = [MetricID: Int]()
        for metric in category.metrics {
            let values = measurements.filter { $0.metric == metric && category.id.includes($0.context) }.map(\.value)
            if let score = MetricResult(metric: metric, values: values).score {
                scores[metric] = score
            }
        }
        guard let mean = Self.mean(Array(scores.values)) else {
            return CategoryScore(id: category.id, title: category.title, score: nil, good: [], bad: [], fix: [])
        }
        return CategoryScore(
            id: category.id, title: category.title, score: mean,
            good: pick(category.good, scores: scores, good: true),
            bad: pick(category.bad, scores: scores, good: false),
            fix: pick(category.fix, scores: scores, good: false)
        )
    }

    /// 言葉を選ぶ。良い点は 70 点以上を高い順、悪い点・改善点は 40 点以下を低い順に、3 つまで。
    /// 言葉の点は、結びつく項目の点のうち、良い点なら一番高いもの、ほかは一番低いもの。同じ点なら、文面の順。
    private func pick(_ phrases: [Rubric.Phrase], scores: [MetricID: Int], good: Bool) -> [String] {
        let rated = phrases.enumerated().compactMap { index, phrase -> (text: String, score: Int, index: Int)? in
            let values = phrase.metrics.compactMap { scores[$0] }
            guard let value = good ? values.max() : values.min() else { return nil }
            return (phrase.text, value, index)
        }
        let chosen = rated.filter { good ? $0.score >= 70 : $0.score <= 40 }.sorted { first, second in
            first.score != second.score ? (good ? first.score > second.score : first.score < second.score) : first.index < second.index
        }
        return chosen.prefix(3).map(\.text)
    }

    private static func mean(_ scores: [Int]) -> Int? {
        guard !scores.isEmpty else { return nil }
        return Int((Double(scores.reduce(0, +)) / Double(scores.count)).rounded())
    }
}
```

- [ ] **Step 4: Markdown の書き出しを書く**

`Sources/PlayScoring/PlayScoreReport.swift`:

```swift
import Foundation

/// 採点の結果を、Markdown の表にする（Mac のテストで動画ごとに書き出す）。
public enum PlayScoreReport {
    public static func markdown(_ score: PlayScore, title: String) -> String {
        var text = "# \(title) の採点\n\n"
        let nearShots = score.shots.filter { $0.hit.side == .near }.count
        text += "ラリー \(score.rallies.count) 本、打球 \(score.shots.count) 回（手前 \(nearShots) 回）。"
        let kinds = ShotKind.allCases.map { kind in "\(kind.title) \(score.shots.filter { $0.kind == kind }.count)" }
        text += "種類: " + kinds.joined(separator: "、") + "、分けられず \(score.shots.filter { $0.kind == nil }.count)。\n\n"
        for player in score.players {
            text += section(for: player)
        }
        return text
    }

    private static func section(for player: PlayerScore) -> String {
        var text = "## 選手 \(player.id)\n\n| 観点 | 点 |\n| --- | --- |\n"
        for group in player.groups {
            text += "| \(group.group.title) | \(scoreText(group.score)) |\n"
        }
        text += "\n| 項目 | 中央値 | 点 | 回数 |\n| --- | --- | --- | --- |\n"
        for metric in player.metrics {
            let median = metric.median.map { metric.metric.format($0) } ?? "-"
            text += "| \(metric.metric.title) | \(median) | \(scoreText(metric.score)) | \(metric.count) |\n"
        }
        text += "\n| 分類 | 点 | 良い点 | 悪い点 | 改善点 |\n| --- | --- | --- | --- | --- |\n"
        for category in player.categories {
            let columns = [category.good, category.bad, category.fix].map { $0.isEmpty ? "-" : $0.joined(separator: "<br>") }
            text += "| \(category.title) | \(scoreText(category.score)) | " + columns.joined(separator: " | ") + " |\n"
        }
        return text + "\n"
    }

    private static func scoreText(_ score: Int?) -> String {
        score.map { "\($0)" } ?? "判定できず"
    }
}
```

- [ ] **Step 5: テストが通るのを確かめる**

Run: `xcrun swift test --filter PlayScoringTests 2>&1 | tail -30`
Expected: `PlayScoringTests` の全部（Task 1〜8 の 38 個）が通る

Run: `swiftlint lint --quiet Sources/PlayScoring Tests/PlayScoringTests`
Expected: 何も出ない

---

### Task 9: 2026-11-19 の動画での採点表

**Files:**
- Create: `Tests/PlayScoringTests/RecordedTimeline.swift`
- Create: `Tests/PlayScoringTests/DemoVideoScoreReportTests.swift`
- Create: `Docs/accuracy/scoring.md`

**Interfaces:**
- Consumes: `PlayScorer`、`PlayScoreReport`（Task 8）。選手の書き出し（`Tests/PlayerPoseTests/PlayerFrameExport.swift` の形の JSON、`<動画>.json`）と、球の書き出し（`Tests/BallTrackingTests/BallFrameExport.swift` の形の JSON、`<動画>.json`）
- Produces: `struct RecordedTimeline { static func frames(from: URL) throws -> [PlayFrame]; static func balls(from: URL) throws -> [BallPoint] }`、テスト `reportsScoresOnDemoVideos`

- [ ] **Step 1: 記録の読み方を書く**

`Tests/PlayScoringTests/RecordedTimeline.swift`:

```swift
import CoreGraphics
import Foundation
import PlayScoring
import PlayerPose

/// Mac のテストが書き出した、選手と球の検出の記録（JSON）を、採点の材料にする。
enum RecordedTimeline {
    private struct PlayerFile: Decodable {
        struct Player: Decodable {
            var id: Int
            var firstSeen: Double
            var isDetected: Bool
            var side: String?
            var court: [Double]?
            var joints: [String: [Double]]
        }

        var seconds: Double
        var imageWidth: Int
        var imageHeight: Int
        var players: [Player]
    }

    private struct BallFile: Decodable {
        var seconds: Double
        var ball: [Double]?
    }

    static func frames(from url: URL) throws -> [PlayFrame] {
        let records = try JSONDecoder().decode([PlayerFile].self, from: Data(contentsOf: url))
        return records.map { record in
            let aspect = record.imageHeight > 0 ? Double(record.imageWidth) / Double(record.imageHeight) : 16.0 / 9.0
            return PlayFrame(time: record.seconds, players: record.players.map(player), aspect: aspect)
        }
    }

    static func balls(from url: URL) throws -> [BallPoint] {
        try JSONDecoder().decode([BallFile].self, from: Data(contentsOf: url)).map { record in
            let center = record.ball.flatMap { $0.count == 2 ? CGPoint(x: $0[0], y: $0[1]) : nil }
            return BallPoint(time: record.seconds, center: center)
        }
    }

    private static func player(_ record: PlayerFile.Player) -> CourtPlayer {
        var joints = [PoseJoint: PoseKeypoint]()
        for (name, values) in record.joints {
            guard let joint = PoseJoint(rawValue: name), values.count >= 3 else { continue }
            joints[joint] = PoseKeypoint(position: CGPoint(x: values[0], y: values[1]), confidence: Float(values[2]))
        }
        return CourtPlayer(
            id: record.id, pose: BodyPose(joints: joints), side: record.side.flatMap(CourtSide.init(rawValue:)),
            courtPosition: record.court.flatMap { $0.count == 2 ? CGPoint(x: $0[0], y: $0[1]) : nil },
            firstSeen: record.firstSeen, isDetected: record.isDetected
        )
    }
}
```

- [ ] **Step 2: 書き出しのテストを書く**

`Tests/PlayScoringTests/DemoVideoScoreReportTests.swift`:

```swift
// 自分たちで撮った動画の、選手と球の検出の記録から、手前の 2 人を採点し、表を書き出す。
// SCORE_POSE_DIR（選手の記録 <動画>.json のフォルダ）、SCORE_BALL_DIR（球の記録 <動画>.json のフォルダ）、
// SCORE_REPORT_DIR（書き出す先）を指定したときだけ動く。SCORE_VIDEOS（例: 20261119-4986,20261119-5013）で動画を絞る。
// 出力: <動画>-score.md（動画ごと）、summary.md（全部の動画の、観点と分類の点の一覧）。
import Foundation
import PlayScoring
import Testing

@Test(.enabled(if: ["SCORE_POSE_DIR", "SCORE_BALL_DIR", "SCORE_REPORT_DIR"].allSatisfy {
    ProcessInfo.processInfo.environment[$0] != nil
}))
func reportsScoresOnDemoVideos() throws {
    let environment = ProcessInfo.processInfo.environment
    let poseDirectory = URL(fileURLWithPath: environment["SCORE_POSE_DIR"] ?? "")
    let ballDirectory = URL(fileURLWithPath: environment["SCORE_BALL_DIR"] ?? "")
    let reportDirectory = URL(fileURLWithPath: environment["SCORE_REPORT_DIR"] ?? "")
    try FileManager.default.createDirectory(at: reportDirectory, withIntermediateDirectories: true)
    let only = environment["SCORE_VIDEOS"]?.split(separator: ",").map(String.init)
    let names = try FileManager.default.contentsOfDirectory(atPath: poseDirectory.path)
        .filter { $0.hasSuffix(".json") }
        .map { String($0.dropLast(5)) }
        .filter { name in FileManager.default.fileExists(atPath: ballDirectory.appendingPathComponent("\(name).json").path) }
        .filter { name in only?.contains { name.contains($0) } ?? true }
        .sorted()
    let scorer = PlayScorer(rubric: try Rubric.standard())
    var summary = "# 採点の一覧\n\n| 動画 | ラリー | 打球（手前） | 選手 | " + MetricGroup.allCases.map(\.title).joined(separator: " | ")
    summary += " | " + CategoryID.allCases.map(\.rawValue).joined(separator: " | ") + " |\n"
    summary += "|" + String(repeating: " --- |", count: 4 + MetricGroup.allCases.count + CategoryID.allCases.count) + "\n"
    for name in names {
        let frames = try RecordedTimeline.frames(from: poseDirectory.appendingPathComponent("\(name).json"))
        let balls = try RecordedTimeline.balls(from: ballDirectory.appendingPathComponent("\(name).json"))
        let score = scorer.score(frames: frames, balls: balls)
        try PlayScoreReport.markdown(score, title: name)
            .write(to: reportDirectory.appendingPathComponent("\(name)-score.md"), atomically: true, encoding: .utf8)
        summary += summaryRows(name: name, score: score)
    }
    try summary.write(to: reportDirectory.appendingPathComponent("summary.md"), atomically: true, encoding: .utf8)
}

private func summaryRows(name: String, score: PlayScore) -> String {
    let near = score.shots.filter { $0.hit.side == .near }.count
    return score.players.map { player in
        let groups = player.groups.map { $0.score.map(String.init) ?? "-" }
        let categories = player.categories.map { $0.score.map(String.init) ?? "-" }
        return "| \(name) | \(score.rallies.count) | \(score.shots.count)（\(near)） | \(player.id) | "
            + (groups + categories).joined(separator: " | ") + " |\n"
    }.joined()
}
```

`CategoryID.allCases` の順は、`rubric.json` の分類の順と同じ（Task 7 のテストで確かめている）。

- [ ] **Step 3: 単体のテストが、環境の変数なしでは飛ばされるのを確かめる**

Run: `xcrun swift test --filter PlayScoringTests 2>&1 | tail -5`
Expected: 全部通る（`reportsScoresOnDemoVideos` は skipped）

- [ ] **Step 4: 元の長さの 29 本に、選手の検出をかける**

球の記録は、作業のフォルダ `W=/private/tmp/claude-503/-Users-akihiro-matsuyama-ghq-github-com-akidon0000-racket-vision/d48cc06c-664b-4dda-9c26-007b2abe6054/scratchpad/newvids` の `ball/` に 29 本ぶんある（2026-11-20 に作った）。コートの記録は `courtcache/` にある。どちらも無ければ、`DemoApp/Clips/README.md` の手順 2 の 1 つ目のコマンドで作る（`BALL_COURT_CACHE=$W/courtcache`）。

選手の検出（時間がかかるので、後ろで動かす）:

```bash
W=/private/tmp/claude-503/-Users-akihiro-matsuyama-ghq-github-com-akidon0000-racket-vision/d48cc06c-664b-4dda-9c26-007b2abe6054/scratchpad/newvids
COURT_DEMO_DIR=$PWD/DemoApp/SamplePlayVideos/FullLength POSE_REPORT_DIR=$W/pose-full POSE_VIDEOS=20261119 POSE_COURT_CACHE=$W/courtcache \
  xcrun swift test -c release -Xswiftc -enable-testing --filter reportsPlayersOnDemoVideos
```

Expected: `$W/pose-full/20261119-4984.json` 〜 `20261119-5020.json` の 29 本と `report.md` ができる

- [ ] **Step 5: 採点表を書き出す**

```bash
W=/private/tmp/claude-503/-Users-akihiro-matsuyama-ghq-github-com-akidon0000-racket-vision/d48cc06c-664b-4dda-9c26-007b2abe6054/scratchpad/newvids
SCORE_POSE_DIR=$W/pose-full SCORE_BALL_DIR=$W/ball SCORE_REPORT_DIR=$W/score \
  xcrun swift test -c release -Xswiftc -enable-testing --filter reportsScoresOnDemoVideos
```

Expected: `$W/score/summary.md` と、29 本ぶんの `<動画>-score.md`

- [ ] **Step 6: 結果を確かめ、記録を書く**

`summary.md` を読み、次を確かめる:

1. コートの見つかる動画で、手前の打球が 1 本あたり数回以上出ているか（0 回が続くなら、`HitDetector` の `reach` か `minimumTurn` が厳しすぎる）。
2. コートの見つからない 4 本（4984、4985、4993、5005）で、落ちずに位置の項目が「判定できず」になっているか。
3. 点が全員 0 か 100 に張り付いている項目が無いか（張り付くなら、基準の値か測り方の単位が違う）。

`Docs/accuracy/scoring.md` を新しく作る。冒頭に「読み手: 採点の基準を直す人／目的: 2026-11-19 の動画での採点の結果と、分かった限界を残す」を書き、`summary.md` の表と、上の 3 点で分かったこと、測った日（2026-11-20 以降の実際の日付）を書く。数値は `summary.md` から写し、確かめていないことは「未確認」と書く。

---

### Task 10: デモのアプリの採点のシート

**Files:**
- Modify: `DemoApp/Library/Package.swift`
- Modify: `DemoApp/Library/Sources/VideoPlayback/PlayerView.swift`
- Create: `DemoApp/Library/Sources/VideoPlayback/PlayScoreSheet.swift`

**Interfaces:**
- Consumes: `PlayScorer`、`PlayScore`、`PlayFrame`、`BallPoint`、`Rubric`、`MetricResult`、`CategoryScore`（Task 1〜8）
- Produces: 画面だけ（ほかのタスクは使わない）

- [ ] **Step 1: パッケージの依存を足す**

`DemoApp/Library/Package.swift` の `VideoPlayback` の `dependencies` に足す:

```swift
                .product(name: "PlayerPose", package: "racket-vision"),
                .product(name: "PlayScoring", package: "racket-vision")
```

（`PlayerPose` の行の末尾にカンマを足し、その次の行に `PlayScoring` を入れる。）

- [ ] **Step 2: 材料をためて採点するようにする**

`PlayerView.swift` の先頭の `import PlayerPoseOverlay` の後に `import PlayScoring` を足す。

`PlayerModel` の `@Published private(set) var usesRecordedPlayers = false` の後に足す:

```swift
    /// 手前の 2 人の採点。採点したら入る。
    @Published private(set) var playScore: PlayScore?
    @Published private(set) var isScoring = false
```

`private var lastPlayerSample: CFTimeInterval = 0` の後に足す:

```swift
    /// 採点の材料（再生を始めてからの全部）。
    private var playFrames = [PlayFrame]()
    private var ballPoints = [BallPoint]()
    private var lastPlayFrameTime: Double = -1
    private let scorer = (try? Rubric.standard()).map(PlayScorer.init(rubric:))
    private var endObserver: NSObjectProtocol?
```

`load()` の `player.play()` の前に足す（再生を流し終えたら採点する）:

```swift
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.scorePlay() }
        }
```

`stop()` の最後に足す:

```swift
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
```

`sample()` の、記録の選手を出す行を書き換える:

```swift
        if usesRecordedPlayers, let recordedPlayers {
            players = recordedPlayers.players(at: time.seconds)
            recordPlayFrame(at: time.seconds, players: players)
        } else {
```

`show(_ outcome: CourtPlayersOutcome)` の `players = outcome.players` の後に足す:

```swift
        if outcome.failure == nil {
            recordPlayFrame(at: outcome.time, players: outcome.players)
        }
```

`show(_ outcome: BallFrameOutcome)` の `rally.append(outcome)` の後に足す:

```swift
        ballPoints.append(BallPoint(time: outcome.time, center: outcome.ball?.center))
```

`PlayerModel` の型の本体が 200 行（SwiftLint の `type_body_length`）を超えないよう、次の関数は同じファイルの拡張に書く。`PlayerModel` の閉じ括弧の後、`DisplayLinkTarget` の前に足す（同じファイルの拡張からは `private` の値も使える）:

```swift
extension PlayerModel {
    /// 選手の材料を、0.1 秒ごとに 1 回ためる（記録の選手は画面の更新のたびに出るので、間引く）。
    private func recordPlayFrame(at time: Double, players: [CourtPlayer]) {
        guard time - lastPlayFrameTime >= 0.09 else { return }
        lastPlayFrameTime = time
        let aspect = videoSize.height > 0 ? Double(videoSize.width / videoSize.height) : 16.0 / 9.0
        playFrames.append(PlayFrame(time: time, players: players, aspect: aspect))
    }

    /// ここまでの材料で、手前の 2 人を採点する。計算は画面の外で動かす。
    func scorePlay() {
        guard let scorer, !isScoring else { return }
        isScoring = true
        let frames = playFrames
        let balls = ballPoints
        Task.detached(priority: .userInitiated) {
            let score = scorer.score(frames: frames, balls: balls)
            await MainActor.run { [weak self] in
                self?.playScore = score
                self?.isScoring = false
            }
        }
    }

    func dismissScore() {
        playScore = nil
    }
}
```

拡張の `private func recordPlayFrame` は、同じファイルの `PlayerModel` の本体（`sample()` と `show(_:)`）から呼べる。

- [ ] **Step 3: ボタンとシートを足す**

`PlayerView.body` の `CourtSceneView(...)` の `.overlay(alignment: .bottom) { ... }` の後に足す:

```swift
            .overlay(alignment: .bottomTrailing) {
                Button(model.isScoring ? "採点中…" : "採点") { model.scorePlay() }
                    .font(.caption)
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isScoring)
                    .padding(8)
            }
```

`.toolbar(.hidden, for: .navigationBar)` の前に足す:

```swift
        .sheet(isPresented: Binding(get: { model.playScore != nil }, set: { if !$0 { model.dismissScore() } })) {
            if let score = model.playScore {
                PlayScoreSheet(score: score)
                    .presentationDetents([.medium, .large])
            }
        }
```

`DemoApp/Library/Sources/VideoPlayback/PlayScoreSheet.swift`:

```swift
import PlayScoring
import SwiftUI

/// 手前の 2 人の採点。選手を切り替えて、観点の点、分類の点と評価の言葉、項目の値を出す。
struct PlayScoreSheet: View {
    let score: PlayScore
    @State private var selected = 0

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("選手", selection: $selected) {
                        ForEach(score.players, id: \.id) { Text("選手 \($0.id)").tag($0.id) }
                    }
                    .pickerStyle(.segmented)
                    Text("ラリー \(score.rallies.count) 本、打球 \(score.shots.count) 回")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let player = score.players.first(where: { $0.id == selected }) {
                    Section("観点") {
                        ForEach(player.groups, id: \.group) { LabeledContent($0.group.title, value: Self.text($0.score)) }
                    }
                    Section("分類") {
                        ForEach(player.categories, id: \.id) { CategoryRow(category: $0) }
                    }
                    Section("項目") {
                        ForEach(player.metrics, id: \.metric) { LabeledContent($0.metric.title, value: Self.detail($0)) }
                    }
                }
            }
            .navigationTitle("手前の 2 人の採点")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    static func text(_ score: Int?) -> String {
        score.map { "\($0) 点" } ?? "判定できず"
    }

    /// 項目の、中央値・点・測った回数。
    static func detail(_ result: MetricResult) -> String {
        guard let median = result.median else { return "測れず" }
        return "\(result.metric.format(median))・\(text(result.score))・\(result.count) 回"
    }
}

/// 分類 1 つの点と、評価の言葉。
private struct CategoryRow: View {
    let category: CategoryScore

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(category.title, value: PlayScoreSheet.text(category.score))
                .font(.headline)
            phrases("良い点", category.good, color: .green)
            phrases("悪い点", category.bad, color: .red)
            phrases("改善点", category.fix, color: .blue)
        }
    }

    @ViewBuilder
    private func phrases(_ title: String, _ items: [String], color: Color) -> some View {
        if !items.isEmpty {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(color)
            ForEach(items, id: \.self) { Text("・\($0)").font(.caption) }
        }
    }
}
```

- [ ] **Step 4: シミュレーターでビルドする**

```bash
cd DemoApp/App && xcodegen generate >/dev/null && xcodebuild -project CourtDemo.xcodeproj -scheme CourtDemo \
  -destination 'platform=iOS Simulator,id=5F5A3DE9-B4E0-4C1F-A518-0571C12F09E8' \
  -derivedDataPath /private/tmp/claude-503/-Users-akihiro-matsuyama-ghq-github-com-akidon0000-racket-vision/d48cc06c-664b-4dda-9c26-007b2abe6054/scratchpad/dd \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: シミュレーターで動かして確かめる**

シミュレーターでは骨格の検出が動かないので、記録の選手（`<動画>.players.json`）がある動画で確かめる。Task 9 の `$W/pose-full/20261119-5013.json` を `DemoApp/SamplePlayVideos/FullLength/20261119-5013.players.json` に `/bin/cp -f` で写し、もう一度ビルドしてから、mcp__Claude_Code_iOS_Simulator__control で起動する。「2026-11-19 撮影」の 5013 を開き、10 秒ほど流してから「採点」を押す。

Expected: シートが下半分に出て、選手 0 と 1 を切り替えられる。観点・分類・項目が並ぶ（点が「判定できず」でもよい。落ちないこと）。スクリーンショットを撮って確かめる。写した `.players.json` は、確かめた後で `/bin/rm -f` で消す（git の対象外だが、アプリに入るため）。

- [ ] **Step 6: lint**

Run: `swiftlint lint --quiet DemoApp/Library/Sources/VideoPlayback`
Expected: 何も出ない（`PlayerView.swift` は 400 行以内に収まる見込み。超えたら、上の拡張を `PlayerModel+Scoring.swift` に移し、拡張から使う値の `private` を外す）

---

### Task 11: 打球の見分けの当たり具合を測る

**Files:**
- Create: `Tests/PlayScoringTests/HitLabelEvaluationTests.swift`
- Create: `Docs/accuracy/hits/README.md`
- Modify: `Docs/accuracy/scoring.md`

**Interfaces:**
- Consumes: `RecordedTimeline`（Task 9）、`PlayScorer`（Task 8）
- Produces: テスト `evaluatesHitsAgainstLabels`。正解の形 `Docs/accuracy/hits/<動画>.csv`（列 `seconds,player`）

spec の「確かめ方」1 のための作業。正解（打った時刻と打った人）は、ユーザーが動画を見て付ける。このタスクでは、正解の形と、比べるテストまでを作る。

- [ ] **Step 1: 正解の付け方を書く**

`Docs/accuracy/hits/README.md`:

```markdown
# 打球の正解（打った時刻と打った人）

- 読み手: 打球の正解を付ける人
- 目的: `HitDetector` の見逃しと誤りを数えるための、正解の書き方を決める

動画ごとに `<動画の名前>.csv` を置く（例: `20261119-4986.csv`）。1 行が 1 回の打球。

| 列 | 中身 |
| --- | --- |
| `seconds` | 球がパドルに当たった時刻（秒、小数 2 桁まで）。QuickTime で 1 コマずつ送って読む |
| `player` | 打った人。手前の 2 人は、アプリの骨格の色の番号（0 か 1）、奥の人は `far` |

1 行目は `seconds,player` の見出し。最初は 3 本（コートが見つかる動画から、ラリーの長いもの）に付ける。
```

- [ ] **Step 2: 比べるテストを書く**

`Tests/PlayScoringTests/HitLabelEvaluationTests.swift`:

```swift
// 打球の正解（Docs/accuracy/hits/<動画>.csv）と、採点が見つけた打球を比べる。
// SCORE_POSE_DIR、SCORE_BALL_DIR、HIT_LABEL_DIR を指定したときだけ動く。結果は標準出力に出す。
// 手前の 2 人の正解の打球のうち、0.1 秒以内に同じ人の打球を見つけた割合（取れた割合）と、
// 見つけた手前の打球のうち、正解に当たらないものの割合（誤りの割合）を出す。
import Foundation
import PlayScoring
import Testing

@Test(.enabled(if: ["SCORE_POSE_DIR", "SCORE_BALL_DIR", "HIT_LABEL_DIR"].allSatisfy {
    ProcessInfo.processInfo.environment[$0] != nil
}))
func evaluatesHitsAgainstLabels() throws {
    let environment = ProcessInfo.processInfo.environment
    let labelDirectory = URL(fileURLWithPath: environment["HIT_LABEL_DIR"] ?? "")
    let scorer = PlayScorer(rubric: try Rubric.standard())
    for file in try FileManager.default.contentsOfDirectory(atPath: labelDirectory.path).filter({ $0.hasSuffix(".csv") }).sorted() {
        let name = String(file.dropLast(4))
        let labels = try String(contentsOf: labelDirectory.appendingPathComponent(file), encoding: .utf8)
            .split(separator: "\n").dropFirst().compactMap { line -> (Double, String)? in
                let columns = line.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                guard columns.count >= 2, let seconds = Double(columns[0]) else { return nil }
                return (seconds, columns[1])
            }
        let frames = try RecordedTimeline.frames(from: URL(fileURLWithPath: environment["SCORE_POSE_DIR"] ?? "").appendingPathComponent("\(name).json"))
        let balls = try RecordedTimeline.balls(from: URL(fileURLWithPath: environment["SCORE_BALL_DIR"] ?? "").appendingPathComponent("\(name).json"))
        let found = scorer.score(frames: frames, balls: balls).shots.map(\.hit).filter { $0.side == .near }
        let nearLabels = labels.filter { $0.1 != "far" }
        let caught = nearLabels.filter { label in found.contains { abs($0.time - label.0) <= 0.1 && String($0.playerID) == label.1 } }
        let wrong = found.filter { hit in !nearLabels.contains { abs(hit.time - $0.0) <= 0.1 && String(hit.playerID) == $0.1 } }
        print(String(
            format: "[HitLabels] %@ 正解 %ld 回、取れた %ld 回（%.0f%%）、見つけた %ld 回のうち誤り %ld 回",
            name, nearLabels.count, caught.count, Double(caught.count) / Double(max(1, nearLabels.count)) * 100, found.count, wrong.count
        ))
    }
}
```

- [ ] **Step 3: 環境の変数なしでは飛ばされるのを確かめる**

Run: `xcrun swift test --filter PlayScoringTests 2>&1 | tail -5`
Expected: 全部通る（`evaluatesHitsAgainstLabels` は skipped）

Run: `swiftlint lint --quiet Tests/PlayScoringTests`
Expected: 何も出ない

- [ ] **Step 4: ユーザーに正解を頼む**

`Docs/accuracy/scoring.md` の最後に「打球の見分けの当たり具合: 正解待ち（`Docs/accuracy/hits/README.md` の形で 3 本）」と書く。正解の 3 本を選ぶときは、Task 9 の `summary.md` で手前の打球の多い動画を 3 本挙げて、ユーザーに渡す。正解が届いたら、次で測り、`scoring.md` に結果を書く（目標は、手前の 2 人の打球の 8 割を 0.1 秒以内・正しい人で取ること）:

```bash
W=/private/tmp/claude-503/-Users-akihiro-matsuyama-ghq-github-com-akidon0000-racket-vision/d48cc06c-664b-4dda-9c26-007b2abe6054/scratchpad/newvids
SCORE_POSE_DIR=$W/pose-full SCORE_BALL_DIR=$W/ball HIT_LABEL_DIR=$PWD/Docs/accuracy/hits \
  xcrun swift test -c release -Xswiftc -enable-testing --filter evaluatesHitsAgainstLabels 2>&1 | grep HitLabels
```

---

## 最後に

spec の「確かめ方」2（点数がユーザーの目と合うか）は、この計画の外。Task 9 の採点表ができたら、ユーザーに 5 本を選んでもらい、手前の 2 人を分類ごとに 3 段階（よい・ふつう・よくない）で付けてもらう。合わない項目は、`MetricID.threshold` の値か測り方を直す（直したら `Docs/accuracy/scoring.md` に、前後の値を残す）。

全部のタスクの後で、次を通す:

Run: `xcrun swift test 2>&1 | tail -5`
Expected: ルートのパッケージのテストが全部通る（動画を使うテストは skipped）

Run: `swiftlint lint --quiet Sources Tests DemoApp/Library/Sources`
Expected: 何も出ない
