# OCUDU Split 7.2: Benetel RAN650 + Falcon

Working lab setup, verified on **14 October 2026** with a **Pixel 8 Pro**: SIM registration, an `srsapn` data session, and host-to-phone ping all succeeded. The old cell-visible-but-no-attach setup has been replaced.

## Tested setup

| Item | Value |
| --- | --- |
| RU | Benetel RAN650, hardware 1.3.1, firmware `RAN650-1v2.1.0-NM-0820797` |
| Switch | Falcon-RX/812/G, management `192.168.1.90` |
| Software | OCUDU `c5acfa5d4c`, DPDK 23.11, Open5GS 2.7.6 |
| Host | Intel X550-T2, real-time Linux, IOMMU/SR-IOV enabled |
| Cell | n78, 3558.18 MHz, ARFCN `637212`, 100 MHz, 30 kHz SCS, 4T2R |
| Network | PLMN `00101`, TAC `7`, SST `1`, APN/DNN `srsapn` |
| Timing / fronthaul | PTP domain `24`, native VLAN `1588`; C/U-plane VLAN `3` |
| RF | RU power `27 dBm`; 30 dB attenuator on each of the four antenna paths |

```text
Host ens7f1 (10G) ── Falcon port 1/1
Benetel Fiber 1   ── Falcon port 1/2
Host eno1 (1G)   ── Falcon management port 1/21
GNSS antenna    ── Falcon GNSS input
```

The host management addresses are `192.168.1.50/24` on `eno1` and `10.10.0.1/24` on `ens7f1`. The RU is at `10.10.0.100`.

## Files

- [gnb.yml](gnb.yml): tested OCUDU configuration, including the Docker core addresses.
- [ru_config.cfg](ru_config.cfg): tested RU settings for firmware 2.1.0.
- [ptp4l-domain24.conf](ptp4l-domain24.conf): host PTP configuration.
- [start-ran650.sh](start-ran650.sh): host preparation and gNB startup.
- [Troubleshooting](Troubleshoot_Network_Not_Visible.md): the faults found and checks to use.

## One-time setup

### Falcon

