"""Package the actual arm64 archive, and validate the IPA before CI goes green."""
import pathlib
import plistlib
import shutil
import subprocess
import sys
import zipfile

archive, output = map(pathlib.Path, sys.argv[1:3])
app = archive / "Products/Applications/Luma.app"
if not app.is_dir():
    raise SystemExit("No archived device application")
info = plistlib.loads((app / "Info.plist").read_bytes())
executable = app / info["CFBundleExecutable"]
if not executable.is_file():
    raise SystemExit("Missing application executable")
architectures = subprocess.check_output(["lipo", "-archs", str(executable)], text=True).strip()
if "arm64" not in architectures.split():
    raise SystemExit("IPA must contain a real arm64 iPhone executable")
staging = output.parent / "ipa-staging"
shutil.rmtree(staging, ignore_errors=True)
(staging / "Payload").mkdir(parents=True)
shutil.copytree(app, staging / "Payload/Luma.app", symlinks=True)
output.parent.mkdir(parents=True, exist_ok=True)
output = output.resolve()
subprocess.run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(staging / "Payload"), str(output)], check=True)
with zipfile.ZipFile(output) as ipa:
    if ipa.testzip():
        raise SystemExit("Corrupt IPA ZIP")
    embedded = plistlib.loads(ipa.read("Payload/Luma.app/Info.plist"))
    assert embedded["CFBundleIdentifier"] == "de.robin9094707.YTIOS"
    assert f'Payload/Luma.app/{embedded["CFBundleExecutable"]}' in ipa.namelist()
print(f"Verified unsigned IPA: {output.name} ({output.stat().st_size:,} bytes; {architectures})")
