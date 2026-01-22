# srsRAN-Benetel

## Switch setup

Turn on the switch and connect it to workstation using one usb cable (red usb port on switch)

ls /dev/tty\*

sudo apt install minicom
sudo minicom -b 115200 -D /dev/ttyUSB0

CTRL A O
This opens the configuration menu.

Go to
Serial port setup

Check these values:

Serial Device: /dev/ttyUSB0

Bps/Par/Bits: 115200 8N1

Hardware Flow Control: Off

Software Flow Control: Off

Save setup as dfl

Username: moose
Password: 1234

Falcon#
configure terminal
interface vlan 1
ip address 192.168.1.90 255.255.255.0
exit

power cycle the switch

connect ethernet from Mgmt on switch to your PC
give the connected ethernet this manual address on the pc
192.168.1.50
Netmask 255.255.255.0

ping 192.168.1.90

Log in via Web GUI

http://192.168.1.90

Username: moose
Password: 1234
