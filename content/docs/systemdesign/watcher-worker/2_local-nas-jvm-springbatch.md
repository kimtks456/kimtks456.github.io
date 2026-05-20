---
title: "2. 로컬/NAS Watcher"
weight: 2
date: 2026-05-20
---

> 로컬 디렉토리나 NAS에 파일이 올라오는 환경에서,
> JVM, Spring Batch, Kafka, Redis 환경을 중심으로 Watcher-Worker 구조를 정리한다.

---

## 1. 요약

로컬/NAS 파일 감지는 "실시간 이벤트"처럼 보이지만, 실제 핵심은 **업로드 완료 판정**이다.
오브젝트 스토리지처럼 범용적인 완료 이벤트가 있는 환경이 아니므로, 방식별 한계를 알고 골라야 한다.

| 방식 | 실시간성 | 업로드 완료 판정 | 장점 | 단점 | 판단 |
|---|---:|---|---|---|---|
| Java `WatchService` | 높음 | 직접 구현 필요 | JVM 표준 API, create/modify/delete 감지 | 이벤트 overflow, NAS 동작 차이, close 이벤트 없음 | 로컬 디스크 보조 trigger |
| OS native event (`inotify` 등) | 높음 | Linux `CLOSE_WRITE` 활용 가능 | 로컬 Linux에서는 완료에 가까운 이벤트 가능 | OS 종속, NAS/NFS/SMB에서는 신뢰 어려움 | 로컬 Linux 한정 |
| Spring Integration File Adapter | 중간~높음 | filter/poller 조합 | Spring 생태계, 파일 필터/폴러 내장 | polling 기반, 완료 판정 정책 필요 | JVM/Spring에서 실용적 |
| Apache Camel File Component | 중간~높음 | `readLock=changed`, `rename`, `markerFile` 등 | 파일 처리 패턴이 풍부 | Camel 도입 비용 | 파일 watcher 전용이면 강함 |
| Spring Batch scheduled scan | 낮음~중간 | processor에서 판정 | 실행 이력, 재시작, 청크 처리 | 실시간 watcher보다는 배치에 가까움 | 정기 스캔/감사/복구용 |
| long-running polling loop | 중간~높음 | 직접 구현 | 1~5초 폴링 가능, 단순 | 라이프사이클/관측성 직접 구현 | 실시간 요구가 있으면 후보 |
| `RepeatTemplate` loop | 중간~높음 | 직접 구현 | Spring Retry/반복 패턴 활용 가능 | watcher daemon 용도로는 애매함 | 직접 loop보다 큰 장점은 약함 |

> **Note: Spring Integration**
>
> Spring Integration은 Spring 애플리케이션 안에서
> "입력 어댑터 → 필터 → 핸들러" 형태의 메시지 파이프라인을 만드는 프레임워크다.
> 파일 watcher에서는 직접 무한 loop를 짜는 대신 파일 inbound adapter와 poller를 쓴다.
>
> 우리 시나리오의 흐름은 다음처럼 잡을 수 있다.
>
> ```text
> inbound directory poller
>   → tmp/done/size-stable filter
>   → Redis lock/dedupe
>   → Kafka produce
> ```
>
> 의사코드:
>
> ```java
> poll("/data/inbound/incoming", every = 5s)
>     .filter(file -> !file.name().endsWith(".tmp"))
>     .filter(file -> hasDoneMarker(file) || sizeStable(file, 30s))
>     .filter(file -> redis.setNx("file:lock:" + fingerprint(file), ttl = 5m))
>     .handle(file -> kafka.send("file.upload.completed", toCloudEvent(file)))
>     .handle(file -> redis.set("file:seen:" + fingerprint(file), ttl = 7d));
> ```
>
> 단, Spring Integration이 업로드 완료를 자동으로 판정해주는 것은 아니다.
> 완료 판정 정책은 marker, atomic rename, size stable 중 하나로 직접 정해야 한다.

추천은 혼합 구조다.

