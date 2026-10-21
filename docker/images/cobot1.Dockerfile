# 협동1 이미지 = ws_dsr (M0609 + RG2) 빌드본 + PyQt5 / Qt Designer + docker CLI
#   두산 런치가 `docker run` 으로 DRCF 에뮬레이터를 띄움 → run.sh 가 호스트 docker 소켓을 공유
ARG BASE_IMAGE=rokey/jazzy-base:latest
FROM ${BASE_IMAGE}
SHELL ["/bin/bash", "-eu", "-o", "pipefail", "-c"]

RUN sudo install -m 0755 -d /etc/apt/keyrings \
 && sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu noble stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null \
 && sudo apt-get update && sudo apt-get install -y docker-ce-cli \
 && sudo rm -rf /var/lib/apt/lists/*

COPY --chown=rokey:rokey resources /opt/rokey_installer/resources
# 협동2 와 같은 호스트 기준 중 컨테이너에 해당하는 것 = ros2-extras + CycloneDDS (sysctl 은 호스트 몫)
RUN R=/opt/rokey_installer/resources \
 && bash $R/base.sh ros2-extras \
 && bash $R/hostcfg.sh dds --no-sysctl \
 && bash $R/cobot1.sh deps \
 && bash $R/cobot1.sh workspace \
 && bash $R/cobot1.sh rosdep \
 && bash $R/cobot1.sh build \
 && bash $R/cobot1.sh extras --no-virtualbox \
 && bash $R/cobot1.sh hostcfg \
 && bash $R/cobot1.sh bashrc \
 && sudo rm -rf /var/lib/apt/lists/*
# 빌드 게이트 = 설치기 verify (docker 데몬 = 런타임 항목이라 제외)
RUN bash /opt/rokey_installer/resources/verify.sh --no-docker --no-host
CMD ["bash"]
