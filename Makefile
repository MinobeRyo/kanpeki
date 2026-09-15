.PHONY: slidepacer-test slidepacer-build

slidepacer-test:
	python3 apps/SlidePacer/scripts/check_editorial_planner.py

slidepacer-build:
	xcodebuild -workspace Kanpeki.xcworkspace -scheme SlidePacer \
		-configuration Debug -destination 'generic/platform=macOS' \
		-derivedDataPath .build/SlidePacer CODE_SIGNING_ALLOWED=NO build
