---
title: "1. 카프카 개요"
weight: 1
date: 2026-04-21
---

[kafka 조금 아는 척하기 by 최범준님](https://www.youtube.com/watch?v=0Ssx7jJJADI&t=33s) 시리즈를 통해 대략적인 개념을 정리한다.

## 1. 카프카 핵심

### 1.1. 분산환경에서 메시지 처리 철학(Message Delivery Semantics)
분산 네트워크 환경(언제든 끊길 수 있음)에서 시스템 간 메시지를 어떻게 처리할 것인지에 대해 3가지 철학이 Kafka 내부 아키텍처에서 구현함

| **의미론 (Semantics)** | **설명** | **데이터 유실** | **데이터 중복** | **카프카 기본 동작** |
| --- | --- | --- | --- | --- |
| **At-most-once** (최대 한 번) | 메시지가 손실될지언정, 절대 중복해서 전달하지 않음 | 발생함 | 없음 | `acks=0`, 혹은 컨슈머가 '읽자마자 커밋' 할 때 |
| **At-least-once** (최소 한 번) | 메시지가 중복될지언정, 절대 유실시키지 않음 | 없음 | 발생함 | 카프카의 기본(Default) 철학 |
| **Exactly-once** (정확히 한 번) | 유실도 없고, 중복도 없이 정확히 한 번만 처리됨 | 없음 | 없음 | — |

Kafka는 왜 At-least-once 인가?
- 데이터 중복처리는 외부 plug-in 써서 처리 가능함.
- 그러나 메시지 유실된건 방법이 없으므로 최소 한번 보장하는 것
  - 예시 
    - producer의 `acks=all, retries`로 produce는 보장하나, 데이터 중복 가능
    - consumer에서 offset을 남겨서 무조건 1번은 처리되도록 함. commit 실패하면 2번 처리될 수 있음.

### 1.2. 구성 요소
- cluster : 메시지를 Disk 저장하는 저장소. 여러 브로커(서버)로 구성
- producer : 메시지 발행 
- consumer : 메시지 소비
- zookeeper : 클러스터의 status, meta 정보 관리하는 별도 서버인데, kafka 4.0 버전부터 KRaft 도입으로 deprecated

### 1.3. 토픽과 파티션
- topic
  - 메시지 구분하는 논리적 단위(ex. 뉴스, 주문)
- partition
  - 토픽 구성하는 물리적 파일. append-only 방식이므로 수정 불가
- offset
  - partition 내 메시지 저장 위치 번호. consumer가 이 번호 덕분에 순서대로 소비

### 1.4. 순서 보장, 데이터 일관성
- 1:1 연결 원칙
  - 하나의 partition은 동일한 consumer group 내 하나의 consumer만 소비
    - 덕분에 순서 보장 가능.
- 그룹 간 독립성
  - 서로 다른 consumer group은 동일한 partition을 독립적으로 읽음
  - 별도로 offset commit하기에 독립 보장됨. 따라서 목적(ex. 알림, 트랜잭션)에 따라 독립적으로 소비 가능

### 1.5. 고성능인 이유
1. __page cache__
    - disk 말고 memory에만 올려놓고 성공처리 후 다음 작업 진행 
2. __Zero Copy__ (전송 최적화)
    - 일반적인 전송 : Disk -> kernel memory -> user memory -> socket buffer -> NIC. 4번 복사 발생하며 CPU 점유
      - On-Heap(JVM memory) 사용하기에, Off-Heap(OS memory)로 복사하는 비용이 들게됨.
    - Kafka 전송 : linux sendfile() 시스템콜 = disk -> kernel memory -> NIC. 복사 2번
3. __브로커의 단순함__
    - 기존 MQ : 브로커가 message 누가 읽었나 확인(Ack), 읽은건 지우고 필터링하는 기능 존재
    - Kafka : 어디까지 읽었는지, 필터링 등 consumer가 직접 관리. broker 부담이 줄어드니 수만 대의 consumer 붙어도 고성능 가능
4. __배치 처리__
   - network 비용 아끼기 위해 일정시간 모아두다 한번에 producer -> broker 전송. consumer도 수백개씩 consume.

> **Page Cache**
>
> OS가 disk에서 읽어온 데이터나, 곧 disk 보낼 데이터를 memory 남는 공간에 잠시 보관하는 공간
> - 일반적인 쓰기 : App -> Page Cache -> Disk
> - Kafka 쓰기 : App -> Page Cache 기록되면 성공 처리
    >   - Disk 옮기는건 OS가 Background로 진행
>   - 순차적 I/O(append-only)로 파일 끝에 write하므로 disk 쓰기 최적


### 1.5. 고가용성인 이유
1. replication 
   - __Leader__ : 모든 r/w 요청 처리하는 'leader' 파티션 
   - **Follower** : leader 데이터를 복사해둔 복제본.  
   - __Failoer__ : leader 죽으면 follower 중에 가장 최신 데이터 가진 follower를 leader로 선출하므로 고가용성


---


## 2. Producer

### 2.1. Main thread와 I/O thread
Producer는 2개의 thread로 동작.
2개가 메모리 버퍼를 매개로 Asych. Producer-Consumer 패턴으로 동작함
1. Main thread
   - `send()` 호출 시, serialization 및 partitioning 거쳐 `RecordAccumulator` 적재됨.
   - 내부적으로 `ConcurrentMap<TopicPartition, Deque<ProducerBatch>>` 구조를 사용하여 파티션별로 데이터를 Deque에 쌓음
2. BufferPool
   - JVM의 잦은 GC 막기 위해 Producer는 `BufferPool`이라는 Off-heap 메모리 영역을 할당받아 재사용 (default 32MB).
3. Sender thread
   - NetworkClient로서 무한 푸프돌며 `RecordAccumulator`의 파티션별 Deque 순회하며 `ProducerBacht`들을 모아 broker로 네트워크 I/O 진행

> **Off-Heap**
> 
> JVM의 통제를 벗어나 OS가 관리하는 system memory를 직접 가져다 쓰는 영역
> - 장점
>   - GC 퍼즈(Stop-The-World) 회피
>     - GC가 주기적으로 메모리 청소하는 Stop-The-World 시, 시스템 전체 멈춤.
>     - Off-Heap에 저장하면, GC 대상 아니므로 수십 GB를 메모리에 캐싱해둬도 GC 퍼즈 발생 안함.
>   - Zero Copy 완성
>     - On-Heap이라면, JVM Heap -> OS(Off-Heap) 복사 후 NIC로 나가야하기에 memory 복사 1회 발생.
>     - Off-Heap이면, OS -> NIC 바로 가능
> - 단점
>   - 비싼 생성 비용
>     - System Call로 요청해야함. 따라서 Pool 만들어두고 재사용함
>   - 메모리 누수 위험
>     - GC 안해주니 개발자가 안해주면 linux 서버 자체가 뻗을 수 있음.
>   - 모니터링 어려움
>     - 자바 profiliing 도구(ex. JVisualVM 등)으로 모니터링 불가.
> 
> **On-Heap과의 비교** 
> 
> | 구분 | 온힙 (On-heap) | 오프힙 (Off-heap) |
> |---|---|---|
> | 관리 주체 | JVM (가비지 컬렉터 - GC) | 운영체제 (OS) / 개발자 수동 관리 |
> | 메모리 위치 | JVM에 할당된 램 공간 안 | JVM 바깥의 일반 시스템 램 공간 |
> | GC (가비지 컬렉션) | 대상임 (GC 지연 시간 발생 가능) | 대상 아님 (GC 부하 전혀 없음) |
> | 할당/해제 속도 | 매우 빠름 (JVM이 알아서 해줌) | 상대적으로 느리고 비쌈 (OS 시스템 콜 필요) |
> | I/O (네트워크/디스크) | 메모리 복사가 한 번 더 일어나서 느림 | OS 레벨에서 바로 쏠 수 있어 압도적으로 빠름 |
> | 자바 구현체 | `ByteBuffer.allocate()` | `ByteBuffer.allocateDirect()` |


### 2.2. Throughput vs Latency: 메모리 파라미터 튜닝

`BufferPool` 크기와 Network I/O System Call 발생주기를 파리미터로 조정 가능

- `batch.size`(Byte 단위)
  - `ProducerBatch` 하나의 메모리 크기. 해당 크기 도달되면 `linger.ms`와 무관하게 Sender thread로 전송
- `linger.ms`
  - 배치 사이즈 차지 않았어도 일정시간 후 강제 전송하는 주기

높은 throughput을 위해서는 둘 다 높여야함. 
단, `batch.size` 너무 높이면 `BufferPool` 메모리 고갈로 main thread가 `max.block.ms`동안 blocking 됨


### 2.3. Durability(신뢰성)의 핵심: ISR과 High Watermark

`acks` 설정은 Kafka의 replication 프로토콜인 ISR(In-Sync Replicas)와 직결됨
- ISR(동기화된 복제본 그룹)
  - Leader 파티션 포함, leader와 동기화 되고있는 follower 파티션들의 리스트(ISR)를 Zookeeper/KRaft에 관리함
  - 장애나거나 동기화 지연되는 follower는 ISR에서 퇴출당함
- `acks=all`과 `min.insync.replicas(default=1)`
  - ISR그룹에 속한 모든 브로커의 ack를 기다린다는 의미.
  - **`min.insync.replicas`은 `acks=all`일때만 동작. `acks=all`이면 반드시 설정해야하는 값**
    - `min.insync.replicas` 설정 안했을 때 장애 예시
      - ISR에 Leader 1대만 있다면, Leader에만 저장되면 Ack 반환됨. 만약 leader 서버 장애나면 유실됨
      
      => **가짜 안전. SPOF!!**
  - 이를 막기위해 `min.insync.replicas=2`로 하면, ISR에 10대 있더라도 최소 2대 이상 존재할 때만 쓰기 허용함
    - `min.insync.replicas=2`인데 ISR이 1개로 줄어들면, `NotEnoughReplicasException`로 쓰기 거절
    - `acks=all`이 ISR에 의존적이지만, 최대 2대는 복제됨을 보장할 수 있음.
- High Watermark(HW)
  - ISR 내 모든 복제본이 성공적으로 복제한 지점을 HW라고 부름. consumer는 HW 이전의 메시지만 읽을 수 있음.
  - `min.insync.replicas`와 무관
  - `LEO(Log End Offset)` : broker마다 개별적으로 갖고있는 로그 끝 지점
  - `HW` : `min(ISR 내 모든 노드의 LEO)`
---

> **`acks=all`과 `min.insync.replicas`는 다른 역할**
> 
> `acks=all`은 ISR내 모든 노드로부터 복제 완료(ack) 받을 때까지 기다리겠다. ISR이 n개면 n개의 Ack 받아야 write 성공
> 
> `min.insync.replicas`는 쓰기 허용할 하한선을 의미.
> - 예시) `min.insync.replicas=2`인 경우
>   - ISR=10 : 10 > 2이므로 쓰기 허용, 그러나 10개 모두 ack 해야 성공 응답
>   - ISR=2 : 2 = 2이므로 쓰기 허용, 모두 ack 해야 성공 응답
>   - ISR=1 : 1 < 2이므로 쓰기 불가.


