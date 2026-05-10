---
title: "Kafka 통합 테스트 — 컨테이너 종료 후 JVM hang"
weight: 2
date: 2026-05-11
---

## 1. 문제

Testcontainers 기반 Kafka 통합 테스트에서 테스트는 모두 통과하지만 **Gradle 테스트 프로세스가 종료되지 않고 멈춘다.** 테스트 클래스가 끝난 후에도 다음 경고가 반복 출력된다.

```
WARN [log-service] [vice-producer-1] o.a.k.c.NetworkClient :
  [Producer clientId=log-service-producer-1]
  Connection to node 1 (localhost/127.0.0.1:32989) could not be established.
  Node may not be available.

INFO [log-service] [ntainer#0-0-C-1] o.a.k.c.NetworkClient :
  [Consumer clientId=consumer-log-service-2, groupId=log-service] Node 1 disconnected.
```

---

## 2. 원인

**Spring 컨텍스트 캐싱 + Testcontainers 컨테이너 종료 순서 불일치 → Kafka 클라이언트 non-daemon 스레드가 JVM 종료를 막는다.**

```
[테스트 클래스 종료]
  ├─ Testcontainers: 정적 컨테이너(@Container static) 중지
  │    → Kafka 브로커가 내려감 (port 32989 닫힘)
  └─ Spring: 컨텍스트 캐싱으로 인해 ApplicationContext 유지
       → Kafka 프로듀서 · 컨슈머 background 스레드 살아있음
       → 죽은 브로커에 재연결 시도 (reconnect backoff loop)
       → 해당 스레드가 non-daemon → JVM 종료 불가
```

Kafka 클라이언트의 `NetworkClient`, `KafkaProducer`, `Fetcher` 등의 I/O 스레드는 기본적으로 **non-daemon** 스레드다. JVM은 non-daemon 스레드가 하나라도 살아있으면 종료되지 않는다.

Spring의 테스트 컨텍스트 캐싱은 성능 최적화를 위해 ApplicationContext를 재사용하는데, 테스트 클래스마다 `@ServiceConnection` 컨테이너 포트가 달라 실제로는 컨텍스트를 공유하지 않는다. 그럼에도 **캐시된 컨텍스트는 명시적으로 닫지 않으면 JVM 종료 시점까지 살아있다.**

---

## 3. 해결

`@DirtiesContext(classMode = AFTER_CLASS)` 를 테스트 클래스에 추가한다.

```java
@SpringBootTest
@Testcontainers
@DirtiesContext(classMode = DirtiesContext.ClassMode.AFTER_CLASS)
class SystemLogFlowTest { ... }
```

### `@DirtiesContext` 란?

Spring 테스트 컨텍스트가 **"오염(dirty)"됐다고 표시**해서, 다음 테스트 실행 전(또는 현재 클래스 종료 후)에 컨텍스트를 강제로 닫고 재생성하도록 지시하는 어노테이션이다.

| classMode | 동작 |
|---|---|
| `BEFORE_CLASS` | 클래스 시작 전 컨텍스트 닫기 |
| `AFTER_CLASS` | 클래스 종료 후 컨텍스트 닫기 ← 이 이슈에 적합 |
| `BEFORE_EACH_TEST_METHOD` | 각 테스트 전 닫기 |
| `AFTER_EACH_TEST_METHOD` | 각 테스트 후 닫기 |

`AFTER_CLASS` 를 사용하면 테스트 클래스의 모든 테스트가 끝난 뒤 컨텍스트가 닫힌다. 컨텍스트가 닫히면 `@PreDestroy`, `DisposableBean.destroy()`, `SmartLifecycle.stop()` 등 소멸 콜백이 순서대로 실행된다. Spring Kafka는 이 시점에 `KafkaListenerContainerFactory`, `KafkaProducer` 등을 정상 종료하며 background 스레드를 정리한다.

**효과**:
```
[테스트 클래스 종료]
  ├─ @DirtiesContext AFTER_CLASS 동작
  │    → ApplicationContext.close() 호출
  │    → Kafka Producer/Consumer destroy → background 스레드 종료
  └─ Testcontainers: 컨테이너 중지
       → 이미 클라이언트가 종료됐으므로 재연결 시도 없음
       → JVM 정상 종료
```

### 성능 영향

`@ServiceConnection` 으로 컨테이너 포트가 동적으로 결정되기 때문에 **각 테스트 클래스는 어차피 별도 컨텍스트를 생성한다.** `@DirtiesContext` 를 추가해도 컨텍스트 재사용 이점이 없으므로 성능 손실이 없다.

---

## 4. 비고

**`junit-platform-launcher` 만으로는 부족하다**

```kotlin
testRuntimeOnly("org.junit.platform:junit-platform-launcher")
```

이 의존성은 Gradle 테스트 워커가 테스트 완료를 인식하고 종료 신호를 보내는 데 도움을 준다. 하지만 non-daemon 스레드가 살아있으면 JVM 자체가 종료되지 않기 때문에, 이 의존성만으로는 hang 문제가 해결되지 않는다. **`@DirtiesContext` 로 컨텍스트를 명시적으로 닫아야** 스레드가 정리된다.

**Testcontainers Reuse 옵션과의 관계**

`testcontainers.reuse.enable=true` 를 사용해 컨테이너를 테스트 클래스 간에 재사용하는 경우, `@DirtiesContext` 로 컨텍스트가 닫혀도 컨테이너 자체는 살아있으므로 다음 테스트가 빠르게 재사용할 수 있다. 이 프로젝트는 현재 재사용을 쓰지 않으므로 해당 없다.
