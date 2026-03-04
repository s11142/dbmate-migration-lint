#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# dbmate-migration-lint
# dbmate マイグレーションファイルの静的解析スクリプト
# =============================================================================

MIGRATION_DIR="${MIGRATION_DIR:-db/migrations}"

# 違反カウント用の一時ファイル（サブシェルからもカウント可能にする）
VIOLATIONS_FILE=$(mktemp)
echo "0" > "$VIOLATIONS_FILE"
trap 'rm -f "$VIOLATIONS_FILE"' EXIT

# ---------------------------------------------------------------------------
# ユーティリティ関数
# ---------------------------------------------------------------------------

report_error() {
  local file="$1"
  local line="$2"
  local message="$3"
  echo "::error file=${file},line=${line}::${message}"
  local count
  count=$(cat "$VIOLATIONS_FILE")
  echo $((count + 1)) > "$VIOLATIONS_FILE"
}

get_violations() {
  cat "$VIOLATIONS_FILE"
}

# migrate:up セクションを抽出（行番号:内容 の形式）
# SQLコメント行（-- で始まる行）は除外
extract_up_section() {
  local file="$1"
  awk '/^-- migrate:up/{in_up=1;next} /^-- migrate:down/{in_up=0} in_up{print NR":"$0}' "$file" \
    | grep -v '^[0-9]*:[[:space:]]*--' || true
}

# ---------------------------------------------------------------------------
# Rule 1: 破壊的変更の検出
# ---------------------------------------------------------------------------
rule_destructive_changes() {
  local file="$1"
  local up_section="$2"

  local line_num content
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    line_num="${line%%:*}"
    content="${line#*:}"
    if echo "$content" | grep -qiE '\bDROP[[:space:]]+TABLE\b'; then
      report_error "$file" "$line_num" "[DESTRUCTIVE] DROP TABLE detected in migrate:up section"
    fi
    if echo "$content" | grep -qiE '\bDROP[[:space:]]+COLUMN\b'; then
      report_error "$file" "$line_num" "[DESTRUCTIVE] DROP COLUMN detected in migrate:up section"
    fi
    if echo "$content" | grep -qiE '\bRENAME[[:space:]]+TABLE\b'; then
      report_error "$file" "$line_num" "[DESTRUCTIVE] RENAME TABLE detected in migrate:up section"
    fi
    if echo "$content" | grep -qiE '\bTRUNCATE[[:space:]]+TABLE\b'; then
      report_error "$file" "$line_num" "[DESTRUCTIVE] TRUNCATE TABLE detected in migrate:up section"
    fi
  done <<< "$up_section"
}

# ---------------------------------------------------------------------------
# Rule 2: 照合順序チェック
# ---------------------------------------------------------------------------
rule_charset_collation() {
  local file="$1"
  local up_section="$2"

  local line_num content
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    line_num="${line%%:*}"
    content="${line#*:}"
    if echo "$content" | grep -qiE '(CHARSET|CHARACTER[[:space:]]+SET)[[:space:]]*=?[[:space:]]*[a-z]'; then
      if ! echo "$content" | grep -qiE '(CHARSET|CHARACTER[[:space:]]+SET)[[:space:]]*=?[[:space:]]*utf8mb4\b'; then
        report_error "$file" "$line_num" "[CHARSET] charset must be utf8mb4"
      fi
    fi
    if echo "$content" | grep -qiE 'COLLATE[[:space:]]*=?[[:space:]]*[a-z]'; then
      if ! echo "$content" | grep -qiE 'COLLATE[[:space:]]*=?[[:space:]]*utf8mb4_0900_ai_ci\b'; then
        report_error "$file" "$line_num" "[COLLATE] collation must be utf8mb4_0900_ai_ci"
      fi
    fi
  done <<< "$up_section"
}

# ---------------------------------------------------------------------------
# Rule 3: NOT NULL カラム追加チェック
# ---------------------------------------------------------------------------
rule_not_null_default() {
  local file="$1"
  local up_section="$2"

  local line_num content
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    line_num="${line%%:*}"
    content="${line#*:}"
    if echo "$content" | grep -qiE '\bADD[[:space:]]+COLUMN\b.*\bNOT[[:space:]]+NULL\b'; then
      if ! echo "$content" | grep -qiE '\bDEFAULT\b'; then
        report_error "$file" "$line_num" "[NOT_NULL] ADD COLUMN with NOT NULL must have a DEFAULT value"
      fi
    fi
  done <<< "$up_section"
}

