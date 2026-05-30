---
title: "3. 코드 구성하기"
weight: 3
date: 2026-05-26
---

## 1. 계층 이름의 관점 차이

### 1.1. Spring 역할 이름과 아키텍처 계층 이름

Spring 예제나 실무 CRUD 코드에서는 보통 패키지를 아래처럼 나눈다.

```text
controller
service
repository
```

이건 Spring stereotype이나 클래스 역할 기준의 이름이다.

반면 책에서는 계층형 아키텍처를 아래처럼 표현한다.

```text
web
domain
persistence
```

이건 아키텍처 계층 기준의 이름이다.
둘은 완전히 다른 구조라기보다 같은 계층형 구조를 다른 관점에서 부르는 것이다.

| 책 표현 | 흔한 Spring 표현 | 의미 |
|---|---|---|
| `web` | `controller`, `request`, `response` | 외부 요청/응답 처리 |
| `domain` | `service`, `domain model` | 비즈니스 규칙, 유스케이스 |
| `persistence` | `repository`, `entity`, mapper | DB 접근, ORM 매핑 |

정리하면 다음처럼 보면 된다.

```text
web           ≈ controller layer
domain        ≈ service/domain layer
persistence   ≈ repository layer
```

`controller/service/repository`는 Spring에서 어떤 종류의 클래스를 만드는지에 가깝고,
`web/domain/persistence`는 아키텍처 책임과 의존성 방향을 설명하기에 더 적합하다.

### 1.2. 왜 `domain`이라고 부르는가

`service`라고만 부르면 비즈니스 계층이 service class 하나로 좁게 보일 수 있다.
하지만 실제 domain 계층에는 service뿐 아니라 도메인 모델과 유스케이스도 함께 들어갈 수 있다.

```text
domain
├── Account
├── Money
├── Activity
├── SendMoneyService
└── SendMoneyUseCase
```

그래서 아키텍처를 설명할 때는 `service`보다 `domain`이라는 표현이 더 넓고 정확하다.

## 2. 계층으로 구성하기

계층 기준 패키징은 기술적 역할에 따라 코드를 나눈다.
BuckPal 예제로 보면 다음과 비슷하다.

```text
buckpal
├── domain
│   ├── Account
│   ├── Activity
│   ├── Money
│   ├── AccountRepository      ← interface
│   └── AccountService
├── persistence
│   ├── SpringDataAccountRepository
│   ├── AccountJpaEntity
│   └── ActivityJpaEntity
└── web
    ├── AccountController
    ├── SendMoneyRequest
    └── AccountResource
```

의존성은 아래처럼 역전시킬 수 있다.

```text
domain
  └── AccountRepository interface
          ▲
          │ implements
persistence
  └── SpringDataAccountRepository
```

도메인 계층은 repository interface만 알고,
영속성 계층이 그 interface를 구현한다.
이렇게 하면 도메인이 persistence 구현체에 직접 의존하지 않는다.

하지만 계층 기준 패키징에는 문제가 있다.

| 문제 | 설명 |
|---|---|
| 기능 경계가 보이지 않음 | `account`, `payment`, `order` 같은 기능 단위 패키지 경계가 없어 새 기능을 어디에 넣을지 애매함 |
| 유스케이스가 보이지 않음 | `AccountService`만 봐서는 송금, 입금, 출금, 조회 중 어떤 유스케이스를 제공하는지 드러나지 않음 |
| 어댑터 방향이 보이지 않음 | `web`, `persistence`를 직접 열어봐야 어떤 incoming/outgoing port와 연결되는지 알 수 있음 |

계층형 패키지는 기술적 역할은 잘 보여준다.
하지만 애플리케이션이 제공하는 기능과 포트/어댑터 구조는 잘 드러나지 않는다.

## 3. 기능으로 구성하기

기능 기준 패키징은 같은 기능에 속한 클래스를 한 패키지에 모은다.

```text
buckpal
└── account
    ├── Account
    ├── Activity
    ├── Money
    ├── SendMoneyService
    ├── SendMoneyUseCase
    ├── AccountRepository
    ├── SpringDataAccountRepository
    ├── AccountJpaEntity
    ├── ActivityJpaEntity
    ├── AccountController
    └── SendMoneyRequest
```

이 방식은 기능 경계가 명확하다.
`account` 기능을 수정하려면 `account` 패키지 안을 보면 된다.

또한 Java의 package-private 접근 수준을 활용할 수 있다.
외부에 공개할 필요가 없는 클래스는 `public`을 제거해서 패키지 안에서만 접근하게 만든다.

```java
class SendMoneyService implements SendMoneyUseCase {
}
```

이렇게 하면 다른 기능 패키지에서 내부 구현체를 직접 참조하기 어려워진다.
기능 간 불필요한 의존성을 줄일 수 있다.

