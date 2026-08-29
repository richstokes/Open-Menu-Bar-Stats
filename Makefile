.PHONY: build test clean

PROJECT := MenuBarStats.xcodeproj
SCHEME := MenuBarStats
DESTINATION := platform=macOS

build:
	xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -destination "$(DESTINATION)" CODE_SIGNING_ALLOWED=NO build

test:
	xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -destination "$(DESTINATION)" CODE_SIGNING_ALLOWED=NO test

clean:
	xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" clean
