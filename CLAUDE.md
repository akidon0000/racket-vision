# racket-vision の作業メモ

- 読み手: このリポジトリで作業するエージェント
- 目的: 毎回調べ直していた手順を残す

## デモのアプリを実機（iPhone）に入れる

署名の設定は `project.yml` に書かず、ビルドのコマンドで渡す。`CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Automatic` を付けないと、署名の無いアプリができ、入れるときに `No code signature found` で落ちる。

```bash
cd DemoApp/App && xcodegen generate
xcodebuild -project CourtDemo.xcodeproj -scheme CourtDemo -destination 'generic/platform=iOS' \
  -derivedDataPath <ビルドの置き場> -allowProvisioningUpdates \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=XSC9AJPSP3 build
xcrun devicectl list devices
xcrun devicectl device install app --device <UDID> <ビルドの置き場>/Build/Products/Debug-iphoneos/CourtDemo.app
xcrun devicectl device process launch --terminate-existing --device <UDID> dev.akidon0000.samples.CourtDemo
```

iPhone が `unavailable` のときは、つないでロックを外してもらう。

## デモを Mac で動かす（骨格をその場で検出する）

シミュレーターでは Vision の骨格検出が動かず、記録（`<動画>.players.json`）を出すだけになる。その場の検出を見るなら、Mac で iOS のアプリとして動かす。手順は `Docs/accuracy/pose.md` の「Mac でデモを動かすとき」。

## その他

- 撮った動画の切り出しは `clip-play-videos`、精度の改善は `improve-vision-accuracy` のスキルの手順に従う。
- スキルの正本は `.apm/skills/<名前>/`。直すときはそこを編集し、`apm install`（初回は `make setup`）で `.claude/skills/` などへ展開し直す。展開先は git に入れない。
- シェルの `rm` と `cp` は確認を求める別名になっている。`/bin/rm -f`、`/bin/cp -f` を使う。
