---
title: "1. Connect 개념"
weight: 1
date: 2026-05-02
---

> Kafka Connect 는 **Kafka 와 외부 시스템 사이의 데이터 이동을 코드 작성 없이 선언형 설정으로 처리**하는 별도 프레임워크다.
> 본 문서는 sink 종류(DB, 검색엔진, 객체스토리지 등)와 무관하게 통용되는 Connect 의 **개념·아키텍처·고가용성·자원**을 1차 출처(Apache / Confluent docs) 인용 중심으로 정리한다.
>
> 관련 문서:
> - 모니터링: [2. 모니터링](./2_monitoring.md)
> - DB sink 시나리오의 구체 의문(Q&A): [3. DB Sink 시나리오 Q&A](./3_db_sink_qna.md)

---

## 1. Connect 개념

> 출처: [Confluent — Kafka Connect Concepts](https://docs.confluent.io/platform/current/connect/concepts.html)

### 1.1. Connect 란 무엇인가

핵심 인용:
> *"You can deploy Kafka Connect as a ... distributed, scalable, fault-tolerant service supporting an entire organization."*
> *"a separate framework layer above the Kafka cluster itself."*

Connect 는 **Kafka 브로커 안에서 도는 게 아니다**. broker 와는 별개의 JVM 프로세스 군(Worker cluster)을 별도 운영한다. 하는 일은 단 하나 — *Kafka 와 외부 시스템 간 데이터 이동을 표준화된 컴포넌트로 처리하기*.

이를 위해 Connect 가 책임지는 것:
- **데이터 이동의 양방향 추상화** (외부 → Kafka, Kafka → 외부)
- **분산 실행·HA·rebalance** (Worker cluster)
- **상태 관리** (offset, 설정, 상태를 Kafka 내부 토픽에 저장)
- **직렬화 분리** (Converter)
- **단일 메시지 변환** (SMT)
- **실패 격리** (DLQ)

### 1.2. 토폴로지

```text
[Service A] ──┐
[Service B] ──┼──→ [Kafka Broker Cluster] ←── [Connect Worker Cluster] ──→ [외부 시스템]
[ ...     ] ──┘     (메타·로그·파티션 보관)      (Sink/Source Connector             (DB / ES / S3 / ...)
                                                    가 task 단위로 실행)
```

- **Producer (비즈니스 서비스)** → broker 로 발행
- **Connect Worker** = broker 의 컨슈머이자 외부 시스템의 클라이언트
- broker 는 외부 시스템을 전혀 모름

### 1.3. 두 가지 방향: Source / Sink Connector

> 출처: 동일 (Confluent Connect Concepts)

| 방향 | 정의 (공식 인용) | 흐름 | 대표 예시 |
|---|---|---|---|
| **Source Connector** | *"Source connectors ingest entire databases and stream table updates to Kafka topics."* | **외부 시스템 → Kafka** | Debezium (CDC), JDBC Source, FileStream Source, MongoDB Source |
| **Sink Connector** | *"Sink connectors deliver data from Kafka topics to secondary indexes, such as Elasticsearch, or batch systems such as Hadoop for offline analysis."* | **Kafka → 외부 시스템** | JDBC Sink, Elasticsearch Sink, S3/GCS Sink, HDFS Sink |

→ 어떤 sink 가 와도 Connect 의 책임 모델은 동일. Sink 별 차이는 *put() 구현 안에서* 흡수된다.

### 1.4. 핵심 구성요소: Connector / Task / Worker

> 출처: 동일 (Confluent Connect Concepts)

| 개념 | 정의 (공식 인용) | 실체 |
|---|---|---|
| **Connector** | *"a logical job that is responsible for managing the copying of data between Kafka and another system"* | **논리적 작업 정의**. YAML/JSON 한 장. 어떤 시스템·어떤 토픽·어떤 변환·어떤 인증 — 선언형 설정 |
| **Task** | *"the main actor in the data model for Connect. Each connector instance coordinates a set of tasks that copy data"* | Connector 가 띄우는 **실행 단위**. `tasks.max=4` 면 task 4 개. 각 task 가 토픽 파티션을 분담해 처리 |
| **Worker** | (개념적) Connector/Task 를 실행하는 **JVM 프로세스** | OS 프로세스. distributed mode 에서 N 대가 한 클러스터를 이룸 |

위계:
```text
Connector (1)                 ← "토픽 X 를 시스템 Y 에 옮겨라" 같은 선언
    └─ Task (N)               ← 병렬도. Connector 가 task 를 N개 만듦
         └─ Worker 에 분산 할당  ← Worker 들이 task 를 나눠 실행
```

비유:
- **Connector** = "이 일을 한다" 의 *직무 명세서*
- **Task** = 그 일을 실제로 하는 *작업자 1명*
- **Worker** = 작업자들이 출퇴근하는 *사무실(서버)*

### 1.5. 추가 구성요소: Converter · Transform · DLQ

Connect 의 데이터 처리 파이프라인 안에서 함께 쓰이는 보조 요소. **모두 sink 종류와 무관**하게 동일하게 적용된다.

#### Converter (직렬화/역직렬화)

> *"change the format of data from bytes to a Connect internal data format and vice versa."*
> *"Converters are decoupled from connectors themselves to allow for the reuse of converters between connectors."*

| Converter | Schema Registry | 용도 |
|---|---|---|
| `AvroConverter` | ✅ 필요 | Avro + Schema Registry (가장 흔한 운영 표준) |
| `ProtobufConverter`, `JsonSchemaConverter` | ✅ 필요 | Protobuf / JSON Schema |
| `JsonConverter` | ❌ 불필요 | 스키마 없는 JSON. 운영급에는 비추 *(개인 추론)* |
| `StringConverter` | ❌ 불필요 | 단순 문자열 |
| `ByteArrayConverter` | ❌ 불필요 | pass-through (변환 없음) |

→ Connector 자체와 **분리되어 있어**, 같은 Avro Converter 를 Source 와 Sink, 그리고 서로 다른 외부 시스템용 Connector 가 동시에 재사용 가능.

#### Transform (SMT — Single Message Transforms)

> *"Connectors can be configured with transformations to make simple and lightweight modifications to individual messages. A transform accepts one record as an input and outputs a modified record."*

- **단일 레코드 단위** 변환만 (필드 rename, cast, mask, filter, route 등)
- 복잡한 변환은 SMT 영역이 아님:
  > *"more complex transformations and operations that apply to many messages are best implemented with ksqlDB ... and Kafka Streams."*

대표 SMT 카테고리:

| 카테고리 | SMT |
|---|---|
| Field 조작 | `ReplaceField`, `Cast`, `ExtractField`, `InsertField`, `HoistField`, `ValueToKey` |
| 마스킹·필터 | `MaskField`, `Drop`, `Filter` |
| 라우팅 | `RegexRouter`, `TimestampRouter`, `TopicRegexRouter` |
| 시간/타입 변환 | `TimestampConverter`, `TimezoneConverter` |
| Header 조작 | `HeaderFrom`, `InsertHeader`, `DropHeaders` |

#### Dead Letter Queue (DLQ)

> Sink Connector 에서 변환·적재 실패 시 *"routed to a special topic and report the error."*

설정 (공식 예):
```text
errors.tolerance = all
errors.deadletterqueue.topic.name = <connector>.dlq
errors.deadletterqueue.context.headers.enable = true
```

→ `errors.tolerance=none` (default) 이면 task 가 죽음. `all` + DLQ 토픽 지정 시 실패 레코드만 격리되고 나머지 적재는 계속.

### 1.6. 실행 모드: Standalone vs Distributed

> *"In distributed mode, you start many worker processes using the same `group.id` and they coordinate to schedule execution of connectors and tasks across all available workers."*

| 모드 | 특징 | 용도 |
|---|---|---|
| **Standalone** | 한 JVM 프로세스에서 모든 task 실행. 설정도 파일 기반 | 단일 머신 테스트, 로컬 개발. **운영급 X** |
| **Distributed** | N 개 Worker 가 같은 `group.id` 로 클러스터링. 설정·offset·status 는 Kafka 내부 토픽에 보관. REST API 로 connector 관리 | **운영급 표준** |

→ 본 조직은 distributed mode + Worker N≥3 을 전제 (자세히는 §3 HA).

### 1.7. 데이터 처리 흐름 (Sink Connector 일반)

Sink Connector 가 한 batch 를 처리하는 흐름 — **외부 시스템 종류와 무관**:

```text
1. Worker 의 SinkTask 가 토픽 partition 들을 consume (Kafka consumer 로 동작)
        │
        ▼
2. Converter 가 byte 를 Connect 내부 자료구조로 deserialize
   (예: AvroConverter 가 Schema Registry 에서 schema 가져와 Avro → Struct)
        │
        ▼
3. SMT chain 적용 (rename, cast, mask, filter, route 순으로 설정한 만큼)
        │
        ▼
4. Connector 의 put() 메서드로 외부 시스템에 batch write
   (각 Connector 구현체가 자기 클라이언트 라이브러리로 호출)
        │
        ├── 성공 → 다음 단계
        └── 실패 → errors.tolerance 정책에 따라 retry / DLQ / task 종료
        │
        ▼
5. offset commit (broker 의 __consumer_offsets 토픽에 기록)
```

→ 이 흐름은 **모든 task 가 자기 외부 시스템 connection 을 가지고 병렬로 수행**. `tasks.max` 개 만큼 동시 진행.

→ 외부 시스템별 batch write 의 구체 동작·connection 모델·재시도 의미는 *각 Connector 의 docs 참조*. 본 문서는 그 추상을 사용자에게 균일하게 보여주는 **framework 계층**까지만 다룬다.

---

## 2. Connect 와 broker 의 경계 — 자원 분리

### 2.1. 통신 구간별 책임

| 구간 | 처리 주체 | 프로토콜 |
|---|---|---|
| 비즈니스 서비스 → broker | broker | Kafka wire protocol (TCP) |
| broker → Connect Worker | broker (Worker 가 consume) | Kafka wire protocol |
| **Worker → 외부 시스템** | **Connect Worker JVM 의 Source/SinkTask** | **외부 시스템별 (JDBC / HTTP / S3 SDK / ...)** |

→ **외부 시스템 connection 은 Connect Worker JVM 내부에 산다**. broker 의 메모리·CPU·네트워크는 외부 시스템 connection 부담을 0 만큼도 지지 않음.

### 2.2. 자주 오해하는 지점

| 오해 (Q) | 왜 이런 의문이 나오나 | 답 (A) |
|---|---|---|
| Connect 는 broker 안에 있나? Kafka 의 일부인가? | 이름이 "Kafka Connect" 라 한 덩어리로 보임. Confluent 패키지가 같이 묶여 있어 더 헷갈림 | **아니다.** broker 와 *완전히 별개의 JVM 프로세스 클러스터* |
| Connect 가 외부 시스템에 쓰는 connection 을 broker 가 관리하나? | "Kafka 가 다 알아서 한다" 는 인상 + Connect 가 Kafka 의 부속처럼 보임 | **broker 는 외부 connection 을 전혀 모른다.** connection 은 Connect Worker JVM 내부에서 관리 |
| Connect 클러스터를 띄우면 broker 자원이 더 들지 않나? | Kafka 한 덩어리라는 오해 + broker 도 이미 무거운데 추가 부하 우려 | **broker 자원은 그대로**. Connect 는 *별도 노드/Pod* 에 띄워 자원 분리 |

---

## 3. 고가용성 (Distributed Mode)

> 출처: 동일 (Confluent Connect Concepts)

### 3.1. 자동 rebalance

핵심 인용:
> *"If you add a worker, shut down a worker, or a worker fails unexpectedly, the rest of the workers acknowledge this and coordinate to redistribute connectors and tasks across the updated set of available workers."*
> *"Behind the scenes, connect workers use consumer groups to coordinate and rebalance."*

→ Worker 가 죽으면 살아있는 Worker 들이 그 task 를 자동 인계. **별도 클러스터 매니저(ZooKeeper, etcd) 불필요** — Kafka 의 컨슈머 그룹 프로토콜을 그대로 재사용.

### 3.2. 상태 저장소 = Kafka 내부 토픽 3 종

> *"a task's state is stored in special topics in Kafka, `config.storage.topic` and `status.storage.topic`, and managed by the associated connector."*

| 토픽 (설정 키) | 저장 내용 |
|---|---|
| `config.storage.topic` | Connector 설정 |
| `offset.storage.topic` | Source Connector 의 외부 시스템 offset (Sink 는 컨슈머 그룹 offset 사용) |
| `status.storage.topic` | Connector / Task 의 running·paused·failed 상태 |

→ Worker 가 전부 죽었다 살아나도 **Kafka 토픽에 상태가 보존되어 마지막 지점부터 재개**.

### 3.3. 한계 (정직하게)

공식 문서가 명시한 한계:
> *"failed tasks themselves don't trigger rebalancing — only worker failures do."*

→ **task 가 예외로 죽어도 자동 rebalance 일어나지 않음**. Worker 단위 장애만 자동 복구. Task-level 실패는:
- `errors.retry.timeout` 으로 재시도
- `errors.tolerance=all` + DLQ (`errors.deadletterqueue.topic.name`) 로 격리
- 모니터링/알림으로 사람이 인지

---

## 4. 시스템 자원 산정

> 본 절은 운영 가이드라인 — 일부는 **(개인 정리)**. 정확한 수치는 워크로드 의존이며 공식 표는 없음.

### 4.1. broker 와 분리된 자원
- broker cluster 와 Connect cluster 는 **서로 다른 노드(Pod / VM)** 에 띄움
- broker: 디스크 I/O · 페이지 캐시 위주
- Connect Worker: CPU · heap · 외부 시스템 IO 위주
- 결과: **자원 경합 없음**. 한쪽 부하가 다른 쪽 성능을 흔들지 않음

### 4.2. 산정 가이드 (개인 정리)

| 항목 | 결정 기준 |
|---|---|
| **Worker JVM heap** | 4~8GB 권장. 메시지 크기·batch.size·SMT 부담에 따라 조정 |
| **Worker 수** | **HA 위해 N ≥ 3** (한 대 죽어도 task 재배치 가능) |
| **CPU** | task 수 × SMT 부담. 일반적인 Sink 라면 worker 당 2~4 vCPU 충분 |
| **`tasks.max`** | min(외부 시스템이 견디는 동시 처리, 토픽 파티션 수) |
| **네트워크** | broker ↔ worker, worker ↔ 외부 시스템 두 방향 모두 측정 |

→ 외부 시스템별 connection 동시성·풀 한도 산정은 *각 Connector docs* 와 *본인 환경의 한계치* 에 따라 별도 결정. (예: DB sink 는 [3. DB Sink 시나리오 Q&A](./3_db_sink_qna.md) §4 참조)

### 4.3. 운영 환경별
- **K8s + Strimzi**: `KafkaConnect` CR 로 worker replica 수·resource limit 선언
- **K8s + CfK (Confluent for Kubernetes)**: `Connect` CR 동일
- **자체 운영**: Worker JVM 을 systemd / VM 으로 직접 운영 (HA 직접 책임)

---

## 5. 자주 겪는 함정 (sink-agnostic)

> 본 절은 **(개인 정리)**. 운영 시 챙길 체크리스트 성격. 외부 시스템 종류와 무관한 일반적 함정만 다룸.

| 함정 | 증상 | 대처 |
|---|---|---|
| `batch.size` ≫ `consumer.max.poll.records` | batch 효과 약화 | `consumer.override.max.poll.records` 로 동기화 |
| `tasks.max` > 토픽 파티션 수 | 잉여 task 가 idle | `tasks.max ≤ partitions` |
| `tasks.max` 가 외부 시스템 한도 초과 | 외부 시스템 거부·지연 | 외부 시스템 동시성 한도와 맞춰 산정 |
| task 실패 시 rebalance 안 됨 | 일부 데이터만 적재 안 됨 | DLQ + task-status 알림 필수 |
| 단일 Worker 운영 | Worker 죽으면 적재 정지 | distributed mode + Worker ≥ 3 |

---

## 6. 본 조직에서의 위치

> Cf. [실습/5. 설계](../practice/5_design.md) — Connect 는 **Connector 선언형 YAML** 로 `kafka-platform/connectors/` 에 들어간다.

- 단순 변환 + 외부 적재는 Connect 로 처리 → consumer 코드 0 줄
- 복잡한 변환·집계가 필요하면 별도 도메인 서비스로 분리
- *기술 계층(Producer/Consumer)* 으로 리포를 가르지 않고, *도메인* 으로 가른다는 platform 설계 원칙은 그대로 유지

→ sink 가 DB 인 구체 시나리오에서 떠오르는 의문은 [3. DB Sink 시나리오 Q&A](./3_db_sink_qna.md) 참조.

---

## 7. 참고 (출처)

### 1차 출처 (Apache / Confluent 공식)
- [Apache Kafka 공식 — Kafka Connect 챕터](https://kafka.apache.org/documentation/#connect)
- [Confluent — Kafka Connect Concepts](https://docs.confluent.io/platform/current/connect/concepts.html)
- [Confluent — Single Message Transforms Overview](https://docs.confluent.io/platform/current/connect/transforms/overview.html)
