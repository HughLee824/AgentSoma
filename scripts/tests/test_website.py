import importlib.util
import re
import tempfile
import unittest
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[2]
WEBSITE = ROOT / "website"
spec = importlib.util.spec_from_file_location("build_website", WEBSITE / "build.py")
build_website = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build_website)


class Links(HTMLParser):
    def __init__(self):
        super().__init__()
        self.targets = []
        self.ids = []

    def handle_starttag(self, tag, attributes):
        attrs = dict(attributes)
        if "id" in attrs:
            self.ids.append(attrs["id"])
        for key in ("href", "src"):
            if key in attrs:
                self.targets.append(attrs[key])


class WebsiteTests(unittest.TestCase):
    def test_rebuild_removes_stale_output_and_rejects_source_target(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = build_website.build(Path(temporary) / "dist")
            (output / "stale.log").write_text("not public")
            build_website.build(output)
            self.assertFalse((output / "stale.log").exists())
        for target in (WEBSITE, ROOT):
            with self.assertRaises(ValueError):
                build_website.build(target)

    def test_public_build_has_no_local_or_hosting_material(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = build_website.build(Path(temporary) / "dist")
            files = [path.relative_to(output) for path in output.rglob("*") if path.is_file()]
            self.assertTrue((output / "index.html").is_file())
            self.assertTrue((output / "404.html").is_file())
            self.assertFalse(any(path.parts[0].startswith(".") for path in files))
            self.assertFalse(any(path.suffix in (".py", ".json", ".mobileprovision", ".log") for path in files))
            for name in ("index.html", "styles.css", "tokens.css", "site.js"):
                self.assertEqual((WEBSITE / name).read_bytes(), (output / name).read_bytes())
                text = (output / name).read_text()
                self.assertNotIn("/Users/", text)
                self.assertNotIn(".local/", text)

    def test_assets_anchors_and_repository_links_resolve(self):
        page = Links()
        page.feed((WEBSITE / "index.html").read_text())
        self.assertEqual(len(page.ids), len(set(page.ids)), "Duplicate page anchors")
        for target in page.targets:
            url = urlsplit(target)
            if not url.scheme:
                if not url.path:
                    self.assertIn(url.fragment, page.ids)
                elif url.path != "./":
                    self.assertTrue((WEBSITE / url.path).is_file(), target)
                continue
            self.assertEqual(url.scheme, "https", target)
            repo_prefix = "/HughLee824/AgentSoma/blob/main/"
            if url.netloc == "github.com" and url.path.startswith(repo_prefix):
                path = ROOT / unquote(url.path.removeprefix(repo_prefix))
                self.assertTrue(path.is_file(), target)
                if url.fragment and path.suffix == ".md":
                    headings = re.findall(r"^#+ (.+)$", path.read_text(), re.MULTILINE)
                    slugs = [re.sub(r"[^\w\- ]", "", h.lower()).replace(" ", "-") for h in headings]
                    self.assertIn(unquote(url.fragment), slugs, target)
        for name in ("styles.css", "tokens.css"):
            for path in re.findall(r"url\(['\"]?([^)'\"]+)", (WEBSITE / name).read_text()):
                self.assertTrue((WEBSITE / path).is_file(), path)


if __name__ == "__main__":
    unittest.main()
