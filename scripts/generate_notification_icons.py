from pathlib import Path
import xml.etree.ElementTree as ET

# Android small-notification icons: transparent canvas, white-only silhouettes.
# Every resource is a separate drawable; do not add text, counters, or backgrounds.
icons = {
    "admin": [
        "M12 2 L14.5 7 L20 7.5 L16 11.5 L17 17 L12 14.2 L7 17 L8 11.5 L4 7.5 L9.5 7 Z",
        "M12 4 L20 7 V12 C20 17 16.5 20.5 12 22 C7.5 20.5 4 17 4 12 V7 Z"
    ],
    "number": [
        "M7 2 H17 C19.2 2 21 3.8 21 6 V18 C21 20.2 19.2 22 17 22 H7 C4.8 22 3 20.2 3 18 V6 C3 3.8 4.8 2 7 2 Z",
        "M9 7 L7.5 17 M16.5 7 L15 17 M6.5 10.5 H18 M6 14 H17.5"
    ],
    "otp": [
        "M4 4 H16 C18.2 4 20 5.8 20 8 V13 C20 15.2 18.2 17 16 17 H10 L5 21 V17 H4 C1.8 17 0 15.2 0 13 V8 C0 5.8 1.8 4 4 4 Z",
        "M8 10 H9 M12 10 H13 M16 10 H17"
    ],
    "auto": [
        "M20 8 C18.5 4.5 15.6 2.5 12 2.5 C7.5 2.5 4 5.5 3 10 H7 C7.8 7.5 9.7 6 12 6 C14 6 15.8 7 17 9 Z",
        "M3 5 V11 H9 M4 16 C5.5 19.5 8.4 21.5 12 21.5 C16.5 21.5 20 18.5 21 14 H17 C16.2 16.5 14.3 18 12 18 C10 18 8.2 17 7 15 Z",
        "M15 2 L21 8 L15 8 Z M9 22 L3 16 L9 16 Z"
    ],
    "payment": [
        "M3 5 H21 C22.1 5 23 5.9 23 7 V18 C23 19.1 22.1 20 21 20 H3 C1.9 20 1 19.1 1 18 V7 C1 5.9 1.9 5 3 5 Z",
        "M1 9 H23 V12 H1 Z M5 16 H10 V17.5 H5 Z"
    ],
    "gift": [
        "M3 10 H21 V21 H3 Z M2 6 H22 V10 H2 Z M11 6 C7 6 5 4.8 5 3.2 C5 1.5 7.2 1 8.5 2 C10 3.1 11 6 12 6 C13 6 14 3.1 15.5 2 C16.8 1 19 1.5 19 3.2 C19 4.8 17 6 13 6 Z",
        "M11 6 V21 M13 6 V21"
    ],
    "general": [
        "M12 22 C10.9 22 10 21.1 10 20 H14 C14 21.1 13.1 22 12 22 Z",
        "M5 17 C6.5 15.5 6 13 6 10 C6 6.7 8.7 4 12 4 C15.3 4 18 6.7 18 10 C18 13 17.5 15.5 19 17 Z",
        "M10 2 H14 V4 H10 Z"
    ],
    "user": [
        "M12 12 C9.2 12 7 9.8 7 7 C7 4.2 9.2 2 12 2 C14.8 2 17 4.2 17 7 C17 9.8 14.8 12 12 12 Z",
        "M3 22 C3 17.6 6.6 14 11 14 H13 C17.4 14 21 17.6 21 22 Z"
    ],
    "system": [
        "M10 2 H14 L14.7 4.4 L17 5.3 L19.4 4.2 L21.8 7.7 L20.1 9.7 L20.2 12.2 L22 14.2 L20 18 L17.5 17.5 L15.5 18.8 L14.8 21 H10.8 L10 18.7 L7.8 17.7 L5.4 18.7 L3.2 15.2 L4.9 13.2 L4.8 10.8 L3 8.8 L5 5 L7.5 5.5 L9.5 4.2 Z",
        "M12 8 A4 4 0 1 0 12 16 A4 4 0 1 0 12 8 Z"
    ],
    "numelixa": [
        "M4 20 V4 L12 14 L20 4 V20 H16 V11 L12 16 L8 11 V20 Z"
    ],
    "announcement": [
        "M2 10 V14 H6 L18 20 V4 L6 10 Z",
        "M6 14 L8 21 H12 L10 16",
        "M20 8 C22 10 22 14 20 16"
    ],
    "success": [
        "M12 2 A10 10 0 1 0 12 22 A10 10 0 1 0 12 2 Z",
        "M7 12 L10.5 15.5 L17.5 8.5"
    ],
}

res = Path("android/app/src/main/res/drawable")
res.mkdir(parents=True, exist_ok=True)
ns = "http://schemas.android.com/apk/res/android"
ET.register_namespace("android", ns)
for name, paths in icons.items():
    root = ET.Element("vector", {
        f"{{{ns}}}width": "24dp",
        f"{{{ns}}}height": "24dp",
        f"{{{ns}}}viewportWidth": "24",
        f"{{{ns}}}viewportHeight": "24",
    })
    for path in paths:
        ET.SubElement(root, "path", {
            f"{{{ns}}}fillColor": "#FFFFFFFF",
            f"{{{ns}}}pathData": path,
        })
    ET.ElementTree(root).write(res / f"ic_notification_{name}.xml", encoding="unicode", xml_declaration=True)
    ET.parse(res / f"ic_notification_{name}.xml")

    # Full-colour artwork is used only as the expanded notification's large icon.
    colour_dir = Path("android/app/src/main/res/drawable-nodpi")
    colour_dir.mkdir(parents=True, exist_ok=True)
    colour_root = ET.Element("vector", {
        f"{{{ns}}}width": "64dp", f"{{{ns}}}height": "64dp",
        f"{{{ns}}}viewportWidth": "24", f"{{{ns}}}viewportHeight": "24",
    })
    for path in paths:
        ET.SubElement(colour_root, "path", {
            f"{{{ns}}}fillColor": "#FF0D63E8",
            f"{{{ns}}}strokeColor": "#FF16D8FF",
            f"{{{ns}}}strokeWidth": "0.7",
            f"{{{ns}}}strokeLineCap": "round",
            f"{{{ns}}}strokeLineJoin": "round",
            f"{{{ns}}}pathData": path,
        })
    colour_file = colour_dir / f"ic_notification_{name}_color.xml"
    ET.ElementTree(colour_root).write(colour_file, encoding="unicode", xml_declaration=True)
    ET.parse(colour_file)

assert len(icons) == 12
print("Generated and XML-validated 12 monochrome icons and 12 large-icon assets.")
