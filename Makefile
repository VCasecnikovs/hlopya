APP_NAME = Hlopya
BUILD_DIR = .build/xcode
INSTALL_DIR = /Applications
ENTITLEMENTS = Hlopya/Hlopya.entitlements

.PHONY: build install clean run debug fix-entitlements

fix-entitlements:
	@printf '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0">\n<dict>\n\t<key>com.apple.security.device.audio-input</key>\n\t<true/>\n\t<key>com.apple.security.app-sandbox</key>\n\t<false/>\n</dict>\n</plist>\n' > $(ENTITLEMENTS)

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
