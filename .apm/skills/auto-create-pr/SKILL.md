---
name: auto-create-pr
description: racket-vision で、コミット、push、Pull Request の作成を一つの手順で行う。「プルリクエストを作成」「PRを作成」「PR にして」などの要求で使用する。
---

## 制約

- この skill だけでコミット、push、Pull Request 作成まで行う。別の skill へ処理を委譲しない（記録の更新は前もって [auto-create-documentation](../auto-create-documentation/SKILL.md) で済ませておく）。
- 現在のブランチが `main` の場合は作業を止める。
- ユーザーが明示的に依頼していない限り、コミット・push を行わない（「PR を作成して」とだけ言われたときは状態確認と本文作成まで）。
- 既存 PR がある場合は本文を上書きせず、ユーザーに確認する。
- PR 本文にエージェント用フッターや変更ファイル一覧を含めない。
- GitHub の branch protection 設定は変更しない。

## ワークフロー

### 1. 状態とブランチを確認する

```bash
git status
git diff --stat
git log --oneline -5
git branch --show-current
gh pr list --head "$(git branch --show-current)" --state open
```

`main` 上では作業を止める。依頼と無関係な変更をコミットに含めない。動画（`DemoApp/SamplePlayVideos/`）や展開先（`.claude/`、`.agents/`）が混ざっていないかも見る。

### 2. 確かめる

コミットの前に、変更に関わる検証を通す。何を流すかは [wiki-git](../wiki-git/SKILL.md) の「コミットの前に確かめる」に従う。通らなければコミットしない。

### 3. コミットと push を行う（依頼がある場合）

変更がある場合は、論理単位でコミットする。件名は日本語で、変更を言い切る（`wiki-git` の「コミット」）。

```bash
git add <files>
git commit -m "$(cat <<'MSG'
コミットメッセージ

MSG
)"
git push -u origin "$(git branch --show-current)"
```

### 4. 本文を作成する

本文は [templates/default.md](templates/default.md) を使う。

「概要」「変更点」「範囲外」「見た目と操作の変化」「判断」「懸念」「確認したこと」を差分から確認できる事実に基づいて記載する。当てはまらない節は削除し、深さは差分に比例させる。変更ファイルの列挙は行わず、コンポーネント（モジュール）ごとにまとめる。精度が変わる変更では、直す前と後の数字と、`Docs/accuracy/` の記録へのリンクを入れる。「確認したこと」は、確かめていない経路を確かめたと書かない。

### 5. PR を作成する

```bash
gh pr create \
  --title "日本語のタイトル" \
  --base <ベースのブランチ> \
  --body-file <temporary-body-file>
```

`--base` は切り元のブランチにする。スタック PR なら依存先のブランチ、それ以外は `main`（`wiki-git` の「ブランチ」）。

タイトルと本文の規範は `wiki-git` に従う。本文の一時ファイルは PR 作成後に削除する。

```bash
gh pr view --web
```

## エラー時

- コミット失敗時は hook やテストのエラーを報告し、push しない。
- push 失敗時は原因を報告し、force push は行わない。
- PR 作成失敗時はコミットと push の状態を保持し、手動作成に必要な情報を提示する。
