---
title: "1. Colima — Mac Docker 환경 설정"
weight: 1
date: 2026-05-10
---

> Mac에서 Docker Desktop 없이 컨테이너를 실행하려면 Colima를 쓴다.  
> Colima는 Apple Silicon/Intel 모두 지원하며, Docker Desktop보다 가볍다.

---

## 1. 엔터프라이즈 환경에서 Colima를 쓰는 이유

### Docker Desktop 라이선스 제한

Docker Desktop은 2022년부터 상업적 사용에 유료 구독을 요구한다.

> **무료 사용 조건 (모두 충족해야 함)**  
> - 직원 수 250명 미만 **AND**  
> - 연 매출 $10M(약 130억 원) 미만  
> - 위 조건 중 하나라도 벗어나면 유료 플랜(Team/Business) 필요

### "CLI만 쓰면 괜찮지 않나?"

**아니다.** 라이선스는 GUI 사용 여부가 아니라 **Docker Desktop 소프트웨어(데몬 + VM) 실행** 기준이다.

macOS에서 Docker Engine은 Linux 커널이 없어 네이티브로 실행되지 않는다. Docker Desktop은 내부적으로 경량 Linux VM을 띄워 그 안에서 Docker 데몬을 실행한다. `docker` CLI는 그 데몬에 붙는 클라이언트에 불과하다.

```
[macOS]
  └── Docker Desktop (VM + 데몬)  ← 라이선스 적용 대상
        └── docker CLI             ← 단순 클라이언트, 라이선스 무관
```

CLI만 쓰더라도 Docker Desktop 데몬이 구동 중이면 Docker Desktop을 사용하는 것이다.

### Colima가 해결하는 것

Colima는 Docker Desktop과 **완전히 독립된** VM + Docker 데몬을 제공한다.  
Docker Desktop을 전혀 설치하지 않아도 되므로 라이선스 문제가 없다.

```
[macOS]
  └── Colima (Lima VM + Docker 데몬)  ← Apache 2.0, 라이선스 무관
        └── docker CLI (brew 설치)    ← 마찬가지로 Apache 2.0
```

| 구분 | Docker Desktop | Colima |
|------|---------------|--------|
| 라이선스 | 상업적 사용 시 유료 | Apache 2.0 (무료) |
| macOS에서 데몬 실행 | 자체 VM으로 제공 | Lima VM으로 제공 |
| GUI | 있음 | 없음 (CLI 전용) |
| 소켓 경로 | `/var/run/docker.sock` | `~/.colima/default/docker.sock` |
| Testcontainers 설정 | 추가 설정 불필요 | env var 설정 필요 |

### 개인 프로젝트라면

개인 사용·소규모 팀은 Docker Desktop 무료 조건에 해당한다.  
이 경우 Docker Desktop이 소켓 경로 문제 없이 Testcontainers와 바로 동작하므로 더 편하다.  
**Colima는 엔터프라이즈 환경에서 라이선스 컴플라이언스를 지키기 위한 선택이다.**

---

## 2. 설치

```bash
brew install colima docker docker-compose
```

- `colima` — VM + containerd 런타임
- `docker` — Docker CLI (도커 데몬이 아닌 클라이언트만)
- `docker-compose` — Compose CLI

> **Note — QEMU 불필요 (Apple Silicon + macOS 13 이상)**  
> Colima는 VM 백엔드로 QEMU 또는 Apple의 Virtualization.Framework(vz) 중 하나를 선택한다.  
> Apple Silicon(M1/M2/M3) + macOS 13 이상 조합에서는 vz 백엔드가 기본값이므로 `brew install qemu`는 필요 없다.  
> `colima status` 출력에 `macOS Virtualization.Framework`가 표시되면 QEMU는 사용되지 않는다.  
> Intel Mac이거나 `--vm-type=qemu`를 명시한 경우에만 QEMU가 필요하다.

### Docker Desktop이 이미 설치된 경우 — brew 버전으로 전환

Docker Desktop을 먼저 설치했다면 `docker`·`docker-compose` 바이너리가 Docker Desktop 것을 가리키고 있을 수 있다.  
`which docker` 출력이 `/Applications/Docker.app/...` 또는 `/usr/local/bin/docker`(Docker Desktop 심볼릭 링크)이면 아래 절차로 전환한다.

**① brew로 설치**

```bash
brew install colima docker docker-compose
```

**② docker-compose CLI 플러그인 교체**

`docker compose` 명령은 `~/.docker/cli-plugins/docker-compose` 플러그인을 쓴다.  
Docker Desktop이 심어 놓은 구버전 플러그인을 brew 버전으로 교체한다.

```bash
mkdir -p ~/.docker/cli-plugins
ln -sfn /opt/homebrew/opt/docker-compose/bin/docker-compose ~/.docker/cli-plugins/docker-compose
```

