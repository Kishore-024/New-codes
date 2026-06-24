"""
AA-DTS-ISQ AI Integration — MCP Server Entry Point.

Starts a FastMCP server with Streamable-HTTP transport so the
MCP Inspector (and any MCP client) can connect at:
    http://<host>:8000/mcp
"""

from fastmcp import FastMCP

from config.logging import setup_logging
from config.settings import settings


def create_app() -> FastMCP:
    """
    Factory that wires every tool module into the main FastMCP instance.

    Tool modules expose a ``register(mcp)`` callable; calling them here
    avoids the circular-import problem that arises when tool files try
    to import the app-level ``mcp`` object at module load time.
    """
    app = FastMCP(name=settings.PROJECT_NAME, version=settings.PROJECT_VERSION)

    # Configure structured logging before anything else logs.
    setup_logging()

    # ------------------------------------------------------------------ #
    # Register tool groups — add new ``register(app)`` calls here as the  #
    # project grows.                                                       #
    # ------------------------------------------------------------------ #
    from src.mcp_server.tools import register_all  # noqa: PLC0415

    register_all(app)

    return app


# Module-level singleton consumed by Uvicorn / gunicorn in production.
app = create_app()


if __name__ == "__main__":
    # Local development: python app.py
    # The MCP Inspector should connect to http://localhost:8000/mcp
    app.run(
        transport="http",
        host="0.0.0.0",  # noqa: S104  (intentional for containerised run)
        port=settings.PORT,
    )
"""
Health-check tool.

WHY no module-level ``mcp = FastMCP()`` here
---------------------------------------------
Creating a separate FastMCP() in each tool file registers tools on a
*different* server object — they are never visible to the main app.
Instead, this module exposes ``register(mcp)`` so the caller (tools/__init__.py)
can wire the tool into whichever FastMCP instance it chooses.  This also
makes the tool trivially testable: pass a throw-away FastMCP() in unit tests.
"""

import logging

from fastmcp import FastMCP

logger = logging.getLogger(__name__)


def register(mcp: FastMCP) -> None:
    """Attach all health-check tools to *mcp*."""

    @mcp.tool(
        name="health_check",
        description="Check if the service is alive and running.",
        tags={"system", "health"},
        meta={"version": "1.0", "owner": "platform-team"},
    )
    async def health_check() -> str:
        """
        Liveness probe.

        Returns a plain-text string that confirms the MCP server process
        is up and the event loop is responsive.  Useful as the first tool
        to call from the MCP Inspector to verify connectivity.
        """
        logger.info("health_check tool invoked")
        return "I am Alive"
"""
Tool registration hub.

Each tool module in this package exposes a ``register(mcp: FastMCP)``
function.  Add a new import + call here whenever a new tool module is
created — that's the only change needed to wire it into the server.
"""

from fastmcp import FastMCP

from . import health_check  # noqa: F401  (import triggers module-level side-effects if any)


def register_all(mcp: FastMCP) -> None:
    """Register every tool group with the given FastMCP instance."""
    health_check.register(mcp)
    # Add more: some_other_tool.register(mcp)
# =============================================================================
# docker-compose.yaml
#
# Services
# --------
# mcp-server    — the FastMCP Python server (Streamable HTTP on port 8000)
# mcp-inspector — the official MCP Inspector web UI
#
# Usage
# -----
# docker compose up --build
#
# Then open  http://localhost:6274  in your browser.
# In the Inspector UI:
#   Transport : Streamable HTTP
#   URL       : http://localhost:8000/mcp    ← forward-declared by VITE_SERVER_URL
#
# Why two ports on mcp-inspector?
#   6274 → Inspector web UI  (you open this in the browser)
#   6277 → Inspector proxy   (browser sends MCP requests here; proxy forwards
#                             them to the MCP server on the Docker network)
# =============================================================================

version: "3.9"

services:

  # --------------------------------------------------------------------------
  # MCP Server (FastMCP / Python)
  # --------------------------------------------------------------------------
  mcp-server:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: mcp-server
    restart: unless-stopped
    env_file:
      - .env                         # ignored if file is absent
    environment:
      LOG_FORMAT: json               # structured logs in containers
      LOG_LEVEL: INFO
      HOST: "0.0.0.0"
      PORT: "8000"
    ports:
      - "8000:8000"
    healthcheck:
      # FastMCP exposes a simple GET /health endpoint when transport=http
      test: ["CMD-SHELL", "wget -qO- http://localhost:8000/health || exit 1"]
      interval: 15s
      timeout: 5s
      retries: 5
      start_period: 10s

  # --------------------------------------------------------------------------
  # MCP Inspector (official @modelcontextprotocol/inspector)
  # --------------------------------------------------------------------------
  mcp-inspector:
    image: node:20-alpine
    container_name: mcp-inspector
    working_dir: /app
    # Install once into /app/node_modules so subsequent restarts are fast.
    command: >
      sh -c "
        npm install --save-exact @modelcontextprotocol/inspector &&
        npx @modelcontextprotocol/inspector
      "
    ports:
      - "6274:6274"    # Inspector web UI
      - "6277:6277"    # Inspector proxy (forwards browser calls to MCP server)
    stdin_open: true
    tty: true
    environment:
      # Pre-fill the server URL in the Inspector UI.
      # The proxy (port 6277) is what the browser actually POSTs to;
      # it in turn forwards to the target URL below over the Docker network.
      MCP_INSPECTOR_PROXY_PORT: "6277"
      MCP_INSPECTOR_PORT: "6274"
      # When using the Inspector UI, enter this URL manually:
      #   http://localhost:8000/mcp
      # (the browser can reach it because port 8000 is forwarded above)
    depends_on:
      mcp-server:
        condition: service_healthy
