---
title: "2. 모니터링"
weight: 2
date: 2026-05-02
---

> 본 문서는 Kafka Connect 클러스터를 운영할 때 보아야 할 메트릭·도구·표준 스택을 정리한다.
> sink 종류와 무관하게 통용되는 부분만 다루며, 외부 시스템(DB, ES 등) 내부 모니터링은 *그 시스템 측 가이드* 로 미룬다.
> 출처: [Confluent — Kafka Connect Monitoring (JMX)](https://docs.confluent.io/platform/current/connect/monitoring.html)
>
> 관련 문서:
> - 개념·아키텍처·HA·자원: [1. Connect 개념](./1_concept.md)
> - DB sink 시나리오의 모니터링 보완(예: DB connection pool): [3. DB Sink 시나리오 Q&A](./3_db_sink_qna.md)

---

## 1. 모니터링이 답해야 할 질문

Connect 운영자가 매일 답하고 싶은 것은 결국 다음 4 가지다:

| # | 질문 | 어디서 보나 |
|---|---|---|
| 1 | 적재가 produce 속도를 따라가고 있나? | **Consumer Lag** (별도 도구) + `sink-record-active-count` |
| 2 | 외부 시스템 쪽이 느려지고 있나? | `put-batch-avg-time-ms`, `put-batch-max-time-ms` |
| 3 | 실패가 늘고 있나? | Task error metrics, DLQ 발행 수 |
| 4 | Worker / Task 가 살아 있나? | `connector-status`, `running-ratio` |

각 질문 → 어떤 메트릭으로 답하는지를 §2 ~ §4 에서 풀어 둔다.

---

## 2. JMX 메트릭

> Connect Worker 는 JVM 이며 **JMX 로 메트릭을 노출**. 표준 운영 패턴은 *JMX Exporter → Prometheus → Grafana*.

### 2.1. Sink Connector 핵심 메트릭

| 메트릭 | 의미 | 활용 |
|---|---|---|
| `put-batch-avg-time-ms`, `put-batch-max-time-ms` | task 가 외부 시스템에 한 batch 쓰는 데 걸린 시간 | **외부 시스템 지연을 가장 직접적으로 보여줌** |
| `sink-record-active-count` | consume 했지만 아직 외부 시스템에 안 쓴 레코드 수 | back-pressure 지표. 늘면 외부가 못 따라가는 중 |
| `sink-record-send-rate`, `sink-record-send-total` | 실제 외부 시스템에 쓴 처리율·누적 | throughput 추세 |
| `offset-commit-success-percentage`, `offset-commit-avg-time-ms` | offset commit 성공률·시간 | 적재 후 commit 실패 시 중복 적재 위험 인지 |
| `batch-size-avg`, `batch-size-max` | 실제 묶인 batch 크기 | `batch.size` 와 `consumer.max.poll.records` 미스매치 진단 |
| Task error metrics, DLQ metrics | task 실패 / DLQ 발행 수 | task-level 실패 알림 트리거 |
| `pause-ratio`, `running-ratio` | task 의 paused/running 시간 비율 | hang / 무한루프 감지 |
| `connector-status` | running / paused / failed | 헬스체크 |

### 2.2. Source Connector 추가 메트릭 (참고)

- `source-record-poll-rate`, `source-record-write-rate`
- `poll-batch-avg-time-ms`

→ 본 조직이 처음 도입할 때는 보통 *Sink* 가 우선. Source 는 CDC 등 도입 시 필요.

### 2.3. 임계값 기준점 (개인 정리)

> 정확한 수치는 워크로드 의존. 첫 운영 시작 시 *의심해 볼 만한* 기준값.

| 지표 | 의심 기준 (개인 정리) | 의미 |
|---|---|---|
| `put-batch-avg-time-ms` | 평소 대비 ×2 이상 지속 5 분 | 외부 시스템 지연 시작 |
| `sink-record-active-count` | 지속 증가 추세 | back-pressure. 적재가 produce 를 못 따라감 |
| `offset-commit-success-percentage` | < 99% | commit 실패. 중복 적재 위험 |
| `running-ratio` | < 1.0 | task 가 일하고 있지 않음 (hang / paused / 죽음) |
| DLQ 발행 rate | > 0 (지속적) | 데이터 품질 또는 외부 시스템 거부 발생 중 |

---

## 3. Consumer Lag — 별도, 매우 중요

Sink Worker 는 본질적으로 **Kafka 컨슈머**. 따라서 **컨슈머 그룹 lag** 으로
*"외부 시스템 적재가 produce 속도를 못 따라가고 있나?"* 를 본다.

JMX 의 `sink-record-active-count` 도 비슷한 신호를 주지만, **Lag 은 broker 측에서 본 진실치** 라서 별도 도구로도 함께 본다.

도구 (택 1):

| 도구 | 특징 |
|---|---|
| **Burrow** | LinkedIn 발. 단독 데몬으로 lag 평가. 무료 |
| **kafka-lag-exporter** | Prometheus exporter 형태. Grafana 대시보드와 자연스럽게 결합 |
| **Confluent Control Center** | 상용. UI 가 정돈됨 |

→ 도구 선택은 환경 결정 후 — *(미정)*

---

## 4. 외부 시스템 측 모니터링은 별도

> Connect 의 JMX 만으로는 외부 시스템 내부 상태(connection 수·풀, 락 경합, 디스크 사용률, queue depth 등)를 **볼 수 없다**.

Connect 가 보여주는 것은 *"외부 시스템에 batch 한 번 쓰는 데 N 초 걸렸다"* 까지. 그 N 초의 *내부 분해* 는 외부 시스템 측 도구로 봐야 한다.

→ 외부 시스템 자체 exporter 와 함께 운영. sink 별 구체 가이드는 해당 시스템 docs 참조:
- DB sink 의 connection 풀 모니터링: [3. DB Sink 시나리오 Q&A](./3_db_sink_qna.md) §5
- Elasticsearch sink: cluster stats / hot threads — *(미정, 도입 시 정리)*
- S3 sink: S3 access log / multipart upload 실패율 — *(미정)*

---

## 5. 표준 모니터링 스택 (제안)

```text
Connect Worker (JMX)
    └→ Prometheus JMX Exporter (sidecar 또는 javaagent)
        └→ Prometheus
            └→ Grafana 대시보드
                └→ Alertmanager
                   ├ DLQ 발행 증가 알림
                   ├ consumer lag 임계 초과 알림
                   ├ put-batch-time-ms 임계 초과 알림
                   └ task FAILED 알림 (connector-status)

별도 트랙:
컨슈머 그룹 (broker)
    └→ Burrow / kafka-lag-exporter
        └→ Prometheus / Grafana

별도 트랙:
외부 시스템 자체 exporter
    └→ Prometheus
        └→ Grafana
```

→ Connect / Lag / 외부 시스템 — **세 트랙을 함께 봐야** 장애 원인을 분리할 수 있음.
- *적재가 느림* + *Connect put-batch-time 정상* + *DB CPU 100%* → DB 측 원인
- *적재가 느림* + *Connect put-batch-time 정상* + *DB 정상* → Worker 자원 부족
- *적재가 느림* + *Connect put-batch-time 급증* + *DB CPU 정상* → DB connection 경합·락 의심

---

## 6. JMX Exporter 운영 메모 (개인 정리)

> *(개인 정리)* — 운영 시 자주 꼬이는 부분.

- **Javaagent vs sidecar**: K8s 환경에서는 javaagent (Worker JVM 자체에 붙임) 가 단순. sidecar 는 별도 포트 expose 필요
- **메트릭 화이트리스트**: JMX 가 노출하는 메트릭이 매우 많음 → 필요한 것만 `lowercaseOutputName` + 패턴 매치로 추리는 게 Prometheus storage 절약
- **태스크 단위 라벨**: `connector`, `task` 라벨이 살아 있어야 *어떤 connector 가 느린지* 분리 가능. exporter rule 설계 시 신경

---

## 7. 알람 설계 원칙 (개인 정리)

| 원칙 | 이유 |
|---|---|
| **task FAILED 즉시 알림** | task-level 실패는 자동 rebalance 안 됨 (Connect 한계) → 사람이 인지해야 함 |
| **DLQ 발행은 *증가율* 로 알람** | 평시에도 0 이 아닐 수 있음. *추세*가 의미 |
| **lag 임계는 *시간* 기준** | 레코드 수 기준은 토픽마다 다름. *"적재가 N 분 뒤처짐"* 이 사람에게 직관적 |
| **`put-batch-time-ms` 와 외부 시스템 알람을 묶음** | 둘 중 하나만 울리면 원인 분리가 빨라짐 |

---

## 8. 참고 (출처)

### 1차 출처
- [Confluent — Kafka Connect Monitoring (JMX)](https://docs.confluent.io/platform/current/connect/monitoring.html)
- [Apache Kafka 공식 — Connect Monitoring](https://kafka.apache.org/documentation/#connect_monitoring)

### 도구
- [linkedin/Burrow](https://github.com/linkedin/Burrow)
- [seglo/kafka-lag-exporter](https://github.com/seglo/kafka-lag-exporter)
- [prometheus/jmx_exporter](https://github.com/prometheus/jmx_exporter)
