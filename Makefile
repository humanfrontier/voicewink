# Define a directory for dependencies in the user's home folder
DEPS_DIR := $(HOME)/VoiceWink-Dependencies
WHISPER_CPP_DIR := $(DEPS_DIR)/whisper.cpp
FRAMEWORK_PATH := $(WHISPER_CPP_DIR)/build-apple/whisper.xcframework
LOCAL_DERIVED_DATA := $(CURDIR)/.local-build
LOCAL_APP_PATH := $(CURDIR)/VoiceWink.app
LOCAL_CODESIGN_DIR := $(DEPS_DIR)/codesign
LOCAL_CODESIGN_KEYCHAIN := $(LOCAL_CODESIGN_DIR)/VoiceWinkLocal.keychain-db
LOCAL_CODESIGN_CERT_NAME := VoiceWink Local Codesign
LOCAL_CODESIGN_SCRIPT := $(CURDIR)/scripts/ensure_local_codesign_identity.sh
RELEASE_DIR := $(CURDIR)/build/release
RELEASE_DERIVED_DATA := $(CURDIR)/.release-build
RELEASE_ARCHIVE_PATH := $(RELEASE_DIR)/VoiceWink.xcarchive
RELEASE_APP_PATH := $(RELEASE_DIR)/VoiceWink.app
RELEASE_ZIP_PATH := $(RELEASE_DIR)/VoiceWink.zip

.PHONY: all clean whisper setup build local check healthcheck help dev run release-check release-public release-archive

# Default target
all: check build

# Development workflow
dev: build run

# Prerequisites
check:
	@echo "Checking prerequisites..."
	@command -v git >/dev/null 2>&1 || { echo "git is not installed"; exit 1; }
	@command -v xcodebuild >/dev/null 2>&1 || { echo "xcodebuild is not installed (need Xcode)"; exit 1; }
	@command -v swift >/dev/null 2>&1 || { echo "swift is not installed"; exit 1; }
	@echo "Prerequisites OK"

healthcheck: check

# Build process
whisper:
	@mkdir -p $(DEPS_DIR)
	@if [ ! -d "$(FRAMEWORK_PATH)" ]; then \
		echo "Building whisper.xcframework in $(DEPS_DIR)..."; \
		if [ ! -d "$(WHISPER_CPP_DIR)" ]; then \
			git clone https://github.com/ggerganov/whisper.cpp.git $(WHISPER_CPP_DIR); \
		else \
			(cd $(WHISPER_CPP_DIR) && git pull); \
		fi; \
		cd $(WHISPER_CPP_DIR) && ./build-xcframework.sh; \
	else \
		echo "whisper.xcframework already built in $(DEPS_DIR), skipping build"; \
	fi

setup: whisper
	@echo "Whisper framework is ready at $(FRAMEWORK_PATH)"
	@echo "Please ensure your Xcode project references the framework from this new location."

build: setup
	xcodebuild -project VoiceWink.xcodeproj -scheme VoiceWink -configuration Debug CODE_SIGN_IDENTITY="" build

