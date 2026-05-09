---
title: "2. build.gradle.kts vs settings.gradle.kts"
weight: 2
date: 2026-05-10
---

> 두 파일은 역할이 완전히 다르다.  
> `settings.gradle.kts`는 **프로젝트 구조**를 정의하고,  
> `build.gradle.kts`는 **빌드 로직**을 정의한다.

---

## 1. 평가 순서

Gradle은 빌드 시작 시 다음 순서로 파일을 평가한다.

```
[1] settings.gradle.kts   ← 가장 먼저 실행
      └── 어떤 모듈이 있는지, 플러그인 저장소는 어디인지 결정
          
[2] build.gradle.kts (root)
      └── 공통 설정 (전체 서브프로젝트에 적용할 것들)

[3] build.gradle.kts (각 서브프로젝트)
      └── 모듈별 의존성, 태스크 등
```

`settings.gradle.kts`가 평가되기 전까지 Gradle은 빌드 대상 모듈이 무엇인지조차 모른다.

---

## 2. settings.gradle.kts

### 역할

| 기능 | 설명 |
|------|------|
| `rootProject.name` | 프로젝트 이름 (Nexus 배포 시 groupId 등에 영향) |
| `include()` | 서브모듈 등록 |
| `pluginManagement {}` | 플러그인 저장소 및 버전 선언 |
| `dependencyResolutionManagement {}` | 의존성 저장소 전역 통제, Version Catalog 선언 |

### 예시 (멀티모듈 프로젝트)

```kotlin
rootProject.name = "kafka-practice"

include("kafka-common-lib", "order-service")
```

`include()`에 없는 디렉토리는 Gradle이 서브모듈로 인식하지 않는다.

---

## 3. build.gradle.kts

### 위치별 역할

#### 루트 `build.gradle.kts`

모든 서브프로젝트에 공통 적용할 설정을 담는다.  
직접 빌드 산출물을 만들지 않는 경우 `apply false`로 플러그인을 선언만 해두고 실제 적용은 서브프로젝트에 위임한다.

```kotlin
plugins {
    alias(libs.plugins.spring.boot) apply false   // 선언만, 적용 안 함
    alias(libs.plugins.dep.management) apply false
}

subprojects {
    apply(plugin = "java")
    apply(plugin = "io.spring.dependency-management")

    java {
        toolchain { languageVersion = JavaLanguageVersion.of(21) }
    }

    // BOM 공통 임포트
    the<DependencyManagementExtension>().apply {
        imports { mavenBom("org.springframework.boot:spring-boot-dependencies:$springBootVersion") }
    }
}
```

#### 서브모듈 `build.gradle.kts`

해당 모듈에만 적용되는 플러그인, 의존성, 태스크를 정의한다.

```kotlin
// kafka-common-lib/build.gradle.kts
plugins {
    `java-library`
    `maven-publish`
}

dependencies {
    api("org.springframework.kafka:spring-kafka")
    implementation("org.springframework.boot:spring-boot-starter-data-redis")
}
```

---

## 4. 멀티모듈 전체 구조

```
kafka-practice/               ← 루트
├── settings.gradle.kts       ← 모듈 선언 (include)
├── build.gradle.kts          ← 공통 설정 (subprojects 블록)
├── gradle/
│   └── libs.versions.toml    ← 버전 카탈로그
│
├── kafka-common-lib/
│   └── build.gradle.kts      ← 라이브러리 모듈 설정
│
└── order-service/
    └── build.gradle.kts      ← 애플리케이션 모듈 설정
```

---

## 5. 자주 혼동하는 포인트

### `apply false`의 의미

루트에서 `id("...") version "..." apply false`는 **버전만 고정**하고 실제 적용은 하지 않겠다는 의미다.  
이후 서브프로젝트에서 `apply(plugin = "...")` 또는 `id("...")` (버전 없이)로 가져다 쓴다.  
버전을 한 곳에서 관리하면서 적용 여부를 모듈별로 제어할 수 있다.

### `java` vs `java-library`

| 플러그인 | 용도 |
|---------|------|
| `java` | 실행 가능한 애플리케이션 |
| `java-library` | 다른 모듈이 가져다 쓰는 라이브러리 |

`java-library`를 쓰면 `api` / `implementation` scope 구분이 가능해진다.  
`api`: 의존성을 소비자 모듈의 컴파일 classpath에도 노출.  
`implementation`: 내부에서만 사용, 소비자에게 노출 안 됨.

---

## 참고

- [Gradle 공식 — Build Lifecycle](https://docs.gradle.org/current/userguide/build_lifecycle.html)
- [Gradle 공식 — Multi-Project Builds](https://docs.gradle.org/current/userguide/multi_project_builds.html)
- [Gradle 공식 — java-library plugin](https://docs.gradle.org/current/userguide/java_library_plugin.html)
