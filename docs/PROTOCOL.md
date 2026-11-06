# Nommo V2 Pro: HID protocol notes

What is known about how the Razer Nommo V2 Pro (USB `1532:055A`) is controlled over USB, as worked out for this
project. Everything here was observed on one speaker pair; nothing is documented by Razer. Where something is
inferred or untested, it says so.

If you have a different speaker (Nommo V2, V2 X, the older Nommo Pro) and want to compare notes, see
[CONTRIBUTING.md](../CONTRIBUTING.md#other-speakers).

## Contents

- [Transport](#transport)
- [Packet format](#packet-format)
- [The speaker says "OK" to everything](#the-speaker-says-ok-to-everything)
- [Verified commands](#verified-commands)
- [Lighting](#lighting)
- [EQ](#eq)
- [Things that are not on the speaker](#things-that-are-not-on-the-speaker)
- [A command to avoid](#a-command-to-avoid)
- [Not understood yet](#not-understood-yet)
- [How this was found](#how-this-was-found)

## Transport

The speaker has one HID interface (interface 0, usage page `0x0C`, consumer control). Its report descriptor
declares:

| Report ID | Type | Size | Use |
|---|---|---|---|
| `0x01` | Input | 1 byte | Media keys |
| `0x03` | Output | 91 bytes | Not a command channel (see below) |
| `0x05` | Input | 15 bytes | Never observed carrying data |
| `0x07` | Feature | 90 bytes (+ ID) | **The control channel** |

All control happens through **feature report 7**: `SET_FEATURE` to send a command, then `GET_FEATURE` to read the
reply. On macOS that is `IOHIDDeviceSetReport` / `IOHIDDeviceGetReport` with report type `kIOHIDReportTypeFeature`
and report ID 7; no kernel extension or special entitlement is needed.

Output report 3 was tried with Razer-format packets, single-byte frames and colour-fill frames. It produced no
reply and no visible change. The 15-byte input report never delivered data, and the speaker pushes no
notifications.

## Packet format

The same 90-byte command format that Razer uses across its other peripherals (and that
[OpenRazer](https://github.com/openrazer/openrazer) documents), with report ID 7 prepended: 91 bytes in total.

```
offset  size  meaning
  0      1    report ID (always 0x07)
  1      1    status (0 on a new command; see below for replies)
  2      1    transaction ID
  3      2    remaining packets (0)
  5      1    protocol type (0)
  6      1    size of the argument block in bytes
  7      1    command class
  8      1    command ID
  9     80    arguments (zero-padded)
 89      1    checksum: XOR of bytes 3 through 88
 90      1    reserved (0)
```

- **Transaction ID:** Synapse counts `0x00` to `0x1F` and wraps, and that is what the app does. Other values
  (`0xFF`, `0x3F`) also get replies, but only the counter was checked against what Synapse sends. The ID is echoed
  in the reply.
- **Getters** use the command ID with the top bit set: setting brightness is `0x0F/0x04`, reading it is `0x0F/0x84`.
- **Reply:** after each `SET_FEATURE`, read the feature report back. Status `2` means done, `1` means busy (poll
  again; Synapse polls up to roughly eight times after an EQ preset change). A reply to a getter carries its
  data in the argument block.

A real packet captured from Synapse (a solid red lighting frame), shown without the trailing zero padding:

```
07 00 07 00 00 00 29 0f 03 | 00 00 00 00 0b | ff 00 00  ff 00 00  ...(12 LEDs)... | 2e 00
 id st txn  rem  pr sz cl cm   header           R  G  B                              crc rsv
```

This packet is one of the test vectors in the Swift unit tests (`Tests/NommoKitTests`).

## The speaker says "OK" to everything

The most important thing to know before probing it: **the speaker answers status `2` (OK) to every command,
including ones it does not implement**, and simply echoes the request back in the reply. That means:

- A write returning "OK" proves nothing.
- You can only trust a command if you can read the effect back, or observe it directly (a light changes, the
  sound changes).
- Getters that really exist return data that differs from the echo. That is how the implemented set was mapped.

Implemented getters found by scanning classes `0x00` to `0x3F`: `00/82`, `00/84`, `00/87`, `07/83`, `07/88`, `08/82`,
`08/84`, `08/87`, `08/88`, `0F/84`.

## Verified commands

"Verified" means a change was confirmed either by reading the value back, or by seeing/hearing the result.

| Command | Arguments | Notes |
|---|---|---|
| `00/82` get | none | Serial number as ASCII. |
| `0F/04` set, `0F/84` get | `[01 00 LL]` | Brightness, `LL` = 0 to 255. Visibly dims the lights; reads back in `data[2]`. |
| `08/02` set, `08/82` get | `[01 PP]` | EQ preset. Game = 1, Music = 2, Movie = 3, Custom = 4. Reads back in `data[1]` (Custom reads back as `0x10`). |
| `08/04` set, `08/84` get | `[00 b1 … b10]` | Ten EQ band gains. `0x0C` is flat. **Audibly applies** (verified by ear with bass- and treble-boosted test scales). Reads back in `data[1…10]`. |
| `00/04` set | `[03 00]` | Device mode 3: software lighting. Sent before streaming lighting frames. |
| `00/84` | `[00 00]` | Sent by Synapse before the mode change. Purpose unknown; harmless. |
| `0F/02` set | `[00 00 08 00 00 00]` | Select effect `0x08`, "custom frames". |
| `0F/03` set | see below | One lighting frame. |

## Lighting

**The speaker has no effect engine you can drive.** Synapse renders every effect on the PC and streams frames to
the speaker. The sequence, from the capture:

1. `00/84 [00 00]`
2. `00/04 [03 00]`: device mode 3
3. `0F/02 [00 00 08 00 00 00]`: effect 8, custom frames
4. A stream of `0F/03` frames

Each frame has a 41-byte argument block:

```
00 00 00 00 0B   then   12 × (R, G, B)
```

- **12 LEDs.** `0x0B` is the last LED index. Frames are sent without waiting for a reply.
- **LED map** (confirmed by looking at the speakers): LEDs 0 to 5 are the **right** speaker and LEDs 6 to 11 are
  the **left** speaker. The six LEDs in a speaker are diffused into a single visible colour, so in practice each
  speaker is one zone.
- **Rate:** about 18 to 25 frames a second for animated effects. A solid colour is a keepalive: Synapse repeats the
  same frame about every five seconds; the app here sends one every half second.
- **Releasing the lights:** stop sending frames and the speaker returns to its built-in colour cycle after a moment.
  There is no "release" command.
- **Brightness 0:** Synapse also stops its frame stream when brightness is set to 0.

The other lighting commands people would reasonably guess did not work on this speaker: the extended-matrix
effect command (`0F/02` with static, spectrum or "none" effects, under several transaction IDs and LED IDs), the
standard matrix commands (class `0x03`), per-LED RGB, and colour frames on output report 3. Only the sequence above
changes colour.

## EQ

- **Presets** are stored in the speaker. Their curves are *not* readable: selecting Game, Music or Movie does not change
  the band registers. The app therefore shows them as built in.
- **Custom bands** are written with `08/04`. They are held by the speaker and applied to the audio, with no host
  processing, once the Custom preset is active. (Synapse for Windows applies Custom EQ in software instead and
  never sends this command, but the speaker honours it.)
- **Scale:** the app assumes one raw step is 1 dB (so raw 0 to 24 is ±12 dB). Direction was confirmed by ear; the
  exact number of dB per step has not been measured.
- **Band centres** (31 Hz to 16 kHz in ten octave steps) are taken from OpenRazer's notes on the sibling Nommo V2 X, not
  measured on this speaker.
- The app selects Custom before writing bands, since the bands only matter under Custom.

## Things that are not on the speaker

- **THX Spatial Audio.** Turning it on in Synapse sends nothing to the speaker; it is a Windows audio effect
  applied on the PC before the sound reaches the speaker. There is nothing to switch on over USB. (The app's Space
  tab is a separate, original effect, not THX.)
- **Custom EQ in Synapse** is likewise software on Windows (see above).
- **Firmware and power-saving commands** were not captured.

## A command to avoid

The sibling Nommo V2 X documents `08/0A` as the **audio source** (`3` Bluetooth, `4` USB). A blind write into class
`0x08` while probing this speaker coincided with it dropping off USB and switching to Bluetooth; it had to be switched
back with the speaker's own button. The app deliberately has no code path for that command. If you probe,
prefer getters and commands you can read back.

## Not understood yet

- `08/07` (read back with `08/87`) accepts values 0 to 7, `08/08` accepts 0 or 1, and `07/08` accepts 0 or 1. None of them
  had a visible or audible effect.
- `07/03` (reads `0384`, which would be 900 as a big-endian number, an idle timeout on the sibling model) does not
  change when written on this speaker.
- `00/87` returns `01 06 01 00 01 05 01 00 01 01`, plausibly hardware or firmware versions.
- The real curves behind the Game, Music and Movie presets.
- Whether custom EQ bands survive a power cycle.

## How this was found

1. **Reading the device.** The HID report descriptor and an enumeration of implemented getters, plus probing with Razer
   command classes from OpenRazer. This found brightness and the EQ, but not colour.
2. **Capturing Synapse.** Razer's Synapse for Mac does not support this speaker, so Synapse 4 for Windows was run in
   a Windows 11 ARM virtual machine with the speaker passed through. USBPcap has no ARM64 driver, so the calls were
   observed instead with [Frida](https://frida.re), hooking `NtDeviceIoControlFile` in the Synapse process and
   matching the HID feature-report IOCTLs (`IOCTL_HID_SET_FEATURE` `0xB0191` and `IOCTL_HID_GET_FEATURE` `0xB0192`).
   Path-based hooks on `kernel32` and `hid.dll` missed them, because these HID handles cannot be resolved to paths.
3. **Replaying on macOS** with `hidapi`, and then confirming each command against the real speaker: by reading values
   back, by watching the lights, and by listening to test tones.

This is interoperability research on hardware the author owns. No Razer software, drivers, firmware or assets are
included in this repository.

Related reading:

- [openrazer/openrazer#2468](https://github.com/openrazer/openrazer/issues/2468): open request for Nommo V2 Pro support.
- [openrazer/openrazer#2758](https://github.com/openrazer/openrazer/issues/2758): notes on the sibling Nommo V2 X, which
  helped with the audio command classes.
