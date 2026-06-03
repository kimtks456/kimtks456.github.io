---
title: "10. 아키텍처 경계 강제하기"
weight: 10
date: 2026-06-03
description: "접근 제한자와 패키지 구조로 아키텍처 경계를 강제하는 방법을 정리한다."
---

## 1. 경계와 의존성

아키텍처 경계를 강제한다는 것은 의존성이 정해진 방향을 벗어나지 못하게 막는다는 뜻이다.

헥사고날 아키텍처의 경계는 다음처럼 볼 수 있다.

```text
바깥쪽                                                                 안쪽
Configuration ─────▶ Adapters ─────▶ Application Ports ─────▶ Application Services ─────▶ Domain
설정 계층             어댑터 계층       포트 계층                 유스케이스 구현체             엔티티
```

가장 안쪽에는 도메인 엔티티가 있다.
application 계층의 service는 유스케이스를 구현하기 위해 도메인 엔티티에 접근한다.

incoming adapter는 incoming port를 통해 application service에 접근한다.
반대로 application service는 outgoing port를 통해 outgoing adapter를 사용한다.

```text
adapter.in.web ─────────────▶ application.port.in ◀──────────── application.service

application.service ────────▶ application.port.out ◀─────────── adapter.out.persistence
```

그 바깥에는 adapter 계층이 있고, 가장 바깥에는 설정 계층이 있다.
설정 계층은 adapter와 service 객체를 생성하는 factory를 포함하고, 의존성 주입 메커니즘을 제공한다.

```text
configuration
  ├─ creates web adapter
  ├─ creates use case service
  ├─ creates persistence adapter
  └─ injects adapters into ports
```

계층 간 경계가 명확하다면 의존성은 항상 안쪽 방향으로 향해야 한다.
이 장에서는 이런 의존성 규칙을 강제하는 방법을 살펴본다.

---

## 2. 접근 제한자

가장 먼저 Java가 기본으로 제공하는 접근 제한자를 사용할 수 있다.

많이 쓰는 접근 제한자는 `public`, `protected`, `private`이다.
하지만 아키텍처 경계를 다룰 때 중요한 것은 package-private 접근 제한자다.
Java에서는 접근 제한자를 생략하면 package-private이 된다.

```java
class SendMoneyService {
}
```

package-private class는 같은 package 안에서만 접근할 수 있다.
이를 활용하면 package를 응집적인 작은 module처럼 만들 수 있다.
module 안의 class끼리는 서로 접근하고, 외부에서 접근해야 하는 진입점만 `public`으로 열어둔다.

[3. 코드 구성하기](./3_code-organization/)에서 본 패키지 구조를 다시 보면 다음과 같다.

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

이 구조에서 `adapter.out.persistence` package의 class들은 외부에서 직접 호출될 필요가 없다.
영속성 어댑터는 자신이 구현하는 outgoing port를 통해 사용된다.

```java
class AccountPersistenceAdapter implements LoadAccountPort, UpdateAccountStatePort {
    // package-private
}
```

application service도 같은 이유로 package-private으로 둘 수 있다.
외부 adapter는 service 구현체가 아니라 incoming port를 호출해야 하기 때문이다.

```java
class SendMoneyService implements SendMoneyUseCase {
    // package-private
}
```

반대로 domain package와 application port package는 외부 adapter에서 접근해야 하므로 `public`이어야 한다.

```java
public interface SendMoneyUseCase {
    boolean sendMoney(SendMoneyCommand command);
}

public interface LoadAccountPort {
    Account loadAccount(AccountId accountId);
}

public class Account {
}
```

### 2.1. Port가 public이어도 adapter 구현체는 package-private일 수 있나

가능하다.

port interface는 application 계층에 있고, 여러 계층에서 접근해야 하므로 `public`이어야 한다.
하지만 port를 구현하는 adapter class까지 public일 필요는 없다.

```java
package buckpal.account.application.port.out;

public interface LoadAccountPort {
    Account loadAccount(AccountId accountId);
}
```

```java
package buckpal.account.adapter.out.persistence;

class AccountPersistenceAdapter implements LoadAccountPort {

    @Override
    public Account loadAccount(AccountId accountId) {
        // ...
    }
}
```

외부 코드는 `AccountPersistenceAdapter` class를 직접 알 필요가 없다.
`LoadAccountPort` type으로만 주입받으면 된다.

