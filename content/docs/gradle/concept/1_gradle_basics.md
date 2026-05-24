---
title: "1. Gradle 기초 개념"
weight: 1
date: 2026-05-10
---

> Gradle은 JVM 기반 프로젝트의 빌드 자동화 도구다.  
> 의존성 다운로드 → 컴파일 → 테스트 → 패키징 → 배포까지 일련의 과정을 자동화한다.

---

## 1. Gradle 이란?

Gradle은 빌드 자동화 도구다.
소스 코드를 컴파일하고, 테스트를 실행하고, JAR/WAR 같은 산출물을 만들고,
필요하면 Nexus 같은 저장소에 배포하는 작업을 자동화한다.

```text
source code
  → dependency download
  → compile
  → test
  → package(jar/war)
  → publish/deploy
```

Java/Kotlin/Spring 프로젝트에서는 Maven과 함께 가장 많이 쓰이는 빌드 도구다.
최근 JVM 프로젝트에서는 멀티 모듈, Kotlin DSL, build cache, task graph 최적화 때문에 Gradle을 쓰는 경우가 많다.

### 1.1. Maven 과의 차이

Maven과 Gradle은 둘 다 의존성 관리와 빌드 자동화를 한다.
차이는 빌드를 표현하는 방식과 확장성에 있다.

| 구분 | Maven | Gradle |
|---|---|---|
| 빌드 파일 | `pom.xml` | `build.gradle`, `build.gradle.kts` |
| 표현 방식 | XML 기반 선언형 | Groovy/Kotlin DSL 기반 |
| 빌드 모델 | 정해진 lifecycle 중심 | task graph 중심 |
| 커스터마이징 | plugin 설정 위주 | 코드처럼 task/plugin 확장 가능 |
| 멀티 모듈 | 안정적이지만 XML이 길어지기 쉬움 | 공통 설정과 모듈별 설정 분리가 유연 |
| 성능 | 단순하고 예측 가능 | incremental build, build cache, daemon 활용 |

Maven은 정해진 규칙을 따를 때 단순하고 안정적이다.
Gradle은 빌드 로직이 복잡해지거나 멀티 모듈 공통 설정이 많아질수록 유리하다.

예를 들어 Maven은 `compile`, `test`, `package`, `install`, `deploy` 같은 lifecycle phase가 중심이다.
Gradle은 `compileJava`, `test`, `jar`, `bootJar`, `publish` 같은 task들이 그래프를 이루고,
필요한 task만 순서대로 실행된다.

```text
Maven: phase 순서 실행
validate → compile → test → package → verify → install → deploy

Gradle: task dependency graph 실행
build → test → compileJava
      → jar
```

### 1.2. Gradle Wrapper 가 필요한 이유

Gradle은 로컬에 직접 설치해서 `gradle build`로 실행할 수도 있다.
하지만 현업 프로젝트에서는 보통 `gradle` 명령어보다 `./gradlew`를 쓴다.

이유는 빌드 도구 버전까지 프로젝트가 고정해야 하기 때문이다.

```text
개발자 A: Gradle 8.7
개발자 B: Gradle 8.11
GitLab CI: Gradle 미설치
```

이 상태에서 각자 로컬에 설치된 Gradle을 쓰면 버전 차이 때문에 빌드 결과가 달라지거나,
CI에서 아예 `gradle: command not found`가 날 수 있다.

Gradle Wrapper는 프로젝트 안에 포함된 wrapper 파일을 통해 지정된 Gradle 버전을 자동으로 내려받아 실행한다.

```text
./gradlew build
  → gradle/wrapper/gradle-wrapper.properties 확인
  → 지정된 Gradle version 다운로드
  → 그 Gradle version으로 build 실행
```

그래서 로컬과 CI 모두 같은 명령을 사용한다.

```bash
./gradlew build
./gradlew test
./gradlew bootJar
```

