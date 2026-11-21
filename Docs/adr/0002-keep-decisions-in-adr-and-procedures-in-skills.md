---
title: "判断は Docs/adr/ に、手順は wiki-* と作業のスキルに、計測の結果は Docs/accuracy/ に置く"
status: Accepted
proposed: 2026-11-21
accepted: 2026-11-21
supersedes:
---

# 判断は Docs/adr/ に、手順は wiki-* と作業のスキルに、計測の結果は Docs/accuracy/ に置く

## Decision（決定事項）

> **長く残る判断と理由は `Docs/adr/` に ADR として書く。作業者が辿る手順は wiki-* スキル（`wiki-git`、`wiki-repo`）と作業のスキル（`improve-vision-accuracy`、`clip-play-videos`）に書く。精度の計測の結果は `Docs/accuracy/<対象>.md` に書く。** `CLAUDE.md` は入口として短いメモだけを置き、手順の本体はスキルの名前で指す。

書き方の手順は `write-adr`、`write-wiki`、記録先の振り分けは `auto-create-documentation`、PR の作り方は `auto-create-pr` に置く。これらは取り込み先のリポジトリのスキルを、チケットの管理と外部のレビューの手順を抜いて、このリポジトリに合わせて直したものである。

## Context（経緯・背景情報）

これまで、判断の理由は `Docs/accuracy/*.md` の記録、設計（`Docs/superpowers/specs/`）、コミットのメッセージに散らばっていた。たとえば「アプリの動画を元の画質にする」は計測の記録の中にだけあり、決めたことと測った結果の区別がつかなかった。手順も、`CLAUDE.md`、README、スキルに分かれていた。

## Consideration（比較・検討内容）

| 案 | 概要 | 判定 |
|----|------|------|
| 案1: 現状維持（記録と設計とコミットに散らす） | 書く場所を選ばなくてよいが、判断を後から探せない | 不採用 |
| 案2: すべて `CLAUDE.md` に書く | 1 か所で読めるが、長くなると毎回の読み込みが重く、Codex には届かない | 不採用 |
| 案3: 判断は ADR、手順は wiki-* と作業のスキル、結果は `Docs/accuracy/` | 取り込み先のリポジトリと同じ分け方。測った数字は今まで通り `Docs/accuracy/` に置ける | 採用 |

wiki-* のジャンルは、`wiki-git` と `wiki-repo` の 2 つから始める。iOS のビルドや実機への入れ方は、まだ `CLAUDE.md` に置く。ジャンルを足すときは ADR で決める。

## Consequences（結果）

- 決めたことは `Docs/adr/README.md` の一覧から辿れる。
- 変更のたびに、どこへ記録するかを `auto-create-documentation` の表で選ぶ手間が増える。
- `main` へ直接コミットせず、ブランチと PR で進める（`wiki-git`）。今までは `main` に直接コミットしていた。

## References（参照）

- 関連 ADR: 0001
- 参考にした構成: 取り込み先のリポジトリの `docs/adr/`、`write-adr`、`wiki-repo` のスキル
