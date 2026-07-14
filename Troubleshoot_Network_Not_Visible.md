# RAN650 Cell Broadcast and Troubleshooting

This document records the configuration that made the `00101` n78 network visible on a Google Pixel 8. It also records the checks that isolated the fault, because a synchronized and operational RU does not necessarily mean that Open Fronthaul traffic is reaching the radio.

> Current result: the Pixel 8 can discover the network. UE attachment is not yet working. No PRACH is decoded by the gNB, so authentication and the Open5GS subscriber configuration are not yet involved in the failure.

## Hardware and software snapshot

```text
DU NIC:             ens7f1
DU NIC MAC:         ec:e7:a7:0f:7c:01
DU management IP:   10.10.0.1/24

Falcon management:  192.168.1.90
Falcon DU port:      10GigabitEthernet 1/1
Falcon RU port:      10GigabitEthernet 1/2

RAN650 management:  10.10.0.100
RAN650 primary MAC:  8c:1f:64:d1:12:e0
RAN650 secondary:    8c:1f:64:d1:12:e1
RAN650 firmware:     RAN650-1v1.0.4-dda1bf5
RAN650 hardware:     1.3.1

OCUDU commit:        45b51f9a27
Band/frequency:      n78 / 3410.1 MHz
Bandwidth/MIMO:      100 MHz / 4T2R
PLMN/PCI/TAC:        00101 / 1 / 7
OFH CP/UP VLAN:      3
PTP domain:          24
```

The primary RAN650 MAC ending in `e0` is the correct `ru_mac_addr`. The secondary MAC ending in `e1` did not receive gNB fronthaul traffic in this setup.

## Root cause of the invisible cell

The gNB transmitted valid Open Fronthaul frames from `ens7f1`, but the RAN650 received no VLAN 3 frames. A DU-side capture showed small C-plane frames and large U-plane frames, while RU-side packet and MAC counters showed none.

The Falcon contained VLANs `1`, `2`, and `1588`, but VLAN `3` did not exist. PTP could therefore lock successfully on VLAN 1588 while all CP/UP fronthaul traffic on VLAN 3 was discarded.

Creating and trunking VLAN 3 across the DU and RU ports was the decisive fix that made the cell appear on the phone.

## Falcon VLAN 3 fix

Verify the learned port mapping:

```text
show mac address-table
```

The PTP entries identified the ports:

```text
Dynamic 1588 8c:1f:64:d1:12:e0 10GigabitEthernet 1/2
Dynamic 1588 ec:e7:a7:0f:7c:01 10GigabitEthernet 1/1
```

Create VLAN 3 and allow it on the DU and RU trunks:

```text
configure terminal
vlan 3
interface 10GigabitEthernet 1/1
switchport trunk allowed vlan 1,2,3,1588
exit
interface 10GigabitEthernet 1/2
switchport trunk allowed vlan 1,2,3,1588
exit
end
```

Verify and save:

```text
show vlan
show running-config interface 10GigabitEthernet 1/1
show running-config interface 10GigabitEthernet 1/2
show mac address-table
copy running-config startup-config
```

Expected VLAN membership:

```text
VLAN  Name       Interfaces
----  ---------  ----------
1     default    Gi 1/21 10G 1/1-20
2     VLAN0002   10G 1/1-20
3     VLAN0003   10G 1/1-2
```

Both fronthaul interfaces should contain:

```text
switchport trunk native vlan 1588
switchport trunk allowed vlan 1-3,1588
switchport mode trunk
```

Do not change the management port, `GigabitEthernet 1/21`.

## Verify fronthaul before changing RF parameters

Configure and inspect the DU NIC:

```bash
sudo ip link set ens7f1 mtu 9000 up
ip -details link show ens7f1
sudo tcpdump -nn -e -i ens7f1 'vlan 3' -c 20
```

Expected observations:

- Source MAC is `ec:e7:a7:0f:7c:01`.
- Destination MAC is `8c:1f:64:d1:12:e0`.
- VLAN ID is `3`.
- Small frames are OFH C-plane traffic.
- Frames around 7.6 kB are OFH U-plane traffic.

Falcon port counters provide another useful check:

```text
show interface 10GigabitEthernet 1/1 statistics
show interface 10GigabitEthernet 1/2 statistics
```

Port `1/1` should receive jumbo frames from the DU and port `1/2` should transmit them toward the RU. In the working test, `Tx 1519-` on port `1/2` increased continuously with zero oversize errors.

## RAN650 RU configuration

The initial visible-cell test used these `/etc/ru_config.cfg` values:

