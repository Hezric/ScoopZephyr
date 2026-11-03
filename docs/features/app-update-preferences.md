# App update preferences

Zephyr uses Scoop to update installed apps. Manifests disable built-in automatic update checks and self-updating through supported per-user controls when available, preserving other app settings.

- Agent Speed: installation sets `updates.autoCheck` to false in its roaming settings file. Close the running app before installing or updating it, then reopen it. Its manual update action remains available upstream.
- Cua Driver: installation sets `update_check_enabled` to false in its user configuration. This disables background checks; explicit `check-update` and `update --apply` remain available upstream.
- Hex: installation sets the current-user `Software\Policies\Anomaly\Hex\DisableUpdates` DWORD to 1 when permitted. Hex applies this policy to the current user's installations. When registry access is denied, installation warns and leaves in-app updates enabled; an administrator must configure the policy.

Check the upstream release's supported control when adding or updating a manifest. Document apps without a control rather than modifying their binaries. Run the root Pester suite via `bin/test.ps1`; the preference tests exercise existing, missing and invalid configuration.