```java
class SendMoneyService {

    private final LoadAccountPort loadAccountPort;

    SendMoneyService(LoadAccountPort loadAccountPort) {
        this.loadAccountPort = loadAccountPort;
    }
}
```

즉 public이어야 하는 것은 **계약인 port**다.
구현체인 adapter는 package-private으로 숨길 수 있다.

> **Note: public interface를 구현하는 method는 왜 public이어야 하나**
>
> `LoadAccountPort.loadAccount()`가 public method이므로,
> 이를 구현하는 `AccountPersistenceAdapter.loadAccount()`도 public이어야 한다.
>
> Java에서는 interface method의 접근 수준을 구현체에서 더 좁힐 수 없다.
> 하지만 class 자체는 package-private으로 둘 수 있다.
>
> ```java
> class AccountPersistenceAdapter implements LoadAccountPort {
>
>     @Override
>     public Account loadAccount(AccountId accountId) {
>         // method는 public
>     }
> }
> ```
>
> 그래서 "class는 숨기고, port method 계약은 공개한다"는 구조가 가능하다.

### 2.2. Reflection이면 접근 제한자가 상관없나

의존성 주입 framework는 보통 reflection으로 객체를 생성한다.
Spring도 bean을 만들 때 reflection을 사용할 수 있다.
그래서 package-private class나 생성자도 instance화할 수 있다.

```java
@Component
class SendMoneyService implements SendMoneyUseCase {

    SendMoneyService(LoadAccountPort loadAccountPort) {
        // package-private constructor
    }
}
```

Spring classpath scanning을 사용하면 위 class를 bean으로 만들 수 있다.
일반 Java code라면 다른 package에서 `new SendMoneyService(...)`를 호출할 수 없지만,
Spring은 reflection으로 생성자 접근을 열어 instance를 만들 수 있다.

> **Note: Reflection과 접근 제한자**
>
> reflection은 런타임에 class, constructor, method, field 정보를 조회하고 호출하는 기능이다.
> Java reflection API는 `setAccessible(true)` 같은 방식으로 일반 접근 제어를 우회할 수 있다.
>
> 다만 "항상 아무 제한 없이 가능하다"는 뜻은 아니다.
> Java module system, security policy, native image 설정 같은 환경에서는 reflection 접근이 제한될 수 있다.
>
> 일반적인 Spring Boot application에서는 Spring이 reflection을 사용해 package-private class나 생성자도 bean으로 만들 수 있다.
> 그래서 classpath scanning 방식에서는 package-private adapter/service를 유지하면서도 Spring이 조립할 수 있다.

주의할 점은 이 방법이 classpath scanning에 특히 잘 맞는다는 것이다.
Java Config 방식에서는 우리가 설정 class 안에서 직접 생성자를 호출한다.

```java
@Configuration
class UseCaseConfiguration {

    @Bean
    SendMoneyService sendMoneyService(LoadAccountPort loadAccountPort) {
        return new SendMoneyService(loadAccountPort);
    }
}
```

이 설정 class가 `SendMoneyService`와 다른 package에 있으면 package-private class에 접근할 수 없다.
따라서 Java Config를 쓰면서 package-private을 유지하려면 configuration class를 같은 package에 두어야 한다.

### 2.3. Package-Private은 왜 작은 모듈에서 효과적인가

package-private은 package 하나를 작은 module처럼 다룰 때 가장 효과적이다.

```text
account.adapter.out.persistence
───────────────────────────────
AccountPersistenceAdapter
SpringDataAccountRepository
AccountJpaEntity
ActivityJpaEntity
AccountMapper
```

이 정도 크기라면 package 안의 class들이 서로 밀접하게 협력한다.
외부에는 `LoadAccountPort`, `UpdateAccountStatePort` 같은 port만 노출하고,
내부 구현 class는 package-private으로 숨길 수 있다.

하지만 package 안 class가 너무 많아지면 구조가 흐려진다.
모든 내부 class가 서로 접근 가능해지기 때문이다.

```text
account.adapter.out.persistence
───────────────────────────────
AccountPersistenceAdapter
ActivityPersistenceAdapter
AccountJpaEntity
ActivityJpaEntity
AccountMapper
ActivityMapper
AccountQueryService
ActivityQueryService
SqlAccountReader
JpaAccountWriter
...
```

이 경우 package-private은 더 이상 강한 경계가 아니다.
같은 package 안의 너무 많은 class가 서로 접근할 수 있으므로 내부 결합이 늘어난다.
그래서 자연스럽게 하위 package로 나누고 싶어진다.

