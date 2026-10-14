#!/usr/bin/env bash
# Host setup for the tested X550 / Falcon / RAN650 lab. No RU credentials are stored.
set -euo pipefail

mode=${1:-start}
case "$mode" in
  start|--prepare|--check) ;;
  *) echo "Usage: $0 [--prepare|--check]"; exit 2 ;;
esac
repo_dir=$(cd -- "$(dirname -- "$0")" && pwd)
ran_dir=${RAN_DIR:-/home/mohit/Desktop/OpenRAN_Testbeds/Split_7.2/ocudu_parent}
ran_lib="$ran_dir/dpdk-23.11/install/lib/x86_64-linux-gnu"
ran_gnb="$ran_dir/ocudu_latest/build-dpdk/apps/gnb/gnb"
ran_bind="$ran_dir/dpdk-23.11/usertools/dpdk-devbind.py"

# Adapt these together with gnb.yml and ru_config.cfg for another host.
nic=ens7f1
vf_pci=0000:75:10.1
vf_mac=ec:e7:a7:0f:7c:02

[[ -x "$ran_gnb" && -f "$ran_bind" && -d "$ran_lib" ]] || {
  echo 'Builds not found. Set RAN_DIR to the installed OCUDU/DPDK parent directory.'
  exit 1
}
if [[ "$mode" == --check ]]; then
  exec env LD_LIBRARY_PATH="$ran_lib" "$ran_gnb" -c "$repo_dir/gnb.yml" --dryrun
fi
if (( EUID != 0 )); then
  exec sudo env RAN_DIR="$ran_dir" "$0" "$mode"
fi
if systemctl is-active --quiet ocudu-ran650-gnb; then
  echo 'OCUDU RAN650 is already running; no settings changed.'
  exit 0
fi
if [[ "$mode" == start ]]; then
  docker inspect open5gs_5gc --format '{{.State.Health.Status}}' | grep -qx healthy || {
    echo 'Start the Open5GS core first: sudo docker compose up -d --wait 5gc'
    exit 1
  }
fi
for clock_service in chrony chronyd systemd-timesyncd ntp; do
  if systemctl is-active --quiet "$clock_service"; then
    echo "Stop $clock_service before using phc2sys to synchronize the host clock."
    exit 1
  fi
done

ip link set "$nic" mtu 9000 up
if [[ $(cat "/sys/class/net/$nic/device/sriov_numvfs") == 0 ]]; then
  echo 1 > "/sys/class/net/$nic/device/sriov_numvfs"
fi
actual_vf=$(basename "$(readlink -f "/sys/class/net/$nic/device/virtfn0")")
[[ "$actual_vf" == "$vf_pci" ]] || { echo "Unexpected VF PCI address: $actual_vf"; exit 1; }
# Hardware inserts VLAN 3 on TX and admits it on RX. gnb.yml sends untagged frames.
ip link set "$nic" vf 0 mac "$vf_mac" vlan 3 spoofchk off trust off
modprobe vfio-pci
python3 "$ran_bind" --bind=vfio-pci "$vf_pci"
if (( $(cat /proc/sys/vm/nr_hugepages) < 1024 )); then
  echo 1024 > /proc/sys/vm/nr_hugepages
fi
(( $(cat /proc/sys/vm/nr_hugepages) >= 1024 )) || { echo 'Could not allocate hugepages.'; exit 1; }

if ! systemctl is-active --quiet ocudu-ran650-ptp; then
  systemd-run --collect --unit=ocudu-ran650-ptp --property=Restart=on-failure \
    /usr/sbin/ptp4l -i "$nic" -f "$repo_dir/ptp4l-domain24.conf" -m
fi
locked=false
for ((attempt=0; attempt<60; attempt++)); do
  status=$(pmc -u -b 0 -d 24 'GET PORT_DATA_SET' 'GET TIME_STATUS_NP' 2>/dev/null)
  if awk '
    /portState/ {slave=($2=="SLAVE")}
    /gmPresent/ {gm=($2=="true")}
    /master_offset/ {offset=$2; measured=1}
    END {exit !(slave && gm && measured && offset>-1000 && offset<1000)}
  ' <<< "$status"; then
    locked=true
    break
  fi
  sleep 1
done
[[ "$locked" == true ]] || { echo 'PTP has not converged; gNB not started.'; exit 1; }

if ! systemctl is-active --quiet ocudu-ran650-phc; then
  systemd-run --collect --unit=ocudu-ran650-phc --property=Restart=on-failure \
    /usr/sbin/phc2sys -s "$nic" -c CLOCK_REALTIME -w -m -n 24
fi
locked=false
for ((attempt=0; attempt<60; attempt++)); do
  status=$(journalctl -u ocudu-ran650-phc --since '-5 seconds' -n 20 -o cat --no-pager)
  if systemctl is-active --quiet ocudu-ran650-phc && awk '
    /CLOCK_REALTIME phc offset/ {
      for (i=1; i<=NF; i++) if ($i=="offset") {offset=$(i+1); state=$(i+2); measured=1}
    }
    END {exit !(measured && (state=="s2" || state=="s3") && offset>-1000 && offset<1000)}
  ' <<< "$status"; then
    locked=true
    break
  fi
  sleep 1
done
[[ "$locked" == true ]] || { echo 'System clock has not converged; gNB not started.'; exit 1; }
if [[ "$mode" == --prepare ]]; then
  echo 'Host timing ready. Check RU PTP lock and Radio bringup complete, then run this script without --prepare.'
  exit 0
fi

LD_LIBRARY_PATH="$ran_lib" "$ran_gnb" -c "$repo_dir/gnb.yml" --dryrun
systemd-run --collect --unit=ocudu-ran650-gnb --property=KillSignal=SIGINT \
  --property=TimeoutStopSec=30 --property=LimitMEMLOCK=infinity --property=LimitRTPRIO=99 \
  --setenv="LD_LIBRARY_PATH=$ran_lib" --working-directory="$repo_dir" \
  /usr/bin/chrt -f 99 "$ran_gnb" -c "$repo_dir/gnb.yml"
sleep 5
systemctl is-active --quiet ocudu-ran650-gnb || {
  journalctl -u ocudu-ran650-gnb -n 30 --no-pager
  exit 1
}
echo 'OCUDU is running. Log: /tmp/gnb-benetel.log'
echo 'Stop gNB: sudo systemctl stop ocudu-ran650-gnb'
