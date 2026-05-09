---
title: "3. Gradle Version Catalog"
weight: 3
date: 2026-05-10
---

> `gradle/libs.versions.toml`에 버전을 선언하고 모든 빌드 스크립트에서 타입세이프하게 참조하는 방식.  
> Gradle 7.4+에서 안정화, Gradle 8.x에서 사실상 표준이 됐다.

---

## 1. 도입 전 — 기존 버전 관리 방식들

### 방법 A: 문자열 하드코딩

```kotlin
dependencies {
    implementation("org.springframework.kafka:spring-kafka:3.2.1")
    implementation("org.springframework.boot:spring-boot-starter-data-redis:3.5.14")
}
```

모듈이 늘어날수록 같은 버전 문자열이 여러 파일에 흩어진다. 업그레이드 시 누락 위험.

### 방법 B: `val` 변수로 추출

```kotlin
val springBootVersion = "3.5.14"

dependencies {
    implementation("org.springframework.boot:spring-boot-starter-web:$springBootVersion")
}
```

단일 파일 내에서는 관리되지만, **`plugins {}` 블록 안에서 변수를 사용할 수 없다**는 Gradle 제약이 있다.

```kotlin
val springBootVersion = "3.5.14"

plugins {
    id("org.springframework.boot") version springBootVersion  // ❌ 컴파일 에러
}
```

### 방법 C: `gradle.properties`에 선언

```properties
# gradle.properties
springBootVersion=3.5.14
```

```kotlin
val springBootVersion: String by project

plugins {
    id("org.springframework.boot") version springBootVersion  // ❌ 여전히 plugins 블록에서 사용 불가
}
```

플러그인 버전은 여전히 하드코딩해야 하는 한계가 있다.

---

## 2. Version Catalog 구조

`gradle/libs.versions.toml` 파일 하나로 버전, 라이브러리, 플러그인, 번들을 통합 관리한다.

```toml
[versions]
spring-boot    = "3.5.14"
dep-management = "1.1.7"
testcontainers = "1.20.4"

[libraries]
spring-boot-bom = { module = "org.springframework.boot:spring-boot-dependencies", version.ref = "spring-boot" }
testcontainers-bom = { module = "org.testcontainers:testcontainers-bom", version.ref = "testcontainers" }

[plugins]
spring-boot    = { id = "org.springframework.boot",        version.ref = "spring-boot" }
dep-management = { id = "io.spring.dependency-management", version.ref = "dep-management" }

[bundles]
observability = ["micrometer-registry", "spring-boot-actuator", "micrometer-core"]
```

`build.gradle.kts`에서 `libs.` 으로 타입세이프하게 참조한다.

```kotlin
plugins {
    alias(libs.plugins.spring.boot) apply false   // ✅ plugins 블록에서도 사용 가능
    alias(libs.plugins.dep.management) apply false
}

dependencies {
    implementation(libs.bundles.observability)    // ✅ 번들 한 줄로 세트 적용
    testImplementation(platform(libs.testcontainers.bom))
}
```

---

## 3. 기존 방식 대비 5가지 장점

### 1) 강력한 IDE 자동완성 (Type-Safe Accessors)

Version Catalog를 정의하면 Gradle이 컴파일 시점에 타입세이프 접근자 클래스를 자동 생성한다.

```kotlin
implementation(libs.  // ← Ctrl+Space → 등록된 라이브러리 목록 전체 표시
```

`val` 방식은 문자열 조합이라 오타를 빌드 실행 후에야 알 수 있다.  
Version Catalog는 오타 시 IDE가 즉시 빨간 줄로 표시한다.

### 2) 함께 쓰는 라이브러리 묶음 처리 (Bundles)

관찰성(Observability) 스택처럼 항상 세트로 쓰는 라이브러리를 번들로 묶을 수 있다.

```toml
[bundles]
observability = ["micrometer-registry", "spring-boot-actuator", "micrometer-core"]
```