### 2.4. Idempotence(멱등성)과 순서 보장(EOS 기반)
Network time-out 등으로 producer의 retry 시, 중복된 순서 뒤바뀜 해결하는 매커니즘 의미
- 원리
  - `enable.idempotence=true` 설정하면, producer마다 Producer ID 부여됨.
  - 각 메시지 배치마다 Sequence Number를 부여
- 로직
  - broker가 partition별로 `[PID, LastSequenceNumber]` map을 유지
  - **batch의 seq. number < `LastSequenceNumber + 1` 이면**
    - 이미 처리되었으므로 drop & Ack 
  - **batch의 seq. number > `LastSequenceNumber + 1`이면**
    - 순서 건너뛴것이므로 `OutOfOrderSequenceException` throw
    - producer가 메모리 버퍼(RecordAccumulator)의 Last.seq.num.부터 재전송
- `max.in.flight.requests.per.connection`
  - 하나의 connection에서 날아가고 있는 최대 요청 수
    - producer -> broker에 send 후 ack 받기 전까지 네트워크 전송중이거나 broker 처리중인 배치의 개수를 몇개까지 허용할지 결정
  - 기본값은 5. 
    - 1번 배치의 Ack 안받아도 2,3,4,5번 배치를 send 함
    - 왜 5인가?
      - broker 내부적으로 memory에 저장하는 seq. num의 윈도우 크기가 5임. 즉, PID별로 5개 seq.num을 caching함
      - KIP-98 설계 당시, 성능/메모리 트레이드오프 고려하여 최대 5개까지만 멱등성 보장하게 하드코딩함.
  - 값이 1보다 크면 순서 꼬일 수 있음
    - 예시) 3이라고 가정. 
      - 배치 1,2,3 날렸는데, 1이 유실됨. 그 사이 2,3은 disk에 저장되고 1은 retry로 디스크 저장되면 **2,3,1 순서로 브로커 저장됨**
    - 1이면 꼬일수가 없음.
  - 멱등성 키면 이 값을 5 이하로 설정해도 순서 보장됨.
  - broker가 sequenceNumber 기반으로 순서 어긋난 패킷을 memory buffer에서 재조립한 후 disk에 씀.

