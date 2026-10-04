#!/usr/bin/env python3
"""Serve a disposable release on loopback with real size and SHA-256 metadata."""
import functools
import hashlib
import http.server
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(root))
server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
base = f"http://127.0.0.1:{server.server_port}"
archive = root / "Meno.zip"
release = {
    "tag_name": "v0.0.2", "html_url": base + "/latest.json",
    "body": "Disposable update test", "draft": False, "prerelease": False,
    "assets": [{"name": archive.name, "browser_download_url": base + "/Meno.zip",
                "size": archive.stat().st_size,
                "digest": "sha256:" + hashlib.sha256(archive.read_bytes()).hexdigest()}],
}
(root / "latest.json").write_text(json.dumps(release))
(root / "endpoint").write_text(base + "/latest.json")
server.serve_forever()
