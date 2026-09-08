# Runner App Icon

`AppIcon.appiconset/AppIcon.png` is the 1024 × 1024 opaque, white-background
Soma symbol from the 2026-09-08 logo kit (`soma-github-icon.png`). Its original
proportions and clear space are preserved. Xcode generates the iPhone and iPad
sizes from this image.

Build with the shared `AgentSomaRunner` scheme. UI-test asset catalogs normally
belong to the `.xctest` bundle; the scheme's `install-app-icon.sh` post-action
copies the compiled icons and icon metadata to the generated Runner app and
sets its Home Screen name to `AgentSoma`, matching release packages. It
refreshes its signature when signed. This also applies to CLI source builds
and release packaging, which use the same scheme.
