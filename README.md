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
Falcon# configure terminal interface vlan 1 ip address 192.168.1.90 255.255.255.0 exit
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

```
