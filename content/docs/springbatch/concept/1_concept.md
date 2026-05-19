---
title: "1. 개념 정리"
weight: 1
date: 2026-05-20
---

## 1. Job / JobInstance / JobExecution

```
Job
└── JobInstance  (Job + identifying JobParameters)
    └── JobExecution  (1회 실행 시도)
        └── StepExecution
```

| 개념 | 설명 |
|---|---|
| `Job` | 배치 작업 정의. 코드로 설정한 불변 객체 |
| `JobInstance` | `Job + identifying JobParameters` 조합으로 식별되는 논리 실행 단위 |
| `JobExecution` | JobInstance를 실제로 실행한 1회 시도. 성공/실패 여부와 무관하게 생성 |
| `StepExecution` | Step을 실제로 실행한 1회 시도 |

---

## 2. Step

Job을 구성하는 독립적인 처리 단위. 두 가지 모델이 있다.

### Chunk-oriented Step

Reader → Processor → Writer를 묶어 chunk 단위로 처리한다.

```
Reader.read() × chunkSize → Processor.process() × N → Writer.write(List)
```

- Reader가 `null`을 반환하면 해당 chunk 종료
- 한 chunk가 끝나면 트랜잭션 커밋
- Writer는 chunk 단위 List를 한 번에 받는다

### Tasklet Step

단일 작업(파일 이동, 테이블 truncate 등)에 사용. `Tasklet.execute()`가 `RepeatStatus.FINISHED`를 반환할 때까지 반복 호출된다.

---

## 3. JobParameters

Job 실행 시 전달하는 파라미터. `identifying` 여부에 따라 JobInstance 식별에 포함될지 결정된다.

- Spring Batch 5부터 모든 파라미터가 기본적으로 `identifying = true`
- `identifying = false`로 설정하면 JobInstance 식별에서 제외

---

## 4. ExecutionContext

Step 또는 Job 실행 중 상태를 저장하는 key-value 저장소. 재시작 시 이전 상태를 복원하는 데 사용한다.

| 범위 | 설명 |
|---|---|
| `StepExecution.executionContext` | 해당 Step 범위 |
| `JobExecution.executionContext` | Job 전체 범위. Step 간 데이터 공유 가능 |

---

## 5. JobRepository

배치 메타데이터(JobInstance, JobExecution, StepExecution 등)를 DB에 저장·조회하는 인터페이스. 기본적으로 아래 테이블을 사용한다.

```
BATCH_JOB_INSTANCE
BATCH_JOB_EXECUTION
BATCH_JOB_EXECUTION_PARAMS
BATCH_STEP_EXECUTION
BATCH_STEP_EXECUTION_CONTEXT
BATCH_JOB_EXECUTION_CONTEXT
```

---

## 6. JobLauncher / JobOperator

| 인터페이스 | 역할 |
|---|---|
| `JobLauncher` | `Job + JobParameters`를 받아 실행. 새 JobExecution 생성 |
| `JobOperator` | 실행 중인 Job 조회, 중단, 재시작 등 운영 작업. `restart(executionId)`로 기존 실패 실행 재시작 |

---

## 7. BatchStatus / ExitStatus

| 개념 | 설명 |
|---|---|
| `BatchStatus` | Spring Batch 내부 상태 머신. `COMPLETED`, `FAILED`, `STOPPED` 등 |
| `ExitStatus` | 외부에 노출되는 종료 코드. 커스텀 가능 (`exitCode`, `exitDescription`) |

`BatchStatus.COMPLETED` 이면서 `ExitStatus.exitCode`를 `"NO_TARGET"` 등 커스텀 값으로 설정하는 것이 가능하다.

## 8. 반복

### 8.1. Repeat

`RepeatTemplate`이 `RepeatCallback`을 반복 호출하고, `CompletionPolicy`와 `ExceptionHandler`로 종료·오류 처리를 결정하는 구조다.

