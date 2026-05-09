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
├── README.md                            # 컨벤션·온콜 연락처
│
├── brokers/
│   └── server.properties                # 브로커 공통 설정 참고본 (Hard 설정 주석 포함)
│
├── topics/                              # 토픽 선언 YAML
│   ├── order/
│   │   ├── order.created.v1.yaml
│   │   └── order.cancelled.v1.yaml
│   └── log/
│       └── system.log.v1.yaml           # Connect DB sink 대상 로그 토픽
│
├── connectors/
│   └── db-sink/
│       ├── system-log-sink.json         # JDBC Sink Connector 설정
│       └── README.md                    # DDL 분리 이유, table 자동생성 금지 이유
│
└── test/
    └── docker-compose.yml               # 로컬 개발용 (Kafka + Kafka UI + Nexus)
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

### `test/docker-compose.yml`

```yaml
version: '3.8'
services:
  kafka:
    image: apache/kafka:latest   # KRaft 모드 — ZooKeeper 별도 불필요
    container_name: kafka
    ports:
      - "9092:9092"
    environment:
      KAFKA_NODE_ID: 1
      KAFKA_PROCESS_ROLES: broker,controller
      KAFKA_LISTENERS: PLAINTEXT://:9092,CONTROLLER://:9093
      KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://localhost:9092
      KAFKA_CONTROLLER_QUORUM_VOTERS: 1@kafka:9093
      KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: PLAINTEXT:PLAINTEXT,CONTROLLER:PLAINTEXT
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 1           # 로컬 단일 브로커용
      KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR: 1
      KAFKA_TRANSACTION_STATE_LOG_MIN_ISR: 1

  kafka-ui:
    image: provectuslabs/kafka-ui:latest
    container_name: kafka-ui
    ports:
      - "8989:8080"
    environment:
      DYNAMIC_CONFIG_ENABLED: "true"
      KAFKA_CLUSTERS_0_NAME: local
      KAFKA_CLUSTERS_0_BOOTSTRAPSERVERS: kafka:9092
    depends_on:
      - kafka

  nexus:
    image: sonatype/nexus3:latest
    container_name: nexus
    ports:
      - "8081:8081"
    volumes:
      - nexus-data:/nexus-data

volumes:
  nexus-data:
```

> - Kafka: `REPLICATION_FACTOR=1`, `MIN_ISR=1` — 로컬 전용. 운영 설정과 다름.
> - Kafka UI: `http://localhost:8989`
> - Nexus: `http://localhost:8081` — 초기 설정은 [6. 초기세팅 §1.6](./6_init.md) 참조.

### JDBC Sink Connector 설정 (`system-log-sink.json`)

```json
{
  "name": "system-log-sink",
  "config": {
    "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
    "tasks.max": "2",
    "topics": "prd.log.system.v1",
    "connection.url": "${env:DB_URL}",
    "connection.user": "${env:DB_USER}",
    "connection.password": "${env:DB_PASSWORD}",
    "insert.mode": "insert",
    "auto.create": "false",
    "auto.evolve": "false",
    "table.name.format": "kafka_system_log",
    "pk.mode": "none",
    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
    "value.converter.schemas.enable": "false"
  }
}
```

> `auto.create=false` — DDL 은 별도 관리. Connect 가 테이블을 자동 생성하지 않음.
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

## 10. 라이브러리 배포 방식 — SNAPSHOT vs Release

### SNAPSHOT vs Release

> Gradle/Maven 버전 관리의 핵심 구분.

| | SNAPSHOT (`1.0.0-SNAPSHOT`) | Release (`1.0.0`) |
|---|---|---|
| 재배포 | 가능 — 같은 버전으로 계속 덮어씀 | **불가** — 동일 버전 재배포 시 Nexus 오류 |
| 소비자 동작 | 빌드마다 Nexus 에서 최신본 재확인 | 로컬 캐시 고정 |
| Nexus 레포 | `maven-snapshots` | `maven-releases` |
| 용도 | 개발 중 | 버전 확정 후 배포 |

```text
개발 중:  version = '1.0.0-SNAPSHOT'
          └── publish → maven-snapshots → 소비자가 매번 최신본 수신

릴리즈:   version = '1.0.0'
          └── publish → maven-releases → 이후 동일 버전 변경 불가
```

### Nexus 레포 구조

기본 생성되는 3개 레포:

| 레포 | 역할 |
|---|---|
| `maven-releases` | Release 버전 저장 |
| `maven-snapshots` | SNAPSHOT 버전 저장 |
| `maven-public` | 위 두 개 + Maven Central 묶은 **group 레포** — 소비자가 여기 하나만 바라봄 |

### 라이브러리 참조 방식 — 두 가지 모드

| 방식 | 설정 | 언제 |
|---|---|---|
| **직접 참조** | `implementation project(':kafka-common-lib')` | lib 개발 중 — 빌드 빠름, Nexus 불필요 |
| **Nexus 참조** | `implementation 'com.example:kafka-common-lib:1.0.0-SNAPSHOT'` | 실제 소비자 입장 검증 / 릴리즈 시 |

평소 개발은 직접 참조, Nexus 검증이 필요할 때만 한 줄 교체. 세팅 상세는 [6. 초기세팅](./6_init.md) 참조.

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
