---
title: "5. Spring Boot 멀티 모듈 구성"
weight: 5
date: 2026-05-23
---

> Spring Boot 애플리케이션을 Gradle 멀티 모듈로 나누는 목적은 단순히 폴더를 쪼개는 것이 아니라,
> 모듈 간 의존성을 명시해서 아키텍처 경계를 지키기 위함이다.

---

## 1. Module 이란

Gradle 멀티 모듈에서 module은 독립된 코드베이스와 빌드 파일을 가진 단위다.

| 특징 | 설명 |
|---|---|
| 코드 분리 | 다른 모듈과 소스 디렉토리를 분리 |
| 산출물 분리 | 빌드 시 별도 JAR로 패키징 가능 |
| 의존성 명시 | 다른 모듈 또는 외부 라이브러리에 대한 의존성을 직접 선언 |

전체 애플리케이션은 하나의 parent build 안에서 빌드되지만,
각 모듈은 자기 책임과 필요한 의존성을 따로 가진다.

---

## 2. 왜 멀티 모듈이 필요한가

단일 모듈에서는 package로 계층을 나눌 수는 있지만, package만으로는 의존성 방향을 강하게 막기 어렵다.

예를 들어 `web`, `application`, `persistence` 패키지가 한 모듈 안에 있으면
web 계층에서 persistence 구현체를 직접 참조하거나, application 계층이 Spring Data JPA에 의존해도 빌드 레벨에서는 막기 어렵다.

멀티 모듈로 나누면 의존성은 `build.gradle`에 명시적으로 드러난다.

```text
의존성을 추가하지 않으면 컴파일 자체가 안 됨
```

따라서 아키텍처 경계를 "규칙"이 아니라 "빌드 구조"로 강제할 수 있다.

---

## 3. 예시 구조

원문 예시는 결제 애플리케이션 BuckPal을 Hexagonal Architecture 스타일로 나눈다.

```text
root
├── common
│   └── build.gradle
├── buckpal-application
│   └── build.gradle
├── adapters
│   ├── buckpal-web
│   │   └── build.gradle
│   └── buckpal-persistence
│       └── build.gradle
├── buckpal-configuration
│   └── build.gradle
├── build.gradle
└── settings.gradle
```

| 모듈 | 책임 |
|---|---|
| `common` | 여러 모듈에서 공통으로 쓰는 클래스 |
| `buckpal-application` | 유스케이스, 애플리케이션 서비스, 도메인 모델 |
| `adapters/buckpal-web` | HTTP API 등 inbound adapter |
| `adapters/buckpal-persistence` | DB 접근 등 outbound adapter |
| `buckpal-configuration` | Spring Boot 실행 클래스와 Spring 설정 조립 |

핵심은 실제 실행 애플리케이션을 `configuration` 모듈에 두고,
나머지 모듈은 각자의 역할만 제공하도록 나누는 것이다.

---

## 4. settings.gradle

parent build가 어떤 submodule을 포함하는지 `settings.gradle`에 선언한다.

```groovy
include 'common'
include 'buckpal-application'
include 'adapters:buckpal-web'
include 'adapters:buckpal-persistence'
include 'buckpal-configuration'
```

이후 root에서 아래 명령을 실행하면 Gradle이 모듈 간 의존성을 보고 올바른 순서로 빌드한다.

```bash
./gradlew build
```

`settings.gradle`에 적은 순서가 곧 빌드 순서는 아니다.
Gradle은 `dependencies`에 선언된 project dependency를 보고 필요한 모듈을 먼저 빌드한다.

---

## 5. root build.gradle

root `build.gradle`에는 모든 submodule에 공통으로 적용할 설정을 둔다.

```groovy
plugins {
  id "io.spring.dependency-management" version "1.0.8.RELEASE"
}

subprojects {
  group = 'io.reflectoring.reviewapp'
  version = '0.0.1-SNAPSHOT'

  apply plugin: 'java'
  apply plugin: 'java-library'
  apply plugin: 'io.spring.dependency-management'

  repositories {
    mavenCentral()
  }

  dependencyManagement {
    imports {
      mavenBom("org.springframework.boot:spring-boot-dependencies:2.1.7.RELEASE")
    }
  }
}
```