```kotlin
// 모듈마다 3줄 → 1줄로
implementation(libs.bundles.observability)
```

### 3) 플러그인과 라이브러리 버전 통합

`val` 방식의 가장 큰 약점은 `plugins {}` 블록에서 변수를 못 쓴다는 것이다.  
결과적으로 플러그인 버전은 하드코딩, 라이브러리 버전은 변수로 관리하는 **이중 관리 구조**가 생긴다.

Version Catalog는 `[plugins]` 섹션이 있어 플러그인과 라이브러리 버전을 동일한 파일에서 관리하고, `alias()`로 `plugins {}` 블록에서도 사용 가능하다.

### 4) 의존성 업데이트 봇 친화적 (Dependabot / Renovate)

`build.gradle.kts` 안에 버전 변수가 섞여 있으면 봇들이 파싱에 실패하는 경우가 있다.  
`libs.versions.toml`은 완전한 표준 포맷이라 Dependabot, Renovate가 정확하게 인식한다.  
새 버전 출시 시 자동으로 버전만 바꾼 PR을 올려준다.

### 5) 전사 표준 TOML 배포 (Nexus Publishing)

Version Catalog는 **TOML 파일 자체를 Nexus 같은 저장소에 배포**할 수 있다.

```toml
# platform-team의 platform-bom.versions.toml
[versions]
spring-boot = "3.5.14"
kafka       = "3.7.0"
```

```kotlin
// 각 도메인 서비스의 settings.gradle.kts
dependencyResolutionManagement {
    versionCatalogs {
        create("libs") {
            from("com.mycompany:platform-catalog:1.0.0")  // Nexus에서 당겨옴
        }
    }
}
```

플랫폼 팀이 전사 라이브러리 버전을 중앙에서 통제하고, 도메인 팀은 버전을 직접 관리할 필요가 없어진다.

---

## 4. 현재 프로젝트 적용 예시

```toml
# gradle/libs.versions.toml
[versions]
spring-boot      = "3.5.14"
dep-management   = "1.1.7"

[plugins]
spring-boot    = { id = "org.springframework.boot",        version.ref = "spring-boot" }
dep-management = { id = "io.spring.dependency-management", version.ref = "dep-management" }

[libraries]
spring-boot-bom = { module = "org.springframework.boot:spring-boot-dependencies", version.ref = "spring-boot" }
```

```kotlin
// build.gradle.kts (root)
plugins {
    alias(libs.plugins.spring.boot) apply false
    alias(libs.plugins.dep.management) apply false
}

val springBootVersion = libs.versions.spring.boot.get()

subprojects {
    the<DependencyManagementExtension>().apply {
        imports {
            mavenBom("org.springframework.boot:spring-boot-dependencies:$springBootVersion")
        }
    }
}
```

> `subprojects {}` 안에서는 delegate가 서브프로젝트로 바뀌어 `libs` 접근자가 동작하지 않는다.  
> 루트 스코프에서 버전을 먼저 꺼내 변수로 넘기는 방식으로 우회한다.

---

## 5. 언제 도입해야 하나

| 상황 | 판단 |
|------|------|
| 단일 모듈, 외부 라이브러리 몇 개 | `val` 변수로도 충분 |
| 멀티모듈 프로젝트 | Version Catalog 권장 |
| 여러 팀이 같은 버전 세트를 써야 하는 경우 | Version Catalog 필수 (Nexus 배포까지) |
| CI에 Dependabot/Renovate 붙이는 경우 | Version Catalog 필수 |

---

## 참고

- [Gradle 공식 — Sharing dependency versions between projects](https://docs.gradle.org/current/userguide/platforms.html)
- [Gradle 공식 — Version Catalogs](https://docs.gradle.org/current/userguide/version_catalogs.html)
- [Spring Boot — Dependency Management](https://docs.spring.io/spring-boot/docs/current/gradle-plugin/reference/htmlsingle/#managing-dependencies)
