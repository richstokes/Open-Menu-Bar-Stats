# Open Menu Stats

Open Menu Stats is a lightweight, open-source system monitor for the macOS menu bar. See CPU activity at a glance, with optional Memory and Thermal items when you want them.

Built from the ground up for modern macOS, Open Menu Stats is optimized to keep its own CPU, memory, and energy use low. It requires **macOS 26 Tahoe or later**.

Open Menu Stats stays out of the way: no Dock icon, no accounts, no analytics, and no network access.

## Highlights

- View all logical CPU cores or follow the busiest core.
- Choose a compact bar chart or numeric percentage.
- Add Memory and macOS thermal state as independent menu-bar items.
- Open the popover for a detailed per-core view.
- Keep your display choices between launches.
- Accessible with VoiceOver, Increase Contrast, and Reduce Motion.

## Build from source

Open `MenuBarStats.xcodeproj` in Xcode 26 or later, select the `MenuBarStats` scheme, and run it on **My Mac**.

From Terminal:

```sh
make build
make test
```

## Privacy

All system information is read locally. Open Menu Stats makes no network requests, includes no analytics or tracking, and collects no personal data.

## Support

Enjoying Open Menu Stats? [Buy me a coffee](https://buymeacoffee.com/richstokes).

## Contributing

Bug reports and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE)
