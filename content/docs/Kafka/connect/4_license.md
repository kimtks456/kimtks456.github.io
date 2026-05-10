---
title: "4. Connect 라이선스 이슈"
weight: 4
date: 2026-05-10
---

> Kafka Connect를 엔터프라이즈·SaaS 환경에서 도입할 때 반드시 검토해야 할 라이선스 문제.  
> 특히 **Confluent Community License** 가 어디까지 허용되고 어디서 막히는지 분석한다.

---

## 1. 라이선스 계층 구조

Kafka Connect 스택은 컴포넌트마다 라이선스가 다르다.

```
┌─────────────────────────────────────────────────────┐
│  Connect Worker  (connect-distributed.sh)           │
│  → Apache Kafka 내장 → Apache 2.0 ✓               │
├─────────────────────────────────────────────────────┤
│  Connector Plugin (JDBC Sink 등)                    │
│  → 벤더마다 다름 ← 여기서 문제 발생               │
├─────────────────────────────────────────────────────┤
│  JDBC Driver (PostgreSQL 등)                        │
│  → PostgreSQL JDBC: BSD-2-Clause ✓                 │
└─────────────────────────────────────────────────────┘
```

**Connect worker 자체는 Apache 2.0이다.** 문제는 그 위에 올리는 **커넥터 플러그인**에 있다.

---

## 2. Confluent Community License — 핵심 조항

Confluent는 2018년부터 자사 고급 기능에 Apache 2.0 대신 **Confluent Community License** 를 적용하고 있다.

### 원문 핵심

