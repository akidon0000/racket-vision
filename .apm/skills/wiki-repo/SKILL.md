---
name: wiki-repo
description: racket-vision のリポジトリの構成（解析のパッケージ、デモアプリ、動画、記録の置き場所）、フォルダの名前の付け方、ADR と手順を更新する基準、Agent Skills（apm）の足し方と名前の付け方、確かめられていない事項（要確認）。構成を変える、フォルダを足す、スキルを足す・名前を変える、ドキュメントを更新するときに読む。
---

# wiki-repo

リポジトリの保守をまとめる。判断の理由は `Docs/adr/` にある。

## リポジトリの保守

- 読み手: このリポジトリの構成を変える人、記録を更新するエージェント
- 目的: リポジトリの構成と、ADR と wiki スキルを更新する基準を示す

### 構成

| 領域 | 場所 | 内容 |
|------|------|------|
| 解析のパッケージ | `Package.swift`、`Sources/` | 外のアプリが取り込むライブラリ（CourtFit、CourtOverlay、BallTracking、PlayerPose、CourtScene、SceneAdvisor）と、計測のテスト用の部品（VideoTestSupport） |
| テストと正解 | `Tests/` | 単体のテストと、環境変数を渡したときだけ動画を流す計測のテスト。正解のデータは `Tests/CourtAnnotations/`（コートの交点）、`Tests/BallAnnotations/`（球の位置。画像は git の外） |
| デモアプリ | `DemoApp/App/`、`DemoApp/Library/` | iOS のデモ。殻は xcodegen（`project.yml`）で作り、画面の部品は Swift パッケージ `DemoApp/Library/` に置く。解析のパッケージには依存するが、逆向きの依存は無い |
| 機種の再現 | `DemoApp/DeviceLab/` | iPhone の機種と OS の条件を Mac で再現するアプリ |
| 動画 | `DemoApp/SamplePlayVideos/` | `FullLength/`（元の長さ。アプリに入り、計測にも使う）、`RallyClips/`（ラリーごとの切り出し）。どちらも git の外 |
| 動画の道具 | `DemoApp/Clips/` | 撮った動画の向きをそろえ、ラリーごとに切り出す（[clip-play-videos](../clip-play-videos/SKILL.md)）。切り方の記録 `<日付>.json` は git に入れる |
| 道具 | `Tools/` | コートの正解づけの道具（`court-annotator/index.html`） |
| 精度の記録 | `Docs/accuracy/` | 対象ごとの計測の結果と、外れ方（[improve-vision-accuracy](../improve-vision-accuracy/SKILL.md)） |
| 意思決定 | `Docs/adr/` | 長く残る判断と理由 |
| 設計と計画 | `Docs/superpowers/` | 機能ごとの設計（`specs/`）と実装の計画（`plans/`） |
| 自前のスキル | `.apm/skills/` | エージェントが使う手順の正本 |
| 外部スキルの定義 | `apm.yml`、`apm.lock.yaml` | 取り込み元と版、展開先のエージェント |
| 初期設定 | `Makefile` | `make setup` で apm を入れ、スキルを展開する |
| 整形と Lint | `.swiftformat`、`.swiftlint.yml` | ルートの設定が、`DemoApp/` の下も含めて全体に効く |
| エージェントの入口 | `CLAUDE.md` | 最初に読む短いメモ。手順の本体は wiki-* とスキルに置き、ここからは名前で指す。手で書き、git に入れる |

CI は無い。検証はコミットの前に手元で流す（`wiki-git` の「コミットの前に確かめる」）。

### フォルダの名前

- リポジトリの直下と `DemoApp/` の下のフォルダは、大文字で始まるキャメルケースにする（例: `Docs`、`Tools`、`SamplePlayVideos`）。Swift のモジュールの名前（`Sources/CourtFit` など）と同じ形にそろえるため（ADR 0003）。
- `.` で始まるフォルダ（`.apm`、`.build` など）は、ツールが決める名前なので対象外。
- 新しいフォルダを足すときは、この形にする。

### ADR に残す変更

次のどれかに当たる判断は、ADR にする（[write-adr](../write-adr/SKILL.md)）。

- アーキテクチャと、モジュールの境界（どのモジュールに何を置くか、依存の向き）
- 外部依存の採用と不採用
- 守るべき規則（グラウンドルール）の変更
- 条件が変わったら見直す割り切り（再評価の条件を伴うもの）

ファイルを動かしただけで、意味も運用も変わらない変更は ADR にしない。

### wiki-* に残す変更

作業者が辿るパス、コマンド、ワークフローが変わるときは、該当する `wiki-*` スキルを更新する（[write-wiki](../write-wiki/SKILL.md)）。

- Git と PR の決まり、コミットの前の検証（`wiki-git`）
- リポジトリの構成、フォルダの名前、スキルの足し方（`wiki-repo`）

