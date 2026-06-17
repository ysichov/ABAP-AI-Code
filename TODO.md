# TODO

## ZCL_CODE_AI_API

- [ ] **Anthropic prompt caching** — add `cache_control: {type: "ephemeral"}` to system prompt and tool definitions in `BUILD_PAYLOAD`. Also parse `cache_read_input_tokens` / `cache_creation_input_tokens` from response into `EV_TOK_CACHED`. Currently caching works automatically for OpenAI only.

## Python Agent / Tools

- [ ] **vsp.exe Python wrapper** — instead of implementing SAP read/write tools in ABAP, call [vibing-steampunk](https://github.com/oisee/vibing-steampunk) CLI from Python via `subprocess`. Covers the gap until our own ABAP tools are ready.

  Key mappings:
  | Tool needed | vsp command |
  |---|---|
  | read SAP object | `vsp source CLAS ZCL_X` |
  | read single method | `vsp source CLAS ZCL_X --method METHOD_NAME` |
  | find callers/callees | `vsp graph CLAS ZCL_X --direction callers` |
  | grep in SAP package | `vsp grep "pattern" --package $Z` |
  | ATC check | `vsp atc CLAS ZCL_X` |
  | deploy file to SAP | `vsp deploy file.abap $TMP` |
  | source + dependencies | `vsp context CLAS ZCL_X --depth 2` |

  Requirements: `vsp.exe` on the agent machine + SAP credentials config.
