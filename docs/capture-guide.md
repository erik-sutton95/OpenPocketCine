# Captures stay local

Packet captures of camera traffic stay in gitignored `captures/`. Never commit
pcaps, SoftAP passwords, BLE HCI snoop logs, or unofficial LUT dumps.

Protocol facts that are confirmed on hardware belong in
[`protocol-notes.md`](protocol-notes.md). Implementation lives in
`Sources/OpenPocketViewCore/`.

Offline helpers on your machine (they read gitignored captures; they are not a
how-to for intercepting another app):

```bash
python3 tools/duml_parse.py --selftest
python3 tools/duml_parse.py captures/your-take.pcap
python3 tools/extract_liveview.py captures/your-take.pcap
python3 tools/mimo_settings.py captures/your-take.pcapng
```

If a capture might contain a Wi-Fi password, leave it in `captures/` and do not
paste payloads into issues, discussions, or pull requests.
