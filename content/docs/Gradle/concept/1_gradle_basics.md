---
title: "1. Gradle 기초 개념"
weight: 1
date: 2026-05-10
---

> Gradle은 JVM 기반 프로젝트의 빌드 자동화 도구다.  
> 의존성 다운로드 → 컴파일 → 테스트 → 패키징 → 배포까지 일련의 과정을 자동화한다.

---

## 1. 핵심 구성 요소

```
kafka-practice/
├── settings.gradle.kts     ← 프로젝트 구조 정의 (무엇을 빌드할지)
├── build.gradle.kts        ← 빌드 로직 정의 (어떻게 빌드할지)
├── gradle/
│   ├── libs.versions.toml  ← 버전 카탈로그 (의존성 버전 관리)
│   └── wrapper/            ← Gradle Wrapper (팀 전체 동일 버전 보장)
├── gradlew                 ← Gradle Wrapper 실행 스크립트 (Unix)
└── gradlew.bat             ← Gradle Wrapper 실행 스크립트 (Windows)
```

---

## 2. 주요 블록

### `plugins {}`

빌드에 사용할 플러그인을 선언한다.  
플러그인은 태스크(`compileJava`, `test`, `jar` 등)와 설정 옵션을 제공한다.

```kotlin
plugins {
    java                              // Java 컴파일, 테스트, jar 태스크 추가
    id("org.springframework.boot")    // bootRun, bootJar 태스크 추가
    id("io.spring.dependency-management") // Spring BOM 임포트 기능 추가
    `maven-publish`                   // Nexus 배포 태스크 추가
}
```

`apply false` — 버전만 선언하고 지금 당장 적용하지 않는다. 루트에서 선언 후 서브모듈에서 버전 없이 적용하는 패턴.

```kotlin
// 루트: 버전 고정만
id("org.springframework.boot") version "3.5.14" apply false

// 서브모듈: 버전 없이 적용
apply(plugin = "org.springframework.boot")
```

---

### `dependencies {}`

프로젝트가 필요한 외부 라이브러리를 선언한다.

```kotlin
dependencies {
    implementation("org.springframework.boot:spring-boot-starter-web")  // 컴파일 + 런타임
    api("org.springframework.kafka:spring-kafka")                       // 소비자에게도 노출
    compileOnly("org.projectlombok:lombok")                             // 컴파일만, jar 미포함
    runtimeOnly("org.postgresql:postgresql")                            // 런타임만
    testImplementation("org.springframework.boot:spring-boot-starter-test")
}
```

| scope | 컴파일 | 런타임 | 소비자 노출 | 주요 용도 |
|-------|--------|--------|------------|-----------|
| `implementation` | ✓ | ✓ | ✗ | 일반 의존성 |
| `api` | ✓ | ✓ | **✓** | 라이브러리가 외부에 타입 노출할 때 |
| `compileOnly` | ✓ | ✗ | ✗ | 어노테이션 프로세서(Lombok 등) |
| `runtimeOnly` | ✗ | ✓ | ✗ | JDBC 드라이버 등 |
| `testImplementation` | 테스트만 | 테스트만 | ✗ | 테스트 전용 |

> `api` vs `implementation`: `java-library` 플러그인을 써야 `api` scope를 사용할 수 있다.

---

### `repositories {}`

의존성을 어디서 다운로드할지 지정한다.

```kotlin
repositories {
    mavenCentral()                      // Maven Central (기본)
    maven {
        url = uri("http://localhost:8081/repository/maven-public/")  // Nexus
        isAllowInsecureProtocol = true
    }
}
```

---

### `subprojects {}` / `allprojects {}` / `project(":name") {}`

멀티모듈 프로젝트에서 여러 모듈에 설정을 일괄 적용할 때 루트 `build.gradle.kts`에 쓴다.

| 블록 | 적용 대상 | 루트 포함 |
|------|----------|-----------|
| `subprojects {}` | `include()`된 모든 서브모듈 | **제외** |
| `allprojects {}` | 루트 + 모든 서브모듈 | **포함** |
| `project(":name") {}` | 지정한 모듈 하나 | — |

```kotlin
// 루트 build.gradle.kts
subprojects {
    apply(plugin = "java")

    java {
        toolchain { languageVersion = JavaLanguageVersion.of(21) }
    }

    repositories { mavenCentral() }
}

// 특정 모듈만 별도 설정
project(":order-service") {
    tasks.withType<Test> {
        jvmArgs("-Xmx512m")
    }
}
```

`subprojects {}` 없이 같은 설정을 하려면 각 모듈 `build.gradle.kts`마다 툴체인, 저장소, BOM을 전부 반복해야 한다.

---

### `tasks {}` / `tasks.withType<T> {}`

Gradle 태스크를 설정하거나 커스텀 태스크를 정의한다.

```kotlin
// 모든 Test 태스크에 JUnit Platform 활성화
tasks.withType<Test> {
    useJUnitPlatform()
}

// 특정 태스크 설정
tasks.named<Jar>("jar") {
    archiveBaseName.set("kafka-common-lib")
}
```

---

### `java {}`

Java 컴파일 설정. Java 툴체인을 쓰면 팀 전체가 동일한 JDK 버전을 자동으로 사용한다.

```kotlin
java {
    toolchain {
        languageVersion = JavaLanguageVersion.of(21)
    }
}
```

---

## 3. Gradle Wrapper (`gradlew`)

`gradle` 명령어를 직접 설치하지 않고 `./gradlew`를 사용하는 이유:

- 프로젝트에 명시된 Gradle 버전(`gradle/wrapper/gradle-wrapper.properties`)을 자동 다운로드
- 팀 전체가 동일한 Gradle 버전 사용 보장
- CI 환경에서도 별도 설치 불필요

```bash
./gradlew build              # 전체 빌드
./gradlew test               # 테스트 실행
./gradlew :order-service:bootRun  # 특정 모듈 실행
./gradlew :kafka-common-lib:publish  # Nexus 배포
./gradlew dependencies       # 의존성 트리 확인
./gradlew tasks              # 사용 가능한 태스크 목록
```

---

## 4. 빌드 평가 순서

```
1. settings.gradle.kts    ← 프로젝트 구조 확정 (include, 저장소 등)
2. build.gradle.kts (루트) ← 루트 + subprojects 블록 실행
3. build.gradle.kts (각 서브모듈) ← 모듈별 설정 적용
```

---

## 참고

- [Gradle 공식 — Build Script Basics](https://docs.gradle.org/current/userguide/writing_build_scripts.html)
- [Gradle 공식 — Dependency Configurations](https://docs.gradle.org/current/userguide/declaring_dependencies.html)
- [Gradle 공식 — Java Toolchains](https://docs.gradle.org/current/userguide/toolchains.html)