```text
account.adapter.out.persistence
├── jpa
│   ├── AccountJpaEntity
│   └── JpaAccountWriter
├── sql
│   └── SqlAccountReader
└── mapper
    └── AccountMapper
```

문제는 Java가 하위 package를 같은 package로 취급하지 않는다는 점이다.
`account.adapter.out.persistence.jpa`와 `account.adapter.out.persistence`는 완전히 다른 package다.

따라서 하위 package의 class를 다른 package에서 사용하려면 `public`으로 열어야 한다.

```java
package account.adapter.out.persistence.jpa;

public class JpaAccountWriter {
}
```

이렇게 public class가 늘어나면 외부에서 접근 가능한 표면이 커진다.
그만큼 아키텍처 의존성 규칙을 깨뜨릴 위험도 커진다.

```java
package account.application.service;

class SendMoneyService {

    // public으로 열린 adapter 내부 class를 직접 참조할 수 있게 됨
    private final JpaAccountWriter writer;
}
```

이런 코드가 가능해지는 순간 application service가 outgoing port를 우회하고 adapter 구현체에 의존할 수 있다.
즉 package-private을 통한 경계 보호가 약해진다.

---

## 3. 컴파일 후 체크

`public` 접근 제한자가 많아지면 Java compiler만으로는 의존성 방향 위반을 막기 어렵다.
잘못된 방향의 의존성이 생겨도 type이 접근 가능하면 정상 compile되기 때문이다.

이 경우 컴파일 후 체크를 도입할 수 있다.
통합 빌드 환경에서 자동화된 테스트로 아키텍처 규칙을 검사하는 방식이다.

Java 진영에서는 ArchUnit을 사용할 수 있다.
ArchUnit은 class dependency를 분석해서 package 간 의존성 규칙을 테스트로 검증한다.

ex) domain 계층이 application 계층에 의존하지 않는지 검사한다.

```java
@AnalyzeClasses(packages = "buckpal")
class DependencyRuleTest {

    @ArchTest
    static final ArchRule domainLayerDoesNotDependOnApplicationLayer =
            noClasses()
                    .that()
                    .resideInAPackage("..domain..")
                    .should()
                    .dependOnClassesThat()
                    .resideInAnyPackage("..application..");
}
```

이 테스트는 `domain` package 안의 class가 `application` package 안의 class에 의존하면 실패한다.
즉 domain이 바깥쪽 계층을 알게 되는 상황을 빌드에서 잡을 수 있다.

ArchUnit을 조금 감싸면 헥사고날 아키텍처 규칙을 표현하는 DSL을 만들 수도 있다.
아래 코드는 예시용 DSL이다.

```java
class HexagonalArchitectureTest {

    @Test
    void validateRegistrationContextArchitecture() {
        JavaClasses classes = new ClassFileImporter()
                .importPackages("buckpal.account");

        HexagonalArchitecture.boundedContext("account")
                .domainLayer("..account.domain..")
                .applicationLayer("..account.application..")
                    .incomingPorts("..account.application.port.in..")
                    .outgoingPorts("..account.application.port.out..")
                    .services("..account.application.service..")
                .adapterLayer("..account.adapter..")
                    .incomingAdapters("..account.adapter.in..")
                    .outgoingAdapters("..account.adapter.out..")
                .configurationLayer("..account.configuration..")
                .check(classes);
    }
}
```

이 DSL은 먼저 bounded context의 부모 package를 지정한다.
그다음 domain, application, adapter, configuration 계층에 해당하는 하위 package를 지정한다.
마지막 `check()`가 다음 같은 의존성 규칙을 검사한다.

```text
domain
  → 바깥 계층 의존 금지

application.service
  → domain, application.port 의존 가능
  → adapter 의존 금지

adapter.in
  → application.port.in 의존 가능

adapter.out
  → application.port.out 의존 가능

configuration
  → 모든 계층 의존 가능
```

컴파일 후 체크는 잘못된 의존성을 잡는 데 도움이 된다.
하지만 fail-safe 하지는 않다.

ex) package 이름에 오타가 있으면 테스트가 아무 class도 찾지 못할 수 있다.

```java
// buckpal이 아니라 bucKpal로 오타
.importPackages("bucKpal.account");
```

