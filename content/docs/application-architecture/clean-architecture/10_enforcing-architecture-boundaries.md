---
title: "10. 아키텍처 경계 강제하기"
weight: 10
date: 2026-06-01
description: "패키지 구조와 접근 제어로 아키텍처 경계를 강제할 때 생기는 이슈를 정리한다."
---

## 1. 9장에서 넘어온 문제

[9. 애플리케이션 조립하기](./9_assembling-application/)에서는 Java Config 방식으로 application을 조립하는 방법을 봤다.
이 방식은 Spring annotation을 application code에 흩뿌리지 않고 configuration class에 모을 수 있다는 장점이 있다.

하지만 package-private class를 유지하려면 configuration class가 생성 대상 class와 같은 package에 있어야 한다.

```text
account.adapter.out.persistence
───────────────────────────────
AccountPersistenceAdapter          // package-private
PersistenceAdapterConfiguration    // 같은 package라서 생성 가능
```

문제는 Java의 package-private 접근 제어가 하위 package에는 적용되지 않는다는 점이다.

```text
account.adapter.out.persistence
├── AccountPersistenceAdapter
└── config
    └── PersistenceAdapterConfiguration
```

위 구조에서 `config`는 하위 package지만 Java 기준으로는 다른 package다.
따라서 `AccountPersistenceAdapter`가 package-private이면 `PersistenceAdapterConfiguration`이 접근할 수 없다.

이 장에서는 이런 제약 속에서 아키텍처 경계를 어떻게 강제할지 다룬다.

---

## 2. 참고

- [도서] 만들면서 배우는 클린 아키텍처 - 톰 홈버그(Tom Hombergs)
