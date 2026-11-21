"""切り出した動画を、1 秒に 1 枚ずつ並べた一覧の画像にする（始まりと終わりで、ラリーが切れていないかを見るため）。

使い方: python3 clip_sheet.py <動画> <一覧の画像.jpg> [列の数（既定 8）]
"""
import math, subprocess, sys, tempfile

video, out = sys.argv[1], sys.argv[2]
columns = int(sys.argv[3]) if len(sys.argv) > 3 else 8
tmp = tempfile.mkdtemp()
subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", video, "-vf", "fps=1,scale=320:-2", f"{tmp}/%03d.jpg"], check=True)
count = int(subprocess.run(["sh", "-c", f"ls {tmp} | wc -l"], capture_output=True, text=True).stdout)
rows = max(1, math.ceil(count / columns))
subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", f"{tmp}/%03d.jpg", "-vf", f"tile={columns}x{rows}", "-frames:v", "1", out],
               check=True)
print(count, "frames", out)
