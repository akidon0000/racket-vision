---
name: write-adr
description: 採用・不採用、モジュールの境界、外部依存、守るべき規則、再評価の条件を伴う割り切りなど、racket-vision の設計判断を Docs/adr/ に ADR として起草する。「ADRを書いて」「ADR作成」「意思決定を記録して」「この判断を残して」などの依頼や、auto-create-documentation から呼ばれたときに使う。
---

# ADR の起草

設計判断を `Docs/adr/` に 1 件 1 ファイルの ADR として書く。置き場所と一覧は [Docs/adr/README.md](../../../Docs/adr/README.md)、雛形は [Docs/adr/TEMPLATE/NNNN-slug.md](../../../Docs/adr/TEMPLATE/NNNN-slug.md)。

## 範囲

- する: `Docs/adr/NNNN-slug.md` の起草。一覧（`Docs/adr/README.md`）の行の追加と、状態の更新。
- しない: 確定していない判断を書くこと。迷ったものは [auto-create-documentation](../auto-create-documentation/SKILL.md) の手順で「要確認」に送る。コードの実装。PR の作成。
- 精度の計測の結果（数字、外れ方）は ADR にせず、`Docs/accuracy/<対象>.md` に書く（[improve-vision-accuracy](../improve-vision-accuracy/SKILL.md)）。ADR からはそこへのリンクを張る。

## 進め方

### 1. 一次情報を集める

推測で埋めない。コード（件数、行数、依存）、コミット、PR、既存の ADR、`Docs/accuracy/` の記録から集める。確かめられない数字や事実は「（要確認）」と書く。

### 2. 番号と slug を決める

- 番号: `Docs/adr/` の既存の最大番号 + 1（4 桁、ゼロ埋め）。`TEMPLATE/` は数えない。
- slug: 短い kebab-case の英語（例: `place-court-plane-in-courtfit`）。
- ファイル名: `Docs/adr/NNNN-slug.md`。

### 3. 雛形から書く

`Docs/adr/TEMPLATE/NNNN-slug.md` をコピーし、`Docs/adr/NNNN-slug.md` にする。front matter を次のように埋める。

- `title`: 動詞で終わる決定の文（目安は 20〜60 字）
- `status`: `Accepted`
- `proposed` と `accepted`: 起草した日（YYYY-MM-DD）
- `supersedes`: 置き換える ADR の番号。なければ空

### 4. 5 つのセクションを書く

1. **Decision**: 結論を太字で先に書き、比較の要約を続ける。
2. **Context**: 背景と課題。数字が取れれば入れる。
3. **Consideration**: 比較表。現状維持を必ず含める。記号だけのセルにしない。
4. **Consequences**: 期待される効果、リスクと対策。
5. **References**: コミット、PR、関連する ADR、`Docs/accuracy/` の記録、外部リンク。コードを指すときは、コミットの SHA で固定した GitHub のリンクにする。

本文は常体で書く（「〜である」「〜する」）。英語版は作らない。
文は、採用した内容と理由を肯定の形で書く。選ばなかった案との比較は Consideration の表に書く。禁止の決まりは禁止のまま書く。

### 5. 一覧を更新する

`Docs/adr/README.md` の表に行を足す。既存の決定を置き換えるときは、旧い ADR の `status` を `Superseded` にし、置き換え先へのリンクを References に足す。内容は消さない。

### 6. チェックする

- [ ] `Docs/adr/NNNN-slug.md` があり、番号が既存の最大 + 1 になっている
- [ ] Decision だけで、何を決めたかが分かる
- [ ] Consideration に現状維持の案がある
- [ ] 「適切に」「なるべく」などの曖昧な語を、具体的な語に直した
- [ ] 一覧の表に行がある
- [ ] 本文が常体で、英語版を作っていない

## 制約

- 会話に出ただけの案を、確定した決定として書かない。
- コードから分かる細かい情報や、変更履歴そのものを複製しない。
- 旧い決定を覆すときは、内容を消さず、後の ADR で置き換える。
