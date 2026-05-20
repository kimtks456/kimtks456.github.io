---
title: "1. 스토리지 이벤트 기반 Watcher"
weight: 1
date: 2026-05-20
---

> 파일 업로드 완료를 감지한 뒤 Kafka로 이벤트를 발행하고,
> Worker는 Kafka Consumer로 이벤트를 받아 실제 파일 처리를 수행하는 구조를 정리한다.
> 오브젝트 스토리지에서는 직접 polling watcher보다 **스토리지 네이티브 이벤트**를 우선한다.

---

## 1. 목표

파일 처리 시스템을 Watcher와 Worker로 나눈다.

```text
Uploader
  → File Storage
  → Watcher
  → Kafka topic
  → Worker
```

| 컴포넌트 | 책임 |
|---|---|
| File Storage | 파일 원본 저장 |
| Watcher | 업로드 완료 감지, 이벤트 정규화, Kafka 발행 |
| Kafka | 파일 처리 이벤트 버퍼 |
| Worker | 파일 다운로드, 검증, 파싱, DB 반영 |

Watcher는 파일 내용을 처리하지 않는다.
Watcher는 "처리할 파일이 준비됐다"는 사실만 Kafka로 발행한다.

---

## 2. 권장 구조

오브젝트 스토리지에서는 스토리지가 제공하는 이벤트 기능을 사용한다.

```text
[Uploader]
    │
    ▼
[Object Storage]
    │  ObjectCreated / ObjectFinalized
    ▼
[Queue or Event Bus]
    │
    ▼
[Watcher]
    │  CloudEvents 변환, dedupe, Kafka produce
    ▼
[Kafka: file.upload.completed]
    │
    ▼
[Worker Consumer]
```

Watcher가 스토리지를 직접 주기적으로 뒤지는 방식보다 이 구조가 낫다.

| 이유 | 설명 |
|---|---|
| 완료 시점 | 스토리지가 object create/finalize 이벤트를 발행 |
| 장애 복구 | Queue/Event Bus가 watcher 장애 동안 이벤트를 보관 |
| 확장성 | watcher 인스턴스를 수평 확장 가능 |
| 비용 | 대량 list polling 비용과 부하 감소 |

---

## 3. 저장소별 표준 패턴

| 저장소 | 이벤트 방식 | 중간 버퍼 | Watcher 입력 |
|---|---|---|---|
| AWS S3 | S3 Event Notifications, EventBridge | SQS, SNS, EventBridge | object created event |
| Google Cloud Storage | Pub/Sub notifications, Eventarc | Pub/Sub | object finalize event |
| Azure Blob Storage | Event Grid | Event Grid | BlobCreated event |
| MinIO | Bucket Notification | Kafka, AMQP, Webhook 등 | object created event |

설계 기준은 같다.

```text
스토리지 이벤트를 직접 업무 처리하지 말고,
Watcher가 내부 표준 이벤트로 변환한 뒤 Kafka에 발행한다.
```

---

## 4. 이벤트 포맷

Kafka 메시지는 CloudEvents 형식을 권장한다.
CNCF 표준이고 Kafka protocol binding도 제공된다.

```json
{
  "specversion": "1.0",
  "type": "file.upload.completed",
  "source": "s3://my-bucket/inbound",
  "id": "my-bucket/inbound/orders/file-001.csv/etag-or-version",
  "time": "2026-05-20T10:15:30Z",
  "subject": "inbound/orders/file-001.csv",
  "datacontenttype": "application/json",
  "data": {
    "storageType": "s3",
    "bucket": "my-bucket",
    "key": "inbound/orders/file-001.csv",
    "size": 123456789,
    "etag": "abc",
    "versionId": "optional",
    "checksum": "optional"
  }
}
```

Kafka key는 중복 제거 기준과 맞춘다.

```text
bucket + key + versionId
bucket + key + etag
storageType + absolutePath
```

---

## 5. Watcher 내부 책임

Watcher는 단순 relay가 아니다.
운영 안정성을 위해 다음 책임을 가진다.

| 책임 | 설명 |
|---|---|
| 이벤트 정규화 | S3/GCS/Azure 이벤트를 내부 표준 이벤트로 변환 |
| metadata 검증 | HEAD 요청으로 size, etag, version 확인 |
| dedupe | 같은 스토리지 이벤트 중복 수신 방지 |
| Kafka 발행 | 표준 topic에 produce |
| 실패 재시도 | queue ack 전에 Kafka produce 성공 보장 |
| 관측성 | event lag, produce 실패, dedupe hit 측정 |

