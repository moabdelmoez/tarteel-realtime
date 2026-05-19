from __future__ import annotations

import datetime as dt
import os
from collections.abc import Mapping
from dataclasses import dataclass
from typing import Protocol


DEFAULT_LIVEKIT_URL = "ws://127.0.0.1:7880"
DEFAULT_LIVEKIT_API_KEY = "devkey"
DEFAULT_LIVEKIT_API_SECRET = "secret"
DEFAULT_LIVEKIT_ROOM = "tarteel-local-recitation"


class LiveKitDependencyMissing(ImportError):
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
    return LiveKitSettings(
        url=values.get("LIVEKIT_URL", DEFAULT_LIVEKIT_URL),
        api_key=values.get("LIVEKIT_API_KEY", DEFAULT_LIVEKIT_API_KEY),
        api_secret=values.get("LIVEKIT_API_SECRET", DEFAULT_LIVEKIT_API_SECRET),
        room_name=values.get("TARTEEL_LIVEKIT_ROOM", DEFAULT_LIVEKIT_ROOM),
        token_ttl_minutes=int(values.get("TARTEEL_LIVEKIT_TOKEN_TTL_MINUTES", "60")),
    )


def livekit_token_response(
    *,
    settings: LiveKitSettings,
    identity: str,
    role: str,
    token_builder: LiveKitTokenBuilder | None = None,
) -> dict[str, str]:
    if not identity.strip():
        raise ValueError("identity must not be empty")

    request = _token_request_for_role(
        settings=settings,
        identity=identity,
        role=role,
    )
    builder = token_builder or LiveKitApiTokenBuilder()
    return {
        "url": settings.url,
        "room": settings.room_name,
        "identity": identity,
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
