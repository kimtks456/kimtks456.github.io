---
title: "@IdempotentConsumer — 멱등성 패턴 설계 분석"
weight: 4
date: 2026-05-11
---

작성된 코드는 엔터프라이즈 환경에서 Kafka의 **At-least-once 전송 보장**으로 인해 필연적으로 발생하는 **메시지 중복 수신 문제를 방어하기 위한 멱등성(Idempotency) 패턴**이다.

비즈니스 로직(Consumer)과 인프라 로직(Redis 체크)을 AOP로 완벽하게 분리한 구조다.

---

## 1. 핵심 개념 — Redis `SET NX`

`SET NX`는 "SET if Not eXists(존재하지 않을 때만 저장)"의 Redis 명령어 옵션이다. Spring Data Redis에서는 `setIfAbsent()`로 제공한다.

여러 Consumer Pod이 떠 있는 분산 환경에서, 네트워크 지연이나 리밸런싱 때문에 **동일한 이벤트(예: 주문 완료 ID: 123)가 컨슈머 A와 B에 동시에 들어올 수 있다.**

**일반 `SET`의 문제:**
- 컨슈머 A도 DB에 저장 후 Redis에 "처리 완료" 기록
- 컨슈머 B도 DB에 저장 후 Redis에 덮어쓰기 → 중복 저장 발생

**`SET NX`의 해결:**
1. 컨슈머 A와 B가 동시에 `SET NX "idempotency:123"`을 요청
2. Redis는 싱글 스레드 기반이므로 단 하나의 요청만 승인(true 반환) — 원자성 보장
3. 늦은 컨슈머 B는 거절(false 반환)
4. 거절당한 B는 조용히 로직을 스킵(`return null`)

---

## 2. 코드 동작 흐름

이벤트가 `@IdempotentConsumer` 어노테이션이 붙은 메서드로 진입할 때의 순서다.

**① AOP 인터셉트 (`IdempotencyAspect.around`)**

이벤트가 실제 비즈니스 로직에 도달하기 전에 Aspect가 먼저 가로챈다.

```java
if (args.length == 0 || !(args[0] instanceof KafkaEvent event)) {
    return pjp.proceed();
}
```

Java 16+ 패턴 매칭으로 null 체크와 타입 캐스팅을 동시에 처리했다.

**② 키(Key) 생성**

```java
String key = switch (idempotentConsumer.keyType()) {
    case EVENT_ID    -> event.eventId();
    case AGGREGATE_ID -> event.aggregateId();
};
```

| keyType | 설명 | 권장 여부 |
|---------|------|-----------|
| `EVENT_ID` | 메시지 자체의 고유 ID. 동일 메시지 재전송 방어. 프로듀서 재시도 시 새 eventId가 생성되므로 재시도는 정상 처리된다. | **기본값으로 사용** |
| `AGGREGATE_ID` | 주문 번호 같은 도메인 ID. **주의:** 프로듀서가 재시도 시 새 eventId + 같은 aggregateId로 발행하면 재시도가 차단된다. "TTL 내 동일 aggregateId 이벤트는 1회만 처리"라는 의도적 비즈니스 룰에만 사용할 것. | 특수 케이스 한정 |

**③ Redis `SET NX` 시도 (`store.setIfAbsent`)**

```java
if (!store.setIfAbsent(key, idempotentConsumer.ttlSeconds())) {
    log.info("[Idempotency] 중복 이벤트 skip. key={}", key);
    return null;
}
```

false 반환 시 → 이미 처리 중이거나 완료된 이벤트 → 스킵

**④ 비즈니스 로직 실행 및 예외 처리**

```java
try {
    return pjp.proceed();
} catch (Exception e) {
    store.delete(key);  // 핵심 안전장치
    throw e;
}
```

에러 발생 시 반드시 `store.delete(key)`로 점유한 Key를 삭제해야 한다. 그렇지 않으면 Kafka가 재시도(Retry)할 때 멱등성 로직에 막혀 영원히 처리되지 않는다.

---

## 3. 코드 리뷰

### 👍 잘된 점

- **비침투적 설계**: 비즈니스 로직 개발자는 `@IdempotentConsumer` 하나만 붙이면 되고, Redis 코드를 전혀 볼 필요 없다.
- **안전한 예외 복구**: `catch` 블록에서 `delete(key)`를 수행해 재시도 가능성을 열어둔다.
- **TTL 활용**: Key가 무한히 쌓여 Redis 메모리가 터지는 것을 `ttlSeconds`로 방지한다.

### 💡 Zombie Lock 문제와 TTL 전략

**시나리오:**
1. 컨슈머가 `SET NX` 성공 → 비즈니스 로직 실행 중
2. Pod에 OOM 또는 강제 종료 발생 → 프로세스 증발
3. `catch` 블록의 `store.delete(key)` 실행 불가
4. Redis에 TTL 시간만큼 Key가 남아있음
5. Kafka가 다른 컨슈머에게 재할당하지만, 새 컨슈머는 Key를 보고 "이미 처리됨"으로 간주 → **메시지 유실**

**대응 전략 — TTL을 짧게**

| TTL 길이 | Zombie Lock 영향 | 중복 방지 범위 |
|----------|-----------------|---------------|
| 86400초 (24시간) | 24시간 동안 재처리 불가 | 넓음 |
| 10초 | Kafka 리밸런싱(~45초) 완료 전에 만료 → 재처리 가능 | 좁음 (수 초 이내 중복만 방어) |

현재 코드는 `ttlSeconds = 10`으로 설정돼 있다. 비즈니스 로직 실행 시간(< 1초)보다 충분히 길고, Pod 재시작 후 Kafka 리밸런싱 완료 시점(~45초)보다 짧아 Zombie Lock이 해소된다.

> **한계**: 이 패턴은 분산 락(Distributed Lock)이 아닌 멱등성 캐시이므로 TTL이 만료된 후 동일 메시지가 재전송되면 중복 처리될 수 있다. 완전한 exactly-once가 필요하면 Kafka 트랜잭션 + DB 유니크 제약 조합을 검토할 것.

---

## 4. 전체 구조 요약

```
Kafka 메시지 수신
    │
    ▼
[IdempotencyAspect]
    │
    ├─ KafkaEvent 타입 확인
    ├─ keyType에 따라 key 추출 (EVENT_ID / AGGREGATE_ID)
    ├─ Redis SET NX (setIfAbsent)
    │       │
    │       ├─ false (이미 존재) → return null (스킵)
    │       │
    │       └─ true (새 key) → 비즈니스 로직 실행
    │                   │
    │                   ├─ 성공 → 완료 (key는 TTL로 자동 만료)
    │                   └─ 예외 → delete(key) → 예외 재발생 (재시도 가능)
    │
    ▼
비즈니스 메서드 (handle)
```
