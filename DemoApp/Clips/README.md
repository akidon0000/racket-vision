# 自分たちで撮った動画の切り出し

- 読み手: 撮った動画を、デモのアプリと精度の計測に足す人
- 目的: 撮った動画を、向きをそろえて `DemoApp/SamplePlayVideos/FullLength` に置き、プレーしている所だけを 60 秒以内に切り出した動画を `DemoApp/SamplePlayVideos/RallyClips` に置く手順を残す

アプリと精度の計測は、元の長さの動画（`DemoApp/SamplePlayVideos/FullLength/20261119-4984.mp4` など 29 本）を使う。ラリーごとの切り出し（53 本）は、別に取っておくだけで、アプリには入れない（2026-11-20 に決めた）。どちらのフォルダも git の対象外なので、ここには切り方（どの動画の何秒から何秒か）と、そのための道具だけを置く。

| ファイル | 中身 |
| --- | --- |
| `20261119.json` | 2026-11-19 に撮った 29 本から切り出した 53 本の範囲（元の 25 分のうち 24 分を残した） |
| `normalize_videos.py` | 元の動画の向きをそろえ、作業のフォルダと `DemoApp/SamplePlayVideos/FullLength` に置く（撮った日で絞れる） |
| `plan_clips.py` | 球の追跡の結果から、ラリーを見つけて切り出す範囲を決める |
| `make_clips.py` | 範囲のとおりに `DemoApp/SamplePlayVideos/RallyClips` へ切り出す（向きをそろえた動画が無ければ先に作る） |

切り方: ラリー（球が 1 秒に 4 フレーム以上見つかる秒が、3 秒以内の切れ目でつながる区間）の始まりの 10 秒前から、終わりの 3 秒後まで。重なれば 1 本にまとめ、60 秒を超えたらラリーの間で切る。分けた 2 本は重ねない。

## 手順

新しく撮った動画を足すときは、スキル [clip-play-videos](../../.apm/skills/clip-play-videos/SKILL.md) の手順に従う（向きをそろえる → 球を追う → 範囲を決める → 切り出す → 目で確かめる → `~/Downloads/<日付>-rally-clips` にコピー）。

```bash
python3 DemoApp/Clips/normalize_videos.py ~/Downloads <作業のフォルダ> 20261119
COURT_DEMO_DIR=<作業のフォルダ> BALL_REPORT_DIR=<作業のフォルダ>/ball BALL_COURT=1 BALL_COURT_CACHE=<作業のフォルダ>/court \
  BALL_VIDEOS=20261119 xcrun swift test -c release -Xswiftc -enable-testing --filter reportsBallsOnDemoVideos
python3 DemoApp/Clips/plan_clips.py <作業のフォルダ> 20261119   # <作業のフォルダ>/clips.json ができる
python3 DemoApp/Clips/make_clips.py ~/Downloads <作業のフォルダ> DemoApp/Clips/20261119.json
```

`plan_clips.py` は `<作業のフォルダ>/ball/<日付>-*.json` だけを読む。

## 分かっている限界

- 球の数だけで決めるので、コートが見つからない動画（4984、4985、4993、5005）では、隣のコートの球も数え、ほぼ全部を残した。
- 球を見逃すラリーは落ちる。4989（5.6 秒）は、ラリーが見つからず、切り出していない。
- 休みの間が 13 秒より短いと、10 秒前から始めるため、休みも残る。
