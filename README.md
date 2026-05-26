# Falcon-RX/812/G Switch Setup Guide

## Connecting the Switch to the Server

The switch has the following ports/interfaces:

- **USB RS232 Console Port (Red USB Port)**  
  Connect to a USB port on the server.

- **MGMT Ethernet Port**  
  Connect to a 1G Ethernet port on the server.

- **1/10G Switching Ports**  
  Connect to the 10G Ethernet port on the server.

- **GNSS ANT (5V)**  
  Connect the GNSS antenna.

---

# 1. USB Connection (Console Access)

This is used for low level console access.

It works even when:

- No IP is configured
- The network is broken
- The management interface is unreachable

You use it for:

- Initial setup
- Recovery
- Factory configuration
- Assigning the management IP
- Debugging

### Connect via USB Console

Turn on the switch and connect it to the server using a USB cable  
(red USB port on the switch).

### Check USB Serial Device

```bash
ls /dev/tty*
```

### Install and Open Minicom

```bash
sudo apt install minicom
sudo minicom -b 115200 -D /dev/ttyUSB0
```

### Configure Minicom

Press:

```text
CTRL A -> leave both -> O
```

This opens the configuration menu.

Go to:

```text
Serial port setup
```

Verify the following values:

```text
Serial Device: /dev/ttyUSB0
Bps/Par/Bits: 115200 8N1
Hardware Flow Control: Off
Software Flow Control: Off
```

Save setup as default (`dfl`).

### Login to the Switch

```text
Username: moose
Password: 1234
```

### Configure Management IP

```text
Falcon# configure terminal
Falcon(config)# interface vlan 1
Falcon(config-if-vlan)# ip address 192.168.1.90 255.255.255.0
exit
```

Power cycle the switch

---

# 2. MGMT Ethernet Port

The MGMT Ethernet port is used for:

- Web GUI access
- SSH
- Switch administration
- PTP configuration
- VLAN configuration
- Monitoring

Earlier, the following configuration assigned an IP address to the switch management interface:

```text
interface vlan 1
ip address 192.168.1.90
```

### Connect to the Management Interface

Connect an Ethernet cable from the **MGMT** port on the switch to your server.

Assign the connected Ethernet interface on the server the following manual IP:

```text
IP Address: 192.168.1.50
Netmask:   255.255.255.0
```

### Verify Connectivity

```bash
ping 192.168.1.90
```

### Access the Web GUI

Open:

```text
http://192.168.1.90
```

Login credentials:

```text
Username: moose
Password: 1234
```

---

# 3. 1/10G Switching Ports

The next phase is to configure the actual dataplane ports via the Web GUI.

These ports carry:

- Open Fronthaul
- eCPRI
- PTP
- Ethernet switching traffic
- VLAN traffic

This is the telecom dataplane.

### Example Setup

```text
Server ens7f1  -> Switch 10G Port
RU FH   -> Switch another 10G Port
```

These ports carry the actual Split 7.2 traffic between the DU and RU.

---

# 4. Falcon PTP Configuration

Next, follow the official srsRAN Falcon switch instructions:

SyncCenter: 

  - GNSS and not GPS:
  - Check the checkbox and click Apply

PTP Clocks:
  - VID -> 1588
  - There are two instaces shown. You can add all the ports to one instance and it's okay

VLAN:

- Port 21 is the Mgmt port. Keep it as shown in the image. If you change it, you will lose access to the Web GUI

https://docs.srsran.com/projects/project/en/latest/tutorials/source/oranRU/source/switches/falcon.html#falcon-rx-switch


### Verify DU Receives PTP from the Falcon

Install Linux PTP tools:

```bash
sudo apt update
sudo apt install linuxptp -y
```

### Verify ptp4l Installation

```bash
which ptp4l
```

You should get:

```text
/usr/sbin/ptp4l
```

### Verify Incoming PTP Traffic

Before running `ptp4l`, verify whether any PTP traffic exists on `ens7f1`.

```bash
sudo tcpdump -i ens7f1 -e
```

If you see traffic, your Falcon switch is successfully acting as a PTP Grandmaster and `ens7f1` is receiving telecom timing packets correctly.

Example output:

```text
tcpdump: verbose output suppressed, use -v[v]... for full protocol decode
listening on ens7f1, link-type EN10MB (Ethernet), snapshot length 262144 bytes

14:53:55.148540 00:05:80:08:78:c5 (oui Unknown) > 01:1b:19:00:00:00 (oui Unknown), ethertype PTP (0x88f7), length 60:
PTPv2, v1 compat : no, msg type : sync msg, length : 44, domain : 24,
reserved1 : 0, Flags [none], NS correction : 0,
sub NS correction : 18649088, reserved2 : 0,
clock identity : 0x580fffe0878c5, port id : 1,
seq id : 37886, control : 0 (sync msg),
log message interval : 252,
originTimeStamp : 1778939672 seconds, 146914416 nanoseconds
```


