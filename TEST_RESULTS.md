# Python migration validation
Version 2.0.0, build 4. Download backend replaced with embedded CPython + yt-dlp + EJS; UI and AVFoundation remain native.

## Current evidence
- Windows Python 3.11 host: 18 Python core/provider tests passed, including a real yt-dlp HTTP transfer of two fixture tracks with byte-for-byte content and progress checks.
- iOS CPython 3.13 runtime, JavaScriptCore EJS loading, HTTPS, cancellation, real YouTube download, merge and Photos tests: pending macOS Actions validation.
- No Python IPA is approved for delivery until all required suites pass. Live geo/bot failures remain failures.
- Desktop network tests and native iOS tests are separate: a desktop pass does not prove native JavaScriptCore works.

## Historical Swift backend
Previous full acceptance run 44127748182 failed 3 of 22 tests. Reported video _pJQFrTU4aQ was region restricted on the CI network; reference aqz-KE-bpKQ required bot verification. That run did not produce an approved IPA.
The earlier 1.1 IPA is not this Python migration.
