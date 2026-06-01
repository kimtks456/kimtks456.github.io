---
title: "9. 애플리케이션 조립하기"
weight: 9
date: 2026-06-01
description: "유스케이스, 웹 어댑터, 영속성 어댑터를 의존성 주입으로 조립하는 방법을 정리한다."
---

## 1. 애플리케이션 조립하기

유스케이스, 웹 어댑터, 영속성 어댑터를 구현했다면 이제 이들을 하나의 application으로 조립해야 한다.
application이 시작될 때 필요한 class를 instance화하고, 서로 연결해야 한다.
이를 위해 의존성 주입(dependency injection) 메커니즘을 사용한다.

이 장에서는 Java에서 객체를 어떻게 조립할 수 있는지,
Spring과 Spring Boot framework가 이 작업을 어떻게 도와주는지 살펴본다.

---

## 2. 왜 조립까지 신경 써야 할까

그냥 필요한 곳에서 직접 객체를 만들면 안 될까?

```java
class SendMoneyService {

    private final AccountPersistenceAdapter persistenceAdapter =
            new AccountPersistenceAdapter();
}
```

이렇게 하면 유스케이스가 영속성 어댑터를 직접 알게 된다.
의존성 방향이 application core에서 바깥 adapter로 향하므로 헥사고날 아키텍처의 핵심 규칙을 깨뜨린다.

```text
나쁜 방향:

application.service ─────────▶ adapter.out.persistence
```

의존성은 안쪽으로 향해야 한다.
도메인과 application code가 바깥 계층의 변경으로부터 안전해야 하기 때문이다.

따라서 유스케이스는 outgoing port interface만 알아야 한다.
런타임에는 이 port를 구현한 adapter instance를 외부에서 제공받는다.

```text
좋은 방향:

application.service ─────────▶ application.port.out ◀──────── adapter.out.persistence
```

이 스타일은 테스트에도 유리하다.
class가 필요한 모든 객체를 생성자로 받으면, 테스트에서 실제 adapter 대신 mock을 전달할 수 있다.

```java
class SendMoneyService {

    private final LoadAccountPort loadAccountPort;
    private final UpdateAccountStatePort updateAccountStatePort;

    SendMoneyService(
            LoadAccountPort loadAccountPort,
            UpdateAccountStatePort updateAccountStatePort
    ) {
        this.loadAccountPort = loadAccountPort;
        this.updateAccountStatePort = updateAccountStatePort;
    }
}
```

테스트에서는 다음처럼 격리된 단위 테스트를 만들 수 있다.

```java
LoadAccountPort loadAccountPort = mock(LoadAccountPort.class);
UpdateAccountStatePort updateAccountStatePort = mock(UpdateAccountStatePort.class);

SendMoneyService service = new SendMoneyService(loadAccountPort, updateAccountStatePort);
```

남는 질문은 이것이다.

```text
그럼 객체 생성과 연결 책임은 누가 가져야 하는가?
```

해답은 configuration component다.
이 컴포넌트는 아키텍처적으로 중립적인 바깥쪽 구성요소다.
instance 생성을 위해 모든 class를 알아야 하므로, 의존성 규칙상 가장 바깥쪽에 둔다.

```text
                                      Configuration Component
                                      application bootstrap
                                      ─────────────────────
                                                │
                 ┌──────────────────────────────┼──────────────────────────────┐
                 │                              │                              │
                 ▼                              ▼                              ▼
          Web Adapter                    Application Core              Persistence Adapter
          account.adapter.in.web         account.application           account.adapter.out.persistence
          ──────────────────────         ───────────────────           ───────────────────────────────

          SendMoneyController ────────▶ SendMoneyUseCase ◀──────────── SendMoneyService ───────────▶ UpdateAccountStatePort ◀──── AccountPersistenceAdapter
                                                                                ▲                                               ▲
                                                                                │                                               │
                                                                                └────────── inject dependencies ────────────────┘
```

Clean Architecture의 원형 그림으로 보면 configuration component는 가장 바깥쪽 원에 위치한다.
가장 바깥쪽은 내부의 모든 요소를 알고 조립할 수 있다.
반대로 내부 요소는 configuration component를 몰라야 한다.

configuration component는 application 조립을 책임진다.

