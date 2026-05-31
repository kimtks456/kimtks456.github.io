---
title: "7. 아키텍처 요소 테스트하기"
weight: 7
date: 2026-06-01
description: "헥사고날 아키텍처에서 도메인, 유스케이스, 어댑터, 시스템 테스트 전략을 정리한다."
---

## 1. 테스트 피라미드

헥사고날 아키텍처에서는 아키텍처 요소별로 테스트 전략을 나누기 좋다.
도메인 로직은 단위 테스트로 빠르게 검증하고, 어댑터는 framework나 DB와 함께 통합 테스트로 검증한다.
주요 사용자 경로는 시스템 테스트로 전체 흐름을 확인한다.

테스트 피라미드는 Mike Cohn의 **Succeeding with Agile: Software Development Using Scrum**에서 널리 알려진 개념이다.
피라미드는 아래로 갈수록 테스트 수가 많고, 위로 갈수록 테스트 수가 적어야 한다는 뜻이다.

```text
                         ┌─────────────────────┐
                         │    System Tests     │
                         │   시스템 테스트     │
                         └─────────────────────┘
                    ┌───────────────────────────────┐
                    │       Integration Tests       │
                    │          통합 테스트          │
                    └───────────────────────────────┘
             ┌────────────────────────────────────────────┐
             │                 Unit Tests                 │
             │                단위 테스트                 │
             └────────────────────────────────────────────┘
```

작고 빠른 테스트는 비용이 낮고 안정적이다.
따라서 단위 테스트는 높은 커버리지를 유지하는 편이 좋다.

반대로 여러 단위, 아키텍처 경계, 시스템 경계를 묶는 테스트는 비용이 크다.
느리고, 유지보수가 어렵고, 기능 문제가 아니라 설정 문제로 깨질 가능성도 높다.
따라서 비싼 테스트는 꼭 필요한 경로에만 배치한다.
그렇지 않으면 기능 개발보다 테스트 수정에 더 많은 시간을 쓰게 된다.

이 장에서는 UI까지 포함하는 end-to-end 테스트는 다루지 않는다.
백엔드 애플리케이션의 아키텍처 요소 테스트에 집중한다.

---

## 2. 단위 테스트로 도메인 엔티티 테스트하기

도메인 엔티티는 다른 클래스에 거의 의존하지 않는다.
그래서 단위 테스트만으로도 비즈니스 규칙을 검증하기 좋다.

ex) `Account.withdraw()`가 출금 가능 금액을 올바르게 판단하는지 검증한다.

```java
class AccountTest {

    @Test
    void withdrawalSucceeds() {
        AccountId accountId = new AccountId(1L);
        Account account = defaultAccount()
                .withAccountId(accountId)
                .withBaselineBalance(Money.of(555L))
                .withActivityWindow(new ActivityWindow(
                        defaultActivity()
                                .withTargetAccount(accountId)
                                .withMoney(Money.of(999L))
                                .build(),
                        defaultActivity()
                                .withTargetAccount(accountId)
                                .withMoney(Money.of(1L))
                                .build()))
                .build();

        boolean success = account.withdraw(Money.of(555L), new AccountId(99L));

        assertThat(success).isTrue();
        assertThat(account.getActivityWindow().getActivities()).hasSize(3);
        assertThat(account.calculateBalance()).isEqualTo(Money.of(1000L));
    }
}
```

이 테스트는 이해하기 쉽고 빠르다.
도메인 엔티티의 핵심 규칙만 검증하므로 테스트도 단순하다.
도메인 엔티티가 framework나 DB에 의존하지 않는다면 다른 종류의 테스트까지 필요하지 않다.

---

## 3. 단위 테스트로 유스케이스 테스트하기

유스케이스 서비스는 도메인 엔티티와 outgoing port를 조합한다.
`SendMoneyService` 테스트에서는 다음 흐름을 검증할 수 있다.

1. 출금 계좌를 잠근다.
2. 출금 계좌와 입금 계좌를 로드한다.
3. 출금과 입금을 수행한다.
4. 변경된 상태를 저장한다.
5. 계좌 잠금을 해제한다.

