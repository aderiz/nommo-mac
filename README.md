<p align="center">
  <img src="docs/images/icon.png" width="128" alt="Nommo for Mac icon">
</p>

<h1 align="center">Nommo for Mac</h1>

<p align="center">
  Lighting, EQ and spatial audio for the Razer Nommo V2 Pro, from your Mac's menu bar.
</p>

<p align="center">
  <img src="docs/images/overview.png" alt="Nommo for Mac: the Light, Sound and Space panels" width="100%">
</p>

> **This is an unofficial, independent project. It is not made, endorsed, sponsored or supported by Razer.**
> "Razer", "Nommo", "Synapse", "Chroma" and "THX" are trademarks of their respective owners and are used here only to
> say which hardware this works with.

## Why this exists

The Razer Nommo V2 Pro is a good pair of desktop speakers with a lot of nice features, and on a Mac you can't use any
of them. Razer's Synapse software does the lighting and EQ, but it is Windows-only for this product: Razer's recent Synapse for
Mac did not recognise these speakers when it was tried. On a Mac they work as plain USB speakers stuck on their default
colour cycle.

So this app was built to fix that. It talks to the speakers directly over USB, using a protocol worked out by watching
what Synapse sends them. See [docs/PROTOCOL.md](docs/PROTOCOL.md) if you are interested in how.

## What it does

- **Lighting.** Solid colours (a different one per speaker if you like), a two-colour Breathe, Spectrum, a Music
  mode that makes the lights follow whatever is playing, and a **Movie** mode that extends the picture on your screen
  into the room. Brightness control.
- **Equaliser.** The speaker's built-in presets (Game, Music, Movie) and a ten-band Custom EQ that runs on the
  speaker itself, with named profiles you can save and switch between.
