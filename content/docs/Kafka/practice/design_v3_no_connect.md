---
title: "3. 설계v3 - Connect 제외"
weight: 3
date: 2026-05-10
---

> Aiven JDBC Connector의 운영 리스크([Connect 라이선스 이슈 → 향후 리스크](../connect/4_license.md))가 현실화될 경우,  
> Kafka Connect를 걷어내고 `log-service` Spring Boot 모듈로 대체하는 설계를 정리한다.

---

## 1. 모듈 위치 (멀티모듈 구성)

```
kafka-practice/
├── kafka-common-lib/      # 공통 라이브러리 (변경 없음)
├── order-service/         # 도메인 서비스 (변경 없음)
└── log-service/           # 신규 — Kafka → DB 적재 전담 서비스
```

`settings.gradle.kts`:
```kotlin
include("kafka-common-lib", "order-service", "log-service")
```

---

## 2. 패키지 트리

```
log-service/
└── src/
    ├── main/
    │   ├── java/com/example/log/
    │   │   ├── LogServiceApplication.java      # @SpringBootApplication
    │   │   ├── domain/
    │   │   │   └── SystemLog.java              # JPA 엔티티
    │   │   ├── repository/
    │   │   │   └── SystemLogRepository.java    # Spring Data JPA
    │   │   └── kafka/
    │   │       └── SystemLogConsumer.java      # @KafkaListener + @IdempotentConsumer
    │   └── resources/
    │       ├── application.yaml               # 공통 설정
    │       └── application-dev.yaml           # 로컬 개발 설정
    └── test/
        └── java/com/example/log/
            ├── LogServiceApplicationTests.java
            └── kafka/
                └── SystemLogFlowTest.java     # Testcontainers 통합 테스트
```

---

## 3. 핵심 클래스

### SystemLogConsumer

```java
@Component
public class SystemLogConsumer {

    @KafkaListener(topics = "prd.log.system.v1", groupId = "log-service")
    @IdempotentConsumer(keyType = IdempotencyKey.EVENT_ID, ttlSeconds = 86400)
    public void handle(SystemLogEvent event) {
        repository.save(SystemLog.from(event));
    }
}
```

- `@IdempotentConsumer` — kafka-common-lib의 Redis 기반 멱등성 AOP 그대로 재사용
- `@KafkaListener` — Kafka Connect 없이 Spring Kafka로 직접 소비

### SystemLog (JPA 엔티티)

```java
@Entity
@Table(name = "system_log")
public class SystemLog {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "event_id", nullable = false, unique = true)
    private String eventId;

    @Column(name = "service_id", nullable = false)
    private String serviceId;

    private String level;       // INFO / WARN / ERROR

    @Column(columnDefinition = "TEXT")
    private String message;

    @Column(name = "context_json", columnDefinition = "TEXT")
    private String contextJson; // Map<String,String> → "key=val,..." 형태

    @Column(name = "occurred_at")
    private Instant occurredAt;

    public static SystemLog from(SystemLogEvent event) { ... }
}
```

---

## 4. Kafka → DB 흐름

```
도메인 서비스 (order-service 등)
    │
    │  kafkaTemplate.send("prd.log.system.v1", eventId, SystemLogEvent)
    ▼
Kafka (prd.log.system.v1 토픽)
    │
    ▼
log-service :: SystemLogConsumer.handle(SystemLogEvent)
    │
    ├── IdempotencyAspect → Redis SET NX "idempotency:{eventId}"
    │       중복이면 skip, 신규면 proceed
    │
    ▼
SystemLogRepository.save(SystemLog.from(event))
    │
    ▼
PostgreSQL :: system_log 테이블
```

---

## 5. Kafka Connect와의 비교

| 항목 | Kafka Connect (JDBC Sink) | log-service |
|------|--------------------------|-------------|
| 커넥터 의존 | Aiven JDBC Connector 필요 | **없음** |
| 커스텀 이미지 | buildx로 직접 빌드 | **불필요** |
| 멱등성 | Connect 내장 (offset 기반) | `@IdempotentConsumer` |
| 변환 로직 | SMT (제한적) | **Java 코드로 자유롭게** |
| 테스트 | Connect Worker 환경 필요 | **Testcontainers로 단독 테스트** |
| 배포 | Connect Worker 컨테이너 | Spring Boot JAR (기존 패턴) |

---

## 6. 테스트 전략

### SystemLogFlowTest (통합 테스트)

| 테스트 | 검증 내용 |
|--------|-----------|
| `로그이벤트_발행후_DB_저장` | 발행 → DB 저장 E2E, 저장된 필드값 일치 확인 |
| `중복_eventId_한번만_저장` | 동일 eventId 2회 발행 → DB row 1개만 생성 |
| `다른_serviceId_이벤트_각각_저장` | 서로 다른 이벤트 → 각각 저장 (count=2) |
| `다양한_레벨_이벤트_모두_저장` | INFO/WARN/ERROR 3건 → 모두 저장 |

**Testcontainers 구성:**
```java
static KafkaContainer kafka       // Kafka 브로커
static GenericContainer redis     // 멱등성 Redis 스토어
static PostgreSQLContainer postgres // DB
```

---

## 7. 의존성 (build.gradle.kts)

```kotlin
dependencies {
    implementation(project(":kafka-common-lib"))
    implementation("org.springframework.boot:spring-boot-starter-web")
    implementation("org.springframework.kafka:spring-kafka")
    implementation("org.springframework.boot:spring-boot-starter-data-jpa")
    implementation("org.springframework.boot:spring-boot-starter-data-redis")
    runtimeOnly("org.postgresql:postgresql")

    testImplementation("org.springframework.boot:spring-boot-testcontainers")
    testImplementation("org.testcontainers:kafka")
    testImplementation("org.testcontainers:postgresql")
}
```

---

## 8. 전환 시 제거 대상

log-service로 전환 확정 시 아래를 제거한다:

```
kafka-platform/connect/           # Dockerfile, Kafka Connect 빌드 설정
kafka-platform/connectors/        # db-sink Connector JSON
docker-compose.yml :: kafka-connect 서비스
```

토픽(`prd.log.system.v1`)과 테이블(`system_log`) DDL은 그대로 유지된다.
