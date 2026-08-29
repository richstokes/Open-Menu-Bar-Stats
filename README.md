# Open Menu Stats

Open Menu Stats is a small, native, open-source macOS CPU monitor. It lives entirely in the menu bar, samples each logical CPU once per second, and has no third-party dependencies.

## Features

- Show all logical cores or automatically follow the busiest core.
- Switch between a live bar chart and a numeric percentage view.
- See a compact summary directly in the menu bar; systems with more than ten logical cores are condensed into ten status-chart buckets while the popover retains every core.
- Keep the detailed per-core view in a scrollable popover on high-core-count Macs.
- Remember display choices between launches.
- Work without accounts, network access, analytics, or elevated permissions.
- Support VoiceOver, increased contrast, and Reduce Motion.

## Requirements

- macOS 14 Sonoma or later
- Xcode 26 or later to build the project as currently configured

The project uses the active `macosx` SDK rather than pinning one SDK release. It is written in Swift 6 with SwiftUI and currently builds against the macOS 26.5 SDK in Xcode 26.6.

## Build and run

1. Open `MenuBarStats.xcodeproj` in Xcode.
2. Select the `MenuBarStats` scheme and the `My Mac` destination.
3. Press Run.
4. Find the CPU symbol in the menu bar; the app intentionally has no Dock icon.

To build or test from Terminal:

```sh
make build
make test
```

The app is configured with the bundle identifier `richstokes.menubarstats` for its App Store Connect record.

## How CPU usage is calculated

`host_processor_info` provides cumulative user, system, nice, and idle tick counters for every logical processor. The app takes the difference between consecutive samples and calculates:

```text
busy = user + system + nice
usage = busy / (busy + idle)
```

The overall value is calculated from summed tick deltas rather than averaging rounded per-core percentages. The first read establishes a baseline, so the UI briefly shows “Measuring CPU usage…” after launch.

All Mach allocations and port rights are released after every read. Sampling and counter state live in an actor so reads cannot overlap.

## Project layout

```text
MenuBarStats/
  App/           SwiftUI app entry point
  CPU/           Mach reader, sampling actor, calculation, and models
  Preferences/   Persisted presentation choices
  UI/            Menu-bar label, popover, charts, and numeric views
MenuBarStatsTests/
```

## Privacy

Open Menu Stats reads CPU counters available on the local Mac. It makes no network requests and stores only the two display preferences in `UserDefaults`. Its privacy manifest declares no tracking or collected data and documents the app-only preferences access.

## Contributing

Bug reports and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for the development workflow.

## License

Open Menu Stats is available under the [MIT License](LICENSE).