### 2.5. 주요 파라미터 정리
| **카테고리**               | **파라미터명** | **타입** | **기본값** | **엔지니어링 튜닝 포인트** |
|---| --- | --- | --- | --- |
| **메모리/배치**             | `batch.size` | Integer | 16384 (16KB) | 단일 파티션으로 향하는 레코드 배치 크기. 크면 Throughput 증가, 작으면 Latency 감소. |
| **메모리/배치**             | `linger.ms` | Long | 0 | 배치가 차지 않아도 대기하는 최대 시간. 보통 10~100ms로 설정하여 Throughput 극대화. |
| **메모리/배치**             | `buffer.memory` | Long | 33554432 (32MB) | 프로듀서가 가질 수 있는 총 버퍼(RecordAccumulator) 크기. 이 값을 넘으면 send()가 블로킹됨. |
| **신뢰성**                | `acks` | String | 1 (v3.0 전) / all (v3.0 후) | `0` (Fire&Forget), `1` (Leader만), `all` (ISR 전체 복제 확인). |
| **신뢰성 (브로커 측)**        | `min.insync.replicas` | Integer | 1 | `acks=all`일 때, 성공으로 간주하기 위한 최소 ISR 복제본 수. 브로커(또는 토픽) 레벨 설정. |
| **신뢰성/네트워크**           | `retries` | Integer | Integer.MAX_VALUE | 일시적 에러(LeaderNotAvailable 등) 발생 시 재시도 횟수. |
| **신뢰성/순서**             | `enable.idempotence` | Boolean | false (v3.0 전) / true (v3.0 후) | PID와 SeqNum을 활용하여 중복 없는 정확히 한 번(Exactly-once) 전송 보장. |
| **네트워크**               | `max.in.flight.requests.per.connection` | Integer | 5 | Ack를 받지 않고 한 커넥션에서 최대로 전송할 수 있는 배치 개수. |


