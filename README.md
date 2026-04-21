# San Kim의 위키

[Hugo Book](https://github.com/alex-shpak/hugo-book) 테마를 Claude 상아색 톤으로
커스터마이징한 개인 위키. GitHub Actions 로 `main` 브랜치 push 시 자동 배포.

- 공개 URL: https://kimtks456.github.io/
- 빌드: GitHub Actions (`.github/workflows/hugo.yml`)
- 시간대: KST (Asia/Seoul)

---

## 1. 요구사항

| 도구 | 최소 버전 | 비고 |
|---|---|---|
| Hugo **extended** | 0.158.0 | 테마 요구사항. `hugo version` 으로 확인 |
| Git | 최신 권장 | 테마가 submodule 로 관리됨 |

macOS 설치 예: `brew install hugo`

---

## 2. 개발 환경 세팅

처음 clone 하거나 다른 기기에서 pull 받은 직후 **반드시 아래 순서대로**.

### 2.1. 저장소 clone (submodule 포함)

```bash
git clone --recurse-submodules https://github.com/kimtks456/kimtks456.github.io.git
cd kimtks456.github.io
```

이미 clone 해버려 테마가 비어있다면:

```bash
git submodule update --init --recursive
```

### 2.2. pre-commit hook 활성화 (로컬 1회)

```bash
git config core.hooksPath hooks
```

> git 의 `core.hooksPath` 는 로컬 설정이라 push 로 공유되지 않습니다.
> 새 기기에서 pull 받으면 이 명령을 한 번 더 실행해야 합니다.

### 2.3. 로컬 서버 실행

```bash
hugo server
```

http://localhost:1313/ 에서 확인. 파일 변경 시 hot reload.

설정을 바꿨거나 빌드가 꼬이면:
```bash
rm -rf resources public .hugo_build.lock
hugo server
```

---

## 3. 문서 작성 규칙

### 3.1. 디렉토리 구조

```
content/
  _index.md                 # 홈 페이지
  docs/
    <섹션>/
      _index.md             # 섹션 루트 (메뉴에 표시)
      <하위섹션>/
        _index.md           # 하위 섹션
        <글이름>.md         # 실제 글 (leaf page)
```

규칙 요약:
- **섹션 (디렉토리)** 에는 반드시 `_index.md` 가 있어야 메뉴에 제대로 표시됩니다.
- **일반 글 (leaf page)** 은 `_index.md` 가 아닌 `.md` 파일.
- `_index.md` 는 `cascade` 로 하위 파일에 front matter 상속 가능.

### 3.2. front matter 필수/권장 항목

#### 3.2.1. 섹션 `_index.md`

```yaml
---
title: "섹션 이름"
weight: 1
---
```

#### 3.2.2. 일반 글 (leaf page)

```yaml
---
title: "카프카 환경 설정 가이드"
date: 2026-04-21          # 필수 — 작성일 (한 번 정하면 고정)
weight: 1
---
```

- `date` 는 **필수**. 없으면 pre-commit 에서 E002 로 실패.
- `lastmod` 는 **적지 않습니다** — git commit 시간이나 파일 수정시간으로 자동 추적됨.
- 날짜 포맷: `YYYY-MM-DD` 만 적어도 충분.

### 3.3. 새 글 만들기

두 가지 방법. 결과는 동일.

**A. 터미널 (권장, date 자동 삽입)**

```bash
hugo new content/docs/<섹션>/<하위섹션>/글이름.md
```

archetypes/docs.md 템플릿이 적용되어 `date` 가 자동으로 박힙니다.

**B. IDE 에서 수동 생성**

파일을 직접 만들 때는 상단 front matter 의 `date` 를 **직접 입력**해야 합니다.

### 3.4. 섹션 기본 동작

- 모든 섹션은 사이드바에서 접혀있다가 클릭 시 펼쳐집니다 (`hugo.toml` 의 `[[cascade]] bookCollapseSection`).
- leaf page 에는 toggle 이 안 보이게 `layouts/_partials/docs/menu-filetree.html` 에서 override.
- 특정 페이지를 숨기려면 front matter 에 `bookHidden: true`.
- 특정 페이지의 작성일/수정일 메타 블록을 숨기려면 `bookHideMeta: true`.

---

## 4. 콘텐츠 검증 (pre-commit hook)

### 4.1. 목적

Hugo 서버를 띄워 일일이 확인하지 않아도 커밋 전에 **구조/front matter 정합성**을 자동으로 잡아줍니다.

### 4.2. 검증 룰

| 코드 | 설명 | 영향 |
|---|---|---|
| **E001** | section 디렉토리에 `_index.md` 가 없음 | 사이드바에서 섹션이 linkless 로 표시되거나 누락 |
| **E002** | leaf page front matter 에 `date` 가 없음 | 페이지 상단 '작성일' 이 파일 수정시간으로 fallback 되어 수정할 때마다 바뀜 |

### 4.3. 수동 실행

```bash
bash scripts/test-content.sh
```

### 4.4. 자동 실행

hook 활성화 (`git config core.hooksPath hooks`) 후에는 매 `git commit` 마다 자동 실행.
위반 발견 시 커밋이 중단되고 해결 가이드가 출력됩니다.

### 4.5. 출력 예시

```
  FAIL  content/docs/Kafka/개념/새글.md             E002  leaf page date 누락

════════════════════════════════════════
  검증 대상 : section 4개 / leaf page 2개
  결과      : FAIL (총 1건)
   · [E002] leaf page date 누락    : 1건
════════════════════════════════════════

[E002] leaf page date 누락
  영향 : ...
  해결 : front matter 최상단(---) 바로 아래에 아래 줄을 추가하세요.
           date: 2026-04-21
```

---

## 5. 배포

`main` 브랜치로 push 하면 GitHub Actions (`.github/workflows/hugo.yml`) 가 자동으로 빌드·배포합니다.

- Hugo 버전: 0.160.1 (workflow 에 고정)
- 타임존: `TZ=Asia/Seoul`
- submodule recursive 체크아웃으로 테마 자동 동기화

별도의 수동 배포는 불필요. Actions 탭에서 진행 상황 확인 가능.

---

## 6. 커스터마이징 참고

Claude Code 의 따뜻한 상아색 + 코럴 오렌지 톤으로 테마를 재색칠했습니다.

| 파일 | 역할 |
|---|---|
| `assets/_custom.scss` | 색상/폰트/스타일 오버라이드 (테마 SCSS partial 대체) |
| `layouts/_partials/docs/menu-filetree.html` | leaf page 에서 chevron toggle 안 뜨도록 override |
| `layouts/_partials/docs/inject/content-before.html` | 페이지 상단에 작성일/최종 수정일시 블록 삽입 |
| `archetypes/docs.md` | `hugo new` 로 글 생성 시 `date` 자동 삽입 |
| `hugo.toml` | `timeZone`, `enableGitInfo`, `[frontmatter]`, `[[cascade]]` |

팔레트:
- 본문 배경: `#F9F8F6` (상아색)
- 사이드/코드블록 배경: `#F3F1ED`
- 링크/악센트: `#C15F3C` (클로드 코럴)
- 본문 글자: `#2B2B28`

---

## 7. 디렉토리 레이아웃

```
kimtks456.github.io/
├── .github/workflows/hugo.yml     # CI/CD
├── archetypes/                    # hugo new 템플릿
├── assets/_custom.scss            # 커스텀 스타일
├── content/                       # 문서 소스
│   ├── _index.md                  #   홈
│   └── docs/                      #   본문
├── hooks/pre-commit               # git pre-commit (scripts 호출만)
├── layouts/                       # 테마 override
├── scripts/test-content.sh        # 콘텐츠 검증 스크립트
├── static/                        # 정적 파일 (favicon 등)
├── themes/hugo-book/              # 테마 (git submodule)
└── hugo.toml                      # Hugo 설정
```
