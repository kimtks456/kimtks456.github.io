---
title: "1. 스케줄러 조사"
weight: 1
date: 2026-05-14
---

> 배치 공통 플랫폼 구축 시 필요한 **자동 스케줄링**과 **중복 실행 방지** 솔루션을 비교·분석한다.
> 선택 기준은 Spring Batch와의 통합 난이도, 별도 인프라 필요 여부, 중복 실행 방지 메커니즘이다.

---

## 1. 핵심 요구사항

| 요구사항 | 설명 |
|---|---|
| 자동 스케줄링 | 특정 시간에 Job 자동 실행 (cron 표현식) |
| 중복 실행 방지 | 같은 Job이 동시에 2개 이상 실행되는 것 차단 |
| 런타임 변경 | 배포 없이 스케줄 cron 변경 가능 여부 |
| 인프라 비용 | 별도 서버/플랫폼 없이 애플리케이션 내장 가능 여부 |

---

## 2. 선택지별 분석

### 2-1. `@Scheduled` + ShedLock

```
Spring Batch App
├── @Scheduled(cron = "0 0 2 * * *")   ← 스케줄
└── @SchedulerLock(name = "jobName")   ← 중복 방지 (DB 락)
```

**동작 원리**
- `@Scheduled`로 JVM 내 스레드 풀에서 cron 실행
- ShedLock이 DB(또는 Redis, Mongo)에 Lock Row를 삽입하여 같은 이름의 Lock을 잡은 인스턴스만 실행
- 다른 인스턴스는 Lock 획득 실패 → 즉시 skip

**중복 방지 방식**: DB Row 삽입 (낙관적 락)

| 항목 | 평가 |
|---|---|
| 설정 복잡도 | 매우 낮음 (의존성 1개, 어노테이션 2개) |
| 런타임 스케줄 변경 | 불가 (코드/배포 필요) |
| 별도 인프라 | 불필요 |
| 중복 방지 신뢰도 | 높음 (DB Row 기반) |
| 모니터링 UI | 없음 |

**적합 케이스**: 단일/소규모 인스턴스, 스케줄 변경 빈도 낮음

---

### 2-2. Quartz Scheduler (Clustered mode)

```
Spring Batch App (N개 인스턴스)
└── Quartz Cluster
    ├── QRTZ_JOB_DETAILS      ← Job 정의 저장
    ├── QRTZ_TRIGGERS         ← 스케줄(cron) 저장
    ├── QRTZ_LOCKS            ← 분산 락 (중복 방지)
    └── QRTZ_FIRED_TRIGGERS   ← 실행 이력
```

**동작 원리**
- 스케줄 정보를 DB에 저장 → 런타임에 변경 가능
- Cluster 모드에서 인스턴스 간 `QRTZ_LOCKS` 테이블의 행 수준 비관적 락(SELECT FOR UPDATE)으로 하나의 인스턴스만 트리거를 실행
- Misfire 처리 내장: 서버 다운 후 복구 시 밀린 Job을 어떻게 처리할지 정책 설정 가능

**중복 방지 방식**: `QRTZ_LOCKS` 비관적 락 (DB SELECT FOR UPDATE)

| 항목 | 평가 |
|---|---|
| 설정 복잡도 | 높음 (QRTZ_* 테이블 DDL, DataSource 설정, Cluster 설정) |
| 런타임 스케줄 변경 | 가능 (DB Trigger 직접 수정 또는 Scheduler API 호출) |
| 별도 인프라 | 불필요 (DB만 공유하면 됨) |
| 중복 방지 신뢰도 | 매우 높음 (비관적 락) |
| 모니터링 UI | 별도 구현 필요 (quartz-ui, 커스텀 Admin API 등) |
| Misfire 처리 | 내장 정책 제공 |

**적합 케이스**: 멀티 인스턴스, 런타임 스케줄 변경 필요, 운영 환경

---

### 2-3. Jenkins

```
Jenkins (외부 서버)
├── Pipeline cron trigger      ← 스케줄
├── Throttle Builds 플러그인    ← 중복 방지
└── HTTP / fat-jar exec        ← Spring Batch App 호출
```

**동작 원리**
- Jenkins가 cron에 따라 Spring Batch 애플리케이션을 HTTP 또는 shell로 호출
- Throttle Concurrent Builds 플러그인으로 동시 실행 제한
- 배치 앱은 "피호출자"가 되며, REST API 또는 실행 가능한 jar 형태로 노출되어야 함

**중복 방지 방식**: Jenkins 플러그인 레벨 (애플리케이션 외부)

| 항목 | 평가 |
|---|---|
| 설정 복잡도 | 높음 (Jenkins 서버 구축, Pipeline 작성) |
| 런타임 스케줄 변경 | 가능 (Jenkins UI) |
| 별도 인프라 | **필요** (Jenkins 서버) |
| 중복 방지 신뢰도 | 중간 (플러그인 의존, 앱 레벨 락 아님) |
| 모니터링 UI | 강력 (실행 이력, 로그, 파이프라인 뷰) |
| 파이프라인 의존 관계 | 표현 가능 (A 완료 후 B 실행) |

**적합 케이스**: 여러 팀이 공유하는 배치, 복잡한 Job 의존 관계, 이미 Jenkins 인프라 존재

---

