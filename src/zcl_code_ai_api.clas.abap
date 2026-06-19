class ZCL_CODE_AI_API definition
  public
  create public .

public section.

  types:
    BEGIN OF TY_TOOL_CALL,
      ID        type STRING,   " OpenAI tool_call id (needed for the reply)
      NAME      type STRING,   " tool name, e.g. 'read_sap_object'
      ARGUMENTS type STRING,   " raw JSON arguments string
    END OF TY_TOOL_CALL .
  types TT_TOOL_CALLS type STANDARD TABLE OF TY_TOOL_CALL WITH NON-UNIQUE DEFAULT KEY .

  " Lists available models via GET <i_url> (direct create_by_url, no SM59).
  " I_PROVIDER selects the auth header: ANTHROPIC -> x-api-key + version,
  " anything else -> Authorization: Bearer. Response "data[].id" -> ET_IDS.
  class-methods LIST_MODELS
    importing
      !I_URL      type STRING
      !I_APIKEY   type STRING
      !I_PROVIDER type STRING default 'ANTHROPIC'
      !I_SSL_ID   type SSFAPPLSSL default 'ANONYM'
    exporting
      !ET_IDS     type STRINGTAB
      !E_ERROR    type STRING .
  class-methods ASK
    importing
      !I_PROMPT type STRING
      !I_SYSTEM_PROMPT type STRING optional
      !IT_HISTORY type ZCL_AI_MESSAGES=>TT_MESSAGES optional
      !I_MODEL type TEXT255
      !I_APIKEY type STRING
      !I_PROVIDER type STRING default 'ANTHROPIC'
      !I_SSL_ID type SSFAPPLSSL default 'ANONYM'
      !I_PROMPT_CACHE_KEY type STRING optional
      !I_JSON_SCHEMA type STRING optional
      !I_TEMPERATURE type STRING optional
      !I_TOOLS_JSON type STRING optional
      !I_MAX_TOKENS type I optional
      !I_THINKING_BUDGET type I default 0
    exporting
      !EV_TOK_IN       type I
      !EV_TOK_OUT      type I
      !EV_TOK_TOTAL    type I
      !EV_TOK_CACHED   type I
      !ET_TOOL_CALLS   type TT_TOOL_CALLS
      !EV_RAW_REQUEST  type STRING
      !EV_RAW_RESPONSE type STRING
      !EV_THINKING     type STRING
    returning
      value(RV_ANSWER) type STRING .
protected section.
private section.

  " Provider base URL for direct create_by_url calls (no SM59 destination).
  " ANTHROPIC -> api.anthropic.com, OPENAI -> api.openai.com,
  " MISTRAL -> api.mistral.ai. The endpoint path is appended by the caller.
  class-methods BASE_URL
    importing
      !I_PROVIDER type STRING
    returning
      value(RV_URL) type STRING .
  class-methods BUILD_PAYLOAD
    importing
      !I_PROMPT type STRING
      !I_SYSTEM_PROMPT type STRING optional
      !IT_HISTORY type ZCL_AI_MESSAGES=>TT_MESSAGES optional
      !I_MODEL type TEXT255
      !I_PROVIDER type STRING
      !I_PROMPT_CACHE_KEY type STRING optional
      !I_JSON_SCHEMA type STRING optional
      !I_TEMPERATURE type STRING optional
      !I_TOOLS_JSON type STRING optional
      !I_MAX_TOKENS type I optional
      !I_THINKING_BUDGET type I default 0
    returning
      value(RV_JSON) type STRING .
  " Converts the OpenAI-format tools array (each entry
  " {"type":"function","function":{...}}) into the Anthropic tools array (each
  " entry {"name":..,"description":..,"input_schema":{..}}). The last tool gets a
  " cache_control marker so the entire tool definition block is prompt-cached.
  class-methods BUILD_ANTHROPIC_TOOLS
    importing
      !I_TOOLS_JSON type STRING
    returning
      value(RV_JSON) type STRING .
  " Returns the balanced { ... } JSON object starting at the first '{' found at
  " or after I_OFFSET, using a string-aware brace scan (braces inside JSON string
  " values are ignored). Returns empty when no balanced object is found.
  class-methods EXTRACT_JSON_OBJECT
    importing
      !I_TEXT type STRING
      !I_OFFSET type I default 0
    returning
      value(RV_OBJECT) type STRING .
  " Extracts Anthropic "tool_use" content blocks
  " ({"type":"tool_use","id":..,"name":..,"input":{..}}) from a raw response and
  " appends them as tool calls; the input object is preserved as a raw JSON string.
  class-methods PARSE_ANTHROPIC_TOOL_USE
    importing
      !I_JSON type STRING
    changing
      !CT_TOOL_CALLS type TT_TOOL_CALLS .
  class-methods PARSE_RESPONSE
    importing
      !I_JSON type STRING
      !I_PROVIDER type STRING
    exporting
      !EV_TOK_IN     type I
      !EV_TOK_OUT    type I
      !EV_TOK_TOTAL  type I
      !EV_TOK_CACHED type I
      !ET_TOOL_CALLS type TT_TOOL_CALLS
      !EV_THINKING   type STRING
    returning
      value(RV_ANSWER) type STRING .