```
«interface»
RepeatOperations
    └── RepeatTemplate
            ├── iterate(RepeatCallback)   ← 반복 실행 진입점
            ├── CompletionPolicy          ← 반복 종료 조건 판단
            └── ExceptionHandler          ← 예외 발생 시 처리 전략

RepeatCallback
    └── doInIteration(RepeatContext) : RepeatStatus

RepeatContext
    └── 반복 회차별 상태 저장 (속성 key-value, 부모 Context 참조)

RepeatStatus  (enum)
    ├── CONTINUABLE   ← 다음 회차 계속
    └── FINISHED      ← 반복 종료
```

| 클래스 / 인터페이스 | 역할 |
|---|---|
| `RepeatOperations` | 반복 실행의 최상위 인터페이스. `iterate(RepeatCallback)` 한 메서드만 정의 |
| `RepeatTemplate` | `RepeatOperations`의 기본 구현체. `CompletionPolicy`와 `ExceptionHandler`를 조립해 반복 루프를 구동 |
| `RepeatCallback` | 매 회차 실행할 로직을 담는 콜백. `doInIteration(RepeatContext)`가 `RepeatStatus`를 반환 |
| `RepeatContext` | 반복 회차별 상태 저장소. 속성 key-value와 부모 Context 참조를 가짐 |
| `RepeatStatus` | 콜백 실행 결과. `CONTINUABLE`이면 다음 회차, `FINISHED`이면 루프 종료 |
| `CompletionPolicy` | 반복 종료 조건을 판단. `SimpleCompletionPolicy`(횟수 제한), `TimeoutTerminationPolicy`(시간 제한) 등 |
| `ExceptionHandler` | 반복 중 예외 발생 시 처리 전략. 기본 구현은 예외를 그대로 전파 |

반복 종료는 세 가지 중 하나로 결정된다.

1. `RepeatStatus.FINISHED` — 콜백이 직접 종료를 선언
2. `CompletionPolicy` — 외부에서 횟수·시간 등 조건으로 종료 판단
3. `ExceptionHandler` — 예외를 전파하여 루프 탈출

### 8.2. 배치 적용 예시

`RepeatTemplate`을 Tasklet 안에서 직접 사용하는 패턴이 가장 일반적이다.
아래 예시는 API를 최대 10번 폴링하다가 결과가 오면 조기 종료한다.

```java
@Bean
public Step pollResultStep(JobRepository jobRepository, PlatformTransactionManager txManager) {
    return new StepBuilder("pollResultStep", jobRepository)
            .tasklet((contribution, chunkContext) -> {
                RepeatTemplate template = new RepeatTemplate();
                // 최대 10회, 조기 종료는 콜백 내부에서 FINISHED 반환으로 처리
                template.setCompletionPolicy(new SimpleCompletionPolicy(10));
                template.setExceptionHandler(new DefaultExceptionHandler()); // 예외 즉시 전파

                template.iterate(context -> {
                    boolean done = externalApi.isReady();
                    if (done) {
                        return RepeatStatus.FINISHED;   // 조기 종료
                    }
                    Thread.sleep(1_000);
                    return RepeatStatus.CONTINUABLE;    // 다음 회차
                });

                return RepeatStatus.FINISHED;
            }, txManager)
            .build();
}
```

`CompletionPolicy`를 조합할 때는 `CompositeCompletionPolicy`로 여러 조건을 AND/OR로 묶을 수 있다.

```java
CompositeCompletionPolicy composite = new CompositeCompletionPolicy();
composite.setPolicies(new CompletionPolicy[]{
    new SimpleCompletionPolicy(10),          // 최대 10회
    new TimeoutTerminationPolicy(5_000)      // 또는 5초 초과
});
template.setCompletionPolicy(composite);    // 둘 중 하나라도 true면 종료
```

### 8.3. 일반 활용 예시

#### 8.3.1. 횟수 제한 재시도

외부 시스템 호출 실패 시 최대 N회 재시도하는 패턴이다.
`ExceptionHandler`를 바꿔 끼우면 특정 예외만 재시도하거나 무조건 전파하는 등 세밀하게 제어할 수 있다.

