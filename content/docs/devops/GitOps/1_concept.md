---
title: "1. GitOps — 정의·배경·역사"
weight: 1
date: 2026-05-04
---

> GitOps 는 *"인프라/애플리케이션의 desired state 를 git 에 선언하고, 클러스터 안의 에이전트가 git 을 pull 해서 actual state 를 지속적으로 일치시키는"* 운영 방식.
> 본 문서는 GitOps 의 정의·해결하려는 문제, 그리고 *어떻게 여기까지 왔는지* 의 흐름을 정리한다.
> 출처: [gitops.tech](https://www.gitops.tech/), [OpenGitOps Principles](https://opengitops.dev/)

---

## 1. 정의 (gitops.tech 인용)

> *"GitOps is a way of implementing Continuous Deployment for cloud native applications. ... using Git as a single source of truth for declarative infrastructure and applications, together with tools ensuring the actual state of infrastructure and applications converges towards the desired state declared in Git."*

OpenGitOps 4 원칙:
1. **Declarative** — 시스템 상태를 *선언* (절차가 아니라 결과)
2. **Versioned and Immutable** — desired state 는 git 에 불변 이력으로 보관
3. **Pulled Automatically** — 에이전트가 git 을 *pull* (외부 push 가 아님)
4. **Continuously Reconciled** — actual state ≠ desired state 시 자동 수렴

---

## 2. 어떻게 여기까지 왔나 — 운영의 진화

### 2.1. 1세대: 수동 SSH + 위키 문서

```text
운영자 ──ssh──▶ 서버에서 직접 명령 / 설정 파일 수정
```

- 진실의 출처 = *운영자의 머리* + 위키 문서 (보통 어긋남)
- 문제:
  - 누가·언제·왜 바꿨는지 추적 불가
  - 환경 재현 불가 (서버가 죽으면 똑같이 못 만듦)
  - 사람 실수 즉시 prd 반영
  - dev / prd 가 점점 달라짐 (drift)

### 2.2. 2세대: 스크립트·구성관리 도구 (Bash, Ansible, Chef, Puppet)

```text
운영자 ──실행──▶ Ansible playbook ──ssh──▶ 서버
```

- 운영 절차를 *코드* 로 표현 → 재현성 ↑
- 한계:
  - 스크립트 *실행 자체* 는 여전히 사람·CI 가 push
  - "지금 prd 에 어떤 버전이 적용돼 있나" 의 답이 *마지막 실행 로그* 에 흩어짐
  - 누가 손으로 만지면 다음 실행이 덮을 때까지 drift

### 2.3. 3세대: CI/CD 파이프라인 (Jenkins, GitLab CI, **AWS CodeBuild/CodeDeploy**, GitHub Actions)

```text
[git push] ──▶ [CI] 빌드/테스트/이미지화 ──▶ [CD] kubectl apply / SSH 배포 ──▶ [서버·클러스터]
                                                  ▲
                                                  │ "Push" 모델
```

- *코드* 의 버전 관리는 git 으로 잘됨
- 빌드·테스트·배포가 자동화됨
- AWS CodeBuild / CodePipeline / CodeDeploy 가 이 세대의 대표 — git → 빌드 → 클러스터로 push
- 한계 (**push 모델의 본질적 약점**):
  - **클러스터 자격증명을 CI 가 들고 있어야 함** → 외부 시크릿 노출 위험
  - **클러스터 상태 ≠ git 상태** — 코드는 git 에 있지만 *클러스터의 실제 상태* 는 다를 수 있음
  - **drift 감지 없음** — 누가 `kubectl edit` 으로 손대도 다음 배포까지 모름
  - **rollback = "이전 빌드 다시 돌리기"** — 클러스터 상태 자체의 시간선이 아님
  - **dev / prd 비교가 어렵다** — *코드는 같은데 실제 상태는 다른* 상황이 가능

### 2.4. 3.5세대: Infrastructure as Code (Terraform, CloudFormation)

- 인프라까지 *코드* 로 — git 추적 범위가 인프라까지 확장
- 그러나 *적용* 은 여전히 사람 또는 CI 가 `terraform apply` 를 *실행*
- "적용 후 콘솔에서 손으로 바꾼 변경" 은 다음 plan 에서 drift 로 보이긴 하지만 *자동 교정* 은 안 함

### 2.5. 4세대: GitOps (Argo CD, Flux)

```text
[git push] ──▶ [manifest repo (git)] ◀──pull── [에이전트 (in-cluster)]
                                                       │
                                                       ▼
                                                   [클러스터]
                                                   (지속 reconcile)
```

#### 용어: manifest

> 영어 단어 *manifest* = *"명백히 드러낸 것 / 명세서"*. 화물선의 manifest 가 *"이 배에 실린 짐 목록"* 인 것처럼, K8s manifest 는 *"이 클러스터에 두고 싶은 리소스 목록"*.

K8s 에서 **manifest** = *"이 리소스를 이렇게 만들어줘"* 라고 적은 **선언형 YAML(또는 JSON) 파일**.

예시 — Deployment manifest:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
        - name: nginx
          image: nginx:1.27
```

→ `kubectl apply -f nginx.yaml` 하면 K8s 가 *"nginx 컨테이너 3개 떠 있어야 한다"* 는 선언을 받아 실제로 띄움. 한 개 죽으면 알아서 새로 띄워 3개 유지.

핵심 특징:
- **선언형 (declarative)**: *"3개 띄워라"* (절차) 가 아니라 *"3개 떠 있어야 한다"* (결과)
- **불변·이력관리 가능**: 그냥 텍스트 파일이라 git 에 그대로 commit
- **kind 별로 종류 다양**: Deployment, Service, ConfigMap, Secret, Ingress, Kafka(Strimzi), KafkaTopic, Application(ArgoCD) ...

→ "**manifest repo**" = 이 YAML 파일들을 잔뜩 모아둔 git 리포. 위 다이어그램의 `manifest repo (git)` 가 이것. ArgoCD/Flux 가 이 repo 를 watch 하면서 *"여기 적힌 대로 클러스터를 만들어"* 를 지속 reconcile.

#### GitOps 4세대의 특징

- 클러스터 *안* 에 사는 에이전트가 git 을 *pull* 해 자기 상태를 맞춤
- 외부에서 push 안 함 → 자격증명 클러스터 안에만 존재
- *git = 진실의 출처* 가 코드뿐 아니라 **클러스터 상태 그 자체** 까지 확장
- drift 자동 감지·교정 (옵션: self-heal)
- rollback = `git revert` 한 줄

---

## 3. GitOps 가 해결하는 문제 — 한 줄로

| 문제 (이전 세대) | GitOps 의 해결 |
|---|---|
| 클러스터 자격증명을 CI 가 들고 외부 push | 에이전트만 보유. CI 는 git 만 만짐 |
| 클러스터에서 누가 손으로 만져도 모름 | 자동 reconcile / OutOfSync 표시 |
| dev / prd 차이가 *명시적이지 않음* | 환경별 git 디렉토리 = 명시적 desired state |
| Rollback 이 빌드 재실행 | `git revert` |
| 변경 추적이 CI 로그·티켓·SSH 기록에 흩어짐 | git history 한 곳 |
| 진실의 출처가 *마지막 누군가의 행위* | git (선언적·불변) |

---

## 4. 그래서 왜 *이 흐름* 으로 왔나

| 전환 | 얻은 것 |
|---|---|
| 1세대 → 2세대 | **재현성** (스크립트화) |
| 2세대 → 3세대 | **자동화** (CI/CD push) |
| 3세대 → 4세대 | **클러스터 상태와 git 의 일치** (Pull + 지속 reconcile) |

각 세대는 *이전 세대의 약점* 을 메우려 등장. GitOps 의 등장 동기는 push 모델이 못 풀던 *"클러스터 실제 상태가 git 에서 벗어나는 것"* 을 구조적으로 막는 것.

---

## 5. 한계·주의 (정직하게)

- **빌드는 여전히 CI 의 일** — GitOps 만으로 코드 → 이미지가 되지 않는다. CI + GitOps 의 *역할 분담* 이 전제
- **클러스터 외부 자원** (RDS, S3, IAM 등) 은 GitOps 범위 밖이거나 별도 통합(Crossplane, Terraform Operator) 필요
- **secrets 관리** 는 기본 GitOps 범위 밖 — Sealed Secrets, SOPS, External Secrets 같은 보조 도구 필요
- **학습 곡선 + 도구 추가 운영 부담** — Argo CD/Flux 자체가 운영 대상

---

## 6. 대표 도구

| 도구 | 한 줄 |
|---|---|
| **Argo CD** | UI 강함. multi-cluster. CNCF Graduated. 자세히는 [DevOps/ArgoCD/1. ArgoCD 개념](../ArgoCD/1_concept.md) |
| **Flux** | CLI 친화. GitOps Toolkit (구성요소 분리). CNCF Graduated |
| **Jenkins X** | Jenkins 기반 GitOps 시도. 채택 적은 편 *(개인 추론)* |

---

## 7. 참고 (출처)

- [gitops.tech — official definition](https://www.gitops.tech/)
- [OpenGitOps — Principles](https://opengitops.dev/)
- [Argo CD docs](https://argo-cd.readthedocs.io/en/stable/)
- [Flux docs](https://fluxcd.io/)
- [Weaveworks — GitOps: What you need to know](https://www.weave.works/technologies/gitops/) — GitOps 용어를 처음 제시한 회사 *(추론 — 직접 검증 권장)*

### 본 사이트 내 관련 문서

- [DevOps/ArgoCD/1. ArgoCD 개념](../ArgoCD/1_concept.md) — Pull 모델의 구체 구현체
- [Kafka/실습/2. GitOps 기반 설계](../../Kafka/practice/2_gitops_design.md) — GitOps 를 Kafka 자원 관리에 적용
