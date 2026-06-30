import logging
import time
from typing import Any

import httpx
from fastmcp.server.middleware import Middleware, MiddlewareContext

from config.settings import settings

logger = logging.getLogger(__name__)

_TOKEN_REFRESH_SKEW_SECONDS = 30


class _TokenCache:
    """Process-wide cache for the local client-credentials token."""

    def __init__(self) -> None:
        self._access_token: str | None = None
        self._expires_at: float = 0.0
        self._lock_in_progress = False

    def is_valid(self) -> bool:
        return bool(self._access_token) and time.time() < (
            self._expires_at - _TOKEN_REFRESH_SKEW_SECONDS
        )

    def set(self, access_token: str, expires_in: int) -> None:
        self._access_token = access_token
        self._expires_at = time.time() + expires_in

    @property
    def access_token(self) -> str | None:
        return self._access_token


_token_cache = _TokenCache()


async def _fetch_external_token() -> str:
    if _token_cache.is_valid():
        return _token_cache.access_token  # type: ignore[return-value]

    if not settings.AUTH_TOKEN_URL:
        raise RuntimeError("AUTH_TOKEN_URL is not configured for local environment")

    async with httpx.AsyncClient(timeout=10.0) as client:
        response = await client.post(
            settings.AUTH_TOKEN_URL,
            data={
                "grant_type": "client_credentials",
                "client_id": settings.CLIENT_ID,
                "client_secret": settings.CLIENT_SECRET,
            },
            headers={"Content-Type": "application/x-www-form-urlencoded"},
        )
        response.raise_for_status()
        body = response.json()

    access_token = body.get("access_token")
    expires_in = body.get("expires_in", 3600)
    if not access_token:
        raise RuntimeError("Token endpoint did not return an access_token")

    _token_cache.set(access_token, expires_in)
    logger.info("Fetched new external API token (expires_in=%s)", expires_in)
    return access_token


class LocalAuthMiddleware(Middleware):
    """
    Only mounted when ENVIRONMENT == 'local'.
    Fetches/refreshes a client-credentials token and puts it on context
    state under 'access_token', mirroring what get_access_token() would
    give you in a deployed/OAuth-protected environment.
    """

    async def on_call_tool(self, context: MiddlewareContext, call_next: Any) -> Any:
        token = await _fetch_external_token()
        context.fastmcp_context.set_state("access_token", token)
        return await call_next(context)


auth_middleware = LocalAuthMiddleware()


from fastmcp.server.dependencies import get_access_token, get_context

from config.settings import settings


async def get_outbound_access_token() -> str:
    """
    Returns the bearer token to use when calling the external API,
    regardless of whether we're in local mode (client-credentials token
    fetched by middleware) or deployed mode (the caller's verified bearer
    token, passed through via OAuthProxy/JWTVerifier).
    """
    if settings.ENVIRONMENT.lower() == "local":
        ctx = get_context()
        token = ctx.get_state("access_token")
        if not token:
            raise RuntimeError("No access_token found in context state (local mode)")
        return token

    # Deployed: token was already validated by JWTVerifier; this pulls
    # the raw bearer token attached to the current request.
    access_token = get_access_token()
    if access_token is None:
        raise RuntimeError("No authenticated access token on this request")
    return access_token.token



import logging

from fastmcp import FastMCP
from fastmcp.server.auth import OAuthProxy
from fastmcp.server.auth.providers.jwt import JWTVerifier

from config.logging import setup_logging
from config.settings import settings
from src.mcp_server.tools import register_all
from src.middleware.authentication import auth_middleware

logger = logging.getLogger(__name__)


def build_auth() -> OAuthProxy:
    """Built only for non-local environments. Validates incoming bearer
    tokens against the IdP's JWKS and proxies the OAuth flow upstream."""
    token_verifier = JWTVerifier(
        jwks_uri=settings.JWKS_URI,
        issuer=settings.REALM_BASE_URL,
        audience=settings.AUDIENCE,
    )

    return OAuthProxy(
        upstream_authorization_endpoint=settings.AUTHORIZATION_ENDPOINT,
        upstream_token_endpoint=settings.TOKEN_ENDPOINT,
        upstream_client_id=settings.CLIENT_ID,
        upstream_client_secret=settings.CLIENT_SECRET,
        token_verifier=token_verifier,
        base_url=settings.BASE_URL,
        service_documentation_url=settings.SERVICE_DOCUMENTATION_URL,
    )


def create_app() -> FastMCP:
    is_local = settings.ENVIRONMENT.lower() == "local"

    app = FastMCP(
        name=settings.PROJECT_NAME,
        version=settings.PROJECT_VERSION,
        auth=None if is_local else build_auth(),
    )

    if is_local:
        # Local: no IdP in front of us, so we fetch our own token
        # (client-credentials) and stamp it onto context state.
        app.add_middleware(auth_middleware)

    register_all(app)
    return app


setup_logging()
app = create_app()

if __name__ == "__main__":
    app.run(transport="http", host="0.0.0.0", port=settings.PORT)
