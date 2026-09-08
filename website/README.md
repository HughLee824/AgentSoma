# AgentSoma website

Static HTML, CSS, and JavaScript. No framework or package installation is required.

```sh
python3 website/build.py
python3 -m http.server 4173 --bind 127.0.0.1 --directory website
```

Open `http://127.0.0.1:4173`. Source preview uses `website/`; deployment uses the explicit public output in `website/dist/`. The build does not copy repository files, local device evidence, or hosting credentials into public output.

Content follows [the first-task guide](../docs/first-task.md). Keep client commands and prerequisites synchronized with that guide and [plugin installation](../docs/plugins.md). Use real, reviewed device captures for demos and describe any editing in `assets/README.md`.

The `.openai/hosting.json` manifest identifies the Sites project and static output. Sites holds deployment credentials; no credentials belong in this repository. See [website release instructions](../docs/public-access-release.md) for validation and publishing.
