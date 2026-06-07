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


def stream_openai(prompt: str, model: str, api_key: str, temperature: float, out_file) -> None:
    from openai import OpenAI  # pip install openai

    client = OpenAI(api_key=api_key)
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

    # Delete prompt file immediately — it contains the API key
    try:
        os.remove(prompt_file)
    except OSError:
        pass

    # Clear response file before writing
    open(response_file, "w", encoding="utf-8").close()

    try:
        with open(response_file, "a", encoding="utf-8") as out:
            if provider == "ANTHROPIC":
                stream_anthropic(prompt, model, api_key, temperature, out)
            else:
                stream_openai(prompt, model, api_key, temperature, out)

            out.write("\n##DONE##")

    except Exception as exc:
        with open(response_file, "a", encoding="utf-8") as out:
            out.write(f"\n##ERROR## {exc}")


if __name__ == "__main__":
    main()
