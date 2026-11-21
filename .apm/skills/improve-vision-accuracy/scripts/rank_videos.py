"""骨格の計測の JSON から、精度が良い動画を選ぶ。
使い方: python3 rank_videos.py <骨格の計測のフォルダ（reportsPlayersOnDemoVideos の POSE_REPORT_DIR）> [本数]
最後に出す JSON を DemoApp/App/App/featured-videos.json に写すと、アプリの一覧の一番上に出る。
- 手前の 2 人（番号 0 と 1）が両方見つかったフレームの割合で並べる。
- コートが 90% 以上のフレームで見つかり、10 秒以上ある動画だけを候補にする（短い動画は、たまたま良く出るため）。
"""
import glob, json, sys
d0 = sys.argv[1]; top = int(sys.argv[2]) if len(sys.argv) > 2 else 5
rows = []
for p in sorted(glob.glob(f"{d0}/2026*.json")):
    d = json.load(open(p)); n = len(d)
    def cnt(f, ids): return sum(1 for q in f["players"] if q["id"] in ids and q["isDetected"])
    near2 = sum(1 for f in d if cnt(f, (0, 1)) == 2) / n
    far2 = sum(1 for f in d if cnt(f, (2, 3)) == 2) / n
    court = sum(1 for f in d if f["courtFound"]) / n
    rows.append(dict(name=p.split("/")[-1][:-5], frames=n, near2=near2, far2=far2, court=court))
for r in sorted(rows, key=lambda r: -r["near2"]):
    ok = r["court"] >= 0.9 and r["frames"] >= 100
    print(f"{'*' if ok else ' '} {r['name']} {r['frames']:5d} near2={r['near2']:4.0%} far2={r['far2']:4.0%} court={r['court']:4.0%}")
picked = [r for r in sorted(rows, key=lambda r: -r["near2"]) if r["court"] >= 0.9 and r["frames"] >= 100][:top]
print(json.dumps({"title": f"精度が良い動画（上位 {len(picked)} 本）", "videos": [
    {"name": r["name"], "caption": f"手前 2 人 {r['near2']:.0%}・奥 2 人 {r['far2']:.0%}・コート {r['court']:.0%}"} for r in picked]},
    ensure_ascii=False, indent=2))
