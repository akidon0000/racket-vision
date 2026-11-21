---
title: "Agent Skills は apm で管理し、正本を .apm/skills/ に置く"
status: Accepted
proposed: 2026-11-21
accepted: 2026-11-21
supersedes:
---

# Agent Skills は apm で管理し、正本を .apm/skills/ に置く

## Decision（決定事項）

> **スキルの正本は `.apm/skills/<名前>/` に置き、`apm install` で各エージェントの置き場（`.claude/skills/`、`.agents/skills/` など）に展開する。展開先は git に入れない。** `CLAUDE.md` は手で書く作業メモとして git に入れ、apm からは作らない。

展開先のエージェントは `apm.yml` の `targets`（cursor、claude、codex）で決める。初回は `make setup` で apm を入れて展開する。

## Context（経緯・背景情報）

スキル（improve-vision-accuracy、clip-play-videos）は `skills/<名前>/` に置き、ほかのリポジトリが apm で取り込んでいた。このリポジトリ自身では展開しておらず、Claude Code はこのリポジトリで作業していてもスキルを読み込まなかった。取り込み先のリポジトリでは、正本を `.apm/skills/` に置いて `apm install` で展開する形で運用している。

## Consideration（比較・検討内容）

| 案 | 概要 | 判定 |
|----|------|------|
| 案1: 現状維持（`skills/` に置き、展開しない） | 外からは取り込めるが、このリポジトリでの作業ではスキルが読み込まれない | 不採用 |
| 案2: `skills/` を正本のまま、`.claude/skills/` へ手でリンクする | エージェントごとに置き場が違い、リンクを手で保つ必要がある | 不採用 |
| 案3: `.apm/skills/` を正本にし、`apm install` で展開する | 取り込み先のリポジトリと同じ形。展開先を `targets` で増やせる | 採用 |

`CLAUDE.md` は、取り込み先のリポジトリでは `.apm/instructions/` から作って git の外に置く。このリポジトリでは、毎回調べ直していた手順を手で書き足すメモとして使っているので、git に入れる。

## Consequences（結果）

- このリポジトリで作業するとき、Claude Code と Codex がスキルを読み込む。
- 外からの取り込みのパスが `akidon0000/racket-vision/.apm/skills/<名前>#<コミット>` に変わる。2026-11-21 より前のコミットは `skills/<名前>` のまま取れる（7b45959 で新しいパスから取れることを確かめた）。
- スキルを直したら `apm install` を流す必要がある。手順は `wiki-repo` の「スキルを足す・変える」。
- Codex 向けの `AGENTS.md` は作られないので、`CLAUDE.md` のメモは Codex に届かない（`wiki-repo` の要確認）。

## References（参照）

- コミット・PR: 7b45959（`ball-tracking`）
- 関連 ADR: 0002
- 参考にした構成: 取り込み先のリポジトリの `.apm/`、`apm.yml`、`.gitignore`
