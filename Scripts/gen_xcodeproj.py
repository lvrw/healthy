#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成 Healthy.xcodeproj（project.pbxproj + 共享 scheme + workspace）。

沿用 ChoreRing 工程生成器的三条规则（写死在脚本里，不要"优化"掉）：
  1. objectVersion 必须是 77；
  2. 所有 build setting 的值、所有数组元素都必须加引号 —— 少一个引号会让 Xcode
     误判为 JSON 并把项目报成"damaged"；
  3. 同一个 fileRef 只能属于一个 group。跨 target 共享源码（Healthy/Scoring、
     Healthy/Support）靠构建阶段复用，绝不放进第二个 group。

测试 target 与 ChoreRing 一致：不设 TEST_HOST，把纯逻辑源码直接编进测试包，
测试无需启动 App、无需真机签名。

用法：python3 Scripts/gen_xcodeproj.py
"""

import hashlib
import os
import sys

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJECT_NAME = "Healthy"
APP_BUNDLE_ID = "cn.rw.healthy"
TEST_BUNDLE_ID = "cn.rw.healthy.tests"
TEST_TARGET_NAME = "HealthyTests"
TEAM_ID = "CM5UZP3C76"

APP_INFO_PLIST = "Config/Info.plist"
APP_ENTITLEMENTS = "Config/Healthy.entitlements"

# 手表伴侣 App：源码仍在 HealthyWatch/ 下（与旧的独立手表工程同源），
# 但产物作为 iOS App 的嵌入内容随手机一起安装 —— 只有配成伴侣才能用 WatchConnectivity
# 把 iPhone 上的配置（喝水目标等）推给手表。
WATCH_TARGET_NAME = "HealthyWatch"
WATCH_WIDGET_TARGET_NAME = "HealthyWatchWidget"
WATCH_BUNDLE_ID = "cn.rw.healthy.watch"
WATCH_WIDGET_BUNDLE_ID = "cn.rw.healthy.watch.waterwidget"
WATCH_ROOT = "HealthyWatch"
WATCH_APP_ROOT = "HealthyWatch/HealthyWatch"
WATCH_WIDGET_ROOT = "HealthyWatch/HealthyWatchWidget"
WATCH_INFO_PLIST = "HealthyWatch/HealthyWatch/Info.plist"
WATCH_ENTITLEMENTS = "HealthyWatch/HealthyWatch/HealthyWatch.entitlements"
WATCH_WIDGET_INFO_PLIST = "HealthyWatch/HealthyWatchWidget/Info.plist"
WATCH_WIDGET_ENTITLEMENTS = "HealthyWatch/HealthyWatchWidget/HealthyWatchWidget.entitlements"
# 手表目录里的构建残留与旧工程文件不能进项目导航器。
WATCH_SKIP_DIRS = ("build", "DerivedData")

CONFIGURATIONS = ["Debug", "Release"]
SCAN_ROOTS = ["Healthy", "HealthyTests", "Config", "Scripts"]

APP_SOURCE_ROOT = "Healthy"
TEST_SOURCE_ROOTS = ("HealthyTests",)
# HealthTypes.swift 只依赖 HealthKit，供测试校验特征类型授权集合；其余 Health/ 源码依赖 UI/SwiftData，不编入测试包。
# FoodModels / FoodDatabase 只依赖 Foundation 与已共享的 Support/IntakeNutrition，供份量解析与等比缩放单测；
# 其它 Food/ 源码依赖 SwiftData / SwiftUI / LLM，按单文件精确加入，不整目录共享。
TEST_SHARED_PREFIXES = (
    "Healthy/Scoring/", "Healthy/Support/", "Healthy/LLM/", "Healthy/Health/HealthTypes.swift",
    "Healthy/Features/Food/FoodModels.swift", "Healthy/Features/Food/FoodDatabase.swift",
    "Healthy/Features/Food/FoodRecognitionService.swift",
    "Healthy/Features/Food/CustomFood.swift", "Healthy/Features/Food/FoodGroup.swift",
    "Healthy/Features/Food/FoodSeed.swift", "Healthy/Features/Food/FoodRecognitionSettings.swift",
)
TEST_EXCLUDED_FILES = ("Healthy/LLM/BriefingService.swift",)

RESOURCE_PREFIX = "Healthy/Resources/"
RESOURCE_SUFFIXES = (".xcassets",)
SOURCE_SUFFIXES = (".swift",)

FILE_TYPES = {
    ".swift": "sourcecode.swift",
    ".plist": "text.plist.xml",
    ".entitlements": "text.plist.entitlements",
    ".xcassets": "folder.assetcatalog",
    ".json": "text.json",
    ".strings": "text.plist.strings",
}


def oid(key):
    """由语义化 key 派生稳定的 24 位十六进制对象 ID，保证重复生成结果不变。"""
    return hashlib.md5(key.encode("utf-8")).hexdigest()[:24].upper()


def q(value):
    """pbxproj 里的一切值都要加引号（见文件头规则 2）。"""
    return '"{0}"'.format(value)


def file_type(filename):
    for suffix, kind in FILE_TYPES.items():
        if filename.endswith(suffix):
            return kind
    return "text"


class Group(object):
    """项目导航器里的一个分组。path 为 None 表示虚拟分组（如 Products）。"""

    def __init__(self, name, path=None, key=None):
        self.name = name
        self.path = path
        self.key = key or name
        self.files = []
        self.children = {}
        self.rel_paths = {}

    def child(self, name):
        if name not in self.children:
            self.children[name] = Group(name, name, "{0}/{1}".format(self.key, name))
        return self.children[name]


def scan_extra_root(root_name, abs_root, skip_dir_names=()):
    """扫描一个额外源码根目录（手表伴侣），返回可直接挂到主组下的 Group。

    与 build_group_tree 的唯一区别：跳过构建残留与旧的 .xcodeproj 目录，
    避免把手表工程的历史产物塞进 iOS 工程导航器。
    """
    node = Group(root_name, root_name, root_name)
    for dirpath, dirnames, filenames in os.walk(abs_root):
        asset_catalogs = sorted(d for d in dirnames if d.endswith(".xcassets"))
        dirnames[:] = sorted(
            d for d in dirnames
            if not d.startswith(".")
            and not d.endswith(".xcassets")
            and not d.endswith(".xcodeproj")
            and d not in skip_dir_names
        )
        rel = os.path.relpath(dirpath, abs_root)
        current = node
        if rel != ".":
            for part in rel.split(os.sep):
                current = current.child(part)
        for filename in asset_catalogs + sorted(filenames):
            if filename.startswith("."):
                continue
            current.files.append(filename)
            current.rel_paths[filename] = os.path.relpath(
                os.path.join(dirpath, filename), PROJECT_ROOT
            )
    return node


def build_group_tree():
    root = Group(PROJECT_NAME, None, "root")
    for scan_root in SCAN_ROOTS:
        abs_root = os.path.join(PROJECT_ROOT, scan_root)
        if not os.path.isdir(abs_root):
            continue
        node = root.child(scan_root)
        for dirpath, dirnames, filenames in os.walk(abs_root):
            asset_catalogs = sorted(d for d in dirnames if d.endswith(".xcassets"))
            dirnames[:] = sorted(
                d for d in dirnames if not d.startswith(".") and not d.endswith(".xcassets")
            )
            rel = os.path.relpath(dirpath, abs_root)
            current = node
            if rel != ".":
                for part in rel.split(os.sep):
                    current = current.child(part)
            for filename in asset_catalogs + sorted(filenames):
                if filename.startswith("."):
                    continue
                current.files.append(filename)
                current.rel_paths[filename] = os.path.relpath(
                    os.path.join(dirpath, filename), PROJECT_ROOT
                )
    watch_abs = os.path.join(PROJECT_ROOT, WATCH_ROOT)
    if os.path.isdir(watch_abs):
        root.children[WATCH_ROOT] = scan_extra_root(WATCH_ROOT, watch_abs, WATCH_SKIP_DIRS)
    return root


def collect_paths(group, predicate):
    found = []
    for filename in group.files:
        rel = group.rel_paths[filename]
        if predicate(filename, rel):
            found.append(rel)
    for name in sorted(group.children):
        found.extend(collect_paths(group.children[name], predicate))
    return found


def flat_groups(group, out):
    out.append(group)
    for name in sorted(group.children):
        flat_groups(group.children[name], out)
    return out


def build_settings_lines(settings):
    lines = []
    for key in sorted(settings):
        value = settings[key]
        if isinstance(value, list):
            items = ", ".join(q(str(v)) for v in value)
            lines.append("\t\t\t\t{0} = ({1},);".format(key, items))
        else:
            lines.append("\t\t\t\t{0} = {1};".format(key, q(str(value))))
    return lines


def main():
    tree = build_group_tree()
    all_groups = flat_groups(tree, [])

    def app_predicate(filename, rel):
        return filename.endswith(SOURCE_SUFFIXES) and rel.split(os.sep)[0] == APP_SOURCE_ROOT

    def test_predicate(filename, rel):
        if not filename.endswith(SOURCE_SUFFIXES):
            return False
        if rel in TEST_EXCLUDED_FILES:
            return False
        if rel.split(os.sep)[0] in TEST_SOURCE_ROOTS:
            return True
        return any(rel.startswith(prefix) for prefix in TEST_SHARED_PREFIXES)

    app_sources = collect_paths(tree, app_predicate)
    test_sources = collect_paths(tree, test_predicate)
    app_resources = collect_paths(
        tree,
        lambda f, r: f.endswith(RESOURCE_SUFFIXES) and r.startswith(RESOURCE_PREFIX),
    )
    # 手表伴侣：App 与小组件扩展的源码 / 资源分别收集，两个 target 各自独立编译。
    watch_sources = collect_paths(
        tree,
        lambda f, r: f.endswith(SOURCE_SUFFIXES) and r.startswith(WATCH_APP_ROOT + os.sep),
    )
    watch_widget_sources = collect_paths(
        tree,
        lambda f, r: f.endswith(SOURCE_SUFFIXES) and r.startswith(WATCH_WIDGET_ROOT + os.sep),
    )
    # WaterShared 是手表 App 与小组件扩展共用的本机共享层（App Group 队列 + 写健康数据），
    # 两个 target 都要编进去；两个 target 各生成自己的 PBXBuildFile，fileRef 仍只有一个。
    shared_watch_source = WATCH_WIDGET_ROOT + "/WaterShared.swift"
    if (
        os.path.exists(os.path.join(PROJECT_ROOT, shared_watch_source))
        and shared_watch_source not in watch_sources
    ):
        watch_sources.append(shared_watch_source)
    watch_resources = collect_paths(
        tree,
        lambda f, r: f.endswith(RESOURCE_SUFFIXES) and r.startswith(WATCH_APP_ROOT + os.sep),
    )

    # 本地化显示名：英文系统下读取 en.lproj/InfoPlist.strings 覆盖 CFBundleDisplayName
    for dirpath, _, filenames in os.walk(os.path.join(PROJECT_ROOT, "Healthy")):
        if not os.path.basename(dirpath).endswith(".lproj"):
            continue
        for fn in filenames:
            if fn == "InfoPlist.strings":
                rel = os.path.relpath(os.path.join(dirpath, fn), PROJECT_ROOT)
                if rel not in app_resources:
                    app_resources.append(rel)
    app_resources.sort()

    assert app_sources, "没有扫描到主 App 源码"
    assert test_sources, "没有扫描到测试源码"
    assert watch_sources, "没有扫描到手表 App 源码"
    assert watch_widget_sources, "没有扫描到手表小组件源码"

    products = [
        (PROJECT_NAME, "{0}.app".format(PROJECT_NAME), "wrapper.application"),
        (TEST_TARGET_NAME, "{0}.xctest".format(TEST_TARGET_NAME), "wrapper.cfbundle"),
        (WATCH_TARGET_NAME, "{0}.app".format(WATCH_TARGET_NAME), "wrapper.application"),
        (
            WATCH_WIDGET_TARGET_NAME,
            "{0}.appex".format(WATCH_WIDGET_TARGET_NAME),
            "wrapper.app-extension",
        ),
    ]

    ids = {
        "project": oid("project"),
        "main_group": oid("group:main"),
        "products_group": oid("group:products"),
        "app_target": oid("target:app"),
        "test_target": oid("target:test"),
        "watch_target": oid("target:watch"),
        "watch_widget_target": oid("target:watch-widget"),
        "watch_embed_phase": oid("phase:embed-watch"),
        "watch_extension_phase": oid("phase:embed-watch-extension"),
        "watch_dependency": oid("dependency:watch"),
        "watch_widget_dependency": oid("dependency:watch-widget"),
        "watch_proxy": oid("proxy:watch"),
        "watch_widget_proxy": oid("proxy:watch-widget"),
    }
    for name, _, _ in products:
        ids["product_" + name] = oid("product:" + name)

    sections = {}

    # ---------- PBXBuildFile ----------
    build_files = []
    for target, sources in (
        (PROJECT_NAME, app_sources),
        (TEST_TARGET_NAME, test_sources),
        (WATCH_TARGET_NAME, watch_sources),
        (WATCH_WIDGET_TARGET_NAME, watch_widget_sources),
    ):
        for rel in sources:
            filename = os.path.basename(rel)
            bf = oid("buildfile:{0}:{1}".format(target, rel))
            fr = oid("fileref:" + rel)
            build_files.append(
                "\t\t{0} /* {1} in Sources */ = {{isa = PBXBuildFile; fileRef = {2} /* {3} */; }};".format(
                    bf, filename, fr, filename
                )
            )
    for rel in app_resources:
        filename = os.path.basename(rel)
        bf = oid("buildfile:app-res:{0}".format(rel))
        fr = oid("fileref:" + rel)
        build_files.append(
            "\t\t{0} /* {1} in Resources */ = {{isa = PBXBuildFile; fileRef = {2} /* {3} */; }};".format(
                bf, filename, fr, filename
            )
        )
    for rel in watch_resources:
        filename = os.path.basename(rel)
        bf = oid("buildfile:watch-res:{0}".format(rel))
        fr = oid("fileref:" + rel)
        build_files.append(
            "\t\t{0} /* {1} in Resources */ = {{isa = PBXBuildFile; fileRef = {2} /* {3} */; }};".format(
                bf, filename, fr, filename
            )
        )
    # 两级嵌入：手表 App 嵌在 iOS App 的 Watch/ 下，小组件扩展嵌在手表 App 的 PlugIns/ 下。
    build_files.append(
        "\t\t{0} /* {1}.app in Embed Watch Content */ = {{isa = PBXBuildFile; "
        "fileRef = {2} /* {1}.app */; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};".format(
            oid("buildfile:embed-watch"), WATCH_TARGET_NAME, ids["product_" + WATCH_TARGET_NAME]
        )
    )
    build_files.append(
        "\t\t{0} /* {1}.appex in Embed App Extensions */ = {{isa = PBXBuildFile; "
        "fileRef = {2} /* {1}.appex */; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};".format(
            oid("buildfile:embed-watch-extension"),
            WATCH_WIDGET_TARGET_NAME,
            ids["product_" + WATCH_WIDGET_TARGET_NAME],
        )
    )
    sections["PBXBuildFile"] = build_files

    # ---------- PBXFileReference ----------
    file_refs = []
    seen_refs = set()
    for group in all_groups:
        for filename in group.files:
            rel = group.rel_paths[filename]
            if rel in seen_refs:
                continue
            seen_refs.add(rel)
            fr = oid("fileref:" + rel)
            file_refs.append(
                "\t\t{0} /* {1} */ = {{isa = PBXFileReference; lastKnownFileType = {2}; "
                "path = {3}; sourceTree = \"<group>\"; }};".format(
                    fr, filename, file_type(filename), q(filename)
                )
            )
    for name, path, kind in products:
        file_refs.append(
            "\t\t{0} /* {1} */ = {{isa = PBXFileReference; explicitFileType = {2}; "
            "includeInIndex = 0; path = {3}; sourceTree = BUILT_PRODUCTS_DIR; }};".format(
                ids["product_" + name], path, kind, q(path)
            )
        )
    sections["PBXFileReference"] = file_refs

    # ---------- PBXContainerItemProxy / PBXTargetDependency ----------
    # 依赖链：Healthy → HealthyWatch → HealthyWatchWidget，构建顺序与嵌入顺序一致。
    sections["PBXContainerItemProxy"] = [
        "\t\t{0} /* PBXContainerItemProxy */ = {{\n"
        "\t\t\tisa = PBXContainerItemProxy;\n"
        "\t\t\tcontainerPortal = {1} /* Project object */;\n"
        "\t\t\tproxyType = 1;\n"
        "\t\t\tremoteGlobalIDString = {2};\n"
        "\t\t\tremoteInfo = {3};\n"
        "\t\t}};".format(
            ids["watch_proxy"], ids["project"], ids["watch_target"], WATCH_TARGET_NAME
        ),
        "\t\t{0} /* PBXContainerItemProxy */ = {{\n"
        "\t\t\tisa = PBXContainerItemProxy;\n"
        "\t\t\tcontainerPortal = {1} /* Project object */;\n"
        "\t\t\tproxyType = 1;\n"
        "\t\t\tremoteGlobalIDString = {2};\n"
        "\t\t\tremoteInfo = {3};\n"
        "\t\t}};".format(
            ids["watch_widget_proxy"], ids["project"],
            ids["watch_widget_target"], WATCH_WIDGET_TARGET_NAME,
        ),
    ]
    sections["PBXTargetDependency"] = [
        "\t\t{0} /* PBXTargetDependency */ = {{\n"
        "\t\t\tisa = PBXTargetDependency;\n"
        "\t\t\ttarget = {1} /* {2} */;\n"
        "\t\t\ttargetProxy = {3} /* PBXContainerItemProxy */;\n"
        "\t\t}};".format(
            ids["watch_dependency"], ids["watch_target"], WATCH_TARGET_NAME, ids["watch_proxy"]
        ),
        "\t\t{0} /* PBXTargetDependency */ = {{\n"
        "\t\t\tisa = PBXTargetDependency;\n"
        "\t\t\ttarget = {1} /* {2} */;\n"
        "\t\t\ttargetProxy = {3} /* PBXContainerItemProxy */;\n"
        "\t\t}};".format(
            ids["watch_widget_dependency"], ids["watch_widget_target"],
            WATCH_WIDGET_TARGET_NAME, ids["watch_widget_proxy"],
        ),
    ]

    # ---------- PBXCopyFilesBuildPhase ----------
    # dstSubfolderSpec 16 = Products Directory，指向 Contents/Watch：Xcode 只认这个位置的手表 App。
    # dstSubfolderSpec 13 = PlugIns：手表小组件扩展必须嵌在手表 App 内部。
    sections["PBXCopyFilesBuildPhase"] = [
        "\t\t{0} /* Embed Watch Content */ = {{\n"
        "\t\t\tisa = PBXCopyFilesBuildPhase;\n"
        "\t\t\tbuildActionMask = 2147483647;\n"
        "\t\t\tdstPath = \"$(CONTENTS_FOLDER_PATH)/Watch\";\n"
        "\t\t\tdstSubfolderSpec = 16;\n"
        "\t\t\tfiles = (\n"
        "\t\t\t\t{1} /* {2}.app in Embed Watch Content */,\n"
        "\t\t\t);\n"
        "\t\t\tname = \"Embed Watch Content\";\n"
        "\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
        "\t\t}};".format(
            ids["watch_embed_phase"], oid("buildfile:embed-watch"), WATCH_TARGET_NAME
        ),
        "\t\t{0} /* Embed App Extensions */ = {{\n"
        "\t\t\tisa = PBXCopyFilesBuildPhase;\n"
        "\t\t\tbuildActionMask = 2147483647;\n"
        "\t\t\tdstPath = \"\";\n"
        "\t\t\tdstSubfolderSpec = 13;\n"
        "\t\t\tfiles = (\n"
        "\t\t\t\t{1} /* {2}.appex in Embed App Extensions */,\n"
        "\t\t\t);\n"
        "\t\t\tname = \"Embed App Extensions\";\n"
        "\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
        "\t\t}};".format(
            ids["watch_extension_phase"], oid("buildfile:embed-watch-extension"),
            WATCH_WIDGET_TARGET_NAME,
        ),
    ]

    # ---------- PBXFrameworksBuildPhase ----------
    frameworks = []
    for label in (PROJECT_NAME, TEST_TARGET_NAME, WATCH_TARGET_NAME, WATCH_WIDGET_TARGET_NAME):
        pid = oid("phase:frameworks:" + label)
        ids["frameworks_" + label] = pid
        frameworks.append(
            "\t\t{0} /* Frameworks */ = {{\n"
            "\t\t\tisa = PBXFrameworksBuildPhase;\n"
            "\t\t\tbuildActionMask = 2147483647;\n"
            "\t\t\tfiles = (\n"
            "\t\t\t);\n"
            "\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
            "\t\t}};".format(pid)
        )
    sections["PBXFrameworksBuildPhase"] = frameworks

    # ---------- PBXGroup ----------
    groups_out = []
    for group in all_groups:
        if group.key == "root":
            group_id = ids["main_group"]
        else:
            group_id = oid("group:" + group.key)
        children = []
        for filename in group.files:
            children.append("{0} /* {1} */".format(oid("fileref:" + group.rel_paths[filename]), filename))
        for name in sorted(group.children):
            children.append("{0} /* {1} */".format(oid("group:" + group.children[name].key), name))
        if group.key == "root":
            children.append("{0} /* Products */".format(ids["products_group"]))
        body = "\t\t{0} /* {1} */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n".format(
            group_id, group.name
        )
        for child in children:
            body += "\t\t\t\t{0},\n".format(child)
        body += "\t\t\t);\n"
        if group.path is not None:
            body += "\t\t\tpath = {0};\n".format(q(group.path))
        body += "\t\t\tsourceTree = \"<group>\";\n\t\t};"
        groups_out.append(body)

    products_children = "".join(
        "\t\t\t\t{0} /* {1} */,\n".format(ids["product_" + name], path)
        for name, path, _ in products
    )
    groups_out.append(
        "\t\t{0} /* Products */ = {{\n"
        "\t\t\tisa = PBXGroup;\n"
        "\t\t\tchildren = (\n"
        "{1}"
        "\t\t\t);\n"
        "\t\t\tname = Products;\n"
        "\t\t\tsourceTree = \"<group>\";\n"
        "\t\t}};".format(ids["products_group"], products_children)
    )
    sections["PBXGroup"] = groups_out

    # ---------- PBXNativeTarget ----------
    sources_phases = {}
    resources_phases = {}
    for label in (PROJECT_NAME, TEST_TARGET_NAME, WATCH_TARGET_NAME, WATCH_WIDGET_TARGET_NAME):
        sources_phases[label] = oid("phase:sources:" + label)
        resources_phases[label] = oid("phase:resources:" + label)
        ids["sources_" + label] = sources_phases[label]
        ids["resources_" + label] = resources_phases[label]

    def sources_phase(phase_id, target_build_files):
        body = "\t\t{0} /* Sources */ = {{\n\t\t\tisa = PBXSourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n".format(
            phase_id
        )
        for bf, filename in target_build_files:
            body += "\t\t\t\t{0} /* {1} in Sources */,\n".format(bf, filename)
        body += "\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};"
        return body

    def resources_phase(phase_id, items):
        body = "\t\t{0} /* Resources */ = {{\n\t\t\tisa = PBXResourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n".format(
            phase_id
        )
        for bf, filename in items:
            body += "\t\t\t\t{0} /* {1} in Resources */,\n".format(bf, filename)
        body += "\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};"
        return body

    app_pairs = [
        (oid("buildfile:{0}:{1}".format(PROJECT_NAME, rel)), os.path.basename(rel))
        for rel in app_sources
    ]
    test_pairs = [
        (oid("buildfile:{0}:{1}".format(TEST_TARGET_NAME, rel)), os.path.basename(rel))
        for rel in test_sources
    ]
    app_res_pairs = [
        (oid("buildfile:app-res:{0}".format(rel)), os.path.basename(rel)) for rel in app_resources
    ]

    def native_target_text(target_id, name, product_path, product_type, phases, dependencies):
        """生成一个 PBXNativeTarget；phases / dependencies 都是 (id, 注释) 列表。"""
        body = (
            "\t\t{0} /* {1} */ = {{\n"
            "\t\t\tisa = PBXNativeTarget;\n"
            "\t\t\tbuildConfigurationList = {2} /* Build configuration list for PBXNativeTarget \"{1}\" */;\n"
            "\t\t\tbuildPhases = (\n"
        ).format(target_id, name, oid("configlist:target:" + name))
        for phase_id, comment in phases:
            body += "\t\t\t\t{0} /* {1} */,\n".format(phase_id, comment)
        body += "\t\t\t);\n\t\t\tbuildRules = (\n\t\t\t);\n\t\t\tdependencies = (\n"
        for dep_id, comment in dependencies:
            body += "\t\t\t\t{0} /* {1} */,\n".format(dep_id, comment)
        body += (
            "\t\t\t);\n"
            "\t\t\tname = {0};\n"
            "\t\t\tproductName = {0};\n"
            "\t\t\tproductReference = {1} /* {2} */;\n"
            "\t\t\tproductType = \"{3}\";\n"
            "\t\t}};"
        ).format(name, ids["product_" + name], product_path, product_type)
        return body

    native_targets = [
        native_target_text(
            ids["app_target"], PROJECT_NAME, "{0}.app".format(PROJECT_NAME),
            "com.apple.product-type.application",
            [
                (sources_phases[PROJECT_NAME], "Sources"),
                (ids["frameworks_" + PROJECT_NAME], "Frameworks"),
                (resources_phases[PROJECT_NAME], "Resources"),
                (ids["watch_embed_phase"], "Embed Watch Content"),
            ],
            [(ids["watch_dependency"], "PBXTargetDependency")],
        ),
        native_target_text(
            ids["test_target"], TEST_TARGET_NAME, "{0}.xctest".format(TEST_TARGET_NAME),
            "com.apple.product-type.bundle.unit-test",
            [
                (sources_phases[TEST_TARGET_NAME], "Sources"),
                (ids["frameworks_" + TEST_TARGET_NAME], "Frameworks"),
                (resources_phases[TEST_TARGET_NAME], "Resources"),
            ],
            [],
        ),
        native_target_text(
            ids["watch_target"], WATCH_TARGET_NAME, "{0}.app".format(WATCH_TARGET_NAME),
            "com.apple.product-type.application",
            [
                (sources_phases[WATCH_TARGET_NAME], "Sources"),
                (ids["frameworks_" + WATCH_TARGET_NAME], "Frameworks"),
                (resources_phases[WATCH_TARGET_NAME], "Resources"),
                (ids["watch_extension_phase"], "Embed App Extensions"),
            ],
            [(ids["watch_widget_dependency"], "PBXTargetDependency")],
        ),
        native_target_text(
            ids["watch_widget_target"], WATCH_WIDGET_TARGET_NAME,
            "{0}.appex".format(WATCH_WIDGET_TARGET_NAME),
            "com.apple.product-type.app-extension",
            [
                (sources_phases[WATCH_WIDGET_TARGET_NAME], "Sources"),
                (ids["frameworks_" + WATCH_WIDGET_TARGET_NAME], "Frameworks"),
                (resources_phases[WATCH_WIDGET_TARGET_NAME], "Resources"),
            ],
            [],
        ),
    ]
    sections["PBXNativeTarget"] = native_targets

    # ---------- PBXProject ----------
    target_attribute_lines = "".join(
        "\t\t\t\t\t{0} = {{ CreatedOnToolsVersion = 27.1; }};\n".format(ids[key])
        for key in ("app_target", "test_target", "watch_target", "watch_widget_target")
    )
    project_target_lines = "".join(
        "\t\t\t\t{0} /* {1} */,\n".format(ids[key], name)
        for key, name in (
            ("app_target", PROJECT_NAME),
            ("test_target", TEST_TARGET_NAME),
            ("watch_target", WATCH_TARGET_NAME),
            ("watch_widget_target", WATCH_WIDGET_TARGET_NAME),
        )
    )
    sections["PBXProject"] = [
        "\t\t{0} /* Project object */ = {{\n"
        "\t\t\tisa = PBXProject;\n"
        "\t\t\tattributes = {{\n"
        "\t\t\t\tBuildIndependentTargetsInParallel = 1;\n"
        "\t\t\t\tLastSwiftUpdateCheck = 2710;\n"
        "\t\t\t\tLastUpgradeCheck = 2710;\n"
        "\t\t\t\tTargetAttributes = {{\n"
        "{1}"
        "\t\t\t\t}};\n"
        "\t\t\t}};\n"
        "\t\t\tbuildConfigurationList = {2} /* Build configuration list for PBXProject \"{3}\" */;\n"
        "\t\t\tdevelopmentRegion = \"zh-Hans\";\n"
        "\t\t\thasScannedForEncodings = 0;\n"
        "\t\t\tknownRegions = (\n"
        "\t\t\t\t\"zh-Hans\",\n"
        "\t\t\t\t\"Base\",\n"
        "\t\t\t);\n"
        "\t\t\tmainGroup = {4};\n"
        "\t\t\tminimizedProjectReferenceProxies = 1;\n"
        "\t\t\tpreferredProjectObjectVersion = 77;\n"
        "\t\t\tproductRefGroup = {5} /* Products */;\n"
        "\t\t\tprojectDirPath = \"\";\n"
        "\t\t\tprojectRoot = \"\";\n"
        "\t\t\ttargets = (\n"
        "{6}"
        "\t\t\t);\n"
        "\t\t}};".format(
            ids["project"], target_attribute_lines,
            oid("configlist:project"), PROJECT_NAME,
            ids["main_group"], ids["products_group"], project_target_lines,
        )
    ]

    watch_pairs = [
        (oid("buildfile:{0}:{1}".format(WATCH_TARGET_NAME, rel)), os.path.basename(rel))
        for rel in watch_sources
    ]
    watch_widget_pairs = [
        (oid("buildfile:{0}:{1}".format(WATCH_WIDGET_TARGET_NAME, rel)), os.path.basename(rel))
        for rel in watch_widget_sources
    ]
    watch_res_pairs = [
        (oid("buildfile:watch-res:{0}".format(rel)), os.path.basename(rel))
        for rel in watch_resources
    ]

    # ---------- PBXResourcesBuildPhase ----------
    sections["PBXResourcesBuildPhase"] = [
        resources_phase(resources_phases[PROJECT_NAME], app_res_pairs),
        resources_phase(resources_phases[TEST_TARGET_NAME], []),
        resources_phase(resources_phases[WATCH_TARGET_NAME], watch_res_pairs),
        resources_phase(resources_phases[WATCH_WIDGET_TARGET_NAME], []),
    ]

    # ---------- PBXSourcesBuildPhase ----------
    sections["PBXSourcesBuildPhase"] = [
        sources_phase(sources_phases[PROJECT_NAME], app_pairs),
        sources_phase(sources_phases[TEST_TARGET_NAME], test_pairs),
        sources_phase(sources_phases[WATCH_TARGET_NAME], watch_pairs),
        sources_phase(sources_phases[WATCH_WIDGET_TARGET_NAME], watch_widget_pairs),
    ]

    # ---------- XCBuildConfiguration ----------
    project_debug = {
        "ALWAYS_SEARCH_USER_PATHS": "NO",
        "CLANG_ANALYZER_NONNULL": "YES",
        "CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION": "YES_AGGRESSIVE",
        "CLANG_ENABLE_MODULES": "YES",
        "CLANG_ENABLE_OBJC_ARC": "YES",
        "CLANG_ENABLE_OBJC_WEAK": "YES",
        "CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING": "YES",
        "CLANG_WARN_BOOL_CONVERSION": "YES",
        "CLANG_WARN_COMMA": "YES",
        "CLANG_WARN_CONSTANT_CONVERSION": "YES",
        "CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS": "YES",
        "CLANG_WARN_DIRECT_OBJC_ISA_USAGE": "YES_ERROR",
        "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES",
        "CLANG_WARN_EMPTY_BODY": "YES",
        "CLANG_WARN_ENUM_CONVERSION": "YES",
        "CLANG_WARN_INFINITE_RECURSION": "YES",
        "CLANG_WARN_INT_CONVERSION": "YES",
        "CLANG_WARN_NON_LITERAL_NULL_CONVERSION": "YES",
        "CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF": "YES",
        "CLANG_WARN_OBJC_LITERAL_CONVERSION": "YES",
        "CLANG_WARN_OBJC_ROOT_CLASS": "YES_ERROR",
        "CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER": "YES",
        "CLANG_WARN_RANGE_LOOP_ANALYSIS": "YES",
        "CLANG_WARN_STRICT_PROTOTYPES": "YES",
        "CLANG_WARN_SUSPICIOUS_MOVE": "YES",
        "CLANG_WARN_UNGUARDED_AVAILABILITY": "YES_AGGRESSIVE",
        "CLANG_WARN_UNREACHABLE_CODE": "YES",
        "CLANG_WARN__DUPLICATE_METHOD_MATCH": "YES",
        "COPY_PHASE_STRIP": "NO",
        "DEBUG_INFORMATION_FORMAT": "dwarf",
        "ENABLE_STRICT_OBJC_MSGSEND": "YES",
        "ENABLE_TESTABILITY": "YES",
        "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
        "GCC_C_LANGUAGE_STANDARD": "gnu17",
        "GCC_DYNAMIC_NO_PIC": "NO",
        "GCC_NO_COMMON_BLOCKS": "YES",
        "GCC_OPTIMIZATION_LEVEL": "0",
        "GCC_PREPROCESSOR_DEFINITIONS": ["DEBUG=1", "$(inherited)"],
        "GCC_WARN_64_TO_32_BIT_CONVERSION": "YES",
        "GCC_WARN_ABOUT_RETURN_TYPE": "YES_ERROR",
        "GCC_WARN_UNDECLARED_SELECTOR": "YES",
        "GCC_WARN_UNINITIALIZED_AUTOS": "YES_AGGRESSIVE",
        "GCC_WARN_UNUSED_FUNCTION": "YES",
        "GCC_WARN_UNUSED_VARIABLE": "YES",
        "IPHONEOS_DEPLOYMENT_TARGET": "18.0",
        "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
        "MTL_FAST_MATH": "YES",
        "ONLY_ACTIVE_ARCH": "YES",
        "SDKROOT": "iphoneos",
        "SUPPORTED_PLATFORMS": ["iphoneos", "iphonesimulator"],
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": ["DEBUG", "$(inherited)"],
        "SWIFT_EMIT_LOC_STRINGS": "YES",
        "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
        "SWIFT_STRICT_CONCURRENCY": "complete",
        "SWIFT_VERSION": "6.0",
        "TARGETED_DEVICE_FAMILY": "1",
    }
    project_release = dict(project_debug)
    project_release.update(
        {
            "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
            "ENABLE_NS_ASSERTIONS": "NO",
            "ENABLE_TESTABILITY": "NO",
            "GCC_OPTIMIZATION_LEVEL": "s",
            "MTL_ENABLE_DEBUG_INFO": "NO",
            "ONLY_ACTIVE_ARCH": "NO",
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS": ["$(inherited)"],
            "SWIFT_COMPILATION_MODE": "wholemodule",
            "SWIFT_OPTIMIZATION_LEVEL": "-O",
            "VALIDATE_PRODUCT": "YES",
        }
    )
    del project_release["GCC_DYNAMIC_NO_PIC"]

    app_common = {
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "CODE_SIGN_ENTITLEMENTS": APP_ENTITLEMENTS,
        "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": "1",
        "DEVELOPMENT_TEAM": TEAM_ID,
        "GENERATE_INFOPLIST_FILE": "NO",
        "INFOPLIST_FILE": APP_INFO_PLIST,
        "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
        "MARKETING_VERSION": "1.0",
        "PRODUCT_BUNDLE_IDENTIFIER": APP_BUNDLE_ID,
        "PRODUCT_NAME": "$(TARGET_NAME)",
        "SWIFT_EMIT_LOC_STRINGS": "YES",
    }
    test_common = {
        "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": "1",
        "DEVELOPMENT_TEAM": TEAM_ID,
        "FRAMEWORK_SEARCH_PATHS": [
            "$(inherited)",
            "$(PLATFORM_DIR)/Developer/Library/Frameworks",
        ],
        "GENERATE_INFOPLIST_FILE": "YES",
        "LD_RUNPATH_SEARCH_PATHS": [
            "$(inherited)",
            "@executable_path/Frameworks",
            "@loader_path/Frameworks",
        ],
        "MARKETING_VERSION": "1.0",
        "PRODUCT_BUNDLE_IDENTIFIER": TEST_BUNDLE_ID,
        "PRODUCT_NAME": "$(TARGET_NAME)",
        "SWIFT_EMIT_LOC_STRINGS": "NO",
    }

    # 手表伴侣 App：SDK 与设备族由 target 级覆盖，project 级的 iphoneos 设置不能漏进来。
    watch_common = {
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "CODE_SIGN_ENTITLEMENTS": WATCH_ENTITLEMENTS,
        "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": "1",
        "DEVELOPMENT_TEAM": TEAM_ID,
        "ENABLE_PREVIEWS": "YES",
        "GENERATE_INFOPLIST_FILE": "NO",
        "INFOPLIST_FILE": WATCH_INFO_PLIST,
        "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
        "MARKETING_VERSION": "1.0",
        "PRODUCT_BUNDLE_IDENTIFIER": WATCH_BUNDLE_ID,
        "PRODUCT_NAME": "$(TARGET_NAME)",
        "SDKROOT": "watchos",
        "SKIP_INSTALL": "YES",
        "SUPPORTED_PLATFORMS": ["watchos", "watchsimulator"],
        "SWIFT_EMIT_LOC_STRINGS": "YES",
        "SWIFT_VERSION": "6.0",
        "TARGETED_DEVICE_FAMILY": "4",
        "WATCHOS_DEPLOYMENT_TARGET": "11.0",
    }
    watch_widget_common = {
        "CODE_SIGN_ENTITLEMENTS": WATCH_WIDGET_ENTITLEMENTS,
        "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": "1",
        "DEVELOPMENT_TEAM": TEAM_ID,
        "GENERATE_INFOPLIST_FILE": "NO",
        "INFOPLIST_FILE": WATCH_WIDGET_INFO_PLIST,
        "LD_RUNPATH_SEARCH_PATHS": [
            "$(inherited)",
            "@executable_path/Frameworks",
            "@executable_path/../../Frameworks",
        ],
        "MARKETING_VERSION": "1.0",
        "PRODUCT_BUNDLE_IDENTIFIER": WATCH_WIDGET_BUNDLE_ID,
        "PRODUCT_NAME": "$(TARGET_NAME)",
        "SDKROOT": "watchos",
        "SKIP_INSTALL": "YES",
        "SUPPORTED_PLATFORMS": ["watchos", "watchsimulator"],
        "SWIFT_EMIT_LOC_STRINGS": "YES",
        "SWIFT_VERSION": "6.0",
        "TARGETED_DEVICE_FAMILY": "4",
        "WATCHOS_DEPLOYMENT_TARGET": "11.0",
    }

    configs = []
    for label in CONFIGURATIONS:
        settings = dict(project_release if label == "Release" else project_debug)
        configs.append(
            "\t\t{0} /* {1} */ = {{\n"
            "\t\t\tisa = XCBuildConfiguration;\n"
            "\t\t\tbuildSettings = {{\n"
            "{2}\n"
            "\t\t\t}};\n"
            "\t\t\tname = {1};\n"
            "\t\t}};".format(
                oid("config:project:" + label), label,
                "\n".join(build_settings_lines(settings)),
            )
        )
    for target_name, common in (
        (PROJECT_NAME, app_common),
        (TEST_TARGET_NAME, test_common),
        (WATCH_TARGET_NAME, watch_common),
        (WATCH_WIDGET_TARGET_NAME, watch_widget_common),
    ):
        for label in CONFIGURATIONS:
            settings = dict(common)
            if label == "Release":
                settings["SWIFT_COMPILATION_MODE"] = "wholemodule"
            configs.append(
                "\t\t{0} /* {1} */ = {{\n"
                "\t\t\tisa = XCBuildConfiguration;\n"
                "\t\t\tbuildSettings = {{\n"
                "{2}\n"
                "\t\t\t}};\n"
                "\t\t\tname = {1};\n"
                "\t\t}};".format(
                    oid("config:target:{0}:{1}".format(target_name, label)), label,
                    "\n".join(build_settings_lines(settings)),
                )
            )
    sections["XCBuildConfiguration"] = configs

    # ---------- XCConfigurationList ----------
    def config_list_fixed(list_id, owner, entries):
        body = "\t\t{0} /* Build configuration list for {1} */ = {{\n".format(list_id, owner)
        body += "\t\t\tisa = XCConfigurationList;\n\t\t\tbuildConfigurations = (\n"
        for config_id, label in entries:
            body += "\t\t\t\t{0} /* {1} */,\n".format(config_id, label)
        body += "\t\t\t);\n\t\t\tdefaultConfigurationIsVisible = 0;\n"
        body += "\t\t\tdefaultConfigurationName = Release;\n\t\t};"
        return body

    lists = [
        config_list_fixed(
            oid("configlist:project"),
            'PBXProject "{0}"'.format(PROJECT_NAME),
            [(oid("config:project:" + label), label) for label in CONFIGURATIONS],
        )
    ]
    for target_name in (PROJECT_NAME, TEST_TARGET_NAME, WATCH_TARGET_NAME, WATCH_WIDGET_TARGET_NAME):
        lists.append(
            config_list_fixed(
                oid("configlist:target:" + target_name),
                'PBXNativeTarget "{0}"'.format(target_name),
                [(oid("config:target:{0}:{1}".format(target_name, label)), label)
                 for label in CONFIGURATIONS],
            )
        )
    sections["XCConfigurationList"] = lists

    # ---------- 组装 ----------
    order = [
        "PBXBuildFile",
        "PBXContainerItemProxy",
        "PBXCopyFilesBuildPhase",
        "PBXFileReference",
        "PBXFrameworksBuildPhase",
        "PBXGroup",
        "PBXNativeTarget",
        "PBXProject",
        "PBXResourcesBuildPhase",
        "PBXSourcesBuildPhase",
        "PBXTargetDependency",
        "XCBuildConfiguration",
        "XCConfigurationList",
    ]
    out = ["// !$*UTF8*$!", "{", "\tarchiveVersion = 1;", "\tclasses = {", "\t};",
           "\tobjectVersion = 77;", "\tobjects = {", ""]
    for section in order:
        out.append("/* Begin {0} section */".format(section))
        out.extend(sections[section])
        out.append("/* End {0} section */".format(section))
        out.append("")
    out.append("\t};")
    out.append("\trootObject = {0} /* Project object */;".format(ids["project"]))
    out.append("}")
    out.append("")

    project_dir = os.path.join(PROJECT_ROOT, "{0}.xcodeproj".format(PROJECT_NAME))
    os.makedirs(project_dir, exist_ok=True)
    pbxproj_path = os.path.join(project_dir, "project.pbxproj")
    pbxproj_text = "\n".join(out)

    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import check_pbxproj

    try:
        check_pbxproj.Parser(check_pbxproj.tokenize(pbxproj_text)).parse()
    except check_pbxproj.Failure as failure:
        raise SystemExit("生成的 pbxproj 语法不合法，已中止写入：{0}".format(failure))

    with open(pbxproj_path, "w", encoding="utf-8") as handle:
        handle.write(pbxproj_text)

    workspace_dir = os.path.join(project_dir, "project.xcworkspace")
    os.makedirs(workspace_dir, exist_ok=True)
    with open(os.path.join(workspace_dir, "contents.xcworkspacedata"), "w", encoding="utf-8") as handle:
        handle.write(
            '<?xml version="1.0" encoding="UTF-8"?>\n'
            '<Workspace\n   version = "1.0">\n'
            '   <FileRef\n      location = "self:">\n   </FileRef>\n'
            "</Workspace>\n"
        )

    schemes_dir = os.path.join(project_dir, "xcshareddata", "xcschemes")
    os.makedirs(schemes_dir, exist_ok=True)
    with open(os.path.join(schemes_dir, "{0}.xcscheme".format(PROJECT_NAME)), "w", encoding="utf-8") as handle:
        handle.write(
            '<?xml version="1.0" encoding="UTF-8"?>\n'
            '<Scheme LastUpgradeVersion = "2710" version = "1.7">\n'
            '   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">\n'
            "      <BuildActionEntries>\n"
            "         <BuildActionEntry buildForTesting = \"YES\" buildForRunning = \"YES\" buildForProfiling = \"YES\" buildForArchiving = \"YES\" buildForAnalyzing = \"YES\">\n"
            "            <BuildableReference BuildableIdentifier = \"primary\" BlueprintIdentifier = \"{app}\" BuildableName = \"{name}.app\" BlueprintName = \"{name}\" ReferencedContainer = \"container:{name}.xcodeproj\">\n"
            "            </BuildableReference>\n"
            "         </BuildActionEntry>\n"
            "         <BuildActionEntry buildForTesting = \"NO\" buildForRunning = \"YES\" buildForProfiling = \"YES\" buildForArchiving = \"YES\" buildForAnalyzing = \"YES\">\n"
            "            <BuildableReference BuildableIdentifier = \"primary\" BlueprintIdentifier = \"{watchApp}\" BuildableName = \"{watchName}.app\" BlueprintName = \"{watchName}\" ReferencedContainer = \"container:{name}.xcodeproj\">\n"
            "            </BuildableReference>\n"
            "         </BuildActionEntry>\n"
            "      </BuildActionEntries>\n"
            "   </BuildAction>\n"
            "   <TestAction buildConfiguration = \"Debug\" selectedDebuggerIdentifier = \"Xcode.DebuggerFoundation.Debugger.LLDB\" selectedLauncherIdentifier = \"Xcode.DebuggerFoundation.Launcher.LLDB\" shouldUseLaunchSchemeArgsEnv = \"YES\" shouldAutocreateTestPlan = \"YES\">\n"
            "      <Testables>\n"
            "         <TestableReference skipped = \"NO\">\n"
            "            <BuildableReference BuildableIdentifier = \"primary\" BlueprintIdentifier = \"{tests}\" BuildableName = \"{testName}.xctest\" BlueprintName = \"{testName}\" ReferencedContainer = \"container:{name}.xcodeproj\">\n"
            "            </BuildableReference>\n"
            "         </TestableReference>\n"
            "      </Testables>\n"
            "   </TestAction>\n"
            "   <LaunchAction buildConfiguration = \"Debug\" selectedDebuggerIdentifier = \"Xcode.DebuggerFoundation.Debugger.LLDB\" selectedLauncherIdentifier = \"Xcode.DebuggerFoundation.Launcher.LLDB\" launchStyle = \"0\" useCustomWorkingDirectory = \"NO\" ignoresPersistentStateOnLaunch = \"NO\" debugDocumentVersioning = \"YES\" debugServiceExtension = \"internal\" allowLocationSimulation = \"YES\">\n"
            "      <BuildableProductRunnable runnableDebuggingMode = \"0\">\n"
            "         <BuildableReference BuildableIdentifier = \"primary\" BlueprintIdentifier = \"{app}\" BuildableName = \"{name}.app\" BlueprintName = \"{name}\" ReferencedContainer = \"container:{name}.xcodeproj\">\n"
            "         </BuildableReference>\n"
            "      </BuildableProductRunnable>\n"
            "   </LaunchAction>\n"
            "   <ProfileAction buildConfiguration = \"Release\" shouldUseLaunchSchemeArgsEnv = \"YES\" savedToolIdentifier = \"\" useCustomWorkingDirectory = \"NO\" debugDocumentVersioning = \"YES\">\n"
            "      <BuildableProductRunnable runnableDebuggingMode = \"0\">\n"
            "         <BuildableReference BuildableIdentifier = \"primary\" BlueprintIdentifier = \"{app}\" BuildableName = \"{name}.app\" BlueprintName = \"{name}\" ReferencedContainer = \"container:{name}.xcodeproj\">\n"
            "         </BuildableReference>\n"
            "      </BuildableProductRunnable>\n"
            "   </ProfileAction>\n"
            "   <AnalyzeAction buildConfiguration = \"Debug\">\n"
            "   </AnalyzeAction>\n"
            "   <ArchiveAction buildConfiguration = \"Release\" revealArchiveInOrganizer = \"YES\">\n"
            "   </ArchiveAction>\n"
            "</Scheme>\n".format(
                app=ids["app_target"], tests=ids["test_target"],
                name=PROJECT_NAME, testName=TEST_TARGET_NAME,
                watchApp=ids["watch_target"], watchName=WATCH_TARGET_NAME,
            )
        )

    print("已生成 {0}/{1}.xcodeproj".format(os.path.basename(PROJECT_ROOT), PROJECT_NAME))
    print("  主 App 源码 {0} 个 / 测试源码 {1} 个 / 资源 {2} 个".format(
        len(app_sources), len(test_sources), len(app_resources)
    ))


if __name__ == "__main__":
    main()

# configured by qoder