```text
빠른 감지        → WatchService 또는 짧은 polling loop
완료 판정        → marker/rename 우선, 불가하면 size stable
중복/락          → Redis
이벤트 전달      → Kafka
누락 복구/감사   → Spring Batch scheduled scan
```

Spring Batch를 메인 watcher로만 쓰면 실시간성이 약하다.
대신 **상시 watcher daemon + Spring Batch 복구 스캔** 조합이 현실적이다.

---

## 2. 전제

오브젝트 스토리지처럼 업로드 완료 이벤트를 받을 수 없다.
Watcher가 파일시스템을 직접 감시하거나 주기적으로 스캔해야 한다.

```text
Uploader
  → Local/NAS directory
  → JVM Watcher
  → Kafka
  → Worker Consumer
```

사용 기술은 다음으로 제한한다.

| 기술 | 역할 |
|---|---|
| JVM | watcher 애플리케이션 런타임 |
| Spring Batch | 주기적 스캔, 누락 복구, 감사성 작업 |
| Kafka | worker로 전달할 파일 준비 이벤트 |
| Redis | dedupe, lock, 처리 상태 캐시 |

---

## 3. 핵심 문제

로컬/NAS에서는 "파일이 보인다"와 "업로드가 끝났다"가 다르다.

예를 들어 다음 이벤트는 업로드 완료가 아닐 수 있다.

```text
CREATE file.csv
MODIFY file.csv
```

파일이 아직 쓰이는 중일 수 있으므로 완료 판정 규칙이 필요하다.

---

## 4. 진짜 업로드 완료 이벤트가 가능한가

결론부터 말하면 **범용적으로는 불가능**하다.
로컬/NAS에는 S3 `ObjectCreated` 같은 표준 완료 이벤트가 없다.

가능하거나 가까운 방법은 있다.

| 방법 | 완료 이벤트에 가까운가 | 한계 |
|---|---:|---|
| Linux `inotify` `CLOSE_WRITE` | 높음 | 로컬 Linux 파일시스템 기준. Java `WatchService`는 이 이벤트를 직접 노출하지 않음 |
| SMB/Windows change notification | 중간 | 파일 변경 감지는 가능하지만 "업로드 완료" 의미는 별도 판정 필요 |
| NFS/NAS watch | 낮음 | 클라이언트/마운트/캐시 정책에 따라 이벤트 신뢰도 차이 큼 |
| 파일 lock 확인 | 낮음 | advisory lock이면 uploader가 lock을 안 잡을 수 있음 |
| `lsof`/handle 검사 | 중간 | OS 종속, 권한/성능 문제, NAS에서는 부정확 가능 |
| uploader callback/API | 높음 | uploader를 수정할 수 있어야 함 |

가장 강한 해법은 uploader와 계약하는 것이다.

```text
1. .tmp로 업로드
2. 업로드 완료 후 atomic rename
3. 또는 .done marker 생성
```

> **Note: atomic rename**
>
> 여기서 `atomic`은 Java CAS의 atomic처럼 "동시성 변수 연산"을 말하는 것이 아니다.
> 파일시스템의 rename 결과가 관찰자에게 중간 상태 없이 보인다는 뜻이다.
>
> 흐름은 다음과 같다.
>
> ```text
> 업로드 중: file.csv.tmp
> 업로드 끝: rename file.csv.tmp → file.csv
> watcher : file.csv가 보이면 처리
> ```
>
> 즉, "완료 상태일 때만 rename한다"는 uploader와 watcher의 계약이다.
> rename 자체가 한 번에 반영되므로 watcher는 최종 파일명(`file.csv`)만 보면 된다.
>
> 단, 같은 파일시스템 안에서 rename할 때만 이 보장을 기대한다.
> 다른 mount나 파일시스템 사이의 move는 copy 후 delete가 될 수 있어 atomic rename으로 보면 안 된다.

이 계약이 없으면 "진짜 완료 이벤트"가 아니라 "완료로 추정"해야 한다.
그때 쓰는 방식이 size stable, min age, lock probe다.

---

## 5. 완료 판정 패턴

우선순위는 다음과 같다.

