---
title: "1. GitOps 기반 Kafka 플랫폼 설계"
weight: 1
date: 2026-04-29
---

> 본 문서는 현업에서 Kafka 공통파트로서 개발 표준을 잡기 위한 설계 노트다.
>
> 단정적 진술은 가능한 한 1차 출처(Confluent 공식 블로그/문서, gitops.tech 등)에 기반해 인용하고,
> 출처가 명확하지 않거나 일반론·추론에 가까운 부분은 **(추론)** 또는 **(미정)** 으로 표기한다.

## 1. 목표

이 작업의 목표는 *Kafka 클러스터 자체* 의 구축이 아니라, **Kafka 자원(Topic, ACL, Schema, Connector 등)을 조직 차원에서 일관되게 관리하기 위한 플랫폼/표준을 정립**하는 것.

구체적으로는 다음을 만족해야 한다.
1. 모든 Kafka 관련 설정(브로커 설정, 토픽 정의, ACL, 스키마)이 **Git 으로 추적**된다.
2. 변경은 **PR 리뷰**를 거쳐 운영에 반영된다 (사람이 운영 클러스터에 직접 명령 X).
3. **dev / stg / prd** 환경 간 차이가 명시적으로 코드로 표현된다.
4. Producer / Consumer 애플리케이션은 도메인 팀이 자기 코드와 함께 관리하되, **공통 라이브러리** 를 통해 직렬화·메트릭·DLQ 등 횡단 관심사를 표준화한다.

---

## 2. 표준 가이드 (1차 출처 인용)

### 2.1. GitOps 정의 (gitops.tech)

