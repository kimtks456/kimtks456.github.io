---
title: "3. Topic 설계"
weight: 3
date: 2026-05-04
---

> 본 문서는 토픽 **네이밍 컨벤션** 을 정한다.
> 출처: [Confluent — *Kafka Topic Naming Convention: Best Practices, Patterns, and Guidelines*](https://www.confluent.io/learn/kafka-topic-naming-convention/)
>
> 관련 문서: [5. 설계](./5_design.md) — 토픽 YAML 의 위치 (`kafka-platform/topics/`).

---

## 1. Confluent 가 권장하는 4가지 구성 요소

1. **Data Source / Domain** — 발생 시스템 (예: `sales`, `hr`, `product`)
2. **Data Type / Action** — 이벤트 종류 (예: `order`, `click`, `transaction`)
3. **Environment / Region** — 배포 컨텍스트 (`prod`/`dev` 또는 `us-east`)
4. **Version** — 스키마 버전 (`v1`, `v2`)

---

## 2. 일반적 패턴 (Confluent 제시)

| 패턴 | 예시 |
|---|---|
| Hierarchical | `domain.data_type.region.version` |
| Action-Based | `user.signup.success` |
| Environment-Specific | `prod.order.events`, `dev.order.events` |
| Multi-Region | `global.sales.eu-west` |

---

## 3. 본 조직 채택안 (제안)

**`<env>.<domain>.<event>.<version>`** — Hierarchical + Environment-Specific 결합.

- 예: `prd.order.created.v1`, `dev.payment.refunded.v2`
- 구분자: `.` (period) 일관 사용 — Confluent 의 *"Use separators ... consistently"* 가이드 준수
- 환경을 prefix 로 둔 이유: ACL/권한을 환경 단위로 묶기 쉽고, 클러스터를 같이 쓸 때 분리에 유리 **(개인 추론)**

---

## 4. 기술적 제약 (Confluent 명시)

- 토픽 이름 **249자 제한** (Confluent 문서 인용)
- 모호한 이름(`data`, `messages`) 금지
- 약어 남발 금지
- 구분자 혼용 금지(`_` 와 `-` 섞지 말 것)

---

## 5. 참고

- [Confluent — Kafka Topic Naming Convention](https://www.confluent.io/learn/kafka-topic-naming-convention/)