1. 웹 어댑터 instance 생성
2. HTTP 요청이 실제 웹 어댑터로 전달되도록 보장
3. 유스케이스 instance 생성
4. 영속성 어댑터 instance 생성
5. 유스케이스에 영속성 어댑터 instance 제공
6. 영속성 어댑터가 실제 DB에 접근할 수 있게 보장

또한 command line parameter, environment variable, config file 같은 설정 값에도 접근할 수 있어야 한다.

이 컴포넌트는 책임이 많다.
즉 변경할 이유도 많으므로 단일 책임 원칙(SRP)을 엄격히 보면 위반한다.

하지만 이 책임을 application core나 adapter에 흩뿌리는 것보다 낫다.
나머지 코드를 깔끔하게 유지하려면, 구성요소를 한곳에서 연결하는 바깥쪽 컴포넌트가 필요하다.

---

## 3. 평범한 코드로 조립하기

configuration component는 꼭 framework로 구현해야 하는 것은 아니다.
의존성 주입 framework 없이 평범한 Java code로도 만들 수 있다.

```java
public class Application {

    public static void main(String[] args) {
        AccountRepository accountRepository = new AccountRepository();
        ActivityRepository activityRepository = new ActivityRepository();
        AccountMapper accountMapper = new AccountMapper();

        AccountPersistenceAdapter accountPersistenceAdapter =
                new AccountPersistenceAdapter(
                        accountRepository,
                        activityRepository,
                        accountMapper);

        SendMoneyUseCase sendMoneyUseCase =
                new SendMoneyService(
                        accountPersistenceAdapter,
                        accountPersistenceAdapter);

        SendMoneyController sendMoneyController =
                new SendMoneyController(sendMoneyUseCase);

        startProcessingWebRequests(sendMoneyController);
    }

    private static void startProcessingWebRequests(SendMoneyController sendMoneyController) {
        // web adapter를 HTTP로 노출하는 bootstrap logic
    }
}
```

Java application은 `main()` method에서 시작한다.
따라서 `main()` 안에서 필요한 모든 class instance를 만들고 연결할 수 있다.
마지막의 `startProcessingWebRequests()`는 web controller를 HTTP로 노출하는 bootstrap logic이 들어갈 자리다.
여기서는 실제 구현을 생략한다.

이 방식은 원리를 이해하기 쉽지만, 현실적인 단점이 있다.

1. application이 커지면 설정 code가 거대해진다.

   위 예시는 web controller, use case, persistence adapter가 하나씩만 있다.
   enterprise application에서는 수십, 수백 개의 객체를 생성하고 연결해야 할 수 있다.

2. 대부분의 class가 `public`이어야 한다.

   `Application` class가 각 class의 package 바깥에서 instance를 생성하려면 생성 대상 class에 접근할 수 있어야 한다.
   그러면 package-private으로 아키텍처 경계를 보호하기 어렵다.

   ```text
   account.adapter.out.persistence
   ───────────────────────────────
   public AccountPersistenceAdapter

   account.application.service
   ───────────────────────────
   public SendMoneyService
   ```

   이렇게 열어두면 유스케이스가 영속성 어댑터에 직접 접근하지 못하게 막기 어렵다.

다행히 의존성 주입 framework가 이런 지저분한 조립 작업을 대신해준다.
Java 진영에서는 Spring Framework가 가장 널리 쓰인다.
Spring은 web과 DB 환경까지 지원하므로 `startProcessingWebRequests()` 같은 bootstrap method도 직접 만들 필요가 없다.

---

## 4. 스프링의 클래스패스 스캐닝으로 조립하기

Spring Framework가 application을 조립한 결과물을 application context라고 부른다.
application context는 application을 구성하는 객체(bean)를 담고 있다.

Spring은 application context를 조립하는 여러 방법을 제공한다.
가장 편한 방식은 classpath scanning이다.

classpath scanning은 classpath에서 접근 가능한 class 중 `@Component`가 붙은 class를 찾아 bean으로 등록한다.
Spring은 생성자를 보고 필요한 의존성을 자동으로 주입한다.
생성자는 직접 만들 수도 있고, Lombok의 `@RequiredArgsConstructor`로 만들 수도 있다.

```java
@Component
@RequiredArgsConstructor
class SendMoneyService implements SendMoneyUseCase {

    private final LoadAccountPort loadAccountPort;
    private final UpdateAccountStatePort updateAccountStatePort;
}
```

