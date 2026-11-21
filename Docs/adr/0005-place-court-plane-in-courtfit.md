---
title: "コートの面の座標（CourtPlane）は CourtFit に置き、デモで映像に重ねる部品は CourtLineOverlay だけにする"
status: Accepted
proposed: 2026-11-21
accepted: 2026-11-21
supersedes:
---

# コートの面の座標（CourtPlane）は CourtFit に置き、デモで映像に重ねる部品は CourtLineOverlay だけにする

## Decision（決定事項）

> **コートの座標と映像の座標を行き来する `CourtPlane` と、コートの線（`CourtSegment`、`CourtPlane.pickleballLines`、`CourtPlane.net`）は、`CourtFit` に置く。`PlayerPose` は `CourtFit` に依存する。デモで映像に重ねる部品は `CourtLineOverlay` のモジュールだけにし、使われていない 2D の重ね描き（骨格、球の点、検出の四角形）は消す。**

`CourtFit` の公開の形が増え、`PlayerPose` から `CourtPlane` が消える。`CourtPlane` を使う側は `import CourtFit` を足す。

## Context（経緯・背景情報）

`CourtPlane` は `PlayerPose` にあった。そのため、コートの線を描くだけのデモの部品（`PlayerPoseOverlay` の `CourtLinesOverlay`）も、骨格のモジュールに依存していた。`CourtPlane` は検出の結果（`DetectedQuad.corners`）から作るので、検出と同じモジュールにあるほうが自然である。

デモには、映像に重ねる部品のモジュールが 3 つ（`CourtLineOverlay`、`PlayerPoseOverlay`、`BallTrackOverlay`）あった。骨格と球を 3D に描くようにしてから（1ddec6b）、2D の骨格と球の重ね描き、検出の四角形はどこからも使われていなかった。

## Consideration（比較・検討内容）

| 案 | 概要 | 判定 |
|----|------|------|
| 案1: 現状維持 | 変えずに済むが、線を描く部品が骨格のモジュールに依存し、使わない部品も残る | 不採用 |
| 案2: 小さなモジュール（`CourtGeometry` など）を新しく作る | 依存は最小になるが、モジュールが増え、外のアプリが取り込む先も増える | 不採用 |
| 案3: `CourtFit` に移す | 検出の結果から直接作れる。外のアプリは `CourtFit` をすでに取り込んでいる | 採用 |

## Consequences（結果）

- `PlayerPose` は `CourtFit` に依存する。`CourtFit` は Debug でも最適化してビルドする設定なので、`PlayerPose` を取り込む側も同じ制約（`revision:` かブランチで取り込む）を受ける。今は外のアプリで `PlayerPose` を使うものは無い。
- デモの `DemoApp/Library` は、映像に重ねる部品が `CourtLineOverlay`（コートの線と、映像を枠に収める計算）1 つになった。
- ルートの `CourtOverlay`（CALayer で方式ごとの線を描く）は、外のアプリが使っているので残す。

## References（参照）

- コミット・PR: `ball-tracking` ブランチ（このADRと同じコミット）
- 関連 ADR: なし