이 경우 규칙 위반 class를 찾지 못해 테스트가 통과할 수 있다.
이를 막으려면 대상 package에서 class를 실제로 찾았는지 확인하는 테스트도 필요하다.

```java
assertThat(classes).isNotEmpty();
```

즉 ArchUnit 테스트도 유지보수 대상이다.
package 구조를 리팩터링하면 ArchUnit 규칙도 함께 수정해야 한다.

---

## 4. 빌드 아티팩트

지금까지 코드 상의 아키텍처 경계는 주로 package로 표현했다.
모든 코드는 하나의 monolithic build artifact에 들어간다.

빌드 아티팩트는 자동화된 빌드 프로세스의 결과물이다.
Java 진영에서는 Maven이나 Gradle 같은 빌드 도구로 compile, test, package 작업을 수행하고 하나의 JAR로 묶을 수 있다.

```text
source code
  → compile
  → test
  → package
  → buckpal.jar
```

빌드 도구의 주요 기능 중 하나는 dependency resolution이다.
빌드 도구는 코드를 빌드 아티팩트로 만들기 전에 필요한 외부 아티팩트가 모두 사용 가능한지 확인한다.
없으면 artifact repository에서 가져오고, 그것도 실패하면 compile 전에 build가 실패한다.

이 기능을 이용해 module과 아키텍처 계층 간 의존성을 강제할 수 있다.
각 module이나 계층을 별도 build module, 별도 JAR로 분리하는 방식이다.

### 4.1. 하나의 application module

가장 단순한 구조는 application code가 하나의 JAR에 들어가는 것이다.

```text
buckpal.jar
────────────────────────────────────
configuration
adapter.in.web
adapter.out.persistence
application.service
application.port.in / port.out
domain
```

이 구조는 단순하지만, build 도구가 아키텍처 경계를 강제해주지는 않는다.
모든 class가 같은 module 안에 있으므로 잘못된 package 의존성도 compile될 수 있다.

### 4.2. Configuration / Adapters / Application 분리

첫 번째 분리 방법은 configuration, adapters, application을 별도 JAR로 나누는 것이다.

```text
configuration.jar
  ├─ depends on adapters.jar
  └─ depends on application.jar

adapters.jar
  └─ depends on application.jar

application.jar
  ├─ application.service
  ├─ application.port.in / port.out
  └─ domain
```

의존성 방향은 다음처럼 고정된다.

```text
configuration.jar ─────▶ adapters.jar ─────▶ application.jar
configuration.jar ─────────────────────────▶ application.jar
```

`application.jar`는 `adapters.jar`를 의존하지 않는다.
따라서 application service가 adapter 구현체를 직접 참조하려 하면 compile 자체가 실패한다.

### 4.3. Adapter별 분리

adapter끼리도 서로 영향을 주지 않는 편이 좋다.
web adapter 변경이 persistence adapter에 영향을 주면 안 된다.

그래서 adapter module을 더 쪼갤 수 있다.

```text
configuration.jar
  ├─ depends on web-adapter.jar
  ├─ depends on persistence-adapter.jar
  └─ depends on application.jar

web-adapter.jar
  └─ depends on application.jar

persistence-adapter.jar
  └─ depends on application.jar

application.jar
  ├─ application.service
  ├─ application.port.in / port.out
  └─ domain
```

이 구조에서는 web adapter가 persistence adapter를 직접 참조하지 못하게 만들 수 있다.
필요하다면 build script에서 adapter 간 의존성을 아예 선언하지 않으면 된다.

### 4.4. API module 분리

도메인 엔티티가 port의 전송 객체로 사용되지 않는 경우,
port를 API module로 분리할 수 있다.
즉 [8. 경계 간 매핑하기](./8_mapping-between-boundaries/)의 `매핑하지 않기` 전략을 사용하지 않는 경우에 적합하다.

```text
configuration.jar
  ├─ depends on web-adapter.jar
  ├─ depends on persistence-adapter.jar
  ├─ depends on application.jar
  └─ depends on api.jar

web-adapter.jar
  └─ depends on api.jar

persistence-adapter.jar
  └─ depends on api.jar

application.jar
  ├─ depends on api.jar
  └─ contains application.service

api.jar
  ├─ application.port.in
  └─ application.port.out
```

한 단계 더 나아가 incoming port와 outgoing port를 별도 module로 나눌 수도 있다.