Spring이 인식할 수 있도록 `@Component`가 붙은 custom annotation을 만들 수도 있다.

```java
@Target(ElementType.TYPE)
@Retention(RetentionPolicy.RUNTIME)
@Documented
@Component
public @interface PersistenceAdapter {
}
```

영속성 어댑터에는 다음처럼 붙인다.

```java
@PersistenceAdapter
@RequiredArgsConstructor
class AccountPersistenceAdapter implements LoadAccountPort, UpdateAccountStatePort {

    private final AccountRepository accountRepository;
    private final ActivityRepository activityRepository;
    private final AccountMapper accountMapper;
}
```

이렇게 하면 단순히 Spring bean이라는 의미를 넘어,
"이 class는 persistence adapter다"라는 아키텍처 의미도 드러난다.

하지만 classpath scanning에도 단점이 있다.

1. framework annotation이 application code에 침투한다.

   class마다 `@Component`, `@Service`, `@PersistenceAdapter` 같은 Spring 기반 annotation을 붙여야 한다.
   일반적인 application 개발에서는 이 정도 결합은 받아들일 수 있다.
   하지만 다른 개발자가 사용할 library나 framework를 만든다면 지양하는 편이 낫다.
   library 사용자가 Spring에 의존하게 되기 때문이다.

2. 의도치 않은 bean이 application context에 올라갈 수 있다.

   classpath scanning은 지정한 package 아래의 `@Component`를 넓게 훑는다.
   application이 커지면 어떤 bean이 context에 올라오는지 한눈에 알기 어렵다.

   ```java
   @Component
   class TestClock implements Clock {
       // 테스트용으로만 의도했지만 scanning 범위에 들어가면 실제 context에도 등록될 수 있다.
   }
   ```

   이런 문제는 Spring에 익숙하지 않으면 추적하기 어렵다.
   scanning은 편하지만 둔한 도구다.

---

## 5. 스프링의 자바 컨피그로 조립하기

다른 방법은 application context에 추가할 bean을 명시적으로 생성하는 Java configuration class를 만드는 것이다.
ex) 모든 persistence adapter instance 생성을 담당하는 설정 class를 둘 수 있다.

```java
@Configuration
@EnableJpaRepositories
class PersistenceAdapterConfiguration {

    @Bean
    AccountPersistenceAdapter accountPersistenceAdapter(
            AccountRepository accountRepository,
            ActivityRepository activityRepository,
            AccountMapper accountMapper
    ) {
        return new AccountPersistenceAdapter(
                accountRepository,
                activityRepository,
                accountMapper);
    }

    @Bean
    AccountMapper accountMapper() {
        return new AccountMapper();
    }
}
```

`@Configuration` class 자체는 여전히 classpath scanning으로 발견될 수 있다.
하지만 모든 bean을 scanning으로 긁어오는 대신, 설정 class만 선택하고 그 안의 factory method로 bean을 만든다.
그래서 의도하지 않은 구현 class가 application context에 올라갈 가능성이 줄어든다.

`@Bean` method의 parameter는 Spring이 자동으로 제공한다.
위 예시에서 `AccountRepository`, `ActivityRepository`는 `@EnableJpaRepositories` 때문에 Spring Data JPA가 구현체를 만들어준다.
`AccountMapper`는 같은 configuration class의 `@Bean` method가 생성한다.

`@EnableJpaRepositories`를 main application class에 붙일 수도 있다.
하지만 그렇게 하면 application을 시작할 때마다 JPA repository가 활성화된다.
영속성이 필요 없는 테스트에서도 JPA 관련 context가 뜨므로 오버헤드가 생긴다.

기능별 annotation은 별도 설정 모듈로 옮기는 편이 유연하다.

```text
PersistenceAdapterConfiguration
  → JPA repository 활성화
  → persistence adapter bean 등록

WebAdapterConfiguration
  → web adapter bean 등록

UseCaseConfiguration
  → application service bean 등록
```

이렇게 하면 특정 테스트에서 필요한 module만 application context에 포함할 수 있다.

```java
@SpringBootTest(classes = {
        UseCaseConfiguration.class,
        PersistenceAdapterConfiguration.class
})
class PersistenceSliceTest {
}
```

반대로 web layer만 테스트하고 persistence는 mock으로 대체할 수도 있다.

