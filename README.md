# dbmate-migration-lint

dbmate で管理する MySQL マイグレーションファイルの静的解析ツール。
PRレビュー時に破壊的変更や命名規約違反を自動検出し、安全なマイグレーション運用を支援する。

## CI 設定

`.github/workflows/migration-lint.yml` で PR 時に自動実行される。
`db/migrations/` 配下のファイルが変更された PR に対して lint を実行し、違反があれば PR 上にアノテーションを表示する。

## Lint ルール

### Rule 1: 破壊的変更の検出

`-- migrate:up` セクション内の以下の操作を検出してエラーにする:

- `DROP TABLE`
- `DROP COLUMN`
- `RENAME TABLE`
- `TRUNCATE TABLE`

`-- migrate:down` セクション内では検出しない（ロールバック操作として正常）。

### Rule 2: 照合順序チェック

- `CHARSET` が `utf8mb4` 以外 → エラー
- `COLLATE` が `utf8mb4_0900_ai_ci` 以外 → エラー

### Rule 3: NOT NULL カラム追加チェック

- `ADD COLUMN ... NOT NULL` に `DEFAULT` がない場合 → エラー
- 既存データがあるテーブルでのオンライン DDL 障害を防止

### Rule 4: 命名規約チェック

| 対象 | ルール | 例 |
|------|--------|-----|
| テーブル名 | snake_case (`^[a-z][a-z0-9_]*$`) | `user_profiles` |
| カラム名 | snake_case (`^[a-z][a-z0-9_]*$`) | `created_at` |
| インデックス名 | `idx_` プレフィックス | `idx_users_email` |
| 外部キー名 | `fk_` プレフィックス | `fk_orders_user_id` |

### Rule 5: migrate:down セクション存在チェック

- `-- migrate:down` がファイルに含まれていない場合 → エラー
- ロールバック不可能なマイグレーションを防止

## 対象ファイル

- `git diff` で PR に新規追加（`--diff-filter=A`）されたマイグレーションファイルのみを対象
- dbmate の原則「適用済みマイグレーションは変更しない」に準拠

## ローカルでのテスト

```bash
# テストスイートの実行
bash tests/run_tests.sh

# 単一ファイルの検査
LINT_SINGLE_FILE=path/to/migration.sql bash scripts/lint.sh

# ディレクトリ内の全ファイルを検査
LINT_ALL_FILES=1 MIGRATION_DIR=db/migrations bash scripts/lint.sh
```

## 既知の制限

- 単一行での SQL 文解析のため、複数行にまたがる SQL 文は検出できない場合がある
- `CREATE TABLE` 内のカラム定義（インライン定義）の命名チェックは `ADD COLUMN` のみ対応
- コメント除外は `--` 形式のみ対応（`/* */` 形式のブロックコメントは非対応）
- 正規表現ベースの解析のため、文字列リテラル内の SQL キーワードを誤検知する可能性がある