### Important Details from Captured Data

You will need the PTP domain value for the next configuration step.

Example:

```text
PTPv2
domain 24
```

### Create ptp4l Configuration

```bash
nano ~/ptp4l.conf
```

Add the following:

```text
[global]
domainNumber 24
slaveOnly 1
time_stamping hardware
network_transport L2
delay_mechanism E2E
logging_level 6
```

### Run ptp4l

```bash
ifconfig ens7f1 mtu 9600 up
sudo timedatectl set-ntp false
```
Start them in this order.

Terminal 1:
```bash
sudo ptp4l -2 -i ens7f1 -f ~/ptp4l.conf -m
```

Example output:

```text
systron@systronlab-hp-z8-1:~$ sudo ptp4l -f ~/ptp4l.conf -i ens7f1 -m

ptp4l[11262.382]: selected /dev/ptp3 as PTP clock
ptp4l[11262.412]: port 1: INITIALIZING to LISTENING on INIT_COMPLETE
ptp4l[11262.412]: port 0: INITIALIZING to LISTENING on INIT_COMPLETE
ptp4l[11262.517]: port 1: new foreign master 000580.fffe.0878c5-1
ptp4l[11262.647]: selected best master clock 000580.fffe.0878c5
ptp4l[11262.647]: updating UTC offset to 37
ptp4l[11262.647]: port 1: LISTENING to UNCALIBRATED on RS_SLAVE
ptp4l[11264.504]: port 1: minimum delay request interval 2^-4
ptp4l[11264.716]: port 1: UNCALIBRATED to SLAVE on MASTER_CLOCK_SELECTED
ptp4l[11264.968]: rms 22436429037 max 33920692332 freq -129 +/- 100 delay 2166 +/- 1
ptp4l[11265.473]: rms 8 max 13 freq -191 +/- 6 delay 2166 +/- 1
ptp4l[11265.978]: rms 8 max 12 freq -181 +/- 7 delay 2165 +/- 0
ptp4l[11266.483]: rms 4 max 9 freq -189 +/- 7 delay 2164 +/- 1
ptp4l[11266.988]: rms 4 max 8 freq -190 +/- 6 delay 2163 +/- 0
ptp4l[11267.493]: rms 4 max 8 freq -192 +/- 7 delay 2164 +/- 0
```


### Important Verification

This is the key line:

```text
UNCALIBRATED to SLAVE on MASTER_CLOCK_SELECTED
```
In the above output, the rms value can be used to determine if the PTP sync is correct, for this we look for a value < 10.
Then leave it running.

Terminal 2:
```bash
sudo phc2sys -s ens7f1 -w -m -R 8 -f ~/ptp4l.conf
```

Example output:
```text
phc2sys[4348.303]: CLOCK_REALTIME phc offset       -25 s2 freq   +8026 delay   1467
phc2sys[4348.428]: CLOCK_REALTIME phc offset       -11 s2 freq   +8033 delay   1466
```

The first value here is used to determine if the PTP sync is correct, for this we look for a value in the range of -100 to 100.


Once this works perfectly, save this configuration of the switch so that it persists even after reboots.
Log into the Falcon# terminal and run:

```text
copy running-config startup-config
```
Ouput should be:
```text
Building configuration... % Saving 6895 bytes to flash:startup-config 2026-05-21T09:18:58.095+00:00: DEVICE configuration changed (copied to startup-config) from local
```
After saving the configuration, power cycle the switch and test the PTP commands again.

Now we move into the RU Integration (Open Fronthaul)

# Benetel RAN 650 

Connect the Benetel port (Fiber 1) to Port 2 on the switch (Ports 1 and 2 were included in the setup. The srsRAN switch config documentation linked above shows 13 onwards but we also added these two ports in the list)

RU Management access:
```text
sudo ip addr add 10.10.0.1/24 dev ens7f1

ping 10.10.0.100

ssh root@10.10.0.100
```
## Next step inside the RU

Check RU synchronization state

```text
cat /var/syncmon/sync-state
```
Output should be 0 (means locked)

```text
cat /etc/ru-sync-mode
```

Output should be PTP

If you get these outputs, it means the RAN650 is synchronized via the Falcon Grandmaster

Next run,

oru_vlan_mac_info