```java
@SpringBootTest(classes = WebAdapterConfiguration.class)
class WebAdapterTest {

    @MockBean
    SendMoneyUseCase sendMoneyUseCase;
}
```

### 5.1. Java Config도 스캔에 맡기니 불필요한 Bean 생성을 못 막지 않나

Java Config도 설정 class 자체를 component scanning으로 찾게 두면,
의도치 않은 설정 class가 application context에 올라갈 수 있다.

```java
@Configuration
class ExperimentalPersistenceConfiguration {

    @Bean
    AccountPersistenceAdapter experimentalAccountPersistenceAdapter(...) {
        // 아직 실험 중인 구현
    }
}
```

이 설정 class가 scanning 범위 안에 있으면 Spring이 발견할 수 있다.
따라서 Java Config가 자동으로 안전한 것은 아니다.

차이는 등록 단위다.

| 방식 | bean 후보 |
|---|---|
| classpath scanning | scanning 범위 안의 `@Component` class 전체 |
| Java Config + scanning | scanning 범위 안의 `@Configuration` class와 그 안의 `@Bean` method |
| Java Config + 명시적 import | 직접 선택한 configuration class의 `@Bean` method |

classpath scanning 방식에서는 실제 구현 class가 광범위하게 bean 후보가 된다.

```java
@Component
class SendMoneyService {
}

@Component
class AccountPersistenceAdapter {
}

@Component
class SomeExperimentalAdapter {
}
```

반면 Java Config 방식에서는 실제 bean 등록 지점이 `@Bean` method로 모인다.

```java
@Configuration
class PersistenceAdapterConfiguration {

    @Bean
    AccountPersistenceAdapter accountPersistenceAdapter(...) {
        return new AccountPersistenceAdapter(...);
    }
}
```

더 엄격하게 하려면 설정 class도 scanning에 맡기지 않고 직접 import한다.

```java
@SpringBootApplication
@Import({
        UseCaseConfiguration.class,
        WebAdapterConfiguration.class,
        PersistenceAdapterConfiguration.class
})
class BuckPalApplication {
}
```

테스트에서도 필요한 설정 module만 직접 고를 수 있다.

```java
@SpringBootTest(classes = WebAdapterConfiguration.class)
class SendMoneyControllerTest {
}
```

정리하면 Java Config의 장점은 "스캔을 써도 무조건 안전하다"가 아니다.
bean 등록 지점을 설정 class로 모아 투명성을 높이고,
`@Import`나 `classes` 지정과 함께 사용할 때 classpath scanning의 불투명성을 크게 줄일 수 있다는 점이다.

### 5.2. 왜 Java Config가 덜 침투적인가

Java Config도 Spring을 사용하므로 `@Configuration`, `@Bean` 같은 Spring annotation은 필요하다.
차이는 annotation이 붙는 위치다.

classpath scanning 방식에서는 실제 application class에 Spring annotation이 붙는다.

```java
@Component
class SendMoneyService {
}
```

Java Config 방식에서는 application class를 순수 Java class로 둘 수 있다.
Spring annotation은 설정 class에만 모인다.

```java
class SendMoneyService {
}

@Configuration
class UseCaseConfiguration {

    @Bean
    SendMoneyService sendMoneyService(LoadAccountPort loadAccountPort) {
        return new SendMoneyService(loadAccountPort);
    }
}
```

즉 "Spring 의존성이 완전히 사라진다"는 뜻이 아니다.
Spring 의존성이 application code가 아니라 configuration code에 갇힌다는 뜻이다.
이 점이 classpath scanning과의 차이다.

이 방식은 특히 application 계층을 framework에 독립적으로 유지하고 싶을 때 유용하다.
`SendMoneyService` 같은 core class를 Spring 없이도 단위 테스트하거나, 다른 조립 방식으로 재사용할 수 있다.

### 5.3. Java Config의 한계

Java Config에도 문제가 있다.
설정 class가 생성하는 bean class가 package-private이면, 설정 class가 같은 package에 있어야 한다.

```text
account.adapter.out.persistence
───────────────────────────────
AccountPersistenceAdapter          // package-private
PersistenceAdapterConfiguration    // 같은 package에 있어야 생성 가능
```

package-private class는 같은 package에서만 접근 가능하다.
Java에서 하위 package는 같은 package가 아니다.

```text
account.adapter.out.persistence
├── PersistenceAdapterConfiguration
└── jpa
    └── AccountPersistenceAdapter  // package-private
```

