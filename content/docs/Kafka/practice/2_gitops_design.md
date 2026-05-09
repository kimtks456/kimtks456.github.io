---
title: "2. GitOps 기반 설계"
weight: 2
date: 2026-05-04
---

> 본 문서는 Kafka 공통 플랫폼의 **GitOps 기반 운영 방향성** — 즉, *어떤 운영 모델로 갈 것인가* 를 정한다.
> GitOps + Pull 모델 채택의 근거를 1차 출처(gitops.tech, Confluent 블로그/docs) 인용으로 정리하고,
> 기존 push 기반 CI/CD 와의 차이를 비교한다.
>
> 관련 문서:
> - [3. Topic 설계](./3_topic_design.md)
> - [4. Message Format 설계](./4_message_format.md)
> - [5. 설계](./5_design.md)

---

## 1. 목표

이 작업의 목표는 *Kafka 클러스터 자체* 의 구축이 아니라, **Kafka 자원(Topic, ACL, Schema, Connector 등)을 조직 차원에서 일관되게 관리하기 위한 플랫폼/표준을 정립**하는 것.

구체적으로는 다음을 만족해야 한다.
1. 모든 Kafka 관련 설정(브로커 설정, 토픽 정의, ACL, 스키마)이 **Git 으로 추적**된다.
2. 변경은 **PR 리뷰**를 거쳐 운영에 반영된다 (사람이 운영 클러스터에 직접 명령 X).
3. **dev / stg / prd** 환경 간 차이가 명시적으로 코드로 표현된다.
4. Producer / Consumer 애플리케이션은 도메인 팀이 자기 코드와 함께 관리하되, **공통 라이브러리** 를 통해 직렬화·메트릭·DLQ 등 횡단 관심사를 표준화한다.

---

## 2. GitOps + Confluent 권장 (요약)

> GitOps 의 정의·OpenGitOps 4원칙·운영 진화의 역사(SSH → Ansible → AWS CodeBuild 같은 push 모델 → GitOps)·push vs pull 비교는 별도 문서로 분리.
> 자세히는 [DevOps/GitOps/1. GitOps — 정의·배경·역사](../../DevOps/GitOps/1_concept.md) 참조.
> 본 절은 *Kafka 자원 관리* 맥락에서 무엇을 채택했는지의 근거만 짧게 정리.

### 2.1. 한 줄 정의

