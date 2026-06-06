---
title: "11. 의식적으로 지름길 사용하기"
weight: 11
date: 2026-05-28
---

> **Note: 4, 5장에서 넘어온 논점**
>
> [4. 유스케이스 구현하기](./4_implement-use-case/)와 [5. 웹 어댑터 구현하기](./5_implement-web-adapter/)에서는 다음 지름길 후보가 나왔다.
>
> 1. 엔티티를 유스케이스의 입력/출력 모델로 그대로 사용하는 문제.
>    `Account` 같은 도메인 entity를 그대로 반환하면 빠르지만,
>    호출자에게 필요 없는 데이터가 노출되고 유스케이스 간 출력 모델 결합이 생길 수 있다.
> 2. 읽기 전용 쿼리에서 application service를 생략하고 client가 outgoing port를 직접 호출할 수 있는지에 대한 문제.
>    단순 조회에서는 효율적일 수 있지만,
>    application 계층의 유스케이스 경계가 흐려질 수 있다.
> 3. 웹 어댑터가 incoming port를 거치지 않고 application service 구현체를 직접 호출하는 문제.
>    단순한 애플리케이션에서는 빠른 선택일 수 있지만,
>    애플리케이션 코어가 외부에 제공하는 유스케이스 계약이 흐려질 수 있다.
>
> 이 장에서는 이런 선택을 무조건 금지하거나 허용하지 않는다.
> 어떤 지름길을 왜 선택했는지 의식적으로 판단하고,
> 나중에 구조를 되돌릴 수 있게 만드는 기준을 다룬다.

## 1. 지름길을 의식적으로 다루기

그간 지름길을 택하다 보면 기술 부채가 쌓인다는 것을 봤다.
지름길을 방지하려면 먼저 지름길 자체를 파악해야 한다.
그래야 지름길을 인식하고 수정하거나, 정당한 지름길이라면 그 효과를 의식적으로 선택할 수 있다.

소프트웨어는 건설공학이나 항공전자공학의 산출물보다 훨씬 변경하기 쉽다.
따라서 어떤 상황에서는 지름길을 먼저 선택하고 나중에 수정하는 편이 더 경제적일 수 있다.
때로는 아예 고치지 않는 선택도 합리적일 수 있다.

중요한 것은 지름길을 무의식적으로 쌓아두지 않는 것이다.

```text
나쁜 지름길:
  → 인식하지 못한 채 반복됨
  → 팀의 기본 작업 방식이 됨
  → 기술 부채로 굳어짐

의식적인 지름길:
  → 왜 선택했는지 기록됨
  → 비용과 효과가 공유됨
  → 나중에 되돌릴 수 있음
```

---

## 2. 왜 지름길은 깨진 창문 같을까

1969년 심리학자 Philip Zimbardo는 나중에 "깨진 창문 이론"으로 알려진 논의에 영향을 준 실험을 진행했다.
그는 번호판이 없고 보닛이 열린 자동차를 두 지역에 세워두었다.

| 지역 | 상태 |
|---|---|
| Bronx | 상대적으로 주거 환경이 나쁜 지역 |
| Palo Alto | 상대적으로 주거 환경이 좋은 지역 |

Bronx의 자동차는 빠르게 부품이 도난당하고 망가졌다.
Palo Alto의 자동차는 한동안 멀쩡했다.
하지만 연구자가 Palo Alto의 자동차 창문을 일부러 깨뜨리자, 이후에는 그 자동차도 훼손되기 시작했다.

이 행동에 가담한 사람은 특정 계층에만 속하지 않았다.
평소에는 준법적으로 행동할 법한 사람들도 포함되었다.
즉 "이미 망가져 보이는 것"은 사람들에게 더 망가뜨려도 된다는 신호처럼 작동할 수 있다.

저자는 이를 다음처럼 표현한다.

> 어떤 것이 멈춘 것처럼 보이고, 망가져 보이고, 박살나 보이면,
> 인간의 뇌는 그것을 더 멈추고, 망가뜨리고, 박살내도 된다고 생각하게 된다.

