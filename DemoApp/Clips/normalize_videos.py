"""撮った動画（iPhone の IMG_1234.MOV など）を、向きをそろえた mp4 に直す。

使い方: python3 normalize_videos.py <元の動画のフォルダ> <作業のフォルダ> [撮った日 YYYYMMDD]
- 撮った日は、動画の com.apple.quicktime.creationdate（撮った場所の時刻）から読む。無ければ creation_time（UTC）。
  日を渡したときは、その日に撮った動画だけを直す。
- 作業のフォルダに <日付>-<番号>.mp4（HEVC 8 Mbps、30 コマ/秒、向きを反映）を書く。球の追跡と切り出しの元にする。
- アプリと精度の計測で使う動画として、DemoApp/SamplePlayVideos/FullLength/<日付>-<番号>.mp4 も書く。元の動画の映像を圧縮し直さずに詰め直す
  （2026-11-20、5 Mbps に圧縮し直すと手前の 2 人の検出が 77% から 68% に落ちたため）。撮影の向きが記録されている動画だけは、
  計測の部品（VideoFrameReader）が読めないので、回して 30 Mbps で書き直す。
- すでにあるファイルは作り直さない。
iPhone の空間オーディオ（apple_apac）は ffmpeg で読めないので、AAC の音声を選ぶ。AAC が無ければ音声を入れない。
"""
import glob, json, os, re, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
VIDEOS = os.path.join(HERE, "..", "SamplePlayVideos", "FullLength")


def shooting_date(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format_tags", "-of", "json", path],
                         capture_output=True, text=True, check=True).stdout
    tags = json.loads(out).get("format", {}).get("tags", {})
    stamp = tags.get("com.apple.quicktime.creationdate") or tags.get("creation_time") or ""
    match = re.match(r"(\d{4})-(\d{2})-(\d{2})", stamp)
    return "".join(match.groups()) if match else None


def aac_stream(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "a", "-show_entries", "stream=index,codec_name",
                          "-of", "csv=p=0", path], capture_output=True, text=True, check=True).stdout
    return next((line.split(",")[0] for line in out.splitlines() if line.endswith("aac")), None)


def normalize(original, full):
    audio = aac_stream(original)
    maps = ["-map", "0:v:0"] + (["-map", f"0:{audio}", "-c:a", "aac", "-b:a", "128k", "-ac", "1"] if audio else ["-an"])
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", original, *maps, "-c:v", "hevc_videotoolbox", "-b:v", "8M",
                    "-tag:v", "hvc1", "-r", "30", "-movflags", "+faststart", full], check=True)


def rotation(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream_side_data=rotation",
                          "-of", "csv=p=0", path], capture_output=True, text=True, check=True).stdout
    return next((int(v) for v in out.replace(",", " ").split() if v.lstrip("-").isdigit()), 0)


def for_app(original, target):
    audio = aac_stream(original)
    maps = ["-map", "0:v:0"] + (["-map", f"0:{audio}", "-c:a", "copy"] if audio else ["-an"])
    video = ["-c:v", "hevc_videotoolbox", "-b:v", "30M", "-tag:v", "hvc1"] if rotation(original) else ["-c:v", "copy", "-tag:v", "hvc1"]
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", original, *maps, *video, "-movflags", "+faststart", target], check=True)


def main():
    source_dir, work_dir = sys.argv[1], sys.argv[2]
    only = sys.argv[3] if len(sys.argv) > 3 else None
    os.makedirs(work_dir, exist_ok=True)
    os.makedirs(VIDEOS, exist_ok=True)
    done = []
    for original in sorted(glob.glob(os.path.join(source_dir, "IMG_*"))):
        if os.path.splitext(original)[1].lower() not in (".mov", ".mp4"):
            continue
        date = shooting_date(original)
        if date is None or (only and date != only):
            continue
        number = re.match(r"IMG_(\d+)", os.path.basename(original)).group(1)
        name = f"{date}-{number}"
        full = os.path.join(work_dir, f"{name}.mp4")
        if not os.path.exists(full):
            normalize(original, full)
        target = os.path.join(VIDEOS, f"{name}.mp4")
        if not os.path.exists(target):
            for_app(original, target)
        done.append(name)
    print(len(done), "videos:", " ".join(done))


if __name__ == "__main__":
    main()
