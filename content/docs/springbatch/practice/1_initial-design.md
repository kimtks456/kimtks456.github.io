---
title: "1. 초기설계"
weight: 1
date: 2026-05-12
---

> 본 문서는 `batch-common` 공통 플랫폼의 **패키지 구조**와
> 각 기능 영역별 **구현 목록** 및 실제 구현 중 확인된 **설계 결정 사항**을 정리한다.
> 실제 코드는 `/spring-batch-practice` 저장소의 `batch-common` 모듈에 있다.

---

## 1. batch-common 실제 패키지 구조

```
batch-common/
└── src/main/java/com/example/spring_batch_practice/
    │
    ├── core/                                   # 공통 인프라 (job 독립)
    │   ├── api/                                # Admin REST API
    │   │   ├── BatchAdminController.java       # GET/POST 엔드포인트
    │   │   ├── BatchJobService.java            # 실행·중단·재시작·이력 조회
    │   │   └── dto/
    │   │       └── JobExecutionResponse.java   # read/write/skip 집계 DTO
    │   │
    │   ├── error/
    │   │   └── BatchErrorConfig.java           # Retry·Skip 정책 기본 빈
    │   │                                       # @ConditionalOnMissingBean → 잡별 재정의 가능
    │   │
    │   ├── item/
    │   │   ├── reader/
    │   │   │   ├── JdbcCursorReaderFactory.java    # JdbcCursorItemReader 팩토리
    │   │   │   ├── JpaPagingReaderFactory.java     # JpaPagingItemReader 팩토리
    │   │   │   └── MyBatisCursorReaderFactory.java # MyBatisCursorItemReader 팩토리
    │   │   └── writer/
    │   │       ├── JpaItemWriterFactory.java        # JpaItemWriter 팩토리
    │   │       └── MyBatisBatchWriterFactory.java   # MyBatisBatchItemWriter 팩토리
    │   │
    │   ├── listener/
    │   │   └── JobLoggingListener.java         # 잡 실행 전후 로그 (시작·종료·소요시간)
    │   │
    │   └── partition/
    │       ├── RangePartitioner.java           # ID 범위 기반 파티셔너 (JdbcTemplate 사용)
    │       └── PartitionStepHelper.java        # 파티션 Step 정적 빌더
    │
    └── job/
        └── sample/                             # 샘플 잡 (JPA vs MyBatis 비교용)
            ├── domain/
            │   └── Order.java                  # @Entity(name="BatchOrder"), @Table(name="orders")
            ├── mybatis/
            │   └── OrderMapper.java            # @Mapper, SELECT/UPDATE/INSERT/DELETE
            ├── SampleJpaJobConfig.java         # JpaCursorItemReader + JpaItemWriter
            └── SampleMyBatisJobConfig.java     # MyBatisCursorItemReader + MyBatisBatchItemWriter

└── src/main/resources/
    ├── application.yaml
    ├── mapper/
    │   └── OrderMapper.xml                     # MyBatis SQL XML
    └── schema/
        ├── batch-schema-postgresql.sql         # Spring Batch 메타 테이블 DDL (수동 관리)
        └── batch-schema-drop-postgresql.sql    # 메타 테이블 DROP DDL
```

---

## 2. 의존성

| 의존성 | 버전 | 용도 |
|---|---|---|
| spring-boot-starter-batch | Boot 관리 | 배치 코어 |
| spring-boot-starter-data-jpa | Boot 관리 | JPA 리더·라이터 |
| spring-boot-starter-web | Boot 관리 | Admin REST API |
| spring-boot-starter-actuator | Boot 관리 | 헬스체크, 메트릭 |
| mybatis-spring-boot-starter | 3.0.4 | MyBatis 자동구성 (`mybatis-spring` 포함 → 배치 클래스도 내장) |
| spring-cloud-starter-task | Cloud 관리 | Task 메타 테이블 |
| postgresql | Boot 관리 | 운영 DB |
| h2 | Boot 관리 | 테스트 인메모리 DB |
| lombok | Boot 관리 | 보일러플레이트 제거 |
| spring-batch-test | Boot 관리 | `JobLauncherTestUtils`, `JobRepositoryTestUtils` |

