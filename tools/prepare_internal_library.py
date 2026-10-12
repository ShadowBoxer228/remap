#!/usr/bin/env python3
"""Provision a DEBUG app's data container without putting credentials in source/binaries.

Install the internal app first, resolve its exact data container, then pass --container.
The app moves the credential into Keychain and removes this file on its next launch.
This script never launches a simulator, prints credentials, or changes user maps.
"""
import argparse
import os
from pathlib import Path
import plistlib
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--container", type=Path, required=True)
    parser.add_argument("--token-file", type=Path, default=Path("build/remap-tester-token.txt"))
    parser.add_argument("--endpoint", default="https://remap-coach.vercel.app")
    args = parser.parse_args()
    from urllib.parse import urlparse
    url = urlparse(args.endpoint)
    if url.scheme != "https" or not url.hostname or url.username or url.password or url.query or url.fragment:
        parser.error("The endpoint must be a plain HTTPS URL.")
    container = args.container.resolve(strict=True)
    if not (container / "Library").is_dir():
        parser.error("Expected an existing, installed app DATA container with Library/.")
    token = args.token_file.read_text().strip()
    if len(token) < 32:
        parser.error("The internal access token is missing or too short.")
    directory = container / "Library/Application Support/ReMap"
    directory.mkdir(parents=True, exist_ok=True)
    data = plistlib.dumps({"endpoint": args.endpoint, "token": token})
    fd, temporary = tempfile.mkstemp(dir=directory, prefix=".connection-")
    try:
        with os.fdopen(fd, "wb") as output:
            output.write(data)
        os.chmod(temporary, 0o600)
        os.replace(temporary, directory / "InternalConnection.plist")
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    print("Internal connection provisioned; credentials omitted. Launch the DEBUG app to complete setup.")


if __name__ == "__main__":
    main()