이를 코드에 적용하면 다음처럼 해석할 수 있다.

1. 품질이 떨어진 코드에서 작업할 때, 더 낮은 품질의 코드를 추가하기 쉽다.
2. 지름길을 많이 사용한 코드에서 작업할 때, 또 다른 지름길을 추가하기 쉽다.

그래서 많은 레거시 코드의 품질이 시간이 갈수록 낮아지는 것은 놀라운 일이 아니다.
깨진 창문이 방치되면 그것이 새로운 기준이 된다.

---

## 3. 깨끗한 상태로 시작할 책임

우리는 모두 깨진 창문 심리에 무의식적으로 영향을 받는다.
따라서 프로젝트를 가능한 한 지름길이 적고 기술 부채가 낮은 상태로 시작하는 것이 중요하다.

소프트웨어 프로젝트는 대부분 오래 지속되고 큰 비용이 든다.
초기에 생긴 깨진 창문은 이후 수많은 의사결정에 영향을 준다.
깨진 창문을 막는 것은 개발자의 중요한 책임이다.

특히 프로젝트를 인계받는 입장에서는 깨진 창문을 만들어내기 쉽다.
이미 충분히 이해하지 못한 코드 위에서 빠른 수정을 해야 하고,
기존 품질이 낮아 보이면 "여기서는 이 정도면 된다"는 생각이 들기 때문이다.

물론 항상 지름길을 피해야 하는 것은 아니다.

```text
지름길이 실용적일 수 있는 경우:
  → 프로젝트 전체에서 중요하지 않은 영역
  → 프로토타이핑 단계
  → 출시 일정이나 비용상 타협이 필요한 경우
  → 나중에 제거할 계획이 명확한 경우
```

이런 의도적인 지름길은 반드시 기록해야 한다.
기록하지 않은 지름길은 시간이 지나면 의도인지 실수인지 구분할 수 없다.
Michael Nygard가 제안한 Architecture Decision Records(ADRs)를 활용할 수 있다.

> **Note: Architecture Decision Records**
>
> ADR은 Architecture Decision Record의 약자다.
> 중요한 아키텍처 결정을 짧은 문서로 남기는 방식이다.
>
> 핵심은 "무엇을 결정했는가"뿐만 아니라,
> "왜 그렇게 결정했는가"와 "그 결과 어떤 trade-off를 감수하는가"를 함께 남기는 것이다.
>
> 일반적인 ADR 구성은 다음과 같다.
>
> ```text
> # 0001. 웹 어댑터에서 application service를 직접 호출한다
>
> ## Status
> Accepted
>
> ## Context
> 현재 애플리케이션은 유스케이스가 2개뿐이고,
> incoming port를 별도로 두면 코드 양이 더 많아진다.
>
> ## Decision
> 당분간 웹 어댑터가 application service를 직접 호출한다.
>
> ## Consequences
> 장점:
>   - 초기 구현 속도가 빠르다.
>   - 파일 수가 줄어든다.
>
> 단점:
>   - 유스케이스 계약이 interface로 드러나지 않는다.
>   - 유스케이스 수가 늘어나면 port를 도입해야 한다.
> ```
>
> ADR은 단순한 이론이 아니라 실무에서도 널리 쓰인다.
> 보통 markdown 파일로 repository 안에 함께 저장한다.
> 그래서 코드 변경과 아키텍처 결정 기록을 같은 version control 흐름에서 관리할 수 있다.
>
> ADR은 길 필요가 없다.
> 오히려 짧고 자주 쓰는 편이 좋다.
> 나중에 팀원이 "왜 이 구조를 선택했는가"를 추적할 수 있으면 충분하다.

이제 헥사고날 아키텍처에서 고려해볼 만한 지름길들을 살펴보자.

---

## 4. 유스케이스 간 모델 공유하기

