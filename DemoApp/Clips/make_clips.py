"""切り出す範囲（<日付>.json）のとおりに、向きをそろえた動画から DemoApp/SamplePlayVideos/RallyClips へ切り出す。

使い方: python3 make_clips.py <元の動画のフォルダ> <作業のフォルダ> <日付>.json
- 向きをそろえた動画（作業のフォルダの <日付>-<番号>.mp4）が無ければ、normalize_videos.py と同じやり方で先に作る
  （DemoApp/SamplePlayVideos/FullLength の元の長さの動画も、無ければ作る）。
- 切り出しは HEVC 5 Mbps で、DemoApp/SamplePlayVideos/RallyClips/<日付>-<番号>-<何本目>.mp4 に書く（アプリには入れない）。
"""
import glob, json, os, subprocess, sys

from normalize_videos import VIDEOS, for_app, normalize

source_dir, work_dir, manifest = sys.argv[1], sys.argv[2], sys.argv[3]
here = os.path.dirname(os.path.abspath(__file__))
rally_clips = os.path.join(here, "..", "SamplePlayVideos", "RallyClips")
os.makedirs(rally_clips, exist_ok=True)
os.makedirs(work_dir, exist_ok=True)

clips = json.load(open(manifest))
for source in sorted({c["source"] for c in clips}):
    number = source.split("-")[1]
    full = os.path.join(work_dir, f"{source}.mp4")
    original = next(p for p in glob.glob(os.path.join(source_dir, f"IMG_{number}.*")))
    if not os.path.exists(full):
        normalize(original, full)
    target = os.path.join(VIDEOS, f"{source}.mp4")
    if not os.path.exists(target):
        for_app(original, target)
for c in clips:
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", str(c["start"]), "-to", str(c["end"]),
                    "-i", os.path.join(work_dir, f"{c['source']}.mp4"), "-c:v", "hevc_videotoolbox", "-b:v", "5M",
                    "-tag:v", "hvc1", "-c:a", "aac", "-b:a", "96k", "-movflags", "+faststart",
                    os.path.join(rally_clips, f"{c['clip']}.mp4")], check=True)
print(len(clips), "clips")
