# 球の位置の正解づけ（見逃しを測るため）

- `frames/NNN.jpg`: 1920×1080 の全フレーム。黄色い格子は 120 px 間隔（左上が原点）。
- `labels.csv` に、フレームごとに書く。
  - `visible`: 球が見えるなら `yes`、見えないなら `no`、判断できないなら `unsure`
  - `ball_x_px`、`ball_y_px`: 球の中心の位置（画像の左上が原点、ピクセル）。`visible` が `yes` のときだけ書く
  - `note`: 任意（例: 手に持っている、ネットの後ろ）
- 球が小さいときは、画像ビューアで拡大して位置を読む。読めないときは `unsure`。

`frames/` の画像は大きい（40 枚で 13 MB）ので git に入れない。無いときは、`frames.json` の動画（`DemoApp/SamplePlayVideos/FullLength/<video>.mp4`）と秒から抜き直す。
