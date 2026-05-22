---
title: "4. 스키마와 부호화"
weight: 4
date: 2026-05-23
---

> Kafka 메시지 포맷을 정하기 전에 **부호화(encoding)**, **스키마(schema)**,
> **스키마 발전(schema evolution)** 을 먼저 정리한다.
> Avro, Protobuf, Schema Registry는 이 문제를 해결하기 위해 등장한 도구다.

---

## 1. 부호화란?

애플리케이션 내부의 객체는 메모리 위에 있다.
네트워크로 보내거나 디스크에 저장하려면 바이트열로 바꿔야 한다.

```text
메모리 객체 → 바이트열    : encoding / serialization
바이트열 → 메모리 객체    : decoding / deserialization
```

예를 들어 Java 객체는 그대로 Kafka에 저장되지 않는다.
Producer는 객체를 JSON, Avro, Protobuf 같은 형식의 byte array로 바꿔 Kafka에 보낸다.
Consumer는 byte array를 다시 객체로 복원한다.

---

## 2. 스키마란?

스키마는 데이터의 구조 계약이다.

```text
이 이벤트는 어떤 필드를 가지는가?
각 필드의 타입은 무엇인가?
필수 필드인가, 선택 필드인가?
필드가 없을 때 기본값은 무엇인가?
```

예:

```json
{
  "orderId": "O-1",
  "amount": 10000,
  "currency": "KRW"
}
```

이 JSON만 보면 사람이 대충 의미를 알 수 있다.
하지만 시스템 입장에서는 다음 질문이 남는다.

| 질문 | 스키마 없을 때 문제 |
|---|---|
| `amount`는 정수인가, 문자열인가 | producer마다 다르게 보낼 수 있음 |
| `currency`는 필수인가 | consumer가 null 처리하다 깨질 수 있음 |
| 새 필드가 추가되면 기존 consumer는 안전한가 | 배포 순서에 따라 장애 가능 |
| 필드명을 바꾸면 호환되는가 | 대부분 호환되지 않음 |

스키마는 producer와 consumer 사이의 데이터 계약을 명시한다.

---

## 3. 스키마리스의 장점과 한계

JSON/XML처럼 스키마 없이도 쓸 수 있는 형식은 시작이 쉽다.

장점:

```text
사람이 읽기 쉽다.
디버깅이 쉽다.
PoC나 내부 도구에서 빠르게 시작할 수 있다.
```

한계:

```text
타입 계약이 약하다.
필수/선택 필드가 코드 관습으로 흩어진다.
호환성 검사를 자동화하기 어렵다.
schema drift가 생기기 쉽다.
```

`schema drift`는 producer와 consumer가 서로 다른 구조를 기대하며 점점 어긋나는 상황이다.

```text
producer A: amount를 number로 보냄
producer B: amount를 string으로 보냄
consumer C: amount가 항상 number라고 가정
```

작은 시스템에서는 코드 리뷰로 막을 수 있지만,
producer와 consumer가 많아지면 문서와 관습만으로는 어렵다.

---

## 4. 이진 부호화가 필요한 이유

JSON은 사람이 읽기 좋지만 필드명과 구조가 매번 payload에 포함된다.
메시지 수가 많아질수록 크기와 파싱 비용이 부담이 된다.

이진 부호화 형식은 보통 다음을 목표로 한다.

| 목표 | 설명 |
|---|---|
| 작은 payload | 필드명을 매번 싣지 않거나 더 압축된 표현 사용 |
| 빠른 처리 | 파싱 비용 감소 |
| 명확한 타입 | int, long, string, record 등을 스키마로 정의 |
| 호환성 관리 | 필드 추가/삭제 규칙을 명시 |

Thrift, Protocol Buffers, Avro는 모두 schema 기반 이진 부호화 계열이다.

---

## 5. Thrift, Protobuf, Avro의 공통점

세 형식 모두 데이터를 그냥 문자열로 주고받지 않는다.
먼저 schema를 정의하고, 그 schema에 맞춰 바이트열로 부호화한다.

```text
schema 정의
  → producer가 schema에 맞춰 encoding
  → consumer가 schema를 기준으로 decoding
```

공통적으로 해결하려는 문제:

```text
payload 크기 감소
타입 안정성 확보
언어 간 데이터 교환
스키마 변경 시 호환성 관리
```

차이는 schema를 어떻게 관리하고, reader와 writer의 schema 차이를 어떻게 다루는지에 있다.

---

## 6. Avro가 중요한 이유

Avro의 핵심은 **writer schema**와 **reader schema**를 분리해서 생각한다는 점이다.

```text
writer schema : 데이터를 쓸 때 producer가 사용한 schema
reader schema : 데이터를 읽을 때 consumer가 기대하는 schema
```

