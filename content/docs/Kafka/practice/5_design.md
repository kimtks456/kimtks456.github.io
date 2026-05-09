---
title: "5. 설계"
weight: 5
date: 2026-05-09
---

> SI 환경 공통 플랫폼. 운영 환경은 단순 배포 (GitOps/K8s 생략).
> 공통팀이 브로커 설정과 공통 라이브러리를 통제하고, 도메인 개발자는 가져다 쓰는 구조.
> 토픽 네이밍은 [3. Topic 설계](./3_topic_design.md), 메시지 포맷은 [4. Message Format 설계](./4_message_format.md) 참조.

---

## 1. 리포 구성 (2개)

| 리포 | 담당 | 목적 |
|---|---|---|
| **`kafka-platform`** | 공통팀 | 브로커 설정, 토픽 선언, Connect 설정, 로컬 테스트 환경 |
| **`kafka-common-lib`** | 공통팀 | Producer/Consumer client 라이브러리, 이벤트 POJO, 멱등성 처리 |

도메인 서비스는 `kafka-common-lib` 를 Maven/Gradle 의존성으로 가져다 쓴다.

---

## 2. Kafka 설정 — Hard vs Soft 구분

### Hard 설정 (변경 불가 — 공통팀만 통제)

> 안정성·데이터 정합성에 직결. `kafka-common-lib` 내 Config 클래스에서 강제 적용 — 도메인 서비스에서 오버라이드해도 lib 설정이 우선.

| 설정 | 값 | 이유 |
|---|---|---|
| `acks` | `all` | 리더 + ISR 전체 확인 → 데이터 유실 방지 |
| `enable.idempotence` | `true` | 재시도 중복 방지 |
| `max.in.flight.requests.per.connection` | `5` | `idempotence=true` 필수 제약값 |
| `min.insync.replicas` | `2` | 브로커 1대 장애 시에도 쓰기 보장 (브로커 3대 전제) |
| `replication.factor` | `3` | 브로커 3대 기준 기본값 |

### Soft 설정 (서비스별 조정 가능)

> `kafka-common-lib` 에 기본값 제공, 도메인 서비스가 `application.yml` 에서 오버라이드 가능.

| 설정 | 기본값 | 용도 |
|---|---|---|
| `linger.ms` | `20` | 배치 대기시간 — 처리량↑ vs 지연↑ 트레이드오프 |
| `batch.size` | `16384` (16KB) | 배치 크기 — payload 크기에 맞게 조정 |
| `max.poll.records` | `500` | consumer 1회 poll 최대 레코드 수 |
| `session.timeout.ms` | `30000` | consumer group 이탈 판단 시간 |
| `compression.type` | `snappy` | 처리량 많을 때 네트워크 절감 |

---

## 3. `kafka-platform` 패키지 트리

```text
kafka-platform/
├── brokers/
│   └── server.properties                # 브로커 공통 설정 참고본 (Hard 설정 주석 포함)
│
├── topics/                              # 토픽 선언 YAML — 토픽 추가 시 이 파일만 추가
│   ├── order/
│   │   ├── order.created.v1.yaml
│   │   └── order.cancelled.v1.yaml
│   └── log/
│       └── system.log.v1.yaml           # Connect DB sink 대상 로그 토픽
│
├── scripts/
│   └── create-topics.sh                 # topics/ YAML을 읽어 토픽 자동 생성
│
├── connectors/
│   └── db-sink/
│       ├── system-log-sink.json         # JDBC Sink Connector 설정
│       ├── system_log.ddl.sql           # 테이블 DDL
│       └── README.md                    # bulk insert 동작 원리, 환경변수 설명
│
└── test/
    ├── docker-compose.yml               # 로컬 개발용 (Kafka + Kafka UI + Redis + Nexus)
    ├── .env.dev                         # 로컬 개발 환경변수 (커밋)
    └── .env.qa                          # QA 환경변수 (커밋, 시크릿 제외)
```

### 토픽 선언 예시 (`order.created.v1.yaml`)

