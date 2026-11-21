# コートの検出

コートの検出（パッケージの `Sources/CourtFit/`）の精度を測って直すときに読む。

## 方式

方式は `CourtDetectionMethod` に並んでいる。使う側のアプリは、方式を `CourtAnalyzer` に登録し、`CourtMethodSwitches` で出し分ける。方式は絞らずに残して比べる方針（2026-11-15 時点）。

| rawValue | 画面の名前 | 中身 | 既定 |
| --- | --- | --- | --- |
| `vision` | Vision | Vision の矩形検出 | オン |
| `lineSearch` | 線の探索 | 輝度の勾配から直線を取り、四角形を作る | オフ |
| `lineModel` | 線の対応 | 白線の芯から直線を取り、図面の線 8 本との対応を総当たり | オフ |
| `lineModelPolished` | 線の対応+等倍で仕上げ | 上を、縮めない画像で合わせ直す | オフ |
| `lineModelTracking` | 線の対応+追従 | 上と同じ探し方。見つけた後は前のフレームから合わせ直す | オン |

一番よく当たるのは `lineModelTracking`。仕組みは下の「線の対応の段」にある。

## 測るコマンド

すべてパッケージの直下で実行する。`D=<サンプル動画のフォルダ>`、`OUT=<一時フォルダ>` とする。

| 何を | コマンド | 出るもの |
| --- | --- | --- |
| 全方式の結果の書き出し（2 秒ごと） | `COURT_DEMO_DIR=$D COURT_QUADS_JSON=$OUT/quads.json xcrun swift test -c release -Xswiftc -enable-testing --filter exportsQuadsOnDemoVideos` | 方式ごとの四隅の JSON。アプリと同じく `CourtAnalyzer` のふるい込みを通した後の結果 |
| 結果を描いた画像（2 秒ごと） | `COURT_DEMO_DIR=$D COURT_REPORT_DIR=$OUT/report xcrun swift test -c release -Xswiftc -enable-testing --filter reportsDetectionOnDemoVideos` | `<方式>-<動画>-<秒>s.png`（出さなかったフレームは `-miss.png`）と `report.md` |
| 正解の交点との採点 | `COURT_DEMO_DIR=$D COURT_REPORT_DIR=$OUT xcrun swift test -c release -Xswiftc -enable-testing --filter reportsScoreOnDemoVideos` | `score.md`。交点のずれ（cm、px） |
| 途中の段の画像 | `COURT_DEMO_DIR=$D COURT_PREVIEW_DIR=$OUT/preview COURT_PREVIEW_FRAMES=short-03:9,1min-06:41 xcrun swift test -c release -Xswiftc -enable-testing --filter previewsLineModelSearch` | 白線の芯（白）、拾った直線（黄）、当てはめた図面（赤） |

方式を絞るときは `COURT_METHODS=lineModel,lineModelTracking` を足す（書き出しと画像の両方に効く）。全方式・全動画で数分かかる。

比べ合わせ（`K=<このスキルのフォルダ>`）:

```bash
python3 $K/scripts/compare_exports.py summary $OUT/after.json
python3 $K/scripts/compare_exports.py diff $OUT/before.json $OUT/after.json --method lineModelTracking
python3 $K/scripts/compare_exports.py score $OUT/after.json --reference $OUT/checked.json --exclude 1min-06:41
```

`score` の基準（`--reference`）は、目で全フレーム確かめた書き出し。正解の交点は 8 フレームにしか無いので、全フレームの当たり外れは、この方法で数える。基準にした方式は当然 100% になるので、報告ではその旨を書く。

画像を並べる:

```bash
<一時フォルダ>/contact_sheet $OUT/sheet.jpg 6 320 $OUT/report/lineModelTracking-pickleball-play-demo-1min-01-*.png
TILE_HEIGHT=384 <一時フォルダ>/contact_sheet $OUT/sheet.jpg 10 216 $OUT/report/lineModelTracking-pickleball-play-demo-short-01-*.png
```

ファイル名の秒は 1、3、…、11 の順に並ばない（`11s` が `1s` より前に来る）。順に見たいときは、秒の数で並べ替えてから渡す。

## 正解の交点