---


## 3. Consumer

### 3.1. Consumer와 Partition은 1:N 할당
- consumer는 consumer group에 속함(`group.id` 기준)
- 하나의 consumer group 내에서 하나의 partition은 1개의 consumer에만 할당됨
  - 예시) consumer 4개이고 topic의 partition이 3개이면 consumer 1개는 항상 idle
  - 따라서 throughput 늘리기 위해 consumer scale-out 한다면, **반드시 partition도 늘려야한다.**

### 3.2. Long Polling 방식으로 데이터 가져옴

- broker가 push하는게 아니라 consumer가 pull 하는 방식. 무한루프 돌며 `poll()` 호출
- producer batch 처럼 broker도 batch로 모아서 한 번에 consumer로 내려줌

### 3.3. Offset과 Commit
- commit : consumer 별로 읽은 데이터 위치를 broker에 기록하는 행위
  - `poll()`로 읽어온 후 처리 끝나면 마지막 처리한 메시지의 **다음 offset 번호**를 broker(`__consumer_offsets__`라는 내부 토픽)에 기록하고, 
  
    다음 `poll()`부터 해당 offset부터 읽음

| 커밋 방식 | 특징 | 장단점 및 사용처 |
| --- | --- | --- |
| 자동 커밋 (Auto Commit) | `enable.auto.commit=true`. `auto.commit.interval.ms`(기본 5초) 주기로 백그라운드에서 자동 커밋 | 편리하지만, 5초가 되기 전에 컨슈머가 죽으면 오프셋이 기록되지 않아 메시지 중복 처리(Duplicate) 발생 가능 |
| 수동 동기 커밋 (`commitSync`) | `commitSync()` 호출. 커밋이 완료될 때까지 스레드 블로킹 | 오프셋 기록이 100% 보장되지만, 매번 네트워크 I/O 응답을 기다려야 하므로 처리량 저하 발생 |
| 수동 비동기 커밋 (`commitAsync`) | `commitAsync()` 호출. 논블로킹으로 커밋을 던지고 바로 다음 작업 진행 | 처리량이 높지만 일시적 네트워크 오류 시 실패 가능. 보통 콜백 함수로 로깅 처리 |

