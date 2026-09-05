"""Bounded observations for the no-WDA iPhone feasibility spike.

Requires pymobiledevice3==11.3.1 and an already-open RSD tunnel.
Raw screen/AX evidence stays in the git-ignored output directory.
"""

import argparse
import asyncio
import hashlib
import importlib.metadata
import json
import time
from datetime import datetime, timezone
from pathlib import Path

from PIL import Image
from pymobiledevice3.remote.core_device.device_info import DeviceInfoService
from pymobiledevice3.remote.core_device.screen_capture_service import ScreenCaptureService
from pymobiledevice3.remote.remote_service_discovery import RemoteServiceDiscoveryService
from pymobiledevice3.services.accessibilityaudit import AccessibilityAudit
from pymobiledevice3.services.dvt.instruments.dvt_provider import DvtProvider
from pymobiledevice3.services.dvt.instruments.screenshot import Screenshot


def serializable(value):
    if isinstance(value, bytes):
        return {"hex": value.hex()}
    if hasattr(value, "_fields"):
        return value._fields
    raise TypeError(type(value).__name__)


def ax_wire(value):
    """Mirror the typed objects and passthrough wrappers in AX audit messages."""
    if hasattr(value, "_fields"):
        return {"ObjectType": type(value).__name__, "Value": ax_wire(value._fields)}
    if isinstance(value, dict):
        value = {key: ax_wire(item) for key, item in value.items()}
    elif isinstance(value, list):
        value = [ax_wire(item) for item in value]
    return {"ObjectType": "passthrough", "Value": value}


async def probe(args):
    result = {
        "mode": args.mode,
        "started_at": datetime.now(timezone.utc).isoformat(),
        "pymobiledevice3": importlib.metadata.version("pymobiledevice3"),
        "status": "running",
    }
    started = time.monotonic()
    args.output.mkdir(parents=True, exist_ok=True)
    try:
        async with asyncio.timeout(35):
            async with RemoteServiceDiscoveryService((args.host, args.port)) as rsd:
                result["connect_ms"] = round((time.monotonic() - started) * 1000)
                properties = rsd.peer_info["Properties"]
                result["device"] = {
                    key: properties.get(key)
                    for key in ("ProductType", "OSVersion", "BuildVersion")
                }
                if args.mode == "inventory":
                    result["services"] = {
                        name: sorted(rsd.get_service_features(name))
                        for name in rsd.peer_info["Services"]
                        if "coredevice" in name.lower() or "axaudit" in name.lower()
                    }
                    async with DeviceInfoService(rsd) as service:
                        result["display"] = await service.get_display_info()
                    try:
                        async with DeviceInfoService(rsd) as service:
                            result["lock_state"] = await service.get_lockstate()
                    except Exception as error:
                        result["lock_state_error"] = str(error)
                elif args.mode in {"screenshot", "dvt-screenshot"}:
                    capture_started = time.monotonic()
                    if args.mode == "screenshot":
                        async with ScreenCaptureService(rsd) as service:
                            response = await service.capture_screenshot()
                        image_bytes = response["image"]
                    else:
                        async with DvtProvider(rsd) as provider, Screenshot(provider) as service:
                            image_bytes = await service.get_screenshot()
                    result["capture_ms"] = round((time.monotonic() - capture_started) * 1000)
                    path = args.output / f"{args.name}.png"
                    path.write_bytes(image_bytes)
                    with Image.open(path) as image:
                        result["pixels"] = list(image.size)
                        result["all_black"] = image.convert("RGB").getbbox() is None
                    result["image"] = path.name
                    result["sha256"] = hashlib.sha256(image_bytes).hexdigest()
                elif args.mode in {"ax", "ax-details"}:
                    async with AccessibilityAudit(rsd) as service:
                        result["capabilities"] = await service.capabilities()
                        result["elements"] = []
                        try:
                            async with asyncio.timeout(20):
                                async for element in service.iter_elements():
                                    result["elements"].append(element)
                                    if args.mode == "ax-details":
                                        result["attribute_values"] = {}
                                        for section in element._fields["InspectorSectionsValue_v1"]:
                                            for attribute in section._fields["ElementAttributesValue_v1"]:
                                                name = attribute._fields["AttributeNameValue_v1"]
                                                if name not in {"Label", "Identifier", "_AXHierarchyElementsAttribute"}:
                                                    continue
                                                try:
                                                    async with asyncio.timeout(3):
                                                        result["attribute_values"][name] = await service._invoke(
                                                            "deviceElement:valueForAttribute:",
                                                            ax_wire(element.element), ax_wire(attribute),
                                                        )
                                                except Exception as error:
                                                    result["attribute_values"][name] = {
                                                        "error": type(error).__name__, "message": str(error)
                                                    }
                                        break
                                    if len(result["elements"]) >= 80:
                                        result["limit_reached"] = True
                                        break
                        finally:
                            await service.set_app_monitoring_enabled(False)
                    result["element_count"] = len(result["elements"])
                result["status"] = "ok"
    except Exception as error:
        result["status"] = "error"
        result["error"] = {"type": type(error).__name__, "message": str(error)}
    if "elements" in result:
        result["element_count"] = len(result["elements"])
    result["total_ms"] = round((time.monotonic() - started) * 1000)
    report_path = args.output / f"{args.name}.json"
    report_path.write_text(json.dumps(result, indent=2, default=serializable), encoding="utf-8")
    summary = {key: value for key, value in result.items() if key not in {"elements", "services"}}
    summary["report"] = str(report_path)
    if "services" in result:
        summary["services"] = list(result["services"])
    print(json.dumps(summary, indent=2, default=serializable))
    return 0 if result["status"] == "ok" else 1


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("inventory", "screenshot", "dvt-screenshot", "ax", "ax-details"))
    parser.add_argument("--host", required=True)
    parser.add_argument("--port", required=True, type=int)
    parser.add_argument("--name", required=True)
    parser.add_argument("--output", type=Path, default=Path(__file__).parent / "evidence")
    raise SystemExit(asyncio.run(probe(parser.parse_args())))