ENDCLASS.



CLASS ZCL_CODE_AI_API IMPLEMENTATION.


  method BASE_URL.

    DATA(lv_prov) = i_provider.
    TRANSLATE lv_prov TO UPPER CASE.
    rv_url = SWITCH #( lv_prov
                       WHEN 'MISTRAL' THEN 'https://api.mistral.ai'
                       WHEN 'OPENAI'  THEN 'https://api.openai.com'
                       ELSE 'https://api.anthropic.com' ).

  endmethod.


  method LIST_MODELS.

    DATA: lo_client   TYPE REF TO if_http_client,
          lv_provider TYPE string.

    CLEAR: et_ids, e_error.

    lv_provider = i_provider.
    TRANSLATE lv_provider TO UPPER CASE.

    cl_http_client=>create_by_url(
      EXPORTING url    = i_url
                ssl_id = i_ssl_id
      IMPORTING client = lo_client
      EXCEPTIONS OTHERS = 4 ).
    IF sy-subrc <> 0.
      e_error = |create_by_url failed rc={ sy-subrc } (check URL / SSL in STRUST)|.
      RETURN.
    ENDIF.

    lo_client->request->set_method( 'GET' ).
    IF lv_provider = 'ANTHROPIC'.
      lo_client->request->set_header_field( name = 'anthropic-version' value = '2023-06-01' ).
      lo_client->request->set_header_field( name = 'x-api-key'         value = i_apikey ).
    ELSE.
      lo_client->request->set_header_field( name = 'Authorization' value = |Bearer { i_apikey }| ).
    ENDIF.
    " Suppress the SAP logon popup so a 401/403 returns the JSON body.
    lo_client->propertytype_logon_popup = if_http_client=>co_disabled.

    DATA lv_err_code TYPE i.
    DATA lv_err_msg  TYPE string.

    lo_client->send( EXCEPTIONS http_communication_failure = 1 OTHERS = 2 ).
    IF sy-subrc <> 0.
      lo_client->get_last_error( IMPORTING code = lv_err_code message = lv_err_msg ).
      e_error = |HTTP send failed (code={ lv_err_code } msg={ lv_err_msg })|.
      RETURN.
    ENDIF.
    lo_client->receive( EXCEPTIONS http_communication_failure = 1 OTHERS = 2 ).
    IF sy-subrc <> 0.
      lo_client->get_last_error( IMPORTING code = lv_err_code message = lv_err_msg ).
      e_error = |HTTP receive failed (code={ lv_err_code } msg={ lv_err_msg })|.
      RETURN.
    ENDIF.

    DATA(lv_json) = lo_client->response->get_cdata( ).

    " Both Anthropic and OpenAI-compatible APIs return models under "data[].id".
    TYPES: BEGIN OF ty_m,
             id TYPE string,
           END OF ty_m,
           BEGIN OF ty_res,
             data TYPE STANDARD TABLE OF ty_m WITH DEFAULT KEY,
           END OF ty_res.
    DATA ls_res TYPE ty_res.
    /ui2/cl_json=>deserialize( EXPORTING json = lv_json CHANGING data = ls_res ).

    LOOP AT ls_res-data INTO DATA(ls).
      APPEND ls-id TO et_ids.
    ENDLOOP.

    IF et_ids IS INITIAL.
      DATA(lv_len) = nmin( val1 = strlen( lv_json ) val2 = 150 ).
      e_error = |Unexpected response: { lv_json(lv_len) }|.
    ENDIF.

  endmethod.


  method ASK.

    DATA: payload  TYPE string,
          o_client TYPE REF TO if_http_client.
    DATA: lv_provider TYPE string,
          lv_auth     TYPE string.

    lv_provider = i_provider.
    TRANSLATE lv_provider TO UPPER CASE.
    IF lv_provider IS INITIAL.
      lv_provider = 'ANTHROPIC'.
    ENDIF.

    payload = build_payload(
      i_prompt           = i_prompt
      i_system_prompt    = i_system_prompt
      it_history         = it_history
      i_model            = i_model
      i_provider         = lv_provider
      i_prompt_cache_key = i_prompt_cache_key
      i_json_schema      = i_json_schema
      i_temperature      = i_temperature
      i_tools_json       = i_tools_json
      i_max_tokens       = i_max_tokens
      i_thinking_budget  = i_thinking_budget ).

    " Build the endpoint URL directly from the provider - no SM59 destination.
    " Anthropic: /v1/messages ; OpenAI-compatible (OpenAI/Mistral): /v1/chat/completions
    DATA(lv_url) = base_url( lv_provider ) &&
      COND string( WHEN lv_provider = 'ANTHROPIC'
                   THEN '/v1/messages'
                   ELSE '/v1/chat/completions' ).

    cl_http_client=>create_by_url(
      EXPORTING  url    = lv_url
                 ssl_id = i_ssl_id
      IMPORTING  client = o_client
      EXCEPTIONS OTHERS = 5 ).
    IF sy-subrc <> 0.
      rv_answer = |Error: create_by_url failed rc={ sy-subrc } (check URL / SSL in STRUST)|.
      RETURN.
    ENDIF.

    o_client->request->set_header_field( name = 'Content-Type' value = 'application/json' ).
    IF lv_provider = 'OPENAI'.
      lv_auth = i_apikey.
      IF lv_auth CP 'Bearer *' OR lv_auth CP 'bearer *'.
        o_client->request->set_header_field( name = 'Authorization' value = lv_auth ).
      ELSE.
        o_client->request->set_header_field( name = 'Authorization' value = |Bearer { lv_auth }| ).
      ENDIF.
    ELSE.
      o_client->request->set_header_field( name = 'anthropic-version' value = '2023-06-01' ).
      o_client->request->set_header_field( name = 'x-api-key'         value = i_apikey ).
    ENDIF.
    o_client->request->set_method( 'POST' ).
    o_client->request->set_cdata( payload ).

    " Suppress the SAP logon popup so a 401/403 returns the JSON error body
    " instead of prompting the user for a user name / password.
    o_client->propertytype_logon_popup = if_http_client=>co_disabled.

    DATA lv_err_code TYPE i.
    DATA lv_err_msg  TYPE string.

    o_client->send(
      EXCEPTIONS http_communication_failure = 1
                 OTHERS                     = 5 ).

    IF sy-subrc <> 0.
      o_client->get_last_error( IMPORTING code = lv_err_code message = lv_err_msg ).
      rv_answer = |Error: HTTP send failed (code={ lv_err_code } msg={ lv_err_msg })|.
      RETURN.
    ENDIF.

    o_client->receive(
      EXCEPTIONS http_communication_failure = 1
                 OTHERS                     = 4 ).

    IF sy-subrc <> 0.
      o_client->get_last_error( IMPORTING code = lv_err_code message = lv_err_msg ).
      rv_answer = |Error: HTTP receive failed (code={ lv_err_code } msg={ lv_err_msg })|.
      RETURN.
    ENDIF.

    DATA(lv_response) = o_client->response->get_cdata( ).
    ev_raw_request  = payload.
    ev_raw_response = lv_response.
    rv_answer = parse_response(
      EXPORTING
        i_json     = lv_response
        i_provider = lv_provider
      IMPORTING
        ev_tok_in     = ev_tok_in
        ev_tok_out    = ev_tok_out
        ev_tok_total  = ev_tok_total
        ev_tok_cached = ev_tok_cached
        et_tool_calls = et_tool_calls
        ev_thinking   = ev_thinking ).

  endmethod.


  method BUILD_PAYLOAD.

    DATA: lv_prompt           TYPE string,
          lv_system_prompt    TYPE string,
          lv_prompt_cache_key TYPE string,
          lv_provider         TYPE string,
          lv_cr               TYPE c LENGTH 1.

    lv_provider = i_provider.
    TRANSLATE lv_provider TO UPPER CASE.
    lv_cr = cl_abap_char_utilities=>cr_lf(1).

    " Escape user prompt for JSON
    lv_prompt = i_prompt.
    REPLACE ALL OCCURRENCES OF '\' IN lv_prompt WITH '\\'.
    REPLACE ALL OCCURRENCES OF '"' IN lv_prompt WITH '\"'.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf IN lv_prompt WITH '\n'.
    REPLACE ALL OCCURRENCES OF lv_cr IN lv_prompt WITH '\r'.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>newline IN lv_prompt WITH '\n'.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>form_feed IN lv_prompt WITH '\f'.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>horizontal_tab IN lv_prompt WITH '\t'.

    " Escape system prompt for JSON (same rules)
    lv_system_prompt = i_system_prompt.
    REPLACE ALL OCCURRENCES OF '\' IN lv_system_prompt WITH '\\'.
    REPLACE ALL OCCURRENCES OF '"' IN lv_system_prompt WITH '\"'.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf IN lv_system_prompt WITH '\n'.
    REPLACE ALL OCCURRENCES OF lv_cr IN lv_system_prompt WITH '\r'.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>newline IN lv_system_prompt WITH '\n'.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>form_feed IN lv_system_prompt WITH '\f'.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>horizontal_tab IN lv_system_prompt WITH '\t'.

    " Anthropic: system is top-level field
    " OpenAI:    system is first message with role "system"
    " For Anthropic the system prompt is sent as a content-block array with a
    " cache_control marker so the (large, stable) system prompt is cached and
    " only billed once per 5-minute window.
    DATA lv_system_field TYPE string.
    IF lv_system_prompt IS NOT INITIAL.
      IF lv_provider = 'ANTHROPIC'.
        lv_system_field = |, "system": [{ '{' }"type": "text", "text": "{ lv_system_prompt }"|
                       && |, "cache_control": { '{' }"type": "ephemeral"{ '}' }{ '}' }]|.
      ENDIF.
    ENDIF.

    " Build provider-specific structured output field from raw JSON schema
    " OpenAI:    response_format -> json_schema wrapper with strict:true
    " Anthropic: output_config  -> format wrapper (no name/strict needed)
    DATA lv_response_format TYPE string.
    IF i_json_schema IS NOT INITIAL.
      IF lv_provider = 'OPENAI'.
        lv_response_format = |, "response_format": { '{' }"type": "json_schema", "json_schema": { '{' }"name": "schema", "strict": true, "schema": { i_json_schema }{ '}' }{ '}' }|.
      ELSEIF lv_provider = 'ANTHROPIC'.
        lv_response_format = |, "output_config": { '{' }"format": { '{' }"type": "json_schema", "schema": { i_json_schema }{ '}' }{ '}' }|.
      ENDIF.
    ENDIF.

    " Build messages array: system + history turns + current user message
    DATA lv_messages TYPE string.
    DATA lv_msg_sep  TYPE string.

    " OpenAI: system as first message in array
    IF lv_provider = 'OPENAI' AND lv_system_prompt IS NOT INITIAL.
      lv_messages = |{ '{' }"role": "system", "content": "{ lv_system_prompt }"{ '}' }|.
      lv_msg_sep = ', '.
    ENDIF.

    " Append conversation history (user/assistant turns for multi-turn context)
    LOOP AT it_history INTO DATA(ls_hist).
      CHECK ls_hist-role = 'user' OR ls_hist-role = 'assistant'.
      DATA lv_hist_content TYPE string.
      lv_hist_content = ls_hist-content.
      REPLACE ALL OCCURRENCES OF '\' IN lv_hist_content WITH '\\'.
      REPLACE ALL OCCURRENCES OF '"' IN lv_hist_content WITH '\"'.
      REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf IN lv_hist_content WITH '\n'.
      REPLACE ALL OCCURRENCES OF lv_cr IN lv_hist_content WITH '\r'.
      REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>newline IN lv_hist_content WITH '\n'.
      REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>form_feed IN lv_hist_content WITH '\f'.
      REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>horizontal_tab IN lv_hist_content WITH '\t'.
      lv_messages = lv_messages && lv_msg_sep
        && |{ '{' }"role": "{ ls_hist-role }", "content": "{ lv_hist_content }"{ '}' }|.
      lv_msg_sep = ', '.
    ENDLOOP.

    " Current user message (always last)
    lv_messages = lv_messages && lv_msg_sep
      && |{ '{' }"role": "user", "content": "{ lv_prompt }"{ '}' }|.

    " Extended thinking (Anthropic only): when a budget is requested, emit the
    " thinking block. Anthropic forbids temperature with thinking (must be 1),
    " so the temperature field is dropped in that case. budget min is 1024.
    DATA lv_thinking_field TYPE string.
    DATA lv_budget         TYPE i.
    DATA lv_thinking_on    TYPE abap_bool.
    IF lv_provider = 'ANTHROPIC' AND i_thinking_budget > 0.
      lv_thinking_on = abap_true.
      lv_budget = i_thinking_budget.
      IF lv_budget < 1024.
        lv_budget = 1024.
      ENDIF.
      lv_thinking_field = |, "thinking": { '{' }"type": "enabled", "budget_tokens": { lv_budget }{ '}' }|.
    ENDIF.

    " Optional temperature field (e.g. "0.2" or "1.0") - omitted when not provided
    " or when extended thinking is on (Anthropic requires the default).
    DATA lv_temp_field TYPE string.
    IF i_temperature IS NOT INITIAL AND lv_thinking_on = abap_false.
      lv_temp_field = |, "temperature": { i_temperature }|.
    ENDIF.

    " Optional function-calling tools array (already valid JSON, no escaping)
    " OpenAI:    "tools": [...]  (schemas are already in OpenAI function format)
    " Anthropic: tools array converted to {"name":..,"description":..,"input_schema":{..}};
    "            the last tool carries a cache_control marker so the whole tool
    "            block is prompt-cached.
    DATA lv_tools_field TYPE string.
    IF i_tools_json IS NOT INITIAL AND lv_provider = 'OPENAI'.
      lv_tools_field = |, "tools": { i_tools_json }|.
    ELSEIF i_tools_json IS NOT INITIAL AND lv_provider = 'ANTHROPIC'.
      lv_tools_field = |, "tools": { build_anthropic_tools( i_tools_json ) }|.
    ENDIF.

    " max_tokens: 0 = omit field (no limit, OpenAI/Mistral only).
    " Anthropic requires it - fall back to 32000 when caller passes 0.
    " max_tokens must exceed budget_tokens when thinking is on (the budget is
    " part of the output allowance), so bump it if the caller's value is too low.
    DATA lv_maxt TYPE i.
    lv_maxt = i_max_tokens.
    IF lv_thinking_on = abap_true AND lv_maxt <= lv_budget.
      lv_maxt = lv_budget + 4096.
    ENDIF.

    DATA lv_maxt_field TYPE string.
    IF lv_maxt > 0.
      lv_maxt_field = |, "max_tokens": { lv_maxt }|.
    ELSEIF lv_provider = 'ANTHROPIC'.
      lv_maxt_field = |, "max_tokens": 32000|.
    ENDIF.

    rv_json = |{ '{' }"model": "{ i_model }"{ lv_system_field }, "messages": [{ lv_messages }]{ lv_maxt_field }{ lv_thinking_field }{ lv_temp_field }{ lv_response_format }{ lv_tools_field }{ '}' }|.
    IF lv_provider = 'OPENAI' AND i_prompt_cache_key IS NOT INITIAL.
      lv_prompt_cache_key = i_prompt_cache_key.
      REPLACE ALL OCCURRENCES OF '\' IN lv_prompt_cache_key WITH '\\'.
      REPLACE ALL OCCURRENCES OF '"' IN lv_prompt_cache_key WITH '\"'.
      rv_json = |{ '{' }"model": "{ i_model }"{ lv_system_field }, "messages": [{ lv_messages }]{ lv_maxt_field }, "prompt_cache_key": "{ lv_prompt_cache_key }"{ lv_temp_field }{ lv_response_format }{ lv_tools_field }{ '}' }|.
    ENDIF.

  endmethod.


  method EXTRACT_JSON_OBJECT.

    DATA lv_start TYPE i.
    FIND FIRST OCCURRENCE OF '{' IN SECTION OFFSET i_offset OF i_text
      MATCH OFFSET lv_start.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    DATA lv_depth TYPE i.
    DATA lv_instr TYPE abap_bool.
    DATA lv_esc   TYPE abap_bool.
    DATA lv_i     TYPE i.
    DATA lv_len   TYPE i.
    lv_i   = lv_start.
    lv_len = strlen( i_text ).
    WHILE lv_i < lv_len.
      DATA(lv_ch) = i_text+lv_i(1).
      rv_object = rv_object && lv_ch.
      IF lv_instr = abap_true.
        IF lv_esc = abap_true.
          lv_esc = abap_false.
        ELSEIF lv_ch = '\'.
          lv_esc = abap_true.
        ELSEIF lv_ch = '"'.
          lv_instr = abap_false.
        ENDIF.
      ELSE.
        IF lv_ch = '"'.
          lv_instr = abap_true.
        ELSEIF lv_ch = '{'.
          lv_depth = lv_depth + 1.
        ELSEIF lv_ch = '}'.
          lv_depth = lv_depth - 1.
          IF lv_depth = 0.
            EXIT.
          ENDIF.
        ENDIF.
      ENDIF.
      lv_i = lv_i + 1.
    ENDWHILE.

  endmethod.


  method BUILD_ANTHROPIC_TOOLS.

    " Strip the outer [ ... ] of the OpenAI tools array. The array is produced as
    " |[<schemas>]| so it starts/ends with the brackets (no surrounding spaces);
    " CONDENSE is deliberately avoided so it cannot collapse spaces inside
    " description strings.
    DATA(lv_inner) = i_tools_json.
    IF strlen( lv_inner ) >= 1 AND lv_inner(1) = '['.
      lv_inner = lv_inner+1.
    ENDIF.
    DATA lv_tail TYPE i.
    lv_tail = strlen( lv_inner ) - 1.
    IF lv_tail >= 0 AND lv_inner+lv_tail(1) = ']'.
      lv_inner = lv_inner(lv_tail).
    ENDIF.

    " Split into top-level tool objects with a brace-aware, string-aware scan so
    " braces inside JSON string values do not affect nesting depth.
    DATA lt_tools TYPE STANDARD TABLE OF string WITH NON-UNIQUE DEFAULT KEY.
    DATA lv_cur   TYPE string.
    DATA lv_depth TYPE i.
    DATA lv_instr TYPE abap_bool.
    DATA lv_esc   TYPE abap_bool.
    DATA lv_idx   TYPE i.
    DATA lv_total TYPE i.
    lv_total = strlen( lv_inner ).
    WHILE lv_idx < lv_total.
      DATA(lv_c) = lv_inner+lv_idx(1).
      IF lv_instr = abap_true.
        lv_cur = lv_cur && lv_c.
        IF lv_esc = abap_true.
          lv_esc = abap_false.
        ELSEIF lv_c = '\'.
          lv_esc = abap_true.
        ELSEIF lv_c = '"'.
          lv_instr = abap_false.
        ENDIF.
      ELSE.
        CASE lv_c.
          WHEN '"'.
            lv_instr = abap_true.
            lv_cur = lv_cur && lv_c.
          WHEN '{'.
            lv_depth = lv_depth + 1.
            lv_cur = lv_cur && lv_c.
          WHEN '}'.
            lv_depth = lv_depth - 1.
            lv_cur = lv_cur && lv_c.
            IF lv_depth = 0.
              APPEND lv_cur TO lt_tools.
              CLEAR lv_cur.
            ENDIF.
          WHEN OTHERS.
            " keep characters only while inside an object; top-level
            " separators (commas, whitespace) between tools are dropped
            IF lv_depth > 0.
              lv_cur = lv_cur && lv_c.
            ENDIF.
        ENDCASE.
      ENDIF.
      lv_idx = lv_idx + 1.
    ENDWHILE.

    " Transform each OpenAI tool object into the Anthropic shape:
    "   {"type":"function","function":{"name":..,"parameters":{..}}}
    " -> {"name":..,"input_schema":{..}}
    DATA lv_result TYPE string.
    DATA lv_count  TYPE i.
    DATA lv_fpos   TYPE i.
    DATA lv_anth   TYPE string.
    DATA lv_cl     TYPE i.
    DATA(lv_lines) = lines( lt_tools ).
    LOOP AT lt_tools INTO DATA(lv_tool).
      lv_count = lv_count + 1.

      " The Anthropic tool object is the value of the OpenAI "function" key, i.e.
      " the balanced { ... } right after it, with "parameters" -> "input_schema".
      FIND FIRST OCCURRENCE OF '"function"' IN lv_tool MATCH OFFSET lv_fpos.
      IF sy-subrc <> 0.
        " Not in the expected wrapper - pass through unchanged.
        lv_anth = lv_tool.
      ELSE.
        lv_anth = extract_json_object( i_text = lv_tool i_offset = lv_fpos ).
        IF lv_anth IS INITIAL.
          lv_anth = lv_tool.
        ENDIF.
        " OpenAI "parameters" -> Anthropic "input_schema"
        REPLACE FIRST OCCURRENCE OF '"parameters"' IN lv_anth WITH '"input_schema"'.
      ENDIF.

      " Mark the last tool with cache_control to cache the whole tool block.
      " lv_anth ends exactly at its closing '}' (balanced extraction), so the
      " marker can be inserted just before it.
      IF lv_count = lv_lines.
        lv_cl = strlen( lv_anth ) - 1.
        lv_anth = lv_anth(lv_cl)
               && |, "cache_control": { '{' }"type": "ephemeral"{ '}' }|
               && '}'.
      ENDIF.

      IF lv_result IS NOT INITIAL.
        lv_result = lv_result && ','.
      ENDIF.
      lv_result = lv_result && lv_anth.
    ENDLOOP.

    rv_json = |[{ lv_result }]|.

  endmethod.


  method PARSE_ANTHROPIC_TOOL_USE.

    DATA lv_off  TYPE i.
    DATA lv_from TYPE i.

    " Walk every "type": "tool_use" marker. For each, the enclosing block's id,
    " name and input follow it (Anthropic emits "type" first in the block).
    DO.
      FIND FIRST OCCURRENCE OF REGEX '"type"\s*:\s*"tool_use"'
        IN SECTION OFFSET lv_from OF i_json MATCH OFFSET lv_off.
      IF sy-subrc <> 0.
        EXIT.
      ENDIF.

      DATA lv_id    TYPE string.
      DATA lv_name  TYPE string.
      DATA lv_input TYPE string.
      CLEAR: lv_id, lv_name, lv_input.

      DATA(lv_rest) = i_json+lv_off.
      FIND FIRST OCCURRENCE OF REGEX '"id"\s*:\s*"([^"]*)"'
        IN lv_rest SUBMATCHES lv_id.
      FIND FIRST OCCURRENCE OF REGEX '"name"\s*:\s*"([^"]*)"'
        IN lv_rest SUBMATCHES lv_name.

      " Capture the raw "input" object (balanced, string-aware) so nested braces
      " and braces inside string values are handled correctly.
      DATA lv_ipos TYPE i.
      FIND FIRST OCCURRENCE OF REGEX '"input"\s*:\s*\{'
        IN lv_rest MATCH OFFSET lv_ipos.
      IF sy-subrc = 0.
        lv_input = extract_json_object( i_text = lv_rest i_offset = lv_ipos ).
      ENDIF.

      IF lv_input IS INITIAL.
        lv_input = '{}'.
      ENDIF.

      IF lv_name IS NOT INITIAL.
        APPEND VALUE #( id        = lv_id
                        name      = lv_name
                        arguments = lv_input ) TO ct_tool_calls.
      ENDIF.

      " advance past this marker to find the next tool_use block
      lv_from = lv_off + 17.
    ENDDO.

  endmethod.


  method PARSE_RESPONSE.

    TYPES: BEGIN OF t_prompt_tokens_details,
             cached_tokens TYPE string,
           END OF t_prompt_tokens_details,
           BEGIN OF t_usage,
             prompt_tokens               TYPE string,
             completion_tokens           TYPE string,
             total_tokens                TYPE string,
             prompt_tokens_details       TYPE t_prompt_tokens_details,
             input_tokens                TYPE string,
             output_tokens               TYPE string,
             cache_read_input_tokens     TYPE string,
             cache_creation_input_tokens TYPE string,
           END OF t_usage,
           BEGIN OF t_content_block,
             type     TYPE string,
             text     TYPE string,
             thinking TYPE string,
           END OF t_content_block,
           t_content_blocks TYPE STANDARD TABLE OF t_content_block WITH NON-UNIQUE DEFAULT KEY,
           BEGIN OF t_anthropic_res,
             id          TYPE string,
             type        TYPE string,
             role        TYPE string,
             model       TYPE string,
             stop_reason TYPE string,
             content     TYPE t_content_blocks,
             usage       TYPE t_usage,
           END OF t_anthropic_res.

    TYPES: BEGIN OF t_oa_function,
             name      TYPE string,
             arguments TYPE string,
           END OF t_oa_function,
           BEGIN OF t_oa_tool_call,
             id       TYPE string,
             type     TYPE string,
             function TYPE t_oa_function,
           END OF t_oa_tool_call,
           t_oa_tool_calls TYPE STANDARD TABLE OF t_oa_tool_call WITH NON-UNIQUE DEFAULT KEY,
           BEGIN OF t_openai_message,
             role              TYPE string,
             content           TYPE string,
             reasoning_content TYPE string,
             tool_calls        TYPE t_oa_tool_calls,
           END OF t_openai_message,
           BEGIN OF t_openai_choice,
             index         TYPE string,
             message       TYPE t_openai_message,
             finish_reason TYPE string,
           END OF t_openai_choice,
           t_openai_choices TYPE STANDARD TABLE OF t_openai_choice WITH NON-UNIQUE DEFAULT KEY,
           BEGIN OF t_openai_res,
             id      TYPE string,
             object  TYPE string,
             created TYPE string,
             model   TYPE string,
             choices TYPE t_openai_choices,
             usage   TYPE t_usage,
           END OF t_openai_res.

    DATA: lv_provider     TYPE string,
          response        TYPE t_anthropic_res,
          openai_response TYPE t_openai_res.

    CLEAR: ev_tok_in, ev_tok_out, ev_tok_total, ev_tok_cached, et_tool_calls, ev_thinking.

    lv_provider = i_provider.
    TRANSLATE lv_provider TO UPPER CASE.

    IF lv_provider = 'OPENAI'.
      /ui2/cl_json=>deserialize( EXPORTING json = i_json CHANGING data = openai_response ).
      IF openai_response-usage-prompt_tokens IS NOT INITIAL.
        ev_tok_in     = openai_response-usage-prompt_tokens.
        ev_tok_out    = openai_response-usage-completion_tokens.
        ev_tok_total  = openai_response-usage-total_tokens.
        ev_tok_cached = openai_response-usage-prompt_tokens_details-cached_tokens.
      ENDIF.
      IF openai_response-choices IS NOT INITIAL.
        rv_answer = openai_response-choices[ 1 ]-message-content.
        DATA(lv_finish) = openai_response-choices[ 1 ]-finish_reason.
        IF lv_finish = 'error' OR lv_finish = 'length'.
          rv_answer = rv_answer
            && cl_abap_char_utilities=>newline
            && |[API error: response cut off, finish_reason={ lv_finish }]|.
        ENDIF.
        " Function calling: expose requested tool calls to the caller
        LOOP AT openai_response-choices[ 1 ]-message-tool_calls INTO DATA(ls_tc).
          APPEND VALUE #( id        = ls_tc-id
                          name      = ls_tc-function-name
                          arguments = ls_tc-function-arguments ) TO et_tool_calls.
        ENDLOOP.
      ELSE.
        rv_answer = i_json.
      ENDIF.
      RETURN.
    ENDIF.

    " Anthropic
    /ui2/cl_json=>deserialize( EXPORTING json = i_json CHANGING data = response ).
    IF response-usage-input_tokens IS NOT INITIAL.
      ev_tok_in    = response-usage-input_tokens.
      ev_tok_out   = response-usage-output_tokens.
      ev_tok_total = ev_tok_in + ev_tok_out.
    ELSEIF response-usage-prompt_tokens IS NOT INITIAL.
      ev_tok_in    = response-usage-prompt_tokens.
      ev_tok_out   = response-usage-completion_tokens.
      ev_tok_total = response-usage-total_tokens.
    ENDIF.
    " Prompt-cache accounting: cache_read = tokens served from cache (cheap),
    " cache_creation = tokens written to cache on this call.
    IF response-usage-cache_read_input_tokens IS NOT INITIAL.
      ev_tok_cached = response-usage-cache_read_input_tokens.
    ENDIF.

    " Concatenate all text content blocks (a tool_use turn may have a leading
    " text block, or none at all) for the user-facing answer.
    IF response-content IS NOT INITIAL.
      LOOP AT response-content INTO DATA(ls_block).
        IF ls_block-type = 'text' AND ls_block-text IS NOT INITIAL.
          IF rv_answer IS NOT INITIAL.
            rv_answer = rv_answer && cl_abap_char_utilities=>newline.
          ENDIF.
          rv_answer = rv_answer && ls_block-text.
        ELSEIF ls_block-type = 'thinking' AND ls_block-thinking IS NOT INITIAL.
          " Keep the reasoning separate from the user-facing answer.
          IF ev_thinking IS NOT INITIAL.
            ev_thinking = ev_thinking && cl_abap_char_utilities=>newline.
          ENDIF.
          ev_thinking = ev_thinking && ls_block-thinking.
        ENDIF.
      ENDLOOP.
    ENDIF.

    " Extract tool_use content blocks as tool calls. The "input" object is kept
    " as a raw JSON string in -arguments, matching how the tools parse arguments.
    parse_anthropic_tool_use(
      EXPORTING i_json        = i_json
      CHANGING  ct_tool_calls = et_tool_calls ).

    " If the model neither produced text nor requested a tool, surface the raw
    " payload so the caller can see what came back.
    IF rv_answer IS INITIAL AND et_tool_calls IS INITIAL.
      rv_answer = i_json.
    ENDIF.

  endmethod.
ENDCLASS.
