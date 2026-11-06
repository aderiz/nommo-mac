"""Read-only scan of Razer 'get' commands (cmd >= 0x80).

The Nommo answers status 0x02 (OK) to every command, including ones it does not implement, and simply
echoes the request back. Real answers are the ones whose data differs from the echo; this script prints
every OK reply so you can compare. Only getters are sent, never setters.
"""
import time, hid
VID, PID = 0x1532, 0x055A
STATUS = {1:"busy",2:"ok",3:"fail",4:"timeout",5:"timeout",6:"unsupported"}

def body(txn, cls, cmd, args=b""):
    b = bytearray(90); b[1]=txn; b[5]=len(args); b[6]=cls; b[7]=cmd; b[8:8+len(args)]=args
    c=0
    for x in b[2:88]: c^=x
    b[88]=c
    return bytes([7])+bytes(b)

dev = hid.device(); dev.open(VID, PID)
for cls in range(0x00, 0x11):
    for cmd in range(0x80, 0xA0):
        for args in (b"", bytes([1,0,0])):
            dev.send_feature_report(body(0xFF, cls, cmd, args))
            time.sleep(0.03)
            r = bytes(dev.get_feature_report(7, 91))
            if r[1] == 2 and r[7] == cls and r[8] == cmd:
                print(f"cls={cls:#04x} cmd={cmd:#04x} args={args.hex() or '-'} size={r[6]} data={r[9:9+max(r[6],8)].hex(' ')}")
dev.close()
