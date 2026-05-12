---
title: "1. SNAPSHOT vs Release"
weight: 1
date: 2026-05-10
---

> Gradle/Maven 버전 관리의 핵심 구분.  
> 버전 번호 뒤에 `-SNAPSHOT`이 붙는지 여부가 전부다.

---

## 1. 개념 비교

| | SNAPSHOT (`1.0.0-SNAPSHOT`) | Release (`1.0.0`) |
|---|---|---|
| 재배포 | 가능 — 같은 버전으로 계속 덮어씀 | **불가** — 동일 버전 재배포 시 Nexus 오류 |
| 소비자 동작 | Gradle이 매번 Nexus에서 최신본 재확인 | 로컬 캐시 고정 |
| 강제 최신화 | `--refresh-dependencies` | 불필요 (버전 올려서 재배포) |
| Nexus 레포 | `maven-snapshots` | `maven-releases` |
| 용도 | 개발 중 반복 배포 | 버전 확정 후 배포 |

```text
개발 중:  version = '1.0.0-SNAPSHOT'
          └── publish → maven-snapshots → 소비자가 매번 최신본 수신

릴리즈:   version = '1.0.0'
          └── publish → maven-releases → 이후 동일 버전 변경 불가 (immutable)
```

---

## 2. Nexus 레포 구조

Nexus 설치 시 기본 생성되는 3개 레포 (별도 생성 불필요):

| 레포 | 역할 |
|---|---|
| `maven-releases` | Release 버전 저장 (변경 불가) |
| `maven-snapshots` | SNAPSHOT 버전 저장 (재배포 가능) |
| `maven-public` | 위 두 개 + Maven Central 묶은 **group 레포** — 소비자가 여기 하나만 바라봄 |

> `maven-public` 하나만 바라보면 releases, snapshots, Maven Central 모두 커버된다.

---

## 3. 실전 전환 흐름

```
1. 개발 중:  version = '1.0.0-SNAPSHOT'  → publish 반복 → 소비자가 매번 최신본 수신
2. 확정 시:  version = '1.0.0'           → publish → 소비자 버전 고정
3. 다음 개발: version = '1.1.0-SNAPSHOT' → 반복
```

---

## 4. 라이브러리 참조 방식 — 두 가지 모드

| 방식 | 설정 | 언제 |
|---|---|---|
| **직접 참조** | `implementation(project(":kafka-common-lib"))` | lib 개발 중 — 빌드 빠름, Nexus 불필요 |
| **Nexus 참조** | `implementation("com.example:kafka-common-lib:1.0.0-SNAPSHOT")` | 실제 소비자 입장 검증 / 릴리즈 시 |

평소 개발은 직접 참조, Nexus 검증이 필요할 때만 한 줄 교체.

### Nexus에서 당겨오기 (order-service 예시)

```kotlin
// order-service/build.gradle.kts
repositories {
    maven {
        url = uri("http://localhost:8081/repository/maven-public/")
        isAllowInsecureProtocol = true
    }
    mavenCentral()
}

dependencies {
    // Nexus 참조 (Nexus 검증 시 활성화)
    implementation("com.example:kafka-common-lib:1.0.0-SNAPSHOT")

    // 직접 참조 (개발 중 빠른 빌드 — 위와 둘 중 하나만 활성화)
    // implementation(project(":kafka-common-lib"))
}
```

SNAPSHOT 최신본 강제 수신:

```bash
./gradlew :order-service:dependencies --refresh-dependencies
```

---

## 5. Gradle build.gradle.kts 배포 설정

`kafka-common-lib`의 Nexus 배포 설정 — 버전 끝이 `-SNAPSHOT`이면 snapshots, 아니면 releases로 자동 분기한다.

```kotlin
publishing {
    publications {
        create<MavenPublication>("mavenJava") {
            from(components["java"])
        }
    }
    repositories {
        maven {
            name = "nexus"
            url = uri(
                if (version.toString().endsWith("SNAPSHOT"))
                    "http://localhost:8081/repository/maven-snapshots/"
                else
                    "http://localhost:8081/repository/maven-releases/"
            )
            credentials {
                username = System.getenv("NEXUS_USERNAME")
                    ?: project.findProperty("nexusUsername") as String? ?: "admin"
                password = System.getenv("NEXUS_PASSWORD")
                    ?: project.findProperty("nexusPassword") as String? ?: ""
            }
            isAllowInsecureProtocol = true
        }
    }
}
```

배포 명령:

```bash
./gradlew :kafka-common-lib:publish

# 테스트 스킵하고 배포만
./gradlew :kafka-common-lib:publish -x test
```

---

## 참고

- [Sonatype Nexus Repository — Docker Hub](https://hub.docker.com/r/sonatype/nexus3)
- [Gradle 공식 — Publishing to Maven repositories](https://docs.gradle.org/current/userguide/publishing_maven.html)
- [Maven — SNAPSHOT vs Release](https://maven.apache.org/guides/getting-started/index.html#what-is-a-snapshot-version)