| 우선순위 | 패턴 | 설명 |
|---|---|---|
| 1 | atomic rename | 업로드 중 `.tmp`, 완료 후 최종 파일명으로 rename |
| 2 | done marker | `file.csv` 업로드 후 `file.csv.done` 생성 |
| 3 | uploader callback | 업로드 시스템이 watcher API 호출 |
| 4 | OS close event | Linux local FS에서 `CLOSE_WRITE` 계열 이벤트 사용 |
| 5 | size stable | N초 동안 size/mtime 변화가 없으면 완료로 추정 |
| 6 | min age | 수정 시간이 충분히 오래된 파일만 처리 |

가능하면 uploader와 계약을 맺고 atomic rename 또는 done marker를 쓴다.
그 계약이 없으면 size stable 방식으로 타협한다.

---

## 6. 실시간성과 폴링 비용

요건이 "업로드 완료 후 1시간 또는 3시간 이내 처리"라면,
watcher가 3시간 동안 계속 떠 있는 것은 문제가 아니다.
서버 프로세스는 원래 계속 떠 있는 형태로 운영된다.

문제는 "계속 폴링" 자체가 아니라 **얼마나 자주, 얼마나 넓게 스캔하느냐**다.

| 폴링 방식 | CPU/IO 비용 | 설명 |
|---|---:|---|
| 1초마다 전체 디렉토리 재귀 스캔 | 높음 | 파일 수가 많으면 NAS metadata I/O가 병목 |
| 5~30초마다 대상 shard만 스캔 | 중간 | 일반적인 실무 타협점 |
| WatchService trigger + 부분 스캔 | 낮음~중간 | 이벤트를 힌트로 쓰고, 정합성은 스캔으로 보정 |
| 5~10분마다 Spring Batch 복구 스캔 | 낮음 | 실시간 처리 누락 보정용 |

파일 수가 수천~수만 개 수준이고 디렉토리 shard가 잘 되어 있으면 5~30초 폴링은 보통 CPU를 죽이지 않는다.
반대로 단일 디렉토리에 수백만 파일을 두고 매초 `Files.walk`를 돌리면 CPU보다 NAS metadata I/O가 먼저 문제가 된다.

`RepeatTemplate`으로 무한 반복하는 것도 가능하지만, watcher daemon을 만들기 위한 1순위 도구는 아니다.
다음이 더 명확하다.

```text
ScheduledExecutorService
Spring @Scheduled fixedDelay
Spring Integration poller
Apache Camel file consumer
```

`RepeatTemplate`은 "반복 처리 정책"을 코드로 표현하는 도구에 가깝다.
장시간 daemon의 lifecycle, backoff, graceful shutdown, metrics는 별도로 붙여야 한다.
즉, `RepeatTemplate`을 쓰면 반복 자체는 표현되지만 운영 프로세스에 필요한 부분은 대부분 직접 구현해야 한다.

| 구현 방향 | 추천순위 | 구현 방식 | 장점 | 단점 | 적합한 경우 |
|---|---:|---|---|---|---|
| Spring Integration poller | 1 | `FileReadingMessageSource` + poller + filter + Kafka outbound | Spring 기반, poller/필터/채널 모델 제공, 짧은 polling 가능 | Spring Integration 학습 필요 | JVM/Spring에서 파일 watcher를 안정적으로 만들 때 |
| Apache Camel File Component | 2 | `file:` consumer + `readLock` + Kafka endpoint | `readLock=changed`, `markerFile`, `rename` 등 파일 패턴이 풍부 | Camel 도입 필요 | 파일 처리 라우팅이 계속 늘어날 때 |
| 직접 long-running polling loop | 3 | `ScheduledExecutorService` 또는 `@Scheduled(fixedDelay)`로 shard 스캔 | 단순, 제어 쉬움, 5~30초 폴링 구현 쉬움 | dedupe/backoff/metrics 직접 구현 | 요구사항이 단순하고 외부 프레임워크를 줄이고 싶을 때 |
| Java `WatchService` + 보정 스캔 | 4 | create/modify 이벤트를 trigger로 쓰고 주기적 scan으로 보정 | 지연 낮음 | NAS 이벤트 신뢰성, overflow, 완료 판정 한계 | 로컬 디스크 또는 이벤트를 힌트로만 쓸 때 |
| Spring Batch scheduled scan | 5 | `@Scheduled`/외부 스케줄러가 `fileWatchJob` 실행 | 실행 이력, 재시작, 청크 처리, 감사성 좋음 | 실시간 watcher로는 무거움 | 누락 복구, 감사, 주기적 정합성 검사 |