```yaml
name: prd.order.created.v1
partitions: 6
replication-factor: 3
configs:
  retention.ms: 604800000       # 7일
  min.insync.replicas: "2"      # Hard 설정
  cleanup.policy: delete
```

### `test/docker-compose.yml` — 로컬 개발 환경

환경별로 다른 값(`KAFKA_HOST` 등)은 `.env.dev` / `.env.qa` 파일로 분리, `--env-file` 로 주입한다.

```bash
# 로컬 개발
docker compose --env-file .env.dev up -d
```

구성 서비스:

| 서비스 | 포트 | 비고 |
|--------|------|------|
| Kafka (KRaft) | 9092 | ZooKeeper 불필요 |
| Kafka UI | 8989 | `http://localhost:8989` |
| Redis | 6379 | 멱등성 store |
| Nexus | 8081 | `http://localhost:8081` |

토픽은 `KAFKA_AUTO_CREATE_TOPICS_ENABLE=false` 로 자동 생성 비활성화.  
대신 `init-kafka` 컨테이너가 Kafka healthcheck 통과 후 `scripts/create-topics.sh` 를 실행해 `topics/` YAML 을 읽어 생성한다.

```
Kafka healthy → init-kafka → create-topics.sh → topics/*.yaml 루프 → kafka-topics.sh --create --if-not-exists
```

`--if-not-exists` 로 재시작 시 충돌 없음. 단 **config 변경(retention 등)은 자동 반영 안 됨** — `kafka-configs.sh --alter` 또는 `down -v` 후 재기동 필요.

### JDBC Sink Connector 설정 (`system-log-sink.json`)

**1초 OR 10개** 단위로 묶어 단일 bulk INSERT 로 flush 한다.

```json
{
  "name": "system-log-sink",
  "config": {
    "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
    "tasks.max": "1",
    "topics": "prd.log.system.v1",
    "connection.url": "${env:DB_URL}",
    "connection.user": "${env:DB_USER}",
    "connection.password": "${env:DB_PASSWORD}",
    "insert.mode": "insert",
    "auto.create": "false",
    "auto.evolve": "false",
    "table.name.format": "system_log",
    "pk.mode": "none",
    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
    "value.converter.schemas.enable": "false",
    "batch.size": "10",
    "consumer.override.max.poll.records": "10",
    "consumer.override.fetch.min.bytes": "1024",
    "consumer.override.fetch.max.wait.ms": "1000",
    "transforms": "rename,drop",
    "transforms.rename.type": "org.apache.kafka.connect.transforms.ReplaceField$Value",
    "transforms.rename.renames": "eventId:event_id,aggregateId:aggregate_id,serviceId:service_id,occurredAt:occurred_at",
    "transforms.drop.type": "org.apache.kafka.connect.transforms.ReplaceField$Value",
    "transforms.drop.exclude": "context"
  }
}
```

| 설정 | 값 | 역할 |
|------|----|------|
| `batch.size` | 10 | INSERT 1문장에 묶을 행 수. 없으면 10번 개별 실행 |
| `consumer.override.max.poll.records` | 10 | poll() 1회 최대 레코드 수 |
| `consumer.override.fetch.min.bytes` | 1024 | 브로커가 응답 전 최소 버퍼 (≈10개 분량) |
| `consumer.override.fetch.max.wait.ms` | 1000 | fetch.min.bytes 미충족 시 최대 대기 ms |
| `transforms` | rename, drop | camelCase→snake_case 리네임, Map 타입 context 필드 제거 |

> `auto.create=false` — DDL(`system_log.ddl.sql`)은 별도 관리. Connect가 테이블을 자동 생성하지 않음.  
> 상세 동작 원리는 [Kafka Connect — DB Sink Q&A](../connect/3_db_sink_qna.md) 참조.
> → JDBC Sink Connector 상세 동작은 [Kafka Connect — DB Sink Q&A](../connect/3_db_sink_qna.md) 참조.

---

## 4. `kafka-common-lib` 패키지 트리

