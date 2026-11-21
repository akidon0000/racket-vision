---
name: wiki-git
description: racket-vision のブランチ、コミット、Pull Request の決まり、コミットの前に流す検証、PR に付ける画像や動画（デモアプリの画面）の撮り方と置き場所。ブランチを切る、コミットする、PR を作る、PR に証跡を付けるときに読む。
---

# wiki-git

Git と PR の流れをまとめる。判断の理由は `Docs/adr/` にある。

## Git の流れ

- 読み手: このリポジトリで変更をコミットし、PR を作るエージェントと人
- 目的: ブランチ、コミット、PR の決まりを示す

### ブランチ

- 作業 1 件につき、ブランチ 1 本と PR 1 本にする。
- ブランチ名は、作業を表す英語の短い kebab-case にする（例: `ball-tracking`、`court-plane-in-courtfit`）。
- 切り元は最新の `main`。前の作業の PR がまだマージされておらず、それに依存するときは、そのブランチから切る（スタック PR）。
- `main` には直接コミットしない。
- force push はしない。
- `pr-assets` は、PR の画像や動画を置くための専用ブランチ。

### コミット

- 件名は日本語で、変更を言い切る（例: 「コートの面の座標（CourtPlane）を CourtFit に移す」）。
- 変更は論理単位でコミットする。
- 動画（`DemoApp/SamplePlayVideos/`）、apm の展開先（`.claude/`、`.agents/` など）、Xcode の生成物はコミットしない（`.gitignore` で外してある）。
- 着手する前に `git status --short` で未コミットの変更がないか確かめる。残っていれば、確認してから進める。
- コミットとプッシュは、ユーザーに頼まれたときだけ行う。

### コミットの前に確かめる

変更した範囲に合わせて流す。通らなければコミットしない。

| 変更した所 | 流すもの |
|---|---|
| `Sources/`、`Tests/`（解析のパッケージ） | `xcrun swift test`（`xcrun` を付けないと、Xcode 27 で `-target-arch-variant` のエラーになる） |
| `DemoApp/Library/` | `cd DemoApp/Library && xcodebuild test -scheme DemoLibrary-Package -destination 'platform=iOS Simulator,name=iPhone 17'`（UIKit を使うので `swift test` ではビルドできない） |
| `DemoApp/App/`、アプリに入る部品 | `cd DemoApp/App && xcodegen generate` のあと、シミュレーター向けに `xcodebuild -project CourtDemo.xcodeproj -scheme CourtDemo -destination 'platform=iOS Simulator,name=iPhone 17' build` |
| `DemoApp/DeviceLab/` | `cd DemoApp/DeviceLab && xcrun swift build` |
| Swift のファイル全般 | `swiftlint lint --strict` と `swiftformat --lint .`。前からある指摘は `wiki-repo` の「要確認」にある。増やさない |
| 検出の精度に関わる直し | [improve-vision-accuracy](../improve-vision-accuracy/SKILL.md) の手順で動画で測り、`Docs/accuracy/` に記録する |
| `.apm/skills/` | `apm install` と `apm audit --ci`（`wiki-repo` の「スキルを足す・変える」） |

### Pull Request

- タイトルは、変更を言い切る日本語にする。
- 本文は [auto-create-pr のテンプレート](../auto-create-pr/templates/default.md) に従う。「概要」「変更点」「範囲外」「見た目と操作の変化」「判断」「懸念」「確認したこと」の順に書き、当てはまらない節は削る。深さは差分に比例させる。1 ファイルの修正なら「概要」と「確認したこと」だけでよい。見た目が変わらない PR では「見た目と操作の変化」を削る。「確認したこと」は、確かめていない経路を確かめたと書かない。
- デモアプリの見た目や操作が変わる PR には、変更前と変更後のスクリーンショットや動画を付ける（下の「PR の証跡」）。
- 変更ファイルの一覧は書かない。diff で確かめられるからである。
- マージは人が行う。スキルはマージしない。

### 流れ

1. 最新の `main`（スタック PR なら依存先のブランチ）から、作業用のブランチを切る。
2. 実装し、「コミットの前に確かめる」の検証を通す。
3. 見た目が変わる変更では、スクリーンショットや動画を撮って置く（下の「PR の証跡」）。
4. 変更の記録を更新する（[auto-create-documentation](../auto-create-documentation/SKILL.md)）。
5. コミットして push し、PR を作る（[auto-create-pr](../auto-create-pr/SKILL.md)）。
6. 人がレビューし、マージする。

