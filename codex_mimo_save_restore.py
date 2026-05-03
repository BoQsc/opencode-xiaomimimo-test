import argparse
import getpass
import json
import os
import shutil
import sys
from pathlib import Path
from datetime import datetime


CODEX_DIR = Path.home() / ".codex"
CONFIG_FILE = CODEX_DIR / "config.toml"
KEY_FILE = CODEX_DIR / "mimo.key"
STATE_FILE = CODEX_DIR / "mimo-test-state.json"
BACKUP_DIR = CODEX_DIR / "backups"

MARKER = "# Managed by codex_mimo_save_restore.py"


def notice(text):
    print(text)


def fail(text):
    print("ERROR:", text)
    sys.exit(1)


def toml_string(text):
    # JSON string escaping is valid for TOML basic strings for this use.
    return json.dumps(str(text))


def powershell_single_quote(text):
    # PowerShell single-quoted string escape: ' becomes ''
    return "'" + str(text).replace("'", "''") + "'"


def mkdirs():
    CODEX_DIR.mkdir(parents=True, exist_ok=True)
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)


def read_text(path):
    try:
        return path.read_text(encoding="utf-8")
    except FileNotFoundError:
        return ""
    except Exception as e:
        fail(f"Could not read {path}: {e}")


def write_text(path, text):
    try:
        path.write_text(text, encoding="utf-8")
    except Exception as e:
        fail(f"Could not write {path}: {e}")


def load_state():
    if not STATE_FILE.exists():
        return None

    try:
        return json.loads(STATE_FILE.read_text(encoding="utf-8"))
    except Exception as e:
        fail(f"Could not read state file {STATE_FILE}: {e}")


def save_state(state):
    write_text(STATE_FILE, json.dumps(state, indent=2))


def delete_file(path):
    try:
        if path.exists():
            path.unlink()
    except Exception as e:
        fail(f"Could not delete {path}: {e}")


def make_config(base_url, model, wire_api):
    key_path = str(KEY_FILE)

    ps_command = (
        "Get-Content -Raw -LiteralPath "
        + powershell_single_quote(key_path)
    )

    return f"""{MARKER}

model_provider = {toml_string("xiaomimimo")}
model = {toml_string(model)}

approval_policy = {toml_string("on-request")}
sandbox_mode = {toml_string("workspace-write")}
windows_wsl_setup_acknowledged = true

[model_providers.xiaomimimo]
name = {toml_string("Xiaomi MiMo")}
base_url = {toml_string(base_url)}
wire_api = {toml_string(wire_api)}

[model_providers.xiaomimimo.auth]
command = {toml_string("powershell.exe")}
args = [{toml_string("-NoProfile")}, {toml_string("-Command")}, {toml_string(ps_command)}]
timeout_ms = 5000
refresh_interval_ms = 0
"""


def apply_config(args):
    mkdirs()

    state = load_state()
    if state and state.get("active") and not args.force:
        fail("MiMo test config already appears active. Use restore first, or use --force.")

    old_config_existed = CONFIG_FILE.exists()

    backup_file = None
    if old_config_existed:
        stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        backup_file = BACKUP_DIR / f"config.toml.before-mimo-{stamp}.bak"
        try:
            shutil.copy2(CONFIG_FILE, backup_file)
        except Exception as e:
            fail(f"Could not backup existing config: {e}")

    if args.provider == "token":
        base_url = "https://token-plan-cn.xiaomimimo.com/v1"
    else:
        base_url = "https://api.xiaomimimo.com/v1"

    if args.base_url:
        base_url = args.base_url

    key = args.key
    if not key:
        key = getpass.getpass("Paste MiMo API key/token: ").strip()

    if not key:
        fail("No key provided.")

    write_text(KEY_FILE, key.strip() + "\n")

    try:
        os.chmod(KEY_FILE, 0o600)
    except Exception:
        pass

    config = make_config(
        base_url=base_url,
        model=args.model,
        wire_api=args.wire_api,
    )

    write_text(CONFIG_FILE, config)

    save_state({
        "active": True,
        "config_existed": old_config_existed,
        "backup_file": str(backup_file) if backup_file else None,
        "config_file": str(CONFIG_FILE),
        "key_file": str(KEY_FILE),
        "base_url": base_url,
        "model": args.model,
        "wire_api": args.wire_api,
    })

    notice("")
    notice("MiMo Codex test config applied.")
    notice(f"Config: {CONFIG_FILE}")
    notice(f"Key file: {KEY_FILE}")

    if backup_file:
        notice(f"Backup: {backup_file}")
    else:
        notice("Backup: none, because no previous config.toml existed.")

    notice("")
    notice("Now open Codex app and test the project.")
    notice("When finished, run:")
    notice("  py codex_mimo_save_restore.py restore")


