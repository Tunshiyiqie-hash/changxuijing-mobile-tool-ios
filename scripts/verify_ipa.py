#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""上传前校验最终 IPA：主 app 与广播扩展的版本号、构建号、顶层 RPBroadcastProcessMode。

用法:
  python3 verify_ipa.py <ipa 路径> <期望版本> <期望构建号>
不符合预期则退出码 1。
"""
import zipfile, plistlib, sys

ipa, expect_ver, expect_build = sys.argv[1], sys.argv[2], sys.argv[3]
z = zipfile.ZipFile(ipa)
app_plist = None
appex_plist = None
for n in z.namelist():
    if n.endswith(".app/Info.plist"):
        app_plist = plistlib.loads(z.read(n))
    if n.endswith(".appex/Info.plist"):
        appex_plist = plistlib.loads(z.read(n))

errors = []

def check(name, d):
    print("----", name)
    if d is None:
        errors.append(name + " plist not found")
        return
    ver = d.get("CFBundleShortVersionString")
    bld = d.get("CFBundleVersion")
    bid = d.get("CFBundleIdentifier")
    print("  bundle id =", bid)
    print("  version   =", ver)
    print("  build     =", bld)
    if ver != expect_ver:
        errors.append("%s version %s != %s" % (name, ver, expect_ver))
    if str(bld) != expect_build:
        errors.append("%s build %s != %s" % (name, bld, expect_build))

check("Main app", app_plist)
check("Broadcast extension", appex_plist)

if appex_plist is not None:
    mode = appex_plist.get("RPBroadcastProcessMode")
    print("  top-level RPBroadcastProcessMode =", mode)
    if mode not in ("RPBroadcastProcessModeSampleBuffer", "RPBroadcastProcessModeMP4Clip"):
        errors.append("missing/invalid top-level RPBroadcastProcessMode")

if errors:
    print("VERIFY FAILED:")
    for e in errors:
        print("  -", e)
    sys.exit(1)
print("VERIFY OK")
