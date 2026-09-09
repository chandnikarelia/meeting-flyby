# App icon

`AppIcon.icns` is generated, not hand-drawn — `makeicon.swift` renders the artwork with
Core Graphics and exports every iconset size.

To change the icon (colors, character, layout), edit `makeicon.swift` and re-run:

```bash
swiftc -O -o /tmp/makeicon Icon/makeicon.swift -framework Cocoa
/tmp/makeicon Icon/AppIcon.iconset
iconutil -c icns Icon/AppIcon.iconset -o Icon/AppIcon.icns
./build.sh
```

`build.sh` copies `AppIcon.icns` into the app bundle; `Info.plist` points at it via
`CFBundleIconFile`.
