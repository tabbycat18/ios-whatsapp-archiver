# App Icon Sources

Use `AppIcon-iOS26-source.png` as the source artwork in Icon Composer. It is an exact copy of the current 1024 px app icon, including the archive arrow and tray cut into the top-right of the WhatsApp-style mark.

Use `AppIcon-iOS26-tinted-grayscale.png` as a starting point for the tinted appearance if you configure the icon through an asset catalog instead of Icon Composer.

`AppIconLayered-from-png.svg` is an editable layered SVG rebuilt from that PNG's composition. The numbered `*-from-png.svg` files split the same artwork into separate Icon Composer layers:

1. `01-background-from-png.svg`
2. `02-whatsapp-bubble-ring-from-png.svg`
3. `03-phone-handset-from-png.svg`
4. `04-archive-arrow-tray-from-png.svg`

Dark variants:

- `AppIconLayered-dark-bw.svg` is a black-and-white dark version.
- `AppIconLayered-jet-black.svg` is a jet-black version with subtle graphite depth and a faint green sheen.
- `01-background-dark-bw.svg` and `01-background-jet-black.svg` can replace the default background layer while reusing the white glyph layers.
