# RAN650 troubleshooting

The Pixel 8 Pro attached successfully on 14 October 2026 with the configs in this repository. Start with the [run steps](README.md#run-the-setup).

## What was fixed

| Symptom | Cause and fix |
| --- | --- |
| RU never finishes initialization | PTP arrived after its startup retries had expired. Stabilize timing, then reboot the RU. |
| RU management becomes unreachable after creating a VF | PF and VF shared a MAC. Keep the PF at `…:01`, set VF 0 to `…:02`, and use `…:02` in both RU DU-MAC fields. |
| gNB runs but no downlink reaches the RU | The NIC reported spoofed packets and dropped the VF's tagged traffic. Disable spoof checking on this dedicated fronthaul VF. |
| RU sends uplink, but DPDK receives almost nothing | VLAN filtering excluded the incoming traffic. Assign VLAN 3 to VF 0 and omit software VLAN tags from `gnb.yml`. |
| Malformed compression headers / no PRACH decode | The old FlexRAN workaround produced incompatible PRACH data. Set `flexran_prach_workaround=disabled` with dynamic BFP9 compression. |
| Phone cannot see the cell | Check the fixes above, frequency, antennas and distance. The successful run used SSB setting `0`, RU power 27 dBm, and four 30 dB attenuators. |

The final configuration succeeded with all these changes together. The SSB change was not tested separately from the fronthaul and compression fixes.

## Quick checks

### Timing

```bash
sudo pmc -u -b 0 -d 24 'GET PORT_DATA_SET' 'GET TIME_STATUS_NP'
sudo journalctl -u ocudu-ran650-phc -n 10 --no-pager
```

Expect `SLAVE`, `gmPresent true`, and small stable offsets (normally tens of nanoseconds in this lab). `SLAVE` alone is insufficient if the offset is still large.

### Fronthaul NIC

```bash
ip -d link show ens7f1
lspci -nnk -s 75:10.1
sudo journalctl -k --since '-2 minutes' | grep -i spoof
```

Expect MTU 9000; VF 0 with MAC `ec:e7:a7:0f:7c:02`, VLAN 3, spoof checking off; and `vfio-pci` on the VF. Keep the physical interface on `ixgbe`. Do not enable DPDK promiscuous mode for this tested VF setup: the driver rejected it.

The host assigns the VLAN, so `gnb.yml` deliberately has no `vlan_tag_cp/up`. Adding them would duplicate tagging. Ordinary `tcpdump` on the physical interface may not see DPDK VF traffic; an empty capture is not proof that fronthaul stopped.

### RU

Connect with `ssh root@10.10.0.100`, then run:

```bash
tail -20 /tmp/logs/radio_sync_status
tail -30 /tmp/logs/radio_status
for reg in C0300 C0302 C0315 C0316 C0319 C031A C0354; do
  registercontrol -r "$reg"
done
```

For this firmware/config, expect:

```text
C0300 = 0x01010101   TX mask
C0302 = 0x00000101   RX mask
C0315 = 0xa70f7c02   U-plane DU MAC, low part
C0316 = 0x0000ece7   U-plane DU MAC, high part
C0319 = 0xa70f7c02   C-plane DU MAC, low part
C031A = 0x0000ece7   C-plane DU MAC, high part
C0354 = 0x000000ff   Dynamic compression without the FlexRAN override
```

Read the traffic counters twice a few seconds apart:

```bash
for reg in C0342 C0344 C0346 C0348 C034A C034C; do
  registercontrol -r "$reg"
done
```

`C0342` (on-time U-plane) and `C0348` (on-time C-plane) should increase. `C0344/C034A` count early packets; `C0346/C034C` count late packets. If traffic is missing, check Falcon VLAN 3 membership on ports 1/1 and 1/2 and the VF settings above.

Make lasting RU changes in `/etc/ru_config.cfg`, then reboot with PTP available. The old firmware 1.0.4 M-plane initialization and manual antenna-mask repairs are not needed for this verified firmware 2.1.0 setup.

### Phone and core

- No network visible: verify radio bringup, on-time downlink traffic, n78 frequency and antenna distance. With 30 dB attenuators on all four paths, start nearby.
- Visible but not attaching: check PRACH compression, uplink reception, then RRC/NGAP logs.
- Authentication failure: check the SIM credentials. In the successful run, an initial sequence-number synchronization failure recovered automatically and was followed by `Registration complete`.
- Registered but no data session: check APN `srsapn` and subscriber slice SST `1`.
- Data session exists but no traffic: check N3 addressing (`10.53.1.1` on the host), routing, forwarding/NAT, and DNS in the core.
- Subscriber disappears after core recreation: save it in the startup CSV or persist MongoDB `/data/db` in a Docker volume.

Use the phone IP reported by the SMF, not a fixed assumption. Keep PHY/MAC packet-level logging and packet captures off during normal use; they grow quickly under traffic.
