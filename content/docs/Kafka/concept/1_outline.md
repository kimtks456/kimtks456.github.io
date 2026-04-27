---
title: "1. 카프카 개요"
weight: 1
date: 2026-04-21
---

[kafka 조금 아는 척하기 by 최범준님](https://www.youtube.com/watch?v=0Ssx7jJJADI&t=33s) 시리즈를 통해 대략적인 개념을 정리한다.

## 1. 카프카 핵심

### 1.1 구성 요소
- cluster : 메시지를 Disk 저장하는 저장소. 여러 브로커(서버)로 구성
- producer : 메시지 발행 
- consumer : 메시지 소비
- zookeeper : 클러스터의 status, meta 정보 관리하는 별도 서버인데, kafka 4.0 버전부터 KRaft 도입으로 deprecated

### 1.2. 토픽과 파티션
- topic
  - 메시지 구분하는 논리적 단위(ex. 뉴스, 주문)
- partition
  - 토픽 구성하는 물리적 파일. append-only 방식이므로 수정 불가
- offset
  - partition 내 메시지 저장 위치 번호. consumer가 이 번호 덕분에 순서대로 소비

### 1.3. 순서 보장, 데이터 일관성
- 1:1 연결 원칙
  - 하나의 partition은 동일한 consumer group 내 하나의 consumer만 소비
    - 덕분에 순서 보장 가능.
- 그룹 간 독립성
  - 서로 다른 consumer group은 동일한 partition을 독립적으로 읽음
  - 별도로 offset commit하기에 독립 보장됨. 따라서 목적(ex. 알림, 트랜잭션)에 따라 독립적으로 소비 가능

### 1.4. 고성능인 이유
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




## 3. Consumer

---


##  참고
https://www.youtube.com/watch?v=0Ssx7jJJADI&t=33s
https://www.youtube.com/watch?v=geMtm17ofPY