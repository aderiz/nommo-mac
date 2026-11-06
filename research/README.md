# Research scripts

Small Python scripts used while working out the Nommo V2 Pro's HID protocol. The macOS app does not use them;
they are here for anyone who wants to explore the protocol or port it somewhere else. The protocol itself is
written up in [`../docs/PROTOCOL.md`](../docs/PROTOCOL.md).

Run them with [uv](https://docs.astral.sh/uv/):

```sh
cd research
uv run python scan.py      # read-only: sends getter commands and prints the replies
uv run python nommo.py     # (library) a small client with the same sequences the app uses
```

- **`nommo.py`** is a compact reference client: lighting frames, brightness, EQ, and the transaction counter and
  status polling the speaker expects.
- **`scan.py`** sends only *getter* commands (command byte `0x80` and up). It is safe to run, but remember the
  speaker answers "OK" to everything, so you have to compare each reply with the request to see which commands
  are really implemented.

> **Be careful with setters.** The speaker accepts writes to commands it does not document, and one of them
> (class `0x08`, command `0x0A`) switches its audio source to Bluetooth, which drops the USB connection until
> someone presses a button on the speaker. Prefer commands that have a getter you can read back.
