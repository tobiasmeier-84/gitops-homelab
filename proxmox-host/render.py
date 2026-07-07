#!/usr/bin/env python3
"""
Renders answer.toml.j2 once per node listed in nodes.yaml, merging in
the SOPS-decrypted root password hash. Output goes to rendered/<hostname>.toml
— gitignored, never committed, since it embeds the (hashed) root credential.

Usage:
    pip install jinja2 pyyaml
    sops -d secrets/root-password.enc.yaml > /tmp/root-password.plain.yaml
    python3 render.py /tmp/root-password.plain.yaml
    rm /tmp/root-password.plain.yaml
"""
import sys
import yaml
from pathlib import Path
from jinja2 import Template

def main():
    if len(sys.argv) != 2:
        print("Usage: render.py <decrypted-root-password-yaml-path>")
        sys.exit(1)

    base = Path(__file__).parent
    template = Template((base / "answer.toml.j2").read_text())
    nodes = yaml.safe_load((base / "nodes.yaml").read_text())["nodes"]
    secret = yaml.safe_load(Path(sys.argv[1]).read_text())
    root_password_hash = secret["root_password_hash"]

    out_dir = base / "rendered"
    out_dir.mkdir(exist_ok=True)

    for node in nodes:
        if node["mgmt_nic_name"].startswith("REPLACE_ME") or node["boot_disk_1"].startswith("REPLACE_ME"):
            print(f"Skipping {node['hostname']}: nodes.yaml still has REPLACE_ME placeholders.")
            continue
        rendered = template.render(**node, root_password_hash=root_password_hash)
        out_path = out_dir / f"{node['hostname']}.toml"
        out_path.write_text(rendered)
        print(f"Wrote {out_path}")

if __name__ == "__main__":
    main()