---
title: "2. 재실행 원리"
weight: 2
date: 2026-05-15
---

> Spring Batch에서 "다시 실행"은 두 가지 의미로 나뉜다.
> `run.id` 같은 파라미터를 바꿔 **새 JobInstance**를 만드는 방식과,
> 실패/중단된 `JobExecution`을 `restart`로 **이어서 실행**하는 방식이다.

---

## 1. 핵심 모델

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

## 4. 현재 프로젝트의 실행 방식

현재 `spring-batch-practice`는 실행 API와 스케줄러에서 `run.id`를 매번 새로 넣는다.

### 4-1. Admin API 실행

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

### 4-2. 스케줄러 실행

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

## 5. 현재 프로젝트의 재시작 방식

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

## 6. 결론

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
- `spring-batch-practice/batch-common/src/main/java/com/example/spring_batch_practice/core/api/BatchJobService.java`
- `spring-batch-practice/batch-common/src/main/java/com/example/spring_batch_practice/core/api/BatchAdminController.java`
- `spring-batch-practice/batch-common/src/main/java/com/example/spring_batch_practice/job/movie/scheduler/MovieLoadScheduler.java`
- `spring-batch-practice/batch-common/src/main/java/com/example/spring_batch_practice/job/notification/scheduler/NotificationResendScheduler.java`