핵심은 "Gradle을 설치하지 않아도 된다"보다 "프로젝트가 요구하는 Gradle 버전을 항상 재현한다"에 있다.

---

## 2. 핵심 구성 요소

```
my-project/
├── settings.gradle.kts     ← 빌드 전체의 구조 정의
├── build.gradle.kts        ← 루트 빌드 스크립트
├── gradle.properties       ← Gradle / 프로젝트 공통 속성
├── gradle/
│   ├── libs.versions.toml  ← 버전 카탈로그 (의존성 버전 관리)
│   └── wrapper/
│       ├── gradle-wrapper.jar        ← Wrapper 실행에 필요한 JAR. Git에 포함
│       └── gradle-wrapper.properties ← 사용할 Gradle 버전/배포 URL
├── gradlew                 ← Gradle Wrapper 실행 스크립트 (Unix)
├── gradlew.bat             ← Gradle Wrapper 실행 스크립트 (Windows)
├── src/                    ← 단일 모듈이면 애플리케이션 소스
│   ├── main/
│   └── test/
└── build/                  ← 빌드 결과물. Git에 올리지 않음
    ├── classes/
    ├── reports/
    └── libs/
        └── my-project.jar  ← jar/war 산출물. CI에서 매번 생성
```

| 구성 요소 | 역할 | Git 포함 여부 |
|---|---|---|
| `settings.gradle.kts` | root project 이름, submodule 목록, plugin/dependency repository 설정 | 포함 |
| `build.gradle.kts` | plugin, dependency, task 등 빌드 로직 정의 | 포함 |
| `gradle.properties` | JVM 옵션, Gradle 옵션, 프로젝트 공통 property 정의 | 포함 |
| `gradle/libs.versions.toml` | dependency/plugin version 중앙 관리 | 포함 |
| `gradle/wrapper/gradle-wrapper.properties` | Gradle Wrapper가 내려받을 Gradle 버전과 URL 정의 | 포함 |
| `gradle/wrapper/gradle-wrapper.jar` | `./gradlew`가 실제 Gradle 배포본을 내려받고 실행하게 해주는 bootstrap JAR | **포함** |
| `gradlew`, `gradlew.bat` | Gradle Wrapper를 시작하는 OS별 실행 스크립트. 직접 Gradle을 구현하지 않고 `gradle-wrapper.jar`를 Java로 실행 | 포함 |
| `src/main` | 운영 코드와 리소스 | 포함 |
| `src/test` | 테스트 코드와 테스트 리소스 | 포함 |
| `build/` | compile/test/package 결과물 | 제외 |
| `build/libs/*.jar`, `build/libs/*.war` | 애플리케이션 패키징 산출물 | 제외 |

### 2.1. `settings.gradle.kts`

Gradle 빌드에서 가장 먼저 읽히는 파일이다.
무엇을 빌드할지, 어떤 저장소에서 플러그인/의존성을 받을지 같은 "빌드의 외형"을 정한다.

단일 모듈에서는 보통 root project 이름만 있어도 된다.

```kotlin
rootProject.name = "my-project"
```

멀티 모듈에서는 어떤 subproject가 빌드에 참여하는지 선언한다.

```kotlin
rootProject.name = "payment-platform"

include("common")
include("payment-application")
include("adapters:payment-web")
include("adapters:payment-persistence")
```

`settings.gradle.kts`에 포함되지 않은 디렉토리는 `build.gradle.kts`가 있어도 Gradle 빌드 대상이 아니다.

### 2.2. `build.gradle.kts`

빌드 로직을 정의하는 파일이다.
무엇을 빌드할지는 `settings.gradle.kts`가 정하고, 어떻게 빌드할지는 `build.gradle.kts`가 정한다.

