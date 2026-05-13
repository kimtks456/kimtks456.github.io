---
title: "2. 실전 예제 설계"
weight: 2
date: 2026-05-13
---

> 3가지 실전 배치 예제를 설계한다.  
> 각 예제의 Job 흐름, 도메인, Skip/Retry 전략, 테스트 전략을 정리한다.

---

## 1. 예제 개요

| # | Job명 | 트리거 | 설명 |
|---|---|---|---|
| 1 | `notificationResendJob` | REST API (trigger) | Job Parameter로 일자를 받아 해당 일자 이후 FAILED 알림 재발송 |
| 2 | `scheduledNotificationResendJob` | Spring Scheduler (1분) | 전체 FAILED 알림 재발송 |
| 3 | `movieLoadJob` | Spring Scheduler (1분) | 외부 API(Feign)에서 영화 데이터 조회 → IF 테이블 적재 |

---

## 2. 배치에서의 응답 방식

Spring Batch Job은 **비동기 처리**가 기본이다.  
HTTP 요청처럼 즉시 결과를 반환하지 않으며, 처리 결과는 로그와 `BATCH_*` 메타 테이블에 남는다.

### trigger 기반 (예제 1)

```
POST /admin/batch/jobs/notificationResendJob/run
  → JobLauncher.run() 즉시 반환: { jobExecutionId, status: "STARTING" }
  → 실제 처리는 백그라운드에서 진행
  → 클라이언트는 GET /admin/batch/executions/{id} 로 폴링하거나
     JobLoggingListener 가 남기는 로그로 확인
```

### "fromDate가 미래"인 경우

Job 흐름에서 `JobExecutionDecider`로 분기한다.

| 항목 | 값 |
|---|---|
| `BatchStatus` | `COMPLETED` (처리 오류가 아니므로 정상 종료) |
| `ExitStatus.exitCode` | `"NO_TARGET"` |
| `ExitStatus.exitDescription` | `"잘못된 fromDate 입니다."` |

```
fromDate > now
  → Decider: FlowExecutionStatus("NO_TARGET")
  → .on("NO_TARGET").end("NO_TARGET")
  → BatchStatus = COMPLETED
  → ExitStatus = ExitStatus("NO_TARGET", "잘못된 fromDate 입니다.")
```

API 응답에 exitCode를 포함시켜 호출자가 구분할 수 있게 한다:

```json
{
  "jobExecutionId": 42,
  "batchStatus": "COMPLETED",
  "exitCode": "NO_TARGET",
  "exitDescription": "잘못된 fromDate 입니다."
}
```

### schedule 기반 (예제 2, 3)

```
@Scheduled → JobLauncher.run() 호출 → 결과는 로그로만 확인
  → 성공/실패 카운트는 JobLoggingListener → BATCH_JOB_EXECUTION 메타
```

> **결론**: 배치의 응답은 로그가 메인이다.  
> 실시간 처리 결과가 필요하면 JobExecution 메타 테이블 조회 API를 노출하거나  
> 처리 후 별도 알림(Slack 등)을 보내는 방식으로 보완한다.

---

## 3. 도메인 설계

### notification_log 테이블

```sql
CREATE TABLE notification_log (
    id          BIGSERIAL     PRIMARY KEY,
    user_id     VARCHAR(100)  NOT NULL,
    channel     VARCHAR(20)   NOT NULL,   -- EMAIL | SMS | PUSH
    message     TEXT          NOT NULL,
    status      VARCHAR(20)   NOT NULL DEFAULT 'PENDING',  -- PENDING | SENT | FAILED
    retry_count INT           NOT NULL DEFAULT 0,
    trial       INT           NOT NULL DEFAULT 0,          -- status 변경 시마다 +1 (발송 시도 횟수)
    sent_at     TIMESTAMP,
    created_at  TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP
);
```

> `retry_count`: Spring Batch Retry 정책에 의한 청크 내 재시도 횟수  
> `trial`: 배치 실행 단위로 status가 갱신될 때마다 +1 되는 누적 발송 시도 횟수  
> 둘은 레벨이 다르다. `retry_count`는 단일 Job 실행 안에서 리셋될 수 있고, `trial`은 영구 누적된다.

### if_movie 테이블 (예제 3)

```sql
CREATE TABLE if_movie (
    id          BIGSERIAL    PRIMARY KEY,
    external_id VARCHAR(100) NOT NULL UNIQUE,   -- 외부 API의 고유 ID
    title       VARCHAR(500) NOT NULL,
    genre       VARCHAR(100),
    rating      NUMERIC(3,1),
    release_date DATE,
    loaded_at   TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at  TIMESTAMP
);
```