그리고 `AccountService`처럼 넓은 이름보다 `SendMoneyService`처럼 유스케이스를 드러내는 이름을 쓰면 책임이 좁아진다.

```text
AccountService
  → 무엇을 하는지 불명확

SendMoneyService
  → 송금하기 유스케이스 담당
```

이런 구조는 로버트 C. 마틴이 말한 Screaming Architecture와도 맞닿아 있다.
코드 구조만 봐도 애플리케이션이 무엇을 하는지 보여야 한다는 관점이다.

하지만 기능 기준 패키징도 한계가 있다.

| 문제 | 설명 |
|---|---|
| 아키텍처 가시성 저하 | adapter, port, application 같은 구조가 패키지명에서 드러나지 않음 |
| 포트 확인 어려움 | incoming port와 outgoing port가 어디 있는지 직접 파일을 열어봐야 함 |
| 의존성 역전 약화 가능 | 같은 패키지 안에 도메인과 영속성 코드가 섞여 package-private으로 서로 접근할 수 있음 |

기능 경계는 잘 보이지만,
Hexagonal Architecture의 핵심 구조는 잘 보이지 않는다.

## 4. 아키텍처적으로 표현력 있는 패키지 구조

Hexagonal Architecture에서 드러내야 할 핵심 요소는 다음과 같다.

| 요소 | 의미 |
|---|---|
| entity | 도메인 모델 |
| use case | 애플리케이션이 제공하는 기능 |
| incoming port | 외부가 애플리케이션을 호출하는 진입점 |
| outgoing port | 애플리케이션이 외부 시스템을 호출하기 위한 interface |
| incoming adapter | web, batch, CLI처럼 애플리케이션을 호출하는 adapter |
| outgoing adapter | DB, message broker, 외부 API처럼 애플리케이션에 의해 호출되는 adapter |

이를 패키지 구조로 표현하면 다음처럼 만들 수 있다.

```text
buckpal
└── account
    ├── adapter
    │   ├── in
    │   │   └── web
    │   │       ├── AccountController
    │   │       └── SendMoneyRequest
    │   └── out
    │       └── persistence
    │           ├── AccountPersistenceAdapter
    │           ├── SpringDataAccountRepository
    │           ├── AccountJpaEntity
    │           └── ActivityJpaEntity
    ├── application
    │   ├── port
    │   │   ├── in
    │   │   │   ├── SendMoneyUseCase
    │   │   │   └── GetAccountBalanceQuery
    │   │   └── out
    │   │       ├── LoadAccountPort
    │   │       └── UpdateAccountStatePort
    │   └── service
    │       ├── SendMoneyService
    │       └── GetAccountBalanceService
    └── domain
        ├── Account
        ├── Activity
        └── Money
```

이 구조는 기능 기준 패키징과 아키텍처 기준 패키징을 같이 드러낸다.

```text
account
  → 기능 경계

adapter / application / domain
  → 아키텍처 경계

port.in / port.out
  → incoming / outgoing 의존성 경계
```

의존성 방향은 다음처럼 읽을 수 있다.

```text
adapter.in.web
  → application.port.in
    → application.service
      → domain
      → application.port.out
        ← adapter.out.persistence
```

`adapter.in.web`은 incoming adapter다.
외부 HTTP 요청을 받아 application의 incoming port를 호출한다.

`adapter.out.persistence`는 outgoing adapter다.
application의 outgoing port를 구현해서 DB 접근을 담당한다.

이 구조의 장점은 패키지명만 봐도 코드의 역할과 의존성 방향을 어느 정도 알 수 있다는 점이다.
즉 코드 구조가 아키텍처를 설명한다.

### 4.1. 패키지 경계와 접근 제한

`adapter` 패키지 안의 클래스들은 application 계층의 port interface를 통하지 않고는 바깥에서 호출될 필요가 없다.

```text
adapter.in.web
  → application.port.in

application.service
  → application.port.out
    ← adapter.out.persistence
```

즉 adapter 구현체는 애플리케이션의 public API가 아니다.
웹 컨트롤러나 영속성 어댑터는 framework가 생성하거나 DI container가 연결할 대상일 뿐,
다른 도메인 코드가 직접 호출해야 하는 대상이 아니다.

그래서 가능하면 adapter 내부 클래스는 package-private 수준으로 둘 수 있다.

```java
class AccountPersistenceAdapter implements LoadAccountPort {
}
```

이렇게 하면 application 계층에서 adapter 구현체로 향하는 우발적 의존성을 줄일 수 있다.
application 계층은 adapter class를 직접 알지 않고 port interface만 알면 된다.

### 4.2. 장점

첫 번째 장점은 adapter 교체가 쉽다는 점이다.

예를 들어 처음에는 key-value DB를 사용하다가 SQL DB로 바꾼다고 하자.
application 계층의 outgoing port는 그대로 둔다.
바뀌는 것은 adapter 구현체다.