> *"GitOps is a way of implementing Continuous Deployment for cloud native applications. ... using Git as a single source of truth for declarative infrastructure and applications, together with tools ensuring the actual state of infrastructure and applications converges towards the desired state declared in Git."*
> — [gitops.tech](https://www.gitops.tech/)

핵심 원칙 — **Declarative · Versioned · Pulled Automatically · Continuously Reconciled** (CNCF OpenGitOps 1.0의 4원칙. 본 문서 작성 시점에 직접 검증 미완 — *추후 https://opengitops.dev/ 확인 필요*).

### 2.2. Confluent의 GitOps 적용 권장 (공식 출처 3건)

| # | 출처 | 핵심 |
|---|---|---|
| (a) | [Confluent Blog — *DevOps for Apache Kafka with Kubernetes and GitOps*](https://www.confluent.io/blog/devops-for-apache-kafka-with-kubernetes-and-gitops/) | Flux + Kustomize + custom operator(ccloud-operator, connect-operator) 패턴 제시 |
| (b) | [Confluent Docs — *DevOps for Kafka with Kubernetes and GitOps* (streaming-ops 튜토리얼)](https://docs.confluent.io/platform/current/tutorials/streaming-ops/index.html) | 공식 docs 에 포함된 GitOps 튜토리얼 |
| (c) | [Confluent Blog — *GitOps For Kafka Admins: CI/CD Pipeline With Confluent for Kubernetes*](https://www.confluent.io/blog/resource-management-with-confluent-for-kubernetes/) | CfK(Confluent for Kubernetes) 환경에서의 CI/CD |

(a) 의 직접 인용:
> *"GitOps allows you to apply the same review and accept processes to deployment code that you use for application code."*
> *"The Git repository represents the desired state of the system ... you can easily detect differences in the desired state across them."*

(a) 가 제시하는 흐름:
1. 개발자가 feature branch 에서 YAML 선언 수정
2. PR → 코드 리뷰
3. 머지 → master
4. Flux 가 Git poll, 변경 감지
5. Flux 가 Kustomize 로 환경별 매니페스트 build
6. Flux 가 K8s API 에 apply
7. Operator/Controller 가 desired ↔ actual reconcile

→ **이 7단계 흐름을 본 문서의 운영 워크플로우 표준으로 채택한다.**

### 2.3. 한계 (정직하게)

- 위 출처들은 **Kubernetes 환경 전제**다. 자체 VM/베어메탈 운영이라면 그대로 적용 불가 → §6 도구 비교 참고
- "Confluent 의 *유일한* 표준" 이라고 선언된 적은 없음. *"권장 패턴 중 하나"* 로 블로그·튜토리얼이 제공된 것 — 본 문서는 이 권장을 채택한다는 입장 (조직 차원의 의사결정)
- "Producer/Consumer 리포를 도메인 단위로 분리" 부분은 **(개인 추론)**. Confluent 가 명시한 표준은 아니며, 마이크로서비스 일반 원칙에서 가져온 추론

---

## 3. 방향성

### 3.1. 채택 결정

| 축 | 결정 | 근거 |
|---|---|---|
| 운영 방식 | **GitOps** | gitops.tech 정의, Confluent 권장 (§2.2) |
| 실행 환경 | **Kubernetes** (Strimzi 또는 CfK 가정) | Confluent 권장 출처 3건 모두 K8s 기반. 비-K8s 환경이면 §6 재선택 |
| Source of Truth | **Git** (선언형 YAML) | GitOps 정의 |
| Reconciliation | **Pull 모델** (에이전트가 Git 을 pull, drift 자동 교정) | OpenGitOps 4원칙 中 "Continuously Reconciled" |
| 환경 분리 | **Kustomize overlays** (base + dev/stg/prd patch) | Confluent (a) 출처 |

### 3.2. 비채택 — push 기반 CI/CD 와의 차이

전통적 CI/CD: PR 머지 → CI 파이프라인이 클러스터에 *push*. 이 경우 누군가 클러스터를 수동으로 만지면 drift 가 누적된다.

GitOps: 클러스터 *내부* 에이전트(Flux/Argo CD)가 Git 을 *pull* 하고 reconcile. 수동 변경이 발생해도 자동으로 Git 상태로 되돌린다 → **운영 안전성 + 변경 가시성** 이 본질.

---

## 4. 토픽 네이밍 컨벤션

> 출처: [Confluent — *Kafka Topic Naming Convention: Best Practices, Patterns, and Guidelines*](https://www.confluent.io/learn/kafka-topic-naming-convention/)

### 4.1. Confluent 가 권장하는 4가지 구성 요소

1. **Data Source / Domain** — 발생 시스템 (예: `sales`, `hr`, `product`)
2. **Data Type / Action** — 이벤트 종류 (예: `order`, `click`, `transaction`)
3. **Environment / Region** — 배포 컨텍스트 (`prod`/`dev` 또는 `us-east`)
4. **Version** — 스키마 버전 (`v1`, `v2`)

### 4.2. 일반적 패턴 (Confluent 제시)

| 패턴 | 예시 |
|---|---|
| Hierarchical | `domain.data_type.region.version` |
| Action-Based | `user.signup.success` |
| Environment-Specific | `prod.order.events`, `dev.order.events` |
| Multi-Region | `global.sales.eu-west` |

### 4.3. 본 조직 채택안 (제안)

**`<env>.<domain>.<event>.<version>`** — Hierarchical + Environment-Specific 결합.

- 예: `prd.order.created.v1`, `dev.payment.refunded.v2`
- 구분자: `.` (period) 일관 사용 — Confluent 의 *"Use separators ... consistently"* 가이드 준수
- 환경을 prefix 로 둔 이유: ACL/권한을 환경 단위로 묶기 쉽고, 클러스터를 같이 쓸 때 분리에 유리 **(개인 추론)**

### 4.4. 기술적 제약 (Confluent 명시)

- 토픽 이름 **249자 제한** (Confluent 문서 인용)
- 모호한 이름(`data`, `messages`) 금지
- 약어 남발 금지
- 구분자 혼용 금지(`_` 와 `-` 섞지 말 것)

---

## 5. Git Repository 설계

### 5.1. 리포 구성 (3+N 개)

> 사용자가 처음 제시한 "Producer / Broker / Consumer 3개 분리" 안은 도메인 로직과 인프라 관리를 같은 축에서 분리해 충돌을 일으키므로 채택하지 않는다 — **(개인 추론. Confluent 공식 출처 없음)**

| 리포 | 개수 | 담당 | 라이프사이클 |
|---|---|---|---|
| **`kafka-platform`** | 1 | 플랫폼/공통팀 | 인프라 사이클 |
| **`kafka-common-lib`** | 1 | 플랫폼/공통팀 | 라이브러리 버전 사이클 |
| 도메인 서비스 리포 (`order-service`, `payment-service` ...) | N | 각 도메인 팀 | 서비스 배포 사이클 |

### 5.2. `kafka-platform` 패키지 트리 (제안)

```text
kafka-platform/
├── README.md                          # 컨벤션·기여 가이드·온콜 연락처
├── CODEOWNERS                         # 토픽/ACL 변경 리뷰어 자동 지정
│
├── clusters/                          # 클러스터 자체 정의 (Strimzi 가정)
│   ├── base/
│   │   └── kafka-cluster.yaml         # Kafka CR (replication, listener, KRaft)
│   └── overlays/
│       ├── dev/
│       │   └── kustomization.yaml
│       ├── stg/
│       │   └── kustomization.yaml
│       └── prd/
│           └── kustomization.yaml
│
├── topics/                            # 토픽 선언
│   ├── base/
│   │   ├── order/
│   │   │   ├── prd.order.created.v1.yaml
│   │   │   └── prd.order.cancelled.v1.yaml
│   │   └── payment/
│   │       └── prd.payment.completed.v1.yaml
│   └── overlays/
│       ├── dev/                       # dev 환경에서 partitions/retention 축소
│       ├── stg/
│       └── prd/
│
├── acls/                              # 토픽-서비스 권한 매핑
│   ├── order-service.yaml             # which topics R/W
│   └── payment-service.yaml
│
├── schemas/                           # Avro/Protobuf (Schema Registry 등록)
│   ├── order/
│   │   ├── order.created.v1.avsc
│   │   └── order.cancelled.v1.avsc
│   └── payment/
│       └── payment.completed.v1.avsc
│
├── connectors/                        # Kafka Connect (있다면)
│   └── debezium-mysql-orders.yaml
│
├── policies/                          # 거버넌스 정책 (PR 템플릿 등에서 참조)
│   ├── topic-naming.md                # §4 네이밍 룰
│   ├── retention-defaults.md          # 기본 retention 표
│   └── partition-sizing.md            # 파티션 산정 가이드
│
└── .github/
    ├── workflows/
    │   ├── validate.yml               # PR: lint, schema 검증, dry-run
    │   └── apply.yml                  # 머지: Flux 가 자동 적용 (push X)
    └── PULL_REQUEST_TEMPLATE.md       # 변경 사유, 영향 범위, rollback 계획
```

### 5.3. `kafka-common-lib` 패키지 트리 (Spring Kafka 기준 제안)

```text
kafka-common-lib/
├── build.gradle / pom.xml
├── src/main/java/.../kafka/
│   ├── config/
│   │   ├── KafkaProducerDefaults.java   # acks=all, enable.idempotence=true
│   │   └── KafkaConsumerDefaults.java   # isolation.level, max.poll.records
│   ├── serde/
│   │   ├── AvroSerdeFactory.java        # Schema Registry 클라이언트 통합
│   │   └── JsonSerdeFactory.java
│   ├── error/
│   │   ├── DltPublisher.java            # Dead Letter Topic 발행 표준
│   │   └── RetryTopicTemplate.java
│   ├── observability/
│   │   ├── MicrometerKafkaMetrics.java
│   │   └── TracingKafkaInterceptor.java # OpenTelemetry
│   └── auth/
│       └── SaslOauthBearerConfig.java
└── src/test/...
```

→ 도메인 서비스는 이 라이브러리를 **Maven/Gradle 의존성** 으로 가져다 쓴다. 디폴트가 안전하게 박혀 있어 개별 팀이 `acks`, `idempotence` 같은 핵심을 잘못 끄지 못하게 함.

### 5.4. 도메인 서비스에서의 사용 (예: `order-service`)

```text
order-service/
├── src/main/java/.../OrderService.java
├── src/main/java/.../events/
│   ├── OrderCreatedProducer.java       # kafka-common-lib 사용
│   └── PaymentCompletedConsumer.java
└── src/main/resources/application.yml  # bootstrap-servers 등 환경값만
```

토픽/스키마 변경이 필요하면 → 도메인 팀이 `kafka-platform` 리포에 PR 생성 → 플랫폼팀 리뷰 → 머지 → Flux 가 적용 → `order-service` 가 새 토픽/스키마를 사용.

---

## 6. 적용 도구 비교

> 환경에 따라 §3.1 의 "Kubernetes" 가정이 깨질 수 있으므로 옵션을 정리.

| 도구 | 적용 환경 | 토픽 | ACL | Schema | 비고 / 출처 |
|---|---|---|---|---|---|
| **Strimzi** (`KafkaTopic` CRD) | K8s | ✅ | ✅ (`KafkaUser`) | ❌ (별도) | OSS, CNCF Sandbox. [strimzi.io](https://strimzi.io/) |
| **Confluent for Kubernetes (CfK)** | K8s + Confluent Platform | ✅ | ✅ | ✅ | 상용. Confluent (c) 출처 권장 |
| **JulieOps** | 모든 Kafka | ✅ | ✅ | ✅ | OSS. [github.com/kafka-ops/julie](https://github.com/kafka-ops/julie). K8s 미사용 환경에 적합 |
| **Terraform Kafka Provider** | 모든 Kafka | ✅ | ✅ | △ | [Mongey/terraform-provider-kafka](https://github.com/Mongey/terraform-provider-kafka). 이미 Terraform 쓰는 조직 |
| **kafka-gitops** | 모든 Kafka | ✅ | ✅ | ❌ | OSS, 경량. [github.com/devshawn/kafka-gitops](https://github.com/devshawn/kafka-gitops) |

### 6.1. 본 조직 추천 (조건부)

- **K8s 사용 + OSS 선호** → Strimzi + Schema 는 별도 (Apicurio Registry 등)
- **K8s 사용 + Confluent 라이선스 보유** → CfK
- **K8s 미사용** → JulieOps 또는 Terraform Provider

→ 환경 결정이 선행되어야 함. **(미정)** — 운영 환경 합의 후 본 절 확정.

---

## 7. 운영 워크플로우

### 7.1. 변경 흐름 (Confluent (a) 7단계 채택)

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

### 7.2. 환경 승급 (dev → stg → prd)

- 동일한 base 매니페스트를 Kustomize overlay 로 환경별 분기
- prd 만 별도 PR + 별도 리뷰어 그룹 (운영 거버넌스)
- prd overlay 변경은 release tag 와 묶음 **(개인 추론 — 조직 정책에 따라 조정)**

### 7.3. Drift 감지 / 롤백

- Flux 의 reconcile 로 수동 변경 자동 교정 (GitOps 의 핵심 가치)
- 사고 시 Git revert → 자동으로 직전 상태로 복귀

---

## 8. 후속 결정사항 (미정)

| 항목 | 옵션 | 결정 시점 |
|---|---|---|
| 실행 환경 | Strimzi (OSS) / CfK / Confluent Cloud / 자체 운영 | 사전 결정 필요 |
| Schema Registry | Confluent Schema Registry / Apicurio / Karapace | 환경 결정 후 |
| 직렬화 포맷 | Avro / Protobuf / JSON Schema | 도메인 요구사항 검토 후 |
| 인증/인가 | mTLS / SASL/OAuth / SCRAM | 보안팀 협의 |
| Connect 사용 여부 | 사용 / 미사용 | CDC/싱크 요구사항 |
| 멀티 클러스터 / DR | MirrorMaker 2 / Cluster Linking | 가용성 SLA 정의 후 |

---

## 9. 참고 (모음)

- [gitops.tech — official definition](https://www.gitops.tech/)
- [Confluent Blog — DevOps for Apache Kafka with Kubernetes and GitOps](https://www.confluent.io/blog/devops-for-apache-kafka-with-kubernetes-and-gitops/)
- [Confluent Docs — DevOps for Kafka with Kubernetes and GitOps](https://docs.confluent.io/platform/current/tutorials/streaming-ops/index.html)
- [Confluent Blog — GitOps For Kafka Admins (CfK)](https://www.confluent.io/blog/resource-management-with-confluent-for-kubernetes/)
- [Confluent — Kafka Topic Naming Convention](https://www.confluent.io/learn/kafka-topic-naming-convention/)
- [Strimzi](https://strimzi.io/)
- [JulieOps](https://github.com/kafka-ops/julie)
- [Terraform Kafka Provider](https://github.com/Mongey/terraform-provider-kafka)
- [kafka-gitops](https://github.com/devshawn/kafka-gitops)
- OpenGitOps 4원칙 — https://opengitops.dev/ (직접 검증 미완 / 추후 확인)