---

## 4. Job 설계

### 4-1. 예제 1 — trigger 기반 알림 재발송

```
notificationResendJob
│
├── [Decision] fromDateValidationDecider
│     fromDate > now  →  FlowExecutionStatus("NO_TARGET")
│                     →  .on("NO_TARGET").end("NO_TARGET")
│                     →  BatchStatus=COMPLETED, ExitStatus("NO_TARGET", "잘못된 fromDate 입니다.")
│     fromDate <= now →  FlowExecutionStatus("PROCEED")
│
└── [Step] notificationResendStep
      Reader   : notification_log WHERE status='FAILED'
                 AND sent_at >= :fromDate AND sent_at <= now()
                 ORDER BY id ASC
      Processor: Feign 호출 → 성공 시 status='SENT', retry_count++ / trial++ 세팅
                            실패 시 status='FAILED', trial++ 세팅
      Writer   : UPDATE notification_log
                   SET status=:status, retry_count=:retryCount, trial=:trial
                 WHERE id=:id
      Chunk    : 100
```

**Job Parameter**

| 파라미터 | 타입 | 필수 | 설명 |
|---|---|---|---|
| `fromDate` | String (yyyy-MM-dd) | Y | 조회 시작 일자 |
| `run.id` | Long | Y | 중복 실행 방지 (currentTimeMillis) |

**흐름 코드 스케치 (JobBuilder)**

```java
// Decider
public class FromDateValidationDecider implements JobExecutionDecider {
    @Override
    public FlowExecutionStatus decide(JobExecution jobExecution, StepExecution stepExecution) {
        String fromDate = jobExecution.getJobParameters().getString("fromDate");
        if (LocalDate.parse(fromDate).isAfter(LocalDate.now())) {
            jobExecution.setExitStatus(new ExitStatus("NO_TARGET", "잘못된 fromDate 입니다."));
            return new FlowExecutionStatus("NO_TARGET");
        }
        return new FlowExecutionStatus("PROCEED");
    }
}

// JobBuilder
return new JobBuilder("notificationResendJob", jobRepository)
    .listener(jobLoggingListener)
    .start(fromDateValidationDecider())
        .on("NO_TARGET").end("NO_TARGET")   // BatchStatus=COMPLETED, ExitCode="NO_TARGET"
        .on("PROCEED").to(notificationResendStep())
    .end()
    .build();
```

---

### 4-2. 예제 2 — schedule 기반 알림 재발송

```
NotificationResendScheduler
  @Scheduled(fixedDelay = 60_000)
  → JobLauncher.run(scheduledNotificationResendJob, params)

scheduledNotificationResendJob
└── [Step] scheduledNotificationResendStep
      Reader   : notification_log WHERE status='FAILED' ORDER BY id ASC
      Processor: Feign 호출 → 성공 시 status='SENT', trial++ 세팅
                            실패 시 status='FAILED', trial++ 세팅
      Writer   : UPDATE notification_log SET status=:status, trial=:trial WHERE id=:id
      Chunk    : 100
```

예제 1과 동일한 Processor/Writer를 재사용하되, Reader의 날짜 조건만 제거한다.

**스케줄러 주의사항**

- `fixedRate` vs `fixedDelay`: 배치에는 **`fixedDelay`** 권장
  - `fixedRate`: 이전 실행이 끝나지 않아도 다음 실행이 시작됨
  - `fixedDelay`: 이전 실행 완료 후 N초 대기 → 중첩 실행 방지
- 동시에 같은 Job이 두 번 실행되지 않도록 `JobParameters`에 `run.id`(타임스탬프) 포함

---

### 4-3. 예제 3 — schedule 기반 영화 데이터 적재

```
MovieLoadScheduler
  @Scheduled(fixedDelay = 60_000)
  → JobLauncher.run(movieLoadJob, params)

movieLoadJob
└── [Step] movieLoadStep
      Reader   : FeignMovieItemReader (커스텀 ItemReader)
                 - 외부 API 페이징 호출, 전체 페이지 순회
      Processor: MovieTransformProcessor
                 - MovieApiDto → IfMovie 변환
                 - 이미 있으면(by external_id) → 업데이트용 세팅
                 - 없으면 → 신규 삽입용 세팅
      Writer   : UPSERT (JPA merge / MyBatis ON CONFLICT)
      Chunk    : 50 (API 응답 페이지 크기에 맞춤)
```

**FeignMovieItemReader 구조**

