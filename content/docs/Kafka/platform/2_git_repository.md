---
title: "2. Git Repository 설계"
weight: 2
date: 2026-05-04
---

> 본 문서는 Kafka 플랫폼을 GitOps 로 운영하기 위한 **Git 리포 구성**과 각 리포의 패키지 트리를 정한다.
> "왜 GitOps 인가" 와 도구 선택은 [1. 방향성](./1_direction.md), 토픽 네이밍은 [3. Topic 설계](./3_topic_design.md) 참조.

---

## 1. 리포 구성 (3+N 개)

> 사용자가 처음 제시한 "Producer / Broker / Consumer 3개 분리" 안은 도메인 로직과 인프라 관리를 같은 축에서 분리해 충돌을 일으키므로 채택하지 않는다 — **(개인 추론. Confluent 공식 출처 없음)**

| 리포 | 개수 | 담당 | 라이프사이클 |
|---|---|---|---|
| **`kafka-platform`** | 1 | 플랫폼/공통팀 | 인프라 사이클 |
| **`kafka-common-lib`** | 1 | 플랫폼/공통팀 | 라이브러리 버전 사이클 |
| 도메인 서비스 리포 (`order-service`, `payment-service` ...) | N | 각 도메인 팀 | 서비스 배포 사이클 |

---

## 2. `kafka-platform` 패키지 트리 (제안)

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
│   ├── topic-naming.md                # 토픽 네이밍 룰 — [3. Topic 설계](./3_topic_design.md) 참조
│   ├── retention-defaults.md          # 기본 retention 표
│   └── partition-sizing.md            # 파티션 산정 가이드
│
└── .github/
    ├── workflows/
    │   ├── validate.yml               # PR: lint, schema 검증, dry-run
    │   └── apply.yml                  # 머지: Flux 가 자동 적용 (push X)
    └── PULL_REQUEST_TEMPLATE.md       # 변경 사유, 영향 범위, rollback 계획
```

---

## 3. `kafka-common-lib` 패키지 트리 (Spring Kafka 기준 제안)

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

→ serde 의 직렬화 포맷·Schema Registry 결정은 [4. Message Format 설계](./4_message_format.md) 참조.

---

## 4. 도메인 서비스에서의 사용 (예: `order-service`)

```text
order-service/
├── src/main/java/.../OrderService.java
├── src/main/java/.../events/
│   ├── OrderCreatedProducer.java       # kafka-common-lib 사용
│   └── PaymentCompletedConsumer.java
└── src/main/resources/application.yml  # bootstrap-servers 등 환경값만
```

토픽/스키마 변경이 필요하면 → 도메인 팀이 `kafka-platform` 리포에 PR 생성 → 플랫폼팀 리뷰 → 머지 → Flux/Argo CD 가 적용 → `order-service` 가 새 토픽/스키마를 사용.
