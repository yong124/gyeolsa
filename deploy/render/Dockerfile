# 결사 온라인 서버 — Render(무료 웹 서비스)용. 저장소의 game/ 소스를 Godot 헤드리스로 바로 돌린다.
# 따로 내보내기(빌드)할 필요 없음: Render가 GitHub에서 받아 이 파일로 이미지를 만든다.
# TLS(wss://)는 Render 앞단이 맡고, 서버는 Render가 주는 PORT 환경 변수의 포트에서 ws로 받는다.
FROM debian:bookworm-slim

ARG GODOT_VERSION=4.7.1
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl unzip libfontconfig1 \
 && curl -fsSL -o /tmp/godot.zip \
    "https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" \
 && unzip -q /tmp/godot.zip -d /opt \
 && mv /opt/Godot_v${GODOT_VERSION}-stable_linux.x86_64 /usr/local/bin/godot \
 && chmod 755 /usr/local/bin/godot \
 && rm /tmp/godot.zip \
 && apt-get purge -y curl unzip && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*

RUN useradd --create-home --shell /usr/sbin/nologin game
WORKDIR /app
COPY --chown=game:game game/ /app/game/
USER game
# 리소스 가져오기(.godot 폴더 생성)는 이미지를 만들 때 한 번만
RUN godot --headless --path /app/game --import || true

ENV PORT=8910
EXPOSE 8910
CMD ["godot", "--headless", "--path", "/app/game", "--", "server"]
