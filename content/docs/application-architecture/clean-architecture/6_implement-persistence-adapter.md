---
title: "6. 영속성 어댑터 구현하기"
weight: 6
date: 2026-05-30
---

## 1. 의존성 역전

[1. 계층형 아키텍처의 문제점](./1_layered-architecture-problems/)에서는 전통적인 계층형 아키텍처가 DB 주도 설계로 흐르기 쉽다고 정리했다.

```text
web
  → domain
    → persistence
      → database
```

이 구조에서는 중요한 도메인 로직이 영속성 계층에 의존하기 쉽다.
ORM entity, repository 구현, transaction 같은 영속성 관심사가 도메인 코드로 스며든다.

의존성 역전을 적용하면 영속성 계층은 application 계층의 플러그인이 된다.
application service는 영속성 구현체를 직접 알지 않고, outgoing port interface만 의존한다.
영속성 어댑터는 그 port를 구현해서 application service에 영속성 기능을 제공한다.

```text
account.application.service          account.application.port.out          account.adapter.out.persistence
───────────────────────────          ───────────────────────────          ───────────────────────────────

SendMoneyService ───────────────────▶ <<Interface>>
                                      UpdateAccountStatePort ◀──────────── AccountPersistenceAdapter
                                                                            implements
```

의존성 방향은 다음처럼 읽는다.

```text
application.service
  → application.port.out
    ← adapter.out.persistence
```

즉 application 계층은 "계좌 상태를 저장한다"는 port만 알고,
JPA, JDBC, Redis 같은 구체 기술은 persistence adapter 안에 갇힌다.

이 구조에서는 DB가 바뀌어도 application service는 바뀌지 않는다.
새로운 persistence adapter가 같은 outgoing port를 구현하면 된다.

> **Note: port interface에 의존하면 충분한가?**
>
> 충분하지 않다.
> 의존성 역전은 구현체 의존을 끊어주지만, port의 입출력 모델이 persistence 모델이면 변경 영향은 계속 application service로 전파된다.
>
> 나쁜 예시는 다음과 같다.
>
> ```java
> interface LoadAccountPort {
>     AccountJpaEntity loadAccount(Long accountId);
> }
> ```
>
> 이 경우 service는 JPA repository 구현체를 직접 모를 뿐,
> 여전히 JPA entity를 알고 있다.
> `AccountJpaEntity` 필드가 바뀌면 service도 바뀔 수 있다.
> 이는 persistence 세부사항이 port를 통해 새어 들어온 구조다.
>
> port는 adapter가 제공하고 싶은 모델이 아니라 application이 필요로 하는 계약이어야 한다.
>
> ```java
> interface LoadAccountPort {
>     Account loadAccount(AccountId accountId);
> }
> ```
>
> ```text
> application.service
>   → LoadAccountPort
>   → Account        // domain/application 모델
>
> adapter.out.persistence
>   → AccountJpaEntity
>   → Account로 mapping해서 반환
> ```
>
> 변경 사유는 이렇게 나뉜다.
>
> | 변경 | 수정 위치 |
> |---|---|
> | DB column 변경 | persistence adapter / mapper |
> | JPA entity 변경 | persistence adapter / mapper |
> | 도메인 규칙에 필요한 값 변경 | domain model / port / service |
> | 유스케이스가 요구하는 데이터 변경 | application port 계약 / service |
>
> 즉 DB schema나 ORM 모델 변경 때문에 service가 바뀐다면 port가 persistence 세부사항을 노출하고 있는 것이다.
> 반대로 새 비즈니스 규칙 때문에 `Account.status`가 필요해져 service가 바뀐다면, 이는 비즈니스 요구 변경이므로 service가 바뀌는 것이 맞다.
>
> 대처 방법은 네 가지다.
>
> 1. port 입출력 모델을 application/domain 소유로 둔다.
> 2. port를 유스케이스에 맞게 좁게 만든다.
> 3. 반환 모델은 필요한 만큼만 둔다.
> 4. persistence model과 domain model 사이 mapping은 adapter 안으로 밀어 넣는다.

---

## 2. 영속성 어댑터의 책임

영속성 어댑터는 application 계층과 DB 사이를 변환한다.
일반적으로 다음 일을 한다.