Configure GNSS/PTP using the [Falcon guide](https://docs.srsran.com/projects/project/en/latest/tutorials/source/oranRU/source/switches/falcon.html#falcon-rx-switch). Use L2 PTP, domain 24, and VLAN 1588. Wait for GNSS lock and a green SyncCenter status.

On the switch CLI, allow VLAN 3 on both fronthaul ports:

```text
configure terminal
vlan 3
exit
interface 10GigabitEthernet 1/1
switchport mode trunk
switchport trunk native vlan 1588
switchport trunk allowed vlan 1,2,3,1588
exit
interface 10GigabitEthernet 1/2
switchport mode trunk
switchport trunk native vlan 1588
switchport trunk allowed vlan 1,2,3,1588
exit
end
copy running-config startup-config
```

Keep management port `GigabitEthernet 1/21` unchanged. PTP lock alone does not prove VLAN 3 is passing fronthaul traffic.

### Host and software

These instructions use the existing lab builds; the script does not install software or flash the RU. Install `linuxptp` and have Docker Compose, Python 3, and a DPDK-enabled OCUDU build available. The tested host uses CPU governor `performance` and kernel options `intel_iommu=on iommu=pt`.

The script defaults to these installed paths under:

```text
/home/mohit/Desktop/OpenRAN_Testbeds/Split_7.2/ocudu_parent/
  ocudu_latest/build-dpdk/apps/gnb/gnb
  dpdk-23.11/install/lib/x86_64-linux-gnu/
  dpdk-23.11/usertools/dpdk-devbind.py
```

For another installation, pass `sudo env RAN_DIR=/your/builds ./start-ran650.sh`. Adapt the NIC, PCI and MAC addresses in both the script and configs. See the [OCUDU installation guide](https://docs.ocudu.org/user_manual/installation/) for building the software.

The physical interface `ens7f1` stays on the kernel driver for PTP and RU management. DPDK uses only VF 0, `0000:75:10.1`:

| Interface | MAC |
| --- | --- |
| Host physical interface | `ec:e7:a7:0f:7c:01` |
| DPDK VF / RU's configured DU address | `ec:e7:a7:0f:7c:02` |
| RU primary fronthaul address | `8c:1f:64:d1:12:e0` |

**VLAN 3 is assigned to the VF by the host.** Do not add `vlan_tag_cp` or `vlan_tag_up` to this `gnb.yml`; the NIC inserts the tag. Keep the PF and VF MACs different.

### RU

Use the settings in `ru_config.cfg` for the tested firmware. Back up the existing file before installing it from this repository:

```bash
ssh root@10.10.0.100 'cp -p /etc/ru_config.cfg /etc/ru_config.cfg.before-ocudu'
scp ru_config.cfg root@10.10.0.100:/etc/ru_config.cfg
```

Check `cat /etc/ru-sync-mode` on the RU: it should be `PTP`. Reboot the RU after host timing is ready, as described below.

The important changes are short PRACH, dynamic compression, `flexran_prach_workaround=disabled`, and both DU MAC fields set to the VF MAC ending in `02`. The old long-PRACH experiment and firmware 1.0.4 register repair steps are not part of this setup.

### Core and SIM

The config expects Open5GS at `10.53.1.2`, with the host's N2/N3 address `10.53.1.1`. Use PLMN `001/01`, TAC `7`, SST `1`, and DNN `srsapn`. Provision your SIM's IMSI, Ki and OPC privately in the core; no SIM secrets are stored here.

Save subscriber entries in the core's startup CSV. Without a persistent MongoDB volume at `/data/db`, container recreation loses database-only changes. A normal container restart and a Compose recreation are different; `compose up` can recreate a container when its configuration changes.

## Run the setup

Run the following after the one-time setup. Do not run extra copies of `ptp4l` or `phc2sys` alongside the script; the lab host uses them instead of an NTP service to control its clock.

**1. Power on the Falcon and wait for GNSS/PTP lock. Start the core:**

```bash
cd /home/mohit/Desktop/5gCore/ocudu_parent/ocudu/docker
sudo docker compose up -d --wait 5gc
```

**2. From this repository, prepare the host:**

```bash
cd /path/to/OCUDU-Split7.2
sudo ./start-ran650.sh --prepare
```

This sets MTU 9000, prepares VF 0 and 2 GiB of hugepages, and starts PTP and system-clock synchronization. It waits for both clocks to converge before returning.

**3. Check the RU:**

```bash
ssh root@10.10.0.100
# Reboot if you changed ru_config.cfg or the log says initialization failed:
reboot
```

After it comes back, reconnect and check:

```bash
tail -20 /tmp/logs/radio_sync_status
tail -30 /tmp/logs/radio_status
```

Wait for `O-RU in PTP locked state`, `Transmission enabled (4x2)` and `Radio bringup complete`. Startup takes a few minutes. If the RU exhausted its synchronization retries before the Falcon was ready, reboot it now.

**4. Back on the host, start OCUDU:**

```bash
sudo ./start-ran650.sh
```

**5. Connect the Pixel:** insert the provisioned SIM, set APN `srsapn`, enable mobile data/5G, toggle airplane mode, and select `00101` / `OCUDU` if needed. With the four 30 dB attenuators, begin about 0.5–1 metre from the antennas. Disable Wi-Fi when testing cellular data.

**6. Check the result:**

```bash
systemctl is-active ocudu-ran650-ptp ocudu-ran650-phc ocudu-ran650-gnb
tail -f /tmp/gnb-benetel.log
docker logs --since 5m open5gs_5gc 2>&1 | grep -E 'Registration complete|IPv4\['
```

Successful registration and a PDU session confirm attachment. The verified phone received `10.45.0.4` and answered 4/4 host pings; its dynamically allocated address may change. To ping from the host, ensure a route to the UE subnet exists:

```bash
sudo ip route replace 10.45.0.0/24 via 10.53.1.2
ping <phone-IP>
```

The core also needs forwarding/NAT for the desired data path. Registration alone does not verify Internet access.

Stop only the gNB with `sudo systemctl stop ocudu-ran650-gnb`. Leave the timing services running while the RU is in use. The script starts transient services; rerun it after a host reboot.
