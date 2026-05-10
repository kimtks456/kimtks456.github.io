---
title: "1. Colima — Mac Docker 환경 설정"
weight: 1
date: 2026-05-10
---

> Mac에서 Docker Desktop 없이 컨테이너를 실행하려면 Colima를 쓴다.  
> Colima는 Apple Silicon/Intel 모두 지원하며, Docker Desktop보다 가볍다.

---

## 1. 설치

```bash
brew install colima docker docker-compose
```

- `colima` — VM + containerd 런타임
- `docker` — Docker CLI (도커 데몬이 아닌 클라이언트만)
- `docker-compose` — Compose CLI

---

## 2. Colima 시작 / 정지

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

## 3. Docker Context 설정

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

## 4. Testcontainers + Colima 연동

Testcontainers는 기본적으로 `DOCKER_HOST` 환경변수 또는 `/var/run/docker.sock`을 본다.  
Colima는 별도 소켓을 사용하므로 두 환경변수를 명시해야 한다.

```bash
export DOCKER_HOST=unix:///Users/kimsan/.colima/default/docker.sock
export TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE=/var/run/docker.sock
```

`TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE` — Ryuk(리소스 정리) 컨테이너가 호스트 소켓을 마운트할 경로.  
이 값이 없으면 Colima 소켓의 전체 경로(`/Users/...`)를 컨테이너 내부에 마운트하려다 실패한다.

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

## 5. Gradle에서 테스트 실행

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

## 6. 자주 겪는 문제

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