1. 입력 받기
2. 입력을 DB 포맷으로 매핑
3. 입력을 DB로 보내기
4. DB 출력을 application 포맷으로 매핑
5. 출력 반환

```text
application model
  → persistence adapter
  → persistence model
  → database
  → persistence model
  → persistence adapter
  → application model
```

영속성 어댑터의 입출력 모델은 application core에 속한다.
따라서 영속성 어댑터 내부의 JPA entity, repository, query 방식이 바뀌어도 application core에 직접 영향이 가지 않는다.

---

## 3. 포트 인터페이스 나누기

서비스를 구현하다 보면 DB 연산을 정의하는 outgoing port interface를 어떻게 나눌지 고민하게 된다.
전통적인 방식은 특정 entity에 필요한 모든 DB 연산을 하나의 repository interface에 모으는 것이다.

```text
account.application.service          account.application.port.out          account.adapter.out.persistence
───────────────────────────          ───────────────────────────          ───────────────────────────────

SendMoneyService ────────────────────┐
                                     │
                                     ▼
                                      <<Interface>>
                                      AccountRepository ◀──────────────── AccountPersistenceAdapter
                                     ▲                                      implements
                                     │
RegisterAccountService ──────────────┘
```

이 방식은 익숙하지만 port가 넓어진다.
서비스가 repository 메서드 하나만 쓰더라도 전체 interface에 의존하게 된다.

```java
interface AccountRepository {
    Account loadAccount(AccountId accountId);
    void updateActivities(Account account);
    void createAccount(Account account);
    void deleteAccount(AccountId accountId);
    List<Account> findDormantAccounts();
}
```

예를 들어 `RegisterAccountService`는 `createAccount()`만 필요할 수 있다.
하지만 테스트에서는 넓은 `AccountRepository` 전체를 mock으로 주입한다.

```java
class RegisterAccountServiceTest {

    @Test
    void registerAccount() {
        AccountRepository repository = mock(AccountRepository.class);
        RegisterAccountService service = new RegisterAccountService(repository);

        service.registerAccount(command);

        verify(repository).createAccount(any());
    }
}
```

당장은 괜찮아 보인다.
문제는 다음 사람이 테스트를 읽을 때 `AccountRepository` 전체가 준비되어 있다고 기대할 수 있다는 점이다.

```java
// 나중에 RegisterAccountService 내부에 중복 계좌 확인이 추가됨
if (accountRepository.loadAccount(command.accountId()).isPresent()) {
    throw new DuplicateAccountException();
}
```

이제 테스트는 실패한다.
기존 테스트는 `createAccount()`만 신경 썼고, `loadAccount()`는 stub하지 않았기 때문이다.
넓은 interface를 mock하면 "이 서비스가 정확히 어떤 기능에 의존하는지"가 테스트에서 흐려진다.

로버트 C. 마틴의 표현을 빌리면 다음과 같은 취지다.

> 필요 없는 화물을 운반하는 무언가에 의존하면 예상하지 못했던 문제가 생길 수 있다.

인터페이스 분리 원칙(ISP, Interface Segregation Principle)은 이 문제에 대한 답이다.
client는 자신이 필요로 하는 메서드만 알아야 한다.

outgoing port에 적용하면 다음처럼 나눌 수 있다.

```text
account.application.service          account.application.port.out          account.adapter.out.persistence
───────────────────────────          ───────────────────────────          ───────────────────────────────

SendMoneyService ────────────────────┬──▶ <<Interface>>
                                     │    LoadAccountPort          ◀──────┐
                                     │                                    │
                                     └──▶ <<Interface>>                   │
                                          UpdateAccountStatePort  ◀──────┼── AccountPersistenceAdapter
                                                                          │   implements
RegisterAccountService ─────────────▶ <<Interface>>                       │
                                      CreateAccountPort           ◀───────┘
```

서비스는 필요한 port에만 의존한다.
테스트에서도 어떤 메서드를 mock해야 하는지 고민할 필요가 줄어든다.
대부분 port 하나에 메서드 하나만 있기 때문이다.

이런 좁은 port는 코딩을 plug-and-play 경험에 가깝게 만든다.
서비스마다 필요한 port를 꽂기만 하면 된다.
운반할 다른 화물이 없다.