# Build for local use without Apple Developer certificate
local: check setup
	@echo "Building VoiceWink for local use (no Apple Developer certificate required)..."
	@test -n "$$P12_PASSWORD" || { echo "P12_PASSWORD is required for make local. Export a local-only value before running make local."; exit 1; }
	@"$(LOCAL_CODESIGN_SCRIPT)" "$(LOCAL_CODESIGN_KEYCHAIN)" "$(LOCAL_CODESIGN_CERT_NAME)" "$(LOCAL_CODESIGN_DIR)"
	@rm -rf "$(LOCAL_DERIVED_DATA)"
	xcodebuild -project VoiceWink.xcodeproj -scheme VoiceWink -configuration Debug \
		-derivedDataPath "$(LOCAL_DERIVED_DATA)" \
		-xcconfig LocalBuild.xcconfig \
		CODE_SIGN_IDENTITY="-" \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGNING_ALLOWED=YES \
		DEVELOPMENT_TEAM="" \
		CODE_SIGN_ENTITLEMENTS=$(CURDIR)/VoiceInk/VoiceWink.local.entitlements \
		SWIFT_ACTIVE_COMPILATION_CONDITIONS='$$(inherited) LOCAL_BUILD' \
		build
	@set -e; \
	APP_PATH="$(LOCAL_DERIVED_DATA)/Build/Products/Debug/VoiceWink.app"; \
	LOCAL_APP_PATH="$(LOCAL_APP_PATH)"; \
	if [ -d "$$APP_PATH" ]; then \
		if pgrep -f "$$LOCAL_APP_PATH/Contents/MacOS/VoiceWink" >/dev/null 2>&1; then \
			echo "Error: $$LOCAL_APP_PATH is currently running. Quit it and rerun 'make local'."; \
			exit 1; \
		fi; \
		echo "Copying VoiceWink.app to $(CURDIR)..."; \
		rm -rf "$$LOCAL_APP_PATH"; \
		ditto "$$APP_PATH" "$$LOCAL_APP_PATH"; \
		xattr -cr "$$LOCAL_APP_PATH"; \
		codesign --force --deep --sign "$(LOCAL_CODESIGN_CERT_NAME)" --keychain "$(LOCAL_CODESIGN_KEYCHAIN)" --entitlements $(CURDIR)/VoiceInk/VoiceWink.local.entitlements "$$LOCAL_APP_PATH"; \
		codesign --verify --deep --strict "$$LOCAL_APP_PATH"; \
		echo ""; \
		echo "Build complete! App saved to: $(LOCAL_APP_PATH)"; \
		echo "Run with: open $(LOCAL_APP_PATH)"; \
		echo ""; \
		echo "Limitations of local builds:"; \
		echo "  - No iCloud dictionary sync"; \
		echo "  - No automatic Sparkle updates without a configured VoiceWink feed"; \
		echo "  - Accessibility trust is stable only for this signed local bundle path: $(LOCAL_APP_PATH)"; \
		echo "  - If no release page is configured, use 'git pull' and 'make local' to update"; \
	else \
		echo "Error: Could not find built VoiceWink.app at $$APP_PATH"; \
		exit 1; \
	fi

# Run application
run:
	@if [ -d "$(LOCAL_APP_PATH)" ]; then \
		echo "Opening $(LOCAL_APP_PATH)..."; \
		open "$(LOCAL_APP_PATH)"; \
	else \
		echo "Looking for VoiceWink.app in DerivedData..."; \
		APP_PATH=$$(find "$(LOCAL_DERIVED_DATA)" "$$HOME/Library/Developer/Xcode/DerivedData" -name "VoiceWink.app" -type d 2>/dev/null | head -1) && \
		if [ -n "$$APP_PATH" ]; then \
			echo "Found app at: $$APP_PATH"; \
			open "$$APP_PATH"; \
		else \
			echo "VoiceWink.app not found. Please run 'make build' or 'make local' first."; \
			exit 1; \
		fi; \
	fi

release-check:
	@test -n "$(VOICEWINK_RELEASE_TEAM)" || { echo "VOICEWINK_RELEASE_TEAM is required, for example: export VOICEWINK_RELEASE_TEAM=YOURTEAMID"; exit 1; }
	@test -n "$(VOICEWINK_RELEASE_IDENTITY)" || { echo "VOICEWINK_RELEASE_IDENTITY is required, for example: export VOICEWINK_RELEASE_IDENTITY='Developer ID Application: Your Name (TEAMID)'"; exit 1; }

release-public: check setup
	@echo "Building VoiceWink public release archive (ad hoc signed, not notarized)..."
	@mkdir -p "$(RELEASE_DIR)"
	@rm -rf "$(RELEASE_DERIVED_DATA)" "$(RELEASE_ARCHIVE_PATH)" "$(RELEASE_APP_PATH)" "$(RELEASE_ZIP_PATH)"
	xcodebuild -project VoiceWink.xcodeproj -scheme VoiceWink -configuration Release \
		-derivedDataPath "$(RELEASE_DERIVED_DATA)" \
		-archivePath "$(RELEASE_ARCHIVE_PATH)" \
		CODE_SIGN_IDENTITY="-" \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGNING_ALLOWED=YES \
		DEVELOPMENT_TEAM="" \
		CODE_SIGN_ENTITLEMENTS=$(CURDIR)/VoiceInk/VoiceWink.local.entitlements \
		SWIFT_ACTIVE_COMPILATION_CONDITIONS='$$(inherited) LOCAL_BUILD' \
		archive
	@ditto "$(RELEASE_ARCHIVE_PATH)/Products/Applications/VoiceWink.app" "$(RELEASE_APP_PATH)"
	@xattr -cr "$(RELEASE_APP_PATH)"
	@codesign --force --deep --sign - "$(RELEASE_APP_PATH)"
	@codesign --verify --deep --strict --verbose=2 "$(RELEASE_APP_PATH)"
	@ditto -c -k --sequesterRsrc --keepParent "$(RELEASE_APP_PATH)" "$(RELEASE_ZIP_PATH)"
	@echo ""
	@echo "Public release archive ready at: $(RELEASE_ARCHIVE_PATH)"
	@echo "Public release app ready at: $(RELEASE_APP_PATH)"
	@echo "Public release zip ready at: $(RELEASE_ZIP_PATH)"
	@echo "Note: this build is ad hoc signed and not notarized."

