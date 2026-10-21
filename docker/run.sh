#!/usr/bin/env bash
# =============================================================
#  ROKEY Jazzy Lecture Installer
# =============================================================
#
# docker/run.sh · 협동1 컨테이너 실행 (X11 GUI · GPU 있으면 사용 · 호스트 네트워크)
#   사용: bash docker/run.sh [명령...]     기본 명령 = bash
#   작업 폴더 = 호스트 ~/rokey_docker/cobot1 ↔ 컨테이너 ~/work (컨테이너를 지워도 남음)
#   네트워크 = host → 같은 ROS_DOMAIN_ID 의 호스트·로봇·다른 컨테이너와 그대로 통신
#   두산 런치가 `docker run` 으로 DRCF 에뮬레이터를 띄움 → 호스트 docker 소켓 공유
set -euo pipefail

: "${IMAGE_PREFIX:=rokey/jazzy}"
: "${WORK_ROOT:=${HOME}/rokey_docker}"

course=cobot1

usage() {
    sed -n '6,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

case "${1:-}" in
    -h|--help) usage; exit 0 ;;
    cobot1) shift ;;   # 예전 호출 형식 (bash docker/run.sh cobot1 ...) 호환
esac

args=(--rm --network host --ipc host -e ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-0}")
# TTY 가 있을 때만 -t (스크립트·CI 에서 호출해도 "not a TTY" 로 죽지 않게)
if [[ -t 0 ]]; then args+=(-it); else args+=(-i); fi

# GPU = nvidia runtime 이 등록된 호스트에서만
if docker info --format '{{json .Runtimes}}' 2>/dev/null | grep -q '"nvidia"'; then
    args+=(--gpus all -e NVIDIA_DRIVER_CAPABILITIES=all)
else
    echo "run: no nvidia runtime in docker — starting without GPU (bash docker/setup-host.sh adds it)." >&2
fi

# X11 = 컨테이너 사용자 uid 1000 → 같은 uid 의 호스트 사용자만 허용, 아니면 local 전체 허용
if [[ -n "${DISPLAY:-}" ]] && command -v xhost >/dev/null; then
    if [[ "$(id -u)" == 1000 ]]; then xhost "+SI:localuser:$(id -un)" >/dev/null; else xhost +local: >/dev/null; fi
    args+=(-e DISPLAY -e QT_X11_NO_MITSHM=1 -v /tmp/.X11-unix:/tmp/.X11-unix:rw)
fi

# RealSense · 웹캠
for dev in /dev/video*; do [[ -e "${dev}" ]] && args+=(--device "${dev}"); done

args+=(-v /var/run/docker.sock:/var/run/docker.sock)
gid="$(getent group docker | cut -d: -f3 || true)"
[[ -n "${gid}" ]] && args+=(--group-add "${gid}")

mkdir -p "${WORK_ROOT}/${course}"
args+=(-v "${WORK_ROOT}/${course}:/home/rokey/work" --name "rokey-${course}-$$")
exec docker run "${args[@]}" "${IMAGE_PREFIX}-${course}:latest" "${@:-bash}"
