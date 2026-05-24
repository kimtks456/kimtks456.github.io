---
title: "1. 계층형 아키텍처의 문제점"
weight: 1
date: 2026-05-23
---

## 1. 계층형 아키텍처의 문제점

전통적인 계층형 아키텍처는 보통 아래처럼 나눈다.

```text
Web Layer
  → Domain / Service Layer
    → Persistence Layer
      → Database
```

겉으로 보면 역할이 깔끔하게 나뉜 것처럼 보인다.
하지만 실제 프로젝트에서는 이 구조가 시간이 지날수록 DB 중심 설계, 넓은 서비스, 테스트 어려움, 동시 작업 충돌로 흐르기 쉽다.

핵심 문제는 계층형 아키텍처가 "아래 계층에만 의존한다"는 규칙 외에는 강한 제약을 거의 주지 않는다는 점이다.

---

### 1.1. DB 주도 설계를 유도한다

계층형 아키텍처는 자연스럽게 영속성 계층을 먼저 생각하게 만든다.

```text
테이블 설계
  → JPA Entity 설계
  → Repository 설계
  → Service 설계
  → Controller 설계
```

이 순서가 항상 틀린 것은 아니다.
하지만 비즈니스 규칙보다 DB 구조를 먼저 고정하면 도메인 모델이 데이터베이스 테이블의 그림자가 되기 쉽다.

그 결과 도메인 모델은 "비즈니스 개념을 표현하는 객체"라기보다 "ORM이 저장하기 쉬운 객체"가 된다.

```java
@Entity
class AccountJpaEntity {
    @Id
    private Long id;

    private BigDecimal balance;

    @OneToMany(fetch = FetchType.LAZY)
    private List<ActivityJpaEntity> activities;
}
```

이런 영속성 모델을 그대로 비즈니스 로직에서 사용하면,
도메인 코드는 비즈니스 규칙뿐 아니라 JPA의 제약까지 같이 신경 써야 한다.

| 관심사 | 도메인 코드에 섞이는 문제 |
|---|---|
| 지연 로딩 | 컬렉션 접근 시점에 DB query 발생 여부를 의식 |
| 트랜잭션 | 영속성 컨텍스트가 열려 있는지 의식 |
| 변경 감지 | 객체 필드 변경이 DB update로 이어지는 시점 의식 |
| flush | 언제 SQL이 나가는지 의식 |
| cascade | 객체 그래프 변경이 어디까지 전파되는지 의식 |

도메인 로직이 이런 영속성 관심사를 알아야 한다면,
도메인 계층과 영속성 계층은 이미 강하게 결합된 상태다.

---

### 1.2. 영속성 모델을 비즈니스 모델처럼 쓰게 된다

ORM을 쓰면 DB row를 객체처럼 다룰 수 있다.
문제는 이 편리함 때문에 JPA Entity를 도메인 모델로 그대로 쓰고 싶어진다는 점이다.

```text
JPA Entity
  = DB 저장 모델
  = API 응답 모델
  = 비즈니스 모델
```

처음에는 빠르다.
하지만 시간이 지나면 하나의 모델이 너무 많은 책임을 가진다.

| 책임 | 한 Entity에 섞일 때 생기는 문제 |
|---|---|
| DB mapping | 테이블 변경이 도메인 코드 변경으로 전파 |
| 비즈니스 규칙 | 순수한 규칙 검증이 영속성 상태에 의존 |
| API 응답 | 외부 노출 형식 때문에 내부 모델 변경이 어려움 |
| validation | 웹 요청 검증과 도메인 불변식이 섞임 |

도메인 모델은 비즈니스 규칙을 표현해야 한다.
영속성 모델은 데이터를 저장하고 복원하기 위한 모델이다.
둘이 항상 같을 필요는 없다.

---

### 1.3. 계층형 아키텍처의 규칙은 너무 약하다

계층형 아키텍처의 기본 규칙은 단순하다.