```ini
mimo_mode=1_2_3_4_4x2
downlink_scaling=0
prach_format=short
compression=dynamic_compressed
lf_prach_compression_enable=false
cplane_per_symbol_workaround=disabled
cuplane_dl_coupling_sectionID=disabled
flexran_prach_workaround=enabled
dl_ul_tuning_special_slot=0xfd00000
```

After boot, verify:

```bash
tail -30 /tmp/logs/radio_sync_status
tail -40 /tmp/logs/radio_status
tail -20 /tmp/logs/o_ru_app.log
```

Required state:

```text
PTP locked, synchronizing system time.
[INFO] Radio synchronized
[INFO] Radio bringup complete
[INFO] Transmission enabled (4x2)
[oper::enabled]
[availability::normal]
```

### Repairing `oper::disabled / faulty`

On this RU, sysrepo initially contained only base IETF modules. The O-RAN modules had not been initialized, leaving the RU disabled/faulty even though the radio hardware was healthy.

Back up sysrepo and check its modules:

```bash
tar -czf /home/root/sysrepo-before-firstboot-init.tgz /etc/sysrepo
sysrepoctl -l
```

If the vendor O-RAN modules are missing, run:

```bash
/usr/sbin/mplane-init.sh
mkdir -p /var/dhcp_params /etc/mplane/vlan
```

The RU also required the management IPv4 runtime status file. Store this tmpfiles entry in `/etc/tmpfiles.d/static-mplane.conf`:

```text
f /tmp/status/mplane_if_ipv4 0644 root root - 10.10.0.100\x208\x20eth0
```

After reboot and RF initialization, `o_ru_app.log` should transition from `oper::disabled` to `oper::enabled` with availability `NORMAL`.

Only run `mplane-init.sh` when the O-RAN sysrepo modules are actually missing. Back up `/etc/sysrepo` first.

## Important: volatile RAN650 registers

Firmware `1.0.4` restored factory DU MAC filters and cleared antenna masks after every RU reboot. This made the cell disappear even though VLAN 3 and the gNB configuration remained correct.

The incorrect factory filters were based on `00:11:22:33:44:66/67`. After `Radio bringup complete`, restore the real DU MAC and 4T2R masks:

```bash
registercontrol -w C0319 -x a70f7c01
registercontrol -w C031A -x ece7
registercontrol -w C0315 -x a70f7c01
registercontrol -w C0316 -x ece7
registercontrol -w C0300 -x 01010101
registercontrol -w C0302 -x 00000101
```

Register meanings:

```text
C0319/C031A  Expected DU MAC for C-plane
C0315/C0316  Expected DU MAC for U-plane
C0300        Four enabled downlink/TX paths
C0302        Two enabled uplink/RX paths
```

Verify:

```bash
for reg in C0300 C0302 C0315 C0316 C0319 C031A; do
  registercontrol -r "$reg"
done
```

Expected values:

```text
C0300 = 0x01010101
C0302 = 0x00000101
C0315 = 0xa70f7c01
C0316 = 0x0000ece7
C0319 = 0xa70f7c01
C031A = 0x0000ece7
```

Do not restart the gNB until the RU is PTP-locked, RF initialization has finished, and these registers are restored.

## gNB Open Fronthaul configuration

The important cell-broadcast settings are:

```yaml
ru_ofh:
  ru_bandwidth_MHz: 100
  t1a_max_cp_dl: 470
  t1a_min_cp_dl: 419
  t1a_max_cp_ul: 336
  t1a_min_cp_ul: 285
  t1a_max_up: 345
  t1a_min_up: 294
  ta4_max: 200
  ta4_min: 0
  is_prach_cp_enabled: false
  compr_method_ul: bfp
  compr_bitwidth_ul: 9
  compr_method_dl: bfp
  compr_bitwidth_dl: 9
  compr_method_prach: bfp
  compr_bitwidth_prach: 9
  enable_ul_static_compr_hdr: false
  enable_dl_static_compr_hdr: false
  iq_scaling: 4.5
  cells:
    - network_interface: ens7f1
      ru_mac_addr: 8c:1f:64:d1:12:e0
      du_mac_addr: ec:e7:a7:0f:7c:01
      vlan_tag_cp: 3
      vlan_tag_up: 3
      prach_port_id: [4, 5]
      dl_port_id: [0, 1, 2, 3]
      ul_port_id: [0, 1]

cell_cfg:
  dl_arfcn: 627340
  band: 78
  channel_bandwidth_MHz: 100
  common_scs: 30
  plmn: "00101"
  tac: 7
  pci: 1
  nof_antennas_dl: 4
  nof_antennas_ul: 2
  prach:
    prach_config_index: 159
    prach_root_sequence_index: 1
    zero_correlation_zone: 0
  ssb:
    ssb_block_power_dbm: 0
  tdd_ul_dl_cfg:
    dl_ul_tx_period: 10
    nof_dl_slots: 7
    nof_dl_symbols: 6
    nof_ul_slots: 2
    nof_ul_symbols: 4
```

