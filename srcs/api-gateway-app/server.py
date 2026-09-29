import os
from pathlib import Path

from dotenv import load_dotenv

# Load the project-root .env for local runs; variables already set (e.g. by PM2
# in the VMs) take precedence.
load_dotenv(Path(__file__).resolve().parents[2] / ".env")

from app import create_app  # noqa: E402

app = create_app()

if __name__ == "__main__":
    host = os.environ.get("GATEWAY_APP_HOST", "0.0.0.0")
    port = int(os.environ.get("GATEWAY_APP_PORT", 3000))
    app.run(host=host, port=port)
