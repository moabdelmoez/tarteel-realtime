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
        self.assertEqual(response["role"], "client")
        self.assertEqual(response["token"], "token:ios-simulator:client")
        self.assertTrue(builder.requests[0].can_publish)
        self.assertTrue(builder.requests[0].can_subscribe)
        self.assertTrue(builder.requests[0].can_publish_data)

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
