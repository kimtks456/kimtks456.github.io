---
title: "5. 웹 어댑터 구현하기"
weight: 5
date: 2026-05-30
---

## 1. 의존성 역전

오늘날 대부분의 애플리케이션은 웹 인터페이스를 제공한다.
웹 브라우저 같은 UI나 다른 시스템이 HTTP API를 통해 애플리케이션을 호출한다.

Hexagonal Architecture 관점에서 웹 어댑터는 **주도하는(driving) 어댑터**이자 **인커밍(incoming) 어댑터**다.
외부 요청을 받아 애플리케이션 코어를 호출하기 때문이다.

---

### 1.1. 웹 어댑터가 서비스를 직접 호출하는 경우

제어 흐름은 보통 왼쪽에서 오른쪽으로 흐른다.
웹 어댑터가 요청을 받고, application service를 호출한다.

```text
account.adapter.in.web          account.application.service
──────────────────────          ───────────────────────────

AccountController ────────────▶ SendMoneyService
```

이 구조는 단순하다.
하지만 웹 어댑터가 application service 구현체를 직접 알게 된다.

즉 incoming port가 없다.
애플리케이션 코어가 외부에 어떤 유스케이스를 제공하는지 interface로 드러나지 않는다.

이런 직접 호출은 의식적으로 선택할 수 있는 지름길이다.
자세한 판단 기준은 [11. 의식적으로 지름길 사용하기](./11_taking-shortcuts-consciously/)에서 다시 다룬다.

---

### 1.2. 인커밍 포트를 두는 경우

의존성 역전 원칙을 적용하면 웹 어댑터와 유스케이스 사이에 incoming port가 생긴다.

```text
account.adapter.in.web          account.application.port.in          account.application.service          account.application.port.out          account.adapter.out.persistence
──────────────────────          ───────────────────────────          ───────────────────────────          ───────────────────────────          ───────────────────────────────

AccountController ────────────▶ <<Interface>>
                                SendMoneyUseCase ◀───────────────── SendMoneyService ─────────────────▶ <<Interface>>
                                                                    implements                         UpdateAccountStatePort ◀──────────── AccountPersistenceAdapter
                                                                                                                                            implements
```

웹 어댑터는 `SendMoneyService` 구현체가 아니라 `SendMoneyUseCase` port를 호출한다.

```text
adapter.in.web
  → application.port.in
    ← application.service
```

port는 애플리케이션 코어가 외부와 통신하는 명세다.
따라서 어댑터와 유스케이스 사이의 간접 계층은 단순한 추상화가 아니라,
애플리케이션이 외부에 제공하는 계약을 명시하는 역할을 한다.

---

### 1.3. 웹 어댑터가 아웃고잉 어댑터가 되는 경우

웹 어댑터는 보통 인커밍 어댑터다.
하지만 WebSocket처럼 애플리케이션이 client로 데이터를 보내야 하는 경우도 있다.

이 경우 application core가 웹 쪽으로 메시지를 보내야 하므로 outgoing port가 필요하다.
outgoing port는 application 계층에 있고, 웹 어댑터가 이를 구현한다.

```text
account.application.service          account.application.port.out          account.adapter.in.web          client
───────────────────────────          ───────────────────────────          ──────────────────────          ──────

SendNotificationService ───────────▶ <<Interface>>
                                    ClientNotificationPort ◀──────────── WebSocketController ───────────▶ Client
                                                                        implements
```

이 구조에서는 하나의 웹 어댑터가 두 역할을 할 수 있다.

| 역할 | 설명 |
|---|---|
| incoming adapter | HTTP 요청을 받아 application port를 호출 |
| outgoing adapter | application core가 보내려는 메시지를 client로 전달 |

하나의 어댑터가 incoming과 outgoing 역할을 동시에 해도 된다.
다만 이후 내용에서는 웹 어댑터가 incoming adapter 역할만 한다고 가정한다.

---

## 2. 웹 어댑터의 책임

웹 어댑터는 HTTP와 application 계층 사이를 변환한다.
일반적으로 다음 책임을 가진다.

1. HTTP 요청을 Java 객체로 매핑
2. 권한 검사
3. 입력 유효성 검증
4. 입력을 유스케이스 입력 모델로 매핑
5. 유스케이스 호출
6. 유스케이스 출력을 HTTP 응답으로 매핑
7. HTTP 응답 반환

여기서 입력 유효성 검증은 앞 장에서 말한 유스케이스 입력 모델의 검증과 다르다.
웹 어댑터가 검증하는 것은 웹 입력 모델이다.

```text
HTTP request
  → web input model
  → use case input model
```

웹 어댑터는 요청이 유스케이스 입력 모델로 변환될 수 있는지 확인한다.
예를 들어 path variable, query parameter, request body가 필요한 형태로 들어왔는지 확인한다.
이 검증이 끝나면 자연스럽게 다음 단계인 유스케이스 입력 모델 매핑으로 이어진다.

반면 유스케이스 입력 모델은 application 계층의 계약이다.
유스케이스가 필요로 하는 값이 의미상 유효한지 검증한다.

웹 어댑터의 책임은 많아 보인다.
하지만 대부분 HTTP와 관련된 일이다.
HTTP 관련 관심사가 application 계층으로 침투하면 안 된다.

---

