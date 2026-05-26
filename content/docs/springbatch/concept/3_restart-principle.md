---
title: "3. 재실행 원리"
weight: 3
date: 2026-05-15
---

> Spring Batch에서 "다시 실행"은 두 가지 의미로 나뉜다.
> `run.id` 같은 파라미터를 바꿔 **새 JobInstance**를 만드는 방식과,
> 실패/중단된 `JobExecution`을 `restart`로 **이어서 실행**하는 방식이다.

---

## 1. 실행 단위

Spring Batch의 실행 단위는 다음 관계로 이해하면 된다.

```
Job
└── JobInstance
    └── JobExecution
        └── StepExecution
```

| 개념 | 의미 |
|---|---|
| `Job` | 배치 작업의 정의. 예: `movieLoadJpaJob` |
| `JobInstance` | 특정 파라미터로 식별되는 Job의 논리 실행 단위 |
| `JobExecution` | JobInstance를 실제로 실행한 1회 시도 |
| `StepExecution` | Step을 실제로 실행한 1회 시도 |

Spring Batch 공식 정의는 다음과 같다.

```text
JobInstance = Job + identifying JobParameters
```

즉, 같은 Job이라도 identifying JobParameters가 다르면 다른 JobInstance다.

---

## 2. `run.id`와 `executionId`는 다르다

### 2-1. `run.id`

`run.id`는 Spring Batch가 자동으로 특별 취급하는 ID가 아니다.
그냥 JobParameters 중 하나다.

```java
new JobParametersBuilder()
        .addLong("run.id", System.currentTimeMillis())
        .toJobParameters();
```

`run.id`가 identifying parameter로 들어가면 JobInstance 식별값에 포함된다.
따라서 `run.id`가 바뀌면 같은 Job이라도 새 JobInstance가 된다.

### 2-1-1. run.id 생성 방식 혼용 금지

`run.id`를 생성하는 방식은 두 가지다.

| 방식 | 동작 |
|---|---|
| `addLong("run.id", currentTimeMillis())` 직접 주입 | 호출할 때마다 밀리스 타임스탬프 삽입 |
| `RunIdIncrementer` + `JobOperator.startNextInstance()` | 직전 `run.id` + 1 |

`RunIdIncrementer` 내부는 다음과 같다.

```java
public JobParameters getNext(JobParameters parameters) {
    long id = parameters.getLong("run.id", 0L) + 1;
    return new JobParametersBuilder(parameters)
            .addLong("run.id", id)
            .toJobParameters();
}
```

**혼용하면 다음과 같이 깨진다.**

스케줄러에서 밀리스 타임스탬프로 실행하다가 `RunIdIncrementer` 방식으로 전환한다고 가정한다.

```text
실행 1: run.id = 1_716_000_000_000  (밀리스)
실행 2: run.id = 1_716_000_000_001  (RunIdIncrementer → 직전값 + 1)
실행 3: run.id = 1_716_000_000_002
...
```

`RunIdIncrementer`가 직전 `run.id`를 읽어서 +1 하므로 순번이 아니라 밀리스 단위 숫자를 이어간다.
"몇 번째 실행인지" 순번으로 추적하려던 의도가 완전히 깨진다.

반대로 `RunIdIncrementer`로 운영하다가 중간에 밀리스를 직접 주입하면 순번이 수백억 단위로 점프한다.

**한 Job의 `run.id` 생성 방식은 처음부터 하나로 통일해야 한다.**

---

### 2-2. `executionId`

`executionId`는 `BATCH_JOB_EXECUTION`에 저장되는 JobExecution의 ID다.
실행 시도 1번마다 새로 생긴다.

예시는 다음과 같다.

```text
jobName = sampleJpaJob
run.id  = 100

JobInstance #1
├── JobExecution #10  실패
└── JobExecution #11  restart
```

여기서 `run.id=100`은 그대로지만, 재시작하면 `executionId`는 새로 생길 수 있다.

---

## 3. 같은 파라미터로 다시 실행할 수 있는가

상태에 따라 다르다.

| 이전 상태 | 같은 JobName + 같은 identifying JobParameters 실행 |
|---|---|
| `COMPLETED` | 불가. 이미 완료된 JobInstance |
| `FAILED` | 가능. 재시작 대상 |
| `STOPPED` | 가능. 재시작 대상 |
| `STARTED` | 불가. 이미 실행 중 |

중요한 점은 같은 파라미터로 다시 실행하는 것이 항상 "새 실행"은 아니라는 점이다.
실패/중단된 JobInstance에 대해 같은 파라미터로 실행하면 재시작 의미가 된다.

반대로 매번 `run.id`를 바꾸면 기존 실패 지점부터 이어서 처리하지 않는다.
새 JobInstance를 만든다.

