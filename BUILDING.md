# Building VoiceWink

This guide provides detailed instructions for building VoiceWink from source.

## Prerequisites

Before you begin, ensure you have:
- macOS 14.4 or later
- Xcode (latest version recommended)
- Swift (latest version recommended)
- Git (for cloning repositories)

## Quick Start with Makefile (Recommended)

The easiest way to build VoiceWink is using the included Makefile, which automates the entire build process including building and linking the whisper framework.

### Simple Build Commands

```bash
# Clone your VoiceWink fork
git clone <your-voicewink-repo-url> VoiceWink
cd VoiceWink

# Build everything (recommended for first-time setup)
make all

# Or for development (build and run)
make dev
```

### Available Makefile Commands

- `make check` or `make healthcheck` - Verify all required tools are installed
- `make whisper` - Clone and build whisper.cpp XCFramework automatically
- `make setup` - Prepare the whisper framework for linking
- `make build` - Build the VoiceWink Xcode project
- `make local` - Build for local use with a stable self-signed local identity
- `make package-public` - Build an ad hoc signed public release zip without notarization
- `make release-archive` - Build a Developer ID signed release archive and zip
- `make run` - Launch the built VoiceWink app
- `make dev` - Build and run (ideal for development workflow)
- `make all` - Complete build process (default)
- `make clean` - Remove build artifacts and dependencies
- `make help` - Show all available commands

### How the Makefile Helps

The Makefile automatically:
1. **Manages Dependencies**: Creates a dedicated `~/VoiceWink-Dependencies` directory for all external frameworks
2. **Builds Whisper Framework**: Clones whisper.cpp and builds the XCFramework with the correct configuration
3. **Handles Framework Linking**: Sets up the whisper.xcframework in the proper location for Xcode to find
4. **Verifies Prerequisites**: Checks that git, xcodebuild, and swift are installed before building
5. **Streamlines Development**: Provides convenient shortcuts for common development tasks

This approach ensures consistent builds across different machines and eliminates manual framework setup errors.

---

## Building for Local Use (No Apple Developer Certificate)

If you don't have an Apple Developer certificate, use `make local`:

```bash
git clone <your-voicewink-repo-url> VoiceWink
cd VoiceWink
export P12_PASSWORD='<local-password>'
make local
open ./VoiceWink.app
```

This builds VoiceWink with the shared local-mode runtime and then applies a project-owned local signing identity. It uses a separate build configuration (`LocalBuild.xcconfig`) and requires no Apple Developer account.

`P12_PASSWORD` is only used locally when the self-signed codesign identity is exported and imported into the local keychain. Set it in your shell or CI secrets, never in source control.

### One Runtime Mode, Two Signing Modes

`make local` and `make package-public` are not two different app variants. They both build the same local-mode VoiceWink runtime:
- `VoiceWink.local.entitlements`
- `LOCAL_BUILD` conditional code path
- no CloudKit dictionary sync
- no automatic Sparkle updater unless a release source is configured

The actual split is in the final signing and output shape:
- `make local` signs the app with a stable self-signed `VoiceWink Local Codesign` certificate and keeps it at `./VoiceWink.app`
- `make package-public` archives the same local-mode app in Release configuration, then ad hoc signs and zips it for GitHub/Homebrew distribution

`make release-public` remains available as a backwards-compatible alias.

That split exists because macOS treats the resulting identities differently. The local self-signed app gets a stable certificate-based designated requirement, which helps Accessibility trust survive rebuilds. The ad hoc public build falls back to a cdhash-based designated requirement, which is fine for shipping a one-off archive but is not stable enough to replace the local trust-preserving path.

### How It Works

The `make local` command uses:
- `LocalBuild.xcconfig` to override signing and entitlements settings
- `scripts/ensure_local_codesign_identity.sh` to create or reuse a stable local codesigning certificate in `~/VoiceWink-Dependencies/codesign`
- `VoiceWink.local.entitlements` (stripped-down, no CloudKit/keychain groups)
- `LOCAL_BUILD` Swift compilation flag for conditional code paths

Your normal `make all` / `make build` commands are completely unaffected.

### Accessibility note for local builds

VoiceWink pastes into other apps through macOS Accessibility access. Earlier ad hoc local builds could lose that trust every time the bundle was rebuilt, because the code identity changed. The stable local signing identity created by `make local` is meant to keep the permission attached across rebuilds as long as you keep launching the same bundle path:

```bash
open ./VoiceWink.app
```

If you ever see Accessibility still appear enabled while paste warnings continue:

