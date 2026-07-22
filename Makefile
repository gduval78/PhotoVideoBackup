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

# Run the full hermetic test target (all groups except the live NAS integration test)
test-all:
	xcodebuild test \
	  -scheme $(SCHEME) \
	  -destination "$(DESTINATION)" \
	  -skip-testing:PhotoVideoBackupTests/LiveNASIntegrationTests \
	  | grep -E "(Test Suite|Test Case|passed|failed|error|\*\* TEST)" \
	  | sed 's/^/  /'

# Live SMB round-trip against a real NAS. Requires nas-test-config.json at the repo root
# (gitignored) and a reachable NAS; the test skips itself if the file is absent. Kept out of
# test-all via -skip-testing, which is the real hermetic boundary.
#
# Runs on the iOS Simulator, NOT "Designed for iPad": the Mac-sandboxed Designed-for-iPad process
# cannot read a file outside its container (the credentials file), whereas the simulator can.
test-nas:
	xcodebuild test \
	  -scheme $(SCHEME) \
	  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
	  -only-testing:PhotoVideoBackupTests/LiveNASIntegrationTests \
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

.PHONY: test-scenario test-all test-nas testiphone build-test
