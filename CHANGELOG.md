# Changelog

All notable changes to this plugin. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [1.1.0] - 2026-11-02

### Added

- On firmware that does not report cycle count or charge thresholds through
  sysfs, such as coreboot on ThinkPads, the helper reads them from an optional
  cache file written by a privileged producer
  (`/run/thinkpad-battery-meta/battery-packs.tsv`, or `OMARCHY_BATTERY_META`).
  Sysfs values always win, and with no file nothing changes. The plugin does
  not ship a producer. Contributed by [@felixzsh](https://github.com/felixzsh)
  in [#2](https://github.com/cinco/omarchy-batteries/pull/2).
- The cache is read as untrusted input: at most 16 KiB, with a 1-second
  timeout. Rows over 128 bytes or without a trailing newline are ignored, and
  values are range-checked (cycles up to six digits, end threshold 1 to 100,
  start below end).

## [1.0.2] - 2026-11-02

### Changed

- With several packs on a horizontal bar, each pack is now its own
  `BarIconButton`: the icon goes in `text` and the percentage in `labelText`.
  Omarchy's button draws, sizes and aligns every pack, so the percentage sits
  on the same baseline as the built-in power widget. The plugin also stops
  redrawing the button's canvas itself. Pressing a pack animates only that
  pack. A single pack and vertical bars keep the one aggregate button,
  unchanged. Approach by [@felixzsh](https://github.com/felixzsh) in
  [#3](https://github.com/cinco/omarchy-batteries/pull/3).

### Fixed

- The open-panel mark covers every pack's percentage and icon, and it stays
  centred when the percentages differ in width (`100%` next to `9%`).
- The panel keeps a single anchor, so plugging or unplugging the bay battery
  while the panel is open no longer moves it.

## [1.0.1] - 2026-10-31

### Fixed

- Packs are readable on the bar again under Omarchy's normalized bar icons.
  `BarIconButton` now fits `text` to a single icon, which squeezed the whole
  per-pack string into one icon slot. Each pack now gets its own label and
  glyph.

## [1.0.0] - 2026-08-23

### Added

- First release: a drop-in replacement for the built-in `omarchy.power`
  widget that shows every battery.
- On the bar, one icon per pack, in sysfs order, with an optional
  percentage. Right-click toggles the percentage.
- In the panel, the aggregate summary followed by a stat block for each pack:
  level, size, cycles, health, time left or time to full, draw and charge
  limit.
- A bundled `battery-packs` helper that reads cycle count, design capacity and
  charge thresholds from sysfs.
- Installing it takes over the built-in widget's place on the bar
  (`clonedFrom: omarchy.power`), and the existing keybinding and menu
  entries keep working.

[1.1.0]: https://github.com/cinco/omarchy-batteries/compare/v1.0.2...v1.1.0
[1.0.2]: https://github.com/cinco/omarchy-batteries/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/cinco/omarchy-batteries/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/cinco/omarchy-batteries/releases/tag/v1.0.0