```text
상위 계층은 같은 계층 또는 하위 계층에 접근할 수 있다.
하위 계층은 상위 계층에 접근하면 안 된다.
```

이 규칙만으로는 아키텍처가 무너지는 것을 막기 어렵다.

예를 들어 어떤 유틸리티가 여러 계층에서 필요하다고 하자.
상위 계층에서 하위 계층만 참조할 수 있으니, 그 유틸리티를 가장 아래쪽 계층으로 내리면 모든 계층에서 사용할 수 있다.

```text
처음 의도:
common utility

실제 흐름:
persistence layer 아래에 utility 추가
  → web/domain/persistence 모두 접근 가능
```

이런 식으로 "접근 가능하게 만들기 위해" 컴포넌트를 아래로 내리기 시작하면,
영속성 계층이나 공통 계층에 온갖 코드가 쌓인다.

계층형 아키텍처는 이런 지름길을 구조적으로 막지 않는다.
막으려면 별도 규칙이 필요하다.

```text
잘못된 의존성
  → 코드 리뷰에서 발견
  → 가능하면 빌드 단계에서 실패
```

규칙이 문서에만 있으면 시간이 지나며 깨진다.
중요한 아키텍처 규칙은 테스트나 빌드로 강제해야 한다.

---

### 1.4. 계층을 건너뛰면 책임이 새기 시작한다

계층형 구조에서는 아래 계층 접근이 허용되므로,
웹 계층이 도메인 서비스를 거치지 않고 영속성 계층을 직접 참조하는 코드가 생길 수 있다.

```text
Controller
  → Repository
  → Entity
```

이런 shortcut은 처음에는 단순해 보인다.
조회 API 하나쯤은 service 없이 repository를 바로 호출해도 괜찮아 보인다.

문제는 이 경로가 열리면 웹 계층에 도메인 로직이 들어가기 시작한다는 점이다.

```java
@RestController
class AccountController {

    @PostMapping("/accounts/{id}/withdraw")
    void withdraw(@PathVariable Long id, @RequestBody WithdrawRequest request) {
        AccountJpaEntity account = accountRepository.findById(id).orElseThrow();

        if (account.getBalance().compareTo(request.amount()) < 0) {
            throw new IllegalArgumentException("잔액 부족");
        }

        account.withdraw(request.amount());
    }
}
```

위 코드는 controller가 단순 입출력 변환을 넘어 유스케이스를 직접 수행한다.
시간이 지나면 controller는 HTTP 처리, request validation, transaction, repository 호출, 도메인 규칙까지 떠안는다.

테스트도 어려워진다.
웹 계층 테스트를 하려는데 repository, entity, transaction까지 같이 준비해야 한다.

```text
Controller 테스트
  → Repository mock 필요
  → Entity 상태 준비 필요
  → 영속성 예외 고려 필요
  → 테스트 작성 비용 증가
  → 테스트를 안 쓰게 됨
```

계층을 건너뛰는 코드는 단기적으로 빠르지만,
유스케이스가 커질수록 책임이 흩어지고 테스트 비용이 커진다.

---

### 1.5. 유스케이스가 숨어버린다

애플리케이션 코드를 읽을 때 가장 알고 싶은 것은 보통 "이 시스템이 어떤 일을 하는가"다.
즉 유스케이스가 보여야 한다.

하지만 계층형 아키텍처에서는 유스케이스가 특정 구조로 드러나지 않는다.

```text
AccountService
  ├── createAccount()
  ├── getAccount()
  ├── withdraw()
  ├── deposit()
  ├── closeAccount()
  ├── exportAccountHistory()
  └── ...
```

계층형 아키텍처는 도메인 서비스의 "너비"를 제한하지 않는다.
그래서 시간이 지나면 하나의 서비스가 여러 유스케이스를 모두 담당하는 넓은 서비스가 되기 쉽다.

넓은 서비스는 많은 repository와 외부 client에 의존한다.
웹 계층의 여러 controller도 이 서비스를 참조한다.