```text
kafka-common-lib/
├── build.gradle
│
└── src/main/java/.../kafka/
    ├── config/
    │   ├── KafkaProducerConfig.java     # Hard 설정 강제 (acks=all, idempotence)
    │   └── KafkaConsumerConfig.java     # isolation.level, Soft 설정 기본값
    │
    ├── events/                          # 이벤트 POJO (도메인별 패키지)
    │   ├── order/
    │   │   ├── OrderCreatedEvent.java
    │   │   └── OrderCancelledEvent.java
    │   └── log/
    │       └── SystemLogEvent.java      # Connect DB sink 대상 로그 이벤트
    │
    ├── idempotency/                     # annotation 기반 Redis 멱등성
    │   ├── IdempotentConsumer.java      # @annotation 정의
    │   ├── IdempotencyAspect.java       # AOP — annotation 감지·Redis 체크·skip
    │   └── IdempotencyRedisStore.java   # Redis SET NX + TTL
    │
    ├── error/
    │   └── DltPublisher.java            # Dead Letter Topic 발행
    │
    └── serde/
        └── JsonEventSerializer.java     # ObjectMapper 설정 (날짜 포맷 등)
```

---

## 5. `/events` — 이벤트 POJO 설계

> JSON schema 는 코드 자체가 스키마. Schema Registry 없이 Jackson 직렬화.
> JVM 환경 전제 (non-JVM 서비스가 있다면 [4. Message Format 설계](./4_message_format.md) 에서 재검토 필요).

### 비즈니스 이벤트 예시 (`OrderCreatedEvent.java`)

```java
public record OrderCreatedEvent(
    String eventId,          // UUID — 멱등성 키
    String aggregateId,      // orderId
    String customerId,
    List<OrderItem> items,
    BigDecimal totalAmount,
    Instant occurredAt
) {}
```

### 로그 이벤트 (`SystemLogEvent.java`)

```java
public record SystemLogEvent(
    String eventId,
    String serviceId,                  // 시스템 식별자 (예: "order-service")
    String level,                      // INFO / WARN / ERROR
    String message,
    Map<String, String> context,       // 추가 컨텍스트 (traceId 등)
    Instant occurredAt
) {}
```

### 호환성 규칙

| 변경 종류 | 처리 |
|---|---|
| 필드 추가 | Consumer 가 모르는 필드를 무시하면 OK. 추가 후 consumer 먼저 배포 |
| 필드 삭제·타입 변경 | **v2 토픽 신규 생성** — 하위 호환 파괴이므로 기존 토픽 수정 금지 |
| 필드명 변경 | 삭제 + 추가로 취급 → v2 |

---

## 6. `/idempotency` — annotation 기반 Redis 멱등성

### annotation 정의 (`IdempotentConsumer.java`)

```java
@Target(ElementType.METHOD)
@Retention(RetentionPolicy.RUNTIME)
public @interface IdempotentConsumer {
    IdempotencyKey keyType() default IdempotencyKey.EVENT_ID;
    long ttlSeconds() default 86400;   // 24h
}

public enum IdempotencyKey {
    EVENT_ID,       // eventId 기준 (기본 — 이벤트 중복 방지)
    AGGREGATE_ID    // aggregateId 기준 (예: orderId — 집계 단위 중복 방지)
}
```

### AOP 처리 흐름

```text
@KafkaListener 메서드 호출
        │
        ▼
IdempotencyAspect.around()
        │
        ├── keyType 에 따라 eventId 또는 aggregateId 추출
        │
        ├── Redis SET NX "idempotency:{key}" 1 EX {ttlSeconds}
        │       │
        │       ├── SET 성공 (처음 처리) → proceed() → 실행
        │       │
        │       └── SET 실패 (이미 처리됨) → skip (return, offset commit)
        │
        └── 비즈니스 예외 발생 시 → Redis key 삭제 후 DLT 발행
```

### 사용 예시 (도메인 서비스)