# ---------------------------------------------------------------------------
# Rule 4: 命名規約チェック
# ---------------------------------------------------------------------------
rule_naming_conventions() {
  local file="$1"
  local up_section="$2"

  local line_num content
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    line_num="${line%%:*}"
    content="${line#*:}"

    # CREATE TABLE テーブル名チェック
    if echo "$content" | grep -qiE '\bCREATE[[:space:]]+TABLE\b'; then
      local table_name
      table_name=$(echo "$content" | sed -nE 's/.*CREATE[[:space:]]+TABLE[[:space:]]+(IF[[:space:]]+NOT[[:space:]]+EXISTS[[:space:]]+)?`?([a-zA-Z0-9_]+)`?.*/\2/Ip')
      if [ -n "$table_name" ] && ! echo "$table_name" | grep -qE '^[a-z][a-z0-9_]*$'; then
        report_error "$file" "$line_num" "[NAMING] Table name '${table_name}' must be snake_case"
      fi
    fi

    # ADD COLUMN カラム名チェック
    if echo "$content" | grep -qiE '\bADD[[:space:]]+COLUMN\b'; then
      local col_name
      col_name=$(echo "$content" | sed -nE 's/.*ADD[[:space:]]+COLUMN[[:space:]]+`?([a-zA-Z0-9_]+)`?.*/\1/Ip')
      if [ -n "$col_name" ] && ! echo "$col_name" | grep -qE '^[a-z][a-z0-9_]*$'; then
        report_error "$file" "$line_num" "[NAMING] Column name '${col_name}' must be snake_case"
      fi
    fi

    # インデックス名チェック
    if echo "$content" | grep -qiE '\b(CREATE|ADD)[[:space:]]+(UNIQUE[[:space:]]+)?INDEX\b'; then
      local idx_name
      idx_name=$(echo "$content" | sed -nE 's/.*INDEX[[:space:]]+`?([a-zA-Z0-9_]+)`?.*/\1/Ip')
      if [ -n "$idx_name" ] && ! echo "$idx_name" | grep -qE '^idx_[a-z][a-z0-9_]*$'; then
        report_error "$file" "$line_num" "[NAMING] Index name '${idx_name}' must start with 'idx_' prefix and be snake_case"
      fi
    fi

    # 外部キー名チェック
    if echo "$content" | grep -qiE '\bADD[[:space:]]+CONSTRAINT\b.*\bFOREIGN[[:space:]]+KEY\b'; then
      local fk_name
      fk_name=$(echo "$content" | sed -nE 's/.*ADD[[:space:]]+CONSTRAINT[[:space:]]+`?([a-zA-Z0-9_]+)`?.*/\1/Ip')
      if [ -n "$fk_name" ] && ! echo "$fk_name" | grep -qE '^fk_[a-z][a-z0-9_]*$'; then
        report_error "$file" "$line_num" "[NAMING] Foreign key name '${fk_name}' must start with 'fk_' prefix and be snake_case"
      fi
    fi
  done <<< "$up_section"
}

# ---------------------------------------------------------------------------
# Rule 5: migrate:down セクション存在チェック
# ---------------------------------------------------------------------------
rule_migrate_down_exists() {
  local file="$1"
  if ! grep -q '^-- migrate:down' "$file"; then
    report_error "$file" "1" "[MIGRATE_DOWN] '-- migrate:down' section is missing. Rollback must be possible."
  fi
}

# ---------------------------------------------------------------------------
# 対象ファイルの取得
# ---------------------------------------------------------------------------
get_target_files() {
  if [ -n "${LINT_SINGLE_FILE:-}" ]; then
    if [ -f "$LINT_SINGLE_FILE" ]; then
      echo "$LINT_SINGLE_FILE"
    fi
    return
  fi

  if [ "${LINT_ALL_FILES:-}" = "1" ]; then
    find "$MIGRATION_DIR" -name '*.sql' -type f 2>/dev/null | sort
    return
  fi

  local base_ref="${BASE_REF:-}"
  if [ -z "$base_ref" ]; then
    echo "::warning::BASE_REF is not set. Scanning all migration files." >&2
    find "$MIGRATION_DIR" -name '*.sql' -type f 2>/dev/null | sort
    return
  fi

  git diff --name-only --diff-filter=A "${base_ref}...HEAD" -- "$MIGRATION_DIR" 2>/dev/null \
    | grep '\.sql$' || true
}

# ---------------------------------------------------------------------------
# メイン処理
# ---------------------------------------------------------------------------
main() {
  local files
  files=$(get_target_files)

  if [ -z "$files" ]; then
    echo "No migration files to lint."
    echo "violations-count=0" >> "${GITHUB_OUTPUT:-/dev/null}"
    exit 0
  fi

  echo "Linting migration files..."
  echo "---"

  while IFS= read -r file; do
    [ -z "$file" ] && continue
    [ ! -f "$file" ] && continue

    echo "Checking: ${file}"

    rule_migrate_down_exists "$file"

    local up_section
    up_section=$(extract_up_section "$file")

    if [ -z "$up_section" ]; then
      continue
    fi

    rule_destructive_changes "$file" "$up_section"
    rule_charset_collation "$file" "$up_section"
    rule_not_null_default "$file" "$up_section"
    rule_naming_conventions "$file" "$up_section"

  done <<< "$files"

  local total
  total=$(get_violations)

  echo "---"
  echo "Lint complete. Violations: ${total}"

  echo "violations-count=${total}" >> "${GITHUB_OUTPUT:-/dev/null}"

  if [ "$total" -gt 0 ]; then
    exit 1
  fi
}

main
