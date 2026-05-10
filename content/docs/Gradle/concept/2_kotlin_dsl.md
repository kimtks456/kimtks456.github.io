---
title: "2. Groovy DSL vs Kotlin DSL (.kts)"
weight: 1
date: 2026-05-10
---

> Gradle 빌드 스크립트는 두 가지 언어로 작성할 수 있다.  
> `build.gradle` (Groovy) vs `build.gradle.kts` (Kotlin).  
> Gradle 공식은 Kotlin DSL을 기본으로 전환했고(Gradle 8.x), 신규 프로젝트는 `.kts`가 표준이다.

---

## 1. 핵심 차이

| 항목 | Groovy DSL | Kotlin DSL (.kts) |
|------|-----------|-------------------|
| 타입 | 동적 타입 | **정적 타입** |
| IDE 자동완성 | 부분적 (추론 실패 많음) | **완전 지원** (IntelliJ 기준) |
| 오타 검출 시점 | 런타임 (빌드 실행 시) | **컴파일 타임** |
| 리팩터링 | 불안정 | 안정적 (rename, find usages 등) |
| 빌드 캐시 히트율 | 높음 | 높음 (동일) |
| 첫 빌드 속도 | 빠름 | 약간 느림 (스크립트 컴파일) |
| 생태계 표준 | 레거시 | **신규 표준** |

---

## 2. 문법 비교

### 플러그인 선언

```groovy
// Groovy
plugins {
    id 'org.springframework.boot' version '3.5.14'
    id 'java'
}
```

```kotlin
// Kotlin DSL
plugins {
    id("org.springframework.boot") version "3.5.14"
    java
}
```

### 의존성 선언

```groovy
// Groovy
dependencies {
    implementation 'org.springframework.boot:spring-boot-starter-web'
    testImplementation 'org.springframework.boot:spring-boot-starter-test'
}
```

```kotlin
// Kotlin DSL
dependencies {
    implementation("org.springframework.boot:spring-boot-starter-web")
    testImplementation("org.springframework.boot:spring-boot-starter-test")
}
```

### 태스크 정의

```groovy
// Groovy
test {
    useJUnitPlatform()
}
```

```kotlin
// Kotlin DSL
tasks.withType<Test> {
    useJUnitPlatform()
}
```

---

## 3. Kotlin DSL의 실질적 이득

### IDE 자동완성

```kotlin
dependencies {
    implementation(libs.  // ← 여기서 Ctrl+Space → libs에 등록된 라이브러리 전체 목록 표시
```

Groovy에서는 문자열이라 IDE가 추론 불가. Kotlin DSL + Version Catalog 조합이 특히 강력하다.

### 컴파일 타임 오류 검출

```kotlin
// 오타 → 빌드 전에 IDE가 빨간 줄로 표시
implementaion("org.springframework.boot:spring-boot-starter-web")
//  ↑ 오타. Kotlin DSL은 컴파일 단계에서 잡아준다.
```

---

## 4. Kotlin DSL의 단점

### 첫 빌드 시 스크립트 컴파일

`.kts` 파일은 Kotlin으로 컴파일된 후 실행된다. 최초 빌드 또는 스크립트 변경 후 첫 빌드는 Groovy보다 수 초 느릴 수 있다.  
이후에는 컴파일 결과가 캐시되므로 반복 빌드 속도 차이는 없다.

### `plugins {}` 블록의 제약

`plugins {}` 블록 안에서는 변수나 함수를 사용할 수 없다. Gradle이 의존성 해석 전에 플러그인을 먼저 로드해야 하기 때문이다.

```kotlin
val version = "3.5.14"

plugins {
    id("org.springframework.boot") version version  // ❌ 컴파일 에러
}
```

Version Catalog의 `alias()`를 쓰면 이 제약을 우회할 수 있다.

```kotlin
plugins {
    alias(libs.plugins.spring.boot)  // ✅ TOML에서 버전 관리
}
```

---

## 5. 결론

신규 프로젝트는 `.kts`를 쓴다.  
Groovy 기반 레거시 프로젝트는 기능 개발 중에 마이그레이션할 필요는 없으나, 멀티모듈 확장이나 Version Catalog 도입 시점에 함께 전환하는 게 자연스럽다.

---

## 참고

- [Gradle 공식 — Kotlin DSL Primer](https://docs.gradle.org/current/userguide/kotlin_dsl.html)
- [Gradle 공식 — Migrating build logic from Groovy to Kotlin](https://docs.gradle.org/current/userguide/migrating_from_groovy_to_kotlin_dsl.html)
