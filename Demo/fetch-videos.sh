#!/bin/sh
# サンプル動画を、ダウンロードのフォルダから、Demo/videos/ へコピーし、名前を揃える。
# 名前は pickleball-play-demo-1min-NN.mp4（NN は 01 から）。コピー先の既存の動画は消してから入れ直す。
# Demo/videos/ は git の対象外（Demo/.gitignore）。元のフォルダは環境変数 SAMPLE_VIDEO_SOURCE で変えられる（既定は ~/Downloads/sample）。
set -eu
source_dir="${SAMPLE_VIDEO_SOURCE:-$HOME/Downloads/sample}"
target_dir="$(cd "$(dirname "$0")" && pwd)/videos"

# 元の名前 → 新しい名前（この順で 01 から番号を振る）
mapping="01_cand2_1min.mp4
01_cand3_1min.mp4
02_cand1_1min.mp4
02_cand2_1min.mp4
02_cand3_1min.mp4
03_9lqL_1min.mp4
pickleball-play-demo-1min-06.mp4
pickleball-play-demo-1min-07.mp4
pickleball-play-demo-short-01.mp4
pickleball-play-demo-short-02.mp4
pickleball-play-demo-short-03.mp4
pickleball-play-demo-short-04.mp4
pickleball-play-demo-short-05.mp4"

mkdir -p "$target_dir"
rm -f "$target_dir"/*.mp4
number=0
echo "$mapping" | while IFS= read -r original; do
  number=$((number + 1))
  printf -v new 'pickleball-play-demo-1min-%02d.mp4' "$number"
  if [ ! -f "$source_dir/$original" ]; then
    echo "見つからない: $source_dir/$original" >&2
    exit 1
  fi
  cp -f "$source_dir/$original" "$target_dir/$new"
  echo "$original -> $new"
done
