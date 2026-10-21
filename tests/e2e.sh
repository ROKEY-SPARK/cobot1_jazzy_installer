#!/usr/bin/env bash
# tests/e2e.sh · install.sh 전체 흐름을 깨끗한 컨테이너 안에서 실행 (호스트는 바꾸지 않음)
#   성공 경로 = 협동1 전 단계 → verify 통과 → 재실행 시 전부 skip
#   실패 경로 = 워크스페이스 고정 커밋이 원격에 없음 → 종료 코드 2 + cobot1_workspace=FAIL 기록 + 원인 메시지
#   전제 = rokey/jazzy-base 이미지 (bash docker/build.sh 가 만듦) · 호스트 docker 소켓
#   사용: bash tests/e2e.sh [success|failure|all]
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${E2E_IMAGE:-rokey/jazzy-base:latest}"
which="${1:-all}"
rc_total=0

# 저장소를 읽기 전용으로 마운트 → 컨테이너 안에서 사본을 만들어 실행 (install_log 가 저장소에 안 남음)
#   컨테이너도 /sys 로 호스트 GPU 를 본다 → GPU 를 주지 않으면 verify 의 nvidia-smi 점검이 실패
run_in_container() {
    local -a gpu=()
    docker info --format '{{json .Runtimes}}' 2>/dev/null | grep -q '"nvidia"' && gpu=(--gpus all)
    docker run --rm -i -u rokey "${gpu[@]}" -v "${ROOT}:/src:ro" -v /var/run/docker.sock:/var/run/docker.sock \
        "${IMAGE}" bash -c "cp -r /src ~/installer && cd ~/installer && $1"
}

e2e_success() {
    echo "== e2e success: bash install.sh (full) + rerun"
    local out rc
    out="$(run_in_container '
        F="--yes --no-kernel --no-static-ip --no-reboot --domain-id 10"
        bash install.sh $F; echo "RC1=$?"
        bash install.sh $F; echo "RC2=$?"
        grep -c "^export ROS_DOMAIN_ID=10$" ~/.bashrc | sed "s/^/DOMAIN_LINES=/"
        bash install.sh --status' 2>&1)"; rc=$?
    echo "${out}" | tail -40
    grep -q '^RC1=0$' <<<"${out}" || { echo "FAIL: first run did not exit 0"; return 1; }
    grep -q '^RC2=0$' <<<"${out}" || { echo "FAIL: rerun did not exit 0"; return 1; }
    grep -q 'skip: cobot1_build (already DONE)' <<<"${out}" || { echo "FAIL: rerun did not skip finished steps"; return 1; }
    grep -q '^DOMAIN_LINES=1$' <<<"${out}" || { echo "FAIL: bashrc block duplicated or missing"; return 1; }
    grep -q -- '---- [0-9]* passed, 0 failed' <<<"${out}" || { echo "FAIL: verify did not pass"; return 1; }
    echo "PASS e2e success (container rc ${rc})"
}

e2e_failure() {
    echo "== e2e failure: bash install.sh with a workspace commit that does not exist"
    local out
    # COBOT1_REPO_REF = config.sh 의 환경변수 override → 설치기 코드를 바꾸지 않고 실패를 만든다
    out="$(run_in_container '
        export COBOT1_REPO_REF=0000000000000000000000000000000000000000
        bash install.sh --yes --no-kernel --no-static-ip --no-reboot; echo "RC=$?"
        bash install.sh --status
        grep -h "ref ${COBOT1_REPO_REF} not found" "${LOG_FILE:-install_log}" | tail -1' 2>&1)"
    echo "${out}" | tail -25
    grep -q '^RC=2$' <<<"${out}" || { echo "FAIL: expected exit code 2"; return 1; }
    grep -q '^step_cobot1_workspace=FAIL$' <<<"${out}" || { echo "FAIL: cobot1_workspace not recorded as FAIL"; return 1; }
    grep -q 'git: ref 0000000000000000000000000000000000000000 not found' <<<"${out}" || { echo "FAIL: no cause in log"; return 1; }
    grep -q '^step_realsense_sdk=DONE$' <<<"${out}" || { echo "FAIL: earlier steps not recorded DONE"; return 1; }
    if grep -q '^step_cobot1_build=' <<<"${out}"; then echo "FAIL: steps after the failure ran"; return 1; fi
    echo "PASS e2e failure"
}

case "${which}" in
    success) e2e_success || rc_total=1 ;;
    failure) e2e_failure || rc_total=1 ;;
    all) e2e_success || rc_total=1; e2e_failure || rc_total=1 ;;
    *) echo "usage: bash tests/e2e.sh [success|failure|all]" >&2; exit 1 ;;
esac
exit "${rc_total}"
