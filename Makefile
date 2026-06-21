DEVICE_ID ?= a03cc3eb
PACKAGE_NAME = id.web.noxymon.translatto
MODEL_FILE = gemma-4-E2B-it.litertlm
TARGET_DIR = /data/data/$(PACKAGE_NAME)/app_flutter

.PHONY: push-model debug release install-release help

push-model:
	@echo "Checking connected device $(DEVICE_ID)..."
	adb -s $(DEVICE_ID) shell getprop ro.product.model
	@echo "Pushing model to /data/local/tmp..."
	adb -s $(DEVICE_ID) push $(MODEL_FILE) /data/local/tmp/$(MODEL_FILE)
	@echo "Setting temporary permissions..."
	adb -s $(DEVICE_ID) shell "chmod 666 /data/local/tmp/$(MODEL_FILE)"
	@echo "Creating target app directory..."
	adb -s $(DEVICE_ID) shell "run-as $(PACKAGE_NAME) mkdir -p $(TARGET_DIR)"
	@echo "Copying model to app private storage..."
	adb -s $(DEVICE_ID) shell "run-as $(PACKAGE_NAME) cp /data/local/tmp/$(MODEL_FILE) $(TARGET_DIR)/$(MODEL_FILE)"
	@echo "Cleaning up temporary file from /data/local/tmp..."
	adb -s $(DEVICE_ID) shell "rm /data/local/tmp/$(MODEL_FILE)"
	@echo "Model successfully pushed to app private directory."

debug:
	@echo "Running app in debug mode on device $(DEVICE_ID)..."
	flutter run -d $(DEVICE_ID)

release:
	@echo "Building release APK..."
	flutter build apk --release

install-release:
	@echo "Installing release APK to device $(DEVICE_ID)..."
	adb -s $(DEVICE_ID) install -r build/app/outputs/flutter-apk/app-release.apk

help:
	@echo "Available commands:"
	@echo "  make push-model    - Push the local Gemma model to the device $(DEVICE_ID)"
	@echo "  make debug         - Run the Flutter app in debug mode on device $(DEVICE_ID)"
	@echo "  make release       - Build release APK"
	@echo "  make install-release - Install release APK to device $(DEVICE_ID)"
