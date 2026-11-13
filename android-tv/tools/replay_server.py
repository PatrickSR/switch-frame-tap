#!/usr/bin/env python3
"""Replay an SFTR recording over TCP/UDP to test the TV app without a Switch.

Only Python's standard library is required. This does not test USB or the real
Switch's network behaviour. Run on a PC in the same LAN as the TV.
"""
import argparse
import math
from pathlib import Path
import re
import socket
import struct
import threading
import time

HEADER = struct.Struct("<IHHIIIIII")
MAGIC = 0x52544653


def packets(path):
    with path.open("rb") as stream:
        while True:
            header = stream.read(32)
            if not header:
                return
            if len(header) != 32:
                raise ValueError("Truncated header")
            h = list(HEADER.unpack(header))
            if h[0] != MAGIC or h[1] != 2 or not 0 < h[6] <= 8 * 1024 * 1024:
                raise ValueError("Invalid SFTR v2 packet")
            data = stream.read(h[6])
            if len(data) != h[6]:
                raise ValueError("Truncated payload")
            if h[2] & 2 and any((nal[0] & 31) == 5 for nal in re.split(b"\x00\x00\x00?\x01", data) if nal):
                h[2] |= 4  # old IDR-only fixtures predate the explicit KEY bit
            yield h, data


def local_ip():
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
        try:
            probe.connect(("192.0.2.1", 9))  # selects a route; sends no packet
            return probe.getsockname()[0]
        except OSError:
            return "127.0.0.1"


def announce(stop, connected, ip, port=9950):
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        while not stop.wait(1):
            if not connected.is_set():
                try:
                    sock.sendto(f"SFTAP1 {ip} {port} Switch Frame Tap test".encode(), ("255.255.255.255", 9951))
                except OSError:
                    pass  # manual IP remains available if broadcasts are filtered


def viewer_messages(client):
    """Print what the viewer sends upstream (mirrors viewermsg::Next in the sysmodule)."""
    buf = bytearray()
    last_pad = None
    last_flags = 0
    pad_second = 0
    second_start = time.monotonic()
    while True:
        try:
            data = client.recv(4096)
        except socket.timeout:
            continue
        except OSError:
            return
        if not data:
            return
        buf.extend(data)
        while len(buf) >= 4:
            if buf[:3] != b"SFT":
                del buf[:1]
                continue
            kind = buf[3]
            if kind in b"KCDLUQ":
                print(f"Viewer: {buf[:4].decode()}", flush=True)
                del buf[:4]
                continue
            if kind == ord("I"):
                if len(buf) < 32:
                    break
                msg = bytes(buf[:32])
                del buf[:32]
                flags, buttons, lx, ly, rx, ry = struct.unpack("<IQiiii", msg[4:32])
                last_flags = flags
                pad_second += 1
                if msg != last_pad:
                    print(f"Viewer: SFTI flags={flags} buttons=0x{buttons:x} lx={lx} ly={ly} rx={rx} ry={ry}", flush=True)
                    last_pad = msg
                continue
            del buf[:1]
        now = time.monotonic()
        if now - second_start >= 1:
            if pad_second:
                print(f"Viewer: SFTI {pad_second}/s flags={last_flags}", flush=True)
            pad_second = 0
            second_start = now


def serve(args):
    # Validate the entire recording before accepting clients; do not load it into RAM.
    frames = sum(bool(h[2] & 2) for h, _ in packets(args.file))
    if not frames:
        raise ValueError("Recording contains no H.264 frames")
    stop, connected = threading.Event(), threading.Event()
    ip = local_ip()
    if not args.no_beacon:
        threading.Thread(target=announce, args=(stop, connected, ip, args.port), daemon=True).start()
    print(f"TV IP field: {ip} · TCP {args.port} · {frames} video frames · {args.fps:g} fps", flush=True)
    print("Ctrl+C stops the server. Optional --tone generates 440 Hz PCM sound.", flush=True)
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as server:
            server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            server.bind((args.bind, args.port))
            server.listen(1)
            while True:
                client, address = server.accept()
                connected.set()
                print(f"Connected: {address[0]}", flush=True)
                try:
                    with client:
                        client.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
                        client.settimeout(5)
                        if args.input:
                            threading.Thread(target=viewer_messages, args=(client,), daemon=True).start()
                        sequence = audio_sequence = sample = 0
                        next_frame = time.monotonic()
                        while True:
                            for header, data in packets(args.file):
                                if header[2] & 8:
                                    if not args.tone:
                                        if args.input and header[2] & 16:
                                            header[2] |= 128
                                        client.sendall(HEADER.pack(*header) + data)
                                    continue
                                if not header[2] & 2:
                                    continue
                                time.sleep(max(0, next_frame - time.monotonic()))
                                next_frame = max(next_frame + 1 / args.fps, time.monotonic())
                                if args.tone:
                                    samples = round(48000 / args.fps)
                                    pcm = bytearray()
                                    for n in range(samples):
                                        value = round(2500 * math.sin(2 * math.pi * 440 * (sample + n) / 48000))
                                        pcm.extend(struct.pack("<hh", value, value))
                                    sample += samples
                                    for offset in range(0, len(pcm), 65536):
                                        chunk = pcm[offset:offset + 65536]
                                        client.sendall(HEADER.pack(MAGIC, 2, 8, 48000, 2, 0, len(chunk), 0, audio_sequence) + chunk)
                                        audio_sequence = (audio_sequence + 1) & 0xffffffff
                                header[5] = 20000  # synthetic console age, not a measured latency
                                header[8] = sequence
                                if args.input:
                                    header[2] |= 128  # v0.7.20 consoles accepting viewer input set this
                                client.sendall(HEADER.pack(*header) + data)
                                sequence = (sequence + 1) & 0xffffffff
                            # Loop boundaries are a new session: force decoder recovery at an IDR.
                            sequence = 0
                except (OSError, BrokenPipeError) as e:
                    print(f"Disconnected: {e}", flush=True)
                finally:
                    connected.clear()
    except KeyboardInterrupt:
        pass
    finally:
        stop.set()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("file", type=Path)
    parser.add_argument("--fps", type=float, default=60)
    parser.add_argument("--tone", action="store_true")
    parser.add_argument("--bind", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=9950, help="TCP port (default: 9950)")
    parser.add_argument("--no-beacon", action="store_true", help="disable LAN announcements (local tests)")
    parser.add_argument("--input", action="store_true",
                        help="set flag 128 on video headers and log upstream viewer messages (SFTK/SFTI)")
    options = parser.parse_args()
    if not 1 <= options.fps <= 120:
        parser.error("--fps must be between 1 and 120")
    if not 1 <= options.port <= 65535:
        parser.error("--port must be between 1 and 65535")
    serve(options)
