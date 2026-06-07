"""
llm_stream.py - Local streaming proxy for ABAP AI Code.

Called by SAP GUI (cl_gui_frontend_services=>execute) asynchronously.
Reads a JSON config/prompt file, streams from LLM API, writes chunks
to a response file that ABAP polls every 100ms via cl_gui_timer.

Usage:
    python llm_stream.py <prompt_file> <response_file>

prompt_file JSON format:
    {
        "prompt":      "user question text",
        "model":       "claude-opus-4-5",
        "provider":    "ANTHROPIC",
        "api_key":     "sk-ant-...",
        "temperature": "0.1"
    }

Terminal markers written to response_file:
    ##DONE##   - streaming completed successfully
    ##ERROR##  - exception occurred (error text follows the marker)
"""

import sys
import os
import json


def stream_anthropic(prompt: str, model: str, api_key: str, temperature: float, out_file) -> None:
    import anthropic  # pip install anthropic

    client = anthropic.Anthropic(api_key=api_key)
    with client.messages.stream(
        model=model,
        max_tokens=8096,
        temperature=temperature,
        messages=[{"role": "user", "content": prompt}],
    ) as stream:
        for text in stream.text_stream:
            out_file.write(text)
            out_file.flush()


def get_base_url(model: str, base_url: str) -> str:
    """Determine base_url from model name if not explicitly provided."""
    if base_url:
        return base_url
    m = model.lower()
    if "codestral" in m:
        return "https://codestral.mistral.ai/v1"
    if "mistral" in m or "mixtral" in m or "devstral" in m:
        return "https://api.mistral.ai/v1"
    return None  # default OpenAI


def stream_openai(prompt: str, model: str, api_key: str, temperature: float, out_file,
                  base_url: str = None) -> None:
    from openai import OpenAI  # pip install openai

    url = get_base_url(model, base_url)
    client = OpenAI(api_key=api_key, base_url=url) if url else OpenAI(api_key=api_key)
    response = client.chat.completions.create(
        model=model,
        max_tokens=8096,
        temperature=temperature,
        messages=[{"role": "user", "content": prompt}],
        stream=True,
    )
    for chunk in response:
        delta = chunk.choices[0].delta.content
        if delta:
            out_file.write(delta)
            out_file.flush()


def main() -> None:
    if len(sys.argv) < 3:
        print("Usage: llm_stream.py <prompt_file> <response_file>", file=sys.stderr)
        sys.exit(1)

    prompt_file   = sys.argv[1]
    response_file = sys.argv[2]

    # Read and parse JSON config
    with open(prompt_file, "r", encoding="utf-8") as f:
        cfg = json.load(f)

    prompt      = cfg.get("prompt", "")
    model       = cfg.get("model", "")
    provider    = cfg.get("provider", "ANTHROPIC").upper()
    api_key     = cfg.get("api_key", "")
    temperature = float(cfg.get("temperature", "0.1"))
    base_url    = cfg.get("base_url", None)  # optional: for OpenAI-compatible APIs (Mistral etc.)

    # Note: prompt file is NOT deleted — useful for local debugging.
    # In production, consider deleting it here to protect the API key.

    # Write log file next to response file for debugging
    import os
    log_file = os.path.join(os.path.dirname(response_file), "llm_stream.log")
    import datetime
    def log(msg):
        with open(log_file, "a", encoding="utf-8") as f:
            f.write(f"[{datetime.datetime.now():%H:%M:%S}] {msg}\n")

    log(f"START provider={provider} model={model}")

    # Use system locale encoding so SAP GUI gui_upload can read the file correctly.
    # On Russian/Ukrainian Windows this is cp1251; on Western Windows cp1252.
    import locale
    file_encoding = locale.getpreferredencoding(False) or "utf-8"
    log(f"file_encoding={file_encoding}")

    # Clear response file before writing
    open(response_file, "w", encoding=file_encoding).close()

    try:
        with open(response_file, "a", encoding=file_encoding, errors="replace") as out:
            if provider == "ANTHROPIC":
                log("calling anthropic stream...")
                stream_anthropic(prompt, model, api_key, temperature, out)
            else:
                log(f"calling openai stream... base_url={base_url}")
                stream_openai(prompt, model, api_key, temperature, out, base_url)

            out.write("\n##DONE##")
            log("DONE")

    except Exception as exc:
        log(f"ERROR: {exc}")
        with open(response_file, "a", encoding=file_encoding, errors="replace") as out:
            out.write(f"\n##ERROR## {exc}")


if __name__ == "__main__":
    main()
