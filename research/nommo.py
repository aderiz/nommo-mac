"""Nommo V2 Pro control over HID feature report 7, mirroring what Synapse (Windows) sends.

Observed in a capture of Razer Synapse for Windows (see docs/PROTOCOL.md):
  lighting start : 00/84 [00 00]  ->  00/04 [03 00] (software mode)  ->  0F/02 [00 00 08 00 00 00]
  lighting frame : 0F/03, args = 00 00 00 00 0B + 12 x (R,G,B)    (streamed; static is a ~5 s keepalive)
  brightness     : 0F/04 [01 00 LL]
  EQ preset      : 08/02 [01 PP]   Game=1 Music=2 Movie=3 Custom=4
  EQ bands (device-verified on macOS): 08/04 [00 b1..b10], 0x0C = flat
"""
import time
import hid

VID, PID = 0x1532, 0x055A
N_LEDS = 12


class Nommo:
    def __init__(self):
        self.dev = hid.device()
        self.dev.open(VID, PID)
        self.txn = 0

    def close(self):
        self.dev.close()

    # ---- low level -------------------------------------------------
    def _packet(self, cls, cmd, args):
        b = bytearray(90)
        b[1] = self.txn & 0x1F
        self.txn = (self.txn + 1) & 0x1F
        b[5] = len(args)
        b[6], b[7] = cls, cmd
        b[8:8 + len(args)] = bytes(args)
        crc = 0
        for x in b[2:88]:
            crc ^= x
        b[88] = crc
        return bytes([7]) + bytes(b)

    def set(self, cls, cmd, args, poll=True, timeout=1.0):
        """SET then (like Synapse) poll GET until status == 2. Returns final status or None."""
        self.dev.send_feature_report(self._packet(cls, cmd, args))
        if not poll:
            return None
        t = time.time()
        while time.time() - t < timeout:
            time.sleep(0.01)
            r = bytes(self.dev.get_feature_report(7, 91))
            if r[1] == 2:
                return 2
        return r[1]

    def get(self, cls, cmd, args=()):
        self.set(cls, cmd, list(args), poll=False)
        time.sleep(0.05)
        return bytes(self.dev.get_feature_report(7, 91))[9:9 + 16]

    # ---- lighting --------------------------------------------------
    def lighting_start(self):
        self.set(0x00, 0x84, [0, 0])
        self.set(0x00, 0x04, [3, 0])               # software/driver mode
        self.set(0x0F, 0x02, [0, 0, 8, 0, 0, 0])   # custom-frame effect

    def frame(self, leds):
        """leds: list of 12 (r,g,b) tuples."""
        assert len(leds) == N_LEDS
        args = [0, 0, 0, 0, N_LEDS - 1]
        for r, g, b in leds:
            args += [r, g, b]
        self.set(0x0F, 0x03, args, poll=False)

    def solid(self, rgb):
        self.frame([tuple(rgb)] * N_LEDS)

    def brightness(self, level):
        self.set(0x0F, 0x04, [1, 0, level])

    # ---- audio -----------------------------------------------------
    def eq_preset(self, preset):
        self.set(0x08, 0x02, [1, preset])

    def eq_bands(self, gains):
        assert len(gains) == 10
        self.set(0x08, 0x04, [0] + list(gains))