```kotlin
plugins {
    java
    id("org.springframework.boot") version "3.5.14"
}

repositories {
    mavenCentral()
}

dependencies {
    implementation("org.springframework.boot:spring-boot-starter-web")
    testImplementation("org.springframework.boot:spring-boot-starter-test")
}

tasks.withType<Test> {
    useJUnitPlatform()
}
```

멀티 모듈 프로젝트에서는 root `build.gradle.kts`에 공통 설정을 두고,
각 submodule의 `build.gradle.kts`에는 그 모듈에 필요한 의존성만 둔다.

### 2.3. `gradle.properties`

Gradle 실행 옵션이나 프로젝트 공통 property를 선언한다.

```properties
org.gradle.jvmargs=-Xmx2g -Dfile.encoding=UTF-8
org.gradle.parallel=true
org.gradle.caching=true
```

민감 정보는 여기에 넣지 않는다.
토큰, 패스워드, 배포 키는 CI variable이나 로컬 `~/.gradle/gradle.properties`로 분리한다.

### 2.4. `gradle/libs.versions.toml`

Version Catalog 파일이다.
의존성 버전과 플러그인 버전을 한 곳에서 관리한다.

```toml
[versions]
spring-boot = "3.5.14"

[plugins]
spring-boot = { id = "org.springframework.boot", version.ref = "spring-boot" }

[libraries]
spring-boot-web = { module = "org.springframework.boot:spring-boot-starter-web" }
```

`build.gradle.kts`에서는 `libs.`로 타입세이프하게 참조한다.

```kotlin
plugins {
    alias(libs.plugins.spring.boot)
}

dependencies {
    implementation(libs.spring.boot.web)
}
```

### 2.5. Gradle Wrapper 파일들

Gradle Wrapper는 팀원과 CI가 같은 Gradle 버전으로 빌드하게 해주는 장치다.

```text
gradlew
gradlew.bat
gradle/wrapper/gradle-wrapper.jar
gradle/wrapper/gradle-wrapper.properties
```

이 네 가지는 일반적으로 모두 Git에 포함한다.

`gradlew`는 일반 셸 스크립트가 맞다.
Unix/macOS/Linux에서는 `gradlew`, Windows에서는 `gradlew.bat`를 실행한다.

다만 `gradlew` 자체가 Gradle 빌드 엔진은 아니다.
이 스크립트의 역할은 Java 명령으로 `gradle-wrapper.jar`를 실행하는 것이다.

```text
./gradlew build
  → gradlew shell script 실행
  → java -classpath gradle/wrapper/gradle-wrapper.jar org.gradle.wrapper.GradleWrapperMain build
  → wrapper가 지정된 Gradle 배포본을 준비
  → 실제 Gradle이 build task 실행
```

그래서 `gradlew`만 있고 `gradle-wrapper.jar`가 없으면 wrapper main class를 실행할 수 없다.
반대로 `gradle-wrapper.jar`만 있고 `gradlew`에 실행 권한이 없으면 Unix 계열에서 `./gradlew`로 실행할 수 없다.

특히 `gradle-wrapper.jar`는 이름 때문에 헷갈리지만 애플리케이션 산출물이 아니다.
`./gradlew` 스크립트가 Gradle을 부팅하기 위해 사용하는 wrapper bootstrap JAR다.

```text
./gradlew
  → gradle/wrapper/gradle-wrapper.jar 실행
  → gradle-wrapper.properties의 distributionUrl 확인
  → 지정된 Gradle 배포본 다운로드
  → 해당 Gradle 버전으로 build/test 실행
```

따라서 `gradle-wrapper.jar`를 Git에 올리지 않으면 로컬에 Gradle이 설치되어 있는 개발자 PC에서는 우연히 빌드가 되는 것처럼 보여도,
GitLab CI 같은 깨끗한 환경에서는 `./gradlew` 실행 단계에서 실패할 수 있다.

### 2.6. `build/`와 `build/libs/*.jar`, `*.war`

`build/` 디렉토리는 Gradle이 만든 결과물이다.

