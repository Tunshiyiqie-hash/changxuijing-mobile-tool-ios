#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""修正 xcarchive 顶层 Info.plist 的 ApplicationProperties 版本元数据，
确保 exportArchive 读取到正确的营销版本与构建号。

用法:
  python3 fix_archive.py <xcarchive 路径> <版本号> <构建号>
"""
import plistlib, sys, os

archive, version, build = sys.argv[1], sys.argv[2], sys.argv[3]
top = os.path.join(archive, "Info.plist")

with open(top, "rb") as f:
    d = plistlib.load(f)

print("xcarchive top-level keys:", list(d.keys()))
props = d.get("ApplicationProperties")
if not isinstance(props, dict):
    print("WARNING: no ApplicationProperties; creating")
    props = {}
    d["ApplicationProperties"] = props

print("ApplicationProperties before:")
for k, v in props.items():
    print("  ", k, "=", v)

# 强制所有版本相关键为期望值
for key in ("ApplicationVersion", "CFBundleShortVersionString",
            "ApplicationVersionString", "ShortBundleVersion"):
    props[key] = version
for key in ("CFBundleVersion", "ApplicationBuildVersion"):
    props[key] = build

with open(top, "wb") as f:
    plistlib.dump(d, f, fmt=plistlib.FMT_BINARY)

with open(top, "rb") as f:
    d2 = plistlib.load(f)
print("ApplicationProperties after:")
for k, v in d2["ApplicationProperties"].items():
    print("  ", k, "=", v)
print("fix_archive OK")