```java
public class FeignMovieItemReader implements ItemReader<MovieApiDto> {
    private final MovieApiClient movieApiClient;
    private Queue<MovieApiDto> buffer = new ArrayDeque<>();
    private int page = 0;
    private boolean done = false;

    @Override
    public MovieApiDto read() {
        if (!buffer.isEmpty()) return buffer.poll();
        if (done) return null;

        List<MovieApiDto> page = movieApiClient.getMovies(this.page++);
        if (page.isEmpty()) { done = true; return null; }
        buffer.addAll(page);
        return buffer.poll();
    }
}
```

> 커스텀 Reader는 `ItemStream`도 함께 구현하면 재시작 시 진행 지점부터 이어서 읽을 수 있다.  
> 외부 API 특성상 재시작 지점 보장이 어려우면 `saveState = false` 설정.

---

## 5. Skip / Retry 전략

### 5-1. 전략 선택 기준

| 상황 | 전략 |
|---|---|
| 일시적 오류 (네트워크, DB 커넥션 등) | **Retry** — 같은 요청이 성공할 수 있음 |
| 데이터 오류 (파싱 실패, 유효성 위반) | **Skip** — 재시도해도 동일하게 실패함 |
| Skip된 항목의 재처리 | Trigger: 다음 실행에 다시 FAILED로 남아있으므로 자연히 재시도됨 |

### 5-2. 예제별 정책

| 예제 | Retry | Skip | 비고 |
|---|---|---|---|
| 1 (trigger) | 3회 (HTTP 5xx, timeout) | 10건 | 스킵된 항목은 FAILED 유지 → 다음 trigger 때 재처리 |
| 2 (schedule) | 1회 | 50건 (관대하게) | 1분 뒤 스케줄이 다시 돌기 때문에 retry 자체가 의미 적음 |
| 3 (movie load) | 3회 (API 불안정) | 20건 | 변환 오류는 skip, API 오류는 retry |

### 5-3. Skip된 항목이 다시 실행되는 원리

```
[실행 1]
  Chunk: item1~100 처리
  item37, item58 → retry 3회 실패 → skip
  → item37, item58은 status='FAILED' 그대로 DB에 남음

[실행 2 - 다음 trigger or 다음 스케줄]
  Reader: status='FAILED' 다시 조회
  → item37, item58도 포함되어 재처리 시도
```

Spring Batch의 skip은 "이번 청크에서는 건너뛴다"이지, "영원히 무시한다"가 아니다.  
DB 상태가 FAILED로 유지되면 다음 실행에서 자동으로 재처리 대상이 된다.

### 5-4. 스케줄 기반에서 retry가 의미 있는 경우

스케줄 기반이라도 **동일 청크 내 retry는 필요하다**.

```
Chunk 처리 중 → item73에서 일시적 네트워크 오류
  → retry 없으면: 청크 전체 fail → item1~100 모두 미처리
  → retry 있으면: item73 재시도 → 성공 → item1~100 모두 처리 완료
```

retry는 "스케줄러의 재시도"가 아니라 "청크 내 일시 오류 흡수"를 위한 것이다.  
큰 청크일수록 retry 없이 실패하면 재처리 비용이 커진다.

---

## 6. 테스트 전략

### 6-1. 배치 테스트에서 롤백이 안 되는 이유

```
@Transactional (테스트 레벨)
  └─ Spring Batch 내부 TX 1 (청크 1, 커밋)
  └─ Spring Batch 내부 TX 2 (청크 2, 커밋)
  └─ 테스트 레벨 롤백 시도 → 이미 커밋된 TX는 되돌릴 수 없음
```

Spring Batch는 청크마다 트랜잭션을 커밋한다.  
테스트 클래스에 `@Transactional`을 붙여도 배치 내부 커밋은 막을 수 없다.

### 6-2. "롤백 없이" 테스트하는 방법들

**방법 1: H2 인메모리 DB + @BeforeEach DELETE** ← 표준 (현재 채택)

```java
@BeforeEach
void setUp() {
    jdbcTemplate.execute("DELETE FROM notification_log");
    // 테스트 데이터 insert
    insertFailed("user1"); insertFailed("user2"); // ... chunk보다 많이
}
```

- 테스트 종료 후 다음 @BeforeEach에서 clean
- 롤백이 아니라 "매 테스트 클린 슬레이트" 전략
- H2가 실제 PostgreSQL과 다른 점(타입, 함수 등)에 주의

**방법 2: Testcontainers (PostgreSQL 정확도 필요 시)**

