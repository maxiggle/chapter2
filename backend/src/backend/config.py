import os
from pathlib import Path
from dotenv import load_dotenv

# Load .env from backend directory or fallback to contracts/.env / root .env
backend_dir = Path(__file__).resolve().parent.parent.parent
root_dir = backend_dir.parent

load_dotenv(backend_dir / ".env")
load_dotenv(root_dir / "contracts" / ".env")
load_dotenv(root_dir / ".env")


class Settings:
    """Backend application configuration settings."""

    # Network RPCs
    OP_SEPOLIA_RPC_URL: str = os.getenv("OP_SEPOLIA_RPC_URL", "https://sepolia.optimism.io")
    BASE_SEPOLIA_RPC_URL: str = os.getenv("BASE_SEPOLIA_RPC_URL", "https://sepolia.base.org")

    # Chain IDs
    SOURCE_CHAIN_ID: int = int(os.getenv("SOURCE_CHAIN_ID", "11155420"))  # OP Sepolia
    TARGET_CHAIN_ID: int = int(os.getenv("TARGET_CHAIN_ID", "84532"))     # Base Sepolia

    # Relayer Credentials
    RELAYER_PRIVATE_KEY: str = os.getenv("RELAYER_PRIVATE_KEY", os.getenv("PRIVATE_KEY", ""))

    # Known Contract Deployments
    FACTORY_ADDRESS: str = os.getenv("FACTORY_ADDRESS", "0x048819533668c605A90E9C98285ac6dCC3619d7f")
    SOURCE_LOCK_ADDRESS: str = os.getenv("SOURCE_LOCK_ADDRESS", "0xB493918a15F413949103f4912d0a545a515a3688")
    SOURCE_TOKEN_ADDRESS: str = os.getenv("SOURCE_TOKEN_ADDRESS", "0xFf3Ec4008Dfde538900aeea4e1b057C12De0D07b")
    TARGET_TOKEN_ADDRESS: str = os.getenv("TARGET_TOKEN_ADDRESS", "0xDb92614412003E94d18B71E5FBC332ae47158A50")
    CLAIM_CONTRACT_ADDRESS: str = os.getenv("CLAIM_CONTRACT_ADDRESS", "0x3e9035b88684544EFEFCF47A4E392ECb2b142083")

    # Database
    DATABASE_URL: str = os.getenv("DATABASE_URL", f"sqlite:///{backend_dir}/chapter2.db")


settings = Settings()