```text
incoming-api.jar
  └─ application.port.in

outgoing-api.jar
  └─ application.port.out

web-adapter.jar
  └─ depends on incoming-api.jar

persistence-adapter.jar
  └─ depends on outgoing-api.jar

application.jar
  ├─ depends on incoming-api.jar
  └─ depends on outgoing-api.jar
```

이렇게 하면 특정 adapter가 incoming adapter인지 outgoing adapter인지 build dependency만 봐도 명확해진다.

### 4.5. Domain module 분리

application module을 더 나누어 service와 domain을 분리할 수도 있다.

```text
application.jar
  ├─ depends on api.jar
  ├─ depends on domain.jar
  └─ contains application.service

domain.jar
  └─ contains domain entities

api.jar
  └─ contains ports / commands / responses
```

이 구조에서는 domain entity가 application service에 접근할 수 없다.
`domain.jar`가 `application.jar`를 의존하지 않기 때문이다.

또 다른 application이 같은 domain entity를 재사용해야 한다면 `domain.jar`에 대한 의존성만 선언하면 된다.

```text
another-application.jar
  └─ depends on domain.jar
```

물론 이 구조는 모든 프로젝트에 필요한 것은 아니다.
분리 수준이 높아질수록 의존성 제어는 강해지지만, module 간 mapping과 build script 유지보수 비용도 늘어난다.

### 4.6. 빌드 모듈 분리의 장점

빌드 module로 아키텍처 경계를 나누면 package만으로 나누는 방식보다 강한 장점이 있다.

1. 순환 의존성을 빌드 도구가 막아준다.

   Gradle이나 Maven module은 순환 의존성을 허용하지 않는다.
   반면 Java compiler는 같은 module 안의 package 순환 의존성을 문제 삼지 않는다.

   ```text
   application.jar ─────▶ adapter.jar
          ▲                  │
          └──────────────────┘   // build tool이 막음
   ```

2. 특정 module만 격리해서 변경하고 테스트할 수 있다.

   같은 build module 안에 application과 adapter가 모두 있으면,
   adapter에 compile error가 있어도 IDE가 전체 module compile을 요구할 수 있다.
   그러면 application 계층 테스트도 실행하지 못할 수 있다.

   분리된 module이라면 application module만 compile하고 test할 수 있다.

   ```text
   ./gradlew :application:test
   ```

   이때 `web-adapter`나 `persistence-adapter`의 compile error는 application module 테스트 실행을 막지 않는다.

3. 새 의존성 추가가 의식적인 행동이 된다.

   어떤 class에 접근하려면 build script에 module dependency를 추가해야 한다.

   ```kotlin
   dependencies {
       implementation(project(":persistence-adapter"))
   }
   ```

   이 줄을 추가하는 순간 "정말 application이 persistence adapter에 의존해도 되는가?"를 다시 생각하게 된다.
   즉 build script가 아키텍처 의존성의 문서이자 방어선이 된다.

단점도 있다.
module이 늘어나면 build script 유지보수 비용이 생긴다.
따라서 처음부터 과도하게 나누기보다, 아키텍처가 어느 정도 안정된 뒤 분리하는 편이 낫다.

---

## 5. 유지보수 가능한 소프트웨어를 만드는 데 어떻게 도움이 될까

소프트웨어 아키텍처는 결국 요소 간 의존성을 관리하는 일이다.

새 코드를 추가하거나 리팩터링할 때는 package 구조를 계속 의식해야 한다.
가능하면 package-private 가시성을 사용해 의존성이 꼬이는 것을 줄인다.

package-private만으로 경계를 지키기 어렵다면 ArchUnit 같은 컴파일 후 체크 도구를 사용한다.
이 방식은 public class가 많아져도 의존성 방향 위반을 자동화된 테스트로 잡을 수 있게 해준다.

아키텍처가 충분히 안정적이라고 느껴지면 아키텍처 요소를 독립적인 build module로 추출한다.
build module은 compile 단계에서 의존성을 더 분명하게 제어할 수 있다.

```text
1단계: package-private으로 작은 경계 보호
2단계: ArchUnit으로 의존성 규칙 자동 검사
3단계: 안정된 경계를 build module로 분리
```

세 방법은 서로 대체 관계가 아니다.
프로젝트 크기와 안정성에 따라 함께 사용할 수 있다.

---

## 6. 참고

- [도서] 만들면서 배우는 클린 아키텍처 - 톰 홈버그(Tom Hombergs)
- [라이브러리] ArchUnit
