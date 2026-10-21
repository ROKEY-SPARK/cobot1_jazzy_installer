# cobot1_jazzy_installer

- ROKEY 협동1 (Doosan M0609 + OnRobot RG2) 강의 PC 를 **Ubuntu 24.04 + ROS 2 Jazzy** 로 자동 설치하는 bash 스크립트
- 협동1 은 협동2 와 **같은 노트북**을 쓴다. 그래서 base 계층은 [cobot2_jazzy_installer](https://github.com/ROKEY-SPARK/cobot2_jazzy_installer) 에서 **GPU 단계만 뺀 같은 순서 · 같은 값**이다
- 다른 강의: 협동2 [cobot2_jazzy_installer](https://github.com/ROKEY-SPARK/cobot2_jazzy_installer) · 협동3 [cobot3_jazzy_installer](https://github.com/ROKEY-SPARK/cobot3_jazzy_installer) · 지능1 [int1_jazzy_installer](https://github.com/ROKEY-SPARK/int1_jazzy_installer)

설치하는 것: HWE 커널 · Docker · ROS 2 · CycloneDDS · 로봇 LAN IP · 재부팅 자동 재개 + `~/ws_cobot_pjt/ws_dsr` (M0609 + RG2) · DRCF 에뮬레이터 · RealSense SDK · PyQt5 / Qt Designer · FastDDS 도구 · VirtualBox

Docker 이미지 (`docker/`) 도 같은 설치 함수로 만든다 → [Docker 로 쓰기](#docker-로-쓰기)

## 설치

```bash
git clone https://github.com/ROKEY-SPARK/cobot1_jazzy_installer.git ~/cobot1_jazzy_installer
cd ~/cobot1_jazzy_installer
bash install.sh --domain-id 10     # 조별 ROS_DOMAIN_ID
```

- `sudo` 없이 일반 사용자로 실행한다. 필요한 곳에서 스크립트가 sudo 를 부른다 (비밀번호 1회)
- 5단계에서 한 번 재부팅하고, GUI 로그인 때 터미널이 열려 자동으로 이어서 설치한다 (협동2 와 같음)
- 콘솔에는 진행 단계만 나온다. 상세 출력 = 저장소 루트 `install_log` (append-only)
- 마지막 단계 = `--verify` 점검. 언제든 다시 확인: `bash install.sh --verify`

### 옵션

| 옵션 | 뜻 |
|------|----|
| `--domain-id N` | 협동1 `~/.bashrc` 블록에 `export ROS_DOMAIN_ID=N` (조 번호). 없으면 주석으로 남김 |
| `--no-kernel` | HWE 커널 단계 생략 |
| `--no-static-ip` | 로봇 LAN 정적 IP (`192.168.1.30/24`) 단계 생략 |
| `--no-reboot` | 5단계 재부팅 생략 (로봇을 쓰기 전에 직접 재부팅) |
| `--yes` · `--verbose` · `--dry-run` | 확인 자동 동의 · 상세 출력 콘솔 표시 · 실행 없이 단계 목록만 |
| `--status` · `--verify` · `--reset` | 진행 상태 · 설치 결과 점검 · 진행 기록 삭제 (설치 파일은 유지) |

종료 코드: `0` 성공 · `1` 사용자 오류 (잘못된 옵션) · `2` 시스템 오류 (단계 실패)

## 단계

커널 · Docker · DDS · 로봇 LAN IP 가 협동2 와 같으므로, 같은 노트북에서 어느 설치기를 먼저 돌려도 결과가 어긋나지 않는다. 앱 계층은 협동1 강의자료의 `cobot_rg2` 워크스페이스다.

| # | 단계 | 내용 · 근거 |
|---|------|------|
| 1 | `kernel_baseline` | HWE 커널 meta + headers + 현재 커널 modules-extra (협동2 1단계) |
| 2 | `docker` | Docker Engine + docker 그룹 + 엔진 버전 hold (협동2 3단계) |
| 3 | `ros2_jazzy` | ROS 2 Jazzy desktop + ros-dev-tools + rosdep (협동2 4단계) |
| 4 | `ros2_extras` | ros2_control · controllers · moveit-msgs · xacro · ros_gz 등 (협동2 5단계) |
| 5 | `reboot` | 재부팅 1회 → GUI 로그인 때 터미널이 열려 **자동으로 이어서 설치** (협동2 6단계) |
| 6 | `vscode` | VS Code (협동2 7단계) |
| 7 | `dds_tuning` | CycloneDDS XML + 소켓 버퍼 sysctl + `~/.bashrc` 블록. 협동2 와 **같은 파일 · 같은 마커** (협동2 8단계) |
| 8 | `network_static_ip` | 유선 NIC `192.168.1.30/24`, gateway/DNS 없음 → 인터넷은 wifi 유지 (협동2 9단계) |
| 9 | `cobot1_deps` | cobot_rg2 README 요구 패키지 (realsense2 ROS · pymodbus 3.6.9 등) |
| 10 | `realsense_sdk` | librealsense2 SDK (협동2 app-install 과 같은 저장소 · 패키지) |
| 11 | `cobot1_workspace` | `git clone https://github.com/ahnisinc/cobot_rg2.git ~/ws_cobot_pjt/ws_dsr/src` (커밋 고정) + 강사 디렉토리 구조 |
| 12 | `cobot1_rosdep` | `rosdep install --from-paths src --ignore-src` (ROS1 잔재 키만 skip) |
| 13 | `dsr_emulator` | `doosanrobot/dsr_emulator:3.0.1` pull |
| 14 | `cobot1_build` | `colcon build` + `dsr_common2/.../imp` 존재 확인 |
| 15 | `cobot1_hostcfg` | 실기 모드 조건: `ip_unprivileged_port_start=0` · RealSense udev rule |
| 16 | `cobot1_extras` | terminator · PyQt5 + Qt Designer · fastdds-tools · VirtualBox · FastAPI/uvicorn · Node.js |
| 17 | `cobot1_bashrc` | `.bashrc 구성` 그대로: `PYTHONPATH` · `ROS_DOMAIN_ID` · `sod` · `sodvir` · `sodreal` |
| 18 | `verify` | 협동2 기준 항목 + 협동1 패키지 · 이미지 · 블록 점검 |

- 협동2 에서 뺀 것: GPU 단계 (NVIDIA 드라이버 · Container Toolkit · YOLO GPU 컨테이너). 협동2 설치기가 나중에 드라이버를 얹는다 (커널 → 드라이버 순서라 그대로 맞음)
- 협동2 전용 앱 (cobot2 소스 · host voice · m0609_rg2_integration) 은 협동1 강의자료에 없어 넣지 않았다. 협동1 로봇 패키지는 강의자료의 `cobot_rg2` 다
- 기본 RMW = CycloneDDS (협동2 와 같음). 강의의 "FastDDS Discovery Server" 실습은 강의대로 `export RMW_IMPLEMENTATION=rmw_fastrtps_cpp` 를 직접 넣으므로 그대로 동작한다
- 유선 NIC 가 없으면 8단계는 경고만 남기고 넘어간다 → 나중에 `bash resources/hostcfg.sh network`

설치 후:

```bash
sod && sodvir                                  # 터미널 1: 가상 모드 브링업 (에뮬레이터 자동 기동)
sod && ros2 run dsr_example dance              # 터미널 2
```

## 강의자료와 다른 점

설치기는 강의자료 절차를 따른다. 아래는 그대로 두면 깨지거나 협동2 와 맞추면서 바꾼 부분이다.

| 항목 | 강의자료 | 설치기 | 이유 |
|------|---------|--------|------|
| ROS apt 저장소 | 강의 미기재 | 협동2 와 같은 `/etc/apt/keyrings/ros.gpg` + `ros2.list` | `ros2-apt-source` 의 `ros2.sources` 와 한 PC 에 같이 있으면 apt 가 `Conflicting values set for option Signed-By` 로 실패 (컨테이너에서 재현) → 협동2 와 같은 방식이 아니면 협동2 설치기가 깨짐 |
| pymodbus | `pip3 install pymodbus==3.6.9` | apt `python3-pymodbus` (3.6.9) | 같은 버전, PEP 668 회피 |
| Dart-Simulator | Drive 에서 VM zip 수동 다운로드 | VirtualBox + `~/ws_cobot_pjt/DartPlatform` 만 준비 | VM 파일은 강의 Drive 전용 (공개 URL 없음) |

## Docker 로 쓰기

호스트에 ROS 를 깔지 않고 협동1 환경을 컨테이너로 쓴다. 이미지 빌드가 위 설치 함수를 그대로 실행하고, 마지막에 `verify.sh` 를 통과해야 이미지가 생긴다.

- 파일: `docker/images/base.Dockerfile` (ROS 2 desktop + 사용자 `rokey` uid 1000) → `docker/images/cobot1.Dockerfile`
- `build.sh` 가 base → cobot1 순서로 빌드하고, 호스트 apt 미러 (예: `kr.archive.ubuntu.com`) 를 이미지에도 쓴다

```bash
bash docker/setup-host.sh          # Docker Engine (+ NVIDIA GPU 가 있으면 Container Toolkit), 호스트 1회
bash docker/build.sh               # rokey/jazzy-base → rokey/jazzy-cobot1
bash docker/run.sh                 # X11 GUI · 호스트 네트워크 · ~/rokey_docker/cobot1 ↔ ~/work
```

- 이미지 `rokey/jazzy-cobot1` = ROS 2 desktop + `ws_dsr` 빌드본 + PyQt5/Designer + docker CLI
- 호스트 docker 소켓을 공유 → `sodvir` 가 에뮬레이터 컨테이너를 호스트에 띄움 (호스트에 에뮬레이터 이미지 필요: `docker pull doosanrobot/dsr_emulator:3.0.1`)
- `ROS_DOMAIN_ID=10 bash docker/run.sh` 처럼 도메인을 넘긴다
- 컨테이너는 `--rm` → 남길 코드는 `~/work` (호스트 `~/rokey_docker/cobot1`) 에 둔다

## 주의

- `cobot1_hostcfg` 는 `net.ipv4.ip_unprivileged_port_start=0` 을 **시스템 전체**에 건다 (cobot_rg2 README 의 실기 모드 조건). 일반 사용자 프로세스도 1024 미만 포트를 열 수 있게 된다
- `docker/run.sh` 는 호스트 docker 소켓을 컨테이너에 준다 → 컨테이너 안 사용자 = 호스트 docker 권한 (= 사실상 root)
- `~/.bashrc` 를 처음 고치기 전에 `~/.bashrc.rokey.bak` 으로 원본을 한 번 백업한다. 관리 블록 마커가 한쪽만 남아 있으면 지우지 않고 멈춘다
- 협동1 블록은 `/opt/ros/jazzy/setup.bash` 를 source 한다 (강의 그대로). 같은 PC 에서 협동3 Isaac Sim 을 쓰면 그 터미널에 시스템 ROS 가 섞인다 → Isaac 터미널에서는 `bash --norc` 후 협동3 블록만 쓰거나, 강의별 PC 를 나눈다
- 같은 PC 에 협동3 설치기를 먼저 돌렸다면 협동3 가 현재 커널을 hold 한다 → 1단계가 새 HWE 커널을 올리지 않는다
- `network_static_ip` 는 유선 NIC 의 NetworkManager 프로필을 고정 IP 로 바꾼다 (협동2 와 같은 동작). 그 NIC 로 다른 유선 인터넷을 쓰고 있었다면 `--no-static-ip`

## 문제 해결

| 증상 | 조치 |
|------|------|
| 단계가 `[FAIL]` 로 멈춤 | 저장소 루트 `install_log` 끝부분 확인 → 원인 해결 → 같은 명령 다시 실행 (끝난 단계는 skip) |
| 처음부터 다시 | `bash install.sh --reset` 후 재실행 (설치된 패키지 · 폴더는 지우지 않음) |
| 재부팅 후 터미널이 안 열림 | GUI 없이 로그인했거나 터미널 프로그램이 없는 경우 → 같은 명령을 직접 다시 실행 |
| `sodvir` 를 끈 뒤 에뮬레이터가 남음 | `docker rm -f dsr01_emulator` (두산 런치가 종료 때 컨테이너를 남기는 경우가 있음) |
| 가상 모드 서비스가 늦게 뜸 | 에뮬레이터 기동에 수십 초 걸린다 (테스트에서 45초 이내). `ros2 service list \| grep /dsr01/dsr_controller2/motion/move_joint` 가 나오면 `dance` 실행 |

## 개발

```bash
bash tests/run.sh                  # 단위 테스트 (sudo · 네트워크 불필요, 격리된 HOME)
bash tests/e2e.sh                  # install.sh 전체를 깨끗한 컨테이너에서 실행 (성공 · 실패 경로)
shellcheck -x install.sh resources/*.sh docker/*.sh tests/*.sh
bash install.sh --dry-run          # 실행할 단계 목록
```

- 버전 핀 · 경로 = `resources/config.sh` 한 곳. 환경변수로 덮어쓸 수 있다 (예: `COBOT1_WS=~/my_ws`)
- 단계 순서 = `resources/courses.sh` · 단계 구현 = `resources/<base|hostcfg|cobot1>.sh`
- 단계 이름은 state 키다 (`~/.rokey_jazzy_installer/cobot1.state`) → 이름을 바꾸면 기존 설치의 재개 기록이 끊긴다