```text
build/classes       컴파일된 .class
build/resources     처리된 리소스
build/test-results  테스트 결과
build/reports       테스트/커버리지 리포트
build/libs          jar/war 산출물
```

Spring Boot 애플리케이션이라면 보통 `bootJar` 또는 `bootWar`로 실행 가능한 산출물이 만들어진다.

```bash
./gradlew bootJar
./gradlew bootWar
```

하지만 이 산출물은 Git에 올리지 않는다.
CI/CD pipeline에서 source를 checkout한 뒤 매번 새로 빌드해야 한다.

```text
Git에 포함: gradle/wrapper/gradle-wrapper.jar
Git에 제외: build/libs/my-app.jar, build/libs/my-app.war
```

정리하면, "Gradle 관련 JAR" 중 Git에 포함해야 하는 것은 Wrapper JAR이고,
애플리케이션 JAR/WAR는 빌드 결과물이므로 포함하지 않는다.

---

## 3. 주요 블록

`build.gradle.kts`는 대략 아래 순서로 읽으면 된다.

```kotlin
plugins {
    // 이 project에 어떤 빌드 기능을 붙일지 선언
}

group = "com.example"
version = "0.0.1-SNAPSHOT"

java {
    // Java plugin이 제공하는 설정 블록
}

repositories {
    // 외부 dependency를 받을 저장소
}

dependencies {
    // 이 project가 필요로 하는 library/module
}

tasks.withType<Test> {
    // task 상세 설정
}

subprojects {
    // 멀티모듈에서 하위 project에 공통 적용할 설정
}
```

큰 흐름은 다음과 같다.

```text
plugin 적용
  → plugin이 task/extension/configuration을 추가
  → repositories에서 dependency 저장소 지정
  → dependencies에서 필요한 library 선언
  → java/tasks 같은 블록으로 세부 빌드 동작 조정
```

### 3.1. `plugins {}`

빌드에 사용할 플러그인을 선언한다.  
Gradle plugin은 특정 종류의 프로젝트를 빌드하기 위한 기능 묶음이다.

plugin을 적용하면 현재 project에 다음 것들이 추가된다.

| 추가되는 것 | 설명 |
|---|---|
| task | `compileJava`, `test`, `jar`, `bootJar`, `publish` 같은 실행 단위 |
| extension | `java {}`, `springBoot {}`, `publishing {}` 같은 설정 블록 |
| configuration | `implementation`, `api`, `runtimeOnly`, `testImplementation` 같은 의존성 scope |
| convention | 기본 소스 디렉토리, 산출물 이름, lifecycle task 연결 등 |

즉 plugin은 "이 project를 어떤 방식으로 빌드할지"를 Gradle에 알려주는 확장 모듈이다.

```kotlin
plugins {
    java                              // Java 컴파일, 테스트, jar 태스크 추가
    id("org.springframework.boot")    // bootRun, bootJar 태스크 추가
    id("io.spring.dependency-management") // Spring BOM 임포트 기능 추가
    `maven-publish`                   // Nexus 배포 태스크 추가
}
```

예를 들어 `java` plugin을 적용하면 Gradle은 이 project를 Java 프로젝트로 보고
`src/main/java`, `src/test/java` 구조를 기본으로 사용한다.
그리고 `compileJava`, `test`, `jar`, `build` 같은 task를 추가한다.

Spring Boot plugin을 적용하면 일반 `jar` 대신 실행 가능한 fat jar를 만드는 `bootJar`,
로컬 실행용 `bootRun` 같은 task가 추가된다.

그래서 root project가 실제 코드를 담지 않고 submodule만 묶는 aggregator라면,
root에 Spring Boot plugin을 적용할 필요가 없다.
root는 실행 가능한 애플리케이션이 아니므로 `bootJar`, `bootRun`이 생겨도 의미가 없고,
오히려 root project까지 Boot 애플리케이션처럼 취급되어 빌드 구조가 헷갈릴 수 있다.