[4. 유스케이스 구현하기](./4_implement-use-case/)에서는 유스케이스마다 별도의 입출력 모델을 두는 편이 좋다고 설명했다.
하지만 비슷한 유스케이스끼리 같은 모델을 공유하는 지름길을 선택할 수 있다.

```text
account.application.port.in                         account.application.service
───────────────────────────                         ───────────────────────────

<<Interface>>
SendMoneyUseCase ◀──────────────────────────────── SendMoneyService
        │                                               implements
        ▼
SendMoneyCommand
        ▲
        │
<<Interface>>
RevokeActivityUseCase ◀────────────────────────── RevokeActivityService
                                                        implements
```

`SendMoneyUseCase`와 `RevokeActivityUseCase`가 모두 `SendMoneyCommand`를 입력 모델로 사용한다.
이러면 두 유스케이스가 결합된다.

`SendMoneyCommand`가 변경되면 두 유스케이스가 모두 영향을 받는다.
즉 두 유스케이스가 변경할 이유를 공유하게 된다.
출력 모델을 공유할 때도 같은 문제가 생긴다.

```text
SendMoneyCommand 변경
  ├─ SendMoneyUseCase 영향
  └─ RevokeActivityUseCase 영향
```

그렇다고 모델 공유가 항상 잘못된 것은 아니다.
유스케이스들이 기능적으로 묶여 있고 특정 요구사항을 함께 공유한다면 같은 모델을 사용하는 것이 자연스러울 수 있다.

판단 기준은 모델의 세부사항이 바뀔 때 실제로 두 유스케이스가 함께 영향을 받아야 하는지다.
함께 바뀌는 것이 의도라면 공유해도 된다.

비슷한 개념의 유스케이스가 여러 개 있다면 다음 질문을 주기적으로 해야 한다.

```text
이 유스케이스들은 앞으로 서로 독립적으로 진화해야 하는가?
```

대답이 `예`라면 입출력 모델을 분리해야 한다.

---

## 5. 도메인 엔티티를 입출력 모델로 사용하기

도메인 엔티티를 incoming port의 입력이나 출력 모델로 사용하는 지름길도 있다.

```text
account.application.port.in          account.application.service          account.domain
───────────────────────────          ───────────────────────────          ──────────────

<<Interface>>
SendMoneyUseCase ◀────────────────── SendMoneyService ─────────────────▶ Account
        │                              implements
        └──────────────── uses / returns Account ────────────────────────┘
```

이 구조에서 incoming port는 `Account` 도메인 엔티티에 의존한다.
그 결과 `Account`에는 유스케이스의 입출력 요구 때문에 변경될 가능성이 생긴다.

### 5.1. Account가 SendMoneyUseCase를 모르는데 왜 변경 이유가 생기나

의존성 화살표는 `SendMoneyUseCase → Account` 방향이다.
`Account`가 incoming port를 직접 의존하는 것은 아니다.

하지만 incoming port의 method signature가 `Account`를 입출력 모델로 사용하면,
유스케이스의 계약을 만족시키기 위해 `Account`의 형태를 바꾸고 싶은 압력이 생긴다.

ex) 송금 유스케이스가 도메인 엔티티에 없는 요청 정보까지 필요하다고 가정한다.

```java
public interface SendMoneyUseCase {
    Account sendMoney(Account account);
}
```

```text
송금 유스케이스에 새로 필요한 정보:
  → 일회용 인증 번호
  → 요청 채널
  → 요청자 IP
```

이 정보는 `Account`의 본질적인 상태가 아닐 수 있다.
다른 도메인이나 bounded context에 속하거나, 유스케이스 전용 command에 있어야 할 가능성이 높다.

그러나 이미 `Account`를 입력 모델로 쓰고 있으면 다음처럼 엔티티에 필드를 추가하고 싶어진다.

```java
class Account {
    private String oneTimePassword; // Account의 도메인 상태가 아님
    private String requestChannel;  // 송금 요청에서만 필요
}
```

즉 `Account`가 incoming port를 의존해서 변경되는 것이 아니다.
incoming port가 `Account`를 통신 모델로 선택했기 때문에, 바깥 요구사항이 엔티티로 새어 들어오는 것이다.