---

## 4. chunk 실패와 skip의 재처리 기준

재실행을 이해할 때 가장 헷갈리는 지점은 **chunk 실패**와 **skip**이다.
둘은 재처리 기준이 다르다.

예를 들어 다음 Job이 있다고 가정한다.

```text
전체 item: 1000건
chunk size: 10
총 chunk: 100개
21번째 chunk 처리 중 문제 발생
```

### 4.1. chunk 자체가 실패한 경우

21번째 chunk 처리 중 예외가 발생했고 skip되지 못해 Step이 `FAILED` 됐다고 하자.

이 경우 commit 상태는 다음과 같다.

```text
1~20 chunk: commit 완료
21 chunk: rollback
22~100 chunk: 실행 안 됨
```

재시작하면 Spring Batch는 업무 테이블의 `status`를 보고 21번째 chunk를 찾는 것이 아니다.
`BATCH_STEP_EXECUTION_CONTEXT`에 저장된 reader checkpoint를 보고 마지막 commit 지점 이후부터 다시 읽는다.

대략 다음 의미다.

```text
1~200번째 item 처리 완료
201번째 item부터 재시작
```

이 동작은 reader가 restartable해야 가능하다.
`FlatFileItemReader`, `JdbcCursorItemReader`, `JdbcPagingItemReader` 같은 Spring Batch reader는
보통 `ExecutionContext`에 현재 위치를 저장해 재시작할 수 있다.

#### 4.1.1. 재시작 전 데이터가 바뀌면 어떻게 되는가

reader checkpoint는 "200번째 item까지 처리했다" 같은 위치 정보를 저장할 수 있다.
하지만 그 사이 업무 테이블의 데이터가 바뀌면 문제가 생길 수 있다.

예:

```text
실패 당시:
  1~200번째 item commit 완료
  restart 지점 = 201번째 item

재시작 전:
  앞쪽 데이터가 삭제됨
  앞쪽 데이터의 status가 바뀜
  새 처리 대상 row가 앞쪽 범위에 추가됨
```

이 경우 단순히 "201번째부터 다시 읽는다"는 방식은 재시작 전과 같은 데이터를 가리킨다고 보장할 수 없다.
특히 `OFFSET/LIMIT` 기반 paging reader는 앞쪽 row가 추가/삭제되면 페이지가 밀릴 수 있다.

대응 방식은 Job 성격에 따라 다르다.

| 방식 | 설명 |
|---|---|
| 처리 대상 snapshot 고정 | Job 시작 시 대상 ID 목록 또는 기준 시각을 고정 |
| stable ordering 사용 | `ORDER BY id`처럼 변하지 않는 정렬 기준 사용 |
| keyset 방식 | `lastProcessedId` 이후를 읽는 식으로 offset 밀림 회피 |
| 처리 상태 전이 | 읽은 row를 `PROCESSING`/`DONE`으로 바꿔 재조회 기준 명확화 |
| 업무 멱등성 보장 | 같은 row가 다시 처리돼도 결과가 중복되지 않게 설계 |
| cursor reader 검토 | 단순 paging보다 실행 중 데이터 변경에 덜 취약한 reader 선택 |

정리하면, Spring Batch meta table은 **어디서 재시작할지**를 기억한다.
하지만 업무 데이터가 재시작 전과 같은 순서/상태로 남아 있다는 것은 보장하지 않는다.
그 보장은 reader 쿼리, 정렬 기준, 업무 상태 모델, 멱등성 설계로 만들어야 한다.

### 4.2. skip된 경우

skip은 다르다.
skip은 "이번 chunk에서 이 item을 건너뛰고 나머지를 계속 처리한다"는 의미다.

예를 들어 21번째 chunk 안의 1개 item이 skip 가능한 예외를 냈고,
skip limit을 넘지 않았다고 하자.

```text
21번째 chunk 전체 실패 아님
문제 item만 skip
나머지 item은 commit
Step은 계속 진행
Job은 COMPLETED 될 수 있음
```

이때 Spring Batch meta table에는 skip count 같은 실행 통계가 남는다.
하지만 Spring Batch가 skip된 item을 "다음 실행에서 자동 재처리할 목록"으로 따로 기억하는 것은 아니다.

skip된 item이 다음 실행에서 다시 잡히는지는 reader의 대상 선정 조건에 달려 있다.

예를 들어 업무 테이블이 다음 상태를 가진다고 하자.

```text
notification_log.status = FAILED
```

reader가 다음처럼 되어 있으면:

```sql
select *
from notification_log
where status = 'FAILED'
```

