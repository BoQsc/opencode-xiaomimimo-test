import argparse
import getpass
import json
import shutil
import sys
from datetime import datetime
from pathlib import Path
from urllib import request, error


HOME = Path.home()
OPENCODE_DIR = HOME / ".config" / "opencode"
CONFIG_FILE = OPENCODE_DIR / "opencode.json"
STATE_FILE = OPENCODE_DIR / "mimo-test-state.json"
BACKUP_DIR = OPENCODE_DIR / "backups"

TOKEN_BASE_URLS = {
    "cn": "https://token-plan-cn.xiaomimimo.com/v1",
    "sgp": "https://token-plan-sgp.xiaomimimo.com/v1",
    "ams": "https://token-plan-ams.xiaomimimo.com/v1",
}

PAYGO_BASE_URL = "https://api.xiaomimimo.com/v1"


def fail(text):
    print("ERROR:", text)
    sys.exit(1)


def mkdirs():
    OPENCODE_DIR.mkdir(parents=True, exist_ok=True)
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)


def read_text(path):
    try:
        return path.read_text(encoding="utf-8-sig")
    except FileNotFoundError:
        return ""
    except Exception as e:
        fail(f"Could not read {path}: {e}")


def write_text(path, text):
    try:
        path.write_text(text, encoding="utf-8")
    except Exception as e:
        fail(f"Could not write {path}: {e}")


def delete_file(path):
    try:
        if path.exists():
            path.unlink()
    except Exception as e:
        fail(f"Could not delete {path}: {e}")


def load_state():
    if not STATE_FILE.exists():
        return None

    try:
        return json.loads(read_text(STATE_FILE))
    except Exception as e:
        fail(f"Could not parse state file {STATE_FILE}: {e}")


def save_state(state):
    write_text(STATE_FILE, json.dumps(state, indent=2) + "\n")


def build_config(base_url, api_key, model):
    return {
        "$schema": "https://opencode.ai/config.json",
        "provider": {
            "mimo": {
                "npm": "@ai-sdk/openai-compatible",
                "name": "MiMo",
                "options": {
                    "baseURL": base_url,
                    "apiKey": api_key,
                },
                "models": {
                    model: {
                        "name": model,
                        "limit": {
                            "context": 1048576,
                            "output": 131072,
                        },
                        "modalities": {
                            "input": ["text"],
                            "output": ["text"],
                        },
                    }
                },
            }
        },
    }


def apply(args):
    mkdirs()

    state = load_state()
    if state and state.get("active") and not args.force:
        fail("MiMo test config already appears active. Run restore first, or use --force.")

    config_existed = CONFIG_FILE.exists()
    backup_file = None

    if config_existed:
        stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        backup_file = BACKUP_DIR / f"opencode.json.before-mimo-{stamp}.bak"
        try:
            shutil.copy2(CONFIG_FILE, backup_file)
        except Exception as e:
            fail(f"Could not backup existing config: {e}")

    if args.provider == "paygo":
        base_url = PAYGO_BASE_URL
    else:
        base_url = TOKEN_BASE_URLS[args.region]

    if args.base_url:
        base_url = args.base_url.rstrip("/")

    api_key = args.key.strip() if args.key else ""
    if not api_key:
        api_key = getpass.getpass("Paste MiMo API key/token: ").strip()

    if not api_key:
        fail("No API key/token provided.")

    if api_key.startswith("Bearer "):
        fail("Paste only the raw key/token, not 'Bearer ...'.")

    config = build_config(
        base_url=base_url,
        api_key=api_key,
        model=args.model,
    )

    write_text(CONFIG_FILE, json.dumps(config, indent=2) + "\n")

    save_state({
        "active": True,
        "config_existed": config_existed,
        "backup_file": str(backup_file) if backup_file else None,
        "config_file": str(CONFIG_FILE),
        "base_url": base_url,
        "model": args.model,
        "provider": args.provider,
        "region": args.region,
    })

    print()
    print("OpenCode MiMo config applied.")
    print(f"Config: {CONFIG_FILE}")
    if backup_file:
        print(f"Backup: {backup_file}")
    else:
        print("Backup: none, because no previous opencode.json existed.")

    print()
    print("Now open OpenCode app.")
    print("Select model:")
    print(f"  mimo/{args.model}")
    print()
    print("Restore later with:")
    print("  py opencode_mimo_save_restore.py restore")


