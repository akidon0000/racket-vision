#!/usr/bin/env python3
"""検出の書き出し（DemoVideoQuadsExport の JSON）を集計し、直す前と後を比べる。

使い方:
  compare_exports.py summary AFTER.json
      方式 × 動画ごとに、枠を出したフレームの数と平均処理時間を出す。
  compare_exports.py diff BEFORE.json AFTER.json [--method lineModelTracking] [--threshold 0.03]
      直す前と後で、枠が出た・消えた・動いたフレームを一覧にする。目で確かめる対象を絞るのに使う。
  compare_exports.py score AFTER.json --reference REF.json [--reference-method lineModelTracking]
                     [--exclude 1min-06:39,1min-06:41]
      目で確かめた書き出し（REF）を基準に、方式ごとに「当たった・外れた・出さなかった・誤って出した」を数える。

「動いた」「当たった」の判定は、四隅どうしの距離（ハウスドルフ距離）が、フレームの長辺 × threshold 以内かどうか。
既定の 0.03 は、1920px の映像で約 58px。
"""
import argparse
import json
import math
import sys
from collections import defaultdict


def load(path):
    with open(path) as file:
        frames = json.load(file)
    return {(frame["video"], int(round(frame["seconds"]))): frame for frame in frames}


def short_name(video):
    # pickleball-play-demo-1min-01 → 1min-01
    return video.replace("pickleball-play-demo-", "")


def pixels(quad, frame):
    width = frame.get("imageWidth", 1920)
    height = frame.get("imageHeight", 1080)
    return [(x * width, (1 - y) * height) for x, y in quad]


def distance(first, second, frame):
    a, b = pixels(first, frame), pixels(second, frame)
    one = max(min(math.dist(p, q) for q in b) for p in a)
    two = max(min(math.dist(p, q) for q in a) for p in b)
    return max(one, two)


def tolerance(frame, ratio):
    return max(frame.get("imageWidth", 1920), frame.get("imageHeight", 1080)) * ratio


def methods_in(frames):
    names = set()
    for frame in frames.values():
        names.update(frame["quads"].keys())
    return sorted(names)


def summary(args):
    frames = load(args.after)
    videos = sorted({video for video, _ in frames})
    print("| 方式 | " + " | ".join(short_name(v) for v in videos) + " | 平均処理時間（ms） |")
    print("| --- |" + " --- |" * (len(videos) + 1))
    for method in methods_in(frames):
        cells, times = [], []
        for video in videos:
            own = [f for (v, _), f in frames.items() if v == video]
            hits = sum(1 for f in own if f["quads"].get(method))
            cells.append(f"{hits}/{len(own)}")
            times += [f["milliseconds"].get(method, 0) for f in own]
        mean = sum(times) / len(times) if times else 0
        print(f"| {method} | " + " | ".join(cells) + f" | {mean:.0f} |")


def diff(args):
    before, after = load(args.before), load(args.after)
    changed = defaultdict(list)
    for key in sorted(after):
        if key not in before:
            continue
        old = before[key]["quads"].get(args.method) or []
        new = after[key]["quads"].get(args.method) or []
        frame = after[key]
        if old and not new:
            kind = "消えた"
        elif new and not old:
            kind = "出た"
        elif old and new and distance(old[0], new[0], frame) > tolerance(frame, args.threshold):
            kind = "動いた"
        else:
            continue
        changed[short_name(key[0])].append(f"{key[1]}秒（{kind}）")
    total = sum(len(items) for items in changed.values())
    print(f"{args.method}: 変わったフレーム {total} 枚")
    for video, items in sorted(changed.items()):
        print(f"- {video}: " + "、".join(items))


def score(args):
    frames, reference = load(args.after), load(args.reference)
    excluded = set()
    for item in filter(None, (args.exclude or "").split(",")):
        video, seconds = item.split(":")
        excluded.add((video, int(seconds)))
    rows = defaultdict(lambda: defaultdict(int))
    for key, frame in frames.items():
        if (short_name(key[0]), key[1]) in excluded or key not in reference:
            continue
        truth = reference[key]["quads"].get(args.reference_method) or []
        for method, quads in frame["quads"].items():
            row = rows[method]
            if truth:
                row["court"] += 1
                if not quads:
                    row["missed"] += 1
                elif any(distance(q, truth[0], frame) <= tolerance(frame, args.threshold) for q in quads):
                    row["correct"] += 1
                else:
                    row["wrong"] += 1
            else:
                row["empty"] += 1
                row["false"] += 1 if quads else 0
    print("| 方式 | 当たった | 外れた枠を出した | 出さなかった | 枠の無いはずのフレームで出した |")
    print("| --- | --- | --- | --- | --- |")
    for method, row in sorted(rows.items()):
        court = row["court"] or 1
        print(f"| {method} | {row['correct']}/{row['court']}（{100 * row['correct'] / court:.0f}%） | {row['wrong']} "
              f"| {row['missed']} | {row['false']}/{row['empty']} |")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    one = commands.add_parser("summary")
    one.add_argument("after")
    two = commands.add_parser("diff")
    two.add_argument("before")
    two.add_argument("after")
    two.add_argument("--method", default="lineModelTracking")
    two.add_argument("--threshold", type=float, default=0.03)
    three = commands.add_parser("score")
    three.add_argument("after")
    three.add_argument("--reference", required=True)
    three.add_argument("--reference-method", default="lineModelTracking")
    three.add_argument("--exclude")
    three.add_argument("--threshold", type=float, default=0.03)
    args = parser.parse_args()
    {"summary": summary, "diff": diff, "score": score}[args.command](args)


if __name__ == "__main__":
    sys.exit(main())
