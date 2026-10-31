"""Adds INTERNET + CAMERA permissions, camera feature (optional), and minSdk 23 (secure storage)."""
import pathlib, re, sys

manifest = pathlib.Path("android/app/src/main/AndroidManifest.xml")
m = manifest.read_text()
add = ""
if "android.permission.INTERNET" not in m:
    add += '    <uses-permission android:name="android.permission.INTERNET"/>\n'
if "android.permission.CAMERA" not in m:
    add += '    <uses-permission android:name="android.permission.CAMERA"/>\n'
    add += '    <uses-feature android:name="android.hardware.camera" android:required="false"/>\n'
if add:
    m = re.sub(r"(<manifest[^>]*>\n)", lambda x: x.group(1) + add, m, count=1)
    manifest.write_text(m)

m = manifest.read_text()
m = re.sub(r'android:label="[^"]*"', 'android:label="S.K. PU College"', m, count=1)
manifest.write_text(m)

for name in ("build.gradle.kts", "build.gradle"):
    f = pathlib.Path("android/app") / name
    if f.exists():
        g = f.read_text()
        g2 = g.replace("flutter.minSdkVersion", "23")
        g2 = re.sub(r"minSdkVersion\s+\d+", "minSdkVersion 23", g2)
        g2 = re.sub(r"minSdk\s*=\s*\d+", "minSdk = 23", g2)
        f.write_text(g2)
        break
else:
    sys.exit("build.gradle not found")
print("Android project patched.")