간단한 create/update CRUD 유스케이스라면 port에서 도메인 엔티티를 사용하는 것이 실용적일 수 있다.
모든 계층이 같은 데이터를 요구하고 비즈니스 규칙도 단순하다면 별도 모델은 과할 수 있다.

하지만 단순 필드 갱신을 넘어 복잡한 도메인 로직을 구현한다면 유스케이스 전용 입출력 모델을 만드는 편이 낫다.

```java
public interface SendMoneyUseCase {
    SendMoneyResult sendMoney(SendMoneyCommand command);
}
```

많은 기능이 간단한 CRUD로 시작해 복잡한 도메인 로직을 가진 기능으로 성장한다.
그래서 도메인 엔티티를 입출력 모델로 사용하는 지름길은 장기적으로 위험할 수 있다.

---

## 6. 인커밍 포트 건너뛰기

outgoing port는 application core에서 바깥 adapter로 향하는 의존성을 역전하기 위해 필요하다.

```text
application.service ─────▶ application.port.out ◀──── adapter.out.persistence
```

반면 incoming adapter에서 application service로 향하는 의존성은 이미 안쪽을 향한다.
따라서 의존성 역전만 놓고 보면 incoming port는 필수 요소가 아니다.

```text
account.adapter.in.web          account.application.service
──────────────────────          ───────────────────────────

SendMoneyController ──────────▶ SendMoneyService
        │                              ▲
        └──── SendMoneyCommand ────────┘
```

incoming port 없이 controller가 application service를 직접 호출해도 의존성 방향은 어긋나지 않는다.
그럼에도 incoming port에는 두 가지 역할이 있다.

### 6.1. 유스케이스 진입점을 명시한다

controller가 호출하는 service method도 물리적인 진입점은 맞다.
문제는 그것이 **외부에 공개할 의도로 설계된 애플리케이션 계약인지** 코드만 보고 바로 구분하기 어렵다는 점이다.

ex) 하나의 service에 public method가 여러 개 있다고 가정한다.

```java
public class AccountService {

    public boolean sendMoney(SendMoneyCommand command) {
        // 외부에 공개할 유스케이스
    }

    public Account loadAccount(AccountId accountId) {
        // sendMoney() 내부 지원용
    }

    public void recalculateBalance(Account account) {
        // application 내부 처리용
    }
}
```

incoming port가 없으면 controller 개발자는 `AccountService` 내부를 읽고 어떤 method가 공식 진입점인지 판단해야 한다.
실수로 내부 지원용 method를 직접 호출할 수도 있다.

```java
@RestController
class AccountController {

    private final AccountService accountService;

    Account account(AccountId id) {
        return accountService.loadAccount(id); // 의도하지 않은 진입점 노출
    }
}
```

전용 incoming port를 두면 외부에 공개한 유스케이스가 interface로 명시된다.

```java
public interface SendMoneyUseCase {
    boolean sendMoney(SendMoneyCommand command);
}
```

controller는 이 interface만 보므로 진입점을 찾기 위해 service 내부를 알 필요가 없다.

### 6.2. 진입점 규칙을 강제한다

incoming adapter가 application service가 아니라 incoming port만 호출하도록 아키텍처 규칙을 만들 수 있다.

```text
허용:
adapter.in ─────▶ application.port.in

금지:
adapter.in ──X──▶ application.service
```

이 규칙을 적용하면 application 계층에 새로운 진입점을 추가하는 일이 의식적인 설계 작업이 된다.
incoming adapter가 외부 호출용이 아닌 service method를 실수로 호출하는 것도 막을 수 있다.

application 규모가 작거나 incoming adapter가 하나뿐이라 모든 흐름을 쉽게 파악할 수 있다면 incoming port는 불필요할 수 있다.
이 경우 service 직접 호출은 합리적인 지름길이다.

---

## 7. 애플리케이션 서비스 건너뛰기

