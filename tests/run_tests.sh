#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# dbmate-migration-lint テストランナー
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LINT_SCRIPT="$PROJECT_DIR/scripts/lint.sh"
FIXTURES_DIR="$SCRIPT_DIR/fixtures"

PASSED=0
FAILED=0
TOTAL=0

# (( expr )) returns exit code 1 when result is 0, which conflicts with set -e.
# Use arithmetic assignment instead.
inc_total()  { TOTAL=$((TOTAL + 1)); }
inc_passed() { PASSED=$((PASSED + 1)); }
inc_failed() { FAILED=$((FAILED + 1)); }

# ---------------------------------------------------------------------------
# テストヘルパー
# ---------------------------------------------------------------------------

# 正常系テスト: lint がパスすることを期待
expect_pass() {
  local name="$1"
  local file="$2"
  inc_total

  local output
  if output=$(LINT_SINGLE_FILE="$file" bash "$LINT_SCRIPT" 2>&1); then
    echo "  PASS: ${name}"
    inc_passed
  else
    echo "  FAIL: ${name} (expected pass, but lint reported errors)"
    echo "    Output: ${output}" | head -20
    inc_failed
  fi
}

# 異常系テスト: lint がエラーを報告することを期待
# 第3引数: 期待するエラーキーワード（オプション）
expect_fail() {
  local name="$1"
  local file="$2"
  local expected_pattern="${3:-}"
  inc_total

  local output
  if output=$(LINT_SINGLE_FILE="$file" bash "$LINT_SCRIPT" 2>&1); then
    echo "  FAIL: ${name} (expected errors, but lint passed)"
    inc_failed
  else
    if [ -n "$expected_pattern" ]; then
      if echo "$output" | grep -qF "$expected_pattern"; then
        echo "  PASS: ${name}"
        inc_passed
      else
        echo "  FAIL: ${name} (error reported but pattern '${expected_pattern}' not found)"
        echo "    Output: ${output}" | head -20
        inc_failed
      fi
    else
      echo "  PASS: ${name}"
      inc_passed
    fi
  fi
}

# ---------------------------------------------------------------------------
# テストケース
# ---------------------------------------------------------------------------

echo "========================================"
echo " dbmate-migration-lint tests"
echo "========================================"
echo ""

echo "[Valid fixtures - should pass]"
expect_pass "create table with proper conventions" "$FIXTURES_DIR/valid/001_create_users.sql"
expect_pass "add column with default" "$FIXTURES_DIR/valid/002_add_column_with_default.sql"
expect_pass "add foreign key with fk_ prefix" "$FIXTURES_DIR/valid/003_add_foreign_key.sql"

echo ""
echo "[Rule 1: Destructive changes]"
expect_fail "DROP TABLE in migrate:up" "$FIXTURES_DIR/invalid/001_drop_table.sql" "[DESTRUCTIVE] DROP TABLE"
expect_fail "DROP COLUMN in migrate:up" "$FIXTURES_DIR/invalid/002_drop_column.sql" "[DESTRUCTIVE] DROP COLUMN"
expect_fail "RENAME TABLE in migrate:up" "$FIXTURES_DIR/invalid/003_rename_table.sql" "[DESTRUCTIVE] RENAME TABLE"
expect_fail "TRUNCATE TABLE in migrate:up" "$FIXTURES_DIR/invalid/004_truncate_table.sql" "[DESTRUCTIVE] TRUNCATE TABLE"

echo ""
echo "[Rule 2: Charset/Collation]"
expect_fail "bad charset and collation" "$FIXTURES_DIR/invalid/005_bad_charset.sql" "[CHARSET]"

echo ""
echo "[Rule 3: NOT NULL without DEFAULT]"
expect_fail "ADD COLUMN NOT NULL without DEFAULT" "$FIXTURES_DIR/invalid/006_not_null_no_default.sql" "[NOT_NULL]"

echo ""
echo "[Rule 4: Naming conventions]"
expect_fail "bad table name (PascalCase)" "$FIXTURES_DIR/invalid/007_bad_table_name.sql" "[NAMING] Table name"
expect_fail "bad index name (no idx_ prefix)" "$FIXTURES_DIR/invalid/008_bad_index_name.sql" "[NAMING] Index name"
expect_fail "bad foreign key name (no fk_ prefix)" "$FIXTURES_DIR/invalid/009_bad_fk_name.sql" "[NAMING] Foreign key name"
expect_fail "bad column name (camelCase)" "$FIXTURES_DIR/invalid/011_bad_column_name.sql" "[NAMING] Column name"

echo ""
echo "[Rule 5: migrate:down existence]"
expect_fail "missing migrate:down" "$FIXTURES_DIR/invalid/010_no_migrate_down.sql" "[MIGRATE_DOWN]"

echo ""
echo "========================================"
echo " Results: ${PASSED}/${TOTAL} passed, ${FAILED} failed"
echo "========================================"

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
