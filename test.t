from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_prefix="MCP_", extra="ignore")

    # Keycloak / OIDC realm base
    realm_base_url: str  # e.g. https://foothill-neutron-outright.ngrok-free.dev/realms/mcp-demo

    # OAuth client
    client_id: str
    client_secret: str
    audience: str = "mcp-client"

    # This server's own public URL (used for OAuth callback construction)
    base_url: str
    service_documentation_url: str | None = None

    @property
    def jwks_uri(self) -> str:
        return f"{self.realm_base_url}/protocol/openid-connect/certs"

    @property
    def authorization_endpoint(self) -> str:
        return f"{self.realm_base_url}/protocol/openid-connect/auth"

    @property
    def token_endpoint(self) -> str:
        return f"{self.realm_base_url}/protocol/openid-connect/token"


settings = Settings()
MCP_REALM_BASE_URL=https://foothill-neutron-outright.ngrok-free.dev/realms/mcp-demo
MCP_CLIENT_ID=mcp-client
MCP_CLIENT_SECRET=8rqzL8Ps4TyDkaezvjWJq1R5RzOvL9v3
MCP_AUDIENCE=mcp-client
MCP_BASE_URL=https://common-eels-refuse.loca.lt
MCP_SERVICE_DOCUMENTATION_URL=https://common-eels-refuse.loca.lt/docs
from fastmcp.server.auth import OAuthProxy
from fastmcp.server.auth.providers.jwt import JWTVerifier

from config import settings


def build_auth() -> OAuthProxy:
    token_verifier = JWTVerifier(
        jwks_uri=settings.jwks_uri,
        issuer=settings.realm_base_url,
        audience=settings.audience,
    )

    return OAuthProxy(
        upstream_authorization_endpoint=settings.authorization_endpoint,
        upstream_token_endpoint=settings.token_endpoint,
        upstream_client_id=settings.client_id,
        upstream_client_secret=settings.client_secret,
        token_verifier=token_verifier,
        base_url=settings.base_url,
        service_documentation_url=settings.service_documentation_url,
    )

from starlette.middleware import Middleware
from starlette.middleware.cors import CORSMiddleware

from fastmcp import FastMCP

import tools
from auth import build_auth
from middleware import TokenStateMiddleware


def register_all(mcp: FastMCP) -> None:
    tools.register(mcp)


def create_app():
    mcp = FastMCP(auth=build_auth())
    register_all(mcp)

    middleware = [
        Middleware(
            CORSMiddleware,
            allow_origins=["*"],
            allow_methods=["*"],
            allow_headers=["*"],
        ),
        Middleware(TokenStateMiddleware),
    ]

    return mcp.http_app(middleware=middleware)


app = create_app()

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8888)
