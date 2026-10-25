#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""归档后把源码 Info.plist 中的自定义键合并进产物 bundle 的 Info.plist。

用法:
  python3 merge_plist.py <源 plist> <产物 plist> <可执行名> <bundle id> <产品名> \
      <模块名> <版本号> <构建号>

- 保留产物 plist 中由构建系统生成的键（图标、DT* 编译信息、AccentColor 等）；
- 源码 plist 中的自定义键（权限说明、Bonjour、NSExtension 等）覆盖/补入；
- 替换 $(EXECUTABLE_NAME) / $(PRODUCT_BUNDLE_IDENTIFIER) 等变量；
- 输出二进制 plist。
"""

import plistlib
import sys


def expand(value, env):
    if isinstance(value, str):
        out = value
        for key, val in env.items():
            out = out.replace("$(%s)" % key, val)
        return out
    if isinstance(value, dict):
        return {k: expand(v, env) for k, v in value.items()}
    if isinstance(value, list):
        return [expand(v, env) for v in value]
    return value


def deep_merge(dst, src):
    for key, sval in src.items():
        if key in dst and isinstance(dst[key], dict) and isinstance(sval, dict):
            deep_merge(dst[key], sval)
        else:
            dst[key] = sval


def main():
    src_path, dst_path, executable, bundle_id, product, module, version, build = sys.argv[1:9]
    env = {
        "EXECUTABLE_NAME": executable,
        "PRODUCT_BUNDLE_IDENTIFIER": bundle_id,
        "PRODUCT_NAME": product,
        "PRODUCT_MODULE_NAME": module,
        "MARKETING_VERSION": version,
        "CURRENT_PROJECT_VERSION": build,
    }

    with open(src_path, "rb") as f:
        source = plistlib.load(f)
    with open(dst_path, "rb") as f:
        built = plistlib.load(f)

    merged = dict(built)
    deep_merge(merged, expand(source, env))

    # 强制写回关键标识，避免变量未替换残留
    merged["CFBundleExecutable"] = executable
    merged["CFBundleIdentifier"] = bundle_id
    merged["CFBundleName"] = product
    merged["CFBundleShortVersionString"] = version
    merged["CFBundleVersion"] = build

    with open(dst_path, "wb") as f:
        plistlib.dump(merged, f, fmt=plistlib.FMT_BINARY)

    print("merged plist:", dst_path)
    for key in ("CFBundleIdentifier", "CFBundleShortVersionString", "CFBundleVersion",
                "NSLocalNetworkUsageDescription", "NSBonjourServices", "NSExtension"):
        if key in merged:
            print("  ok:", key)


if __name__ == "__main__":
    main()
