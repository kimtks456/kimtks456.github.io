---
title: "4. Message Format 설계"
weight: 4
date: 2026-05-04
---

> 본 문서는 메시지의 **직렬화 포맷·Schema Registry·호환성 정책·버전 관리** 를 정한다.
> 본 시점에는 결정 단계 — 후보를 정리하고 비교하며, 본 조직 결정이 내려지면 §5 에 채워 넣는다.
>
> 관련 문서:
> - 토픽 이름의 `.v1` `.v2` 부분: [3. Topic 설계](./3_topic_design.md) §1, §3
> - `kafka-common-lib` 의 `serde/` 위치: [2. Git Repository 설계](./2_git_repository.md) §3

---

## 1. 직렬화 포맷 비교

> 출처: [Confluent — Schema Registry Concepts (Schema Formats)](https://docs.confluent.io/platform/current/schema-registry/index.html)

| 포맷 | 스키마 필요 | 장점 | 단점 | 비고 |
|---|---|---|---|---|
| **Avro** | ✅ (`.avsc`) | Schema Registry 통합 표준 · binary 효율 · evolution rule 성숙 | 사람이 읽기 어려움 (binary) | Confluent 에코시스템의 default. 가장 흔한 운영 표준 |
| **Protobuf** | ✅ (`.proto`) | gRPC 와 호환 · 다국어 지원 우수 | Avro 대비 evolution rule 가 약간 더 빡셈 | 이미 gRPC 쓰는 조직에 자연스러움 |
| **JSON Schema** | ✅ (`.json`) | 사람이 읽기 좋음 · 도구 생태계 풍부 | binary 비효율 · payload 크기 큼 | 사람 디버깅 빈번한 케이스 |
| **JSON (스키마 없음)** | ❌ | 진입 장벽 낮음 | **schema drift 위험** · 운영급 비추 *(개인 추론)* | 빠른 PoC 외에는 비권장 |
| **String / ByteArray** | ❌ | 단순 | 도메인 의미 0 | 메타·로그 wrapper 가 아니면 비추 |

→ 본 조직 default 후보: **Avro + Schema Registry** (Confluent 표준). 단, 이미 Protobuf 쓰는 도메인이 있다면 Protobuf 도 허용 — *(미정)*

---

## 2. Schema Registry 후보

> 출처: 각 프로젝트 공식 문서

| 도구 | 라이선스 | 호환 포맷 | 비고 |
|---|---|---|---|
| **Confluent Schema Registry** | Confluent Community License (개정) | Avro · Protobuf · JSON Schema | 상용/Confluent 환경 표준 |
| **Apicurio Registry** | Apache 2.0 (OSS) | Avro · Protobuf · JSON Schema · OpenAPI · AsyncAPI | Strimzi 등 OSS 스택과 잘 맞음 |
| **Karapace** | Apache 2.0 (OSS) | Avro · Protobuf · JSON Schema | Aiven 발. Confluent SR 와 API 호환 |

→ §1 의 [실행 환경 결정](./1_direction.md) 과 묶여 결정됨:
- CfK 환경 → Confluent Schema Registry
- Strimzi/OSS 환경 → Apicurio 또는 Karapace
- *(미정)*

---

## 3. 호환성 정책 (Schema Evolution)

> 출처: [Confluent — Schema Evolution and Compatibility](https://docs.confluent.io/platform/current/schema-registry/fundamentals/schema-evolution.html)

Schema Registry 가 표준화한 호환성 모드:

| 모드 | 의미 | 새 Producer ↔ 기존 Consumer | 새 Consumer ↔ 기존 Producer |
|---|---|---|---|
| `BACKWARD` (default) | 새 schema 가 *이전 schema 로 작성된 데이터* 를 읽을 수 있어야 함 | OK | OK (조건 충족 시) |
| `BACKWARD_TRANSITIVE` | 위와 같되 **모든** 이전 버전과 호환 | OK | OK |
| `FORWARD` | 이전 schema 가 *새 schema 로 작성된 데이터* 를 읽을 수 있어야 함 | OK | (조건 다름) |
| `FORWARD_TRANSITIVE` | 위와 같되 모든 이전 버전 | OK | OK |
| `FULL` | BACKWARD + FORWARD 둘 다 | OK | OK |
| `FULL_TRANSITIVE` | FULL + 모든 이전 버전 | OK | OK |
| `NONE` | 호환성 검사 안 함 | — | — |

→ 본 조직 default 후보: **`BACKWARD`** (Confluent default). 단, 사용 패턴(여러 Consumer 가 schema 갱신 속도 차이가 클 때)에 따라 `FULL` 검토 — *(미정)*

---

## 4. 버전 관리 — 토픽 명과의 관계

[3. Topic 설계 §3](./3_topic_design.md) 의 `<env>.<domain>.<event>.<version>` 에서 *version* 은 **schema 의 호환성을 깨는 변경(breaking change)** 시에만 올린다.

- `prd.order.created.v1` 의 schema 가 호환 가능한 변경(필드 추가 default 있음 등) → schema version 만 올라감 (`order.created` schema 의 v1 → v2). 토픽명 그대로
- 호환 불가능한 변경(필드 의미 변경, 타입 변경) → **새 토픽** `prd.order.created.v2` 신설. 기존 v1 은 deprecation 기간 동안 병행

→ 즉, 토픽명의 `.v1` 은 *schema 호환성 boundary* 표시. SR 내부의 schema version 은 별도 차원.

---

## 5. 본 조직 결정 (잠정)

> 본 절은 *현재 결정 상태*. 미정 항목은 그대로 표기.

| 항목 | 결정 |
|---|---|
| 직렬화 포맷 | **(미정)** — Avro 후보 우세, 환경 결정 후 확정 |
| Schema Registry | **(미정)** — [1. 방향성 §4 실행 환경](./1_direction.md) 결정 후 자동 결정됨 |
| 호환성 모드 (default) | **(미정)** — `BACKWARD` 후보 |
| 토픽 버전 vs schema 버전 분리 정책 | §4 채택 (toplevel breaking 만 토픽 v 갱신) |
| `kafka-common-lib` 의 default Serde | 직렬화 포맷 결정 후 — [2. Git Repository 설계 §3](./2_git_repository.md) `serde/` |

---

## 6. 참고 (출처)

### 1차 출처 (공식)
- [Confluent — Schema Registry Concepts](https://docs.confluent.io/platform/current/schema-registry/index.html)
- [Confluent — Schema Evolution and Compatibility](https://docs.confluent.io/platform/current/schema-registry/fundamentals/schema-evolution.html)
- [Apache Avro Specification](https://avro.apache.org/docs/current/specification/)
- [Protocol Buffers Language Guide](https://protobuf.dev/programming-guides/proto3/)

### 도구
- [Confluent Schema Registry](https://github.com/confluentinc/schema-registry)
- [Apicurio Registry](https://www.apicur.io/registry/)
- [Karapace](https://github.com/aiven/karapace)
