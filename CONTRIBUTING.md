# Contributing to Open Menu Stats

Thanks for helping improve Open Menu Stats.

## Development workflow

1. Fork and clone the repository.
2. Create a focused branch for the change.
3. Open `MenuBarStats.xcodeproj` in Xcode 26 or later.
4. Keep the app dependency-free unless a dependency has a clear maintenance and user benefit.
5. Add or update tests for calculation, persistence, or behavior changes.
6. Run `make test` before opening a pull request.

## Design principles

- Stay native to macOS and feel at home in the menu bar.
- Keep background CPU and energy use low.
- Preserve stable core ordering so visualizations do not jump around.
- Keep status-item width bounded on machines with many logical processors.
- Make every visualization understandable with VoiceOver and without relying only on color.
- Do not add analytics, telemetry, or network access.

## Pull requests

Keep each pull request narrow and explain the user-facing outcome. Include screenshots for visible UI changes and note the macOS and Xcode versions used for verification.