dedupe 테이블 예시는 다음과 같다.

```text
file_event_dedup
├── event_id
├── storage_type
├── bucket
├── object_key
├── version_id
├── etag
├── status
├── first_seen_at
└── produced_at
```

---

## 6. 중복과 순서

스토리지 이벤트는 일반적으로 at-least-once로 봐야 한다.
같은 object event가 중복될 수 있고, 순서가 항상 보장된다고 가정하면 안 된다.

따라서 아래를 전제로 설계한다.

| 문제 | 대책 |
|---|---|
| 같은 이벤트 중복 수신 | watcher dedupe |
| Kafka 중복 발행 | worker 멱등 처리 |
| 같은 key 재업로드 | versionId, etag, lastModified로 구분 |
| watcher 장애 | queue visibility timeout / retry |
| worker 장애 | Kafka offset commit 기준 재처리 |

중복 제거는 watcher와 worker 양쪽에 둔다.
Watcher dedupe만 믿으면 Kafka produce 성공 후 ack 실패 같은 케이스에서 중복이 발생할 수 있다.

---

## 7. 완료 판정

오브젝트 스토리지에서는 "업로드 완료 이벤트"를 사용한다.
로컬 파일시스템처럼 size stable check를 직접 구현하는 방식은 우선순위가 낮다.

| 상황 | 완료 판정 |
|---|---|
| S3 일반 업로드 | ObjectCreated 이벤트 |
| S3 multipart upload | CompleteMultipartUpload 이후 ObjectCreated 이벤트 |
| GCS | object finalize 이벤트 |
| Azure Blob | BlobCreated 이벤트 |

---

## 8. 선택지 비교

| 방식 | 장점 | 단점 | 적합 |
|---|---|---|---|
| Storage Event + Queue + Watcher | 안정적, 확장 가능 | 클라우드 이벤트 설정 필요 | 운영 표준 |
| Watcher polling list | 구현 단순 | 비용/지연/중복 처리 부담 | 소규모, 임시 |
| OS filesystem watch | 지연 낮음 | 업로드 완료 판정 어려움 | 로컬/NAS |
| Kafka Connect Source | Kafka 연동 쉬움 | 이벤트만 발행하기엔 과할 수 있음 | 파일 내용을 Kafka로 넣을 때 |
| Apache NiFi | UI 기반 플로우, 다양한 커넥터 | 별도 플랫폼 운영 | 데이터플로우 플랫폼 필요 |

---

## 9. 테스트 시나리오

| # | 시나리오 | 기대 |
|---|---|---|
| 1 | 같은 object event 2번 수신 | Kafka 이벤트 1개 또는 worker 멱등 처리 |
| 2 | Kafka produce 성공 후 watcher ack 실패 | 재수신되어도 중복 처리 |
| 3 | 같은 key에 다른 파일 재업로드 | version/etag 기준 별도 이벤트 |
| 4 | worker 처리 중 실패 | Kafka offset 미커밋 후 재처리 |
| 5 | 대량 파일 업로드 | watcher lag와 Kafka 처리량 관측 |

---

## 10. 결론

오브젝트 스토리지 기반이면 다음 구조를 기본값으로 둔다.

```text
Object Storage Event
  → Queue/Event Bus
  → Watcher
  → Kafka
  → Worker
```

Watcher는 파일 처리기가 아니라 이벤트 정규화기다.
파일 파싱, 검증, DB 반영은 Worker의 책임이다.

---

## 참고

- [AWS S3 Event Notifications](https://docs.aws.amazon.com/AmazonS3/latest/userguide/EventNotifications.html)
- [Amazon S3 EventBridge](https://docs.aws.amazon.com/AmazonS3/latest/userguide/EventBridge.html)
- [Google Cloud Storage Pub/Sub notifications](https://cloud.google.com/storage/docs/pubsub-notifications)
- [Azure Blob Storage Event Grid](https://learn.microsoft.com/en-us/azure/storage/blobs/storage-blob-event-overview)
- [CloudEvents Specification](https://github.com/cloudevents/spec)
- [CloudEvents Kafka Protocol Binding](https://github.com/cloudevents/spec/blob/main/cloudevents/bindings/kafka-protocol-binding.md)
- [Apache NiFi Documentation](https://nifi.apache.org/docs.html)