> `mybatis-spring-batch` 별도 아티팩트는 존재하지 않는다.
> `MyBatisCursorItemReader`, `MyBatisBatchItemWriter` 등 배치 통합 클래스는
> `mybatis-spring` (`org.mybatis.spring.batch.*`) 내에 포함되어 있으며,
> `mybatis-spring-boot-starter`를 추가하면 함께 제공된다.

---

## 3. 주요 설계 결정 사항

### 3-1. Spring Batch 메타 테이블 관리 방식

`spring.batch.jdbc.initialize-schema: never` 로 Spring Boot의 자동 DDL 생성을 비활성화.
`src/main/resources/schema/batch-schema-postgresql.sql` 에 Spring Batch 5.2.x PostgreSQL DDL을 보관,
Docker Compose 기동 시 초기 스크립트(`01_batch_schema.sql`)로 실행.

### 3-2. Job 자동 실행 비활성화

`spring.batch.job.enabled: false` → 애플리케이션 기동 시 Job 자동 실행 없음.
Admin REST API(`POST /admin/batch/jobs/{jobName}/run`) 또는 스케줄러를 통한 명시적 트리거만 허용.

### 3-3. Spring Boot 3.5의 JobOperator 자동 구성

Spring Boot **3.5부터 `JobOperator`를 `BatchAutoConfiguration` 내에서 자동 구성**한다.
이전에는 직접 `SimpleJobOperator`를 `@Bean`으로 등록해야 했으나, 3.5 이후 불필요.
→ `BatchCoreConfig.java`(직접 정의했던 `JobOperator` 빈) 삭제. Spring Boot 자동 구성에 위임.

### 3-4. @Entity 이름과 JPQL 예약어

JPA 엔티티 클래스명이 `Order`일 때 JPQL에서 `FROM Order o`를 사용하면
`ORDER`가 예약어로 인식될 수 있다.
→ `@Entity(name = "BatchOrder")`로 JPQL 내 엔티티명을 변경하여 충돌 회피.
테이블명은 `@Table(name = "orders")`로 그대로 유지.

### 3-5. JpaCursorItemReader vs JpaPagingItemReader

| | `JpaCursorItemReader` | `JpaPagingItemReader` |
|---|---|---|
| 방식 | JPQL 스트리밍 커서 | OFFSET/LIMIT 페이지네이션 |
| 트랜잭션 | 커서가 청크 경계를 넘어 유지됨 | 각 페이지가 독립 트랜잭션 |
| 읽기 대상 수정 시 | 안전 (커서 기반) | **데이터 밀림 발생** (처리 후 OFFSET 틀어짐) |
| 샘플 채택 | **SampleJpaJobConfig** | — |

→ 처리 후 상태가 바뀌는 쿼리에는 `JpaCursorItemReader` 사용.

### 3-6. @SpringBatchTest 미사용 이유

`@SpringBatchTest`는 내부적으로 `JobScopeTestExecutionListener`를 등록한다.
이 리스너는 **`JobExecution`을 반환하는 모든 메서드**를 job execution 공급자로 간주하고
`@BeforeEach` 이전에 호출을 시도한다.
`launch()` 같은 테스트 헬퍼 메서드가 있으면 충돌이 발생한다 (`The Job must not be null`).

→ `@SpringBatchTest` 제거. `JobLauncherTestUtils`와 `JobRepositoryTestUtils`를 `@BeforeEach`에서 직접 인스턴스화.

```java
@BeforeEach
void setUp() {
    launcher = new JobLauncherTestUtils();
    launcher.setJobLauncher(jobLauncher);
    launcher.setJobRepository(jobRepository);
    launcher.setJob(targetJob);

    new JobRepositoryTestUtils(jobRepository).removeJobExecutions();
}
```

### 3-7. MyBatis 표준화 결정

