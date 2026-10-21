# 협동1 강의 .bashrc 구성 (install.sh cobot1 이 관리 — 직접 고치면 다음 실행 때 덮어씀)
source /opt/ros/jazzy/setup.bash
[ -f /usr/share/colcon_argcomplete/hook/colcon-argcomplete.bash ] && source /usr/share/colcon_argcomplete/hook/colcon-argcomplete.bash
export PYTHONPATH=${PYTHONPATH:+$PYTHONPATH:}__WS__/install/dsr_common2/lib/dsr_common2/imp
__DOMAIN_LINE__
alias sod='source __WS__/install/setup.bash'
alias sodvir='ros2 launch m0609_rg2_bringup bringup.launch.py mode:=virtual host:=127.0.0.1 port:=12345 model:=m0609'
alias sodreal='ros2 launch m0609_rg2_bringup bringup.launch.py mode:=real host:=__ROBOT_IP__ port:=12345 model:=m0609'