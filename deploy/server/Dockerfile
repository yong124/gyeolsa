# 결사 온라인 서버 (헤드리스 Godot, 리눅스). 빌드: game/tools/build_server.ps1 이 이 폴더에 실행 파일을 넣는다.
FROM debian:bookworm-slim
RUN useradd --create-home --shell /usr/sbin/nologin game
WORKDIR /app
COPY gyeolsa_server.x86_64 /app/gyeolsa_server.x86_64
RUN chmod 755 /app/gyeolsa_server.x86_64
USER game
EXPOSE 8910
# 포트는 data/v2/online.json의 port (기본 8910)
CMD ["/app/gyeolsa_server.x86_64", "--headless", "--", "server"]
