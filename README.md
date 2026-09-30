# めんどログ

日常の小さな摩擦を3秒で記録し、繰り返す不便を見つけて改善するローカル完結の Flutter Android アプリ。

## 機能（MVP 完了）

- 「探した」「忘れた」「やり直した」「待った」「面倒だった」「その他」の高速入力
- 最近使った対象の再利用
- 同一カテゴリ × 同一対象の直近30日集計
- 3回以上で改善候補を表示
- 「探した」×「爪切り」には「定位置を決める」を提案
- 改善の詳細メモ・開始日を保存し、改善前後30日の発生回数を比較（改善ループ）
- 改善を完了/中止した時点の比較件数は集計スナップショットとして保存し、その後に元の履歴を削除しても確定済みの結果は変えない（削除した元イベント自体は保持しない）
- 表記揺れ（つめきり / 爪きり / ネイルクリッパー）を「爪切り」に集約
- データは端末内の SharedPreferences へ JSON で保存（ネットワーク・AI なし）

## 開発状況

- MVP 機能一通り完成（2026-08-10 時点）
- リリース準備: applicationId `com.mendolog.mendolog`・アプリ名「めんどログ」・
  アイコン（Android 全密度 + adaptive）・CI（analyze/test/APK）・署名配線は完了
- リリース手順は [docs/RELEASE.md](docs/RELEASE.md) 参照

## 確認方法

```text
flutter analyze
flutter test
flutter build apk --debug
git diff --check
```

`integration_test/` に実機フローを用意しています。実機または Android エミュレーター未接続の環境では、
integration_test の実行結果は未確認です。

## 構成

- `lib/main.dart` — UI（入力タブ・改善タブ）
- `lib/domain.dart` — ドメインモデル（カテゴリ・イベント・改善・集計）
- `lib/storage.dart` — SharedPreferences 永続化
- `test/` — 単体・ウィジェットテスト
- `integration_test/` — 実機フロー