```text
Controller A ─┐
Controller B ─┼→ AccountService → Repository A
Controller C ─┘                 → Repository B
                                  → ExternalClient
```

이 구조의 문제:

| 문제 | 설명 |
|---|---|
| 수정 위치 탐색 어려움 | 새 기능을 어디에 넣어야 할지 애매함 |
| 테스트 어려움 | 서비스 하나를 테스트하려면 많은 의존성을 준비해야 함 |
| 변경 영향 증가 | 한 유스케이스 변경이 같은 서비스의 다른 기능에 영향 |
| merge conflict 증가 | 여러 개발자가 같은 큰 서비스 파일을 동시에 수정 |

유스케이스 단위로 좁은 서비스를 만들면 기능의 위치가 더 명확해진다.

```text
SendMoneyUseCase
WithdrawMoneyUseCase
DepositMoneyUseCase
CloseAccountUseCase
```

이름만 봐도 시스템이 제공하는 기능이 드러난다.
테스트도 해당 유스케이스에 필요한 의존성만 준비하면 된다.

---

### 1.6. 동시 작업이 어려워진다

계층형 아키텍처는 기능을 어느 계층에 구현해야 하는지 강하게 강제하지 않는다.
그래서 같은 유스케이스를 두고도 개발자마다 구현 위치가 달라질 수 있다.

```text
개발자 A: Controller에 로직 추가
개발자 B: Service에 로직 추가
개발자 C: Repository query로 해결
```

또한 DB 주도 설계로 흐르면 개발 순서도 경직된다.

```text
테이블 설계
  → Entity / Repository 구현
  → Service 구현
  → Controller 구현
```

이 순서에서는 영속성 계층이 준비되기 전까지 도메인이나 웹 계층 작업이 막히기 쉽다.

물론 인터페이스를 먼저 정의하면 병렬 작업이 가능하다.
하지만 도메인과 영속성 모델이 강하게 섞여 있으면 인터페이스를 기준으로 독립 개발하기 어렵다.

넓은 서비스도 동시 작업을 방해한다.
여러 유스케이스가 같은 서비스 파일에 모이면 여러 개발자가 같은 파일을 계속 수정하게 되고,
merge conflict 가능성이 높아진다.

---

### 1.7. 문제의 핵심

계층형 아키텍처가 항상 나쁜 것은 아니다.
작은 애플리케이션이나 단순 CRUD에서는 충분히 실용적일 수 있다.

문제는 계층형 아키텍처가 잘못된 방향으로 흐르는 것을 너무 쉽게 허용한다는 점이다.

```text
DB 먼저 설계
  → JPA Entity를 도메인 모델처럼 사용
  → 웹 계층이 repository/entity 직접 참조
  → 유스케이스가 넓은 service 안에 숨음
  → 테스트 어려움
  → 동시 작업 어려움
```

따라서 규모가 커지고 유스케이스가 복잡해질수록,
단순한 계층 구분만으로는 부족하다.

필요한 것은 다음과 같은 더 강한 구조다.

| 필요한 규칙 | 의미 |
|---|---|
| 도메인 중심 | DB 모델이 아니라 유스케이스와 도메인 규칙을 먼저 둠 |
| 의존성 방향 강제 | 도메인이 영속성/웹 기술에 의존하지 않게 함 |
| 유스케이스 명시 | 기능 단위를 코드 구조에서 드러냄 |
| adapter 분리 | 웹, DB, 외부 시스템을 도메인 바깥으로 밀어냄 |
| 빌드/테스트 강제 | 아키텍처 규칙 위반 시 빌드나 테스트에서 실패 |

이 흐름이 Clean Architecture, Hexagonal Architecture가 해결하려는 핵심 문제다.

---

## 2. 참고

- [도서] 만들면서 배우는 클린 아키텍처 - 톰 홈버그(Tom Hombergs)
- https://github.com/wikibook/clean-architecture
