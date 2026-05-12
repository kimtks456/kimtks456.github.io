---
title: "Kafka 통합 테스트 — auto-offset-reset 미설정 시 메시지 유실"
weight: 1
date: 2026-05-11
---

## 1. 문제

Spring Boot + Testcontainers 기반 Kafka 통합 테스트에서 다음과 같은 실패가 반복 발생했다.

```
Wanted but not invoked:
orderEventConsumer.handle(<any OrderCreatedEvent>);
-> at com.example.order.kafka.OrderEventConsumer.handle(...)
Actually, there were zero interactions with this mock.
```

`producer.publish()` 로 메시지를 발행한 뒤 `verify(consumer, timeout(5000).times(1))` 를 호출했지만, 컨슈머가 메시지를 수신하지 못했다.

영향 테스트:
- `OrderEventFlowTest.주문_이벤트_발행_후_컨슈머_수신()`
- `OrderPubSubTest.여러_이벤트_연속_발행_모두_수신()`
- `OrderIdempotencyTest.어노테이션_없을때_동일_eventId_두번_발행_두번_모두_처리()` — latch.await(5s) timeout

---

## 2. 원인

**Race condition: 컨슈머의 파티션 할당보다 프로듀서의 발행이 먼저 완료된다.**

```
[context 시작]
  ├─ producer bean 초기화 완료 (즉시)
  └─ consumer listener container 시작 → 백그라운드 스레드에서 join-group 진행 중

[test 메서드 실행 (context 준비 직후)]
  ├─ producer.publish() → 메시지 offset 0에 적재
  └─ consumer의 join-group이 아직 진행 중...

[몇 초 뒤]
  └─ consumer join-group 완료 → 파티션 할당
     → auto-offset-reset: latest (기본값)
     → 최신 offset = 1 (메시지 다음 위치)
     → offset 0의 메시지를 건너뜀 → 유실
```

실제 로그:
```
Resetting offset for partition order.created-0 to position FetchPosition{offset=1, ...}
```

메시지가 offset 0에 있는데 컨슈머가 offset 1에서 시작해 수신하지 못한다.

`auto-offset-reset` 의 기본값은 `latest` 이므로, 커밋된 offset이 없을 때 파티션의 끝(최신)부터 읽는다. 테스트 환경에서는 Testcontainers가 매번 새 브로커를 띄우기 때문에 커밋된 offset이 항상 없고, 이 race condition이 재현된다.

추가로, `OrderIdempotencyTest` 에서 사용하는 토픽(`order.idempotency-without` 등)은 컨슈머 구독 시점에 아직 존재하지 않는다. 프로듀서가 메시지를 발행할 때 토픽이 auto-create 되는데, 이 때 컨슈머 측에서 rebalance가 발생한다. rebalance 완료 후 `latest` 리셋이 적용되면, 이미 발행된 메시지가 누락된다.

---

## 3. 해결

테스트 전용 프로파일 설정(`application-test.yaml`)에 `auto-offset-reset: earliest` 를 추가한다.

```yaml
# order-service/src/test/resources/application-test.yaml
spring:
  kafka:
    consumer:
      auto-offset-reset: earliest
```

`earliest` 로 설정하면, 커밋된 offset이 없을 때 파티션의 처음(0)부터 읽는다. 컨슈머의 파티션 할당이 늦어지더라도 발행된 메시지를 소급해서 수신할 수 있다.

테스트 클래스에 `@ActiveProfiles("test")` 가 없으면 이 설정이 로드되지 않으므로, 해당 클래스에 어노테이션을 추가한다.

```java
@SpringBootTest
@Testcontainers
@ActiveProfiles("test")   // 추가
class OrderEventFlowTest { ... }

@SpringBootTest
@Testcontainers
@ActiveProfiles("test")   // 추가
@Import(OrderPubSubTest.SecondGroupConsumer.class)
class OrderPubSubTest { ... }
```

---

## 4. 비고

**프로덕션에서 `earliest` 를 쓰면 안 되는 이유**

`auto-offset-reset: earliest` 를 프로덕션에 적용하면, 컨슈머 그룹의 offset이 브로커에서 만료(삭제)됐을 때 처음부터 재처리된다. 대용량 토픽에서 Pod 재시작이나 그룹 재생성 시 중복 처리가 발생할 수 있어 위험하다.

**`auto-offset-reset` 이 동작하는 조건**

`auto-offset-reset` 은 **커밋된 offset이 없거나 out-of-range일 때만** 적용된다. 한 번 offset이 커밋되면 이후 재시작에서는 커밋된 위치에서 재개되며, 이 설정은 무시된다. 따라서 `earliest` 로 설정해도 정상적인 운영 중에는 메시지를 이중 처리하지 않는다.

**결론**: `auto-offset-reset: earliest` 는 테스트 환경 전용으로 격리해서 사용한다.