```java
class SendMoneyServiceTest {

    private final LoadAccountPort loadAccountPort = mock(LoadAccountPort.class);
    private final AccountLock accountLock = mock(AccountLock.class);
    private final UpdateAccountStatePort updateAccountStatePort = mock(UpdateAccountStatePort.class);

    private final SendMoneyService sendMoneyService =
            new SendMoneyService(loadAccountPort, accountLock, updateAccountStatePort);

    @Test
    void transactionSucceeds() {
        Account sourceAccount = givenSourceAccount();
        Account targetAccount = givenTargetAccount();

        given(loadAccountPort.loadAccount(sourceAccount.getId()))
                .willReturn(sourceAccount);
        given(loadAccountPort.loadAccount(targetAccount.getId()))
                .willReturn(targetAccount);

        SendMoneyCommand command = new SendMoneyCommand(
                sourceAccount.getId(),
                targetAccount.getId(),
                Money.of(500L));

        boolean success = sendMoneyService.sendMoney(command);

        assertThat(success).isTrue();

        then(accountLock).should().lockAccount(sourceAccount.getId());
        then(sourceAccount).should().withdraw(Money.of(500L), targetAccount.getId());
        then(targetAccount).should().deposit(Money.of(500L), sourceAccount.getId());
        then(updateAccountStatePort).should().updateActivities(sourceAccount);
        then(updateAccountStatePort).should().updateActivities(targetAccount);
        then(accountLock).should().releaseAccount(sourceAccount.getId());
    }
}
```

테스트는 BDD(Behavior-Driven Development)에서 자주 쓰는 `given / when / then` 구조로 읽으면 된다.

| 구간 | 역할 |
|---|---|
| given | 테스트에 필요한 계좌와 port 응답 준비 |
| when | `sendMoney()` 유스케이스 실행 |
| then | 계좌 lock, 출금, 입금, 상태 저장, lock 해제 호출 검증 |

코드에는 자세히 드러나지 않지만, Mockito는 mock 객체를 만들고 특정 메서드 호출 여부를 검증하는 도구다.
`given(...).willReturn(...)`으로 mock 응답을 준비하고,
`then(...).should()`로 호출 여부를 확인한다.

유스케이스 서비스는 보통 stateless다.
따라서 `then` 단계에서 서비스 자신의 상태를 검증하기 어렵다.
대신 의존 대상과의 상호작용을 검증한다.

이 방식은 테스트가 코드 구조에 민감해진다는 단점이 있다.
리팩터링으로 내부 호출 순서나 협력 객체가 바뀌면, 동작은 같아도 테스트가 깨질 수 있다.
따라서 모든 상호작용을 검증하기보다 핵심 계약만 골라야 한다.

이 테스트는 단위 테스트로 분류한다.
mock을 사용하므로 실제 DB나 framework를 띄우지 않기 때문이다.
다만 의존 객체와의 상호작용을 검증하므로 순수 계산 함수 테스트보다는 통합 테스트에 가깝다.

---

## 4. 통합 테스트로 웹 어댑터 테스트하기

웹 어댑터는 HTTP 요청, JSON 매핑, 입력 검증, 유스케이스 호출, HTTP 응답 변환을 담당한다.
이 책임은 Spring MVC와 강하게 결합되어 있으므로 framework와 통합된 상태로 테스트하는 편이 낫다.

```java
@WebMvcTest(controllers = SendMoneyController.class)
class SendMoneyControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private SendMoneyUseCase sendMoneyUseCase;

    @Test
    void testSendMoney() throws Exception {
        mockMvc.perform(post("/accounts/send/{sourceAccountId}/{targetAccountId}/{amount}",
                        41L, 42L, 500L)
                        .header("Content-Type", "application/json"))
                .andExpect(status().isOk());

        then(sendMoneyUseCase).should()
                .sendMoney(eq(new SendMoneyCommand(
                        new AccountId(41L),
                        new AccountId(42L),
                        Money.of(500L))));
    }
}
```

겉으로는 controller 하나만 테스트하는 것처럼 보인다.
하지만 `@WebMvcTest`는 요청 경로 매핑, Java-JSON 변환, HTTP 입력 검증에 필요한 Spring MVC 객체 네트워크를 구성한다.
테스트는 controller가 이 네트워크 안에서 올바르게 동작하는지 확인한다.

웹 controller를 순수 단위 테스트로만 검증하면 HTTP 매핑, validation, serialization 커버리지가 낮아진다.
프로덕션 환경에서 실제 요청이 정상 처리될지 확신하기 어렵다.
그래서 웹 어댑터는 통합 테스트가 합리적이다.

---

## 5. 통합 테스트로 영속성 어댑터 테스트하기

영속성 어댑터도 단위 테스트보다 통합 테스트가 적절하다.
어댑터 로직뿐 아니라 SQL, DB table, ORM mapping까지 함께 검증해야 하기 때문이다.