### 3.4. Health Check 및 Rebalance
- **Rebalance** : broker는 consumer health check 계속 하며 죽으면 해당 consumer의 partition을 다른 consumer에 재할당
- health check 로직
  1. 백그라운드 통신 (Heartbeat Thread)
     - `heartbeat.interval.ms`: 이 주기마다 브로커에게 "나 살아있어"라고 신호를 보냅니다. (보통 `session.timeout.ms`의 1/3 로 설정)
     - `session.timeout.ms`: 이 시간 동안 하트비트가 오지 않으면, 브로커는 컨슈머가 죽었다고 판단(네트워크 단절 등)하고 **강제 리밸런싱을 트리거.**
  2. 데이터 처리 속도 감시 (Main Thread)
     - `max.poll.interval.ms` : consumer의 `poll()` 간격의 최대 하용 시간 의미
       - 만약 consumer가 너무 오래걸려 이 시간 초과하면, application hang 걸렸다 판단하여 **rebalance 트리거.**

### 3.5. Idempotence 구현
consumer의 장애, 리밸런싱, 커밋 실패 등으로 **동일 메시지 두 번 이상(At-least-once) 수신 가능함**
- 예시) A consumer가 처리 후, 서버 다운돼서 commit 실패함. 재기동하면 offset부터 재처리하니까 이주으로 처리됨

해결법
  1. idempotence 하도록 consume 로직 설계
    - `Transaction ID` 또는 `Timestamp` 포함시키거나 DB에 넣는걸 idempotence 하게 설계
  2. Unique 보장 Plug-in 구축
    - DB/Cache 등 분산저장소를 통해 이미 처리한 ID 관리

### 3.6. Consumer는 Thread-Safe 한가?
`KafkaConsumer` 인스턴스는 절대 thread-safe 아님.

