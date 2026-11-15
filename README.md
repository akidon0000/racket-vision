# racket-vision

ラケットを使う球技（ピックルボール、テニス、バドミントンなど）の映像を解析する Swift パッケージ。今はピックルボールのコートの検出だけがある。選手の骨格の推定（`PlayerPose`）は、これから足す。

| モジュール | 中身 |
| --- | --- |
| `CourtFit` | 映像のフレームから、コートの位置（図面から画面への射影変換と、外周の四隅）を求める。コートの図面を映像に当てはめる。方式は複数あり、同じ入出力で差し替えられる。図面は今はピックルボールだけ |
| `CourtOverlay` | 検出の結果を、映像の上に方式ごとの色の線で描く（iOS） |

## 使う

```swift
.package(url: "https://github.com/akidon0000/racket-vision.git", revision: "<コミット>")
```

```swift
import CourtFit

let analyzer = CourtAnalyzer(detectors: [TrackingLineModelCourtRectangleDetector()])
let outcomes = analyzer.analyze(pixelBuffer, orientation: .up) // 32BGRA の CVPixelBuffer
```

一番よく当たるのは `TrackingLineModelCourtRectangleDetector`（線の対応+追従）。仕組みと、方式ごとの精度は [docs/accuracy/court.md](docs/accuracy/court.md) にある。

検出は画素を 1 つずつ回す計算が多いので、`CourtFit` は Debug でも最適化してビルドする設定にしてある（`unsafeFlags`）。SwiftPM は、版（`from:`）で取り込んだ依存先の `unsafeFlags` を許さないので、取り込むときはコミット（`revision:`）かブランチで指定する。

## 測る

サンプル動画（`.mp4`）は git に入れず、手元のフォルダに置いて `COURT_DEMO_DIR` で渡す。手順は、同梱のスキル [skills/improve-vision-accuracy](skills/improve-vision-accuracy/SKILL.md) にある。

```bash
xcrun swift test                       # 計算のテスト
COURT_DEMO_DIR=<動画のフォルダ> COURT_QUADS_JSON=/tmp/quads.json \
  xcrun swift test -c release -Xswiftc -enable-testing --filter exportsQuadsOnDemoVideos
```

`swift test` は `xcrun` を付けて呼ぶ（付けないと、Xcode 27 の環境で `-target-arch-variant` のエラーになる）。

## スキルを取り込む

apm を使うリポジトリでは、`apm.yml` の `dependencies.apm` に足す。

```yaml
- akidon0000/racket-vision/skills/improve-vision-accuracy#<コミット>
```

## 整形と Lint

```bash
swiftformat --lint .
swiftlint lint --strict
```

## ほかの競技に広げるとき

方式は `CourtDetectionMethod` の値で表す。使う側のアプリが自前の方式を足すときは、`extension CourtDetectionMethod { static let myMethod = CourtDetectionMethod(rawValue: "myMethod", label: "…", color: SIMD3(…)) }` と書き、`CourtRectangleDetector` を実装する。

`CourtModel` は寸法を差し替えられるが、線の並び（ベースライン、キッチンの線、センターライン）はピックルボールの形で決め打ちになっている。テニスのサービスラインやダブルスのサイドラインを入れるときは、線の並びも図面ごとに持たせる。
