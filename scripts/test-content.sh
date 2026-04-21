#!/usr/bin/env bash
#
# Hugo 콘텐츠 정합성 검증
#
# 검증 규칙
#   E001  section _index.md 누락
#         → section 디렉토리에 .md 파일은 있는데 _index.md 가 없음
#   E002  leaf page date 누락
#         → 일반 .md (non _index.md) 의 front matter 에 date 필드 없음
#
# 수동 실행 :  bash scripts/test-content.sh
# 자동 실행 :  hooks/pre-commit 에서 호출 (git config core.hooksPath hooks)

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

CONTENT_DIR="content"
section_missing=0
page_missing_date=0
checked_sections=0
checked_pages=0

if [ ! -d "$CONTENT_DIR" ]; then
  echo "[FATAL] '$CONTENT_DIR' 디렉토리를 찾을 수 없습니다." >&2
  exit 2
fi

# ────────────────────────────────────────
# 1) section 디렉토리 검증
# ────────────────────────────────────────
while IFS= read -r -d '' dir; do
  [ "$dir" = "$CONTENT_DIR" ] && continue
  checked_sections=$((checked_sections + 1))

  if [ -f "$dir/_index.md" ]; then
    continue
  fi

  # .md 콘텐츠가 실제로 존재하는 디렉토리만 경고 (빈 폴더는 skip)
  if find "$dir" -maxdepth 1 -type f -name "*.md" | grep -q .; then
    printf "  FAIL  %-55s  %s  %s\n" "$dir" "E001" "section _index.md 누락" >&2
    section_missing=$((section_missing + 1))
  fi
done < <(find "$CONTENT_DIR" -type d -print0)

# ────────────────────────────────────────
# 2) leaf page date front matter 검증
# ────────────────────────────────────────
while IFS= read -r -d '' file; do
  filename=$(basename "$file")
  [ "$filename" = "_index.md" ] && continue
  checked_pages=$((checked_pages + 1))

  # 최상단 30줄 내 date 키 존재 여부 (YAML: `date:`, TOML: `date =`)
  if ! head -30 "$file" | grep -qE '^date[[:space:]]*[:=]'; then
    printf "  FAIL  %-55s  %s  %s\n" "$file" "E002" "leaf page date 누락" >&2
    page_missing_date=$((page_missing_date + 1))
  fi
done < <(find "$CONTENT_DIR" -type f -name "*.md" -print0)

# ────────────────────────────────────────
# 요약
# ────────────────────────────────────────
total=$((section_missing + page_missing_date))

echo ""
echo "════════════════════════════════════════"
echo "  검증 대상 : section ${checked_sections}개 / leaf page ${checked_pages}개"

if [ "$total" -eq 0 ]; then
  echo "  결과      : PASS"
  echo "════════════════════════════════════════"
  exit 0
fi

echo "  결과      : FAIL (총 ${total}건)"
[ "$section_missing" -gt 0 ]   && echo "   · [E001] section _index.md 누락 : ${section_missing}건"
[ "$page_missing_date" -gt 0 ] && echo "   · [E002] leaf page date 누락    : ${page_missing_date}건"
echo "════════════════════════════════════════"

# ────────────────────────────────────────
# 룰별 해결 가이드 (실제 위반이 있는 룰만 출력)
# ────────────────────────────────────────
echo ""
echo "해결 가이드"
echo "────────────────────────────────────────"

if [ "$section_missing" -gt 0 ]; then
  cat >&2 <<'HELP'

[E001] section _index.md 누락
  영향 : 사이드바 메뉴에서 해당 섹션이 누락되거나 linkless 로 표시됩니다.
  해결 : 해당 디렉토리에 _index.md 를 생성하세요.

           ---
           title: "<섹션 이름>"
           weight: 1
           ---
HELP
fi

if [ "$page_missing_date" -gt 0 ]; then
  cat >&2 <<HELP

[E002] leaf page date 누락
  영향 : 페이지 상단 '작성일' 이 파일 수정시간으로 fallback 됩니다.
         이후 파일을 수정할 때마다 '작성일' 도 함께 바뀌어 버립니다.
  해결 : front matter 최상단(---) 바로 아래에 아래 줄을 추가하세요.

           date: $(date +%Y-%m-%d)

         또는 새 글은 archetype 으로 생성하면 자동 삽입됩니다.
           hugo new content/<path>/글이름.md
HELP
fi

echo ""
echo "수정 후 다시 커밋해주세요. (수동 재검증: bash scripts/test-content.sh)"
exit 1
