FROM ubuntu:24.04
RUN apt-get update && apt-get install -y ffmpeg zsh bc
WORKDIR /app
COPY . /app
CMD ["bash", "tests/test_shortcuts.sh"]
