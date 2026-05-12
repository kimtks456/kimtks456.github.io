---
title: "1. 초기설계"
weight: 1
date: 2026-05-12
---

> 본 문서는 `batch-common` 공통 플랫폼의 **패키지 구조 설계**와
> 각 기능 영역별 **구현 목록**을 정의한다.
> 실제 구현은 `/spring-batch-practice` 저장소에서 진행한다.

---

## 1. batch-common 패키지 구조

```
batch-common/
└── src/main/java/com/example/batch/
    ├── config/                          # Auto-configuration, DataSource 분리
    │   ├── BatchAutoConfiguration.java  # @EnableBatchProcessing 공통 진입점
    │   ├── BatchDataSourceConfig.java   # 메타 DB / 업무 DB DataSource 분리
    │   └── BatchProperties.java         # application.yml 바인딩 설정값
    │
    ├── core/
    │   ├── job/                         # Job 실행·관리
    │   │   ├── BatchJobLauncher.java    # Job 수동 실행, 재실행 진입점
    │   │   ├── BatchJobRegistry.java    # 등록된 Job 조회
    │   │   └── BatchJobService.java     # 실행·중단·이력 조회 비즈니스 로직
    │   │
    │   ├── step/                        # Step 설정 유틸
    │   │   ├── ChunkStepHelper.java     # Chunk Step 공통 빌더 래퍼
    │   │   └── PartitionStepHelper.java # Partitioning Step 빌더 래퍼
    │   │
    │   └── item/                        # 공통 ItemReader / Writer / Processor
    │       ├── reader/
    │       │   ├── JpaCursorReaderFactory.java
    │       │   ├── JpaPagingReaderFactory.java
    │       │   └── RestApiItemReader.java
    │       ├── writer/
    │       │   ├── JpaItemWriterFactory.java
    │       │   └── FlatFileWriterFactory.java
    │       └── processor/
    │           └── ValidatingItemProcessor.java
    │
    ├── listener/                         # 공통 Job/Step Listener
    │   ├── JobLoggingListener.java       # 실행 전후 로그
    │   ├── StepLoggingListener.java
    │   └── JobAlertListener.java         # 실패 시 알림 트리거
    │
    ├── error/                            # Retry / Skip 정책
    │   ├── BatchRetryPolicy.java
    │   └── BatchSkipPolicy.java
    │
    ├── monitoring/                       # 메트릭·실행 추적
    │   ├── BatchMetrics.java             # Micrometer 커스텀 메트릭 등록
    │   └── BatchExecutionTracker.java    # 실행 진행률 추적
    │
    ├── admin/                            # Admin REST API
    │   ├── BatchAdminController.java
    │   └── dto/
    │       ├── JobExecutionResponse.java
    │       ├── StepExecutionResponse.java
    │       └── JobTriggerRequest.java
    │
    ├── notification/                     # 알림 발송
    │   ├── NotificationService.java      # 인터페이스
    │   ├── SlackNotificationSender.java
    │   └── EmailNotificationSender.java
    │
    └── util/
        ├── JobParameterUtils.java        # JobParameters 빌더 유틸
        └── BatchDateUtils.java           # 배치용 날짜 계산 유틸
```

---

## 2. Spring Initializr 의존성

| 의존성 | 용도 |
|---|---|
| Spring Batch | 배치 코어 |
| Spring Data JPA | 메타 DB + 업무 DB 접근 |
| Spring Web | Admin REST API |
| Spring Boot Actuator | `/actuator/health`, metrics 엔드포인트 |
| Micrometer Prometheus Registry | 배치 실행 메트릭 수집 |
| H2 Database | 로컬/테스트용 메타 DB |
| MySQL Driver | 운영 메타 DB |
| Lombok | 보일러플레이트 제거 |
| Quartz Scheduler | 스케줄링 필요 시 추가 (선택) |

---

## 3. 기능 영역별 구현 목록

### 3-1. Job 실행/관리

| # | 구현 항목 | 설명 | 우선순위 |
|---|---|---|---|
| 1 | Job 수동 실행 API | `POST /admin/batch/jobs/{jobName}/run` | 높음 |
| 2 | Job 재실행 | 실패한 `JobExecution`을 마지막 실패 지점부터 재시작 | 높음 |
| 3 | Job 중단 API | `POST /admin/batch/jobs/{executionId}/stop` | 높음 |
| 4 | JobParameters 빌더 유틸 | 타입 안전한 파라미터 생성, 유효성 검사 | 중간 |
| 5 | Job 목록 조회 API | 등록된 Job 이름·설명 목록 반환 | 중간 |
| 6 | 실행 중인 Job 상태 조회 | 진행률, 시작 시각, 소요 시간 실시간 확인 | 중간 |

---

### 3-2. 모니터링

