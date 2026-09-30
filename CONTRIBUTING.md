# Contributing to Blaster

Thank you for your interest in contributing!

## Filing Issues

Use GitHub Issues to report bugs, request features, or ask questions. Please include:
- A clear description of the problem or request
- Steps to reproduce (for bugs)
- Device/simulator and iOS version (for UI issues)

## Opening Pull Requests

1. Fork the repository and create your branch from `main`.
2. Branch naming convention: `feature/<short-description>` or `fix/<short-description>`.
3. Keep changes focused — one feature or fix per PR.
4. Ensure the build passes before submitting:
   ```sh
   xcodebuild -scheme "claudeBlast" -configuration Debug build
   ```
5. Run tests:
   ```sh
   xcodebuild -project claudeBlast.xcodeproj -scheme "claudeBlast" \
     -destination "platform=iOS Simulator,name=iPad Pro 11-inch (M5),OS=26.2" test
   ```
6. Open a PR against `main` with a clear description of what changed and why.

## License

By submitting a pull request you agree that your contribution will be licensed under the **Apache License 2.0**, the same license as the rest of this project.

## Important Notes

- **Do not commit API keys or secrets.** The OpenAI key belongs in the scheme environment variable (`OPENAI_API_KEY`, read by DEBUG builds only) or the in-app settings UI, never in source code.
- **ARASAAC images:** Do not add new ARASAAC pictograms to the repository without understanding the CC BY-NC-SA 4.0 non-commercial restriction. See [NOTICE](NOTICE) and [README.md](README.md) for details.