skip된 item은 업무 상태가 여전히 `FAILED`라서 다음 새 JobInstance 실행 때 다시 읽힌다.
반대로 processor나 writer에서 `SKIPPED`, `INVALID`, `ERROR_HANDLED` 같은 상태로 바꿔두면 다음 실행에서 제외될 수 있다.

정리하면 다음과 같다.

| 상황 | 재처리 기준 |
|---|---|
| chunk 실패로 Step `FAILED` 후 restart | Spring Batch meta table의 `ExecutionContext` |
| skip 후 Job `COMPLETED`, 다음 새 실행 | reader 쿼리와 업무 DB 상태 |
| skip item만 자동 추적해서 재처리 | Spring Batch 기본 기능 아님 |
| 업무 상태 `FAILED` 재조회 | 애플리케이션 설계 |

따라서 "skip은 이번 chunk에서 건너뛴다"는 말은 맞지만,
"영원히 무시한다"는 뜻은 아니다.
다음 실행에서 다시 읽힐지는 업무 테이블 상태와 reader 조건이 결정한다.

---

## 5. 현재 프로젝트의 실행 방식

현재 `spring-batch-practice`는 실행 API와 스케줄러에서 `run.id`를 매번 새로 넣는다.

### 5-1. Admin API 실행

`POST /admin/batch/jobs/{jobName}/run`

```java
public Long run(String jobName, Map<String, String> params) throws Exception {
    Job job = jobRegistry.getJob(jobName);
    JobParametersBuilder builder = new JobParametersBuilder();
    params.forEach(builder::addString);

    if (!params.containsKey("run.id")) {
        builder.addLong("run.id", System.currentTimeMillis());
    }

    return jobLauncher.run(job, builder.toJobParameters()).getId();
}
```

`run.id`를 요청에서 넘기지 않으면 현재 시간으로 자동 추가한다.
따라서 일반적인 `/run` 호출은 매번 새 JobInstance다.

### 5-2. 스케줄러 실행

스케줄러도 같은 방식이다.

```java
JobParameters params = new JobParametersBuilder()
        .addLong("run.id", System.currentTimeMillis())
        .toJobParameters();

jobLauncher.run(movieLoadJpaJob, params);
```

스케줄이 돌 때마다 `run.id`가 달라진다.
따라서 스케줄 실행도 매번 새 JobInstance다.

---

## 6. 현재 프로젝트의 재시작 방식

진짜 재시작은 별도 API로 분리되어 있다.

```java
@PostMapping("/executions/{executionId}/restart")
public ResponseEntity<Long> restart(@PathVariable Long executionId) throws Exception {
    return ResponseEntity.ok(batchJobService.restart(executionId));
}
```

서비스에서는 `JobOperator.restart(executionId)`를 호출한다.

```java
public Long restart(Long executionId) throws Exception {
    return jobOperator.restart(executionId);
}
```

이 방식은 새 `run.id`를 넣지 않는다.
기존 실패/중단 JobExecution의 `executionId`를 기준으로 Spring Batch가 재시작한다.

---

## 7. 결론

| 실행 경로 | 현재 동작 | 의미 |
|---|---|---|
| `/admin/batch/jobs/{jobName}/run` | `run.id` 없으면 현재 시간 추가 | 매번 새 JobInstance |
| `MovieLoadScheduler` | `run.id = System.currentTimeMillis()` | 매번 새 JobInstance |
| `NotificationResendScheduler` | `run.id = System.currentTimeMillis()` | 매번 새 JobInstance |
| `/admin/batch/executions/{executionId}/restart` | `JobOperator.restart(executionId)` | 실패/중단 실행 재시작 |

운영 기준으로는 다음처럼 구분한다.

```text
새 업무 실행이 필요함      → /run
실패한 실행을 이어야 함    → /restart
완료된 실행을 다시 돌림    → 새 run.id로 /run
실패 지점부터 이어서 처리  → 기존 executionId로 /restart
```

---

## 참고

- [Spring Batch Reference - Domain Language of Batch](https://docs.spring.io/spring-batch/reference/domain.html)
- [Spring Batch API - JobOperator](https://docs.spring.io/spring-batch/reference/api/org/springframework/batch/core/launch/JobOperator.html)
- [spring-batch-practice](https://github.com/kimtks456/spring-batch-practice)
  - `batch-common/src/main/java/com/example/spring_batch_practice/core/api/BatchJobService.java`
  - `batch-common/src/main/java/com/example/spring_batch_practice/core/api/BatchAdminController.java`
  - `batch-common/src/main/java/com/example/spring_batch_practice/job/movie/scheduler/MovieLoadScheduler.java`
  - `batch-common/src/main/java/com/example/spring_batch_practice/job/notification/scheduler/NotificationResendScheduler.java`
