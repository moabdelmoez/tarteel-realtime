import unittest

from tarteel_realtime.livekit_tokens import (
    LiveKitSettings,
    LiveKitTokenRequest,
    livekit_settings_from_env,
    livekit_token_response,
)


class RecordingTokenBuilder:
    def __init__(self):
        self.requests = []

    def build(self, request: LiveKitTokenRequest) -> str:
        self.requests.append(request)
        return f"token:{request.identity}:{request.role}"


class LiveKitTokenTests(unittest.TestCase):
    def test_local_dev_settings_use_livekit_dev_defaults(self):
        settings = livekit_settings_from_env({})

        self.assertEqual(settings.url, "ws://127.0.0.1:7880")
        self.assertEqual(settings.api_key, "devkey")
        self.assertEqual(settings.api_secret, "secret")
        self.assertEqual(settings.room_name, "tarteel-local-recitation")

    def test_blank_cloud_settings_keep_livekit_dev_defaults(self):
        settings = livekit_settings_from_env({
            "LIVEKIT_URL": "",
            "LIVEKIT_API_KEY": "",
            "LIVEKIT_API_SECRET": "",
        })

        self.assertEqual(settings.url, "ws://127.0.0.1:7880")
        self.assertEqual(settings.api_key, "devkey")
        self.assertEqual(settings.api_secret, "secret")

    def test_cloud_settings_use_livekit_cloud_credentials_from_env(self):
        settings = livekit_settings_from_env({
            "LIVEKIT_URL": "wss://tarteel-example.livekit.cloud",
            "LIVEKIT_API_KEY": "cloud-key",
            "LIVEKIT_API_SECRET": "cloud-secret",
            "TARTEEL_LIVEKIT_ROOM": "tarteel-cloud-recitation",
            "TARTEEL_LIVEKIT_TOKEN_TTL_MINUTES": "15",
        })

        self.assertEqual(settings.url, "wss://tarteel-example.livekit.cloud")
        self.assertEqual(settings.api_key, "cloud-key")
        self.assertEqual(settings.api_secret, "cloud-secret")
        self.assertEqual(settings.room_name, "tarteel-cloud-recitation")
        self.assertEqual(settings.token_ttl_minutes, 15)

    def test_cloud_settings_require_url_key_and_secret_together(self):
        with self.assertRaisesRegex(ValueError, "LIVEKIT_API_KEY, LIVEKIT_API_SECRET"):
            livekit_settings_from_env({
                "LIVEKIT_URL": "wss://tarteel-example.livekit.cloud",
            })

    def test_token_response_builds_client_grants(self):
        builder = RecordingTokenBuilder()

        response = livekit_token_response(
            settings=LiveKitSettings(),
            identity="ios-simulator",
            role="client",
            token_builder=builder,
        )

        self.assertEqual(response["url"], "ws://127.0.0.1:7880")
        self.assertEqual(response["room"], "tarteel-local-recitation")
        self.assertEqual(response["identity"], "ios-simulator")
        self.assertEqual(response["session_id"], "ios-simulator")
        self.assertEqual(response["role"], "client")
        self.assertEqual(response["token"], "token:ios-simulator:client")
        self.assertTrue(builder.requests[0].can_publish)
        self.assertTrue(builder.requests[0].can_subscribe)
        self.assertTrue(builder.requests[0].can_publish_data)

    def test_token_response_generates_unique_ios_identity_when_not_provided(self):
        builder = RecordingTokenBuilder()

        first = livekit_token_response(
            settings=LiveKitSettings(),
            identity=None,
            role="client",
            token_builder=builder,
        )
        second = livekit_token_response(
            settings=LiveKitSettings(),
            identity=None,
            role="client",
            token_builder=builder,
        )

        self.assertRegex(first["identity"], r"^ios-reciter-[0-9a-f-]+$")
        self.assertRegex(second["identity"], r"^ios-reciter-[0-9a-f-]+$")
        self.assertNotEqual(first["identity"], second["identity"])
        self.assertEqual(first["session_id"], first["identity"])
        self.assertEqual(second["session_id"], second["identity"])
        self.assertEqual(builder.requests[0].identity, first["identity"])
        self.assertEqual(builder.requests[1].identity, second["identity"])

    def test_token_response_builds_worker_grants_without_media_publish(self):
        builder = RecordingTokenBuilder()

        response = livekit_token_response(
            settings=LiveKitSettings(),
            identity="backend-worker",
            role="worker",
            token_builder=builder,
        )

        self.assertEqual(response["role"], "worker")
        self.assertFalse(builder.requests[0].can_publish)
        self.assertTrue(builder.requests[0].can_subscribe)
        self.assertTrue(builder.requests[0].can_publish_data)


if __name__ == "__main__":
    unittest.main()