## 3. 컨트롤러 나누기

웹 어댑터는 하나 이상의 controller 클래스로 구성할 수 있다.
모든 요청을 하나의 controller에 모을 필요는 없다.
보통 너무 적은 controller보다 여러 작은 controller가 낫다.

자주 보이는 방식은 하나의 `AccountController`가 계좌 관련 모든 요청을 받는 것이다.

```java
@RestController
@RequestMapping("/accounts")
class AccountController {

    @PostMapping
    ResponseEntity<AccountResource> createAccount(
            @RequestBody AccountResource resource
    ) {
        // ...
    }

    @GetMapping("/{accountId}")
    ResponseEntity<AccountResource> getAccount(
            @PathVariable Long accountId
    ) {
        // ...
    }

    @PutMapping("/{accountId}")
    ResponseEntity<AccountResource> updateAccount(
            @PathVariable Long accountId,
            @RequestBody AccountResource resource
    ) {
        // ...
    }

    @DeleteMapping("/{accountId}")
    ResponseEntity<Void> deleteAccount(
            @PathVariable Long accountId
    ) {
        // ...
    }

    @PostMapping("/{sourceAccountId}/send/{targetAccountId}")
    ResponseEntity<Void> sendMoney(
            @PathVariable Long sourceAccountId,
            @PathVariable Long targetAccountId,
            @RequestBody SendMoneyRequest request
    ) {
        // ...
    }
}
```

이 방식은 처음에는 단순하다.
하지만 단점이 있다.

첫째, 클래스는 작을수록 이해하기 쉽다.
저자는 가장 큰 클래스가 3만 줄인 레거시 프로젝트를 담당한 적이 있다고 한다.
재배포 없이 런타임에 변경하기 위해 컴파일된 Java bytecode를 하나의 `.class` 파일로 올려야 했기 때문이다.
그런 상황에서는 200줄을 추가로 파악하는 것조차 큰 부담이 된다.

테스트 코드도 마찬가지다.
controller가 커지면 테스트도 커지고,
테스트 코드는 보통 추상화가 많아서 운영 코드보다 읽기 어려울 수 있다.

둘째, 큰 controller는 데이터 구조 재사용을 유도한다.
위 예시의 `AccountResource`가 여러 메서드에서 공유되면,
모든 요청/응답에 필요한 데이터를 담는 큰 모델이 되기 쉽다.

```text
createAccount
  → id 필요 없음

updateAccount
  → id 필요

getAccount
  → 전체 응답 필요

AccountResource
  → 모든 필드를 다 가짐
```

이런 공유 모델은 사용하지 않는 필드가 생기고,
어떤 필드가 어떤 유스케이스에서 필요한지 헷갈리게 만든다.

저자는 가급적 별도 패키지 안에 별도 controller를 만드는 방식을 선호한다.
예를 들어 송금 유스케이스는 별도 controller로 둘 수 있다.

```java
@RestController
@RequestMapping("/accounts")
class SendMoneyController {

    private final SendMoneyUseCase sendMoneyUseCase;

    @PostMapping("/{sourceAccountId}/send/{targetAccountId}")
    ResponseEntity<Void> sendMoney(
            @PathVariable Long sourceAccountId,
            @PathVariable Long targetAccountId,
            @RequestBody SendMoneyRequest request
    ) {
        // ...
    }

    private static class SendMoneyRequest {
        private Money amount;
    }
}
```

이 방식의 장점은 다음과 같다.

| 장점 | 설명 |
|---|---|
| 전용 모델 사용 | `CreateAccountResource`, `UpdateAccountResource`, `SendMoneyRequest` 같은 전용 모델을 둘 수 있음 |
| 재사용 방지 | controller 내부 private class로 두면 다른 곳에서 재사용할 수 없음 |
| 명확한 이름 | `CreateAccount`보다 `RegisterAccount`처럼 실제 사용자 의도를 드러내는 이름을 고민할 수 있음 |
| 동시 작업 | 여러 개발자가 서로 다른 controller를 동시에 수정하기 쉬움 |

물론 `Create`, `Update`, `Delete`만으로 의미가 충분히 드러나는 경우도 있다.
하지만 이름을 붙일 때 한 번 더 유스케이스의 의도를 고민해야 한다.

---

## 4. 유지보수 가능한 소프트웨어를 만드는 데 어떻게 도움이 될까

웹 어댑터는 HTTP 요청을 application 계층으로 전달하고,
application 계층의 출력을 HTTP 응답으로 변환한다.

웹 어댑터 안에는 도메인 로직이 없어야 한다.

```text
HTTP parsing
authorization
web input validation
mapping
use case call
HTTP response mapping
```

이런 작업은 웹 어댑터의 책임이다.
반대로 application 계층은 HTTP를 몰라야 한다.
그래야 HTTP adapter를 CLI, batch, message consumer 같은 다른 adapter로 교체할 수 있다.

controller를 나눌 때는 모델을 공유하지 않는 여러 작은 클래스로 나누는 습관을 들이는 것이 좋다.
작은 controller와 유스케이스별 요청/응답 모델은 변경 범위를 줄이고,
테스트와 동시 작업을 쉽게 만든다.

---

## 5. 참고

- [도서] 만들면서 배우는 클린 아키텍처 - 톰 홈버그(Tom Hombergs)