위 구조에서 `PersistenceAdapterConfiguration`은 `account.adapter.out.persistence` package에 있다.
`AccountPersistenceAdapter`는 `account.adapter.out.persistence.jpa` package에 있다.
이 둘은 부모-자식처럼 보이지만 Java 접근 제어 기준으로는 완전히 다른 package다.

따라서 아래 코드는 compile error가 난다.

```java
package account.adapter.out.persistence;

@Configuration
class PersistenceAdapterConfiguration {

    @Bean
    AccountPersistenceAdapter accountPersistenceAdapter(...) {
        return new AccountPersistenceAdapter(...);
    }
}
```

```java
package account.adapter.out.persistence.jpa;

class AccountPersistenceAdapter implements LoadAccountPort {
    // package-private class
}
```

상위 package의 설정 class가 하위 package의 package-private adapter에 접근할 수 없기 때문이다.
해결하려면 선택지가 있다.

1. adapter class를 `public`으로 연다.
2. configuration class를 adapter와 같은 package로 옮긴다.
3. 하위 package를 덜 쓰는 구조로 바꾼다.

하지만 1번은 package-private으로 아키텍처 경계를 보호하려던 의도를 약화시킨다.
2번은 package마다 configuration class가 흩어질 수 있다.
3번은 패키지 구조의 표현력이 줄어든다.

그래서 Java Config는 투명하지만,
package-private 접근 제어와 깊은 package 구조를 함께 쓰려면 설계 trade-off가 생긴다.

이 문제는 [10. 아키텍처 경계 강제하기](./10_enforcing-architecture-boundaries/)에서 다시 다룬다.

---

## 6. 유지보수 가능한 소프트웨어를 만드는 데 어떻게 도움이 될까

Spring과 Spring Boot는 application 조립을 편하게 만든다.
classpath scanning은 특히 빠르게 개발하기 좋다.
application 전체 구조를 깊게 고민하지 않아도 `@Component`를 붙이면 bean이 등록된다.

하지만 규모가 커질수록 투명성이 낮아진다.
어떤 bean이 application context에 들어오는지 파악하기 어려워지고, 테스트에서 context 일부만 독립적으로 띄우기도 어려워진다.

ex) web adapter만 테스트하고 싶은데, scanning 범위 때문에 persistence adapter까지 같이 올라올 수 있다.

```java
@SpringBootTest
class SendMoneyControllerTest {

    // controller만 검증하고 싶지만,
    // scanning 때문에 repository, datasource, mapper까지 context에 포함될 수 있다.
}
```

반면 전용 설정 component를 두면 필요한 module만 골라 context를 만들 수 있다.

```java
@SpringBootTest(classes = WebAdapterConfiguration.class)
class SendMoneyControllerTest {

    @MockBean
    SendMoneyUseCase sendMoneyUseCase;
}
```

설정 class를 module 가까이에 두면 응집도 높은 module을 만들 수 있다.
module을 다른 package, codebase, jar 파일로 옮길 때도 관련 설정을 함께 옮길 수 있다.

```text
account.adapter.out.persistence
───────────────────────────────
AccountPersistenceAdapter
ActivityRepository
AccountMapper
PersistenceAdapterConfiguration
```

이 말은 "어디에 있든 자동 등록되니 괜찮다"는 뜻이 아니다.
오히려 module이 필요로 하는 조립 정보를 같은 곳에 두기 때문에,
module을 옮길 때 누락되는 의존성이 줄어든다는 뜻이다.

다만 configuration class를 유지보수하는 공수는 추가된다.
생성자 parameter가 바뀌면 `@Bean` method도 함께 수정해야 한다.

```java
@Bean
SendMoneyService sendMoneyService(
        LoadAccountPort loadAccountPort,
        UpdateAccountStatePort updateAccountStatePort,
        AccountLock accountLock
) {
    return new SendMoneyService(loadAccountPort, updateAccountStatePort, accountLock);
}
```

이 비용은 classpath scanning의 편리함과 맞바꾸는 비용이다.
대신 어떤 bean이 올라오는지 명시적으로 통제할 수 있고,
module 단위 테스트와 분리가 쉬워진다.

---

## 7. 참고

- [도서] 만들면서 배우는 클린 아키텍처 - 톰 홈버그(Tom Hombergs)