`Tests/CourtAnnotations/<動画の名前>.json` にある（交点 12 個の画面の位置）。付けた人のずれが 5〜30cm あるので、コートの面で 5cm の合格線はこのデータでは判定できない。画面の上のずれ（px）も一緒に見る。正解を付ける道具は `Tools/court-annotator/index.html`（ブラウザで開き、書き出したフレームの画像を読み込んで交点をクリックする）。フレームの画像は `exportsFramesForAnnotation`（`COURT_DEMO_DIR` と `COURT_FRAMES_DIR` を指定）で書き出せる。

## 線の対応の段

落ちたフレームは、途中の段の画像（`previewsLineModelSearch`）で、どの段で落ちたかを決める。

| 段 | 処理 | ファイル | 落ちたときの見え方 |
| --- | --- | --- | --- |
| 1. 白線の芯 | 赤・緑・青の一番小さい値を白さとし、両側より白い画素を残す。横幅 1600px 以上の映像は半分に縮める | `EdgeMap+WhiteRidge.swift` | 白い画像にコートの線が出ていない |
| 2. まっすぐな芯 | 前後 15 画素がまっすぐ続く芯だけを残す（文字・観客・服を消す） | `RidgeMask.swift` | 線が途切れて消えている |
| 3. 直線 | ハフ変換で拾い、芯に当てはめ直し、続く長さの順に、向き（15 度ごと）ごとに 6 本、計 18 本を選ぶ | `CourtLineModelSearch.swift` の `fittedLines` | 黄色の直線に、コートの線が入っていない |
| 4. 対応の総当たり | 直線 2 本ずつ 2 組を、図面の横の線 4 本・縦の線 3 本に当てはめ、カメラとしてありえる変換を、図面の線の重なりで採点 | `forEachHypothesis`、`CameraEstimate.swift` | 赤の図面が、別の線の組に当たっている |
| 5. 位置合わせ | 上位を、線の法線方向のエッジに合わせ直す（Levenberg-Marquardt） | `CourtAlignment.swift` | 赤が線から少しずれている |
| 6. 受け入れ | 支持率 0.55 以上、図面の線 8 本のうち 5 本以上が「線として」見えていること（芯の外側の両脇に別の芯が無い点が 4 分の 1 以上） | `isAccepted`、`supportedLineCount` | 正しい当てはめなのに出ない、または観客席に出る |
| 7. 追従 | 前のフレームの変換から 5 と 6 だけを行う。通らなければ探し直す | `LineModelCourtRectangleDetector.swift` | カメラが切り替わっても前の枠が残る |

## 分かっている落ち方

| 映像 | 落ち方 | 段 | 直したか |
| --- | --- | --- | --- |
| 縦長の動画 | 半分に縮めると線が短く、直線として拾えない | 1、3 | 直した（横幅 1600px 未満は縮めない） |
| 字幕・観客席の多い映像 | 横線で直線の枠が埋まり、斜めのサイドラインが漏れる | 3 | 直した（向きごとに上限） |
| 観客席 | 細かい芯だらけで、どこに線を引いても当たる | 6 | 直した（両脇が空いているか） |
| コートの外側の縁がある床 | 毎フレーム探すと、外側の縁に当てはめる | 4 | 追従で避けている |
| 真横・低い位置、手持ちで近い | 見える線が 2〜3 本で、変換が決まらない | 4 | 未。重力の向き（CoreMotion）で傾きを決める案。実機の映像が要る |
| 体育館（別の競技の線） | 別の線の組に当てはめる | 4、6 | 未。線の色と、線の間隔で絞る案 |
| 屋外（白とオレンジの線） | 見える白線が少ない | 1、4 | 未 |

奥の角は、画面で 7〜15px のずれでもコートの面では 30〜50cm になる（奥ほど 1px が長い）。イン/アウトの判定に使うなら、ここを詰める必要がある。

## よくある詰まり

- シミュレーターで枠が遅れて残る: 検出は Debug（最適化なし）だと 1 フレームに数秒かかる。使う側のアプリで、このパッケージを最適化してビルドする（Release で動かす、またはアプリ側の設定で最適化をかける）。
- `CourtAnalyzer` は、方式が支持率を自分で出しているとき（`supports` が四角形と同じ数）は、輝度の勾配での再検査をしない（`DetectionOutcome+Plausible.swift`）。
- 追従の方式は前のフレームを覚えるので、動画ごとに作り直す（`DemoVideoQuadsExport` はそうしている）。
