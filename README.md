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
sudo ptp4l -f ~/ptp4l.conf -i ens7f1 -m
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

That means ens7f1 hardware clock is synchronized to the Falcon Grandmaster

Now we move into the RU Integration (Open Fronthaul)