물론 모든 상황에서 port 하나당 메서드 하나를 강제할 필요는 없다.
응집도가 높고 항상 함께 쓰이는 DB 연산은 하나의 interface에 묶을 수 있다.

---

## 4. 영속성 어댑터 나누기

앞의 다이어그램은 하나의 `AccountPersistenceAdapter`가 모든 account 관련 port를 구현했다.
하지만 모든 port를 하나의 adapter class가 구현해야 하는 것은 아니다.

DDD의 aggregate 단위로 영속성 어댑터를 나눌 수 있다.

> **Note: Aggregate**
>
> Aggregate는 함께 일관성을 지켜야 하는 도메인 객체 묶음이다.
> 외부에서는 aggregate root를 통해서만 내부 객체를 변경한다.
>
> 예를 들어 `Account`가 aggregate root라면,
> 계좌의 활동(`Activity`)은 `Account`를 통해 추가되거나 검증된다.
> 이렇게 하면 계좌 잔고, 출금 가능 여부 같은 규칙을 한 경계 안에서 지킬 수 있다.

```text
account.application.service          account.application.port.out          account.adapter.out.persistence
───────────────────────────          ───────────────────────────          ───────────────────────────────

SendMoneyService ───────────────────┬──▶ LoadAccountPort ◀────────────────┐
                                    │                                      ├── AccountPersistenceAdapter
                                    └──▶ UpdateAccountStatePort ◀──────────┘   implements


user.application.service             user.application.port.out             user.adapter.out.persistence
────────────────────────             ─────────────────────────             ────────────────────────────

RegisterUserService ────────────────▶ CreateUserPort ◀───────────────────── UserPersistenceAdapter
                                                                            implements
```

이 구조에서는 영속성 어댑터가 도메인 경계를 따라 자연스럽게 나뉜다.
`Account` aggregate의 영속성 요구는 `AccountPersistenceAdapter`가 담당하고,
`User` aggregate의 영속성 요구는 `UserPersistenceAdapter`가 담당한다.

영속성 어댑터를 더 세분화할 수도 있다.
예를 들어 일부 port는 JPA로 구현하고, 성능이 중요한 조회 port는 SQL 기반 adapter로 구현할 수 있다.

```text
AccountPersistenceAdapter      // JPA 기반 command/update
AccountQueryPersistenceAdapter // SQL 기반 query/read
```

`애그리거트당 하나의 영속성 어댑터` 접근은 나중에 bounded context를 분리하기 위한 토대가 된다.
bounded context는 특정 도메인 모델과 언어가 유효한 경계다.

```text
account bounded context
billing bounded context
```

`account` 맥락의 service가 `billing` 맥락의 persistence adapter를 직접 호출하면 경계가 깨진다.
반대로 `billing` service가 `account` persistence adapter를 직접 호출해도 마찬가지다.

다른 맥락의 기능이 필요하면 그 맥락이 외부에 공개한 incoming port를 통해 접근한다.

```text
account.application.service          billing.application.port.in           billing.application.service          billing.adapter.out.persistence
───────────────────────────          ───────────────────────────           ───────────────────────────          ───────────────────────────────

CloseAccountService ────────────────▶ <<Interface>>
                                      CreateFinalBillUseCase ◀───────────── CreateFinalBillService ────────────▶ BillingPersistenceAdapter
                                                                            implements
```

이 말은 account가 billing DB adapter를 직접 호출하지 않는다는 뜻이다.
billing 쪽에 `CreateFinalBillUseCase` 같은 전용 incoming port를 만들고,
account는 그 port를 호출한다.
그래야 billing의 영속성 구조가 바뀌어도 account가 영향을 덜 받는다.

---

## 5. Spring Data JPA 예제

도메인 모델은 영속성 기술을 몰라야 한다.
`Account`는 유효한 상태의 계좌만 만들 수 있도록 factory method와 도메인 행위를 제공한다.

