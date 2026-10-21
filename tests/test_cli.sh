#!/usr/bin/env bash
# tests/test_cli.sh · install.sh (협동1 전용) 인자 처리 · 종료 코드 · dry-run 단계 목록
#   sudo · 네트워크 · apt 를 쓰지 않는 경로만 실행 (--help / 잘못된 인자 / --dry-run / --status)

_cli() { bash "${INSTALLER_ROOT}/install.sh" "$@"; }

test_help_exits_0_and_names_cobot1_and_other_repos() {
    out="$(_cli --help)"
    assert_contains "${out}" "Usage: bash install.sh [options]"
    assert_contains "${out}" "협동1 (cobot1)"
    assert_contains "${out}" "https://github.com/ROKEY-SPARK/cobot3_jazzy_installer"
    assert_contains "${out}" "https://github.com/ROKEY-SPARK/int1_jazzy_installer"
}

test_no_course_argument_installs_cobot1() {
    out="$(_cli --dry-run)"
    assert_contains "${out}" "== ROKEY Jazzy installer: cobot1"
    assert_contains "${out}" "would run: cobot1_workspace"
}

test_other_course_names_point_to_their_repo() {
    rc=0; out="$(_cli cobot3 --dry-run 2>&1)" || rc=$?
    assert_eq "${rc}" "1"
    assert_contains "${out}" "https://github.com/ROKEY-SPARK/cobot3_jazzy_installer"
    rc=0; out="$(_cli intel1 2>&1)" || rc=$?
    assert_eq "${rc}" "1"
    assert_contains "${out}" "https://github.com/ROKEY-SPARK/int1_jazzy_installer"
    rc=0; out="$(_cli int1 2>&1)" || rc=$?
    assert_eq "${rc}" "1"
    assert_contains "${out}" "https://github.com/ROKEY-SPARK/int1_jazzy_installer"
}

test_removed_options_of_other_courses_are_user_errors() {
    for opt in --no-nvidia --isaac-download --no-kernel-hold --discovery; do
        rc=0; _cli --dry-run "${opt}" >/dev/null 2>&1 || rc=$?
        assert_eq "${rc}" "1" "${opt}"
    done
}

test_unknown_option_is_user_error() {
    rc=0; _cli cobot1 --bogus >/dev/null 2>&1 || rc=$?
    assert_eq "${rc}" "1"
}

test_domain_id_must_be_integer_in_range() {
    rc=0; _cli cobot1 --domain-id abc --dry-run >/dev/null 2>&1 || rc=$?
    assert_eq "${rc}" "1"
    rc=0; _cli cobot1 --domain-id 999 --dry-run >/dev/null 2>&1 || rc=$?
    assert_eq "${rc}" "1"
}

test_domain_id_without_value_is_user_error() {
    rc=0; _cli cobot1 --domain-id --dry-run >/dev/null 2>&1 || rc=$?
    assert_eq "${rc}" "1"
}

test_dry_run_cobot1_lists_steps_in_order_and_changes_nothing() {
    out="$(_cli cobot1 --dry-run --domain-id 10)"
    assert_contains "${out}" "would run: ros2_jazzy"
    assert_contains "${out}" "would run: dsr_emulator"
    assert_contains "${out}" "cobot1_bashrc -> bash"
    assert_contains "${out}" "bashrc 10"
    # 순서 = 협동2 base 9단계에서 nvidia 만 뺀 것 → 앱 계층
    order="$(grep -oE 'would run: [a-z0-9_]+' <<<"${out}" | awk '{print $3}' | tr '\n' ' ')"
    assert_eq "${order}" "kernel_baseline docker ros2_jazzy ros2_extras reboot vscode dds_tuning network_static_ip cobot1_deps realsense_sdk cobot1_workspace cobot1_rosdep dsr_emulator cobot1_build cobot1_hostcfg cobot1_extras cobot1_bashrc verify "
    if grep -q nvidia <<<"${out}"; then echo "cobot1 must not touch the NVIDIA driver"; return 1; fi
    [[ ! -e "${BASHRC}" ]]
    [[ ! -e "${STATE_DIR}/cobot1.state" ]] || [[ ! -s "${STATE_DIR}/cobot1.state" ]]
}

test_status_prints_state_file() {
    out="$(_cli --status)"
    assert_contains "${out}" "cobot1.state"
}

test_rerun_skips_steps_recorded_done() {
    mkdir -p "${STATE_DIR}"
    printf 'step_ros2_jazzy=DONE\nstep_docker=DONE\n' > "${STATE_DIR}/cobot1.state"
    out="$(_cli --dry-run)"
    assert_contains "${out}" "skip: ros2_jazzy (already DONE)"
    assert_contains "${out}" "skip: docker (already DONE)"
}

test_dry_run_cobot1_skip_flags() {
    out="$(_cli cobot1 --dry-run --no-kernel --no-static-ip --no-reboot)"
    assert_contains "${out}" "skip: kernel_baseline (--no-kernel)"
    assert_contains "${out}" "skip: network_static_ip (--no-static-ip)"
    assert_contains "${out}" "skip: reboot (--no-reboot"
    assert_contains "${out}" "verify.sh --no-kernel --no-static-ip"
}

test_resume_terminal_flag_is_not_a_user_error() {
    # --resumed 는 내부 플래그 = 파싱만 통과해야 함 (dry-run 이라 아무것도 안 바뀜)
    out="$(_cli --resumed --dry-run)"
    assert_contains "${out}" "would run: kernel_baseline"
}

test_verify_does_not_require_nvidia_driver() {
    # 협동1 은 드라이버를 깔지 않음 (협동2 설치기 몫) → 드라이버 없는 새 노트북에서도 점검이 GPU 로 실패하면 안 됨
    out="$(bash "${INSTALLER_ROOT}/resources/verify.sh" --no-docker --no-host 2>&1)" || true
    if grep -q 'nvidia-smi' <<<"${out}"; then echo "verify checks nvidia-smi: ${out}" | grep nvidia; return 1; fi
}
