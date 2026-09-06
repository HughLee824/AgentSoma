#!/usr/bin/env python3
"""Maintainer-only: build a relocatable, unsigned release candidate. Never publishes."""

import argparse
import hashlib
import json
import platform
import plistlib
import re
import shutil
import subprocess
import tarfile
import tempfile
from pathlib import Path


def run(arguments, *, cwd, log=None):
    if log:
        with log.open("wb") as output:
            result = subprocess.run(arguments, cwd=cwd, stdout=output, stderr=subprocess.STDOUT)
        if result.returncode:
            raise RuntimeError(f"{arguments[0]} failed; see {log}")
        return None
    return subprocess.check_output(arguments, cwd=cwd, text=True).strip()


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_plist(path, value):
    path.write_bytes(plistlib.dumps(value, sort_keys=True))


def package_runner(products, destination):
    manifests = list(products.glob("*.xctestrun"))
    if len(manifests) != 1:
        raise RuntimeError("Expected exactly one generated Runner .xctestrun")
    generated = plistlib.loads(manifests[0].read_bytes())
    target = generated["AgentSomaTests"]
    host = target["TestHostPath"]
    if not host.startswith("__TESTROOT__/"):
        raise RuntimeError("Unexpected generated Runner host path")
    source = (products / host.removeprefix("__TESTROOT__/")).resolve()
    if not source.is_relative_to(products.resolve()):
        raise RuntimeError("Runner host escapes build products")
    app = destination / "AgentSomaRunner.app"
    shutil.copytree(source, app, symlinks=True)
    # iOS 17+ uses XCTest from the device. Do not redistribute Apple's test frameworks.
    shutil.rmtree(app / "Frameworks", ignore_errors=True)
    for path in list(app.rglob("*.dSYM")):
        shutil.rmtree(path)
    for path in list(app.rglob("*.mobileprovision")):
        path.unlink()
    for path in list(app.rglob("_CodeSignature")):
        shutil.rmtree(path)
    test = app / "PlugIns/AgentSomaTests.xctest"
    for bundle, executable in [(test, "AgentSomaTests"), (app, "AgentSomaTests-Runner")]:
        if subprocess.run(["/usr/bin/codesign", "-d", str(bundle)], capture_output=True).returncode == 0:
            run(["/usr/bin/codesign", "--remove-signature", str(bundle / executable)], cwd=destination)
        run(["/usr/bin/strip", "-S", str(bundle / executable)], cwd=destination)
    info = plistlib.loads((app / "Info.plist").read_bytes())
    info["CFBundleDisplayName"] = "AgentSoma Runner"
    write_plist(app / "Info.plist", info)
    # Generate a closed, portable test manifest instead of shipping local build settings.
    write_plist(destination / "Runner.xctestrun", {
        "__xctestrun_metadata__": {"FormatVersion": 1},
        "AgentSomaTests": {
            "BlueprintName": "AgentSomaTests", "ProductModuleName": "AgentSomaTests",
            "IsUITestBundle": True, "IsXCTRunnerHostedTestBundle": True,
            "UseUITargetAppProvidedByTests": True, "TestTimeoutsEnabled": False,
            "TestHostBundleIdentifier": info["CFBundleIdentifier"],
            "TestHostPath": "__TESTROOT__/AgentSomaRunner.app",
            "TestBundlePath": "__TESTHOST__/PlugIns/AgentSomaTests.xctest",
            "DependentProductPaths": ["__TESTROOT__/AgentSomaRunner.app",
                                      "__TESTROOT__/AgentSomaRunner.app/PlugIns/AgentSomaTests.xctest"],
            "SystemAttachmentLifetime": "deleteOnSuccess", "UserAttachmentLifetime": "deleteOnSuccess",
        },
    })
    files = {}
    for path in sorted(destination.rglob("*")):
        if path.is_symlink():
            raise RuntimeError(f"Unexpected symbolic link in Runner payload: {path.name}")
        if path.is_file():
            files[path.relative_to(destination).as_posix()] = digest(path)
    return files, info["MinimumOSVersion"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True, help="Explicit release version, e.g. 0.1.0-dev.1")
    parser.add_argument("--output-dir", type=Path, help="Default: .build/releases")
    args = parser.parse_args()
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?", args.version):
        parser.error("Use a semantic version without a leading v")
    architecture = platform.machine()
    if platform.system() != "Darwin" or architecture not in ("arm64", "x86_64"):
        parser.error("Build on macOS using an arm64 or x86_64 host")
    root = Path(__file__).resolve().parents[1]
    output = (args.output_dir or root / ".build/releases").resolve()
    output.mkdir(parents=True, exist_ok=True)
    name = f"agentsoma-{args.version}-macos-{architecture}"
    destination = output / name
    archive = output / f"{name}.tar.gz"
    if destination.exists() or archive.exists():
        parser.error("Output already exists; use another version or output directory")
    log = output / f"{name}-build.log"
    run(["swift", "build", "-c", "release"], cwd=root, log=log)
    bin_path = Path(run(["swift", "build", "-c", "release", "--show-bin-path"], cwd=root))
    # Isolated builds keep development Runner products and active sessions untouched.
    with tempfile.TemporaryDirectory(prefix="release-runner-", dir=root / ".build") as temporary:
        runner_log = output / f"{name}-runner-build.log"
        run(["xcrun", "xcodebuild", "build-for-testing", "-project", "Runner/AgentSomaRunner.xcodeproj",
             "-scheme", "AgentSomaRunner", "-configuration", "Debug", "-sdk", "iphoneos",
             "-destination", "generic/platform=iOS", "-derivedDataPath", temporary,
             "CODE_SIGNING_ALLOWED=NO", "IPHONEOS_DEPLOYMENT_TARGET=17.0",
             "SWIFT_OPTIMIZATION_LEVEL=-O", "SWIFT_ACTIVE_COMPILATION_CONDITIONS=",
             "DEBUG_INFORMATION_FORMAT=dwarf-with-dsym", "SWIFT_SERIALIZE_DEBUGGING_OPTIONS=NO"],
            cwd=root, log=runner_log)
        (destination / "bin").mkdir(parents=True)
        shutil.copy2(bin_path / "agentsoma", destination / "bin/agentsoma")
        run(["/usr/bin/strip", "-S", str(destination / "bin/agentsoma")], cwd=root)
        # Ad-hoc signing keeps the local arm64 binary executable; this is not Developer ID signing.
        run(["/usr/bin/codesign", "--force", "--sign", "-", "--timestamp=none", str(destination / "bin/agentsoma")], cwd=root)
        runner = destination / "libexec/agentsoma/runner"
        runner.mkdir(parents=True)
        files, minimum_os = package_runner(Path(temporary) / "Build/Products", runner)
        for path in [destination / "bin/agentsoma", *(runner / name for name in files)]:
            if str(root).encode() in path.read_bytes():
                raise RuntimeError(f"Local source path leaked into release payload: {path.relative_to(destination)}")
        runner_version = hashlib.sha256(json.dumps(files, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
        (runner / "manifest.json").write_text(json.dumps({
            "formatVersion": 1, "releaseVersion": args.version, "cliSHA256": digest(destination / "bin/agentsoma"), "runnerVersion": runner_version,
            "minimumOSVersion": minimum_os, "files": files,
        }, indent=2, sort_keys=True) + "\n")
    shutil.copy2(root / "docs/install.md", destination / "README.md")
    for source in root.glob("LICENSE*"):
        if source.is_file():
            shutil.copy2(source, destination / source.name)
    with tarfile.open(archive, "w:gz") as tar:
        tar.add(destination, arcname=name)
    checksum = output / f"{archive.name}.sha256"
    checksum.write_text(f"{digest(archive)}  {archive.name}\n")
    print(json.dumps({"directory": str(destination), "archive": str(archive), "checksum": str(checksum),
                      "runnerVersion": runner_version, "macSigning": "not performed", "published": False}))


if __name__ == "__main__":
    main()
