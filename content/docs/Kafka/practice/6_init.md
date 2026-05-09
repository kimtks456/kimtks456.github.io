---
title: "6. 초기세팅"
weight: 6
date: 2026-05-09
---

> `kafka-platform` 과 `kafka-common-lib` 을 각각 새 git 레포로 시작할 때의 초기 세팅.
> 패키지 구조·설정 원칙은 [5. 설계](./5_design.md) 참조.

---

## 1. kafka-platform

설정 파일과 docker-compose 만 있는 **config-only 레포** — Java 빌드 도구 불필요.

### 1.1. 레포 초기화

```bash
git init kafka-platform
cd kafka-platform
```

### 1.2. 디렉토리 구조 생성

```bash
mkdir -p brokers
mkdir -p topics/order topics/log
mkdir -p connectors/db-sink
mkdir -p test
touch README.md .gitignore
touch brokers/server.properties
touch test/docker-compose.yml
```

### 1.3. `.gitignore`

```
.DS_Store
*.swp
```

### 1.4. `test/docker-compose.yml`

[5. 설계 §3](./5_design.md) 의 docker-compose 내용 그대로 (Kafka + Kafka UI + Nexus).

로컬 실행:

```bash
cd test
docker compose up -d

# Kafka 준비 확인
docker compose logs kafka | grep "Kafka Server started"
```

접근 포인트:

| 서비스 | URL |
|---|---|
| Kafka UI | `http://localhost:8989` |
| Nexus | `http://localhost:8081` |

### 1.5. 첫 커밋

```bash
git add .
git commit -m "chore: kafka-platform 초기 구조 세팅"
```

### 1.6. Nexus 초기 설정

> 컨테이너 첫 기동 시 1~2분 초기화 시간 필요. 로그에 `Started Sonatype Nexus` 확인 후 진행.

**① 초기 admin 패스워드 확인**

```bash
docker exec nexus cat /nexus-data/admin.password
```

**② 브라우저에서 `http://localhost:8081` 접속**

1. `admin` / (위 패스워드) 로 로그인
2. 패스워드 변경 화면 → 새 패스워드 설정
3. "Configure Anonymous Access" → **Enable anonymous access** 선택

> Anonymous access 활성화: 로컬 실습 환경에서 pull 시 인증 생략용. 운영 환경에서는 비활성화.

**③ 레포 구조 확인**

설치 시 기본으로 생성되는 3개 레포 (별도 생성 불필요):

| 레포 | 역할 |
|---|---|
| `maven-releases` | Release 버전 저장 (변경 불가) |
| `maven-snapshots` | SNAPSHOT 버전 저장 (재배포 가능) |
| `maven-public` | 위 두 개 + Maven Central 묶은 **group 레포** — 소비자가 여기 하나만 바라봄 |

Nexus UI → **Browse** → 각 레포 선택으로 업로드된 아티팩트 확인 가능.

---

## 2. kafka-common-lib

Spring Kafka 기반 **공통 라이브러리** — Spring Boot 앱이 아니라 다른 서비스가 의존성으로 가져다 쓰는 jar.

### 2.1. 프로젝트 생성

