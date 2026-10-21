#!/usr/bin/env bash
# =============================================================
#  ROKEY Jazzy Lecture Installer
# =============================================================
#
# shellcheck shell=bash
# resources/courses.sh · source 전용 · 협동1 단계 순서 (install.sh 가 호출)
#   선행 조건 = config.sh · lib.sh source + RESOURCE_DIR · 옵션 변수(OPT_*) 설정
#   단계 이름 = state 키 → 이름을 바꾸면 기존 설치의 재개 기록이 끊긴다

# shellcheck disable=SC2034  # STEPS_TOTAL = lib.sh run_step 이 읽는다
R() { echo "${RESOURCE_DIR}/$1"; }

domain_args() { [[ -n "${OPT_DOMAIN_ID}" ]] && echo "${OPT_DOMAIN_ID}"; return 0; }

# 설치에서 건너뛴 단계는 점검에서도 건너뜀
cobot1_verify_args() {
    [[ "${OPT_NO_KERNEL}" == 1 ]] && echo --no-kernel
    [[ "${OPT_NO_STATIC_IP}" == 1 ]] && echo --no-static-ip
    return 0
}

# 협동2 6단계와 같은 재부팅 경계: 기록을 먼저 DONE 으로 남기고 재부팅 → 로그인하면 autostart 가 재개
#   --no-reboot 은 state 에 남기지 않음 → 다음 실행에서 옵션을 빼면 재부팅한다
reboot_step() {
    local n="$1"
    if step_is_done reboot; then
        [[ "${DRY_RUN:-0}" == 1 ]] || remove_resume_autostart
        echo "[${n}/${STEPS_TOTAL}] skip: reboot (already DONE)"
        return 0
    fi
    if [[ "${OPT_NO_REBOOT}" == 1 ]]; then
        echo "[${n}/${STEPS_TOTAL}] skip: reboot (--no-reboot: reboot yourself before using the robot)"
        return 0
    fi
    [[ "${DRY_RUN:-0}" == 1 ]] && { echo "[${n}/${STEPS_TOTAL}] would run: reboot"; return 0; }
    echo "[${n}/${STEPS_TOTAL}] reboot — kernel/docker group apply after reboot; install resumes on login."
    state_set reboot DONE
    if ! as_root reboot; then
        state_set reboot FAIL
        remove_resume_autostart
        die "${EXIT_SYSTEM}" "reboot failed — reboot by hand, then run the same command again."
    fi
    exit 0
}

# 협동2 install.sh 9단계 중 NVIDIA 를 뺀 8단계 (같은 노트북 → 같은 커널 · DDS · 정적 IP)
plan_cobot1_base() {
    if [[ "${OPT_NO_KERNEL}" == 1 ]]; then
        run_step_skip 1 kernel_baseline "--no-kernel"
    else
        run_step 1 kernel_baseline bash "$(R base.sh)" kernel
    fi
    run_step 2 docker            bash "$(R base.sh)" docker
    run_step 3 ros2_jazzy        bash "$(R base.sh)" ros2
    run_step 4 ros2_extras       bash "$(R base.sh)" ros2-extras
    reboot_step 5
    run_step 6 vscode            bash "$(R base.sh)" vscode
    run_step --always 7 dds_tuning bash "$(R hostcfg.sh)" dds
    if [[ "${OPT_NO_STATIC_IP}" == 1 ]]; then
        run_step_skip 8 network_static_ip "--no-static-ip"
    else
        run_step 8 network_static_ip bash "$(R hostcfg.sh)" network
    fi
}

# 앱 계층 = 협동1 강의 워크스페이스 (협동2 setup-app.sh 자리)
plan_cobot1() {
    STEPS_TOTAL=18
    plan_cobot1_base
    run_step 9 cobot1_deps       bash "$(R cobot1.sh)" deps
    run_step 10 realsense_sdk    bash "$(R cobot1.sh)" realsense-sdk
    run_step 11 cobot1_workspace bash "$(R cobot1.sh)" workspace
    run_step 12 cobot1_rosdep    bash "$(R cobot1.sh)" rosdep
    run_step 13 dsr_emulator     bash "$(R cobot1.sh)" emulator
    run_step 14 cobot1_build     bash "$(R cobot1.sh)" build
    run_step 15 cobot1_hostcfg   bash "$(R cobot1.sh)" hostcfg
    run_step 16 cobot1_extras    bash "$(R cobot1.sh)" extras
    # shellcheck disable=SC2046
    run_step --always 17 cobot1_bashrc bash "$(R cobot1.sh)" bashrc $(domain_args)
    # shellcheck disable=SC2046
    run_step --always --interactive 18 verify bash "$(R verify.sh)" $(cobot1_verify_args)
    [[ "${DRY_RUN:-0}" == 1 ]] || remove_resume_autostart
}

