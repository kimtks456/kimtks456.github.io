---
title: "7. Connect를 통한 DB 적재"
weight: 7
date: 2026-05-10
---

> `prd.log.system.v1` 토픽의 시스템 로그를 Kafka Connect JDBC Sink로 PostgreSQL에 적재하는 실습.  
> 별도 Consumer 서비스 없이 Connect만으로 처리하는 설정과 동작을 단계별로 구성한다.  
> 개념 일반론은 [Connect 개념](../connect/1_concept.md), Q&A는 [DB Sink 시나리오](../connect/3_db_sink_qna.md), 라이선스 이슈는 [Connect 라이선스](../connect/4_license.md).

---

## 1. 전체 흐름

```
order-service (Producer)
    │  SystemLogEvent (JSON)
    ▼
Kafka Broker — prd.log.system.v1
    │
    ▼
Kafka Connect Worker
    │
    ├── [1] Consumer.poll()  ←── max.poll.records, fetch.min.bytes, fetch.max.wait.ms
    │
    ├── [2] SMT Pipeline
    │       ├── rename: camelCase → snake_case
    │       └── drop: context 필드 제거
    │
    └── [3] JDBC Sink
            └── batch INSERT (batch.size 개씩 묶어 1 SQL 문장으로)
                    │
                    ▼
              PostgreSQL — system_log 테이블
```

---

## 2. 커넥터 설정 전체 (`system-log-sink.json`)

```json
{
  "name": "system-log-sink",
  "config": {
    "connector.class": "io.aiven.connect.jdbc.JdbcSinkConnector",
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

---

## 3. 필드별 설명

### 3.1. 기본 식별

| 필드 | 값 | 설명 |
|------|----|------|
| `name` | `system-log-sink` | Connect 내 커넥터 고유 이름. REST API `/connectors/{name}` 으로 조회·관리 |
| `connector.class` | `io.aiven.connect.jdbc.JdbcSinkConnector` | 사용할 커넥터 구현체. Aiven JDBC Sink (Apache 2.0). [라이선스 이슈 참고](../connect/4_license.md) |
| `tasks.max` | `1` | 병렬 처리 task 수. **1로 고정한 이유**: 여러 task 쓰면 각 task가 독립 batch 가져가므로 batch 크기가 분산됨. 로그 적재는 순서보다 batch 효율이 중요하므로 단일 task로 묶음 처리 |
| `topics` | `prd.log.system.v1` | 이 커넥터가 소비할 Kafka 토픽. 여러 개면 콤마 구분 |

### 3.2. DB 연결

| 필드 | 값 | 설명 |
|------|----|------|
| `connection.url` | `${env:DB_URL}` | JDBC URL. `${env:VAR}` 형식으로 Connect Worker의 환경변수에서 주입. 하드코딩 금지 |
| `connection.user` | `${env:DB_USER}` | DB 사용자 |
| `connection.password` | `${env:DB_PASSWORD}` | DB 패스워드 |

> Connect Worker의 `connect-distributed.properties`에서 `config.providers=env,file` 설정이 필요.

### 3.3. 삽입 방식

| 필드 | 값 | 설명 |
|------|----|------|
| `insert.mode` | `insert` | 매 레코드를 INSERT. `upsert`(MERGE/ON CONFLICT)나 `update`도 가능하지만 로그는 항상 신규 적재 |
| `pk.mode` | `none` | DB의 PK를 Connect가 관리하지 않음. 테이블의 `id BIGSERIAL`은 PostgreSQL이 자동 생성 |
| `auto.create` | `false` | **Connect가 테이블을 자동으로 만들지 않음.** 테이블은 `system_log.ddl.sql`로 별도 관리. 자동 생성하면 타입이 부정확하게 추론되고 DDL이 코드로 추적되지 않음 |
| `auto.evolve` | `false` | 스키마 변경 시 ALTER TABLE 자동 실행 비활성화. 컬럼 추가는 DDL 파일 변경 + 수동 적용 |
| `table.name.format` | `system_log` | INSERT 대상 테이블명. `${topic}` 으로 토픽명을 그대로 쓸 수도 있음 |

### 3.4. 변환기 (Converter)

| 필드 | 값 | 설명 |
|------|----|------|
| `value.converter` | `JsonConverter` | Kafka 메시지 value를 JSON으로 역직렬화 |
| `value.converter.schemas.enable` | `false` | Schema Registry 없이 사용. `true`면 `{"schema": {...}, "payload": {...}}` 형태의 enveloped JSON을 기대함. 우리 Producer는 plain JSON 직렬화이므로 `false` |

### 3.5. 배치(Bulk Insert) 제어

```
Kafka Broker
  │
  │  [fetch.min.bytes=1024] → 1KB 이상 쌓일 때까지 대기
  │  [fetch.max.wait.ms=1000] → 최대 1초까지만 대기 (타임아웃)
  │
  ▼
Consumer.poll()
  └── max.poll.records=10 → 최대 10개만 가져옴
          │
          ▼
     10개 레코드 (또는 1초 경과 시 모인 것)
          │
          ▼
  JDBC batch INSERT
  INSERT INTO system_log (event_id, aggregate_id, ...) VALUES
    ('uuid-1', 'order-svc', ...),
    ('uuid-2', 'order-svc', ...),
    ...
    ('uuid-10', 'order-svc', ...);   ← 1 SQL 문장, 10행