```java
public class Account {

    private AccountId id;
    private Money baselineBalance;
    private ActivityWindow activityWindow;

    public static Account withoutId(Money baselineBalance, ActivityWindow activityWindow) {
        // ...
    }

    public static Account withId(AccountId id, Money baselineBalance, ActivityWindow activityWindow) {
        // ...
    }

    public Money calculateBalance() {
        // ...
    }

    public boolean withdraw(Money money, AccountId targetAccountId) {
        // ...
    }

    public boolean deposit(Money money, AccountId sourceAccountId) {
        // ...
    }
}
```

JPA를 사용하려면 DB 상태를 표현하는 entity가 필요하다.

```java
@Entity
@Table(name = "account")
class AccountJpaEntity {

    @Id
    @GeneratedValue
    private Long id;
}
```

지금은 `id`만 있지만, 나중에 사용자 id 같은 필드가 추가될 수 있다.
활동 테이블도 별도 JPA entity로 표현한다.

```java
@Entity
@Table(name = "activity")
class ActivityJpaEntity {

    @Id
    @GeneratedValue
    private Long id;

    private Long ownerAccountId;
    private Long sourceAccountId;
    private Long targetAccountId;
    private LocalDateTime timestamp;
    private BigDecimal amount;
}
```

`ActivityJpaEntity`와 `AccountJpaEntity`는 `@ManyToOne`, `@OneToMany`로 연결할 수도 있다.
하지만 관계 mapping은 쿼리 시점과 로딩 방식에 부수효과를 만들 수 있다.
예제에서는 항상 데이터 일부만 가져오고 싶으므로 일단 관계 mapping을 제외했다.

JPA는 강력하지만, 즉시/지연 로딩, 영속성 컨텍스트, 캐시 같은 기능 때문에 복잡도가 커질 수 있다.
많은 문제에는 더 단순한 ORM이나 SQL mapper가 더 적합할 수도 있다.
다만 앞으로 JPA가 제공하는 기능이 필요할 수 있으므로 여기서는 JPA를 사용한다.

Spring Data repository는 다음처럼 만들 수 있다.

```java
interface AccountRepository extends JpaRepository<AccountJpaEntity, Long> {
}
```

```java
interface ActivityRepository extends JpaRepository<ActivityJpaEntity, Long> {

    @Query("select a from ActivityJpaEntity a where a.ownerAccountId = :ownerAccountId and a.timestamp >= :since")
    List<ActivityJpaEntity> findByOwnerSince(Long ownerAccountId, LocalDateTime since);

    @Query("select sum(a.amount) from ActivityJpaEntity a where a.targetAccountId = :accountId and a.ownerAccountId = :accountId and a.timestamp < :until")
    BigDecimal getDepositBalanceUntil(Long accountId, LocalDateTime until);

    @Query("select sum(a.amount) from ActivityJpaEntity a where a.sourceAccountId = :accountId and a.ownerAccountId = :accountId and a.timestamp < :until")
    BigDecimal getWithdrawalBalanceUntil(Long accountId, LocalDateTime until);
}
```

Spring Boot는 repository interface를 자동으로 찾는다.
Spring Data는 실제 DB와 통신하는 repository 구현체를 런타임에 제공한다.

이제 영속성 어댑터를 구현한다.

```java
@Component
class AccountPersistenceAdapter implements LoadAccountPort, UpdateAccountStatePort {

    private final AccountRepository accountRepository;
    private final ActivityRepository activityRepository;
    private final AccountMapper accountMapper;

    @Override
    public Account loadAccount(AccountId accountId) {
        AccountJpaEntity account = accountRepository.findById(accountId.value())
                .orElseThrow(EntityNotFoundException::new);

        List<ActivityJpaEntity> activities =
                activityRepository.findByOwnerSince(accountId.value(), LocalDateTime.now().minusDays(10));

        return accountMapper.mapToDomainEntity(account, activities);
    }

    @Override
    public void updateActivities(Account account) {
        for (Activity activity : account.getActivityWindow().getActivities()) {
            activityRepository.save(accountMapper.mapToJpaEntity(activity));
        }
    }
}
```

이 어댑터는 application이 필요로 하는 두 port를 구현한다.

| port | 역할 |
|---|---|
| `LoadAccountPort` | 계좌 aggregate를 로드 |
| `UpdateAccountStatePort` | 계좌 활동 변경분을 저장 |

여기에는 `Account`, `Activity` 도메인 모델과 `AccountJpaEntity`, `ActivityJpaEntity` 영속성 모델 간 양방향 매핑이 존재한다.