Spring Batch로 구현할 경우에는 watcher 본류보다 **복구 스캔 job**으로 두는 편이 낫다.
그래도 Spring Batch만으로 구성한다면 다음 형태가 된다.

```text
Scheduler
  → fileWatchJob(scanAt=...)
      ├── scanCandidateStep
      │   ├── Reader: incoming shard 파일 목록 stream
      │   ├── Processor: 완료 판정, Redis lock/dedupe
      │   └── Writer: Kafka produce, Redis status update
      └── staleLockCleanupStep
```

이때 `scanAt` 또는 `run.id`는 Batch 실행 식별용이다.
파일 중복 처리 기준은 JobParameter가 아니라 파일 fingerprint여야 한다.

```text
absolutePath + size + lastModified
absolutePath + checksum
directory + filename + producerBatchId
```

---

## 7. 권장 디렉토리 구조

아래 구조는 애플리케이션 내부 디렉토리가 아니라 **로컬/NAS 파일시스템에 실제로 둘 작업 디렉토리 구조**다.
Uploader, watcher, worker가 같은 NAS 경로를 공유한다고 가정한다.

```text
/data/inbound/
├── incoming/      # 업로드 중 또는 신규 파일
├── ready/         # watcher가 완료 판정한 파일
├── processing/    # worker 처리 중
├── done/          # 처리 완료
└── error/         # 처리 실패
```

Watcher가 파일을 직접 처리하지 않는다면 `ready` 이동까지도 생략 가능하다.
다만 로컬/NAS에서는 파일 상태가 눈에 보여야 운영이 쉬우므로 stage directory를 두는 편이 낫다.

---

## 8. 권장 구조

실시간성이 필요하면 Spring Batch만으로 watcher를 만들기보다,
상시 daemon과 복구 batch를 분리한다.

```text
[Realtime Watcher Daemon]
  ├── WatchService or short polling
  ├── completion check
  ├── Redis lock/dedupe
  └── Kafka produce

[Recovery Scan Job]
  ├── Spring Batch scheduled scan
  ├── missed file 재검사
  └── stale lock cleanup

[Worker]
  └── Kafka Consumer
```

역할 분리는 다음과 같다.

| 컴포넌트 | 책임 |
|---|---|
| Realtime Watcher | 빠른 감지와 Kafka 이벤트 발행 |
| Spring Batch Recovery Job | 누락 파일 재스캔, stale 상태 정리, 감사성 이력 |
| Redis | watcher 간 lock, dedupe |
| Kafka | worker로 이벤트 전달 |
| Worker | 실제 파일 처리 |

---

## 9. Redis 사용

Redis는 DB가 아니라 빠른 상태/락 저장소로 둔다.

| key | 용도 | TTL |
|---|---|---|
| `file:lock:{fingerprint}` | watcher 중복 선점 방지 | 짧게 |
| `file:seen:{fingerprint}` | Kafka 발행 완료 dedupe | 길게 |
| `file:state:{fingerprint}` | 상태 추적 | 정책에 따라 |

처리 흐름:

```text
1. 파일 후보 발견
2. 완료 판정
3. SET file:lock:{fingerprint} NX EX 300
4. file:seen:{fingerprint} 있으면 skip
5. Kafka produce
6. file:seen:{fingerprint} 저장
7. lock 해제
```

Kafka produce 성공 후 Redis `seen` 저장 전에 장애가 나면 중복 발행 가능하다.
따라서 Worker도 멱등해야 한다.

---

## 10. Kafka 이벤트