```java
RepeatTemplate template = new RepeatTemplate();
template.setCompletionPolicy(new SimpleCompletionPolicy(3)); // 최대 3회

AtomicBoolean succeeded = new AtomicBoolean(false);
template.iterate(context -> {
    try {
        externalService.call();
        succeeded.set(true);
        return RepeatStatus.FINISHED;
    } catch (TransientException e) {
        log.warn("재시도 {}/3", context.getStartedCount() + 1);
        return RepeatStatus.CONTINUABLE;
    }
});

if (!succeeded.get()) {
    throw new BatchException("3회 재시도 후 실패");
}
```

#### 8.3.2. 시간 제한 드레인

큐나 테이블에 쌓인 항목을 정해진 시간 동안 소진하는 패턴이다.
시간이 끝나면 남은 항목은 다음 배치 실행에 처리된다.

```java
RepeatTemplate template = new RepeatTemplate();
template.setCompletionPolicy(new TimeoutTerminationPolicy(30_000)); // 30초

template.iterate(context -> {
    MyTask task = taskQueue.poll();
    if (task == null) {
        return RepeatStatus.FINISHED; // 큐 소진
    }
    worker.process(task);
    return RepeatStatus.CONTINUABLE;
});
```

---

### 8.4. Watcher-Worker 모델 적용 가능성

Watcher-Worker 모델은 Watcher가 새 작업을 감시하고, Worker가 꺼내서 처리하는 구조다.

```
Watcher Loop
    ├── 새 작업 감지 (DB polling / 큐 polling)
    └── Worker.execute(task)
```

`RepeatTemplate`은 이 Watcher Loop의 골격으로 활용할 수 있다.
`iterate` 콜백이 "확인 → 처리 → 계속 여부 반환"을 한 회차로 담당하고,
`CompletionPolicy`가 루프 종료 시점을 외부에서 제어한다.

```java
// Watcher Tasklet: DB에서 PENDING 상태의 작업을 꺼내 Worker에 위임
@Bean
public Step watcherStep(JobRepository jobRepository, PlatformTransactionManager txManager) {
    return new StepBuilder("watcherStep", jobRepository)
            .tasklet((contribution, chunkContext) -> {
                RepeatTemplate template = new RepeatTemplate();

                // Watcher는 지정 시간(5분) 동안 루프, 그 안에서 빈 큐면 FINISHED로 조기 종료
                template.setCompletionPolicy(new TimeoutTerminationPolicy(300_000));

                template.iterate(context -> {
                    List<Task> tasks = taskRepository.findTop10ByStatusOrderByCreatedAt(PENDING);
                    if (tasks.isEmpty()) {
                        return RepeatStatus.FINISHED; // 처리할 작업 없음 → 루프 종료
                    }
                    tasks.forEach(worker::execute);   // Worker에 위임
                    return RepeatStatus.CONTINUABLE;  // 다음 배치 확인
                });

                return RepeatStatus.FINISHED;
            }, txManager)
            .build();
}
```

**적합한 케이스와 한계**

| 항목 | 내용 |
|---|---|
| 적합 | 배치 윈도 안에서 DB/큐를 드레인하는 단순 Watcher |
| 적합 | 외부 이벤트 완료를 폴링으로 기다리는 단계 |
| 한계 | 진짜 이벤트 드리븐이 필요하면 Kafka Consumer / SQS 리스너가 적합 |
| 한계 | Watcher와 Worker를 물리적으로 분리(별도 스레드/프로세스)해야 한다면 `RepeatTemplate`만으로는 부족 |

핵심은 `RepeatTemplate`이 **동기 폴링 루프**라는 점이다.
Watcher와 Worker가 같은 스레드에서 순차 실행되어도 무방한 경우에 잘 맞는다.
비동기 처리나 Worker 병렬 확장이 필요한 구조라면 Spring Batch의 `AsyncItemProcessor` / `Partitioned Step` 조합이 더 적합하다.

## 9. 오류 제어