그냥 `Account`와 `Activity`에 JPA annotation을 붙이면 매핑 코드를 줄일 수 있다.
[8. 경계 간 매핑하기](./8_mapping-between-boundaries/)에서 말한 `매핑하지 않기` 전략도 유효한 선택일 수 있다.

하지만 그렇게 하면 JPA 요구사항 때문에 도메인 모델이 수정될 수 있다.
예를 들어 JPA entity에는 기본 생성자가 필요하다.
또 영속성 성능을 위해 `@ManyToOne` 관계가 적절할 수 있지만,
도메인 모델에서는 그 관계 방향이 반대이거나 아예 필요 없을 수 있다.

풍부한 도메인 모델을 영속성 기술과 타협 없이 만들고 싶다면,
도메인 모델과 영속성 모델을 분리하고 adapter 안에서 매핑하는 편이 낫다.

---

## 6. DB transaction은 어떻게 할까

트랜잭션은 하나의 유스케이스에서 일어나는 모든 쓰기 작업을 감싸야 한다.
하나라도 실패하면 모두 롤백되어야 하기 때문이다.

영속성 어댑터는 어떤 DB 연산들이 같은 유스케이스에 포함되는지 모른다.
따라서 언제 transaction을 열고 닫아야 하는지도 모른다.

트랜잭션 경계는 영속성 어댑터 호출을 관장하는 application service에 두는 편이 자연스럽다.

```java
@Transactional
class SendMoneyService implements SendMoneyUseCase {

    @Override
    public boolean sendMoney(SendMoneyCommand command) {
        // ...
    }
}
```

Spring에서는 `@Transactional`로 public method를 트랜잭션으로 감쌀 수 있다.

서비스 코드가 `@Transactional`로 오염되는 것이 싫다면 AspectJ 같은 도구로 AOP 기반 transaction boundary를 적용할 수 있다.

> **Note: Weaving**
>
> Weaving은 AOP에서 사용하는 용어다.
> aspect를 실제 코드 실행 흐름에 연결하는 작업을 말한다.
>
> 예를 들어 `@Transactional`은 메서드 호출 전 transaction을 열고,
> 정상 종료 시 commit, 예외 발생 시 rollback하는 관심사를 business method 주변에 붙인다.
>
> weaving은 컴파일 타임, 클래스 로딩 타임, 런타임에 일어날 수 있다.
> 핵심은 비즈니스 코드에 직접 transaction 시작/종료 코드를 쓰지 않고,
> 별도 관심사를 코드 실행 지점에 엮는다는 점이다.

---

## 7. 유지보수 가능한 소프트웨어를 만드는 데 어떻게 도움이 될까

도메인 코드에 플러그인처럼 동작하는 영속성 어댑터는 도메인 코드를 영속성 로직과 분리한다.
덕분에 JPA, SQL, Redis 같은 기술 제약에 끌려가지 않는 풍부한 도메인 모델을 만들 수 있다.

1. 좁은 port interface를 사용하면 port마다 다른 방식으로 구현할 수 있다.

   예를 들어 `LoadAccountPort`는 성능 때문에 SQL query adapter로 구현하고,
   `UpdateAccountStatePort`는 JPA adapter로 구현할 수 있다.

2. port 뒤에서 application이 모르게 다른 영속성 기술을 사용할 수 있다.

   예를 들어 `LoadAccountPort` 구현체가 처음에는 PostgreSQL을 사용하다가,
   조회 성능 때문에 Redis cache를 먼저 확인한 뒤 DB를 조회하도록 바뀔 수 있다.
   application service는 여전히 `LoadAccountPort`만 호출한다.

3. port 명세만 지켜지면 영속성 계층 전체를 교체할 수 있다.

   예를 들어 `AccountPersistenceAdapter`를 JPA 기반 구현에서 MyBatis나 JDBC 기반 구현으로 바꿔도,
   `LoadAccountPort`, `UpdateAccountStatePort` 계약이 유지되면 application service는 바뀌지 않는다.

---

## 8. 참고

- [도서] 만들면서 배우는 클린 아키텍처 - 톰 홈버그(Tom Hombergs)
