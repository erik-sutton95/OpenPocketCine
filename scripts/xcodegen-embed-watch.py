#!/usr/bin/env python3
"""Xcode 26+ embeds watchOS apps in PlugIns/, not Watch/.

XcodeGen still emits Embed Watch Content with dstSubfolderSpec 16 and
dstPath $(CONTENTS_FOLDER_PATH)/Watch. Rewrite that copy phase in place.
Run from `ios/` after `xcodegen generate`. Idempotent.
"""
from pathlib import Path

pbx = Path("OpenPocketCine.xcodeproj/project.pbxproj")
if not pbx.exists():
    raise SystemExit(0)
text = pbx.read_text()
old = 'dstPath = "$(CONTENTS_FOLDER_PATH)/Watch";\n\t\t\tdstSubfolderSpec = 16;'
new = 'dstPath = "";\n\t\t\tdstSubfolderSpec = 13;'
if old in text:
    pbx.write_text(text.replace(old, new, 1))