> **"Excluded Purpose"** means making the Software available to third parties  
> as a **hosted or managed service**, where the service provides users with  
> access to any substantial set of the features or functionality of the Software.
>
> — [Confluent Community License](https://www.confluent.io/confluent-community-license/)

한 줄 요약: **"Confluent 소프트웨어를 제3자에게 호스팅/관리형 서비스로 제공하는 것"** 이 금지된 목적(Excluded Purpose).

### 허용 vs 금지

| 케이스 | 판단 | 이유 |
|--------|------|------|
| 사내 인프라에서 내부 운영 | **허용** | 제3자 제공 아님 |
| 개발·테스트 환경 | **허용** | — |
| 자사 제품에 내장, 고객이 Kafka Connect에 직접 접근 안 함 | **회색지대** | 실질적 접근 범위가 판단 기준 |
| **AI 플랫폼을 SaaS로 판매, Kafka Connect가 그 플랫폼의 일부** | **⚠️ 위험** | 제3자에게 기능 제공에 해당할 수 있음 |
| Confluent Cloud 같은 managed Kafka 서비스 판매 | **명시적 금지** | 직접 경쟁 서비스 |

---

## 3. 예시 케이스 분석 — AI 플랫폼 내 Kafka 사용

> **예시 시나리오**: Kafka를 내부 파이프라인으로 포함한 AI 플랫폼을 SaaS 형태로 타 회사에 제공하는 경우

Confluent의 판단 기준은 **"고객이 Confluent 소프트웨어의 실질적 기능에 접근하는가"** 다.

```
[AI 플랫폼 SaaS — 예시]
    │
    ├── 시나리오 A: Connect가 내부 파이프라인으로만 동작
    │       고객이 사용하는 것: AI 기능, API, 대시보드
    │       Kafka Connect는 백엔드에서 로그 적재 등에만 사용
    │               → 고객이 Connect에 직접 접근 불가
    │               → 회색지대 (법무 검토 권장)
    │
    └── 시나리오 B: Connect 기능을 고객에게 직접 노출
        고객이 Connect REST API를 호출하거나
        커넥터를 직접 설정·관리할 수 있는 UI 제공
                → Confluent 기능을 서비스로 제공한 것
                → 위반 가능성 높음
```

**케이스별 결론:**

| 시나리오 | 판단 | 권장 조치 |
|----------|------|-----------|
| Connect가 완전히 백엔드 내부에만 존재, 고객 미노출 | 회색지대 | 법무 검토 또는 Apache 2.0 대안으로 전환 |
| Connect 설정·관리를 고객에게 직접 노출 | 위반 리스크 | Apache 2.0 대안 필수 또는 Confluent 상업 라이선스 구매 |
| 내부 운영 전용 (SaaS 아님) | 허용 | 현행 유지 가능 |

> Confluent FAQ: "확신이 없으면 상업 라이선스를 구매하거나 Apache 2.0 대안을 사용하라"

---

## 4. Apache 2.0 JDBC Sink 대안 비교

| 커넥터 | 라이선스 | 유지보수 | batch.size | SMT 지원 | 비고 |
|--------|----------|----------|------------|----------|------|
| **Confluent kafka-connect-jdbc** | Community License | ✅ 활발 | ✓ | ✓ | SaaS 사용 리스크 |
| **[Aiven JDBC Connector](https://github.com/Aiven-Open/jdbc-connector-for-apache-kafka)** | **Apache 2.0** | ✅ 활발 (v6.10, 2025) | ✓ | ✓ | Confluent 것과 가장 유사. **SaaS 무제한** |
| **[Debezium JDBC Sink](https://debezium.io/documentation/reference/stable/connectors/jdbc.html)** | **Apache 2.0** | ✅ 매우 활발 (v3.1, 2025) | ✓ | 자체 방식 | CDC 이벤트 중심 설계. Debezium 이벤트 형식 강제 |
| **Apache Camel Kafka Connector** | **Apache 2.0** | ✅ | △ | △ | 설정 복잡, 기능 제한적 |

### Aiven vs Debezium 선택 기준

| | Aiven JDBC | Debezium JDBC Sink |
|--|------------|-------------------|
| **적합한 케이스** | 일반 INSERT 적재 (로그·이벤트 단순 적재) | CDC 이벤트(INSERT/UPDATE/DELETE) 처리 |
| **이벤트 포맷 제약** | 없음 (plain JSON 가능) | Debezium 이벤트 envelope 형식 권장 |
| **Confluent JDBC 호환성** | 높음 (설정 키 유사) | 낮음 (다른 설계 철학) |
| **설정 난이도** | 낮음 | 중간 |

**→ 현재 설계(plain JSON → PostgreSQL INSERT)에는 Aiven JDBC Connector 권장.**

---

## 5. 권장 구성 및 현재 채택 (SaaS 환경 기준)

```
Connect Worker:  confluentinc/cp-kafka-connect-base (Apache 2.0) ✓
JDBC Connector:  Aiven JDBC Connector (Apache 2.0)               ✓  ← 현재 프로젝트 채택
JDBC Driver:     PostgreSQL JDBC (BSD-2-Clause)                  ✓
```

> **Connect Worker 이미지 (`cp-kafka-connect-base`)는 Apache 2.0이다.**  
> Confluent Community License 이슈는 **커넥터 플러그인** 에만 해당한다. Worker 이미지 자체는 SaaS 환경에서도 사용 가능하다.

Aiven JDBC Connector는 Confluent JDBC와 설정 키가 유사해 `system-log-sink.json` 변경이 최소화된다.  
완전 동일하지는 않으므로 [Aiven 설정 레퍼런스](https://github.com/Aiven-Open/jdbc-connector-for-apache-kafka/blob/master/docs/sink-connector.md)를 참조한다.

### 현재 프로젝트 커넥터 설정

```json
{
  "connector.class": "io.aiven.connect.jdbc.JdbcSinkConnector"
}
```

---

## 6. Aiven JDBC Connector 향후 리스크 분석

현재 프로젝트는 Aiven JDBC Connector를 Apache 2.0 대안으로 채택했으나, 운영 관점에서 아래 리스크를 인지해야 한다.

### 리스크 목록

| 리스크 | 수준 | 설명 |
|--------|------|------|
| **단일 기업 의존** | 중 | Aiven 사가 유지보수를 중단하면 사실상 방치됨. Apache 2.0이라 포크는 가능하나 유지 부담이 생김 |
| **Confluent Hub 미등록** | 중 | `confluent-hub install` 불가 → GitHub 릴리즈에서 직접 다운로드 필요. 버전 업데이트 자동화가 어렵고 빌드 파이프라인 관리 부담이 증가함 |
| **릴리즈 아티팩트 지연** | 중 | 실제로 v6.12.0은 소스만 태깅되고 배포 아티팩트(ZIP/TAR)가 누락된 상태로 공개됨. 최신 버전으로 즉시 업그레이드 불가 상황 발생 가능 |
| **공식 Docker 이미지 없음** | 중 | Connect Worker에 얹는 커스텀 이미지를 직접 빌드해야 함. `buildx` 버전 등 빌드 환경 의존성이 생기고, 이미지 빌드 파이프라인을 직접 관리해야 함 |
| **커뮤니티 규모** | 하 | Confluent JDBC 대비 이슈 레포트·스택오버플로우 자료가 적음. 트러블슈팅 난이도 상승 가능 |

### 트리거 조건 — 대안 전환 검토 시점

아래 중 하나라도 발생하면 Kafka Connect 방식 자체를 재검토한다:

- Aiven 리포 아카이브(보관 전용) 또는 6개월 이상 커밋 없음
- 필요 버전 릴리즈 아티팩트가 2주 이상 누락
- 사용 중인 Kafka 버전과 커넥터 호환성 문제 발생

### 대안 방향 — log-service 전환

Connect 의존성을 완전히 제거하는 방향으로 **`log-service` 마이크로서비스**를 별도 운영하는 방안이 있다.  
자세한 내용은 [5. 설계 — log-service 전환 검토](../practice/5_design.md#10-log-service-전환-검토-향후-방향성) 참조.

---

## 참고 (출처)

- [Confluent Community License 원문](https://www.confluent.io/confluent-community-license/) — "Excluded Purpose" 정의 포함
- [Confluent Community License FAQ](https://www.confluent.io/confluent-community-license-faq/)
- [Aiven JDBC Connector — GitHub](https://github.com/Aiven-Open/jdbc-connector-for-apache-kafka)
- [Debezium JDBC Sink Connector](https://debezium.io/documentation/reference/stable/connectors/jdbc.html)
- [Debezium 3.1 릴리즈 노트](https://debezium.io/blog/2025/04/02/debezium-3-1-final-released/)

### 본 사이트 내 관련 문서

- [7. Connect를 통한 DB 적재 (실습)](../practice/7_connect_db_sink.md)
- [3. DB Sink 시나리오 Q&A](./3_db_sink_qna.md)