```java
@DataJpaTest
@Import({ AccountPersistenceAdapter.class, AccountMapper.class })
class AccountPersistenceAdapterTest {

    @Autowired
    private AccountPersistenceAdapter adapter;

    @Autowired
    private ActivityRepository activityRepository;

    @Test
    @Sql("AccountPersistenceAdapterTest.sql")
    void loadsAccount() {
        Account account = adapter.loadAccount(new AccountId(1L));

        assertThat(account.getActivityWindow().getActivities()).hasSize(2);
        assertThat(account.calculateBalance()).isEqualTo(Money.of(500L));
    }

    @Test
    void updatesActivities() {
        Account account = defaultAccount()
                .withBaselineBalance(Money.of(555L))
                .withActivityWindow(new ActivityWindow(
                        defaultActivity()
                                .withId(null)
                                .withMoney(Money.of(1L))
                                .build()))
                .build();

        adapter.updateActivities(account);

        assertThat(activityRepository.findAll()).hasSize(1);
    }
}
```

`@DataJpaTest`는 Spring Data repository를 포함해 DB 접근에 필요한 객체 네트워크를 만든다.
`@Import`를 사용하면 테스트에 포함할 adapter와 mapper를 명시적으로 추가할 수 있다.

`loadAccount()` 테스트는 SQL script로 DB를 특정 상태로 만든 뒤 adapter가 도메인 모델을 제대로 복원하는지 확인한다.
`updateActivities()` 테스트는 반대로 도메인 객체를 adapter에 넘기고, DB에 활동이 저장되었는지 검증한다.

중요한 점은 DB를 mock하지 않는다는 것이다.
DB를 mock하면 코드 라인 커버리지는 비슷하게 나올 수 있다.
하지만 SQL 문법, table 구조, ORM mapping 오류는 잡을 수 없다.

Spring은 H2 같은 인메모리 DB를 제공한다.
실용적이지만 실제 DB engine 고유 문법까지 검증해야 한다면 부족할 수 있다.
이럴 때 Testcontainers로 PostgreSQL, MySQL 같은 실제 DB를 테스트 중에 띄우는 방식이 유용하다.

---

## 6. 시스템 테스트로 주요 경로 테스트하기

시스템 테스트는 테스트 피라미드의 최상단에 있다.
전체 application을 띄우고 API로 요청을 보내 모든 계층이 함께 동작하는지 검증한다.

```java
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class SendMoneySystemTest {

    @Autowired
    private TestRestTemplate restTemplate;

    @Autowired
    private LoadAccountPort loadAccountPort;

    @Test
    void sendMoney() {
        Money initialSourceBalance = getBalance(new AccountId(1L));
        Money initialTargetBalance = getBalance(new AccountId(2L));

        ResponseEntity<Void> response = restTemplate.postForEntity(
                "/accounts/send/{sourceAccountId}/{targetAccountId}/{amount}",
                null,
                Void.class,
                1L, 2L, 500L);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(getBalance(new AccountId(1L)))
                .isEqualTo(initialSourceBalance.minus(Money.of(500L)));
        assertThat(getBalance(new AccountId(2L)))
                .isEqualTo(initialTargetBalance.plus(Money.of(500L)));
    }

    private Money getBalance(AccountId accountId) {
        return loadAccountPort.loadAccount(accountId).calculateBalance();
    }
}
```

`@SpringBootTest`는 애플리케이션을 구성하는 전체 객체 네트워크를 띄운다.
웹 어댑터 테스트처럼 `MockMvc`로 controller를 직접 호출하지 않고,
`TestRestTemplate`으로 실제 HTTP 요청을 보낸다.
프로덕션 환경에 조금 더 가까운 방식이다.

출력 어댑터도 실제 구현을 사용한다.
예제에서는 application과 DB를 연결하는 persistence adapter가 해당된다.
다만 모든 third-party system을 시스템 테스트에서 실제로 띄우기는 어렵다.
외부 결제, 메일, 메시징 시스템은 mock이나 fake로 대체해야 할 때가 있다.

**헥사고날 아키텍처의 장점은 여기서 강하게 드러난다.**
외부 시스템을 직접 mock하는 대신, application core가 의존하는 outgoing port interface 몇 개만 mock하면 된다.
외부 기술이 adapter 뒤에 숨어 있으므로 시스템 테스트의 대체 지점이 명확해진다.

테스트 가독성을 위해 지저분한 준비 로직과 검증 로직은 helper method로 숨길 수 있다.
이 helper들이 모이면 테스트 전용 DSL(Domain-Specific Language)이 된다.

