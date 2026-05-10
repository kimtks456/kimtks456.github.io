---
title: "8. Kafka UI — 토픽·메시지·모니터링"
weight: 8
date: 2026-05-10
---

> Kafka UI(Provectus)는 브라우저에서 Kafka 클러스터를 관리·모니터링할 수 있는 오픈소스 웹 대시보드다.  
> 토픽 CRUD, 메시지 발행/조회, 컨슈머 그룹 추적, 브로커 상태까지 한 화면에서 확인할 수 있다.

---

## 1. 실행

### docker-compose

```yaml
services:
  kafka-ui:
    image: provectuslabs/kafka-ui:latest
    ports:
      - "8989:8080"
    environment:
      KAFKA_CLUSTERS_0_NAME: local
      KAFKA_CLUSTERS_0_BOOTSTRAPSERVERS: kafka:9092
      # Schema Registry 연동 (선택)
      # KAFKA_CLUSTERS_0_SCHEMAREGISTRY: http://schema-registry:8081
      # Kafka Connect 연동 (선택)
      # KAFKA_CLUSTERS_0_KAFKACONNECT_0_NAME: connect
      # KAFKA_CLUSTERS_0_KAFKACONNECT_0_ADDRESS: http://kafka-connect:8083
    depends_on:
      - kafka
```

브라우저에서 `http://localhost:8989` 접속.

### 멀티 클러스터

환경변수 인덱스를 올려서 여러 클러스터를 동시에 등록할 수 있다.

```yaml
KAFKA_CLUSTERS_0_NAME: local
KAFKA_CLUSTERS_0_BOOTSTRAPSERVERS: kafka-local:9092
KAFKA_CLUSTERS_1_NAME: staging
KAFKA_CLUSTERS_1_BOOTSTRAPSERVERS: kafka-staging:9092
```

---

## 2. 토픽 관리

| 기능 | 설명 |
|------|------|
| 토픽 목록 조회 | 파티션 수, 복제 인수(RF), 보존 기간, 메시지 수 한눈에 확인 |
| 토픽 생성 | 이름·파티션·RF·Config(retention.ms 등) 지정 후 클릭 한 번 |
| 토픽 설정 변경 | `retention.ms`, `cleanup.policy`, `compression.type` 등 런타임 변경 |
| 토픽 삭제 | UI에서 바로 삭제 (브로커 `delete.topic.enable=true` 필요) |
| 파티션 상세 | 각 파티션의 Leader, ISR, Offline 레플리카 확인 |

---

## 3. 메시지 발행 (Produce)

**Dashboard → Topics → [토픽명] → Produce Message**

- **Key**: 문자열 직접 입력
- **Value**: JSON / Plain Text / Avro(Schema Registry 연동 시)
- **Partition**: 특정 파티션 지정 또는 라운드로빈
- **Headers**: `key: value` 형식으로 커스텀 헤더 추가

```json
// Value 예시
{
  "orderId": "abc-123",
  "customerId": "customer-1",
  "totalAmount": 10000
}
```

> **주의**: Avro 스키마 메시지를 보내려면 Schema Registry URL을 환경변수에 등록해야 한다.  
> 등록 없이 보낸 raw JSON은 컨슈머 쪽에서 역직렬화 에러가 날 수 있다.

---

## 4. 메시지 조회 (Consume)

**Dashboard → Topics → [토픽명] → Messages**

### 조회 옵션

| 옵션 | 설명 |
|------|------|
| Offset | `Earliest` / `Latest` / 특정 offset 지정 |
| Partition | 전체 또는 특정 파티션만 |
| Seek by timestamp | 특정 시각 이후 메시지만 조회 |
| Filter | 메시지 Key/Value에 포함된 문자열로 필터 (스마트 필터 지원) |
| Max messages | 한 번에 가져올 메시지 수 제한 |

### 스마트 필터 (Groovy DSL)

조건식을 작성해 메시지를 필터링할 수 있다.

```groovy
// orderId가 특정 값인 메시지만 보기
import groovy.json.JsonSlurper
def obj = new JsonSlurper().parseText(record.value)
obj.orderId == "abc-123"
```

---

## 5. 컨슈머 그룹 모니터링

**Dashboard → Consumers**

| 항목 | 설명 |
|------|------|
| Group ID | 등록된 컨슈머 그룹 목록 |
| State | `Stable` / `Empty` / `Dead` |
| Members | 현재 붙어 있는 컨슈머 인스턴스 수 |
| Lag (파티션별) | 각 파티션의 Current Offset / Log End Offset / **Lag** |
| Total Lag | 그룹 전체 누적 Lag |

Lag가 0이면 컨슈머가 실시간으로 따라가고 있는 것이고,  
Lag가 계속 증가하면 컨슈머 처리 속도가 부족하다는 신호다.

---

## 6. 브로커 / 클러스터 모니터링

**Dashboard → Brokers**

| 항목 | 설명 |
|------|------|
| Broker 목록 | Broker ID, Host:Port, Controller 여부 |
| 디스크 사용량 | 각 브로커의 디스크 사용량 |
| JVM Heap | Heap Used / Max (브로커 JMX 활성화 시) |
| 초당 메시지 처리량 | Bytes In/Out per second |
| Under-replicated 파티션 | ISR에서 빠진 레플리카 — 0이 정상 |
| Offline 파티션 수 | Leader 없는 파티션 — 0이어야 함 |

> **JMX 필요 항목**: JVM Heap, Bytes In/Out 등 상세 메트릭은 브로커에 JMX가 활성화되어 있어야 수집된다.  
> `KAFKA_JMX_PORT: 9997` 환경변수 설정 후 Kafka UI에 JMX 주소를 등록하면 된다.

---

## 7. Schema Registry 연동

`KAFKA_CLUSTERS_0_SCHEMAREGISTRY` 를 등록하면:

- 토픽 메시지를 Avro/Protobuf/JSON Schema로 자동 역직렬화해서 보여줌
- **Schema Registry 탭**: 스키마 목록 조회, 버전 이력, 호환성 모드(BACKWARD 등) 확인
- UI에서 직접 스키마 등록·삭제 가능

---

## 8. Kafka Connect 연동

`KAFKA_CLUSTERS_0_KAFKACONNECT_0_ADDRESS` 를 등록하면:

- **Connectors 탭**: 등록된 커넥터 목록, 상태(Running/Failed/Paused)
- 커넥터 설정 조회 및 수정
- 커넥터 재시작 / 일시정지 / 삭제
- 태스크 단위 상태 확인

---

## 9. 할 수 없는 것 (한계)

| 항목 | 설명 |
|------|------|
| ACL 관리 | Kafka ACL 설정·조회 UI 없음 (CLI 필요) |
| KRaft 메타데이터 상세 | KRaft 모드에서 일부 브로커 메타데이터 미지원 |
| 실시간 스트리밍 뷰 | 메시지 탭은 폴링 방식 — Kafka Streams 실시간 tail 아님 |
| 알람/Alert | Lag 임계치 알림 등 alerting 기능 없음 (Prometheus + Grafana 조합 필요) |
| 프로덕션 접근 제어 | 기본 빌드에 인증 없음 — `AUTH_TYPE: LOGIN_FORM` 설정 필요 |

---

## 참고

- [Kafka UI GitHub](https://github.com/provectus/kafka-ui)
- [Kafka UI Docs](https://docs.kafka-ui.provectus.io/)
