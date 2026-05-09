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
mkdir -p scripts
mkdir -p connectors/db-sink
mkdir -p test
touch .gitignore
touch brokers/server.properties
touch scripts/create-topics.sh
touch test/docker-compose.yml test/.env.dev test/.env.qa
```

### 1.3. `.gitignore`

```
# OS
.DS_Store
*.swp

# Secrets (.env.dev / .env.qa 는 커밋 대상)
.env
.env.prd
```

### 1.4. `test/docker-compose.yml` 실행

환경별로 `.env.dev` / `.env.qa` 파일을 `--env-file` 로 지정한다.

```bash
cd test

# 로컬 개발
docker compose --env-file .env.dev up -d

# Kafka 준비 확인
docker compose logs -f init-kafka
```

접근 포인트:

| 서비스 | URL | 비고 |
|--------|-----|------|
| Kafka UI | `http://localhost:8989` | 토픽·메시지 확인 |
| Nexus | `http://localhost:8081` | 라이브러리 저장소 |
| Redis | `localhost:6379` | 멱등성 store |

### 1.5. 토픽 자동 생성 스크립트 (`scripts/create-topics.sh`)

`topics/` 하위 YAML 파일을 루프하며 토픽을 생성한다. docker-compose의 `init-kafka` 서비스가 Kafka healthcheck 통과 후 이 스크립트를 실행한다.

```bash
#!/bin/bash
for f in $(find /topics -name "*.yaml" | sort); do
  name=$(grep '^name:'             "$f" | awk '{print $2}')
  partitions=$(grep '^partitions:' "$f" | awk '{print $2}')
  replication=$(grep '^replication-factor:' "$f" | awk '{print $2}')
  retention=$(grep 'retention.ms:' "$f" | awk '{print $2}' | tr -d '"')
  cleanup=$(grep 'cleanup.policy:' "$f" | awk '{print $2}')

  /opt/kafka/bin/kafka-topics.sh --bootstrap-server "$BOOTSTRAP" \
    --create --if-not-exists \
    --topic "$name" --partitions "$partitions" --replication-factor "$replication" \
    --config "retention.ms=${retention}" --config "cleanup.policy=${cleanup}"
done
```

토픽 추가 시 YAML 파일만 추가하면 된다. `docker-compose.yml` 수정 불필요.

> `--if-not-exists`: 재시작 시 이미 존재하는 토픽은 skip — 충돌 없음.
> config 변경(retention 등)은 재시작으로 반영 안 됨 → `kafka-configs.sh --alter` 사용.

### 1.6. 첫 커밋

```bash
git add .
git commit -m "chore: kafka-platform 초기 구조 세팅"
```

### 1.7. Nexus 초기 설정

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

### 2.5. Nexus 배포

```bash
./gradlew :kafka-common-lib:publish
```

성공 시 Nexus UI → Browse → `maven-snapshots` 에서 `com/example/kafka-common-lib/1.0.0-SNAPSHOT/` 확인.

> 빌드 스킵하고 바로 배포만: `./gradlew :kafka-common-lib:publish -x test`

### 2.6. order-service 에서 당겨오기

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

### 2.7. order-service — dev/qa/prd 환경 분리

Spring 프로파일 기반으로 환경을 분리한다.

| 파일 | 커밋 여부 | 용도 |
|------|-----------|------|
| `application.yaml` | ✓ | 공통 설정 (serializer, port 등) |
| `application-dev.yaml` | ✓ | 로컬 개발 (localhost 호스트명) |
| `application-qa.yaml` | ✓ | QA 환경 (QA 클러스터 주소, 시크릿은 `${VAR}`) |
| `application-prd.yaml` | ✗ gitignore | 운영 환경 (모든 값 env 주입) |

```yaml
# application-dev.yaml
spring:
  kafka:
    bootstrap-servers: localhost:9092
  datasource:
    url: jdbc:postgresql://localhost:5432/orderdb
    username: postgres
    password: postgres
  data:
    redis:
      host: localhost
      port: 6379
```

실행 시 프로파일 지정:

```bash
# 로컬 개발
SPRING_PROFILES_ACTIVE=dev ./gradlew :order-service:bootRun

# 운영 (K8s 등에서 env 주입)
SPRING_PROFILES_ACTIVE=prd java -jar order-service.jar
```

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