여러 thread에서 동시에 하나의 consumer 객체의 `poll(), commit()` 호출하면 `ConcurrentModificationException` 발생
- 단, 무한 루프를 우아하게 종료시키기 위해 외부 thread에서 호출하는 `wakeup()` 메서드는 예외 발생 안함


### 3.7. 주요 파라미터 정리
| **카테고리** | **파라미터명** | **타입** | **기본값** | **엔지니어링 튜닝 포인트** |
| --- | --- | --- | --- | --- |
| **그룹/식별** | `group.id` | String | (필수) | 같은 `group.id` 끼리 partition 을 나눠 분담. 다른 그룹은 독립 소비. |
| **시작 위치** | `auto.offset.reset` | String | `latest` | offset 없거나 invalid 시 동작: `earliest`(처음부터) / `latest`(현재) / `none`(예외 throw). |
| **Auto Commit** | `enable.auto.commit` | Boolean | `true` | true 면 백그라운드 자동 commit. 정확 처리 보장하려면 false + 수동 `commitSync/commitAsync`. |
| **Auto Commit** | `auto.commit.interval.ms` | Long | 5000 (5s) | 자동 commit 주기. 짧을수록 중복 처리 위험은 줄지만 commit 호출 부하 증가. |
| **Fetch** | `fetch.min.bytes` | Integer | 1 (1 Byte) | 값을 키우면 브로커가 데이터를 모을 때까지 대기 → Latency 증가, Throughput 증가. |
| **Fetch** | `fetch.max.wait.ms` | Integer | 500 (ms) | `fetch.min.bytes` 채워질 때까지 브로커가 기다리는 최대 시간. 타임아웃 캡. |
| **Fetch** | `fetch.max.bytes` | Integer | 52428800 (50MB) | 단일 fetch 요청 전체 최대 크기 (여러 partition 합산). |
| **Fetch** | `max.partition.fetch.bytes` | Integer | 1048576 (1MB) | 파티션당 반환 최대 크기. 이 크기 넘으면 즉시 컨슈머에게 리턴. |
| **Polling/처리량** | `max.poll.records` | Integer | 500 | 단일 `poll()` 호출에서 받을 최대 레코드 수. 처리 시간 길면 줄여서 `max.poll.interval` 초과 방지. |
| **Polling/처리량** | `max.poll.interval.ms` | Long | 300000 (5분) | `poll()` 호출 사이 최대 간격. 초과 시 컨슈머 hang 으로 간주하여 rebalance 트리거. |
| **Health/Heartbeat** | `session.timeout.ms` | Integer | 45000 (45s) | heartbeat 못 받은 채 이 시간 지나면 컨슈머가 죽었다고 판단 → rebalance. |
| **Health/Heartbeat** | `heartbeat.interval.ms` | Integer | 3000 (3s) | heartbeat 주기. 보통 `session.timeout.ms / 3` 로 설정. |
| **파티션 할당** | `partition.assignment.strategy` | List | `RangeAssignor`, `CooperativeStickyAssignor` | partition 을 컨슈머에 분배하는 전략. Cooperative 는 점진적 rebalance 로 stop-the-world 회피. |
| **파티션 할당** | `group.instance.id` | String | `null` | static membership ID. 설정 시 짧은 다운/재기동에도 rebalance 발생 안 함. |
| **격리 수준** | `isolation.level` | String | `read_uncommitted` | `read_committed` 로 두면 트랜잭션 commit 된 메시지만 읽음 (EOS 컨슈머). |
| **직렬화** | `key.deserializer` | Class | (필수) | key 역직렬화 클래스. 보통 `StringDeserializer`, `ByteArrayDeserializer`. |
| **직렬화** | `value.deserializer` | Class | (필수) | value 역직렬화 클래스. |

---


##  참고
- https://www.youtube.com/watch?v=0Ssx7jJJADI&t=33s
- https://www.youtube.com/watch?v=geMtm17ofPY
- https://www.youtube.com/watch?v=xqrIDHbGjOY