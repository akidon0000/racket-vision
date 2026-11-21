---
title: "直下と DemoApp/ の下のフォルダは大文字で始まるキャメルケースにし、動画は DemoApp/SamplePlayVideos/ にまとめる"
status: Accepted
proposed: 2026-11-21
accepted: 2026-11-21
supersedes:
---

# 直下と DemoApp/ の下のフォルダは大文字で始まるキャメルケースにし、動画は DemoApp/SamplePlayVideos/ にまとめる

## Decision（決定事項）

> **リポジトリの直下と `DemoApp/` の下のフォルダは、大文字で始まるキャメルケースにする（`Docs`、`Tools`、`DemoApp/Clips`）。動画は `DemoApp/SamplePlayVideos/` にまとめ、元の長さの動画を `FullLength/`、ラリーごとの切り出しを `RallyClips/` に置く。**

`.` で始まるフォルダはツールが決める名前なので対象外。`Docs/` と `Tools/` の中のフォルダは、まだそろえていない（`wiki-repo` の要確認）。

## Context（経緯・背景情報）

直下に `Sources`、`Tests`、`DemoApp` と、`docs`、`tools` が混ざっていた。`DemoApp/` の下も `App`、`Library`、`DeviceLab` と、`clips`、`videos`、`rally-clips` が混ざっていた。動画は `videos` と `rally-clips` の 2 か所に分かれ、切り出しの道具（`clips`）と名前が近く、どれが動画か分かりにくかった。

## Consideration（比較・検討内容）

| 案 | 概要 | 判定 |
|----|------|------|
| 案1: 現状維持 | 名前を変えずに済むが、大文字と小文字が混ざったまま | 不採用 |
| 案2: すべて小文字の kebab-case にする | `Sources` や `Tests` は SwiftPM が決める名前なので、そろえられない | 不採用 |
| 案3: 大文字で始まるキャメルケースにそろえる | Swift のモジュールの名前と同じ形になる | 採用 |

動画の置き場の名前は、中身が試合（プレー）の動画であることが分かる `SamplePlayVideos` にした。

## Consequences（結果）

- 参照しているパス（スキル、記録、`project.yml`、`.gitignore`、Python の道具）を書き換えた。コミットの SHA で固定したリンクは、当時の場所を指すので変えていない。
- macOS のファイルシステムは大文字と小文字を区別しないので、名前を変えるときは 2 段階（一度別の名前にしてから）で行う。
- 動画は git の外なので、ほかの機械では `DemoApp/SamplePlayVideos/FullLength/` に置き直す必要がある。

## References（参照）

- コミット・PR: 7b45959（`ball-tracking`）
- 関連 ADR: 0004
