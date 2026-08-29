# Project identity

- App name: **Open Menu Stats**
- Bundle identifier: `richstokes.menubarstats`
- App Store Connect app ID: `6806666233`
- Distribution record: https://appstoreconnect.apple.com/apps/6806666233/distribution
- Keep the existing `MenuBarStats` Xcode project, target, scheme, and Swift module names unless a deliberate internal rename is required. The shipped product name is `Open Menu Stats`.

# App Store compatibility

- Preserve Mac App Store compatibility in every change.
- Use only documented public Apple APIs and keep the app sandboxed.
- Do not add undocumented SMC/IOHID sensor access, private frameworks, privileged helpers, root escalation, or shell-command-based hardware sampling.
- When macOS does not publicly expose a metric, use the closest accurate public representation and label it honestly. For temperature, use `ProcessInfo.thermalState`; do not present it as a Celsius reading.