> *"Git as a single source of truth for declarative infrastructure and applications, together with tools ensuring the actual state ... converges towards the desired state declared in Git."*
> — [gitops.tech](https://www.gitops.tech/)

### 2.2. Confluent 의 GitOps 적용 권장 (공식 출처 3건)

| # | 출처 | 핵심 |
|---|---|---|
| (a) | [Confluent Blog — *DevOps for Apache Kafka with Kubernetes and GitOps*](https://www.confluent.io/blog/devops-for-apache-kafka-with-kubernetes-and-gitops/) | Flux + Kustomize + custom operator(ccloud-operator, connect-operator) 패턴 제시 |
| (b) | [Confluent Docs — *DevOps for Kafka with Kubernetes and GitOps* (streaming-ops 튜토리얼)](https://docs.confluent.io/platform/current/tutorials/streaming-ops/index.html) | 공식 docs 에 포함된 GitOps 튜토리얼 |
| (c) | [Confluent Blog — *GitOps For Kafka Admins: CI/CD Pipeline With Confluent for Kubernetes*](https://www.confluent.io/blog/resource-management-with-confluent-for-kubernetes/) | CfK(Confluent for Kubernetes) 환경에서의 CI/CD |

(a) 직접 인용:
> *"GitOps allows you to apply the same review and accept processes to deployment code that you use for application code."*
> *"The Git repository represents the desired state of the system."*

(a) 가 제시하는 7단계 흐름은 [§5 운영 워크플로우](#5-운영-워크플로우) 에서 본 조직 표준으로 채택.

### 2.3. 한계 (정직하게)

- 위 출처들은 **Kubernetes 환경 전제**. 자체 VM/베어메탈 운영이라면 그대로 적용 불가 → §4 도구 비교 참고
- "Confluent 의 *유일한* 표준" 이 아니라 *권장 패턴 중 하나*. 본 문서는 이 권장을 채택한다는 조직 차원 의사결정
- "Producer/Consumer 리포를 도메인 단위로 분리" 부분은 **(개인 추론)** — 마이크로서비스 일반 원칙에서 차용

---

## 3. 방향성

### 3.1. 채택 결정

| 축 | 결정 | 근거 |
|---|---|---|
| 운영 방식 | **GitOps** | gitops.tech 정의, Confluent 권장 (§2.2) |
| 실행 환경 | **Kubernetes** (Strimzi 또는 CfK 가정) | Confluent 권장 출처 3건 모두 K8s 기반. 비-K8s 환경이면 §4 재선택 |
| Source of Truth | **Git** (선언형 YAML) | GitOps 정의 |
| Reconciliation | **Pull 모델** (에이전트가 Git 을 pull, drift 자동 교정) | OpenGitOps 4원칙 中 "Continuously Reconciled" |
| 환경 분리 | **Kustomize overlays** (base + dev/stg/prd patch) | Confluent (a) 출처 |

### 3.2. 비채택 — push 기반 CI/CD 와의 차이

전통적 push 모델(Jenkins / AWS CodeBuild·CodeDeploy / GitHub Actions 가 클러스터에 직접 `kubectl apply` push) 과의 핵심 차이는 *클러스터 자격증명 위치, drift 감지, rollback 단위* 세 가지. **Kafka 자원처럼 *desired state 가 운영 중에 표류하면 안 되는*(토픽이 누가 손으로 만든 것 vs git 선언인지) 자원** 일수록 pull 모델의 가치가 큼.

자세한 비교 표·GitOps 의 등장 동기·운영 진화의 역사는 [DevOps/GitOps/1. GitOps — 정의·배경·역사](../../DevOps/GitOps/1_concept.md) 에 정리.

→ Pull 모델의 구체 구현체(ArgoCD)는 [DevOps/ArgoCD/1. ArgoCD 개념](../../DevOps/ArgoCD/1_concept.md) 참조.

---

## 4. 적용 도구 비교

> 환경에 따라 §3.1 의 "Kubernetes" 가정이 깨질 수 있으므로 옵션을 정리.

| 도구 | 적용 환경 | 토픽 | ACL | Schema | 비고 / 출처 |
|---|---|---|---|---|---|
| **Strimzi** (`KafkaTopic` CRD) | K8s | ✅ | ✅ (`KafkaUser`) | ❌ (별도) | OSS, CNCF Sandbox. [strimzi.io](https://strimzi.io/) |
| **Confluent for Kubernetes (CfK)** | K8s + Confluent Platform | ✅ | ✅ | ✅ | 상용. Confluent (c) 출처 권장 |
| **JulieOps** | 모든 Kafka | ✅ | ✅ | ✅ | OSS. [github.com/kafka-ops/julie](https://github.com/kafka-ops/julie). K8s 미사용 환경에 적합 |
| **Terraform Kafka Provider** | 모든 Kafka | ✅ | ✅ | △ | [Mongey/terraform-provider-kafka](https://github.com/Mongey/terraform-provider-kafka). 이미 Terraform 쓰는 조직 |
| **kafka-gitops** | 모든 Kafka | ✅ | ✅ | ❌ | OSS, 경량. [github.com/devshawn/kafka-gitops](https://github.com/devshawn/kafka-gitops) |

### 4.1. 본 조직 추천 (조건부)

- **K8s 사용 + OSS 선호** → Strimzi + Schema 는 별도 (Apicurio Registry 등)
- **K8s 사용 + Confluent 라이선스 보유** → CfK
- **K8s 미사용** → JulieOps 또는 Terraform Provider

→ 환경 결정이 선행되어야 함. **(미정)** — 운영 환경 합의 후 본 절 확정.

---

## 5. 운영 워크플로우

### 5.1. 변경 흐름 (Confluent (a) 7단계 채택)

```text
[도메인 개발자]
   │ 1. feature branch 에서 topics/ schemas/ acls/ YAML 수정
   ▼
[GitHub PR]
   │ 2. CODEOWNERS 가 플랫폼팀 리뷰어 자동 지정
   │ 3. CI: validate.yml (lint, schema 호환성, dry-run apply)
   │ 4. 리뷰 통과 → 머지
   ▼
[main branch]
   │ 5. Flux/Argo CD 가 Git poll
   ▼
[K8s cluster]
   │ 6. Strimzi/CfK Operator 가 reconcile (KafkaTopic, KafkaUser, Schema)
   ▼
[Kafka cluster]
   │ 7. 새 토픽/ACL/스키마 활성. 도메인 서비스에서 사용 가능
```

### 5.2. 환경 승급 (dev → stg → prd)

- 동일한 base 매니페스트를 Kustomize overlay 로 환경별 분기
- prd 만 별도 PR + 별도 리뷰어 그룹 (운영 거버넌스)
- prd overlay 변경은 release tag 와 묶음 **(개인 추론 — 조직 정책에 따라 조정)**

### 5.3. Drift 감지 / 롤백

- Flux/Argo CD 의 reconcile 로 수동 변경 자동 교정 (GitOps 의 핵심 가치)
- 사고 시 Git revert → 자동으로 직전 상태로 복귀

→ Pull 모델 reconcile 의 구체 동작은 [DevOps/ArgoCD/1. ArgoCD 개념](../../DevOps/ArgoCD/1_concept.md) §4 참조.

---

## 6. 후속 결정사항 (미정)

| 항목 | 옵션 | 결정 시점 | 관련 문서 |
|---|---|---|---|
| 실행 환경 | Strimzi (OSS) / CfK / Confluent Cloud / 자체 운영 | 사전 결정 필요 | 본 문서 §4 |
| Schema Registry | Confluent Schema Registry / Apicurio / Karapace | 환경 결정 후 | [4. Message Format 설계](./4_message_format.md) |
| 직렬화 포맷 | Avro / Protobuf / JSON Schema | 도메인 요구사항 검토 후 | [4. Message Format 설계](./4_message_format.md) |
| 인증/인가 | mTLS / SASL/OAuth / SCRAM | 보안팀 협의 | (별도 문서 *(미정)*) |
| Connect 사용 여부 | 사용 / 미사용 | CDC/싱크 요구사항 | [Kafka/Connect](../../Kafka/connect/1_concept.md) — 사용 결정 |
| 멀티 클러스터 / DR | MirrorMaker 2 / Cluster Linking | 가용성 SLA 정의 후 | (별도 문서 *(미정)*) |

---

## 7. 참고 (출처)

- [gitops.tech — official definition](https://www.gitops.tech/)
- [Confluent Blog — DevOps for Apache Kafka with Kubernetes and GitOps](https://www.confluent.io/blog/devops-for-apache-kafka-with-kubernetes-and-gitops/)
- [Confluent Docs — DevOps for Kafka with Kubernetes and GitOps](https://docs.confluent.io/platform/current/tutorials/streaming-ops/index.html)
- [Confluent Blog — GitOps For Kafka Admins (CfK)](https://www.confluent.io/blog/resource-management-with-confluent-for-kubernetes/)
- [Strimzi](https://strimzi.io/)
- [JulieOps](https://github.com/kafka-ops/julie)
- [Terraform Kafka Provider](https://github.com/Mongey/terraform-provider-kafka)
- [kafka-gitops](https://github.com/devshawn/kafka-gitops)
- OpenGitOps 4원칙 — https://opengitops.dev/ (직접 검증 미완 / 추후 확인)
