#!/usr/bin/env python3
"""Write ExportOptions-ci.plist for GitHub Actions signed IPA export."""
import os
import pathlib
import sys

method = os.environ.get("METHOD", "ad-hoc")
team = os.environ.get("TEAM_ID", "")
app = os.environ.get("APP_NAME", "")
nse = os.environ.get("NSE_NAME", "")

if not team or not app or not nse:
    print("Missing METHOD/TEAM_ID/APP_NAME/NSE_NAME", file=sys.stderr)
    sys.exit(1)

content = f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>{method}</string>
	<key>teamID</key>
	<string>{team}</string>
	<key>signingStyle</key>
	<string>manual</string>
	<key>compileBitcode</key>
	<false/>
	<key>stripSwiftSymbols</key>
	<true/>
	<key>provisioningProfiles</key>
	<dict>
		<key>top.hangxun.app</key>
		<string>{app}</string>
		<key>top.hangxun.app.NotificationService</key>
		<string>{nse}</string>
	</dict>
</dict>
</plist>
"""
out = pathlib.Path("ios/ExportOptions-ci.plist")
out.write_text(content, encoding="utf-8")
print(content)