```

| 필드 | 값 | 설명 |
|------|----|------|
| `batch.size` | `10` | INSERT 1문장에 묶을 최대 행 수. **이게 없으면** 10개를 받아도 `INSERT` 10번 개별 실행 |
| `consumer.override.max.poll.records` | `10` | 한 번의 `poll()`에서 꺼낼 최대 레코드 수. `batch.size`와 맞춤 |
| `consumer.override.fetch.min.bytes` | `1024` | 브로커가 응답 전 최소 버퍼 크기(bytes). SystemLogEvent 약 100~200B × 10개 ≈ 1~2KB를 근거로 설정. 이 조건이 충족되거나 `fetch.max.wait.ms`가 만료되면 응답 |
| `consumer.override.fetch.max.wait.ms` | `1000` | `fetch.min.bytes` 미충족 시 최대 대기 시간. "1초 OR 10개" 의 **1초** 제어 |

> **주의**: `fetch.min.bytes`는 bytes 기반이라 "정확히 10개"를 보장하지는 않음.  
> 10개에 못 미쳐도 1초 경과하면 flush. 10개가 넘어도 `max.poll.records` 가 cap을 걸어줌.

### 3.6. SMT (Single Message Transform)

레코드를 INSERT 하기 전, 필드 이름을 변환하고 저장 불가한 필드를 제거한다.

```
Kafka 레코드 (camelCase)             DB 컬럼 (snake_case)
─────────────────────────────────    ────────────────────────────
eventId     ──[rename]──────────→   event_id
aggregateId ──[rename]──────────→   aggregate_id
serviceId   ──[rename]──────────→   service_id
level       ──(그대로)──────────→   level
message     ──(그대로)──────────→   message
context     ──[drop]────────────→   (제거됨)
occurredAt  ──[rename]──────────→   occurred_at
```

| 필드 | 값 | 설명 |
|------|----|------|
| `transforms` | `rename,drop` | 적용할 SMT 이름 목록. 순서대로 체인 실행 |
| `transforms.rename.type` | `ReplaceField$Value` | Value 필드를 rename/exclude 하는 SMT. `$Value` 는 레코드의 value 부분에 적용 |
| `transforms.rename.renames` | `eventId:event_id,...` | `원본명:변경명` 형식으로 콤마 구분 |
| `transforms.drop.type` | `ReplaceField$Value` | 동일 SMT를 drop용으로 재사용 |
| `transforms.drop.exclude` | `context` | 제거할 필드명. `Map<String,String>` 타입은 JDBC 컬럼에 직접 삽입 불가 |

> `context` 를 저장하고 싶다면 PostgreSQL `JSONB` 컬럼 + 커스텀 SMT(Map → JSON string 직렬화)가 필요.

---

## 4. 테이블 DDL (`system_log.ddl.sql`)

```sql
CREATE TABLE IF NOT EXISTS system_log (
    id           BIGSERIAL    PRIMARY KEY,
    event_id     VARCHAR(36)  NOT NULL,
    aggregate_id VARCHAR(255) NOT NULL,
    service_id   VARCHAR(255) NOT NULL,
    level        VARCHAR(10)  NOT NULL,   -- INFO / WARN / ERROR
    message      TEXT         NOT NULL,
    occurred_at  VARCHAR(50)  NOT NULL    -- Instant → ISO-8601 or epoch string
);

CREATE INDEX IF NOT EXISTS idx_system_log_service  ON system_log (service_id);
CREATE INDEX IF NOT EXISTS idx_system_log_occurred ON system_log (occurred_at);
CREATE INDEX IF NOT EXISTS idx_system_log_level    ON system_log (level);
```

> `occurred_at` 을 `VARCHAR`로 선언한 이유:  
> Spring Boot 기본 Jackson 설정에서 `Instant`는 epoch 소수(초) 숫자로 직렬화됨 (`1715299200.123...`).  
> PostgreSQL `TIMESTAMP`와 타입 불일치 방지를 위해 `VARCHAR`로 저장.  
> `write-dates-as-timestamps=false` 설정 시 ISO-8601 문자열로 바뀌며, 이 경우 `TIMESTAMPTZ`로 선언 가능.

---

## 5. 커넥터 등록

Kafka Connect REST API로 등록한다.

```bash
# 등록
curl -X POST http://localhost:8083/connectors \
  -H "Content-Type: application/json" \
  -d @system-log-sink.json

# 상태 확인
curl http://localhost:8083/connectors/system-log-sink/status

# 삭제
curl -X DELETE http://localhost:8083/connectors/system-log-sink
```

정상 상태 응답:
```json
{
  "name": "system-log-sink",
  "connector": { "state": "RUNNING", "worker_id": "..." },
  "tasks": [{ "id": 0, "state": "RUNNING", "worker_id": "..." }]
}
```

---

## 참고 (출처)

- [Confluent JDBC Sink Connector — Config Options](https://docs.confluent.io/kafka-connectors/jdbc/current/sink-connector/sink_config_options.html)
- [Confluent — ReplaceField SMT](https://docs.confluent.io/platform/current/connect/transforms/replacefield.html)
- [Kafka Connect — REST API](https://docs.confluent.io/platform/current/connect/references/restapi.html)

### 본 사이트 내 관련 문서

- [Connect 개념](../connect/1_concept.md)
- [DB Sink 시나리오 Q&A](../connect/3_db_sink_qna.md)
- [Connect 라이선스 이슈](../connect/4_license.md)
- [5. 설계 §3](./5_design.md)
