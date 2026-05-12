---
title: "3. DB Sink 시나리오 Q&A"
weight: 3
date: 2026-05-02
---

> 본 문서는 sink = **관계형 DB** 라는 구체 시나리오에서 Connect 도입 시 떠올린 의문과 그 답을 정리한다.
> Connect 의 일반 개념은 [1. Connect 개념](./1_concept.md), 모니터링 일반론은 [2. 모니터링](./2_monitoring.md).
> 본 문서는 *DB 적재* 라는 케이스에 한정해 — connection 산정, schema 변환, batch insert, DB 측 모니터링, "그냥 직접 짜면 안 되나?" 같은 의문을 다룬다.

---

## 1. 시나리오

본 조직의 적재 요구:

```text
[Service A]                                                   ┌──→ [Postgres]
[Service B] ──→ [Kafka Broker] ←── [Connect Worker Cluster] ──┤
[ ...     ]                       (JDBC Sink Connector)       └──→ (필요 시 ES/S3 등 추가)
```

요구사항 (이전 프로젝트에서 직접 짠 consumer 가 했던 일):
- **DB schema 에 맞춘 필드 매핑·타입 변환**
- **Batch insert** (모아서 한 번에 INSERT — DB 부담·throughput 최적화)
- **DB connection 재사용** (매 레코드마다 새 connection 여는 것 방지)
- **장애 격리** (DB 가 느려져도 비즈니스 서비스에 영향 없게)

→ 이 4 개를 Connect 가 모두 받아낼 수 있는가? — 결론은 **그렇다** (자세히는 §3).

---

## 2. 핵심 의문 — Q&A

### 2.1. "왜 Kafka 를 거치는가" 에 대한 의문

| 의문 (Q) | 왜 이런 의문이 나오나 | 답 (A) |
|---|---|---|
| 어차피 누군가 DB connection 을 들어야 한다면, **그냥 produce 하는 곳에서 바로 INSERT 하지** 왜 Kafka 를 거치나? | Connect 도 connection 을 들어야 하니, "분리" 의 이득이 없어 보임 | 핵심은 *connection 자원의 위치*. **비즈니스 서비스에서 DB conn 을 떼어내는 것** 자체가 Kafka 의 가치 — DB 장애 격리, 버퍼, 트래픽 평탄화, 재처리, fan-out (자세히는 §3) |
| 그럴 거면 직접 consumer 짜는 거랑 Connect 는 뭐가 다른가? | 어차피 둘 다 별도 프로세스에서 connection 들고 INSERT 하니 똑같아 보임 | **분리 효과는 동일**. 차이는 *코드를 짤 거냐, 선언형 설정으로 처리할 거냐* 뿐 (자세히는 §4) |

### 2.2. 기능적 한계에 대한 의문

