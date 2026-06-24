# state/token_state.py

from dataclasses import dataclass


@dataclass
class TokenState:
    access_token: str | None = None


token_state = TokenState()
# middleware/auth_middleware.py

import httpx

from state.token_state import token_state
from config.settings import settings


async def auth_middleware(ctx, call_next):

    if not token_state.access_token:

        async with httpx.AsyncClient() as client:

            response = await client.get(
                f"{settings.BASE_URL}/v1/get/token"
            )

            response.raise_for_status()

            body = response.json()

            token_state.access_token = body["access_token"]

    return await call_next(ctx)

from fastmcp import FastMCP

from middleware.auth_middleware import auth_middleware

mcp = FastMCP("Demo")

mcp.add_middleware(auth_middleware)
# utils/api_client.py

import httpx

from state.token_state import token_state


class APIClient:

    def __init__(self):
        self.client = httpx.AsyncClient(timeout=30)

    async def get(self, url, **kwargs):

        headers = kwargs.pop("headers", {})

        headers["Authorization"] = f"Bearer {token_state.access_token}"

        response = await self.client.get(
            url,
            headers=headers,
            **kwargs,
        )

        response.raise_for_status()

        return response.json()

    async def post(self, url, **kwargs):

        headers = kwargs.pop("headers", {})

        headers["Authorization"] = f"Bearer {token_state.access_token}"

        response = await self.client.post(
            url,
            headers=headers,
            **kwargs,
        )

        response.raise_for_status()

        return response.json()


api_client = APIClient()
