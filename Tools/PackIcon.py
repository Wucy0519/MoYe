"""Package generated PNG representations in the standard ICNS container."""
import pathlib
import struct
import sys

root = pathlib.Path(sys.argv[1])
entries = [(b"icp4", "16x16"), (b"icp5", "32x32"), (b"icp6", "32x32@2x"),
           (b"ic07", "128x128"), (b"ic08", "256x256"), (b"ic09", "512x512"),
           (b"ic10", "512x512@2x"), (b"ic11", "16x16@2x"), (b"ic12", "32x32@2x"),
           (b"ic13", "128x128@2x"), (b"ic14", "256x256@2x")]
chunks = []
for kind, name in entries:
    data = (root / f"icon_{name}.png").read_bytes()
    chunks.append(kind + struct.pack(">I", len(data) + 8) + data)
body = b"".join(chunks)
pathlib.Path(sys.argv[2]).write_bytes(b"icns" + struct.pack(">I", len(body) + 8) + body)
