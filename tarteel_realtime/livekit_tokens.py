from __future__ import annotations

import datetime as dt
import os
import uuid
from collections.abc import Mapping
from dataclasses import dataclass
from typing import Protocol


DEFAULT_LIVEKIT_URL = "ws://127.0.0.1:7880"
DEFAULT_LIVEKIT_API_KEY = "devkey"
DEFAULT_LIVEKIT_API_SECRET = "secret"
DEFAULT_LIVEKIT_ROOM = "tarteel-local-recitation"
LIVEKIT_CREDENTIAL_ENV_NAMES = (
    "LIVEKIT_URL",
    "LIVEKIT_API_KEY",
    "LIVEKIT_API_SECRET",
)


class LiveKitDependencyMissing(ImportError):
    pass


class LiveKitConfigurationError(ValueError):
    pass


@dataclass(frozen=True)
class LiveKitSettings:
    url: str = DEFAULT_LIVEKIT_URL
    api_key: str = DEFAULT_LIVEKIT_API_KEY
    api_secret: str = DEFAULT_LIVEKIT_API_SECRET
    room_name: str = DEFAULT_LIVEKIT_ROOM
    token_ttl_minutes: int = 60


@dataclass(frozen=True)
class LiveKitTokenRequest:
    settings: LiveKitSettings
    identity: str
    role: str
    can_publish: bool
    can_subscribe: bool
    can_publish_data: bool


class LiveKitTokenBuilder(Protocol):
    def build(self, request: LiveKitTokenRequest) -> str:
        """Return a signed LiveKit join token."""


def livekit_settings_from_env(env: Mapping[str, str] | None = None) -> LiveKitSettings:
    values = os.environ if env is None else env
    cloud_values = {
        name: _non_empty_env_value(values, name)
        for name in LIVEKIT_CREDENTIAL_ENV_NAMES
    }
    provided_cloud_names = {name for name, value in cloud_values.items() if value is not None}
    if provided_cloud_names and provided_cloud_names != set(LIVEKIT_CREDENTIAL_ENV_NAMES):
        missing = ", ".join(
            name for name in LIVEKIT_CREDENTIAL_ENV_NAMES if name not in provided_cloud_names
        )
        raise LiveKitConfigurationError(
            "LiveKit Cloud configuration requires LIVEKIT_URL, "
            f"LIVEKIT_API_KEY, and LIVEKIT_API_SECRET together. Missing: {missing}"
        )

    return LiveKitSettings(
        url=cloud_values["LIVEKIT_URL"] or DEFAULT_LIVEKIT_URL,
        api_key=cloud_values["LIVEKIT_API_KEY"] or DEFAULT_LIVEKIT_API_KEY,
        api_secret=cloud_values["LIVEKIT_API_SECRET"] or DEFAULT_LIVEKIT_API_SECRET,
        room_name=_non_empty_env_value(values, "TARTEEL_LIVEKIT_ROOM") or DEFAULT_LIVEKIT_ROOM,
        token_ttl_minutes=int(
            _non_empty_env_value(values, "TARTEEL_LIVEKIT_TOKEN_TTL_MINUTES") or "60"
        ),
    )


def livekit_token_response(
    *,
    settings: LiveKitSettings,
    identity: str | None,
    role: str,
    token_builder: LiveKitTokenBuilder | None = None,
) -> dict[str, str]:
    token_identity = _token_identity(identity)

    request = _token_request_for_role(
        settings=settings,
        identity=token_identity,
        role=role,
    )
    builder = token_builder or LiveKitApiTokenBuilder()
    return {
        "url": settings.url,
        "room": settings.room_name,
        "identity": token_identity,
        "session_id": token_identity,
        "role": role,
        "token": builder.build(request),
    }


class LiveKitApiTokenBuilder:
    def build(self, request: LiveKitTokenRequest) -> str:
        try:
            from livekit import api
        except ModuleNotFoundError as exc:
            raise LiveKitDependencyMissing(
                "Install livekit-api to generate LiveKit access tokens."
            ) from exc

        return (
            api.AccessToken(
                request.settings.api_key,
                request.settings.api_secret,
            )
            .with_identity(request.identity)
            .with_name(request.identity)
            .with_ttl(dt.timedelta(minutes=request.settings.token_ttl_minutes))
            .with_grants(
                api.VideoGrants(
                    room_join=True,
                    room=request.settings.room_name,
                    can_publish=request.can_publish,
                    can_subscribe=request.can_subscribe,
                    can_publish_data=request.can_publish_data,
                )
            )
            .to_jwt()
        )


def _token_request_for_role(
    *,
    settings: LiveKitSettings,
    identity: str,
    role: str,
) -> LiveKitTokenRequest:
    match role:
        case "client":
            can_publish = True
            can_subscribe = True
        case "worker":
            can_publish = False
            can_subscribe = True
        case _:
            raise ValueError("role must be client or worker")

    return LiveKitTokenRequest(
        settings=settings,
        identity=identity,
        role=role,
        can_publish=can_publish,
        can_subscribe=can_subscribe,
        can_publish_data=True,
    )


def _non_empty_env_value(values: Mapping[str, str], name: str) -> str | None:
    value = values.get(name)
    if value is None:
        return None
    stripped = value.strip()
    return stripped or None


def _token_identity(identity: str | None) -> str:
    if identity is None or not identity.strip():
        return f"ios-reciter-{uuid.uuid4().hex}"
    return identity.strip()
