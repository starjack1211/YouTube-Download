"""yt-dlp public JSC provider API backed by the app's JavaScriptCore bridge."""
import json
from collections import defaultdict
import _iosjs
import yt_dlp_ejs.yt.solver
from yt_dlp.extractor.youtube.jsc.provider import (
    JsChallengeProvider, JsChallengeProviderError, JsChallengeProviderResponse,
    JsChallengeResponse, JsChallengeType, NChallengeOutput, SigChallengeOutput,
    register_provider, register_preference,
)

@register_provider
class IOSJavaScriptCoreJCP(JsChallengeProvider):
    _SUPPORTED_TYPES = (JsChallengeType.N, JsChallengeType.SIG)

    def is_available(self):
        return True

    def _real_bulk_solve(self, requests):
        grouped = defaultdict(list)
        for request in requests:
            grouped[request.input.player_url].append(request)
        for player_url, group in grouped.items():
            try:
                player = self._get_player(group[0].video_id, player_url)
                payload = {"type": "player", "player": player,
                           "requests": [{"type": r.type.value, "challenges": r.input.challenges} for r in group],
                           "output_preprocessed": False}
                result = json.loads(_iosjs.solve(json.dumps(payload),
                    yt_dlp_ejs.yt.solver.lib(), yt_dlp_ejs.yt.solver.core()))
                responses = result.get("responses", [])
                if len(responses) != len(group):
                    raise JsChallengeProviderError(result.get("error", "Incomplete JavaScript response"))
                completed = []
                for request, response in zip(group, responses):
                    if response.get("type") != "result":
                        completed.append(JsChallengeProviderResponse(request, error=JsChallengeProviderError(
                            response.get("error", "JavaScript challenge failed"))))
                        continue
                    data = response.get("data") or {}
                    if any(not isinstance(data.get(c), str) or not data[c] for c in request.input.challenges):
                        raise JsChallengeProviderError("Missing challenge solution")
                    output = NChallengeOutput(data) if request.type is JsChallengeType.N else SigChallengeOutput(data)
                    completed.append(JsChallengeProviderResponse(request, JsChallengeResponse(request.type, output)))
                yield from completed
            except Exception as error:
                for request in group:
                    yield JsChallengeProviderResponse(request, error=error)

@register_preference(IOSJavaScriptCoreJCP)
def prefer_native(provider, requests):
    return 1000
