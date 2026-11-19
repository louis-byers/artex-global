# syntax=docker/dockerfile:1
#
# 이 저장소 소스에서 바로 빌드하는 이미지입니다. 미리 컴파일한 바이너리나 레지스트리 이미지를 쓰지 않습니다.
# 빌드 단계(web, go)는 빌드 머신 플랫폼($BUILDPLATFORM)에서 돌고 Go 가 목표 아키텍처로 크로스 컴파일하므로
# (CGO_ENABLED=0, 순수 Go), 다중 아키텍처 빌드에서도 Next/Go 컴파일은 에뮬레이션하지 않습니다.
#
#   docker compose build                         # docker-compose.yml 이 이 파일을 씁니다
#   docker build --build-arg ARTEX_VERSION="$(git describe --tags --always --dirty)" -t artex:local .

# ① 프런트엔드 정적 내보내기
FROM --platform=$BUILDPLATFORM node:22-bookworm-slim AS web
WORKDIR /src/web
COPY web/package.json web/package-lock.json ./
RUN npm ci
COPY web/ ./
RUN npm run build:static

# ② 프런트엔드를 내장한 단일 바이너리(build.sh 와 같은 플래그)
FROM --platform=$BUILDPLATFORM golang:1.26-bookworm AS go
ARG TARGETOS=linux
ARG TARGETARCH
ARG ARTEX_VERSION=dev
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
COPY --from=web /src/web/out ./server/webui/dist
RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH go build -tags embedui -trimpath \
      -ldflags "-s -w -buildid= -X main.version=${ARTEX_VERSION}" -o /out/artex ./cmd/artex

# ③ 실행 이미지
FROM python:3.12-slim-bookworm
# 상용 도구: ripgrep / curl / vim 에 더해 recon 에 자주 쓰는 도구 묶음(필요에 따라 추가·삭제).
# Node 는 NodeSource 에서 20.x 를 설치한다: bookworm 기본 apt nodejs 는 18 이고, Playwright 는 >=20 을 요구한다.
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates ripgrep curl wget vim git jq unzip \
      dnsutils iputils-ping netcat-openbsd inetutils-telnet whois nmap \
    && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*
# Playwright MCP 와 CLI 를 전역으로 미리 설치한다(런타임에 npx 로 네트워크 다운로드하지 않도록).
# @playwright/mcp: browser MCP 는 `npx @playwright/mcp` 로 바로 실행한다(전역 설치 완료, -y/@latest 불필요).
# @playwright/cli: playwright-cli 를 제공하며, 설치 후 --help 로 실행 가능 여부를 확인한다.
# 다음으로 playwright(브라우저 관리 제공)를 설치하고, --with-deps 로 chromium 과 그 시스템 의존성을 미리 깔아 둔다.
# 이렇게 하면 컨테이너 안의 MCP/CLI 가 최초 기동 시 바로 쓸 수 있고, 브라우저를 네트워크로 내려받지 않는다.
RUN npm install -g @playwright/mcp@latest @playwright/cli@latest playwright@latest \
    && playwright-cli --help \
    && playwright install --with-deps chromium \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=go /out/artex /app/artex
# 감시 기동 스크립트: 비정상 종료 시 백오프 후 다시 띄운다.
# 이 스크립트는 SIGTERM 을 artex 로 전달하는 일도 맡는다: docker stop 은 신호를 PID 1 에만 보내므로,
# 전달하지 않으면 artex 가 신호를 받지 못해 우아한 종료를 못 하고 10 초 뒤 SIGKILL 로 강제 종료된다.
COPY start.sh /app/start.sh
RUN chmod +x /app/artex /app/start.sh
COPY skills/ /app/skills/
# data/(SQLite + jwt.key) 영속화 지점
VOLUME ["/app/data"]
EXPOSE 8787 8788
ENTRYPOINT ["/app/start.sh"]
CMD ["-addr", ":8787", "-proxy", ":8788"]