release-archive: check setup release-check
	@echo "Building VoiceWink release archive..."
	@mkdir -p "$(RELEASE_DIR)"
	@rm -rf "$(RELEASE_DERIVED_DATA)" "$(RELEASE_ARCHIVE_PATH)" "$(RELEASE_APP_PATH)" "$(RELEASE_ZIP_PATH)"
	xcodebuild -project VoiceWink.xcodeproj -scheme VoiceWink -configuration Release \
		-derivedDataPath "$(RELEASE_DERIVED_DATA)" \
		-archivePath "$(RELEASE_ARCHIVE_PATH)" \
		CODE_SIGN_STYLE=Manual \
		DEVELOPMENT_TEAM="$(VOICEWINK_RELEASE_TEAM)" \
		CODE_SIGN_IDENTITY="$(VOICEWINK_RELEASE_IDENTITY)" \
		archive
	@ditto "$(RELEASE_ARCHIVE_PATH)/Products/Applications/VoiceWink.app" "$(RELEASE_APP_PATH)"
	@codesign --verify --deep --strict --verbose=2 "$(RELEASE_APP_PATH)"
	@spctl --assess --type execute --verbose "$(RELEASE_APP_PATH)"
	@ditto -c -k --sequesterRsrc --keepParent "$(RELEASE_APP_PATH)" "$(RELEASE_ZIP_PATH)"
	@if [ -n "$(VOICEWINK_NOTARY_PROFILE)" ]; then \
		echo "Submitting release zip for notarization with profile $(VOICEWINK_NOTARY_PROFILE)..."; \
		xcrun notarytool submit "$(RELEASE_ZIP_PATH)" --keychain-profile "$(VOICEWINK_NOTARY_PROFILE)" --wait; \
		xcrun stapler staple "$(RELEASE_APP_PATH)"; \
		spctl --assess --type execute --verbose "$(RELEASE_APP_PATH)"; \
	else \
		echo "Skipping notarization because VOICEWINK_NOTARY_PROFILE is not set."; \
	fi
	@echo ""
	@echo "Release archive ready at: $(RELEASE_ARCHIVE_PATH)"
	@echo "Release app ready at: $(RELEASE_APP_PATH)"
	@echo "Release zip ready at: $(RELEASE_ZIP_PATH)"

# Cleanup
clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(DEPS_DIR) "$(LOCAL_DERIVED_DATA)" "$(RELEASE_DERIVED_DATA)" "$(RELEASE_DIR)"
	@echo "Clean complete"

# Help
help:
	@echo "Available targets:"
	@echo "  check/healthcheck  Check if required CLI tools are installed"
	@echo "  whisper            Clone and build whisper.cpp XCFramework"
	@echo "  setup              Copy whisper XCFramework to the VoiceWink project"
	@echo "  build              Build the VoiceWink Xcode project"
	@echo "  local              Build for local use (no Apple Developer certificate needed)"
	@echo "  release-public     Build an ad hoc signed public release zip (not notarized)"
	@echo "  release-archive    Build a Developer ID signed release archive and zip"
	@echo "  run                Launch the built VoiceWink app"
	@echo "  dev                Build and run the app (for development)"
	@echo "  all                Run full build process (default)"
	@echo "  clean              Remove build artifacts"
	@echo "  help               Show this help message"