### スタック PR のマージ

スタック PR（ベースが `main` 以外のブランチの PR）は、ベースの PR から順にマージする。

1. ベースの PR をマージする。
2. 次の PR のベースを `main` に切り替える。ベースのブランチを消す前に行う。消すと、GitHub が PR を閉じてしまい、ベースを戻せなくなるため。

   ```bash
   gh pr edit <番号> --base main
   ```

3. 切り替えたあと、PR の差分が依存先の変更を含まず、その作業の変更だけになっていることを確かめる（`gh pr diff <番号> --name-only`）。
4. 人がマージする。

## PR の証跡（スクリーンショットと動画）

- 読み手: デモアプリの画面が変わる PR を作る人
- 目的: 挙動の変化が一目で分かる画像や動画を付ける手順を示す

### いつ付けるか

- デモアプリ（`DemoApp/App`、`DemoApp/DeviceLab`）の画面、操作、文言が変わる PR には付ける。
- ライブラリの内部、ドキュメント、リファクタなど、見た目が変わらない PR には付けない。PR 本文の「見た目と操作の変化」の節ごと削る。
- 変更前（`main`）と変更後を並べられるときは、両方を撮る。新しい画面など、変更前がないときは変更後だけでよい。
- 精度の変化は、画像より `Docs/accuracy/` の数字と、確認用の画像（計測のテストが書き出す JPG）で示す。

### 撮る

シミュレーターで、デモアプリを開いて撮る。骨格の検出はシミュレーターでは動かず記録を出すだけなので、その場の検出を見せるときは、実機か Mac（`CLAUDE.md` の「デモを Mac で動かす」）で撮る。

```bash
xcrun simctl boot "iPhone 17"   # 起動していなければ（起動済みなら「Booted」のエラーで、そのまま進めてよい）
xcrun simctl io booted screenshot after.png
xcrun simctl io booted recordVideo after.mov   # Ctrl-C で止める
```

起動引数 `-autoplay <動画の名前の一部>` を渡すと、その動画を開いた状態で始まるので、同じ場面を撮り直しやすい。

動画は、PR 本文に埋め込める GIF に変換する。GitHub は、リポジトリのファイルの動画を本文に埋め込めない。

```bash
ffmpeg -i after.mov -vf "fps=12,scale=360:-1:flags=lanczos" after.gif
```

GIF が大きすぎる（目安 10 MB 超）ときは、動画の長さを短くするか、動画ファイル（mp4）へのリンクにする。

### 置く

画像と動画は、`main` の履歴に入れない。専用の `pr-assets` ブランチに、ブランチ名ごとのディレクトリで置く。作業中のブランチを切り替えないよう、`git worktree` を使う。

```bash
git fetch origin
# 初回だけ: pr-assets ブランチがなければ空の履歴で作る
git ls-remote --exit-code --heads origin pr-assets >/dev/null 2>&1 \
  || git worktree add --orphan -b pr-assets /tmp/pr-assets

# 2 回目以降
[ -d /tmp/pr-assets ] || git worktree add /tmp/pr-assets pr-assets

mkdir -p /tmp/pr-assets/<ブランチ名>
/bin/cp -f before.png after.png after.gif /tmp/pr-assets/<ブランチ名>/
git -C /tmp/pr-assets add <ブランチ名>
git -C /tmp/pr-assets commit -m "<ブランチ名> の PR の証跡を足す"
git -C /tmp/pr-assets push -u origin pr-assets
```

### 貼る

PR 本文には、`pr-assets` のコミット SHA を指す URL で書く。ブランチ名（`blob/pr-assets/...`）で書くと、あとから画像を差し替えたときに過去の PR の見た目も変わるため。SHA は、画像を置いたあとの `pr-assets` の先頭を使う。

```bash
git -C /tmp/pr-assets rev-parse HEAD
```

```markdown
![変更後](https://github.com/akidon0000/racket-vision/blob/<SHA>/<ブランチ名>/after.png?raw=true)
```

画像の下に、撮った環境を一行書く（例: iPhone 17 のシミュレーター、iOS 27.1）。

リポジトリは公開なので、画像も誰でも見られる。人の顔がはっきり写る画面は、写る人に確かめてから載せる。

### 撮り直す

push のたびに撮り直したら、本文は書き換えない。本文は最初の状態として残し、新しい画像と撮った環境は PR のコメントに載せる。新しい画像は、`pr-assets` に置き直して、その新しい SHA の URL で貼る。
