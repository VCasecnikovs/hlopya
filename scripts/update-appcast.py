#!/usr/bin/env python3
"""Append a new Sparkle release entry to appcast.xml.

Called from `make release` after sign-notarize + sign_update have produced:
  - the notarized, stapled zip at .build/xcode/Build/Products/Release/Hlopya.zip
  - an EdDSA signature + length from `sign_update`

Usage:
    update-appcast.py \
        --version 2.9.0 \
        --build 1 \
        --zip .build/xcode/Build/Products/Release/Hlopya.zip \
        --signature "<base64 ed sig>" \
        --length <byte length>

Creates appcast.xml if missing. Otherwise prepends the new <item> block
so the newest release is first (what Sparkle expects).
"""

from __future__ import annotations

import argparse
import datetime
import os
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
APPCAST = REPO / "appcast.xml"
GITHUB_RELEASE_URL = "https://github.com/VCasecnikovs/hlopya/releases/download/v{v}/Hlopya.zip"

EMPTY_APPCAST = """<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
<channel>
<title>Hlopya</title>
<link>https://raw.githubusercontent.com/VCasecnikovs/hlopya/main/appcast.xml</link>
<description>Hlopya updates</description>
<language>en</language>
</channel>
</rss>
"""


def rfc822_now() -> str:
    # Sparkle wants RFC 822 dates.
    return datetime.datetime.now(datetime.timezone.utc).strftime(
        "%a, %d %b %Y %H:%M:%S +0000"
    )


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--version", required=True, help="marketing version, e.g. 2.9.0")
    p.add_argument("--build", required=True, help="CFBundleVersion, e.g. 1")
    p.add_argument("--zip", required=True, help="path to signed+notarized zip")
    p.add_argument("--signature", required=True, help="EdDSA signature from sign_update")
    p.add_argument("--length", required=True, type=int, help="file byte length")
    p.add_argument("--min-system", default="14.2", help="minimum macOS version")
    p.add_argument("--notes", default="", help="release notes URL or markdown")
    args = p.parse_args()

    if not Path(args.zip).exists():
        print(f"error: zip not found at {args.zip}", file=sys.stderr)
        return 1

    if not APPCAST.exists():
        APPCAST.write_text(EMPTY_APPCAST)

    ET.register_namespace("sparkle", "http://www.andymatuschak.org/xml-namespaces/sparkle")
    tree = ET.parse(APPCAST)
    root = tree.getroot()
    channel = root.find("channel")
    if channel is None:
        print("error: appcast.xml has no <channel>", file=sys.stderr)
        return 1

    sparkle_ns = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
    item = ET.Element("item")
    ET.SubElement(item, "title").text = f"Version {args.version}"
    ET.SubElement(item, "pubDate").text = rfc822_now()
    ET.SubElement(item, f"{sparkle_ns}version").text = args.build
    ET.SubElement(item, f"{sparkle_ns}shortVersionString").text = args.version
    ET.SubElement(item, f"{sparkle_ns}minimumSystemVersion").text = args.min_system
    if args.notes:
        ET.SubElement(item, "description").text = args.notes
    ET.SubElement(
        item,
        "enclosure",
        {
            "url": GITHUB_RELEASE_URL.format(v=args.version),
            "length": str(args.length),
            "type": "application/octet-stream",
            f"{sparkle_ns}edSignature": args.signature,
        },
    )

    existing_items = channel.findall("item")
    insert_idx = 0
    for idx, child in enumerate(list(channel)):
        if child.tag == "item":
            insert_idx = idx
            break
    else:
        insert_idx = len(list(channel))
    # Drop any prior entry for the same version (idempotency on retries).
    for old in existing_items:
        short = old.find(f"{sparkle_ns}shortVersionString")
        if short is not None and short.text == args.version:
            channel.remove(old)
    channel.insert(insert_idx, item)

    ET.indent(tree, space="  ")
    tree.write(APPCAST, encoding="utf-8", xml_declaration=True)
    # ET.indent + xml_declaration adds a newline issue on macOS - ensure final newline.
    data = APPCAST.read_bytes()
    if not data.endswith(b"\n"):
        APPCAST.write_bytes(data + b"\n")

    print(f"appended v{args.version} to {APPCAST}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