CloudEvents 형태를 유지한다.
여기서 "Cloud"는 클라우드 인프라 전용이라는 뜻이 아니라, 이벤트 메타데이터 envelope 표준이라는 의미로 본다.
on-prem Kafka에서도 다음 이유 때문에 쓸 가치가 있다.

| 이유 | 설명 |
|---|---|
| 공통 envelope | `id`, `type`, `source`, `time`, `subject`, `data` 위치가 고정됨 |
| dedupe 기준 명확화 | `id`를 이벤트 중복 제거 기준으로 사용 가능 |
| 라우팅 기준 명확화 | `type=file.upload.completed`로 consumer 분기 가능 |
| 출처 추적 | `source=file:///data/inbound`로 이벤트 발생 위치 표현 |
| payload와 metadata 분리 | 파일 경로/크기 같은 업무 데이터는 `data`, 이벤트 속성은 상위 필드 |
| 확장성 | 나중에 S3, SFTP, NAS, API callback이 섞여도 같은 consumer 계약 유지 |

CloudEvents를 안 써도 된다.
단일 producer와 단일 consumer만 있고 이벤트 종류가 하나뿐이면 커스텀 JSON도 충분하다.
하지만 watcher-worker 구조는 시간이 지나면 보통 다음처럼 이벤트가 늘어난다.

```text
file.upload.completed
file.upload.rejected
file.processing.started
file.processing.failed
file.processing.completed
```

이때 envelope가 없으면 각 이벤트마다 `eventId`, `eventType`, `occurredAt`, `source` 필드명이 흔들린다.
CloudEvents를 쓰면 이 공통부를 미리 고정할 수 있다.

```json
{
  "specversion": "1.0",
  "type": "file.upload.completed",
  "source": "file:///data/inbound",
  "id": "/data/inbound/incoming/order-001.csv:12345:1779252000000",
  "time": "2026-05-20T10:15:30Z",
  "subject": "incoming/order-001.csv",
  "datacontenttype": "application/json",
  "data": {
    "storageType": "local",
    "path": "/data/inbound/incoming/order-001.csv",
    "size": 12345,
    "lastModified": "2026-05-20T10:15:00Z",
    "fingerprint": "/data/inbound/incoming/order-001.csv:12345:1779252000000"
  }
}
```

Kafka key:

```text
fingerprint
```

---

## 11. Worker 책임

Worker는 Kafka Consumer로 둔다.
Watcher와 Worker의 책임을 섞지 않는다.

| Worker 책임 | 설명 |
|---|---|
| 파일 열기 | 이벤트 path 기준으로 파일 접근 |
| 멱등성 확인 | 이미 처리한 fingerprint skip |
| 처리 상태 이동 | processing/done/error 이동 |
| DB 반영 | 업무 트랜잭션 수행 |
| offset commit | 파일 처리 성공 후 commit |

Worker가 파일을 처리하기 전에 `processing`으로 rename하면,
다른 worker가 같은 파일을 잡는 문제를 줄일 수 있다.

---

## 12. OS WatchService vs Spring Batch Polling

JVM에는 `WatchService`가 있지만 운영 기준으로는 polling batch가 더 단순할 때가 많다.

| 방식 | 장점 | 단점 |
|---|---|---|
| Java WatchService | 지연 낮음 | 이벤트 누락/overflow, NAS 동작 차이, 완료 판정 별도 필요 |
| Spring Batch polling | 재시작/이력/청크 처리 쉬움 | 짧은 지연시간에는 불리 |
| 혼합형 | WatchService로 trigger, Batch로 scan | 구조가 복잡 |

NAS는 OS 이벤트가 로컬 디스크처럼 안정적으로 전달된다고 가정하기 어렵다.
따라서 "이벤트를 받으면 해당 파일만 처리"보다 "주기적으로 디렉토리 상태를 재계산"하는 polling이 더 안전하다.

---

## 13. 트랜잭션 경계

파일시스템, Redis, Kafka는 하나의 DB 트랜잭션으로 묶이지 않는다.
정확히 한 번 처리보다 at-least-once + idempotency로 설계한다.

