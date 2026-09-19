# Tasks

## 1. Xcode Shared Scheme Configuration

- [x] 1.1 Export and commit the shared scheme `GooCal.xcodeproj/xcshareddata/xcschemes/GooCal.xcscheme` covering build, test (unit & UI), and run actions; verify `xcodebuild -list` discovers the scheme independently of user-specific data.
- [x] 1.2 Validate headless test execution with `xcodebuild test -scheme GooCal -destination 'platform=macOS'` and verify both `GooCalTests` and `GooCalUITests` pass.

## 2. GitHub Actions CI Workflow Setup

- [x] 2.1 Create `.github/workflows/ci.yml` configured to trigger on pushes to `main`, pull requests to `main`, and manual execution (`workflow_dispatch`).
- [x] 2.2 Configure the CI job on `macos-latest` to checkout the repository, execute `xcodebuild test -scheme GooCal -destination 'platform=macOS' -resultBundlePath TestResults.xcresult`, and upload test artifacts on completion using `actions/upload-artifact@v4`.
- [x] 2.3 Verify workflow YAML syntax and structure locally to ensure valid GitHub Actions syntax.