> **Note: 테스트 DSL**
>
> DSL이라고 해서 꼭 새로운 언어를 만든다는 뜻은 아니다.
> 같은 Java 코드라도 특정 도메인을 읽기 쉬운 어휘로 표현하면 DSL처럼 사용할 수 있다.
>
> ex)
>
> ```java
> givenAccount().withBalance(1000);
> sendMoney().from(1L).to(2L).amount(500L);
> assertAccount(1L).hasBalance(500);
> ```
>
> 이는 문법은 Java지만, 테스트를 읽는 사람은 "계좌를 준비하고, 송금하고, 잔고를 확인한다"는 도메인 문장처럼 이해할 수 있다.

> **Note: JGiven**
>
> JGiven은 Java 테스트에서 BDD 스타일 시나리오를 작성하도록 돕는 라이브러리다.
> `given()`, `when()`, `then()` 단계와 도메인 어휘를 조합해 테스트를 읽기 쉬운 시나리오로 만들 수 있다.
>
> 시스템 테스트에서는 특히 유용하다.
> 내부 구현보다 사용자 관점의 행동을 표현해야 하기 때문이다.
>
> 기본 형태는 다음과 같다.
>
> ```java
> class SendMoneyScenarioTest
>         extends ScenarioTest<GivenAccountState, WhenSendMoney, ThenAccountState> {
>
>     @Test
>     void sendMoneyBetweenAccounts() {
>         given()
>                 .account_$_has_balance(1L, 1_000L)
>                 .and()
>                 .account_$_has_balance(2L, 500L);
>
>         when()
>                 .the_user_sends_$_from_account_$_to_account_$(300L, 1L, 2L);
>
>         then()
>                 .account_$_has_balance(1L, 700L)
>                 .and()
>                 .account_$_has_balance(2L, 800L);
>     }
> }
> ```
>
> `GivenAccountState`, `WhenSendMoney`, `ThenAccountState` 같은 stage class가 테스트 어휘를 정의한다.
>
> ```java
> class GivenAccountState extends Stage<GivenAccountState> {
>
>     @Autowired
>     private AccountRepository accountRepository;
>
>     GivenAccountState account_$_has_balance(Long accountId, long balance) {
>         accountRepository.save(accountWithBalance(accountId, balance));
>         return self();
>     }
> }
> ```
>
> ```java
> class WhenSendMoney extends Stage<WhenSendMoney> {
>
>     @Autowired
>     private TestRestTemplate restTemplate;
>
>     WhenSendMoney the_user_sends_$_from_account_$_to_account_$(
>             long amount,
>             Long sourceAccountId,
>             Long targetAccountId
>     ) {
>         restTemplate.postForEntity(
>                 "/accounts/send/{sourceAccountId}/{targetAccountId}/{amount}",
>                 null,
>                 Void.class,
>                 sourceAccountId,
>                 targetAccountId,
>                 amount);
>         return self();
>     }
> }
> ```
>
> ```java
> class ThenAccountState extends Stage<ThenAccountState> {
>
>     @Autowired
>     private LoadAccountPort loadAccountPort;
>
>     ThenAccountState account_$_has_balance(Long accountId, long expectedBalance) {
>         Account account = loadAccountPort.loadAccount(new AccountId(accountId));
>         assertThat(account.calculateBalance()).isEqualTo(Money.of(expectedBalance));
>         return self();
>     }
> }
> ```
>
> 이 방식의 장점은 테스트 본문이 구현 세부사항보다 도메인 문장에 가까워진다는 점이다.
>
> ```java
> given().account_$_has_balance(1L, 1_000L);
> when().the_user_sends_$_from_account_$_to_account_$(300L, 1L, 2L);
> then().account_$_has_balance(1L, 700L);
> ```
>
> 실패 리포트도 시나리오 문장처럼 읽힌다.
>
> ```text
> Given account 1 has balance 1000
> When the user sends 300 from account 1 to account 2
> Then account 1 has balance 700
> ```
>
> 더 복잡한 시스템 테스트에서는 여러 stage를 조합할 수 있다.
>
> ```java
> given()
>         .account_$_has_balance(1L, 1_000L)
>         .and()
>         .daily_transfer_limit_is(500L);
>
> when()
>         .the_user_sends_$_from_account_$_to_account_$(700L, 1L, 2L);
>
> then()
>         .the_request_is_rejected()
>         .and()
>         .account_$_has_balance(1L, 1_000L);
> ```
>
> 즉 JGiven의 핵심은 테스트 프레임워크를 바꾸는 것이 아니라,
> 테스트 코드를 도메인 전문가도 읽을 수 있는 시나리오 언어에 가깝게 만드는 것이다.

