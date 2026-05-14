---
title: "1. ArgoCD 개념"
weight: 1
date: 2026-05-04
---

> ArgoCD 는 **K8s 클러스터의 실제 상태를 git 에 적힌 manifest 와 일치시키는 GitOps continuous delivery 도구**.
> 빌드는 안 한다 — 그건 CI 의 일이다. ArgoCD 의 일은 *git 의 선언* 을 *클러스터의 실제* 로 옮기는 것 단 하나.
> 출처: [Argo CD docs — What Is Argo CD](https://argo-cd.readthedocs.io/en/stable/)
>
> GitOps 자체의 정의·배경·역사 (왜 push 모델에서 pull 로 왔는지) 는 [DevOps/GitOps/1. GitOps — 정의·배경·역사](../GitOps/1_concept.md) 참조. 본 문서는 그 *구체 구현체* 인 ArgoCD 만 다룬다.

---

## 1. ArgoCD 가 하는 일 (한 줄 요약)

공식 정의 인용:
> *"Argo CD is a declarative, GitOps continuous delivery tool for Kubernetes."*
> *"Application definitions, configurations, and environments should be declarative and version controlled."*

→ ArgoCD = **클러스터 안에 사는 컨트롤러**가 git 의 manifest 를 watch 하면서, *클러스터의 실제 상태와 git 의 선언 사이 차이를 reconcile* 하는 도구.

핵심 책임:
- **git 의 manifest 를 K8s 에 apply** (선언 → 실제)
- **drift 감지** (누가 클러스터를 손으로 바꾸면 OutOfSync 표시)
- **self-heal** (선택적) — 손으로 바꾼 변경을 git 기준으로 자동 되돌림
- **상태 시각화** (UI 로 각 Application 의 healthy/synced 표시)
- **rollback** = `git revert`

→ 빌드, 이미지 푸시, 테스트는 **ArgoCD 가 안 한다.** CI 도구 (GitHub Actions, Jenkins, Tekton 등) 의 책임.

---

## 2. Pull-based vs Push-based — ArgoCD 의 본질적 차별점

### 2.1. 두 모델 비교

| 항목 | Push-based (예: CI 가 `kubectl apply`) | Pull-based (ArgoCD) |
|---|---|---|
| 누가 apply 하나 | CI runner (클러스터 외부) | ArgoCD 컨트롤러 (클러스터 내부) |
| 클러스터 자격증명 위치 | CI 시크릿 저장소 | ArgoCD 만 보유 |
| Drift 감지 | 없음 (누가 손으로 바꿔도 모름) | 자동 (주기 reconcile) |
| Rollback | 직전 빌드 다시 돌림 | `git revert` 한 번 |
| 진실의 출처 | CI 로그·이력에 흩어짐 | git 한 곳 |
| Self-heal | 없음 | 손으로 만진 변경 자동 되돌림 (옵션) |
| 외부 시스템 → 클러스터 의존성 | 외부 → 안쪽 (방화벽 뚫어야 함) | 안쪽 → 외부 git (방화벽 친화적) |

### 2.2. 왜 pull-based 인가

> 출처: [OpenGitOps 4 Principles](https://opengitops.dev/) — *"continuously reconciled"* 원칙.

핵심은 **git 이 단일 진실의 출처(SSOT)** 라는 것.
- Push 모델은 *"git → CI → 클러스터"* 의 *순간적 전달*. 클러스터가 그 후 바뀌어도 git 은 모름
- Pull 모델은 *"클러스터가 항상 git 을 보고 자기 상태를 맞춤"* 의 *지속적 일치*

→ 후자가 GitOps 의 정의에 부합. ArgoCD / Flux 가 후자를 구현하는 대표 도구.

---

## 3. CI 와의 역할 분담 — 표준 흐름

```text
[code repo] ── push ──┐
                      ▼
              ┌──────────────┐
              │ CI (Actions, │
              │  Jenkins …)  │
              └──────┬───────┘
                     │ ① 빌드
                     │ ② 이미지 push (도커 레지스트리)
                     │ ③ manifest repo 의 image tag 만 git commit
                     ▼
            [manifest repo (git)]
                     ▲
                     │ pull (주기 또는 webhook)
                     │
              ┌──────┴────────┐
              │ ArgoCD        │  ← 클러스터 안에서 동작
              │ (controller)  │
              └──────┬────────┘
                     │ ④ kubectl apply 와 동등한 reconcile
                     ▼
              [K8s 클러스터]
```

| 단계 | 주체 | 일 |
|---|---|---|
| ① ~ ③ | **CI** | 코드 → 이미지 → manifest 갱신 |
| ④ | **ArgoCD** | manifest → 클러스터 |

→ **두 도구의 권한과 자격이 분리**된다. CI 는 git 만 만지면 끝, 클러스터 자격증명을 모름. 클러스터는 외부 push 를 받지 않음.

---

## 4. ArgoCD 가 *추가로* 사주는 것

CI 에서 `kubectl apply` 만 잘 돌려도 배포 자체는 된다. ArgoCD 를 굳이 도입해 얻는 것:

### 4.1. Drift 감지

> 누가 새벽 3 시에 `kubectl edit deployment ...` 로 replica 수를 바꿨다면?

- Push 모델: 다음 배포 전까지 모름. 다음 배포가 되어야 silently 덮임
- ArgoCD: 즉시 OutOfSync 로 표시. 사람이 인지

### 4.2. Self-heal (옵션)

`syncPolicy.automated.selfHeal: true` 면 손으로 바꾼 변경을 *자동으로 git 기준으로 되돌림*. 운영 disciplines 강제.

### 4.3. Rollback = `git revert`

배포 N+1 이 문제 → 이전 commit 으로 git revert → ArgoCD 가 자동으로 N 상태로 reconcile. 별도 *"이전 빌드 다시 돌리기"* 없음.

### 4.4. 멀티 클러스터 / 멀티 환경

> 출처: [Argo CD — Multiple Clusters](https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/#clusters)

같은 ArgoCD 인스턴스가 여러 클러스터(dev/stage/prod)를 동시에 관리. 환경별 manifest 디렉토리 구조 + ApplicationSet 으로 패턴화.

### 4.5. 권한 / 감사

- ArgoCD 의 RBAC 으로 *"누가 어떤 Application 을 sync 할 수 있는가"* 분리
- 모든 변경의 진짜 이유 = git commit. 추적 단일

---

## 5. 도입 시 자주 헷갈리는 부분

### 5.1. *"git push 하면 알아서 다 되는 거 아닌가요?"*

- code repo 에 push 한다고 ArgoCD 가 직접 보지는 않음 (보통은)
- ArgoCD 는 **manifest repo** 를 본다. CI 가 *"image tag 만 갈아끼우는 commit"* 을 manifest repo 에 만들어 줘야 ArgoCD 가 인지
- 즉 **repo 를 둘로 나누는 게 표준** — code repo 와 manifest repo. (한 repo 에 함께 둘 수도 있지만 권한 분리 어려워짐)

### 5.2. *"그럼 CI 는 뭐가 다른 거? Jenkins 면 다 되는 거 아닌가?"*

- Jenkins 는 *workflow 를 실행하는 도구*. apply 도 시킬 수 있음
- ArgoCD 는 *"git 과 클러스터 일치를 보장하는 컨트롤러"*. 항상 켜져서 reconcile. Jenkins 처럼 *작업이 끝나면 잠드는* 도구가 아님
- 둘은 경쟁 관계가 아니라 *역할 분담*

### 5.3. *"빌드도 ArgoCD 가 했으면 좋겠는데?"*

- 안 함. 그게 GitOps 원칙
- 빌드 = code → artifact (image). 외부 행위. *git 의 선언을 클러스터에 옮기는* 일과 분리되어야 함
- 만약 *"CD 만 ArgoCD 라면 CI 안에 image build 도 들어가는 게 어울리지 않나"* 싶다면 — 그게 정확. CI 와 CD 가 분리되는 게 GitOps 의 전제

### 5.4. *"webhook vs polling, 뭐가 좋아요?"*

- ArgoCD 는 default 3 분 polling. webhook 설정 시 즉시 반영
- Polling 만으로도 운영 가능. webhook 은 반응성 향상용 — *(개인 추론)*

---

## 6. 참고 (출처)

### 1차 출처
- [Argo CD — What Is Argo CD](https://argo-cd.readthedocs.io/en/stable/) — 기본 정의·구조
- [Argo CD — Architectural Overview](https://argo-cd.readthedocs.io/en/stable/operator-manual/architecture/)
- [Argo CD — Declarative Setup](https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/) — Application / ApplicationSet 정의
- [Argo CD — Sync Policies & Self-Heal](https://argo-cd.readthedocs.io/en/stable/user-guide/auto_sync/)

### GitOps 원칙
- [OpenGitOps — Principles](https://opengitops.dev/)
- [gitops.tech — What is GitOps?](https://www.gitops.tech/)

### 본 사이트 내 관련 문서
- [Kafka/실습/1. 설계v1 - GitOps](../../kafka/practice/design_v1_gitops.md) — GitOps 원칙을 Kafka 도입 시 어떻게 적용할지 (ArgoCD 가 그 실현 도구 중 하나)