중요한 점은 두 가지다.

1. Spring Boot BOM을 parent에서 관리해서 각 모듈이 dependency version을 반복 선언하지 않게 한다.
2. `java-library` plugin을 적용해서 `api`와 `implementation` 의존성 스코프를 구분할 수 있게 한다.

---

## 6. module build.gradle

각 모듈은 자신에게 필요한 의존성만 선언한다.

예를 들어 persistence adapter는 application 모듈의 port interface를 구현해야 하므로 application 모듈에 의존한다.

```groovy
dependencies {
  implementation project(':common')
  implementation project(':buckpal-application')
  implementation 'org.springframework.boot:spring-boot-starter-data-jpa'
}
```

web adapter도 application 모듈의 use case를 호출해야 하므로 application 모듈에 의존한다.

```groovy
dependencies {
  implementation project(':common')
  implementation project(':buckpal-application')
  implementation 'org.springframework.boot:spring-boot-starter-web'
}
```

이 구조에서는 web module과 persistence module이 서로를 모른다.
web에서 persistence 구현체를 직접 쓰려면 `build.gradle`에 의존성을 추가해야 하므로,
잘못된 의존성 추가가 코드 리뷰에서 드러난다.

---

## 7. Spring Boot 실행 모듈

Spring Boot plugin과 `@SpringBootApplication` 클래스는 모든 모듈에 둘 필요가 없다.
실행 애플리케이션 역할을 하는 configuration 모듈에만 둔다.

```groovy
plugins {
  id "org.springframework.boot" version "2.1.7.RELEASE"
}

dependencies {
  implementation project(':common')
  implementation project(':buckpal-application')
  implementation project(':adapters:buckpal-persistence')
  implementation project(':adapters:buckpal-web')
  implementation 'org.springframework.boot:spring-boot-starter'
}
```

```java
@SpringBootApplication
public class BuckPalApplication {

    public static void main(String[] args) {
        SpringApplication.run(BuckPalApplication.class, args);
    }
}
```

실행은 configuration 모듈 기준으로 수행한다.

```bash
./gradlew :buckpal-configuration:bootRun
```

---

## 8. 의존성 방향

Hexagonal Architecture 관점에서 의존성 방향은 다음처럼 잡는다.

```text
web adapter ───────┐
                   ▼
             application
                   ▲
persistence adapter┘

configuration → 모든 모듈 조립
```

| 방향 | 의미 |
|---|---|
| adapter → application | adapter는 application port/use case를 호출하거나 구현 |
| application → adapter | 금지. application core가 외부 기술에 끌려가면 안 됨 |
| web → persistence | 금지. inbound adapter가 outbound adapter를 직접 알면 계층이 섞임 |
| configuration → all | 실행 시점에 Spring Bean을 조립하는 역할 |

멀티 모듈의 장점은 이 방향을 Gradle 의존성으로 표현할 수 있다는 점이다.

---

## 9. 정리

Gradle 멀티 모듈은 큰 프로젝트를 보기 좋게 나누는 기능이기도 하지만,
더 중요한 용도는 아키텍처 경계를 빌드 레벨에서 강제하는 것이다.

| 단일 모듈 | 멀티 모듈 |
|---|---|
| package 경계에 의존 | Gradle dependency로 경계 강제 |
| 잘못된 참조가 쉽게 섞임 | 의존성 추가 없이는 컴파일 불가 |
| 라이브러리 의존성이 전체에 퍼지기 쉬움 | 모듈별 필요한 라이브러리만 선언 |
| 구조가 커질수록 Big Ball of Mud 위험 | 모듈 간 책임과 방향이 명시됨 |

Spring Boot 애플리케이션에서는 모든 모듈을 Boot 애플리케이션으로 만들기보다,
실행/조립 모듈 하나와 역할별 library module 여러 개로 나누는 방식이 깔끔하다.

---

## 참고

- [Building a Multi-Module Spring Boot Application with Gradle](https://reflectoring.io/spring-boot-gradle-multi-module/)