시스템 테스트는 단위 테스트나 통합 테스트가 놓치기 쉬운 버그를 찾는다.
대표적으로 계층 간 mapping 오류, Spring bean wiring 오류, 실제 HTTP 요청/응답 오류가 있다.

---

## 7. 얼마만큼의 테스트가 충분할까

라인 커버리지는 좋은 기준이 아니다.
80%가 충분한지, 100%가 충분한지 답하기 어렵다.
100%가 아니면 중요한 로직이 빠졌을 수 있고, 100%여도 버그를 잘 잡는다는 보장은 없다.

저자는 "마음 편히 배포할 수 있는가"를 더 실용적인 기준으로 본다.
자주 배포할수록 테스트 신뢰도도 실제로 검증된다.
1년에 두 번만 배포한다면 테스트도 1년에 두 번만 검증되는 셈이므로 신뢰하기 어렵다.

배포 후 버그가 발생하면 항상 질문해야 한다.

```text
왜 테스트가 이 버그를 잡지 못했을까?
```

그리고 원인을 기록하고 테스트를 추가한다.

헥사고날 아키텍처에서 기본 테스트 전략은 다음과 같다.

1. 도메인 엔티티는 단위 테스트로 커버한다.
2. 유스케이스는 단위 테스트로 핵심 상호작용을 검증한다.
3. 어댑터 구현 시 통합 테스트로 커버한다.
4. 사용자가 취할 수 있는 주요 application 경로는 시스템 테스트로 커버한다.

여기서 중요한 말은 **구현할 때**다.
테스트를 기능 개발이 끝난 뒤 억지로 붙이면 귀찮은 산출물이 된다.
반대로 구현 중에 테스트를 쓰면, 방금 만든 코드가 동작하는지 즉시 알려주는 개발 도구가 된다.
테스트가 설계 피드백 역할도 한다.

다만 필드 하나를 추가하는데 테스트를 한 시간 고쳐야 한다면 테스트 구조가 잘못된 것이다.
테스트가 구현 세부사항에 너무 강하게 묶였다는 신호다.
리팩터링할 때마다 테스트가 깨진다면 테스트는 안전망이 아니라 유지보수 비용이 된다.

---

## 8. 유지보수 가능한 소프트웨어를 만드는 데 어떻게 도움이 될까

헥사고날 아키텍처는 도메인 로직과 바깥 어댑터를 분리한다.
그래서 테스트 전략도 명확해진다.

| 대상 | 적절한 테스트 |
|---|---|
| 도메인 엔티티 | 단위 테스트 |
| 유스케이스 서비스 | 단위 테스트 |
| 웹 어댑터 | 통합 테스트 |
| 영속성 어댑터 | 통합 테스트 |
| 주요 사용자 경로 | 시스템 테스트 |

입출력 port는 명확한 mocking 지점이 된다.
mock을 쓸지 실제 구현을 쓸지 선택하기도 쉽다.
port interface가 좁을수록 어떤 메서드를 mock해야 할지 덜 헷갈린다.

mocking이 버겁거나 어떤 종류의 테스트를 써야 할지 계속 헷갈린다면 경고 신호다.
아키텍처 경계가 흐려졌거나 port가 너무 넓거나, 도메인 로직이 어댑터에 섞였을 수 있다.

> **Note: 카나리아**
>
> 카나리아는 작은 참새목 새다.
> 노란색 품종이 잘 알려져 있고, 노래하는 새로도 유명하다.
>
> 광산에서는 과거에 유독가스를 감지하기 위해 카나리아를 데려갔다.
> 카나리아가 먼저 이상 반응을 보이면 사람이 위험을 알아차릴 수 있었기 때문이다.
>
> 소프트웨어에서 "카나리아"는 문제가 커지기 전에 위험 신호를 알려주는 장치를 비유한다.
> 테스트가 너무 어렵거나 자주 깨진다면, 그 자체가 아키텍처 문제를 알려주는 카나리아가 될 수 있다.

좋은 테스트는 단순히 버그를 잡는 도구가 아니다.
아키텍처 경계가 잘 지켜지고 있는지 알려주는 피드백 장치다.

---

## 9. 참고

- [도서] 만들면서 배우는 클린 아키텍처 - 톰 홈버그(Tom Hombergs)
- [도서] Succeeding with Agile: Software Development Using Scrum - Mike Cohn
- [라이브러리] Mockito
- [라이브러리] Testcontainers
- [라이브러리] JGiven
