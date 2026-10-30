# Branding

`icon.svg` is Legato's icon: two notes as eyes, and the legato slur bridging them as a smile, in white on #7E302A. It is the one
source for every app's icon. After changing it, run

```
branding/export.sh
```

which renders it (with Qt's SVG renderer, in `tools/`) into:

| File | Used by |
|---|---|
| `ios/Legato/Assets.xcassets/AppIcon.appiconset/icon-1024.png` | Legato for iPhone (opaque, full bleed: iOS rounds the corners) |
| `ios/LegatoWatch/Assets.xcassets/AppIcon.appiconset/icon-1024.png` | Legato for Apple Watch (watchOS crops it to a circle) |
| `qt/icons/legato.png` | Legato Desktop's window and Dock icon (the macOS shape: a rounded square with a margin) |
| `icon-preview.png` | a preview, rounded as on the iPhone |