### 2-4. Spring Cloud Data Flow (SCDF)

```
SCDF Server (K8s or Cloud Foundry)
├── Scheduler (cron)          ← 스케줄
├── Task Execution History    ← 실행 이력
└── Spring Cloud Task App     ← 배치 앱 (이미 의존성 있음)
```

**동작 원리**
- Spring Cloud Task(`spring-cloud-starter-task`)와 긴밀하게 통합
- K8s CronJob 또는 Cloud Foundry Task로 배치를 실행
- SCDF UI에서 스케줄 관리, 실행 이력 확인 가능

| 항목 | 평가 |
|---|---|
| 설정 복잡도 | 매우 높음 (K8s 또는 Cloud Foundry 필수) |
| 런타임 스케줄 변경 | 가능 |
| 별도 인프라 | **필수** (SCDF 서버 + K8s) |
| 중복 방지 신뢰도 | 높음 |
| 모니터링 UI | 강력 |

**적합 케이스**: 이미 K8s 운영 중, 클라우드 네이티브 환경

---

## 3. 비교 요약

| 항목 | `@Scheduled` + ShedLock | Quartz (Clustered) | Jenkins | SCDF |
|---|:---:|:---:|:---:|:---:|
| 런타임 스케줄 변경 | ✗ | ✅ | ✅ | ✅ |
| 중복 방지 | ✅ | ✅ | △ | ✅ |
| 별도 인프라 불필요 | ✅ | ✅ | ✗ | ✗ |
| 설정 난이도 | 쉬움 | 보통 | 높음 | 매우 높음 |
| 모니터링 UI | ✗ | △ | ✅ | ✅ |
| Misfire 처리 | ✗ | ✅ | △ | ✅ |
| Spring Batch 통합 | ✅ | ✅ | △ | ✅ |

---

## 4. 결론 및 선택

```
토이 프로젝트 / 단일 인스턴스  →  @Scheduled + ShedLock
프로덕션 / 멀티 인스턴스       →  Quartz Clustered
외부 오케스트레이션 필요        →  Jenkins (Quartz와 병행 가능)
K8s 환경                     →  SCDF
```

**Quartz Clustered 선택**

이유:
1. **런타임 스케줄 변경**: `QRTZ_TRIGGERS` 테이블 직접 수정 또는 `Scheduler.rescheduleJob()`으로 재배포 없이 cron 수정 가능
2. **신뢰도 높은 중복 방지**: `QRTZ_LOCKS` SELECT FOR UPDATE로 동시 실행 원천 차단
3. **Misfire 처리 내장**: `@DisallowConcurrentExecution` + Misfire 정책 조합으로 서버 다운 후 시나리오 대응
4. **별도 인프라 불필요**: 이미 사용 중인 PostgreSQL을 JobStore로 사용 가능
5. **공통화 용이**: `batch-common` 모듈에 `QuartzConfig` + `BaseQuartzJob` 추상 클래스 정의 → 각 Job은 `JobDetail` 빈만 등록

Jenkins는 "여러 팀이 Job 실행 이력을 UI로 봐야 할 때" 추가하는 레이어이며, Quartz와 배타적이지 않다.

---

## 5. Quartz Clustered 적용 시 고려 사항

### 5-1. 필요한 테이블 (PostgreSQL)

Quartz가 관리하는 11개의 `QRTZ_*` 테이블 DDL을 별도로 관리해야 한다.
공식 배포 파일: `quartz-x.x.x/docs/dbTables/tables_postgres.sql`

```sql
-- 핵심 테이블 (일부)
QRTZ_JOB_DETAILS     -- Job 정의
QRTZ_TRIGGERS        -- 트리거(cron 등)
QRTZ_CRON_TRIGGERS   -- cron 표현식
QRTZ_FIRED_TRIGGERS  -- 실행 중/완료 이력
QRTZ_LOCKS           -- 분산 락
```

### 5-2. Spring Batch와의 DataSource 분리

Spring Batch 메타 테이블(`BATCH_*`)과 Quartz 테이블(`QRTZ_*`)이 같은 DB를 사용한다면,
Quartz의 `JobStoreTX`가 Batch 트랜잭션을 간섭하지 않도록 DataSource를 분리하거나
`@QuartzDataSource` 한정자를 사용하여 별도 DataSource로 지정하는 것을 권장한다.

### 5-3. `@DisallowConcurrentExecution`

`QuartzJobBean`을 상속한 Job 클래스에 이 어노테이션을 붙이면
이전 실행이 완료되지 않은 경우 다음 트리거 실행을 건너뛰어 중복 실행을 애플리케이션 레벨에서 한 번 더 방지한다.
`QRTZ_LOCKS` 분산 락과 이중으로 보호하는 구조가 된다.

```java
@DisallowConcurrentExecution
public class SampleQuartzJob extends QuartzJobBean {
    @Override
    protected void executeInternal(JobExecutionContext context) {
        // JobLauncher.run(job, params) 호출
    }
}
```

---

## 참고

- [Quartz Scheduler Documentation](http://www.quartz-scheduler.org/documentation/)
- [ShedLock GitHub](https://github.com/lukas-krecan/ShedLock)
- [Spring Boot + Quartz Integration Guide](https://docs.spring.io/spring-boot/reference/io/quartz.html)
