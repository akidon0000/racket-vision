---
name: clip-play-videos
description: 自分たちで撮ったピックルボール（ラケット競技）の動画から、プレーしている所（ラリー）だけを切り出す。iPhone の IMG_xxxx.MOV を向きをそろえた mp4 に直し、racket-vision の球の追跡でラリーを見つけ、ラリーの 10 秒前から 3 秒後までを 60 秒以内の動画に切り、デモのアプリ（DemoApp/SamplePlayVideos/FullLength）と切り出しのフォルダ（DemoApp/SamplePlayVideos/RallyClips、~/Downloads/<日付>-rally-clips）に置く。「撮った動画を切り抜いて」「プレーの所だけにして」「ラリーごとに分けて」「休んでいる所を省いて」「今日撮った動画を登録して」「動画を精度の計測に足して」と言われたとき、Downloads に新しい IMG_ の動画が入ったときは、明示されていなくても使う。ネットの動画の切り出しや、画面の録画の編集には使わない。
---

# clip-play-videos

撮った動画を、プレーしている所だけの短い動画にする手順。道具は racket-vision リポジトリの `DemoApp/Clips/` にあり、作業はリポジトリの直下で行う。

## 決まっていること（2026-11-20 にユーザーと決めた）

- 切り方: ラリーの始まりの 10 秒前から、終わりの 3 秒後まで。重なれば 1 本にまとめ、60 秒を超えたらラリーの間で切る。分けた 2 本は重ねない。
- ラリー: 球が 1 秒に 4 フレーム以上見つかる秒が、差 3 秒以内でつながる区間（動いている秒が 3 秒以上のもの）。
- アプリと精度の計測は、元の長さの動画（`DemoApp/SamplePlayVideos/FullLength/<日付>-<番号>.mp4`）を使う。画質は元のまま（圧縮し直すと骨格の検出が落ちる。`Docs/accuracy/pose.md` の 2026-11-20「元の動画で測る」）。切り出し（`DemoApp/SamplePlayVideos/RallyClips/`）はアプリに入れず、別に取っておく。
- ユーザーに渡す切り出しは、`~/Downloads/<日付>-rally-clips/` にもコピーする。
- 動画は git に入れない（`DemoApp/SamplePlayVideos/FullLength/`、`DemoApp/SamplePlayVideos/RallyClips/` は git の対象外）。git に入れるのは、切り方の記録 `DemoApp/Clips/<日付>.json` だけ。

切り方を変えたいと言われたら、`plan_clips.py` の先頭の値（`ACTIVE`、`GAP`、`MIN_ACTIVE`、`PRE`、`POST`、`LONGEST`）を変える。

## 手順

`W` は作業のフォルダ（セッションの scratchpad の中に作る）、`SRC` は元の動画のフォルダ（ふつうは `~/Downloads`）、`DATE` は撮った日（`YYYYMMDD`）。

### 1. 元の動画を確かめる

```bash
ls -la $SRC | grep -i "IMG_"
ffprobe -v error -show_entries format_tags=com.apple.quicktime.creationdate -of default=nw=1 $SRC/IMG_xxxx.MOV
```

撮った日がいくつあるか、何本あるか、縦か横かを先に見る。撮った日が複数あれば、日ごとに 2〜6 を回す（アプリの一覧は、名前の先頭の日付ごとに見出しを分ける。`VideoShelf`）。すでに `DemoApp/Clips/<日付>.json` がある日は、前に切った日なので、ユーザーに作り直すか聞く。

### 2. 向きをそろえる

```bash
python3 DemoApp/Clips/normalize_videos.py $SRC $W $DATE
```

`$W/<日付>-<番号>.mp4`（8 Mbps、30 コマ/秒。球の追跡と切り出しの元）と、アプリ用の `DemoApp/SamplePlayVideos/FullLength/<日付>-<番号>.mp4`（元の動画の映像を圧縮し直さずに詰め直したもの。撮影の向きが記録されている動画だけ、回して 30 Mbps）ができる。25 分ぶんで数分かかる。iPhone の空間オーディオは読めないので、AAC の音声を使う（無ければ音声なし）。

