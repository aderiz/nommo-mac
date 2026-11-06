# Contributing

Thanks for taking an interest. This is a small, unofficial project; contributions of any size are welcome.

## Ground rules

- **Be careful with the hardware.** The speaker answers "OK" to every command, including ones it doesn't implement, so
  guessing at writes can leave it in a strange state. One write switched it to Bluetooth and dropped the USB
  connection until someone pressed a button. Prefer commands you can read back, and say in your pull request how
  you confirmed a command does what you think. See [docs/PROTOCOL.md](docs/PROTOCOL.md).
- **No Razer code or assets.** Don't contribute decompiled code, extracted firmware, drivers, or artwork. Packet
  captures and observed behaviour are fine; copying Razer's software is not.
- **Keep the "unofficial" wording.** Nothing here should suggest the project is made by or endorsed by Razer.

## Building and testing

```sh
swift build
swift test            # unit tests; no speaker needed
./scripts/install_app.sh
```

Changes to the interface can be reviewed without clicking through the app: `swift run NommoSnapshot <folder>`
renders every panel to a PNG using sample data. Please include before and after images in pull requests that change
the look.

Please add or update tests for changes to `NommoKit` (packet encoding, DSP, effects). Packets captured from real
Synapse traffic make the best test vectors.

## Other speakers

If you have a **Nommo V2**, **V2 X** or another model, the most helpful thing is a report: open an issue using the
*device report* template. Useful things to include: whether the app connects, whether brightness, colour and EQ work,
and (if you are comfortable with it) the output of `research/scan.py`, which only reads from the speaker.

A capture of what Razer's own software sends is the best evidence of all. [docs/PROTOCOL.md](docs/PROTOCOL.md#how-this-was-found)
describes how it was done here.

## Pull requests

Keep them focused, explain *why* as well as what, and make sure `swift build` and `swift test` pass. If you change
user-visible behaviour, update the README.
