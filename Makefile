APP_NAME = Hlopya
BUILD_DIR = .build/xcode
INSTALL_DIR = /Applications
ENTITLEMENTS = Hlopya/Hlopya.entitlements

.PHONY: build install clean run debug fix-entitlements release sign-notarize

fix-entitlements:
	@printf '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0">\n<dict>\n\t<key>com.apple.security.device.audio-input</key>\n\t<true/>\n\t<key>com.apple.security.app-sandbox</key>\n\t<false/>\n\t<key>com.apple.security.get-task-allow</key>\n\t<false/>\n</dict>\n</plist>\n' > $(ENTITLEMENTS)

build: fix-entitlements
	@echo "Generating Xcode project..."
	@xcodegen generate 2>/dev/null || true
	@$(MAKE) fix-entitlements
	@echo "Building $(APP_NAME).app..."
	@xcodebuild -project $(APP_NAME).xcodeproj \
		-scheme $(APP_NAME) \
		-configuration Release \
		-derivedDataPath $(BUILD_DIR) \
		build 2>&1 | tail -5
	@echo ""
	@echo "Built: $(BUILD_DIR)/Build/Products/Release/$(APP_NAME).app"

debug:
	@xcodegen generate 2>/dev/null || true
	@$(MAKE) fix-entitlements
	@xcodebuild -project $(APP_NAME).xcodeproj \
		-scheme $(APP_NAME) \
		-configuration Debug \
		-derivedDataPath $(BUILD_DIR) \
		build 2>&1 | tail -5

install: build
	@echo "Installing to $(INSTALL_DIR)/$(APP_NAME).app..."
	@rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	@cp -R "$(BUILD_DIR)/Build/Products/Release/$(APP_NAME).app" "$(INSTALL_DIR)/"
	@echo "Installed! Launch from Applications or Spotlight."

run: debug
	@open "$(BUILD_DIR)/Build/Products/Debug/$(APP_NAME).app"

clean:
	@rm -rf $(BUILD_DIR) $(APP_NAME).xcodeproj
	@echo "Cleaned."

# Full local release: bump → commit → tag → push → sign → notarize → staple → upload.
# CI is disabled (billing locked on VCasecnikovs account) - everything runs locally.
release:
ifndef VERSION
	$(error Usage: make release VERSION=2.8.1)
endif
	@echo "==> Releasing v$(VERSION)..."
	@sed -i '' 's/MARKETING_VERSION: .*/MARKETING_VERSION: $(VERSION)/' project.yml
	@sed -i '' 's/<string>[0-9]*\.[0-9]*\.[0-9]*<\/string>/<string>$(VERSION)<\/string>/' Hlopya/Info.plist
	@git add project.yml Hlopya/Info.plist
	@git commit -m "Release v$(VERSION)"
	@git tag "v$(VERSION)"
	@git push origin main --tags
	@$(MAKE) sign-notarize
	@echo "==> Uploading to GitHub release..."
	@gh release create "v$(VERSION)" "$(BUILD_DIR)/Build/Products/Release/Hlopya.zip" \
		--title "v$(VERSION)" --generate-notes
	@echo "==> Done: https://github.com/VCasecnikovs/hlopya/releases/tag/v$(VERSION)"

# Build with Developer ID + hardened runtime, notarize via Apple, staple ticket.
# Requires keychain profile 'hlopya-notary' (set up once with notarytool store-credentials).
sign-notarize: fix-entitlements
	@pkill -x Hlopya 2>/dev/null; sleep 1
	@rm -rf $(BUILD_DIR)
	@xcodegen generate 2>/dev/null
	@$(MAKE) fix-entitlements
	@echo "==> Building signed Release..."
	@xcodebuild -project $(APP_NAME).xcodeproj \
		-scheme $(APP_NAME) -configuration Release \
		-derivedDataPath $(BUILD_DIR) \
		CODE_SIGN_IDENTITY="Developer ID Application: Maksimilians Maksimovs (3S29L64542)" \
		CODE_SIGN_STYLE=Manual \
		DEVELOPMENT_TEAM=3S29L64542 \
		OTHER_CODE_SIGN_FLAGS="--options=runtime --timestamp" \
		CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
		CODE_SIGN_ENTITLEMENTS=$(ENTITLEMENTS) \
		build 2>&1 | tail -5
	@cd $(BUILD_DIR)/Build/Products/Release && \
		ditto -c -k --keepParent $(APP_NAME).app $(APP_NAME).zip && \
		echo "==> Submitting to Apple notarytool (3-10 min)..." && \
		xcrun notarytool submit $(APP_NAME).zip --keychain-profile hlopya-notary --wait && \
		xcrun stapler staple $(APP_NAME).app && \
		rm $(APP_NAME).zip && \
		ditto -c -k --keepParent $(APP_NAME).app $(APP_NAME).zip && \
		/usr/sbin/spctl --assess --type execute --verbose=4 $(APP_NAME).app