精度の測り方は `improve-vision-accuracy`、動画の切り出し方は `clip-play-videos` が正本なので、そちらを直す。

### 変更の記録

PR を作る前に [auto-create-documentation](../auto-create-documentation/SKILL.md) を呼ぶ。手で変更するときも、同じ基準で記録する。

- 判断は ADR に、手順は wiki-* とスキルに、計測の結果は `Docs/accuracy/` に書く。
- 文は、採用した内容と理由を肯定の形で書く。選ばなかった案との比較は ADR の Consideration に書く。禁止の決まりは禁止のまま書く。
- 迷ったものは、この skill の「要確認」に書く。ADR には書かない。
- 記録しないときは、理由を一文で最後の報告に書く。

## Agent Skills

- 読み手: スキルを足す・直す・名前を変える人
- 目的: スキルの正本、取り込み、生成先、命名の決まりを示す

### 正本と生成先

| パス | 役割 |
|------|------|
| `.apm/skills/` | 自前のスキルの正本。編集とコミットはここで行う |
| `apm.yml` | 取り込む外部スキルと、展開先のエージェント（`cursor`、`claude`、`codex`） |
| `apm.lock.yaml` | 解決済みの版と、生成したファイルの記録。コミットする |
| `.agents/`、`.claude/`、`.cursor/`、`.codex/` など | `apm install` が生成する。Git 管理外（`.gitignore`） |

ほかのリポジトリからは、`apm.yml` の `dependencies.apm` に `akidon0000/racket-vision/.apm/skills/<名前>#<コミット>` と書いて取り込む（README の「スキル」）。

### 命名の決まり

- 接頭辞（`wiki-`、`auto-`、`write-`）の違いと、新しいスキルの名前の付け方は [guideline.md](guideline.md) にある。
- 利用者が頼む作業そのものを表すスキルは、接頭辞を付けず、作業の名前にする（例: `improve-vision-accuracy`、`clip-play-videos`）。
- `auto-` は、作業の途中で他のスキルの手順から呼ばれ、利用者が直接呼ぶことを想定しないスキルに付ける（例: `auto-create-documentation`、`auto-create-pr`）。
- 旧い名前は残さない。名前を変えたら、[名前を変える](#名前を変える)の手順で、旧い名前の展開先と `apm.lock.yaml` の行を消す。

### スキルを足す・変える

1. `.apm/skills/<名前>/SKILL.md` を作るか、直す。
2. `apm install` を実行する（初回は `make setup`）。
3. `.claude/skills/<名前>/SKILL.md` と `.agents/skills/<名前>/SKILL.md` が生成されたことを確かめる。名前を変えたときは、旧い名前が残っていないことも確かめる。
4. `apm audit --ci` が通ることを確かめる。
5. `git status` で、コミットするファイルに想定外のものがないか確かめる。`apm.lock.yaml` が変わっていれば、一緒にコミットする。

スキルの中から、リポジトリの道具（`DemoApp/Clips/*.py` など）を指すときは、リポジトリの直下からのパスで書く。スキルに同梱する道具（`scripts/`）は、`.apm/skills/<名前>/scripts/` のパスで書く。

### 名前を変える

`git mv` で `.apm/skills/` の名前を変えて `apm install` を実行すると、旧い名前の展開先と `apm.lock.yaml` の行は自動で消える（「stale ... cleaned」とログに出る）。

1. `git mv .apm/skills/<旧い名前> .apm/skills/<新しい名前>`
2. 旧い名前を参照している他のスキル・Docs を直す（`rg <旧い名前>` で洗い出す）。
3. `apm install` を実行する。
4. `rg '<旧い名前>' apm.lock.yaml` が何も返さず、`apm audit --ci` が通ることを確かめる。

`apm.lock.yaml` を消して `apm install` で作り直す方法は使わない。作り直すと、既存の展開先が「apm の管理外」として扱われる。

## 要確認

記録すべきか迷った判断と、確かめられなかった事実を箇条書きにする。確かめて決まったら、ADR か該当ページに移し、ここから消す。

- `Docs/` と `Tools/` の中のフォルダ（`accuracy`、`superpowers`、`adr`、`court-annotator`）を大文字のキャメルケースにそろえるか: ADR 0003 は直下と `DemoApp/` の下だけを決めた。
- 前からある Lint の指摘: `swiftlint lint --strict` で 12 件（`BallPlacement.swift` の 5 件など、2026-11-21）、`swiftformat --lint .` で 28 ファイル。直すまでは、増やさないことだけを守る。
- `AGENTS.md`（Codex 向け）: `apm install` では生成されない。Codex は `CLAUDE.md` を読まないので、`CLAUDE.md` のメモが Codex に届かない。
- `Tests/BallAnnotations/frames/` の画像を作り直す道具が無い。今は `frames.json` の動画と秒から手で抜き直す。
- 精度を測るテスト（環境変数で動く 9 ファイル）を、ふつうのテストから別のターゲットに分けるか。