### 3. 球を追う

```bash
COURT_DEMO_DIR=$W BALL_REPORT_DIR=$W/ball BALL_COURT=1 BALL_COURT_CACHE=$W/court BALL_VIDEOS=$DATE \
  xcrun swift test -c release -Xswiftc -enable-testing --filter reportsBallsOnDemoVideos
```

動画の長さと同じくらいかかるので、後ろで動かす。`$W/ball/<日付>-<番号>.json`（フレームごとの球）と、`$W/court/`（コートの記録。骨格の計測でも使い回せる）ができる。`swift test` は `xcrun` を付けて呼ぶ。

### 4. 切る範囲を決める

```bash
python3 DemoApp/Clips/plan_clips.py $W $DATE
```

動画ごとに、ラリーの数と、残した秒数が出る。`$W/clips.json` を `DemoApp/Clips/<日付>.json` に写す。

ここで、次の 2 つを見る。どちらも、球の数だけで決めるために起きる。

- ほぼ全部を残した動画: コートが見つからず、隣のコートの球も数えている。範囲は残してよいが、報告に書く。
- 1 本も切れなかった動画: 球を見逃している。短い動画（10 秒未満）なら、そのままでよい。長い動画なら、目で見て確かめる（5）。

### 5. 切り出して、目で確かめる

```bash
python3 DemoApp/Clips/make_clips.py $SRC $W DemoApp/Clips/$DATE.json
mkdir -p ~/Downloads/$DATE-rally-clips && /bin/cp -f DemoApp/SamplePlayVideos/RallyClips/$DATE-*.mp4 ~/Downloads/$DATE-rally-clips/
```

切り出しのうち数本（短いもの、長いもの、ほぼ全部を残した動画のもの）を、1 秒ごとの一覧の画像にして見る。始まりの 10 秒のうちにサーブの構えが入っているか、終わりでラリーが切れていないかを確かめる。

```bash
python3 .apm/skills/clip-play-videos/scripts/clip_sheet.py DemoApp/SamplePlayVideos/RallyClips/<切り出し>.mp4 $W/sheet.jpg
```

画像は Read で開いて見る。シェルの `rm` と `cp` は確認を求める別名になっていることがあるので、`/bin/rm -f`、`/bin/cp -f` を使う。

### 6. アプリに入れて、記録する

```bash
cd DemoApp/App && xcodegen generate
```

`DemoApp/SamplePlayVideos/FullLength` に置いた動画は、アプリの一覧の「YYYY-MM-DD 撮影」の見出しの下に出る。シミュレーターで一覧を開いて確かめる。

`DemoApp/Clips/README.md` の表に、その日の範囲のファイル（何本から何本を切り出し、元の何分のうち何分を残したか）を 1 行足し、「分かっている限界」に、その日に見つけた落ち方（コートが見つからない動画の番号など）を足す。

## 報告の形

1. 一文目で、何本の動画から何本を切り出したか、元の何分のうち何分を残したか
2. 置き場所（`DemoApp/SamplePlayVideos/FullLength`、`DemoApp/SamplePlayVideos/RallyClips`、`~/Downloads/<日付>-rally-clips`）
3. うまく切れなかった動画と、その理由（ほぼ全部を残した、1 本も切れなかった）
4. 目で確かめた切り出しと、確かめていないもの

## 分かっている限界

- 球の数だけで決めるので、コートが見つからない動画（真横や、コートの外から撮ったもの）では、隣のコートの球も数え、ほぼ全部を残す。
- 球を見逃すラリーは落ちる。
- 休みの間が 13 秒より短いと、10 秒前から始めるため、休みも残る。
- 打球音でラリーを見つける方法は、隣のコートの音と分けられず、使っていない（2026-11-19 の動画で、音の立ち上がりが 5 分で 167 回あった）。
