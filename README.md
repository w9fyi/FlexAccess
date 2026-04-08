# FlexAccess

**VoiceOver-first control for FlexRadio 6000- and 8000-series SDRs.**

FlexAccess is a native macOS and iOS app for the FlexRadio 6000 and 8000 families, written from the ground up to be fully usable with VoiceOver and other assistive technology. It is built by a blind operator who uses a FLEX-8400 in his own shack every day, and the accessibility commitments are not bolted on at the end — they are the reason the app exists.

If you are sighted: it is a clean, fast, native Swift client that talks directly to your radio over the LAN. If you are blind: it is the FlexRadio client you have probably been waiting for.

## What it does

- **Slice control** — RIT, XIT, squelch, APF, tuning step, RF gain, audio level, mode, filter
- **Meters** — full S-meter, power, SWR, ALC, compression, and panadapter readouts wired through a real `RadioMeter` model with VITA-49 stream routing
- **Equalizer** — RX and TX EQ with screen-reader-friendly band controls
- **CW** — built-in keyer plus a Goertzel-based decoder for hands-off receive
- **MIDI** — full MIDI engine with mappable controls, so you can drive the radio from any MIDI surface
- **Frequency memories** — store, recall, organize
- **QSO log** — capture contacts as you work them
- **Panadapter / bandscope** — visual for sighted operators, with accessible numeric and structural readouts for screen readers
- **Connection profiles** — multiple radios, multiple operators, fast switching

## Platforms

- **macOS** (primary, daily-driven on the developer's own FLEX-8400)
- **iOS** target also builds — the same Swift codebase

## Status

- 372 unit tests passing
- Phases 1, 2, and 3 of the roadmap complete (slice control, meters/EQ, CW + MIDI + memories + log + panadapter + profiles)
- Used in production in the developer's own shack
- Active development — see the issues tab for what is in flight and what is planned next

## Building

This is a Swift Package / Xcode project. WDSP is built from source (six C files compiled directly), and the build links `libfftw3` from Homebrew. See the project file for the exact target setup.

```sh
brew install fftw
xcodebuild -project FlexAccess.xcodeproj \
  -scheme FlexAccess_macOS -configuration Release build
```

## Why it exists

Mainstream SDR consoles are built around dense, custom-drawn visual panels that screen readers cannot see at all. A blind ham can buy a multi-thousand-dollar radio and then discover that the software needed to use most of its features is unreachable. FlexAccess is one answer to that problem for the Flex line, written by someone who needs it to work.

If you are a Flex owner who cannot use the stock software because of a disability, please open an issue — bug reports from real assistive-technology users are the most valuable thing this project can receive.

## License

GPL-3.0. The build links `libfftw3`, which is GPL, so the binary is GPL by inheritance and the source matches.

## Author

Justin Mann — **AI5OS**, Austin, Texas. Blind macOS developer building accessible amateur radio software.
Profile: [github.com/w9fyi](https://github.com/w9fyi) · Email: w9fyi@me.com
