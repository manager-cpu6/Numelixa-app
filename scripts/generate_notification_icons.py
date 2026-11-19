from pathlib import Path
import xml.etree.ElementTree as ET

# Each notification category has its own balanced, centered vector silhouette.
# "fill" paths are solid shapes; "stroke" paths use rounded vector strokes.
icons = {
    "admin": [
        ("M12 1.5 L14.2 4.1 L17.5 3.5 L18.4 6.7 L21.5 8.2 L20.4 11.4 L22 14.3 L19.4 16.5 L19.5 19.8 L16.2 20.2 L14 22.5 L11.2 20.7 L8.1 21.5 L6.8 18.5 L3.8 17.1 L4.5 13.8 L2.5 11.2 L4.8 8.8 L4.5 5.5 L7.8 5 L9.5 2.1 Z", "fill"),
    ],
    "number": [
        ("M6.6 2.5 C5.5 1.8 4.1 2 3.3 3 L2.2 4.5 C1.5 5.5 2 7 2.6 8.3 C5.2 14 10 18.8 15.7 21.4 C17 22 18.5 22.5 19.5 21.8 L21 20.7 C22 19.9 22.2 18.5 21.5 17.4 L18.8 14.8 C18 14 16.7 13.8 15.8 14.5 L14.3 15.7 C11.8 14.5 9.5 12.2 8.3 9.7 L9.5 8.2 C10.2 7.3 10 6 9.2 5.2 Z", "fill"),
    ],
    "otp": [
        ("M4 3 H20 C21.1 3 22 3.9 22 5 V14 C22 15.1 21.1 16 20 16 H10 L4 21 V16 H4 C2.9 16 2 15.1 2 14 V5 C2 3.9 2.9 3 4 3 Z", "stroke"),
        ("M6.5 8.5 H8.5 V10.5 H6.5 Z M11 8.5 H13 V10.5 H11 Z M15.5 8.5 H17.5 V10.5 H15.5 Z", "fill"),
    ],
    "auto": [
        ("M20 8 C18.5 4.5 15.6 2.5 12 2.5 C7.5 2.5 4 5.5 3 10", "stroke"),
        ("M3 7 L3 11 L7 10 Z", "fill"),
        ("M4 16 C5.5 19.5 8.4 21.5 12 21.5 C16.5 21.5 20 18.5 21 14", "stroke"),
        ("M21 17 L21 13 L17 14 Z", "fill"),
    ],
    "payment": [
        ("M4 5 H19 C20.7 5 22 6.3 22 8 V18 C22 19.1 21.1 20 20 20 H4 C2.9 20 2 19.1 2 18 V7 C2 5.9 2.9 5 4 5 Z", "fill"),
        ("M15 9 H22 V15 H15 C13.3 15 12 13.7 12 12 C12 10.3 13.3 9 15 9 Z", "fill"),
    ],
    "gift": [
        ("M3 10 H21 V21 H3 Z M2 6 H22 V10 H2 Z", "fill"),
        ("M11 6 H13 V21 H11 Z", "fill"),
        ("M12 6 C8 6 5 5 5 3.2 C5 1.6 7.2 1 8.5 2 C10 3 11 5 12 6 C13 5 14 3 15.5 2 C16.8 1 19 1.6 19 3.2 C19 5 16 6 12 6 Z", "fill"),
    ],
    "general": [
        ("M12 22 C10.9 22 10 21.1 10 20 H14 C14 21.1 13.1 22 12 22 Z", "fill"),
        ("M5 17 C6.5 15.5 6 13 6 10 C6 6.7 8.7 4 12 4 C15.3 4 18 6.7 18 10 C18 13 17.5 15.5 19 17 Z", "fill"),
        ("M10 2 H14 V4 H10 Z", "fill"),
    ],
    "user": [
        ("M12 12 C9.2 12 7 9.8 7 7 C7 4.2 9.2 2 12 2 C14.8 2 17 4.2 17 7 C17 9.8 14.8 12 12 12 Z", "fill"),
        ("M3 22 C3 17.6 6.6 14 11 14 H13 C17.4 14 21 17.6 21 22 Z", "fill"),
    ],
    "system": [
        ("M10 2 H14 L14.8 4.6 L17 5.5 L19.5 4.3 L22 8.5 L20.2 10.4 L20.2 13 L22 14.9 L19.5 19 L17 17.8 L14.8 18.7 L14 22 H10 L9.2 18.7 L7 17.8 L4.5 19 L2 14.9 L3.8 13 L3.8 10.4 L2 8.5 L4.5 4.3 L7 5.5 L9.2 4.6 Z", "fill"),
    ],
    "numelixa": [
        ("M4 20 V4 L12 13 L20 4 V20 H16 V11 L12 16 L8 11 V20 Z", "fill"),
    ],
    "announcement": [
        ("M2 10 V14 H6 L18 20 V4 L6 10 Z", "fill"),
        ("M6 14 L8 21 H12 L10 16 Z", "fill"),
        ("M20 8 C22 10 22 14 20 16", "stroke"),
    ],
    "success": [
        ("M12 2 A10 10 0 1 0 12 22 A10 10 0 1 0 12 2 Z", "stroke"),
        ("M7 12 L10.5 15.5 L17.5 8.5", "stroke"),
    ],
}

res = Path("android/app/src/main/res/drawable")
res.mkdir(parents=True, exist_ok=True)
colour_dir = Path("android/app/src/main/res/drawable-nodpi")
colour_dir.mkdir(parents=True, exist_ok=True)
ns = "http://schemas.android.com/apk/res/android"
ET.register_namespace("android", ns)

for name, paths in icons.items():
    for directory, large in ((res, False), (colour_dir, True)):
        root = ET.Element("vector", {
            f"{{{ns}}}width": "24dp" if not large else "64dp",
            f"{{{ns}}}height": "24dp" if not large else "64dp",
            f"{{{ns}}}viewportWidth": "24",
            f"{{{ns}}}viewportHeight": "24",
        })
        for path_data, kind in paths:
            attrs = {f"{{{ns}}}pathData": path_data}
            if kind == "fill":
                attrs[f"{{{ns}}}fillColor"] = "#FFFFFFFF" if not large else "#FF0D63E8"
                if large:
                    attrs[f"{{{ns}}}strokeColor"] = "#FF16D8FF"
                    attrs[f"{{{ns}}}strokeWidth"] = "0.45"
                    attrs[f"{{{ns}}}strokeLineJoin"] = "round"
            else:
                attrs[f"{{{ns}}}fillColor"] = "#00000000"
                attrs[f"{{{ns}}}strokeColor"] = "#FFFFFFFF" if not large else "#FF16D8FF"
                attrs[f"{{{ns}}}strokeWidth"] = "2.2" if not large else "1.15"
                attrs[f"{{{ns}}}strokeLineCap"] = "round"
                attrs[f"{{{ns}}}strokeLineJoin"] = "round"
            ET.SubElement(root, "path", attrs)
        filename = f"ic_notification_{name}{'_color' if large else ''}.xml"
        target = directory / filename
        ET.ElementTree(root).write(target, encoding="unicode", xml_declaration=True)
        ET.parse(target)

assert len(icons) == 12
print("Generated and XML-validated 12 balanced monochrome notification icons and 12 colour large-icon assets.")
