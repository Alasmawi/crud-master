from pathlib import Path

from dotenv import load_dotenv

# Load the project-root .env for local runs; variables already set (e.g. by PM2
# in the VMs) take precedence.
load_dotenv(Path(__file__).resolve().parents[2] / ".env")

from app.consumer import run  # noqa: E402

if __name__ == "__main__":
    run()
