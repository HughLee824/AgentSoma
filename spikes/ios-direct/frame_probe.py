"""Bounded AXAuditDaemon geometry queries; no XCTest session or UI activation.

Requires pymobiledevice3==11.3.1 and an open RSD tunnel. Keep Calculator visible.
Attribute names are candidates, not advertised iOS geometry capabilities.
Value types come from Xcode 16's XDMDeviceFakeGeneric.sendFocusUpdate:
string=2, rect=4, size=8, point=16. Raw replies are retained without inference.
"""

import argparse
import asyncio
import importlib.metadata
import json
from datetime import datetime, timezone
from pathlib import Path

from pymobiledevice3.remote.remote_service_discovery import RemoteServiceDiscoveryService
from pymobiledevice3.services.accessibilityaudit import AccessibilityAudit, AXAuditElementAttribute_v1
from pymobiledevice3.services.dvt.instruments.dvt_provider import DvtProvider
from pymobiledevice3.services.dvt.instruments.screenshot import Screenshot

from probe import ax_wire, serializable


CANDIDATES = [
    ("Label", 2, False),
    ("Frame", 4, False),
    ("AXFrame", 4, False),
    ("Frame", 4, True),
    ("AXFrame", 4, True),
    ("ElementRect", 4, False),
    ("ElementFrame", 4, False),
    ("Position", 16, False),
    ("AXPosition", 16, False),
    ("Size", 8, False),
    ("AXSize", 8, False),
]


async def run(args):
    args.output.mkdir(parents=True, exist_ok=True)
    result = {
        "started_at": datetime.now(timezone.utc).isoformat(),
        "pymobiledevice3": importlib.metadata.version("pymobiledevice3"),
        "status": "running", "elements": [], "screenshots": [],
    }
    try:
        async with asyncio.timeout(50):
            async with RemoteServiceDiscoveryService((args.host, args.port)) as rsd:
                result["device"] = {
                    key: rsd.peer_info["Properties"].get(key)
                    for key in ("ProductType", "OSVersion", "BuildVersion")
                }
                async with DvtProvider(rsd) as dvt, Screenshot(dvt) as screenshots:
                    for phase in ("before", "after"):
                        path = args.output / f"{args.name}-{phase}.png"
                        timestamp = datetime.now(timezone.utc).isoformat()
                        path.write_bytes(await screenshots.get_screenshot())
                        result["screenshots"].append({"phase": phase, "started_at": timestamp, "file": path.name})
                        if phase == "after":
                            break
                        async with AccessibilityAudit(rsd) as ax:
                            result["capabilities"] = await ax.capabilities()
                            try:
                                async for focus in ax.iter_elements():
                                    item = {"focus": focus, "queries": []}
                                    result["elements"].append(item)
                                    label = next(
                                        attribute for section in focus._fields["InspectorSectionsValue_v1"]
                                        for attribute in section._fields["ElementAttributesValue_v1"]
                                        if attribute._fields["AttributeNameValue_v1"] == "Label"
                                    )
                                    for name, value_type, internal in CANDIDATES:
                                        fields = dict(label._fields, AttributeNameValue_v1=name,
                                                      ValueTypeValue_v1=value_type, IsInternal_v1=internal)
                                        query = {"attribute": fields}
                                        item["queries"].append(query)
                                        try:
                                            async with asyncio.timeout(3):
                                                query["reply"] = await ax._invoke(
                                                    "deviceElement:valueForAttribute:",
                                                    ax_wire(focus.element), ax_wire(AXAuditElementAttribute_v1(fields)),
                                                )
                                        except Exception as error:
                                            query["error"] = {"type": type(error).__name__, "message": str(error)}
                                    print(f"Queried element {len(result['elements'])}: {focus.caption}", flush=True)
                                    if len(result["elements"]) >= 80:
                                        result["limit_reached"] = True
                                        break
                            finally:
                                async with asyncio.timeout(3):
                                    await ax.set_app_monitoring_enabled(False)
                result["status"] = "observed"
    except Exception as error:
        result["status"] = "error"
        result["error"] = {"type": type(error).__name__, "message": str(error)}
    path = args.output / f"{args.name}.json"
    path.write_text(json.dumps(result, indent=2, default=serializable), encoding="utf-8")
    print(json.dumps({"status": result["status"], "elements": len(result["elements"]), "report": str(path)}))
    return 0 if result["status"] == "observed" else 1


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", required=True)
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--name", default="calculator-frame-verification")
    parser.add_argument("--output", type=Path, default=Path(__file__).parent / "evidence")
    raise SystemExit(asyncio.run(run(parser.parse_args())))