def restore(args):
    mkdirs()

    state = load_state()
    if not state:
        if args.force:
            print("No state file found. Nothing to restore.")
            return
        fail("No saved MiMo test state found. Use --force only if you are sure.")

    if state.get("config_existed"):
        backup_file = state.get("backup_file")
        if not backup_file:
            fail("State says config existed, but backup path is missing.")

        backup_path = Path(backup_file)
        if not backup_path.exists():
            fail(f"Backup file is missing: {backup_path}")

        try:
            shutil.copy2(backup_path, CONFIG_FILE)
        except Exception as e:
            fail(f"Could not restore backup: {e}")

        print(f"Restored original config from: {backup_path}")
    else:
        delete_file(CONFIG_FILE)
        print("Removed generated opencode.json because no original config existed.")

    delete_file(STATE_FILE)

    print("Deleted MiMo test state file.")
    print("Restore complete.")


def status(args):
    state = load_state()

    print(f"OpenCode dir: {OPENCODE_DIR}")
    print(f"Config:       {CONFIG_FILE}")
    print(f"State:        {STATE_FILE}")
    print()

    if state and state.get("active"):
        print("Status: MiMo test state exists.")
        print(f"Model:    mimo/{state.get('model')}")
        print(f"Base URL: {state.get('base_url')}")
        print(f"Backup:   {state.get('backup_file')}")
    else:
        print("Status: no active MiMo test state found.")

    print()
    if CONFIG_FILE.exists():
        print("opencode.json exists.")
    else:
        print("No opencode.json exists.")


def chatcheck(args):
    if not CONFIG_FILE.exists():
        fail("No opencode.json exists. Run apply first.")

    try:
        config = json.loads(read_text(CONFIG_FILE))
    except Exception as e:
        fail(f"Could not parse opencode.json: {e}")

    provider = config.get("provider", {}).get("mimo", {})
    options = provider.get("options", {})
    base_url = str(options.get("baseURL", "")).rstrip("/")
    api_key = str(options.get("apiKey", ""))

    models = provider.get("models", {})
    if args.model:
        model = args.model
    elif models:
        model = next(iter(models.keys()))
    else:
        fail("No model found in opencode.json.")

    if not base_url:
        fail("No provider.mimo.options.baseURL found in opencode.json.")

    if not api_key:
        fail("No provider.mimo.options.apiKey found in opencode.json.")

    url = base_url + "/chat/completions"

    body = {
        "model": model,
        "messages": [
            {
                "role": "user",
                "content": "Say hello in one short sentence.",
            }
        ],
        "stream": False,
    }

    data = json.dumps(body).encode("utf-8")

    req = request.Request(
        url,
        data=data,
        method="POST",
        headers={
            "Authorization": "Bearer " + api_key,
            "Content-Type": "application/json",
        },
    )

    print(f"Testing: {url}")
    print(f"Model:   {model}")

    try:
        with request.urlopen(req, timeout=60) as res:
            text = res.read().decode("utf-8", errors="replace")
            print("HTTP " + str(res.status))
            print(text[:4000])
    except error.HTTPError as e:
        text = e.read().decode("utf-8", errors="replace")
        print("HTTP " + str(e.code))
        print(text[:4000])
        sys.exit(1)
    except Exception as e:
        fail(f"Request failed: {e}")


def main():
    parser = argparse.ArgumentParser(
        description="Temporarily configure OpenCode for Xiaomi MiMo, then restore it."
    )

    sub = parser.add_subparsers(dest="command", required=True)

    p_apply = sub.add_parser("apply")
    p_apply.add_argument("--provider", choices=["token", "paygo"], default="token")
    p_apply.add_argument("--region", choices=["cn", "sgp", "ams"], default="ams")
    p_apply.add_argument("--base-url", default="")
    p_apply.add_argument("--model", default="mimo-v2.5-pro")
    p_apply.add_argument("--key", default="", help="Avoid this; terminal history can expose it.")
    p_apply.add_argument("--force", action="store_true")
    p_apply.set_defaults(func=apply)

    p_restore = sub.add_parser("restore")
    p_restore.add_argument("--force", action="store_true")
    p_restore.set_defaults(func=restore)

    p_status = sub.add_parser("status")
    p_status.set_defaults(func=status)

    p_chatcheck = sub.add_parser("chatcheck")
    p_chatcheck.add_argument("--model", default="")
    p_chatcheck.set_defaults(func=chatcheck)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()