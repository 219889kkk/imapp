#!/usr/bin/env python3
"""Patch project.pbxproj for CI manual signing (no catastrophic regex)."""
import os
import pathlib
import sys


def patch_block(lines: list[str], start: int, end: int, team: str, profile: str) -> None:
    keys = {
        "CODE_SIGN_STYLE": "Manual",
        "DEVELOPMENT_TEAM": team,
        "PROVISIONING_PROFILE_SPECIFIER": profile,
    }
    present = {k: False for k in keys}
    insert_at = start + 1

    for i in range(start + 1, end):
        line = lines[i]
        for key, value in keys.items():
            token = f"{key} = "
            if token in line:
                if key == "PROVISIONING_PROFILE_SPECIFIER":
                    lines[i] = f'\t\t\t\tPROVISIONING_PROFILE_SPECIFIER = "{profile}";\n'
                else:
                    lines[i] = f"\t\t\t\t{key} = {value};\n"
                present[key] = True

    missing = [k for k, ok in present.items() if not ok]
    if not missing:
        return

    inserts = []
    if "CODE_SIGN_STYLE" in missing:
        inserts.append("\t\t\t\tCODE_SIGN_STYLE = Manual;\n")
    if "DEVELOPMENT_TEAM" in missing:
        inserts.append(f"\t\t\t\tDEVELOPMENT_TEAM = {team};\n")
    if "PROVISIONING_PROFILE_SPECIFIER" in missing:
        inserts.append(f'\t\t\t\tPROVISIONING_PROFILE_SPECIFIER = "{profile}";\n')
    lines[insert_at:insert_at] = inserts


def patch_bundle(path: pathlib.Path, bundle: str, profile: str, team: str) -> int:
    lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
    needle = f"PRODUCT_BUNDLE_IDENTIFIER = {bundle};"
    count = 0
    i = 0
    while i < len(lines):
        if needle not in lines[i]:
            i += 1
            continue
        # Walk back to buildSettings = {
        j = i
        while j >= 0 and "buildSettings = {" not in lines[j]:
            j -= 1
        if j < 0:
            raise SystemExit(f"buildSettings not found for {bundle} near line {i + 1}")
        start = j
        depth = 0
        k = start
        while k < len(lines):
            depth += lines[k].count("{")
            depth -= lines[k].count("}")
            if depth == 0 and k > start:
                patch_block(lines, start, k, team, profile)
                count += 1
                i = k + 1
                break
            k += 1
        else:
            raise SystemExit(f"Unclosed buildSettings for {bundle}")
    if count == 0:
        raise SystemExit(f"No buildSettings found for {bundle}")
    path.write_text("".join(lines), encoding="utf-8")
    return count


def main() -> None:
    team = os.environ.get("TEAM_ID", "").strip()
    app_profile = os.environ.get("APP_NAME", "").strip()
    nse_profile = os.environ.get("NSE_NAME", "").strip()
    pbx = pathlib.Path("ios/Runner.xcodeproj/project.pbxproj")

    if not team or not app_profile or not nse_profile:
        print("Missing TEAM_ID / APP_NAME / NSE_NAME", file=sys.stderr)
        sys.exit(1)

    n_app = patch_bundle(pbx, "top.hangxun.app", app_profile, team)
    n_nse = patch_bundle(pbx, "top.hangxun.app.NotificationService", nse_profile, team)
    print(f"Patched {n_app} Runner + {n_nse} NotificationService buildSettings blocks")


if __name__ == "__main__":
    main()
