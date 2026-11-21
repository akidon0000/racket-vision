# racket-vision

ラケットを使う球技（ピックルボール、テニス、バドミントンなど）の映像を解析する Swift パッケージ。ピックルボールのコートの検出、球の追跡、選手の骨格の検出と特定がある。

| モジュール | 中身 |
| --- | --- |
| `CourtFit` | 映像のフレームから、コートの位置（図面から画面への射影変換と、外周の四隅）を求める。コートの図面を映像に当てはめる。方式は複数あり、同じ入出力で差し替えられる。図面は今はピックルボールだけ |
| `CourtOverlay` | 検出の結果を、映像の上に方式ごとの色の線で描く（iOS） |
| `BallTracking` | 球を追い、ラリー（打ってから打ち返されるまで）ごとの軌跡にする。精度は [Docs/accuracy/ball.md](Docs/accuracy/ball.md) |
| `PlayerPose` | 選手の骨格を検出し、コートにいる選手（ダブルスなら 4 人）を選んで、同じ人に同じ番号を付け続ける。精度は [Docs/accuracy/pose.md](Docs/accuracy/pose.md) |
| `CourtScene` | 解析の結果を、コートの 3D の座標（メートル）に置く。コートの四隅からカメラの位置と向きを求め、選手の骨格と球の軌跡を置く |
| `SceneAdvisor` | 試作。外部のモデル（TypeSafe AI の Jev）に映像の 1 枚を見せて、球の色と拾う線の色を選ぶ（[記録](Docs/accuracy/scene-advice.md)） |

## 使う

```swift
.package(url: "https://github.com/akidon0000/racket-vision.git", revision: "<コミット>")
```

```swift
import CourtFit

let analyzer = CourtAnalyzer(detectors: [TrackingLineModelCourtRectangleDetector()])
let outcomes = analyzer.analyze(pixelBuffer, orientation: .up) // 32BGRA の CVPixelBuffer
```

一番よく当たるのは `TrackingLineModelCourtRectangleDetector`（線の対応+追従）。仕組みと、方式ごとの精度は [Docs/accuracy/court.md](Docs/accuracy/court.md) にある。

検出は画素を 1 つずつ回す計算が多いので、`CourtFit` は Debug でも最適化してビルドする設定にしてある（`unsafeFlags`）。SwiftPM は、版（`from:`）で取り込んだ依存先の `unsafeFlags` を許さないので、取り込むときはコミット（`revision:`）かブランチで指定する。

## 測る

サンプル動画（`.mp4`）は git に入れず、手元のフォルダに置いて `COURT_DEMO_DIR` で渡す。手順は、同梱のスキル [improve-vision-accuracy](.apm/skills/improve-vision-accuracy/SKILL.md) にある。

```bash
xcrun swift test                       # 計算のテスト
COURT_DEMO_DIR=<動画のフォルダ> COURT_QUADS_JSON=/tmp/quads.json \
  xcrun swift test -c release -Xswiftc -enable-testing --filter exportsQuadsOnDemoVideos
```

`swift test` は `xcrun` を付けて呼ぶ（付けないと、Xcode 27 の環境で `-target-arch-variant` のエラーになる）。

## スキル

スキルは [apm](https://microsoft.github.io/apm/) で管理する。正本は `.apm/skills/<名前>/` にあり、`apm install` で `.claude/skills/`、`.agents/skills/` などに展開する（展開先は git に入れない）。clone した直後は、次で apm を入れて展開する。

```bash
make setup
```

ほかのリポジトリで使うときは、そのリポジトリの `apm.yml` の `dependencies.apm` に足す。2026-11-21 より前のコミットでは、置き場所が `skills/<名前>` だった。

```yaml
- akidon0000/racket-vision/.apm/skills/improve-vision-accuracy#<コミット>
- akidon0000/racket-vision/.apm/skills/clip-play-videos#<コミット>
```

| スキル | 中身 |
| --- | --- |
| [improve-vision-accuracy](.apm/skills/improve-vision-accuracy/SKILL.md) | 解析の精度を、動画で測り、目で確かめ、直して記録する |
| [clip-play-videos](.apm/skills/clip-play-videos/SKILL.md) | 撮った動画から、プレーしている所（ラリー）だけを切り出し、アプリと Downloads に置く |

## 整形と Lint

```bash
swiftformat --lint .
swiftlint lint --strict
```

## ほかの競技に広げるとき

方式は `CourtDetectionMethod` の値で表す。使う側のアプリが自前の方式を足すときは、`extension CourtDetectionMethod { static let myMethod = CourtDetectionMethod(rawValue: "myMethod", label: "…", color: SIMD3(…)) }` と書き、`CourtRectangleDetector` を実装する。

`CourtModel` は寸法を差し替えられるが、線の並び（ベースライン、キッチンの線、センターライン）はピックルボールの形で決め打ちになっている。テニスのサービスラインやダブルスのサイドラインを入れるときは、線の並びも図面ごとに持たせる。

## デモと道具

| 場所 | 中身 |
| --- | --- |
| `DemoApp/App`（iOS） | 縦画面で、上に動画、下に解析の結果を 3D で描く。ドラッグで視点を回せる |
| `DemoApp/SamplePlayVideos` | 動画（git に入れない）。`FullLength/` は元の長さの動画で、アプリに入り、精度の計測にも使う。`RallyClips/` はラリーごとの切り出しで、アプリには入れない |
| `DemoApp/Clips` | 撮った動画の向きをそろえ、ラリーごとに切り出す道具（[clip-play-videos](.apm/skills/clip-play-videos/SKILL.md)） |
| `DemoApp/DeviceLab`（macOS） | iPhone の機種と OS の条件で、デモと同じ処理を Mac で流し、2 機種を並べて比べる。記録は [Docs/accuracy/device-lab.md](Docs/accuracy/device-lab.md) |