이럴 때 `apply false`를 쓴다.
plugin version은 root에서 관리하지만, 실제 기능은 필요한 submodule에만 적용한다.

```kotlin
// 루트: 버전 고정만
id("org.springframework.boot") version "3.5.14" apply false

// 서브모듈: 버전 없이 적용
apply(plugin = "org.springframework.boot")
```

---

### 3.2. `repositories {}`

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

`dependencies {}`에 라이브러리를 적어도,
`repositories {}`에 해당 라이브러리를 받을 저장소가 없으면 다운로드할 수 없다.

---

### 3.3. `dependencies {}`

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

### 3.4. `java {}`

Java 컴파일 설정. Java 툴체인을 쓰면 팀 전체가 동일한 JDK 버전을 자동으로 사용한다.

```kotlin
java {
    toolchain {
        languageVersion = JavaLanguageVersion.of(21)
    }
}
```

---

### 3.5. `tasks {}` / `tasks.withType<T> {}`

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

`tasks.withType<Test>`처럼 타입으로 잡으면 모든 `Test` task에 공통 설정을 적용한다.
`tasks.named<Jar>("jar")`처럼 이름으로 잡으면 특정 task 하나만 설정한다.

---

### 3.6. `subprojects {}` / `allprojects {}` / `project(":name") {}`

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
```

`subprojects {}` 없이 같은 설정을 하려면 각 모듈 `build.gradle.kts`마다 툴체인, 저장소, BOM을 전부 반복해야 한다.

```kotlin
// 특정 모듈만 별도 설정
project(":order-service") {
    tasks.withType<Test> {
        jvmArgs("-Xmx512m")
    }
}
```

---

## 4. 자주 혼동하는 포인트

### 4.1. `settings.gradle.kts`와 `build.gradle.kts`

두 파일은 역할이 다르다.

| 파일 | 역할 |
|---|---|
| `settings.gradle.kts` | 빌드 대상 구조 정의. root project 이름, submodule 목록, plugin/dependency repository 설정 |
| `build.gradle.kts` | 빌드 로직 정의. plugin, dependency, task, compile/test/package 설정 |

`settings.gradle.kts`는 "무엇을 빌드할지"를 정하고,
`build.gradle.kts`는 "어떻게 빌드할지"를 정한다.

```text
settings.gradle.kts에 include 안 된 모듈
  → build.gradle.kts가 있어도 Gradle 빌드 대상 아님
```

### 4.2. `apply false`

Gradle의 `plugins {}` 블록은 기본적으로 plugin을 **resolve**하고 즉시 현재 project에 **apply**한다.

| 단계 | 의미 |
|---|---|
| resolve | plugin id와 version을 보고 plugin artifact를 찾아 build classpath에 올림 |
| apply | 그 plugin이 현재 project에 task, extension, configuration을 추가함 |

`apply false`는 첫 번째 단계까지만 하고 두 번째 단계는 하지 말라는 뜻이다.

```text
apply false
  → plugin version/artifact는 이 build에서 알게 함
  → 하지만 현재 project에는 plugin 기능을 붙이지 않음