1. Quit VoiceWink.
2. Remove every existing VoiceWink entry from `System Settings > Privacy & Security > Accessibility`.
3. Add the current `~/Projects/VoiceWink/VoiceWink.app`.
4. Relaunch that exact bundle path.

### What `make local` guarantees

`make local` is now the reproducible path for local development and security-sensitive testing:
- It creates or reuses the same self-signed `VoiceWink Local Codesign` identity.
- It keeps the finished app at the same path: `./VoiceWink.app`.
- It produces a stable designated requirement based on the VoiceWink bundle identifier and that local certificate.

That combination is what keeps macOS Accessibility trust attached across rebuilds for the local bundle path.

### Important limit: local signing is not for public distribution

The local certificate is intentionally self-signed. It is valid for stable local identity and permission testing, but Gatekeeper will reject it for public distribution. Do not publish `make local` output.

If you want to ship an unnotarized public build, use `make package-public`. That target packages the same local-mode runtime in Release configuration and re-signs the final bundle ad hoc, which is a better fit for public unnotarized distribution than a machine-local self-signed identity.

---

## Building for Distribution

### Public unnotarized release

For an unnotarized public release that does not require an Apple Developer account:

```bash
make package-public
```

This target:
- archives the same local-mode app with Release configuration
- preserves the local-only entitlements and `LOCAL_BUILD` code path
- re-signs the finished bundle ad hoc
- packages the finished app as `build/release/VoiceWink.zip`

Legacy alias:

```bash
make release-public
```

Outputs:
- archive: `build/release/VoiceWink.xcarchive`
- app bundle: `build/release/VoiceWink.app`
- distributable zip: `build/release/VoiceWink.zip`

This is the correct path for public Homebrew and GitHub release distribution when you are intentionally not notarizing.

### Developer ID signed release

For a distributable build signed with a real Apple Developer identity, use `make release-archive`:

```bash
export VOICEWINK_RELEASE_TEAM=YOURTEAMID
export VOICEWINK_RELEASE_IDENTITY="Developer ID Application: Your Name (YOURTEAMID)"
make release-archive
```

This target:
- archives the app with Release configuration
- signs it with the Developer ID identity you provide
- verifies the resulting app with `codesign`
- checks Gatekeeper acceptance with `spctl`
- packages the finished app as `build/release/VoiceWink.zip`

Outputs:
- archive: `build/release/VoiceWink.xcarchive`
- app bundle: `build/release/VoiceWink.app`
- distributable zip: `build/release/VoiceWink.zip`

### Optional notarization

If you already created a notarytool keychain profile, you can notarize in the same command:

```bash
export VOICEWINK_NOTARY_PROFILE=voicewink-notary
make release-archive
```

When `VOICEWINK_NOTARY_PROFILE` is set, the target submits the zip with `xcrun notarytool`, waits for completion, and staples the resulting ticket onto the app bundle.

---

## Manual Build Process (Alternative)

If you prefer to build manually or need more control over the build process, follow these steps:

### Building whisper.cpp Framework

1. Clone and build whisper.cpp:
```bash
git clone https://github.com/ggerganov/whisper.cpp.git
cd whisper.cpp
./build-xcframework.sh
```
This will create the XCFramework at `build-apple/whisper.xcframework`.

### Building VoiceWink

1. Clone the VoiceWink repository:
```bash
git clone <your-voicewink-repo-url> VoiceWink
cd VoiceWink
```

2. Add the whisper.xcframework to your project:
   - Drag and drop `../whisper.cpp/build-apple/whisper.xcframework` into the project navigator, or
   - Add it manually in the "Frameworks, Libraries, and Embedded Content" section of project settings

3. Build and Run
   - Build the project using Cmd+B or Product > Build
   - Run the project using Cmd+R or Product > Run

## Development Setup

1. **Xcode Configuration**
   - Ensure you have the latest Xcode version
   - Install any required Xcode Command Line Tools

2. **Dependencies**
   - The project uses [whisper.cpp](https://github.com/ggerganov/whisper.cpp) for transcription
   - Ensure the whisper.xcframework is properly linked in your Xcode project
   - Test the whisper.cpp installation independently before proceeding

3. **Building for Development**
   - Use the Debug configuration for development
   - Enable relevant debugging options in Xcode

4. **Testing**
   - Run the test suite before making changes
   - Ensure all tests pass after your modifications

## Troubleshooting

If you encounter any build issues:
1. Clean the build folder (Cmd+Shift+K)
2. Clean the build cache (Cmd+Shift+K twice)
3. Check Xcode and macOS versions
4. Verify all dependencies are properly installed
5. Make sure whisper.xcframework is properly built and linked

For more help, check the issue tracker for your active VoiceWink fork. 