| 영역 | 기술 | 비고 |
|---|---|---|
| 배치 Reader (업무) | `MyBatisCursorItemReader` | SQL XML에서 관리 |
| 배치 Writer (업무) | `MyBatisBatchItemWriter` | batch executor 자동 사용 |
| 인프라 쿼리 (RangePartitioner 등) | `JdbcTemplate` | MIN/MAX 2줄 쿼리에 Mapper XML 생성은 과잉 |
| 테스트 setup (JPA 버전 테스트) | `JdbcTemplate` | 테스트 헬퍼는 JdbcTemplate이 간단 |
| 테스트 setup (MyBatis 버전 테스트) | `OrderMapper` | 프로덕션 Mapper 재사용 |

---

## 4. 기능 영역별 구현 목록

### 4-1. Job 실행/관리

| # | 구현 항목 | 상태 |
|---|---|---|
| 1 | Job 수동 실행 API `POST /admin/batch/jobs/{jobName}/run` | ✅ 완료 |
| 2 | Job 재실행 `POST /admin/batch/executions/{id}/restart` | ✅ 완료 |
| 3 | Job 중단 API `POST /admin/batch/executions/{id}/stop` | ✅ 완료 |
| 4 | Job 목록 조회 `GET /admin/batch/jobs` | ✅ 완료 |
| 5 | 실행 이력 조회 `GET /admin/batch/executions` | ✅ 완료 |

### 4-2. 공통 에러 처리

| # | 구현 항목 | 상태 |
|---|---|---|
| 1 | Retry 정책 빈 (`SimpleRetryPolicy(3)`, `@ConditionalOnMissingBean`) | ✅ 완료 |
| 2 | Skip 정책 빈 (`LimitCheckingItemSkipPolicy(10, ...)`, `@ConditionalOnMissingBean`) | ✅ 완료 |
| 3 | `JobLoggingListener` (실행 전후 로그, 소요시간) | ✅ 완료 |
| 4 | `StepLoggingListener` | ⬜ 미구현 |
| 5 | `JobAlertListener` (실패 알림) | ⬜ 미구현 |

### 4-3. 공통 ItemReader / Writer

| # | 구현 항목 | 상태 |
|---|---|---|
| 1 | `JpaPagingReaderFactory` | ✅ 완료 |
| 2 | `JdbcCursorReaderFactory` | ✅ 완료 |
| 3 | `JpaItemWriterFactory` | ✅ 완료 |
| 4 | `MyBatisCursorReaderFactory` | ✅ 완료 |
| 5 | `MyBatisBatchWriterFactory` | ✅ 완료 |
| 6 | `FlatFileWriterFactory` | ⬜ 미구현 |
| 7 | `RestApiItemReader` | ⬜ 미구현 |

### 4-4. 병렬 처리

| # | 구현 항목 | 상태 |
|---|---|---|
| 1 | `RangePartitioner` (ID 범위 분할) | ✅ 완료 |
| 2 | `PartitionStepHelper` (빌더 래퍼) | ✅ 완료 |
| 3 | `TaskExecutor` 공통 빈 | ⬜ 미구현 |

### 4-5. 샘플 Job

| # | 구현 항목 | 설명 |
|---|---|---|
| 1 | `SampleJpaJobConfig` | `JpaCursorItemReader` + `JpaItemWriter`, orders 처리 |
| 2 | `SampleMyBatisJobConfig` | `MyBatisCursorItemReader` + `MyBatisBatchItemWriter`, 동일 기능 |

두 Job은 동일한 비즈니스 로직(PENDING·amount>10000 → COMPLETED)을 JPA와 MyBatis로 각각 구현하여 비교 목적으로 공존한다.

---

## 5. 미결 사항

| 항목 | 현황 | 검토 방향 |
|---|---|---|
| 스케줄링 방식 | 미정 | Quartz(클러스터링) vs 외부(k8s CronJob, Jenkins) |
| 멀티 모듈 구조 | 단일 모듈 | `batch-core` + `batch-jobs` 분리 고려 가능 |
| 알림(Notification) | 미구현 | Slack Webhook 우선 검토 |
| Prometheus/Grafana 연동 | 미구현 | Actuator Micrometer 기반 |