Start the gNB with real-time priority:

```bash
cd ocudu/build/apps/gnb
sudo chrt -f 99 ./gnb -c ./gnb.yml
```

Expected startup:

```text
Cell pci=1, bw=100 MHz, 4T2R, dl_arfcn=627340 (n78), dl_freq=3410.1 MHz
N2: Connection to AMF on 127.0.1.100:38412 completed
==== gNB started ===
```

## Confirm that the RU is transmitting

Read the PDSCH counters twice:

```bash
registercontrol -r C0311
registercontrol -r C031B
sleep 2
registercontrol -r C0311
registercontrol -r C031B
```

Both values should increase. This confirms that downlink radio data is being processed and is stronger evidence than `oper::enabled` alone.

Useful Open Fronthaul counters are:

```bash
for reg in C0340 C0342 C0344 C0346 C0348 C034A C034C; do
  registercontrol -r "$reg"
done
```

```text
C0340  Total received OFH packets
C0342  On-time U-plane packets
C0344  Early U-plane packets
C0346  Late U-plane packets
C0348  On-time C-plane packets
C034A  Early C-plane packets
C034C  Late C-plane packets
```

`reportMacStatus.sh` can also confirm that `rx_stats_etherStatsPkts1519toXOctets` is increasing. A zero jumbo-frame counter while the DU transmits normally points back to the switch VLAN or MTU path.

## Pixel 8 network scan and RF power

Four suitable 50-ohm n78 antennas were connected for the OTA test.

At the original 37 dBm RU setting, the phone needed to be moved away from the antennas to avoid possible receiver saturation. During later troubleshooting, the RU was reduced to 27 dBm; at that setting the phone had to move closer before `00101` appeared again.

For an OTA test:

1. Confirm all active ports are connected to suitable antennas or rated 50-ohm loads.
2. Start at a safe distance from the RU.
3. Toggle airplane mode.
4. Open manual network selection.
5. Look for `00101`, `001 01`, or an unnamed network.

For a conducted RF setup, use correctly specified high-power attenuators. Never connect the RAN650 directly to a UE emulator, modem, or test instrument.

## Current UE attachment limitation

Cell discovery works, but the Pixel remains at `Connecting`. The gNB log shows no decoded PRACH preamble, RRC Setup, or Initial UE Message. The remaining failure is therefore before SIM authentication and Open5GS subscriber lookup.

The symptoms match [srsRAN Project issue #1118](https://github.com/srsran/srsRAN_Project/issues/1118). A legacy long-PRACH experiment was also tested on firmware `1.0.4` using:

```text
prach_format=long
prach_config_index=7
C0321=0x1
C0324=0xef780000
RU transmit power=27 dBm
iq_scaling=8
```

The cell remained visible at the appropriate distance, but no PRACH was decoded. The issue reporter achieved stable attachment only after:

1. Upgrading the RAN650 to firmware `1.4.0`.
2. Upgrading to a newer srsRAN build.
3. Enabling DPDK for Open Fronthaul processing.

These are the next planned steps. The current OCUDU process also reports repeated real-time timing-worker symbol skips, another reason to prioritize the newer build and DPDK path.

## Fast troubleshooting decision tree

```text
RU cannot be pinged
  -> Check 10.10.0.1/24 on ens7f1 and RU management cabling.

RU PTP is not locked
  -> Check Falcon GNSS/PTP, VLAN 1588, ptp4l, and phc2sys.

RU is oper::disabled / faulty
  -> Check sysrepo O-RAN modules and the M-plane runtime IP status file.

DU sends VLAN 3 but RU receives no jumbo frames
  -> Create/allow VLAN 3 on Falcon ports 1/1 and 1/2.

RU receives OFH but PDSCH counters remain zero after a reboot
  -> Restore the volatile DU MAC filters and 4T2R masks.

PDSCH counters advance but the phone cannot see 00101
  -> Check antennas, RF distance/power, ARFCN, SSB, and manual scan.

Phone sees 00101 but stays on Connecting, with no RACH in the gNB log
  -> Investigate PRACH/UL timing. For this firmware/build combination,
     proceed with the RAN650 1.4.0, newer srsRAN, and DPDK upgrade.
```
