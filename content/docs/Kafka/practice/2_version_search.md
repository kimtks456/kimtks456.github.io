---
title: "2. 버전 정리 — 4.0과 그 이전의 차이"
weight: 2
date: 2026-04-29
---

> 본 문서는 Kafka 버전 흐름을 짚고, **4.0** 과 **3.x** 의 주요 차이를 정리한다.
> 단정적 진술은 1차 출처(Apache Kafka 공식 release announcement, KIP 문서) 인용으로 갈음하고,
> 출처가 약한 내용은 **(미확인)** 표기.

---

## 1. 마일스톤 한눈에

| 버전 | 릴리즈 | 핵심 의미 | 출처 |
|---|---|---|---|
| 2.8.0 | 2021-04 | KRaft **early access** (KIP-500) | (미확인 — 본 문서 작성 시 직접 검증 안 함) |
| 3.0.0 | 2021-09 | KRaft 진행 / 메이저 정리 | (미확인) |
| 3.3.0 | **2022-10-03** | **KRaft production-ready** (KIP-833, 신규 클러스터 한정) | [KIP-833](https://cwiki.apache.org/confluence/display/KAFKA/KIP-833:+Mark+KRaft+as+Production+Ready), [Confluent blog](https://www.confluent.io/blog/apache-kafka-3-3-0-new-features-and-updates/) |
| 3.4 ~ 3.8 | 2023~2024 | ZK→KRaft 마이그레이션 기능 추가, KIP-848 early access (3.7) | [Confluent — Kafka 3.9](https://www.confluent.io/blog/introducing-apache-kafka-3-9/) (간접) |
| **3.9.0** | **2024-11-06** | **ZK 지원 마지막 메이저**, Tiered Storage GA | [Apache 공식 release announcement](https://kafka.apache.org/blog/2024/11/06/apache-kafka-3.9.0-release-announcement/), [Confluent blog](https://www.confluent.io/blog/introducing-apache-kafka-3-9/) |
| **4.0.0** | **2025-03-18** | **ZK 완전 제거**, Java 17 (broker), KIP-848 GA, KIP-932 EA | [Apache 4.0 release announcement](https://kafka.apache.org/blog/2025/03/18/apache-kafka-4.0.0-release-announcement/) |

> 3.9 의 트위터 공식 계정 발표:
> *"Hello Apache Kafka 3.9.0! - **last release using ZooKeeper** - tiered storage is production-ready"* — [Apache Kafka X(Twitter)](https://x.com/apachekafka/status/1854677903176614030)

---

## 2. 4.0 핵심 변경 (3.x 대비)

> 출처: [Apache Kafka 4.0.0 Release Announcement (2025-03-18)](https://kafka.apache.org/blog/2025/03/18/apache-kafka-4.0.0-release-announcement/) — 이하 본 절의 인용은 모두 이 페이지에서.

### 2.1. ZooKeeper 완전 제거 (KRaft only)

> *"the first major release to operate entirely without Apache ZooKeeper."*
> *"simplifies deployment and management, eliminating the complexity of maintaining a separate ZooKeeper ensemble."*

- 4.0 부터는 **ZK 모드로 기동 자체가 불가능** — 메타데이터/컨트롤러는 KRaft 가 전담
- 3.9 가 ZK 지원 마지막 버전이므로, ZK 운영 클러스터는 **3.9 → 4.0 전환 사이에 KRaft 마이그레이션 완료** 필요

### 2.2. Java 버전 요구 상향

| 컴포넌트 | 4.0 최소 Java | 3.x 와 차이 |
|---|---|---|
| **Kafka Brokers / Connect / Tools** | **Java 17** | 3.x 는 Java 11 까지 지원 → 4.0 에서 17 로 상향 |
| **Kafka Clients / Streams** | **Java 11** | 클라이언트는 11 유지 (broker 와 분리) |

→ **JDK 17 미만 운영 인프라는 4.0 전 업그레이드 필수**.

### 2.3. KIP-848 — 새 Consumer Rebalance Protocol GA

> *"increases the stability and the performance of consumer groups while simplifying clients."*

- 3.7 에서 early access 였던 신규 rebalance 프로토콜이 **4.0 에서 General Availability(GA)**
- **opt-in 방식**: 컨슈머가 `group.protocol=consumer` 명시 설정해야 사용. 미설정 시 기존 프로토콜 그대로 동작
- 효과(공식 문구 인용): 컨슈머 그룹 안정성·성능 향상, 클라이언트 단순화

### 2.4. KIP-932 — Queues for Kafka (Early Access)

> *"Early Access"* / *"cooperative consumption using Kafka topics"* / *"share groups ... roughly equivalent to a durable shared subscription in existing systems."*

- 기존: 파티션:컨슈머 = 1:1 → 공유 소비 불가
- KIP-932: **share group** 도입 → 같은 토픽을 여러 컨슈머가 협력적으로 소비 (전통 MQ 의 durable shared subscription 과 유사)
- **Early Access** — 본격 운영 채택은 GA 까지 보류 권고 *(추론)*

### 2.5. 제거된 API / 프로토콜

| KIP | 제거 항목 | 영향 |
|---|---|---|
| **KIP-896** | 구버전 client protocol API 제거 | **브로커가 2.1 이상이어야 4.0 클라이언트 업그레이드 가능** |
| **KIP-724** | Message format v0, v1 제거 | v2 만 지원. 매우 오래된 클라이언트와 호환 끊김 |
| **KIP-970** | Connect 의 `/connectors/{connector}/tasks-config` endpoint 제거 | Connect 외부 도구 점검 필요 |

### 2.6. 기타 주목 KIP (4.0 포함)

| KIP | 내용 |
|---|---|
| **KIP-890** | Transactions server-side defense — producer 장애 시 *"zombie transactions"* 감소 |
| **KIP-966** | Eligible Leader Replicas (ELR) — **preview** 상태. 데이터 유실 위험 추가 감소 |
| **KIP-996** | KRaft Pre-Vote — 불필요한 leader election 감소 |
| **KIP-653** | Log4j → **Log4j2** 마이그레이션 |

---

## 3. 3.x 주요 마일스톤 (4.0 으로 가는 길)

### 3.1. 3.3 — KRaft Production Ready (KIP-833)

- 출처: [KIP-833: Mark KRaft as Production Ready](https://cwiki.apache.org/confluence/display/KAFKA/KIP-833:+Mark+KRaft+as+Production+Ready)
- 단, **신규 클러스터 한정**. 기존 ZK 클러스터를 *마이그레이션* 하는 기능은 이 시점엔 미완

### 3.2. 3.4 ~ 3.8 — ZK→KRaft 마이그레이션 기능 진화

- 3.4 부터 ZK→KRaft 마이그레이션 기능 도입, 이후 버전에서 안정화 진행 *(검색 결과 기반 — 각 버전별 정확한 KIP 매핑은 미확인)*

### 3.3. 3.9 — ZK 지원 마지막 메이저 + Tiered Storage GA

- 출처: [Apache 3.9.0 release announcement](https://kafka.apache.org/blog/2024/11/06/apache-kafka-3.9.0-release-announcement/), [Confluent — Introducing Apache Kafka 3.9](https://www.confluent.io/blog/introducing-apache-kafka-3-9/)
- **마지막 ZK 호환 버전** — 4.0 으로 가기 전 ZK→KRaft 전환의 마지막 안전망
- **Tiered Storage 가 production-ready** 로 승격 — 오래된 로그를 S3/object storage 등으로 오프로드

---

## 4. 본 조직 입장에서의 의미

> 본 절은 §2.1 (ZK 제거) 가 §1 의 KRaft 전제와 일치함을 4.0 기준으로 재확인하는 성격.

### 4.1. 신규 구축이라면

- **처음부터 4.x + KRaft** 로 시작. ZK 운영을 알 필요가 없어짐
- JDK 17 인프라 전제 (broker), 11 (client/streams)
- KIP-848 Consumer Protocol 사용 시 클라이언트에 `group.protocol=consumer` 명시 — 표준 가이드에 명문화

### 4.2. 기존 ZK 운영 클러스터가 있다면 (마이그레이션)

1. **3.9 로 우선 정렬** — 4.0 직행 불가. 3.9 가 ZK→KRaft 마이그레이션의 최종 안정 버전
2. 3.9 에서 KRaft 모드로 마이그레이션 (별도 설계 필요 — *(미정)*)
3. **모든 클라이언트가 ≥2.1** 인지 점검 (KIP-896)
4. **메시지 포맷 v0/v1** 사용 여부 점검 (KIP-724)
5. JDK 업그레이드 (broker 17, client 11)
6. 4.0 으로 업그레이드

### 4.3. 토픽/공통 라이브러리 영향

- [`kafka-platform`](../platform/2_git_repository.md) 리포에서 사용하는 도구별 4.0 지원 시점 확인 필요:
  - **Strimzi**: 버전별 지원 Kafka 매트릭스 — [strimzi-kafka-operator/kafka-versions.yaml](https://github.com/strimzi/strimzi-kafka-operator/blob/main/kafka-versions.yaml)
  - **Confluent for Kubernetes (CfK)**: Confluent Platform 8.x 라인 (4.0 기반)이 정렬되는지 — *(미확인)*
  - **JulieOps / kafka-gitops / Terraform Provider**: 4.0 클러스터 대상 호환성 점검 — *(미확인)*

---

## 5. 정리

| 축 | 3.x 마지막 (3.9) | 4.0 |
|---|---|---|
| 메타데이터 관리 | ZK / KRaft 양쪽 | **KRaft only** |
| Broker JDK | 11+ | **17+** |
| Client/Streams JDK | 8+ (3.x 대부분) → 11 | 11+ |
| Consumer Rebalance | classic + KIP-848 EA | **KIP-848 GA** (opt-in) |
| 공유 소비 (Queue 의미론) | 미지원 | **KIP-932 Early Access** |
| Tiered Storage | **GA (3.9)** | 유지 |
| 메시지 포맷 | v0/v1/v2 | **v2 only** |
| 클라이언트 호환 하한 | — | **broker ≥ 2.1 (KIP-896)** |
| Log4j | Log4j 1.x | **Log4j2** |

---

## 6. 참고 (출처 모음)

### 1차 출처 (Apache 공식)
- [Apache Kafka 4.0.0 Release Announcement (2025-03-18)](https://kafka.apache.org/blog/2025/03/18/apache-kafka-4.0.0-release-announcement/)
- [Apache Kafka 3.9.0 Release Announcement (2024-11-06)](https://kafka.apache.org/blog/2024/11/06/apache-kafka-3.9.0-release-announcement/)
- [Apache Kafka — Upgrading docs (3.9)](https://kafka.apache.org/39/getting-started/upgrade/)
- [Apache Kafka downloads](https://kafka.apache.org/downloads)
- [Apache Kafka X(Twitter) — 3.9 announcement](https://x.com/apachekafka/status/1854677903176614030)

### KIP 1차 문서
- [KIP-833: Mark KRaft as Production Ready](https://cwiki.apache.org/confluence/display/KAFKA/KIP-833:+Mark+KRaft+as+Production+Ready)
- (이외 KIP-848, KIP-932, KIP-896, KIP-724, KIP-970, KIP-890, KIP-966, KIP-996, KIP-653 — 본문 표 참조. 각 KIP 페이지 직접 검증은 미완 — 추후 cwiki.apache.org 에서 KIP 번호로 조회)

### 2차 자료 (해설/요약)
- [Confluent — Apache Kafka 3.3 New Features](https://www.confluent.io/blog/apache-kafka-3-3-0-new-features-and-updates/)
- [Confluent — Introducing Apache Kafka 3.9](https://www.confluent.io/blog/introducing-apache-kafka-3-9/)
- [InfoQ — Apache Kafka 3.3 Replaces ZooKeeper with KRaft](https://www.infoq.com/news/2022/10/apache-kafka-kraft/)
- [heise online — Kafka 3.9 says goodbye to ZooKeeper](https://www.heise.de/en/news/Event-streaming-Kafka-3-9-says-goodbye-to-ZooKeeper-10011502.html)

### 도구 호환성 참고
- [Strimzi — kafka-versions.yaml](https://github.com/strimzi/strimzi-kafka-operator/blob/main/kafka-versions.yaml)
- [AWS MSK — Supported Apache Kafka versions](https://docs.aws.amazon.com/msk/latest/developerguide/supported-kafka-versions.html)