def restore_config(args):
    mkdirs()

    state = load_state()

    if not state:
        if not args.force:
            fail("No saved MiMo test state found. Use --force to remove generated files anyway.")

        current = read_text(CONFIG_FILE)
        if MARKER in current:
            delete_file(CONFIG_FILE)

        delete_file(KEY_FILE)
        delete_file(STATE_FILE)
        notice("Forced cleanup finished.")
        return

    config_existed = bool(state.get("config_existed"))
    backup_file = state.get("backup_file")

    current = read_text(CONFIG_FILE)
    if MARKER not in current and not args.force:
        fail(
            "Current config.toml does not look like the generated MiMo test config. "
            "Use --force only if you really want to restore/cleanup."
        )

    if config_existed:
        if not backup_file:
            fail("State says config existed, but backup file path is missing.")

        backup_path = Path(backup_file)
        if not backup_path.exists():
            fail(f"Backup file is missing: {backup_path}")

        try:
            shutil.copy2(backup_path, CONFIG_FILE)
        except Exception as e:
            fail(f"Could not restore backup: {e}")

        notice(f"Restored original config from: {backup_path}")
    else:
        delete_file(CONFIG_FILE)
        notice("Removed generated config.toml because no original config existed.")

    delete_file(KEY_FILE)
    delete_file(STATE_FILE)

    notice("Deleted MiMo key file and state file.")
    notice("Restore complete.")


def status(args):
    state = load_state()

    notice(f"Codex dir:   {CODEX_DIR}")
    notice(f"Config file: {CONFIG_FILE}")
    notice(f"Key file:    {KEY_FILE}")
    notice(f"State file:  {STATE_FILE}")
    notice("")

    if state and state.get("active"):
        notice("Status: MiMo test state exists.")
        notice(f"Model:   {state.get('model')}")
        notice(f"Base:    {state.get('base_url')}")
        notice(f"Wire:    {state.get('wire_api')}")
        notice(f"Backup:  {state.get('backup_file')}")
    else:
        notice("Status: no active MiMo test state found.")

    if CONFIG_FILE.exists():
        current = read_text(CONFIG_FILE)
        if MARKER in current:
            notice("Current config.toml appears to be generated by this script.")
        else:
            notice("Current config.toml exists, but is not generated by this script.")
    else:
        notice("No config.toml exists.")


def main():
    parser = argparse.ArgumentParser(
        description="Temporarily replace Codex config with Xiaomi MiMo config, then restore it."
    )

    sub = parser.add_subparsers(dest="command", required=True)

    apply_p = sub.add_parser("apply", help="Backup current Codex config and apply MiMo test config.")
    apply_p.add_argument(
        "--provider",
        choices=["token", "paygo"],
        default="token",
        help="Use token plan or pay-as-you-go base URL.",
    )
    apply_p.add_argument(
        "--model",
        default="mimo-v2-flash",
        help="Model name to put in Codex config.",
    )
    apply_p.add_argument(
        "--wire-api",
        default="responses",
        choices=["responses", "chat"],
        help="Use responses for current Codex. Try chat only with old Codex builds.",
    )
    apply_p.add_argument(
        "--base-url",
        default="",
        help="Override base URL manually.",
    )
    apply_p.add_argument(
        "--key",
        default="",
        help="API key/token. Avoid this if possible because it can appear in terminal history.",
    )
    apply_p.add_argument(
        "--force",
        action="store_true",
        help="Overwrite existing active test state.",
    )
    apply_p.set_defaults(func=apply_config)

    restore_p = sub.add_parser("restore", help="Restore previous Codex config and delete MiMo key file.")
    restore_p.add_argument(
        "--force",
        action="store_true",
        help="Force cleanup even if state/marker checks fail.",
    )
    restore_p.set_defaults(func=restore_config)

    status_p = sub.add_parser("status", help="Show current save/restore status.")
    status_p.set_defaults(func=status)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()