| 실패 지점 | 결과 | 대책 |
|---|---|---|
| lock 획득 후 watcher 장애 | lock 잔존 | TTL |
| Kafka produce 후 seen 저장 전 장애 | 중복 발행 가능 | worker dedupe |
| seen 저장 후 Kafka produce 실패 | 이벤트 유실 가능 | 순서를 produce 성공 후 seen 저장으로 둠 |
| worker 처리 후 offset commit 전 장애 | 재처리 가능 | worker dedupe |
| worker가 파일 이동 후 장애 | 상태 디렉토리 재스캔/복구 job |

---

## 14. 대용량 고려

| 문제 | 대책 |
|---|---|
| 디렉토리에 파일 수백만 개 | 날짜/업무 기준 하위 디렉토리 shard |
| `Files.walk` 비용 증가 | 최근 mtime 범위, cursor 파일, 상태 캐시 |
| NAS metadata I/O 병목 | scan 주기 조절, 병렬 scan 제한 |
| Kafka produce 병목 | batch produce, linger.ms 조정 |
| Redis hot key | fingerprint 분산, prefix shard |

디렉토리 하나에 파일을 계속 쌓는 구조는 피한다.

```text
/data/inbound/order/2026/05/20/HH/
```

처럼 경로를 나눈다.

---

## 15. 예제 구현 순서

1. 짧은 polling watcher 또는 WatchService watcher 생성
2. `incoming` 디렉토리 scanner 구현
3. `.tmp` 제외, `.done` marker, size stable 완료 판정 구현
4. Redis `SET NX EX` lock 구현
5. Kafka `file.upload.completed` produce
6. Worker Consumer 구현
7. Worker dedupe와 `done/error` 이동 구현
8. Spring Batch recovery scan job 추가
9. 실패 케이스 테스트

---

## 16. 테스트 시나리오

| # | 시나리오 | 기대 |
|---|---|---|
| 1 | `.tmp` 파일 생성 | 이벤트 미발행 |
| 2 | `.tmp` → `.csv` rename | 이벤트 발행 |
| 3 | `.done` marker 생성 | 이벤트 발행 |
| 4 | 같은 파일 두 번 scan | Redis seen으로 skip |
| 5 | watcher 2대 동시 실행 | Redis lock으로 1대만 발행 |
| 6 | Kafka produce 후 watcher 장애 | 중복 가능, worker dedupe |
| 7 | worker 처리 후 offset commit 전 장애 | 재처리되지만 업무 중복 없음 |
| 8 | NAS에 대량 파일 투입 | scan 지연과 Redis/Kafka 부하 측정 |
| 9 | WatchService 이벤트 누락 | recovery scan으로 재발행 |
| 10 | 3시간 동안 업로드 지속 | 완료 전 이벤트 미발행 |

---

## 17. 결론

로컬/NAS + JVM/Spring Batch/Kafka/Redis 환경에서는 다음 구조를 기본값으로 둔다.

```text
Realtime watcher daemon
  → completion check
  → Redis lock/dedupe
  → Kafka CloudEvents
  → Worker Kafka Consumer
  → worker-side idempotency

Spring Batch recovery scan
  → missed file 재검사
  → stale 상태 정리
```

핵심은 "파일 발견"이 아니라 "완료 판정"과 "중복 허용 설계"다.
로컬/NAS에서는 exactly-once를 목표로 두지 말고 at-least-once + idempotency로 간다.

---

## 참고

- [Java WatchService API](https://docs.oracle.com/javase/8/docs/api/java/nio/file/WatchService.html)
- [Spring Batch Reference](https://docs.spring.io/spring-batch/reference/)
- [Spring Integration File Support](https://docs.spring.io/spring-integration/reference/file.html)
- [Apache Camel File Component](https://camel.apache.org/components/latest/file-component.html)
- [Redis SET command](https://redis.io/docs/latest/commands/set/)
- [Kafka Producer Configs](https://kafka.apache.org/documentation/#producerconfigs)
- [CloudEvents Specification](https://github.com/cloudevents/spec)