**③ 쉘 경로 캐시 초기화**

쉘은 명령어 경로를 캐싱하기 때문에 `which docker-compose`가 여전히 Docker Desktop 경로를 반환할 수 있다.  
캐시를 초기화하면 `/opt/homebrew/bin`의 brew 버전을 바라본다.

```bash
hash -r
which docker          # → /opt/homebrew/bin/docker
which docker-compose  # → /opt/homebrew/bin/docker-compose
```

새 터미널을 열어도 동일하게 적용된다.

**④ 버전 확인**

```bash
docker --version        # Docker version 29.x.x
docker-compose version  # Docker Compose version v5.x.x
docker compose version  # 동일
```

---

## 3. Colima 시작 / 정지

```bash
# 기본 시작 (CPU 2, Memory 4GB, Disk 100GB)
colima start

# 리소스 명시
colima start --cpu 4 --memory 8 --disk 100

# 정지
colima stop

# 상태 확인
colima status
```

---

## 4. Docker Context 설정

Colima는 자체 소켓을 사용한다.

```
# Colima 소켓 위치
unix:///Users/<username>/.colima/default/docker.sock

# 기본 Docker 소켓 (/var/run/docker.sock → Docker Desktop)
unix:///var/run/docker.sock
```

`colima start` 후 자동으로 `colima` context가 활성화된다:

```bash
docker context ls
# NAME          TYPE   DESCRIPTION   DOCKER ENDPOINT
# colima *      moby   colima        unix:///Users/kimsan/.colima/default/docker.sock
# default       moby   ...           unix:///var/run/docker.sock
# desktop-linux moby   Docker Desktop unix:///Users/kimsan/.docker/run/docker.sock
```

---

## 5. Testcontainers + Colima 연동

Testcontainers는 기본적으로 `DOCKER_HOST` 환경변수 또는 `/var/run/docker.sock`을 본다.  
Colima는 별도 소켓을 사용하므로 두 환경변수를 명시해야 한다.

```bash
export DOCKER_HOST=unix:///Users/kimsan/.colima/default/docker.sock
export TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE=/var/run/docker.sock
```

`TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE` — Ryuk(리소스 정리) 컨테이너가 호스트 소켓을 마운트할 경로.  
이 값이 없으면 Colima 소켓의 전체 경로(`/Users/...`)를 컨테이너 내부에 마운트하려다 실패한다.

### ~/.testcontainers.properties 방식은 동작하지 않는다

Testcontainers 공식 문서는 `~/.testcontainers.properties`에 아래처럼 설정하는 방법을 안내한다:

```properties
docker.host=unix:///Users/kimsan/.colima/default/docker.sock
ryuk.disabled=true
```

**Testcontainers 1.21.x 기준으로 이 방식은 동작하지 않는다.** `ryuk.disabled` 프로퍼티가 무시되어 Ryuk이 계속 실행을 시도하고, 소켓 마운트에 실패한다. 환경변수 방식으로 진행한다.

### 매번 export 없이 쓰는 방법

`~/.zshrc` 또는 `~/.zprofile`에 추가:

```bash
# Colima Docker socket
export DOCKER_HOST="unix://${HOME}/.colima/default/docker.sock"
export TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE=/var/run/docker.sock
```

적용:

```bash
source ~/.zshrc
```

---

## 6. Gradle에서 테스트 실행

환경변수가 설정된 상태에서:

```bash
./gradlew :kafka-common-lib:test
./gradlew :order-service:test
```

환경변수 없이 일회성으로 실행:

```bash
DOCKER_HOST=unix:///Users/kimsan/.colima/default/docker.sock \
TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE=/var/run/docker.sock \
./gradlew test
```

---

## 7. 자주 겪는 문제

### Docker CLI 버전 오류

```
Error response from daemon: client version 1.43 is too old. Minimum supported API version is 1.44
```

Docker CLI(`docker` 패키지)와 Colima 내부 데몬 API 버전 불일치.  
`brew upgrade docker`로 CLI를 올린다.

### "Could not find a valid Docker environment"

Testcontainers가 Docker 소켓을 못 찾는 경우. `DOCKER_HOST`가 설정됐는지 확인:

```bash
echo $DOCKER_HOST
```

비어 있으면 `colima start`를 다시 실행하거나 위 4번 export를 추가한다.

### Ryuk 컨테이너 실행 실패

```
error while creating mount source path '/Users/.../.colima/default/docker.sock': operation not supported
```

`TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE=/var/run/docker.sock`이 없어서 발생.  
위 4번 설정 추가 후 재시도한다.

---

## 참고

- [Colima GitHub](https://github.com/abiosoft/colima)
- [Testcontainers — Docker on macOS](https://java.testcontainers.org/supported_docker_environment/)