간단한 유스케이스에서는 application service를 생략하고 persistence adapter가 incoming port를 직접 구현할 수도 있다.

```text
account.application.port.in          account.domain          account.adapter.out.persistence
───────────────────────────          ──────────────          ───────────────────────────────

<<Interface>>
RegisterAccountUseCase ◀──────────────────────────────────── AccountPersistenceAdapter
        │                                                       implements
        └────────────────────────────┐                           │
                                     ▼                           │
                                  Account ◀──────────────────────┘
```

`AccountPersistenceAdapter`가 `RegisterAccountUseCase`를 직접 구현해 application service를 대체한다.

간단한 CRUD 유스케이스에서는 service가 도메인 로직 없이 요청을 persistence adapter로 전달하기만 하는 경우가 많다.

```java
class RegisterAccountService implements RegisterAccountUseCase {

    private final CreateAccountPort createAccountPort;

    @Override
    public Account register(Account account) {
        return createAccountPort.create(account);
    }
}
```

이 정도라면 중간 service를 제거하고 adapter가 incoming port를 구현하고 싶어질 수 있다.
하지만 두 가지 문제가 생긴다.

### 7.1. 인커밍 어댑터와 아웃고잉 어댑터가 모델을 공유한다

위 구조에서는 incoming port와 persistence adapter가 `Account`를 공유한다.
따라서 [5. 도메인 엔티티를 입출력 모델로 사용하기](#5-도메인-엔티티를-입출력-모델로-사용하기)에서 설명한 문제가 그대로 발생한다.

web 요구나 persistence 요구가 도메인 엔티티로 새어 들어갈 수 있다.

### 7.2. Application core가 사라진다

application service를 제거하면 application core에 유스케이스 구현이라고 부를 만한 코드가 없어진다.

처음에는 단순 CRUD였더라도 기능이 복잡해지면 도메인 로직을 persistence adapter에 추가하기 쉽다.

```java
class AccountPersistenceAdapter implements RegisterAccountUseCase {

    @Override
    public Account register(Account account) {
        validateRegistrationPolicy(account); // 도메인 로직이 adapter로 이동
        calculateInitialLimit(account);
        return repository.save(mapToJpaEntity(account));
    }
}
```

이렇게 되면 도메인 로직이 adapter 여러 곳에 흩어져 유지보수가 어려워진다.
단순 전달만 하던 유스케이스가 복잡해지는 시점을 놓치지 않아야 한다.

---

## 8. 유지보수 가능한 소프트웨어를 만드는 데 어떻게 도움이 될까

경제적인 이유로 지름길이 합리적일 수 있다.
간단한 CRUD 유스케이스에서는 port, service, 전용 입출력 모델을 모두 만드는 것이 지나치게 느껴질 수 있다.

모든 application은 작게 시작한다.
중요한 것은 CRUD를 벗어나는 시점이 언제인지 팀이 합의하는 것이다.

```text
지름길 유지 가능:
  → 단순 CRUD가 계속 유지됨
  → 도메인 규칙이 거의 없음
  → 유스케이스들이 함께 변경됨

구조 분리 필요:
  → 유스케이스별 검증 규칙이 달라짐
  → 도메인 로직이 복잡해짐
  → 모델에 유스케이스 전용 필드가 추가됨
  → 어댑터에 비즈니스 로직이 들어가기 시작함
```

CRUD에서 벗어나지 않는 유스케이스라면 지름길을 그대로 유지하는 편이 더 경제적일 수 있다.
불필요한 추상화도 유지보수 비용이기 때문이다.

어떤 선택을 하든 아키텍처와 지름길을 왜 선택했는지 기록해야 한다.
그래야 다음 개발자가 이를 실수가 아니라 의식적인 결정으로 이해하고, 상황이 바뀌었을 때 재검토할 수 있다.

---

## 9. 참고

- [도서] 만들면서 배우는 클린 아키텍처 - 톰 홈버그(Tom Hombergs)
- [인물] Philip Zimbardo
- [인물] Michael Nygard
- [개념] Architecture Decision Records