Consumer는 writer schema와 reader schema를 비교해 읽을 수 있는지 판단한다.
이 과정을 schema resolution이라고 한다.

예:

```text
v1 writer schema
  orderId
  amount

v2 reader schema
  orderId
  amount
  currency(default = "KRW")
```

v2 consumer가 v1 메시지를 읽을 때 `currency`가 없다.
하지만 reader schema에 default가 있으면 `"KRW"`로 채워 읽을 수 있다.

이게 schema evolution의 핵심이다.

---

## 7. Schema Evolution

스키마는 한 번 정하면 끝나는 것이 아니다.
서비스가 바뀌면 이벤트 구조도 바뀐다.

```text
필드 추가
필드 삭제
필드명 변경
타입 변경
의미 변경
```

문제는 producer와 consumer가 항상 동시에 배포되지 않는다는 점이다.

```text
producer는 v2 schema로 배포됨
consumer는 아직 v1 schema를 사용함
```

또는 반대도 가능하다.

```text
consumer는 v2 schema로 배포됨
topic에는 v1 메시지가 남아 있음
```

따라서 schema 변경은 "새 코드가 컴파일되는가"가 아니라
"서로 다른 버전의 producer/consumer가 공존해도 읽을 수 있는가"로 판단해야 한다.

---

## 8. Backward / Forward Compatibility

호환성은 읽는 주체 기준으로 이해하면 쉽다.

| 용어 | 의미 |
|---|---|
| Backward compatibility | 새 reader가 이전 writer의 데이터를 읽을 수 있음 |
| Forward compatibility | 이전 reader가 새 writer의 데이터를 읽을 수 있음 |
| Full compatibility | backward + forward 둘 다 만족 |

예:

```text
Backward:
  v2 consumer가 v1 message를 읽을 수 있는가?

Forward:
  v1 consumer가 v2 message를 읽을 수 있는가?
```

필드 추가는 default가 있으면 backward compatible이 되기 쉽다.
필드 타입 변경이나 의미 변경은 보통 위험하다.

---

## 9. Kafka에서 더 중요한 이유

Kafka에서는 schema evolution이 특히 중요하다.

DB는 보통 한 시점의 최신 row를 조회한다.
반면 Kafka topic에는 과거 이벤트가 남아 있다.

```text
offset 10: v1 schema로 작성된 OrderCreated
offset 11: v1 schema로 작성된 OrderCreated
offset 12: v2 schema로 작성된 OrderCreated
offset 13: v2 schema로 작성된 OrderCreated
```

Consumer가 새 코드로 배포되어도 topic에는 이전 schema로 작성된 메시지가 남아 있을 수 있다.
또 consumer group을 새로 만들거나 offset을 처음부터 읽으면 오래된 메시지를 다시 읽게 된다.

따라서 Kafka에서는 다음 질문이 중요하다.

```text
새 consumer가 과거 메시지를 읽을 수 있는가?
기존 consumer가 새 producer의 메시지를 읽어도 깨지지 않는가?
topic 안에 여러 schema version이 섞여도 처리 가능한가?
```

이 문제 때문에 Kafka 메시지 포맷에서는 Avro, Protobuf, JSON Schema,
Schema Registry, 호환성 정책이 중요해진다.

---

## 10. Schema Registry가 필요한 이유

schema 기반 형식을 쓰더라도 schema 파일이 각 서비스 저장소에 흩어져 있으면 문제가 남는다.

```text
어떤 schema가 최신인가?
producer가 실제로 어떤 schema로 썼는가?
consumer가 해당 schema를 어디서 가져오는가?
새 schema가 기존 schema와 호환되는가?
```

Schema Registry는 schema를 중앙에서 저장하고 버전 관리한다.
또 새 schema 등록 시 호환성 규칙을 검사할 수 있다.

```text
Producer
  → schema 등록/조회
  → schema id와 함께 메시지 encoding
  → Kafka
  → Consumer
  → schema id로 schema 조회
  → decoding
```

즉, Schema Registry는 단순 저장소가 아니라 schema evolution을 운영 정책으로 강제하는 장치다.

---

## 11. 다음 문서와의 연결

이 문서의 결론은 다음이다.

```text
Kafka 메시지는 시간이 지나며 구조가 바뀐다.
Producer와 consumer는 독립적으로 배포된다.
Topic에는 과거 schema로 작성된 이벤트가 남아 있다.
따라서 메시지 포맷은 schema evolution을 전제로 골라야 한다.
```

다음 문서인 [5. Message Format 설계](./5_message_format.md)에서는
이 배경을 바탕으로 JSON, Avro, Protobuf, JSON Schema, Schema Registry를 비교한다.

---

## 참고

- Designing Data-Intensive Applications - Martin Kleppmann
- Apache Avro Documentation
- Confluent Schema Registry Documentation