[start.spring.io](https://start.spring.io) 에서 생성:

| 항목 | 값 |
|---|---|
| Project | **Gradle - Groovy** |
| Language | Java |
| Spring Boot | 3.4.x |
| Java | **17** |
| Artifact | `kafka-common-lib` |
| Dependencies | 없음 (직접 추가) |

다운로드 후 압축 해제, git 초기화:

```bash
cd kafka-common-lib
git init
git add .
git commit -m "chore: kafka-common-lib 초기 세팅"
```

### 2.2. `build.gradle` 전면 수정

앱이 아닌 **라이브러리** 이므로 `spring-boot` 플러그인 대신 `java-library` 사용.

```gradle
plugins {
    id 'java-library'
    id 'io.spring.dependency-management' version '1.1.7'
    id 'maven-publish'
}

group = 'com.example'
version = '1.0.0-SNAPSHOT'       // 개발 중: SNAPSHOT. 릴리즈 시 '1.0.0' 으로 변경

java {
    sourceCompatibility = JavaVersion.VERSION_17
}

repositories {
    mavenCentral()
}

dependencyManagement {
    imports {
        mavenBom "org.springframework.boot:spring-boot-dependencies:3.4.5"
    }
}

dependencies {
    // 도메인 서비스도 직접 사용 → api 로 전파
    api 'org.springframework.kafka:spring-kafka'

    // 라이브러리 내부에서만 사용
    implementation 'org.springframework.boot:spring-boot-starter-aop'
    implementation 'org.redisson:redisson-spring-boot-starter:3.46.0'

    compileOnly 'org.projectlombok:lombok'
    annotationProcessor 'org.projectlombok:lombok'
    annotationProcessor 'org.springframework.boot:spring-boot-autoconfigure-processor'

    testImplementation 'org.springframework.boot:spring-boot-starter-test'
    testImplementation 'org.springframework.kafka:spring-kafka-test'
    testImplementation 'org.testcontainers:kafka'
}

publishing {
    publications {
        mavenJava(MavenPublication) {
            from components.java
        }
    }
    repositories {
        maven {
            name = 'nexus'
            // SNAPSHOT 이면 maven-snapshots, 아니면 maven-releases 로 자동 분기
            url = version.endsWith('SNAPSHOT')
                ? 'http://localhost:8081/repository/maven-snapshots/'
                : 'http://localhost:8081/repository/maven-releases/'
            credentials {
                username = project.findProperty('nexusUsername') ?: 'admin'
                password = project.findProperty('nexusPassword') ?: ''
            }
            allowInsecureProtocol = true    // http 허용 (로컬 Nexus)
        }
    }
}
```

**`gradle.properties` (레포 루트 또는 `~/.gradle/gradle.properties`)**

```properties
nexusUsername=admin
nexusPassword=설정한-패스워드
```

> `~/.gradle/gradle.properties` 에 두면 모든 프로젝트에서 공유. 레포 루트에 두면 `.gitignore` 에 반드시 추가 — 패스워드를 git 에 올리면 안 됨.

### 2.3. 패키지 구조 생성

```bash
BASE=src/main/java/com/example/kafka
mkdir -p $BASE/config
mkdir -p $BASE/events/order
mkdir -p $BASE/events/log
mkdir -p $BASE/idempotency
mkdir -p $BASE/error
mkdir -p $BASE/serde
mkdir -p src/main/resources/META-INF/spring
```

### 2.4. Auto-configuration 등록

`src/main/resources/META-INF/spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports`:

```
com.example.kafka.config.KafkaAutoConfiguration
```

`KafkaAutoConfiguration.java`:

```java
@AutoConfiguration
@ConditionalOnClass(KafkaTemplate.class)
public class KafkaAutoConfiguration {

    @Bean
    @ConditionalOnMissingBean
    public KafkaProducerConfig kafkaProducerConfig() {
        return new KafkaProducerConfig();
    }

    @Bean
    @ConditionalOnMissingBean
    public KafkaConsumerConfig kafkaConsumerConfig() {
        return new KafkaConsumerConfig();
    }

    @Bean
    @ConditionalOnMissingBean
    public IdempotencyAspect idempotencyAspect(IdempotencyRedisStore store) {
        return new IdempotencyAspect(store);
    }
}
```

### 2.5. SNAPSHOT vs Release — 개념

> 버전 번호 뒤에 `-SNAPSHOT` 이 붙는지 여부가 전부.

```text
개발 중:   1.0.0-SNAPSHOT  →  maven-snapshots  →  같은 버전으로 계속 덮어쓸 수 있음
릴리즈:    1.0.0           →  maven-releases   →  한번 올리면 변경 불가 (immutable)
```

| | SNAPSHOT | Release |
|---|---|---|
| 재배포 | 가능 | **불가** — 동일 버전 재배포 시 Nexus 오류 |
| 소비자 동작 | Gradle 이 매번 Nexus 에서 최신본 재확인 | 로컬 캐시 고정 |
| 강제 최신화 | `--refresh-dependencies` | 불필요 (버전 올려서 재배포) |
| 용도 | lib 개발·반복 시 | 버전 확정 후 배포 |

**실전 전환 흐름:**

1. 개발 중: `version = '1.0.0-SNAPSHOT'` 유지 → publish 반복 → 소비자가 매번 최신본 수신
2. 확정 시: `version = '1.0.0'` 으로 변경 → publish → 소비자 버전 고정
3. 다음 개발: `version = '1.1.0-SNAPSHOT'` 으로 올려서 반복

### 2.6. Nexus 배포

```bash
./gradlew :kafka-common-lib:publish
```

성공 시 Nexus UI → Browse → `maven-snapshots` 에서 `com/example/kafka-common-lib/1.0.0-SNAPSHOT/` 확인.

> 빌드 스킵하고 바로 배포만: `./gradlew :kafka-common-lib:publish -x test`

### 2.7. order-service 에서 당겨오기

`order-service/build.gradle`:

```gradle
repositories {
    maven {
        url 'http://localhost:8081/repository/maven-public/'
        allowInsecureProtocol = true
    }
    mavenCentral()
}

dependencies {
    // ── Nexus 참조 (Nexus 검증 시) ─────────────────────────────────────
    implementation 'com.example:kafka-common-lib:1.0.0-SNAPSHOT'

    // ── 직접 참조 (개발 중 빠른 빌드, 아래와 둘 중 하나만 활성화) ───────
    // implementation project(':kafka-common-lib')
}
```

SNAPSHOT 최신본 강제 수신:

```bash
./gradlew :order-service:dependencies --refresh-dependencies
```

> `maven-public` 은 group 레포 — releases + snapshots + Maven Central 을 하나로 묶음. 여기 하나만 바라보면 된다.

---

## 3. 개발 순서 (권장)

```text
1. kafka-platform
   └── docker compose up -d  (Kafka + Kafka UI + Nexus 기동)
   └── Nexus 초기 설정 (§1.6)
           │
           ▼
2. kafka-common-lib
   └── lib 개발 → ./gradlew :kafka-common-lib:publish → Nexus
           │
           ▼
3. order-service
   └── Nexus 에서 당겨와 실제 send/receive 검증
   └── 빠른 반복 시엔 직접 참조 (project(':kafka-common-lib')) 로 전환
           │
           ▼
4. kafka-platform
   └── 검증 완료된 토픽 YAML PR → merge
```

---

## 참고 (출처)

- [Spring Initializr](https://start.spring.io)
- [Spring Kafka — Reference Documentation](https://docs.spring.io/spring-kafka/reference/)
- [Redisson — Spring Boot Starter](https://github.com/redisson/redisson/tree/master/redisson-spring-boot-starter)
- [Spring Boot — Creating Your Own Auto-configuration](https://docs.spring.io/spring-boot/reference/features/developing-auto-configuration.html)
- [Gradle — java-library plugin](https://docs.gradle.org/current/userguide/java_library_plugin.html)
- [Sonatype Nexus Repository — Docker](https://hub.docker.com/r/sonatype/nexus3)
- [Gradle — Publishing to Maven repositories](https://docs.gradle.org/current/userguide/publishing_maven.html)

### 본 사이트 내 관련 문서

- [5. 설계](./5_design.md) — 패키지 구조·의존성 설계 원칙
