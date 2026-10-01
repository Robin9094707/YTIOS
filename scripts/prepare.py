"""Fetch exact MIT-licensed dependencies and generate the app's vector-inspired icon.

Two unrelated upstream packages are both called YouTubeKit. Give the stream
package a distinct module name, without modifying its extraction implementation.
"""
import json
import math
import pathlib
import shutil
import struct
import subprocess
import zlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
REVISION = "e5b7d0396ce12bf3444f0d209e8436c83373b7af"
vendor = ROOT / ".vendor" / "LumaStreams"
if not vendor.exists():
    vendor.parent.mkdir(exist_ok=True)
    subprocess.run(["git", "clone", "https://github.com/alexeichhorn/YouTubeKit.git", str(vendor)], check=True)
subprocess.run(["git", "-C", str(vendor), "checkout", "--force", REVISION], check=True)
manifest = (vendor / "Package.swift").read_text().replace('"YouTubeKit"', '"LumaStreams"')
manifest = manifest.replace('dependencies: [],\n            resources:', 'dependencies: [],\n            path: "Sources/YouTubeKit",\n            resources:')
# No upstream test target is needed in the shipping package.
manifest = manifest.replace('.testTarget(\n            name: "YouTubeKitTests",\n            dependencies: ["LumaStreams"]),', '')
(vendor / "Package.swift").write_text(manifest)
# The optional remote service may only orchestrate anonymous HTTPS requests to
# YouTube's public infrastructure. Keep app account cookies entirely separate.
remote_file = vendor / "Sources/YouTubeKit/Remote/RemoteYouTubeClient.swift"
remote_code = remote_file.read_text()
remote_code = remote_code.replace('let request = serverMessage.content', '''let request = serverMessage.content
                guard request.url.scheme == "https", let host = request.url.host?.lowercased(),
                      ["youtube.com", "googlevideo.com", "ytimg.com", "google.com", "gstatic.com"].contains(where: { host == $0 || host.hasSuffix("." + $0) }) else {
                    throw URLError(.unsupportedURL)
                }''')
remote_code = remote_code.replace('if !request.allowRedirects || request.applyCookiesOnRedirect {', 'if true {')
remote_code = remote_code.replace('let configuration = URLSessionConfiguration.default', 'let configuration = URLSessionConfiguration.ephemeral\n                    configuration.httpCookieStorage = nil\n                    configuration.urlCredentialStorage = nil')
remote_code = remote_code.replace('allowsRedirect: request.allowRedirects, applyCookiesOnRedirect: request.applyCookiesOnRedirect', 'allowsRedirect: false, applyCookiesOnRedirect: false')
remote_file.write_text(remote_code)
assets = ROOT / "Luma/Resources/Assets.xcassets"
icons = assets / "AppIcon.appiconset"
icons.mkdir(parents=True, exist_ok=True)
(assets / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}))
(icons / "Contents.json").write_text(json.dumps({"images": [{"filename": "Luma.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}], "info": {"author": "xcode", "version": 1}}))

def chunk(kind, data):
    return struct.pack('!I', len(data)) + kind + data + struct.pack('!I', zlib.crc32(kind + data))

raw = bytearray()
for y in range(1024):
    raw.append(0)
    for x in range(1024):
        u, v = x / 1024, y / 1024
        glow = math.exp(-((u-.28)**2+(v-.22)**2)/.18)
        cyan = math.exp(-((u-.75)**2+(v-.80)**2)/.20)
        color = [int(15+68*glow+8*cyan), int(17+37*glow+61*cyan), int(32+128*glow+77*cyan)]
        # Curved frosted tile, with a crisp pearl play mark.
        dx, dy = max(abs(x-512)-185, 0), max(abs(y-512)-185, 0)
        if dx*dx+dy*dy < 115**2:
            color = [min(255, int(c*.70+60)) for c in color]
            if dx*dx+dy*dy > 109**2:
                color = [min(255,c+60) for c in color]
        if 430 < x < 655 and abs(y-512) < (655-x)*.63:
            color = [235, 247, 255]
        raw.extend(color)
png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('!2I5B',1024,1024,8,2,0,0,0)) + chunk(b'IDAT',zlib.compress(raw,9)) + chunk(b'IEND',b'')
(icons / "Luma.png").write_bytes(png)
notice = "Luma uses b5i/YouTubeKit (MIT) and alexeichhorn/YouTubeKit (MIT).\n\n"
notice += (ROOT / "licenses/YouTubeAPI-MIT.txt").read_text()
notice += "\n\n" + (ROOT / "licenses/StreamKit-MIT.txt").read_text()
(ROOT / "Luma/Resources/ThirdPartyNotices.txt").write_text(notice)
print("Pinned stream module and 1024px icon prepared.")
