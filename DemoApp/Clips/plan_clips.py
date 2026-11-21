"""球の追跡の結果から、ラリーの区間を見つけ、切り出す範囲を決める。

ラリー: 球を 1 秒に 4 フレーム以上出した秒（動いている秒）が、3 秒以内の切れ目でつながる区間。動いている秒が 3 秒以上のものだけ。
切り出す範囲: ラリーの始まりの 10 秒前から、終わりの 3 秒後まで。重なる範囲は 1 本にまとめ、60 秒を超えたら、ラリーの間で切る。
切って分けた 2 本は重ねない。
"""
import json, glob, os, sys

ACTIVE = 4
GAP = 3
MIN_ACTIVE = 3
PRE, POST, LONGEST = 10, 3, 60

def rallies(counts):
    active = [i for i, c in enumerate(counts) if c >= ACTIVE]
    groups = []
    for i in active:
        if groups and i - groups[-1][-1] <= GAP:
            groups[-1].append(i)
        else:
            groups.append([i])
    return [(g[0], g[-1] + 1) for g in groups if len(g) >= MIN_ACTIVE]

def split(window, inner):
    """window が長すぎるとき、中のラリーの間（一番長い切れ目）で 2 つに分ける。"""
    start, end = window
    if end - start <= LONGEST:
        return [window]
    gaps = [(inner[k + 1][0] - inner[k][1], k) for k in range(len(inner) - 1)]
    # 分けた両方が LONGEST の半分以上になる切れ目を優先し、無ければ一番長い切れ目
    best = None
    for gap, k in sorted(gaps, reverse=True):
        cut = (inner[k][1] + inner[k + 1][0]) / 2
        if cut - start >= 10 and end - cut >= 10:
            best = k
            break
    if best is None:
        # ラリーが 1 つで長い: 等分する
        pieces = int((end - start) // LONGEST) + 1
        size = (end - start) / pieces
        return [(start + size * i, start + size * (i + 1)) for i in range(pieces)]
    # 分けた 2 本は重ねない（同じ場面を 2 回数えないため）。次のラリーの 10 秒前が、前の 1 本の終わりより前なら、そこから始める。
    left = (start, min(end, inner[best][1] + POST))
    right = (max(left[1], inner[best + 1][0] - PRE), end)
    return split(left, inner[: best + 1]) + split(right, inner[best + 1 :])

def plan(path):
    d = json.load(open(path))
    duration = d[-1]["seconds"] + 1 / 30
    counts = [0] * (int(duration) + 1)
    for x in d:
        if x.get("ball"):
            counts[int(x["seconds"])] += 1
    found = rallies(counts)
    windows = []
    for r in found:
        w = [max(0, r[0] - PRE), min(duration, r[1] + POST), [r]]
        if windows and w[0] <= windows[-1][1]:
            windows[-1][1] = max(windows[-1][1], w[1])
            windows[-1][2].append(r)
        else:
            windows.append(w)
    clips = []
    for start, end, inner in windows:
        clips += split((start, end), inner)
    return duration, found, clips

# 使い方: python3 plan_clips.py <作業のフォルダ> [撮った日 YYYYMMDD]
# <作業のフォルダ>/ball/<日付>-<番号>.json（球の追跡の書き出し）を読み、<作業のフォルダ>/clips.json を書く。
S = sys.argv[1]
pattern = f"{sys.argv[2]}-*.json" if len(sys.argv) > 2 else "[0-9]*-*.json"
result = []
for p in sorted(glob.glob(f"{S}/ball/{pattern}")):
    name = os.path.basename(p)[:-5]
    duration, found, clips = plan(p)
    kept = sum(e - s for s, e in clips)
    print(f"{name} {duration:6.1f}s rallies={len(found)} clips={len(clips)} kept={kept:5.1f}s  " + " ".join(f"[{s:.0f}-{e:.0f}]" for s, e in clips))
    for i, (s, e) in enumerate(clips, 1):
        result.append({"source": name, "clip": f"{name}-{i}", "start": round(s, 2), "end": round(e, 2)})
json.dump(result, open(f"{S}/clips.json", "w"), indent=1, ensure_ascii=False)
total = sum(c["end"] - c["start"] for c in result)
print(len(result), "clips", f"{total:.0f}s")
