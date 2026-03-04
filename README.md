# dbmate-migration-lint

dbmate で管理する MySQL マイグレーションファイルの静的解析を行う GitHub Actions Composite Action。
PRレビュー時に破壊的変更や命名規約違反を自動検出し、安全なマイグレーション運用を支援する。

## 使い方

```yaml
# .github/workflows/migration-lint.yml
name: Migration Lint
on:
  pull_request:
    paths:
      - 'db/migrations/**'

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - uses: s11142/dbmate-migration-lint@v1
        with:
          migration-dir: 'db/migrations'  # デフォルト: db/migrations
```

## Inputs

| Name | 説明 | デフォルト |
|------|------|-----------|
| `migration-dir` | マイグレーションファイルのディレクトリパス | `db/migrations` |
| `base-ref` | 比較元の git ref | PRのbase SHA |

## Outputs

| Name | 説明 |
|------|------|
| `violations-count` | 検出された違反の総数 |

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