| # | 구현 항목 | 설명 | 우선순위 |
|---|---|---|---|
| 1 | Job 실행 이력 조회 API | `BATCH_JOB_EXECUTION` 기반 페이징 조회 | 높음 |
| 2 | Step 상세 조회 API | read/write/skip/commit count 포함 | 높음 |
| 3 | Micrometer 커스텀 메트릭 | `batch.job.duration`, `batch.step.skip.count` 등 등록 | 중간 |
| 4 | Prometheus + Grafana 연동 | Actuator → Prometheus scrape → Grafana 대시보드 | 중간 |
| 5 | 메타 테이블 정리 배치 | 오래된 `BATCH_*` 이력 주기적 삭제 | 낮음 |

---

### 3-3. 공통 에러 처리

| # | 구현 항목 | 설명 | 우선순위 |
|---|---|---|---|
| 1 | Retry 정책 빈 | 재시도 횟수·대상 예외 타입 중앙 설정 | 높음 |
| 2 | Skip 정책 빈 | 허용 예외 타입·최대 스킵 수 중앙 설정 | 높음 |
| 3 | JobLoggingListener | Job 시작/종료/실패 로그 공통 처리 | 높음 |
| 4 | StepLoggingListener | Step 단위 실행 결과 로그 | 중간 |
| 5 | JobAlertListener | 실패 시 알림 발송 트리거 (Slack/Email) | 중간 |
| 6 | 전역 예외 핸들러 | Admin API용 `@ControllerAdvice` | 낮음 |

---

### 3-4. 공통 ItemReader / Writer / Processor

| # | 구현 항목 | 설명 | 우선순위 |
|---|---|---|---|
| 1 | JpaPagingReaderFactory | `JpaPagingItemReader` 설정 줄여주는 팩토리 | 높음 |
| 2 | JpaCursorReaderFactory | `JpaCursorItemReader` 팩토리 | 높음 |
| 3 | JpaItemWriterFactory | `JpaItemWriter` 팩토리 | 높음 |
| 4 | FlatFileWriterFactory | CSV/고정길이 파일 출력 팩토리 | 중간 |
| 5 | RestApiItemReader | 외부 API 페이징 조회용 ItemReader | 중간 |
| 6 | ValidatingItemProcessor | `javax.validation` 기반 입력값 검증 Processor | 중간 |

---

### 3-5. 병렬 처리

| # | 구현 항목 | 설명 | 우선순위 |
|---|---|---|---|
| 1 | RangePartitioner | ID 범위 기반 데이터 분할 Partitioner | 높음 |
| 2 | PartitionStepHelper | Partitioning Step 설정 빌더 래퍼 | 높음 |
| 3 | TaskExecutor 설정 | `ThreadPoolTaskExecutor` 공통 빈 | 중간 |
| 4 | Multi-threaded Step 예제 | 청크 병렬 처리 레퍼런스 구현 | 중간 |
| 5 | AsyncItemProcessor/Writer | 비동기 처리 레퍼런스 구현 | 낮음 |

---

### 3-6. 메타데이터 관리

| # | 구현 항목 | 설명 | 우선순위 |
|---|---|---|---|
| 1 | 메타 DB DataSource 분리 | 업무 DB와 메타 DB를 별도 DataSource로 분리 | 높음 |
| 2 | 메타 테이블 DDL 관리 | `schema-mysql.sql` 버전별 관리 | 높음 |
| 3 | 이력 정리 Job | N일 이상 지난 `BATCH_JOB_EXECUTION` 삭제 | 중간 |

---

### 3-7. Admin REST API

| # | 구현 항목 | 설명 | 우선순위 |
|---|---|---|---|
| 1 | `GET /admin/batch/jobs` | 등록 Job 목록 | 높음 |
| 2 | `POST /admin/batch/jobs/{jobName}/run` | Job 실행 (파라미터 포함) | 높음 |
| 3 | `POST /admin/batch/jobs/{executionId}/stop` | 실행 중 Job 중단 | 높음 |
| 4 | `GET /admin/batch/executions` | 실행 이력 페이징 조회 | 중간 |
| 5 | `GET /admin/batch/executions/{id}/steps` | Step 상세 조회 | 중간 |

---

### 3-8. 알림 (Notification)

| # | 구현 항목 | 설명 | 우선순위 |
|---|---|---|---|
| 1 | `NotificationService` 인터페이스 | 알림 발송 추상화 | 중간 |
| 2 | Slack 알림 | Job 실패 시 Slack Webhook 발송 | 중간 |
| 3 | Email 알림 | Job 실패 시 이메일 발송 | 낮음 |

---

## 4. 미결 사항

| 항목 | 현황 | 검토 방향 |
|---|---|---|
| 스케줄링 방식 | 미정 | Quartz(클러스터링 지원) vs 외부(k8s CronJob, Jenkins) |
| 메타 DB 분리 여부 | 미정 | 로컬은 H2, 운영은 업무 DB와 분리 검토 |
| 멀티 모듈 구조 | 미정 | `batch-core` + `batch-jobs` 분리 vs 단일 모듈 |
