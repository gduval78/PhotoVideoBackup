SCHEME      = PhotoVideoBackup
# Mac "Designed for iPad" — no simulator needed, fastest execution
DESTINATION = platform=macOS,variant=Designed for iPad

# Run all regression scenarios (SD card / USB source flows)
test-scenario:
	xcodebuild test \
	  -scheme $(SCHEME) \
	  -destination "$(DESTINATION)" \
	  -only-testing:PhotoVideoBackupTests/BackupFromSDCardTests \
	  | grep -E "(Test Suite|Test Case|passed|failed|error|\*\* TEST)" \
	  | sed 's/^/  /'

# Run the full test target (all test groups)
test-all:
	xcodebuild test \
	  -scheme $(SCHEME) \
	  -destination "$(DESTINATION)" \
	  | grep -E "(Test Suite|Test Case|passed|failed|error|\*\* TEST)" \
	  | sed 's/^/  /'
# Run all tests on iPhone 17 Pro simulator
testiphone:
	xcodebuild test \
	  -scheme $(SCHEME) \
	  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
	  | grep -E "(Test Suite|Test Case|passed|failed|error|\*\* TEST)" \
	  | sed 's/^/  /'

# Build without running tests (quick sanity check)
build-test:
	xcodebuild build-for-testing \
	  -scheme $(SCHEME) \
	  -destination "$(DESTINATION)"

.PHONY: test-scenario test-all testiphone build-test