| 의문 (Q) | 왜 이런 의문이 나오나 | 답 (A) | 자세히 |
|---|---|---|---|
| Connect 는 매 레코드마다 DB connection 을 새로 여나? | "자동" 이라 비효율적일 거란 직관적 우려 | **아니다.** task 당 단일 JDBC connection 을 유지·재사용 | §5 |
| DB schema 에 맞춰 필드 매핑·타입 변환을 Connect 로 할 수 있나? | 직접 consumer 에서는 자바 코드로 자유롭게 했음 | **단순 변환은 SMT(Single Message Transforms) 로 가능** — 필드 rename, cast, mask, filter, route 등 | [Confluent SMT](https://docs.confluent.io/platform/current/connect/transforms/overview.html), [1. Connect 개념 §1.5](./1_concept.md) |
| Batch insert 를 Connect 가 알아서 해주나? | "모아서 한 번에 INSERT" 는 직접 짠 consumer 의 핵심 최적화였음 | **JDBC Sink Connector 가 자체 지원.** `batch.size` 디폴트 3000 | [JDBC Sink config](https://docs.confluent.io/kafka-connectors/jdbc/current/sink-connector/sink_config_options.html) |
| 변환이 복잡하면(여러 메시지 join, 외부 lookup, 집계) Connect 만으로 안 되지 않나? | SMT 가 단일 레코드 변환만 다룸 | **그렇다.** 그 경우엔 Kafka Streams 로 사전 변환 토픽 만들거나, 별도 도메인 서비스(`log-ingestion-service`) 로 분리 | §4.4 |

### 2.3. DB 운영 측면 의문

| 의문 (Q) | 왜 이런 의문이 나오나 | 답 (A) | 자세히 |
|---|---|---|---|
| Connect 클러스터의 동시 connection 수가 DB max_connections 를 깨지 않나? | task × Worker 수가 곱해져서 폭증할 수 있음 | **`tasks.max × Worker 수` 가 동시 connection 상한**. DB 풀 한도와 맞춰 산정 | §5 |
| DB connection 자체를 모니터링할 수 있나? (TCP 지연, active/idle conn 수) | 직접 짠 consumer 에서는 HikariCP 메트릭으로 봤음 | **Connect 의 표준 JMX 에는 connection pool 메트릭 없음** *(개인 추론)*. `put-batch-time-ms` 로 간접 추정 + DB 측 exporter 로 보완 | §6 |
| DB 가 잠깐 죽으면 Connect 도 죽나? | 강결합으로 보일 수 있음 | **task 가 retry 하다 `errors.tolerance` 정책에 따라 동작**. `retry.timeout` 동안 재시도 → 실패 시 DLQ 또는 task FAILED. 비즈니스 서비스는 무관 | §6 |

---

## 3. 왜 Kafka 를 거치는가 — 분리(decoupling)가 본질

### 3.1. 두 구조 비교

| 구조 | DB connection 보유 주체 | 비즈니스 서비스 부담 |
|---|---|---|
| **A. produce 측에서 바로 INSERT** | 비즈니스 서비스 | DB 장애·느림·락 즉시 전파. 응답 지연 |
| **B. Kafka 경유 → Connect → DB** | Connect 클러스터. **비즈니스 서비스 0** | 0 — Kafka 에 produce 끝. DB 가 죽어도 무관 |

→ Kafka 를 쓰는 이유 = **DB connection 을 비즈니스 서비스에서 떼어내는 것 자체**. Connect 든 직접 짠 consumer 든 *"비즈니스 측이 아닌 별도 프로세스가 connection 을 듦"* 효과는 동일.

### 3.2. Kafka 가 추가로 사주는 것

- **버퍼**: DB 가 잠깐 죽어도 Kafka 에 적체 → 복구 후 천천히 소진
- **트래픽 평탄화**: 피크에 produce 만 빠르게 응답. 적재는 뒤에서 자기 속도로
- **재처리**: offset reset 으로 동일 토픽 재적재 (스키마 변경 시 유용)
- **fan-out**: 같은 로그를 DB · ES · S3 등 여러 sink 로 동시 분기 (Connect 면 connector 한 줄 추가)
- **장애 격리**: DB 장애 → 적재 지연. 비즈니스 서비스 영향 0

---

## 4. Connect vs 직접 짠 Consumer

### 4.1. 비교 표

| 측면 | 직접 짠 Consumer | Connect Sink (JDBC) |
|---|---|---|
| 분리 효과 (Kafka 본질) | ✅ | ✅ — **동일** |
| 변환 (필드 rename·cast·mask 등) | 코드로 작성 | SMT 설정 |
| Batch insert | 직접 구현 (JDBC PreparedStatement + addBatch) | `batch.size` 한 줄 |
| Connection pool | HikariCP 등 직접 도입·튜닝 | Connector 가 task 당 단일 connection 유지 |
| Retry / DLQ | 직접 구현 | `errors.retry.timeout`, `errors.deadletterqueue.topic.name` 한 줄씩 |
| Offset 관리 | 직접 (auto-commit / 수동) | Framework 자동 |
| 코드 리포 | **예** (도메인 서비스 1 개) | **아니오** (`kafka-platform/connectors/*.yaml`) |
| 변환 자유도 | 무제한 | SMT 범위 (단순 변환). 복잡하면 별도 서비스 |

### 4.2. Connect 를 우선 선택하는 기준

다음을 *모두* 만족하면 Connect:
1. 변환 로직이 SMT 범위 안에 들어옴 (필드 rename·cast·mask·filter·route)
2. Batch insert·retry·DLQ 의 표준 동작이 비즈니스 요구를 만족
3. DB schema 가 비교적 안정적 (스키마 변경 빈도가 낮음)

### 4.3. 직접 Consumer 를 선택해야 하는 경우

- 여러 메시지를 join 해서 한 행으로 만들어야 함
- 외부 lookup (캐시·다른 DB 조회) 가 매 레코드마다 필요
- 비즈니스 검증 로직이 복잡 (예: 위반 시 다른 토픽으로 라우팅)
- 배치 INSERT 안에서 추가 트랜잭션 처리 (예: 자체 ID 시퀀스 발급)

→ 이 경우엔 별도 도메인 서비스(`log-ingestion-service` 같은) 로 분리.

### 4.4. Streams 로 보조하는 패턴

복잡한 변환이지만 *DB 적재 자체는 단순* 한 경우:

```text
원천 토픽 → Kafka Streams (join · 집계 · 외부 lookup) → 변환된 토픽 → Connect JDBC Sink → DB
```

→ "복잡한 변환" 과 "외부 적재" 를 *각자 강한 도구* 에 맡기는 표준 패턴.

---

## 5. DB Connection 산정

### 5.1. Connection 모델

- **JDBC Sink Connector** 는 task 당 단일 JDBC connection 을 유지·재사용 *(개인 추론 — Apache 2.0 소스 기반의 일반 사실이지만 공식 docs 한 줄 인용은 미확보. 정확히는 [confluentinc/kafka-connect-jdbc](https://github.com/confluentinc/kafka-connect-jdbc) 의 `JdbcSinkTask` 코드 참조)*
- 따라서 **동시 DB connection 상한 ≈ `tasks.max × Worker 수`** *(개인 추론)*

### 5.2. 산정 절차

1. DB 의 `max_connections` 와 *현재 사용 중* 인 connection 수 파악
2. Connect 에 줄 수 있는 여유분 결정 (예: 50)
3. `tasks.max × Worker 수 ≤ 여유분` 을 만족하도록 설정
   - 예: Worker 3 대, 여유분 50 → `tasks.max ≤ 16`
4. **`tasks.max ≤ 토픽 partition 수`** 도 함께 만족 (그렇지 않으면 잉여 task idle)

### 5.3. 함정

| 함정 | 증상 | 대처 |
|---|---|---|
| `tasks.max × Worker 수 > DB max_connections` | DB connection 거부, task FAILED | DB 풀 한도와 맞춰 재산정 |
| 여러 connector 가 같은 DB 를 향함 | 모든 connector 의 task 합이 max_connections 를 침범 | DB 단위로 합계 관리 |
| DB 측에 `pgbouncer` 등 풀러가 있음 | 이중 풀링 → idle connection 누적 | pgbouncer 모드를 transaction 으로, 또는 Connect 측에서 idle timeout 설정 |

---

## 6. DB 측 모니터링 보완

> Connect JMX 에는 **connection pool 활성/대기 connection 수가 노출되지 않음** *(개인 추론. 공식 메트릭 표에서 확인 안 됨)*. 따라서 *connection 자체* 의 정밀 모니터링은 DB 측에서 본다.

### 6.1. Connect 측 간접 지표

| Connect JMX | DB 측에서 의심해 볼 것 |
|---|---|
| `put-batch-avg-time-ms` 급증 | DB CPU, lock, slow query, network 지연 |
| `put-batch-max-time-ms` ≫ avg | 일부 query 가 hang 또는 락 대기 |
| `sink-record-active-count` 누적 | DB 처리 한계 도달 (back-pressure) |
| Task FAILED, retry 증가 | DB connection 거부 / 인증 만료 / disk full |

### 6.2. DB 측 도구 (Postgres 예)

| 도구 | 보는 것 |
|---|---|
| `pg_stat_activity` | 활성 query, idle in transaction, lock 대기 |
| `pg_stat_database` | commit / rollback / deadlock 추세 |
| `postgres_exporter` (Prometheus) | active/idle connection 수, transaction rate, replication lag |
| `pg_stat_statements` | 느린 query 식별 |

### 6.3. MySQL 의 경우

- `SHOW PROCESSLIST` / `performance_schema`
- `mysqld_exporter`

### 6.4. 표준 알람 (DB 측)

> *(개인 정리)*

| 알람 | 임계 (개인 정리) | 의미 |
|---|---|---|
| Connect 계정의 active connection 수 | `tasks.max × Worker 수` 의 80% 초과 지속 | 풀 부족 임박 |
| `idle in transaction` 수 | > 10 지속 5 분 | task 가 commit 안 하고 떠 있음 (의심 상황) |
| commit/sec | 평소 대비 ×2 | INSERT 속도 비정상 (피크 또는 retry 폭주) |
| deadlock 발생 | > 0 | 동시 INSERT 가 같은 행을 침범. partition 키 또는 batch 전략 점검 |

→ *Connect 측 알람 + DB 측 알람을 함께 봐야* 원인이 분리됨. (자세히는 [2. 모니터링 §5](./2_monitoring.md))

---

## 7. 본 조직 적용 — 구체 결정 (잠정)

> 본 절은 *현재 조직 결정 상태*. 미정 항목은 그대로 표기.

| 항목 | 결정 |
|---|---|
| Sink Connector | **JDBC Sink Connector** (Confluent) |
| Worker mode | distributed, N ≥ 3 |
| `tasks.max` 초기값 | min(파티션 수, DB 여유 connection / Worker 수) |
| `batch.size` | default 3000 부터 시작, `put-batch-time-ms` 보며 조정 |
| Converter | Avro + Schema Registry — *(Schema Registry 도구 미정)* |
| 변환 | SMT (필드 rename·cast·mask) 까지만 → 더 복잡하면 별도 서비스 |
| DLQ | `errors.tolerance=all` + DLQ 토픽 (`<connector>.dlq`) |
| Retry | `errors.retry.timeout` 적정값 — *(미정, 도입 시 결정)* |
| DB 풀 한도 결정 | DBA 와 협의 — *(미정)* |
| DB 측 exporter | postgres_exporter — *(MySQL 인지 PG 인지 환경 결정 후)* |

---

## 8. 참고 (출처)

### 1차 출처 (공식)
- [Confluent — Kafka Connect Concepts](https://docs.confluent.io/platform/current/connect/concepts.html)
- [Confluent — JDBC Sink Connector configuration](https://docs.confluent.io/kafka-connectors/jdbc/current/sink-connector/sink_config_options.html)
- [Confluent — Single Message Transforms Overview](https://docs.confluent.io/platform/current/connect/transforms/overview.html)

### 소스 (직접 검증 권장)
- [confluentinc/kafka-connect-jdbc (GitHub)](https://github.com/confluentinc/kafka-connect-jdbc) — connection 관리·batch 동작의 정확한 코드 확인용

### 본 사이트 내 관련 문서
- [1. Connect 개념](./1_concept.md) — Connect 일반 개념·HA·자원
- [2. 모니터링](./2_monitoring.md) — JMX·Lag·표준 스택
- [실습/5. 설계](../practice/5_design.md) — Connector YAML 위치 (`kafka-platform/connectors/`)
