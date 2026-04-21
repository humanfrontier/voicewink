<div align="center">
  <img src="VoiceInk/Assets.xcassets/AppIcon.appiconset/256-mac.png" width="180" height="180" />
  <h1>VoiceWink</h1>
  <p>Security-conscious, local-first voice dictation for macOS</p>

  [![License](https://img.shields.io/badge/License-GPL%20v3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
  ![Platform](https://img.shields.io/badge/platform-macOS%2014.4%2B-brightgreen)
</div>

---

VoiceWink is a fork of [Beingpax/VoiceInk](https://github.com/Beingpax/VoiceInk) for environments that need a narrower, more security-conscious baseline.

## Install

### Homebrew

Published builds are available through the `humanfrontier/tap` Homebrew tap:

```bash
brew tap humanfrontier/tap
brew install --cask --no-quarantine humanfrontier/tap/voicewink
```

Current public releases are signed with a local self-signed certificate and are not notarized.

If you install the app with quarantine still attached, remove it manually:

```bash
xattr -dr com.apple.quarantine "/Applications/VoiceWink.app"
```

Releases are published on GitHub here: [humanfrontier/voicewink/releases](https://github.com/humanfrontier/voicewink/releases)

This fork keeps the core dictation workflow intact:
- local transcription with a bundled starter model
- explicit microphone selection
- configurable recording shortcuts
- history and last-transcription access
- top-level discoverability of retained controls

At the same time, it removes product areas that do not fit the local-only fork direction:
- cloud transcription providers
- AI enhancement providers and prompt flows
- licensing and pro-upgrade paths
- announcements, promotions, and marketing surfaces

## Why This Fork Exists

VoiceInk is the original project and the work this fork builds on. VoiceWink exists for teams and users who need a tighter deployment posture, fewer moving parts, and a local-only default.

If VoiceInk works for your setup, support the original app at [tryvoiceink.com](https://tryvoiceink.com). Even if you use VoiceWink, supporting VoiceInk helps fund the upstream work that made this fork possible.

## Getting Started

### Build from Source

VoiceWink can also be built locally from source:

```bash
git clone <your-voicewink-repo-url> VoiceWink
cd VoiceWink
make local
open ./VoiceWink.app
```

For full build details, see [BUILDING.md](BUILDING.md).

### Releases

- Local testing builds use `make local`.
- Public releases are published on GitHub Releases in this repository.
- Homebrew installation is published as `humanfrontier/tap/voicewink`.
- Current public releases are intentionally unnotarized and may require `--no-quarantine` or manual quarantine removal.
- Developer ID signing and notarization remain optional release paths if you decide to enable them later.

## Documentation

- [Building from Source](BUILDING.md)
- [Contributing Guidelines](CONTRIBUTING.md)
- [Code of Conduct](CODE_OF_CONDUCT.md)

## Contributing

Treat this repository as a maintained fork, not as the upstream VoiceInk project.

If you are maintaining this fork:
- keep release-facing identity as VoiceWink
- keep the local-only security posture intact
- avoid reintroducing removed cloud, enhancement, or commercial surfaces without an explicit product decision

## License

This project remains licensed under the GNU General Public License v3.0. See [LICENSE](LICENSE).

## Acknowledgments

### Upstream

- [Beingpax/VoiceInk](https://github.com/Beingpax/VoiceInk)

### Core Technology

- [whisper.cpp](https://github.com/ggerganov/whisper.cpp)
- [FluidAudio](https://github.com/FluidInference/FluidAudio)

### Essential Dependencies

- [Sparkle](https://github.com/sparkle-project/Sparkle), still vendored from upstream and pending removal from the local-only fork
- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts)
- [LaunchAtLogin](https://github.com/sindresorhus/LaunchAtLogin)
- [MediaRemoteAdapter](https://github.com/ejbills/mediaremote-adapter)
- [Zip](https://github.com/marmelroy/Zip)
- [SelectedTextKit](https://github.com/tisfeng/SelectedTextKit)
- [Swift Atomics](https://github.com/apple/swift-atomics)
