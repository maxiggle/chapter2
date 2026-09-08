import json
from functools import lru_cache
from pathlib import Path
from typing import Any

ABI_DIRECTORY = Path(__file__).resolve().parent


@lru_cache(maxsize=16)
def load_abi(contract_name: str) -> list[dict[str, Any]]:
    """Loads and caches a JSON ABI file by contract name."""
    clean_name = contract_name.removesuffix(".json")
    abi_path = ABI_DIRECTORY / f"{clean_name}.json"
    if not abi_path.exists():
        raise FileNotFoundError(f"ABI file not found for contract: {clean_name} at {abi_path}")

    with open(abi_path, "r", encoding="utf-8") as f:
        return json.load(f)


__all__ = ["load_abi"]
