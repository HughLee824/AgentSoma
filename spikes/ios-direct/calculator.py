"""One bounded AX activation probe, restricted to Calculator's digit 2.

Launches Apple's Calculator, reads its live AX elements, requests activation,
and saves before/after screenshots. A sent request is not proof of a UI change.
"""

import argparse
import asyncio
import json
import time
from pathlib import Path

from PIL import Image, ImageChops
from pymobiledevice3.remote.core_device.app_service import AppServiceService
from pymobiledevice3.remote.remote_service_discovery import RemoteServiceDiscoveryService
from pymobiledevice3.services.accessibilityaudit import AccessibilityAudit
from pymobiledevice3.services.dvt.instruments.dvt_provider import DvtProvider
from pymobiledevice3.services.dvt.instruments.screenshot import Screenshot

from probe import ax_wire, serializable


async def run(args):
    output = Path(__file__).parent / "evidence"
    output.mkdir(exist_ok=True)
    result = {"status": "running", "bundle_id": "com.apple.calculator", "target": "Two"}
    started = time.monotonic()
    try:
        async with asyncio.timeout(30):
            async with RemoteServiceDiscoveryService((args.host, args.port)) as rsd:
                async with AppServiceService(rsd) as app:
                    result["launch"] = await app.launch_application("com.apple.calculator", kill_existing=False)
                async with DvtProvider(rsd) as dvt, Screenshot(dvt) as screenshots:
                    (output / "ax-press-before.png").write_bytes(await screenshots.get_screenshot())
                    async with AccessibilityAudit(rsd) as ax:
                        try:
                            async for focus in ax.iter_elements():
                                if focus.element._fields.get("AccessibilityIdentifier_v1") != "Two":
                                    continue
                                result["element"] = focus
                                action = next(
                                    attribute
                                    for section in focus._fields["InspectorSectionsValue_v1"]
                                    for attribute in section._fields["ElementAttributesValue_v1"]
                                    if attribute._fields.get("AttributeNameValue_v1") == "AXAction-2010"
                                )
                                await ax._invoke(
                                    "deviceElement:performAction:withValue:",
                                    ax_wire(focus.element), ax_wire(action), 0,
                                    expects_reply=False,
                                )
                                result["request_sent"] = True
                                break
                            else:
                                raise RuntimeError("Calculator digit Two was not found")
                        finally:
                            await ax.set_app_monitoring_enabled(False)
                    await asyncio.sleep(0.5)
                    (output / "ax-press-after.png").write_bytes(await screenshots.get_screenshot())
                with Image.open(output / "ax-press-before.png") as before, Image.open(output / "ax-press-after.png") as after:
                    result["images_identical"] = ImageChops.difference(
                        before.convert("RGB"), after.convert("RGB")
                    ).getbbox() is None
                result["activation_verified"] = False
                result["assessment"] = (
                    "No visible effect: before and after RGB pixels are identical."
                    if result["images_identical"]
                    else "Pixels changed; inspect the screenshots to verify the intended effect."
                )
                result["status"] = "observed"
    except Exception as error:
        result["status"] = "error"
        result["error"] = {"type": type(error).__name__, "message": str(error)}
    result["total_ms"] = round((time.monotonic() - started) * 1000)
    (output / "calculator-activation.json").write_text(json.dumps(result, indent=2, default=serializable))
    print(json.dumps({key: value for key, value in result.items() if key != "element"}, indent=2, default=serializable))
    return 0 if result["status"] == "observed" else 1


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", required=True)
    parser.add_argument("--port", required=True, type=int)
    raise SystemExit(asyncio.run(run(parser.parse_args())))