```

예를 들어 root project가 실제 Spring Boot 애플리케이션이 아니라 여러 submodule을 묶는 aggregator 역할만 한다면,
root에 Spring Boot plugin을 적용할 이유가 없다.

```kotlin
// root build.gradle.kts
plugins {
    id("org.springframework.boot") version "3.5.14" apply false
}
```

위 설정은 Spring Boot plugin version을 root build에서 선언하지만,
root project에는 `bootJar`, `bootRun` 같은 Spring Boot task를 만들지 않는다.

실제 애플리케이션 submodule에서만 plugin을 적용한다.

```kotlin
// app/build.gradle.kts
plugins {
    id("org.springframework.boot")
}
```

이때 submodule에서 version을 다시 쓰지 않아도 되는 이유는,
같은 build 안에서 root가 이미 해당 plugin id의 version을 plugin request로 선언했기 때문이다.

`libs.versions.toml`과의 관계는 다음처럼 보면 된다.

| 위치 | 역할 |
|---|---|
| `libs.versions.toml` | plugin id/version에 이름을 붙이는 catalog |
| root `plugins { alias(...) apply false }` | catalog에 있는 plugin을 이 build의 plugin request로 선언하되 root에는 적용하지 않음 |
| submodule `plugins { alias(...) }` 또는 `id("...")` | 실제로 그 project에 plugin 적용 |

즉 `libs.versions.toml`은 "버전 적어둔 파일"이고,
`apply false`는 "이 plugin을 root에는 붙이지 말고 하위 모듈에서 골라 쓰게 하자"는 빌드 구조 표현이다.

Version Catalog를 쓰면 보통 이렇게 쓴다.

```kotlin
// root build.gradle.kts
plugins {
    alias(libs.plugins.spring.boot) apply false
}
```

```kotlin
// app/build.gradle.kts
plugins {
    alias(libs.plugins.spring.boot)
}
```

이 경우에도 `apply false`의 의미는 같다.
root project에는 Spring Boot plugin을 적용하지 않고,
실제 Boot 애플리케이션 모듈에만 적용한다.

### 4.3. `java`와 `java-library`

둘 다 Java 프로젝트용 plugin이지만 목적이 다르다.

| 플러그인 | 용도 | 특징 |
|---|---|---|
| `java` | 일반 Java 애플리케이션 | `implementation`, `compileOnly`, `runtimeOnly` 등 기본 scope 사용 |
| `java-library` | 다른 모듈이 소비하는 라이브러리 | `api` scope 사용 가능 |

`api` scope는 라이브러리의 public API에 드러나는 타입을 소비자 모듈의 compile classpath에도 노출한다.
반면 `implementation`은 해당 모듈 내부 구현 의존성으로 숨긴다.

```kotlin
dependencies {
    api("org.springframework.kafka:spring-kafka")             // 소비자에게 노출
    implementation("com.fasterxml.jackson.core:jackson-databind") // 내부 구현
}
```

다른 모듈이 가져다 쓰는 공통 라이브러리라면 `java-library`를 우선 검토한다.

### 4.4. `gradle-wrapper.jar`와 애플리케이션 JAR/WAR

둘 다 `.jar`라는 확장자를 가질 수 있지만 성격이 완전히 다르다.

| 파일 | 성격 | Git 포함 여부 |
|---|---|---|
| `gradle/wrapper/gradle-wrapper.jar` | Gradle Wrapper 실행용 bootstrap JAR | 포함 |
| `build/libs/*.jar` | 애플리케이션 빌드 산출물 | 제외 |
| `build/libs/*.war` | 웹 애플리케이션 빌드 산출물 | 제외 |

`gradle-wrapper.jar`가 없으면 `./gradlew` 실행 자체가 실패할 수 있다.
반대로 `build/libs/*.jar`, `build/libs/*.war`는 CI에서 매번 새로 만들어야 하므로 Git에 올리지 않는다.

---

## 5. 빌드 평가 순서

```
1. settings.gradle.kts    ← 프로젝트 구조 확정 (include, 저장소 등)
2. build.gradle.kts (루트) ← 루트 + subprojects 블록 실행
3. build.gradle.kts (각 서브모듈) ← 모듈별 설정 적용
```

---

## 6. 참고

- [Gradle 공식 — Build Script Basics](https://docs.gradle.org/current/userguide/writing_build_scripts.html)
- [Gradle 공식 — Dependency Configurations](https://docs.gradle.org/current/userguide/declaring_dependencies.html)
- [Gradle 공식 — Java Toolchains](https://docs.gradle.org/current/userguide/toolchains.html)
