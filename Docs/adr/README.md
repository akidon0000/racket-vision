# ADR（設計判断の記録）

- 読み手: racket-vision で作業する人とエージェント
- 目的: 採用・不採用の判断と、その理由を後から辿れるようにする

判断は、理由と一緒に Markdown でリポジトリに残す。今の手順は `.apm/skills/wiki-*` と作業のスキルに、精度の計測の結果は `Docs/accuracy/` に書く（0002）。確定していない判断は書かない。書き方の手順は `write-adr` スキルにある。

## 一覧

この表は、ADR を追加する変更と同じ変更で更新する。

| ID | タイトル | 状態 | 概要 | 本文 |
|----|----------|------|------|------|
| 0001 | Agent Skills は apm で管理し、正本を .apm/skills/ に置く | Accepted | 正本は `.apm/skills/`、展開先は git の外。`CLAUDE.md` は手で書いて git に入れる | [0001-manage-agent-skills-with-apm.md](0001-manage-agent-skills-with-apm.md) |
| 0002 | 判断は Docs/adr/ に、手順は wiki-* と作業のスキルに、計測の結果は Docs/accuracy/ に置く | Accepted | 判断、手順、結果の置き場を分ける。取り込み先のリポジトリの記録のスキルを、このリポジトリに合わせて取り込む | [0002-keep-decisions-in-adr-and-procedures-in-skills.md](0002-keep-decisions-in-adr-and-procedures-in-skills.md) |
| 0003 | 直下と DemoApp/ の下のフォルダは大文字で始まるキャメルケースにし、動画は DemoApp/SamplePlayVideos/ にまとめる | Accepted | `Docs`、`Tools`、`DemoApp/Clips`。動画は `SamplePlayVideos/FullLength`、`SamplePlayVideos/RallyClips` | [0003-name-folders-in-upper-camel-case.md](0003-name-folders-in-upper-camel-case.md) |
| 0004 | アプリと計測に使う動画は、撮った動画の画質のまま入れる | Accepted | 圧縮し直すと手前の 2 人の検出が 77.3% から 67.5% に落ちた。向きのある動画だけ 30 Mbps で回す | [0004-bundle-videos-at-original-quality.md](0004-bundle-videos-at-original-quality.md) |
| 0005 | コートの面の座標（CourtPlane）は CourtFit に置き、デモで映像に重ねる部品は CourtLineOverlay だけにする | Accepted | `PlayerPose` は `CourtFit` に依存する。使われていない 2D の重ね描きを消す | [0005-place-court-plane-in-courtfit.md](0005-place-court-plane-in-courtfit.md) |

### 状態

- **Accepted**: 採用済み。今も有効
- **Superseded**: 後の ADR で置き換えた。内容は履歴として残す

## 配置

```text
Docs/adr/
  README.md              # この一覧と書き方
  TEMPLATE/NNNN-slug.md  # 新しい ADR の雛形
  NNNN-slug.md           # 1 件 1 ファイル
```

- 番号は、既存の最大番号 + 1 にする（4 桁、ゼロ埋め）。`TEMPLATE/` は数えない。
- slug は短い kebab-case の英語にする。
- 本文は日本語だけで書く。

## 書き方

1. `TEMPLATE/NNNN-slug.md` をコピーして書く。
2. Decision → Context → Consideration → Consequences → References の順に書く。
3. Consideration には、必ず現状維持の案を入れる。
4. 一覧の表に行を足す。状態を変えたときは、その行も直す。

既存の決定を覆すときは、新しい ADR の `supersedes` に旧い番号を書く。旧い ADR の `status` を `Superseded` にし、置き換え先へのリンクを References に足す。内容は消さない。