```java
@Testcontainers
class NotificationResendJobTest {
    @Container
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16");

    @BeforeEach
    void setUp() {
        jdbcTemplate.execute("TRUNCATE TABLE notification_log");
    }
}
```

- 실제 PostgreSQL과 동일한 동작 보장
- 컨테이너 기동 시간 추가 (초기화 10~20초)
- CI/CD 환경에서도 Docker만 있으면 동작

**방법 3: WireMock (외부 API 격리)**

```java
@WireMockTest(httpPort = 8089)
class MovieLoadJobTest {
    @BeforeEach
    void stubApi() {
        stubFor(get("/api/movies?page=0")
            .willReturn(aResponse()
                .withStatus(200)
                .withBody("""
                    [{"id":"m1","title":"Inception",...}]
                    """)));
    }
}
```

- Feign 클라이언트가 실제 외부 서버 대신 WireMock으로 요청
- DB 롤백 문제와 무관하게 API 응답을 제어
- 성공/실패/타임아웃 시나리오를 쉽게 재현

**방법 4: @MockBean 으로 Feign 대체 (간단한 경우)**

```java
@SpringBootTest
class MovieLoadJobTest {
    @MockBean
    private MovieApiClient movieApiClient;

    @Test
    void 성공_영화목록_if_movie에_적재() {
        given(movieApiClient.getMovies(0))
            .willReturn(List.of(new MovieApiDto("m1", "Inception", ...)));
        given(movieApiClient.getMovies(1)).willReturn(List.of());  // 마지막 페이지
        // ...
    }
}
```

- Spring Context 내 Feign 빈만 Mock으로 대체
- WireMock보다 가볍지만 HTTP 레벨 검증 불가

### 6-3. 선택 기준 정리

| 상황 | 추천 방법 |
|---|---|
| 기본 통합 테스트 | H2 + @BeforeEach DELETE |
| PostgreSQL 특화 기능 (jsonb 등) | Testcontainers |
| 외부 API 호출 포함 | WireMock 또는 @MockBean |
| 순수 Processor 로직 테스트 | 단위 테스트 (DB 불필요) |
| 동일 DB로 여러 팀이 공유하는 환경 | 테스트 데이터 네이밍 격리 (`user_id LIKE 'TEST_%'`) |

### 6-4. 청크보다 많은 FAILED 데이터로 테스트

chunk size = 100 이면 FAILED 건수를 120~150건으로 설정해야  
"2개 청크가 나눠서 처리되는 시나리오"를 검증할 수 있다.

```java
@BeforeEach
void setUp() {
    for (int i = 0; i < 150; i++) {
        insertFailed("user_" + i);
    }
}

@Test
void 성공_150건_FAILED_모두_SENT_처리() throws Exception {
    JobExecution execution = launch();
    assertThat(execution.getStatus()).isEqualTo(BatchStatus.COMPLETED);
    assertThat(countByStatus("SENT")).isEqualTo(150);
    assertThat(countByStatus("FAILED")).isEqualTo(0);
    // 2 chunks × 100 + 50: readCount = 150, writeCount = 150 검증
}
```

---

## 7. 패키지 구조 (제안)

```
job/
├── notification/
│   ├── domain/
│   │   └── NotificationLog.java           # @Entity 또는 MyBatis 도메인
│   ├── mybatis/
│   │   └── NotificationLogMapper.java
│   ├── client/
│   │   └── NotificationApiClient.java     # Feign 인터페이스
│   ├── scheduler/
│   │   └── NotificationResendScheduler.java
│   ├── NotificationResendJobConfig.java         # 예제 1 (trigger)
│   └── ScheduledNotificationResendJobConfig.java # 예제 2 (schedule)
│
└── movie/
    ├── domain/
    │   └── IfMovie.java
    ├── mybatis/
    │   └── IfMovieMapper.java
    ├── client/
    │   └── MovieApiClient.java
    │   └── dto/
    │       └── MovieApiDto.java
    ├── reader/
    │   └── FeignMovieItemReader.java
    ├── scheduler/
    │   └── MovieLoadScheduler.java
    └── MovieLoadJobConfig.java              # 예제 3
```

---

## 8. 구현 계획

| 순서 | 작업 |
|---|---|
| 1 | 테이블 DDL 작성 및 Docker Compose 반영 |
| 2 | 도메인 클래스 (NotificationLog, IfMovie) |
| 3 | Mapper / Repository |
| 4 | Feign 클라이언트 인터페이스 |
| 5 | Job Config (JPA 버전) |
| 6 | Job Config (MyBatis 버전) |
| 7 | 스케줄러 |
| 8 | 테스트 (WireMock + H2) |