```text
application.port.out
  ├── LoadAccountPort
  └── UpdateAccountStatePort

adapter.out.persistence.keyvalue
  └── KeyValueAccountPersistenceAdapter implements LoadAccountPort, UpdateAccountStatePort

adapter.out.persistence.sql
  └── SqlAccountPersistenceAdapter implements LoadAccountPort, UpdateAccountStatePort
```

여기서 "아웃고잉 포트들을 새로운 어댑터 패키지에 구현한다"는 말은,
port interface 자체를 adapter 패키지로 옮긴다는 뜻이 아니다.

정확한 의미는 다음과 같다.

```text
port interface 위치:
  application.port.out

port 구현체 위치:
  adapter.out.persistence.*
```

즉 port는 application 안에 그대로 두고,
새 adapter 패키지에 그 port를 `implements`하는 구현체를 만든다는 의미다.

두 번째 장점은 DDD 개념과 대응하기 쉽다는 점이다.

```text
account
  → bounded context 후보

account.domain
  → entity, value object, aggregate, domain rule

account.application.port
  → bounded context와 외부 세계가 통신하는 진입점
```

`account` 같은 상위 패키지는 하나의 bounded context처럼 볼 수 있다.
그 안의 `domain` 패키지에서는 DDD의 도구를 사용해 도메인 모델을 자유롭게 만들 수 있다.
도메인 모델은 JPA entity, web request DTO, 외부 API schema 같은 기술 모델에 끌려가지 않는다.

### 4.3. 의존성 주입의 역할

Clean Architecture의 핵심 조건은 application 계층이 incoming adapter와 outgoing adapter에 의존하지 않는 것이다.

incoming 방향은 쉽다.
제어 흐름과 의존성 방향이 같다.

```text
adapter.in.web
  → application.port.in
```

웹 컨트롤러가 `SendMoneyUseCase` interface를 호출한다.
컨트롤러가 application을 의존하므로 의존성 방향이 안쪽을 향한다.

outgoing 방향은 다르다.
application service는 DB를 호출해야 하지만,
DB adapter에 직접 의존하면 의존성 방향이 바깥으로 샌다.

그래서 application 계층에 outgoing port interface를 둔다.
adapter는 그 interface를 구현한다.

```text
application.service
  → application.port.out.LoadAccountPort
      ← adapter.out.persistence.AccountPersistenceAdapter
```

문제는 실제 객체 연결이다.
`SendMoneyService`는 `LoadAccountPort` interface가 필요하다.
하지만 application 계층 안에서 `new AccountPersistenceAdapter()`를 하면 adapter 의존성이 생긴다.

```java
class SendMoneyService {
    private final LoadAccountPort loadAccountPort;

    SendMoneyService(LoadAccountPort loadAccountPort) {
        this.loadAccountPort = loadAccountPort;
    }
}
```

따라서 중립적인 조립자가 필요하다.
Spring 같은 DI container가 이 역할을 한다.

```text
adapter.in.web              application.port.in          application.service          application.port.out          adapter.out.persistence
──────────────              ───────────────────          ───────────────────          ────────────────────          ───────────────────────

AccountController ────────▶ SendMoneyUseCase ◀────────── SendMoneyService ─────────▶ LoadAccountPort ◀──────────── AccountPersistenceAdapter ───▶ SpringDataAccountRepository ───▶ Database
                                                     implements                                                   implements

Spring DI Container
  ├─ injects AccountController
  ├─ injects SendMoneyService
  └─ injects AccountPersistenceAdapter
```

호출 흐름은 다음과 같다.

```text
AccountController
  → SendMoneyUseCase
    → SendMoneyService
      → LoadAccountPort
        → AccountPersistenceAdapter
          → SpringDataAccountRepository
            → Database
```

의존성 방향은 다르다.

```text
adapter.in.web
  → application.port.in
application.service
  → application.port.out
adapter.out.persistence
  → application.port.out
```

Spring은 런타임에 `LoadAccountPort` 자리에 `AccountPersistenceAdapter` 구현체를 주입한다.
덕분에 application 계층은 adapter 구현체를 모르면서도 외부 시스템을 사용할 수 있다.

이 패키지 구조를 따르면 코드를 탐색할 때 아키텍처 요소를 바로 찾을 수 있다.
`application`, `adapter.in.web`, `adapter.out.persistence`를 따라가면 하나의 유스케이스가 어떻게 요청을 받고,
도메인 로직을 실행하고, 영속성 어댑터를 호출하는지 확인할 수 있다.

참고:

- [도서] 만들면서 배우는 클린 아키텍처 - 톰 홈버그(Tom Hombergs)
- [Screaming Architecture - Robert C. Martin](https://blog.cleancoder.com/uncle-bob/2011/09/30/Screaming-Architecture.html)
- [Spring Framework Reference - Stereotype Annotations](https://docs.spring.io/spring-framework/reference/core/beans/classpath-scanning.html#beans-stereotype-annotations)