- **Spatial audio.** An original stereo effect for two close speakers: crosstalk cancellation that makes the sound
  reach past the speakers, or a simple widener. This is **not THX**; see [below](#spatial-audio-and-thx).
- **Lives in the menu bar.** Optional launch at login. A `nommoctl` command-line tool is included too.

<table>
<tr>
<td><img src="docs/images/light.png" alt="Light panel" width="260"></td>
<td><img src="docs/images/sound.png" alt="Sound panel" width="260"></td>
<td><img src="docs/images/space.png" alt="Space panel" width="260"></td>
</tr>
</table>

## Install

**You need:** a Nommo V2 Pro connected by **USB**, and a Mac running macOS 14.2 or later. The app is a universal binary
(Apple silicon and Intel), but it has only been run on Apple silicon.

1. Download the latest `Nommo-<version>.dmg` from the [**Releases page**](https://github.com/aderiz/nommo-mac/releases/latest),
   open it, and drag **Nommo** into **Applications**.
2. Open Nommo. A speaker icon appears in the menu bar; click it.

### Is it safe to open?

The release is signed with a Developer ID certificate and **notarised by Apple**, so macOS checks it and opens it
without any warnings beyond the usual one for apps downloaded from the internet (*"Nommo is an app downloaded from the
Internet. Are you sure you want to open it?"*, which you confirm with **Open**).

Notarisation means Apple scanned the build for known malware; it does not mean Apple has reviewed or endorses the app.
If you would rather not run a downloaded binary at all, **build it yourself**; it takes a minute (see
[Building from source](#building-from-source)). The source is all here, and each release lists the SHA-256 checksum of
its DMG so you can check what you downloaded.

### Permissions

- **System Audio Recording**: asked for the first time you turn on **Spatial audio**, the **Music** lighting effect or
  **Movie** (which uses it for the soundtrack fallback). These work by listening to the sound your Mac is playing
  (Spatial audio also plays it back after processing). Nothing is recorded, stored or sent anywhere. Without the
  permission, lighting colours, brightness and EQ still work.
- **Screen Recording**: asked for the first time you choose **Movie** lighting. Movie mode looks at a tiny, low-rate
  copy of your screen (about 96 pixels wide, up to 20 times a second) to average its colours. The pictures are not kept,
  saved or sent anywhere, and are discarded as soon as the colours are worked out. Nothing else needs this permission.
- Nothing else. The speaker is controlled over a standard USB HID connection, which needs no special permission.

## Using it

Click the menu-bar icon.

- **Light.** Choose an effect. *Solid* takes a colour for each speaker (use the link button to set both at once).
  *Breathe* asks for two colours and fades between them. *Spectrum* cycles through the rainbow. *Music* reacts to
  what's playing, either as a pulse in your colours or as bass, mid and treble mapped to red, green and blue.
  *Movie* makes the speakers an extension of your screen: the left speaker takes the colour from the left of the
  picture and the right speaker from the right (see [Movie mode](#movie-mode)).
  *Built-in* hands the lights back to the speaker's own colour cycle. The interface itself takes its accent colour
  from the colour you pick.
- **Sound.** Pick a preset, or choose **Custom** to shape ten bands. Drag a fader, double-click to zero a band,
  and save the curve as a named profile from the bookmark menu. The built-in presets are tuned inside the speaker, which
  does not tell the app what their curves are, so they are shown as presets only.
- **Space.** Turn spatial audio on and choose **Immersive** (crosstalk cancellation) or **Widen**. Sit centred in front
  of the speakers for Immersive.

Because colours and animations are streamed to the speaker from your Mac (that is how Synapse does it too), **the app
needs to stay running** for custom lighting. Choose *Built-in* or quit the app and the speakers go back to their own
colour cycle.

### Movie mode

Choose **Movie** in the Light tab and play something. The lights follow the scene, each speaker from its own side of the
screen, so a fire on the left of the picture glows more on the left speaker than the right. **Intensity** sets
how bright and colourful the light is (dim, muted scenes are lifted so they still show as colour, and dark scenes stay
dark), and **Smoothness** sets how slowly the colour settles. Letterbox and pillarbox bars are ignored, a hard cut snaps
to the new scene, and a limiter keeps flashing in the picture from turning into strobing on the speakers.

Whether the picture can be read depends on the player, because streaming services protect their video:

| Playing in | What Movie mode does |
|---|---|
| **Chrome with hardware acceleration off** | Follows the picture. Tested with Netflix. |
| Chrome with hardware acceleration on | The protected video reads as black, so the lights follow the sound instead. |
| Safari, the Apple TV app, the Netflix app | Not tested. Protected video there is expected to read as black, so the lights follow the sound. |
| Local video files, YouTube, games, anything not protected | Not tested yet, but expected to follow the picture. |

**Following the sound** is the fallback when the screen reads as black for about a second and a half: the lights then
follow the soundtrack instead, left and right separately, going from a cool blue at quiet moments through amber to
white on loud impacts. The picture takes over again the moment it can be read.

To use Netflix in Chrome, turn off hardware acceleration in Chrome's System settings and restart Chrome. Chrome then
decodes the video in software, which macOS allows Nommo to see, and the service may stream it at a lower quality.
Nommo does not get around any copy protection: it only sees what macOS shows it, so protected video reads as black. Movie mode watches your main display only.

### Command line

```sh
nommoctl info                      # serial, brightness, EQ bands
nommoctl color 255 0 128 10        # hold a colour for 10 seconds
nommoctl effect spectrum 15
nommoctl brightness 128
nommoctl movie 60                  # follow the screen for a minute (needs Screen Recording)
```

Build it with `swift build --product nommoctl`. It's a development tool; the app is the main way to use this.

## If something doesn't work

Run this in Terminal. It checks that the speaker can be opened and that system audio capture and screen recording are
allowed, and it prints nothing that identifies you or your speaker:

```sh
/Applications/Nommo.app/Contents/MacOS/Nommo --diagnose
```

- **"speaker: not found"**: it isn't plugged in over USB, or it is on another input.
- **"found but could not be opened"**: Razer Synapse, or a virtual machine with the speaker attached, has it.
- **"system audio tap: failed"**: allow Nommo under System Settings → Privacy & Security → System Audio Recording
  (only Spatial audio and the Music and Movie lighting effects need it).
- **"screen recording: not allowed"**: allow Nommo under System Settings → Privacy & Security → Screen & System Audio
  Recording (only Movie lighting needs it).
- **Movie mode says "Can't read this video"**: the player is showing protected video, so the lights are following the
  sound. See the table under [Movie mode](#movie-mode).

## Compatibility

| Speaker | Status |
|---|---|
| Razer Nommo V2 Pro (`1532:055A`) | Developed and tested on this one |
| Razer Nommo V2 (`1532:055C`) | Untested. Probably the same chipset and protocol. |
| Razer Nommo V2 X (`1532:055E`) | Untested. It has no lighting. |
| Older Nommo, Nommo Pro, Nommo Chroma | Different hardware; not supported |

Tested on Apple silicon with macOS 27. If you have one of the untested models and try this, please open an issue
using the *device report* template and say what worked. Even "nothing happened" is useful.

## Notes and limits

- **Spatial audio and THX.** The THX Spatial Audio option in Synapse is a Windows audio effect that runs on the PC;
  it isn't something the speaker does, so it can't be switched on from a Mac. The Space tab is an independent effect
  written for this project and makes no attempt to copy THX.
- **Only one app can control the speaker at a time.** Quit Synapse, and any virtual machine that has the speaker
  attached, before opening Nommo. If it can't connect, the app says so.
- **Audio source.** There is deliberately no control for switching the speaker's input (USB, Bluetooth and so on):
  getting it wrong can drop the USB connection until you press the speaker's own button.
- **Presets' curves.** Game, Music and Movie can be selected but their curves can't be read back from the speaker.
  (This is the speaker's EQ preset called Movie, not the Movie lighting mode.)
- **Not tested over a power cycle:** whether the speaker remembers a custom EQ curve after it is switched off.

### Movie mode: what to expect

Movie mode is new and has had far less testing than the rest of the app. It was tuned by eye on one Mac (Apple silicon,
macOS 27), watching Netflix in Chrome with hardware acceleration off. Please read this before relying on it.

- **Protected video can't be read.** Streaming services protect their video, and macOS hides it from screen capture
  when it is played through the hardware path: Safari, the Apple TV app, the Netflix app and Chrome with hardware
  acceleration on all show up as black. Nommo then follows the soundtrack instead, which is a much looser match to the
  film. Nommo does not try to get round this.
- **Only Chrome with hardware acceleration off was tested.** That makes Chrome decode in software, which macOS lets Nommo
  see, but it uses more of your CPU, can lower the quality a service will stream at, and applies to every site in Chrome
  until you turn it back on. Safari, the Apple TV and Netflix apps, local files, YouTube, games, HDR video, and screen
  sleep or wake have not been tested.
- **Your main display only.** If the film is on another monitor, Movie mode cannot see it, and there is no way to pick
  a display yet.
- **It reads the whole screen, not just the video.** Anything at the edges of the display counts: a notification banner,
  the Dock or a menu bar can tint the light. It works best with the video full-screen. Black bars above and below a
  film, and beside a 4:3 picture, are ignored.
- **A long black screen looks like protected video.** If the whole screen is black for about a second and a half (a
  long fade to black, say), the lights switch to the soundtrack until the picture returns.
- **The colours are an approximation.** Each speaker has six LEDs shown as one diffused colour, so you get the mood of
  that side of the screen, not an image. The brightness lift, colour boost and LED response were set by eye on a few
  dim, muted film scenes, so very dark films will still look subdued, and bright, colourful scenes were not tuned
  with the same care. Intensity and Smoothness are there to adjust this to taste.
- **Flashing is softened, not removed.** Movie mode limits how fast the lights can change brightness, but it follows
  what's on screen. If you are sensitive to flashing lights, be careful with scenes that flash.
- **Cost.** On the test Mac, Movie mode used about 1 to 2% of one CPU core with the Nommo window closed, and about 10%
  while the window is open, because the window's animated glow follows the lights. It reads the screen at 96 pixels
  wide, up to 20 times a second.
- **Screen Recording is a broad permission.** It is what macOS requires to read the screen, and Nommo uses it only for
  Movie mode, but macOS may ask you to confirm it again from time to time. If you would rather not allow it, don't
  choose Movie; the other lighting modes do not need it.

## Building from source

You need Xcode 16 or later (the Swift 6 toolchain) on macOS 14.2 or later.

```sh
git clone https://github.com/aderiz/nommo-mac.git
cd nommo-mac

swift build                    # the library, the menu-bar app and the CLI
swift test                     # unit tests (no speaker needed)

./scripts/build_app.sh         # builds dist/Nommo.app
./scripts/install_app.sh       # builds, installs into /Applications and launches it
./scripts/make_dmg.sh          # builds Releases/Nommo-<version>.dmg
```

**Signing.** `build_app.sh` signs with an *Apple Development* or *Developer ID* certificate if it finds one in
your keychain, and otherwise falls back to an ad-hoc signature (or set `NOMMO_SIGN_IDENTITY`). Use a real certificate if
you can: macOS ties the System Audio Recording and Screen Recording permissions to the app's signing identity, and an
ad-hoc signature changes with every build, so you would be asked for them again after each rebuild.

### Layout

| Path | What's in it |
|---|---|
| `Sources/NommoKit` | The core library: packets, HID transport, device commands, lighting engine, effects, audio taps and DSP, and the screen reader behind Movie mode. No UI. |
| `Sources/NommoUI` | The SwiftUI interface and app state. |
| `Sources/NommoApp` | The menu-bar app entry point. |
| `Sources/nommoctl` | The command-line tool. |
| `Sources/screenprobe` | A read-only tool that reports whether a player's video can be read, to check Movie mode compatibility. |
| `Sources/NommoSnapshot` | Renders the interface to PNGs (used for the screenshots above and to review design changes without clicking through it). |
| `Tests/NommoKitTests` | Unit tests, including packets captured from Synapse. |
| `docs/PROTOCOL.md` | What is known about the speaker's USB protocol. |
| `research/` | Python scripts used while working the protocol out. |
| `scripts/` | Build, install, icon and DMG scripts. |

## Contributing

Issues and pull requests are welcome; see [CONTRIBUTING.md](CONTRIBUTING.md). The most useful contributions right now:

- Trying it on a **Nommo V2** or other model and reporting what happens.
- The real curves behind the **Game, Music and Movie** presets.
- Checking it on an **Intel Mac**: the build is universal, but only Apple silicon has been tested.

## Licence

[Apache License 2.0](LICENSE). See [NOTICE](NOTICE) for the copyright and trademark notice. This project contains no
Razer software, drivers, firmware or artwork. The speaker drawings in the interface are original illustrations.
