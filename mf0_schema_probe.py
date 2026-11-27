import json
import re
import sys
import time
import uuid
from urllib.error import HTTPError, URLError
from urllib.parse import quote
from urllib.request import Request, urlopen


URL = "https://www.mf0.ai/api/v1/generations"
DEFAULT_MODEL = "claude-haiku-5-5"
API_KEY = re.compile(r"[A-Za-z0-9._~+/\-]+=*")
SUCCESS = {"succeeded", "success", "completed", "complete", "done"}
FAILURE = {"failed", "cancelled", "canceled", "expired", "rejected"}
SCHEMA = {
    "type": "object",
    "properties": {"translation": {"type": "string"}},
    "required": ["translation"],
    "additionalProperties": False,
}


def request_json(url, key, payload=None, timeout=15):
    headers = {"X-API-Key": key}
    data = None
    if payload is not None:
        headers["Idempotency-Key"] = str(uuid.uuid4())
        headers["Content-Type"] = "application/json"
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    request = Request(url, data=data, headers=headers)
    with urlopen(request, timeout=timeout) as response:
        body = json.load(response)
    if not isinstance(body, dict) or body.get("ok") is False:
        raise ValueError(f"Unexpected MF0 response: {body}")
    return body


def read_generation(body):
    generation = body.get("generation")
    if not isinstance(generation, dict):
        raise ValueError("MF0 response has no generation object.")
    return generation


def probe(key, word, model):
    prompt = (
        "Translate the supplied word into Ukrainian. Choose the most common meaning. "
        "Return only JSON matching this schema, without Markdown or explanations.\n"
        f"{json.dumps(SCHEMA)}\n"
        f"Word to translate: {json.dumps(word, ensure_ascii=False)}"
    )
    generation_id = None
    started = time.monotonic()
    try:
        generation = read_generation(
            request_json(URL, key, {"model": model, "prompt": prompt, "maxTokens": 512}, timeout=60)
        )
        generation_id = generation.get("id")
        if not isinstance(generation_id, str) or not generation_id:
            raise ValueError("MF0 response has no generation.id.")
        accepted = time.monotonic()
        print(f"Generation: {generation_id} (POST: {accepted - started:.2f} s)", flush=True)

        poll_url = f"{URL}/{quote(generation_id, safe='')}"
        deadline = accepted + 1200
        last_status = None
        polls = 0
        while True:
            status = str(generation.get("status", "unknown")).lower()
            if status != last_status:
                print(f"Status: {status}", flush=True)
                last_status = status
            if status in SUCCESS:
                break
            if status in FAILURE:
                raise ValueError(f"Generation {status}: {generation.get('error', '')}")
            remaining = deadline - time.monotonic()
            delay = 0.5 if polls == 0 else 1
            if remaining <= delay:
                raise TimeoutError("Timed out while waiting for the generation.")
            time.sleep(delay)
            generation = read_generation(request_json(poll_url, key, timeout=min(15, remaining - delay)))
            polls += 1

        finished = time.monotonic()
        print(f"Result observed: {finished - started:.2f} s total, "
              f"{finished - accepted:.2f} s after POST, {polls} GET request(s)")

        result = generation.get("result")
        content = result.get("text") if isinstance(result, dict) else None
        if not isinstance(content, str):
            raise ValueError("MF0 response has no generation.result.text.")
    except HTTPError as error:
        details = error.read().decode("utf-8", errors="replace").replace(key, "[redacted]")
        print(f"MF0 returned HTTP {error.code}: {details[:1500]}", file=sys.stderr)
        return 1
    except (URLError, TimeoutError, ValueError) as error:
        details = str(error).replace(key, "[redacted]")
        print(f"MF0 request failed: {details[:1500]}", file=sys.stderr)
        return 1

    try:
        translation = json.loads(content)
    except ValueError:
        translation = None
    if (
        not isinstance(translation, dict)
        or set(translation) != {"translation"}
        or not isinstance(translation["translation"], str)
    ):
        print("Response did not match the JSON schema.", file=sys.stderr)
        print(content.replace(key, "[redacted]")[:1500], file=sys.stderr)
        return 1

    print(f"Translation: {translation['translation'].replace(key, '[redacted]')}")
    print("Response matches the schema supplied in the prompt.")
    return 0


def main():
    model = input(f"MF0 model ID [{DEFAULT_MODEL}]: ").strip() or DEFAULT_MODEL
    words = [word.strip() for word in input("Enter one word or three comma-separated words: ").split(",")]
    if len(words) not in {1, 3} or not all(words):
        print("Enter one word or three nonempty words separated by commas.", file=sys.stderr)
        return 1
    while True:
        key = input("MF0 API key (visible): ").strip()
        if not key:
            print("An MF0 API key is required.", file=sys.stderr)
            return 1
        if API_KEY.fullmatch(key):
            break
        print("Paste only the MF0 API key (mf0_v1_...), without quotes or extra text.", file=sys.stderr)

    failures = 0
    for index, word in enumerate(words, start=1):
        print(f"\n[{index}/{len(words)}] {word}", flush=True)
        failures += probe(key, word, model)
    print(f"\nPassed: {len(words) - failures}/{len(words)}")
    return int(failures > 0)


if __name__ == "__main__":
    sys.exit(main())