```java
@KafkaListener(topics = "prd.order.created.v1", groupId = "payment-service")
@IdempotentConsumer(keyType = IdempotencyKey.EVENT_ID, ttlSeconds = 86400)
public void handle(OrderCreatedEvent event) {
    // 중복 eventId 면 AOP 가 이 메서드 자체를 실행하지 않음
    paymentService.processPayment(event);
}
```

---

## 7. `/error` — DLT 설계

### 케이스별 처리

| 케이스 | 처리 |
|---|---|
| 역직렬화 실패 | DLT 로 raw bytes 발행 후 offset commit |
| 비즈니스 예외 | DLT 발행 후 offset commit (무한 재시도 방지) |
| 멱등성 중복 감지 | skip — DLT 발행 없음 |

### DLT 토픽 네이밍

```text
prd.order.created.v1  →  (처리 실패)  →  prd.order.created.v1.DLT
```

### DLT 메시지 헤더

| 헤더 | 내용 |
|---|---|
| `X-Exception-Message` | 예외 메시지 |
| `X-Original-Topic` | 원본 토픽명 |
| `X-Original-Offset` | 원본 offset |
| `X-Original-Partition` | 원본 partition |
| `X-Failed-At` | 실패 시각 (ISO-8601) |

---

## 8. 로그 이벤트 스키마 귀속 — 분석

**질문**: 각 시스템 로그를 Kafka → DB sink 할 때, 로그 이벤트 스키마를 `/events/log/` POJO 로 정의해야 하나, Connect 설정(SMT)에서만 처리해야 하나?

| 방식 | 특징 | 적합한 경우 |
|---|---|---|
| **A. `/events/log/` POJO 정의** | 스키마가 Java 코드로 명시. producer type-safe. Connect 는 단순 sink. | 로그 필드가 공통 표준화 가능한 경우. 모든 서비스가 common-lib 사용하는 경우 |
| **B. `Map<String, Object>` 로 publish** | POJO 없이 자유 형태. Connect SMT 로 field mapping. | 서비스마다 로그 구조가 달라서 공통화 불가한 경우 |

**본 설계 채택: 방식 A** — 이유:
- SI 공통 플랫폼 특성상 모든 서비스가 `kafka-common-lib` 를 사용 → POJO 강제 가능
- 로그 스키마 변경이 PR 리뷰를 거쳐 추적됨 (Connect 설정만 바꾸면 추적 어려움)
- Connect 는 단순 JDBC sink 역할만 → SMT 복잡도 최소화

---

## 9. 도메인 서비스에서의 사용

```gradle
dependencies {
    implementation 'com.example:kafka-common-lib:1.x.x'
}
```

```yaml
# application.yml — Soft 설정만 오버라이드
kafka:
  bootstrap-servers: kafka-broker:9092
  producer:
    linger-ms: 50
    batch-size: 32768
```

> Hard 설정 (`acks=all`, `enable.idempotence=true` 등) 은 `KafkaProducerConfig` 에서 강제 적용.

---

## 참고 (출처)

- [apache/kafka — Docker Hub](https://hub.docker.com/r/apache/kafka)
- [provectuslabs/kafka-ui — GitHub](https://github.com/provectuslabs/kafka-ui)
- [sonatype/nexus3 — Docker Hub](https://hub.docker.com/r/sonatype/nexus3)
- [Spring Kafka — Reference Documentation](https://docs.spring.io/spring-kafka/reference/)
- [Spring AOP — Reference Documentation](https://docs.spring.io/spring-framework/reference/core/aop.html)
- [Confluent JDBC Sink Connector](https://docs.confluent.io/kafka-connectors/jdbc/current/sink-connector/overview.html)

### 본 사이트 내 관련 문서

- [3. Topic 설계](./3_topic_design.md)
- [4. Message Format 설계](./4_message_format.md)
- [6. 초기세팅](./6_init.md)
- [Kafka Connect — 개념](../connect/1_concept.md)
- [Kafka Connect — DB Sink Q&A](../connect/3_db_sink_qna.md)
