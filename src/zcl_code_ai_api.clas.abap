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

  class-methods ASK
    importing
      !I_PROMPT type STRING
      !I_SYSTEM_PROMPT type STRING optional
      !IT_HISTORY type ZCL_AI_MESSAGES=>TT_MESSAGES optional
      !I_DEST type TEXT255
      !I_MODEL type TEXT255
      !I_APIKEY type STRING
      !I_PROVIDER type STRING default 'ANTHROPIC'
      !I_PROMPT_CACHE_KEY type STRING optional
      !I_JSON_SCHEMA type STRING optional
      !I_TEMPERATURE type STRING optional
      !I_TOOLS_JSON type STRING optional
    exporting
      !EV_TOK_IN       type I
      !EV_TOK_OUT      type I
      !EV_TOK_TOTAL    type I
      !EV_TOK_CACHED   type I
      !ET_TOOL_CALLS   type TT_TOOL_CALLS
      !EV_RAW_REQUEST  type STRING
      !EV_RAW_RESPONSE type STRING
    returning
      value(RV_ANSWER) type STRING .
protected section.
private section.

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
    returning
      value(RV_ANSWER) type STRING .
ENDCLASS.



CLASS ZCL_CODE_AI_API IMPLEMENTATION.


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
      i_tools_json       = i_tools_json ).

    CALL METHOD cl_http_client=>create_by_destination
      EXPORTING  destination              = i_dest
      IMPORTING  client                   = o_client
      EXCEPTIONS destination_not_found    = 2
                 OTHERS                   = 5.

    IF sy-subrc = 2.
      rv_answer = 'Error: Destination not found (check SM59)'.
      RETURN.
    ELSEIF sy-subrc <> 0.
      rv_answer = |Error: cl_http_client rc={ sy-subrc }|.
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

    o_client->send(
      EXCEPTIONS http_communication_failure = 1
                 OTHERS                     = 5 ).

    IF sy-subrc <> 0.
      rv_answer = 'Error: HTTP send failed'.
      RETURN.
    ENDIF.

    o_client->receive(
      EXCEPTIONS http_communication_failure = 1
                 OTHERS                     = 4 ).

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
        et_tool_calls = et_tool_calls ).

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

    " Optional temperature field (e.g. "0.2" or "1.0") - omitted when not provided
    DATA lv_temp_field TYPE string.
    IF i_temperature IS NOT INITIAL.
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

    rv_json = |{ '{' }"model": "{ i_model }"{ lv_system_field }, "messages": [{ lv_messages }], "max_tokens": 20000{ lv_temp_field }{ lv_response_format }{ lv_tools_field }{ '}' }|.
    IF lv_provider = 'OPENAI' AND i_prompt_cache_key IS NOT INITIAL.
      lv_prompt_cache_key = i_prompt_cache_key.
      REPLACE ALL OCCURRENCES OF '\' IN lv_prompt_cache_key WITH '\\'.
      REPLACE ALL OCCURRENCES OF '"' IN lv_prompt_cache_key WITH '\"'.
      rv_json = |{ '{' }"model": "{ i_model }"{ lv_system_field }, "messages": [{ lv_messages }], "max_tokens": 20000, "prompt_cache_key": "{ lv_prompt_cache_key }"{ lv_temp_field }{ lv_response_format }{ lv_tools_field }{ '}' }|.
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
             type TYPE string,
             text TYPE string,
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

    CLEAR: ev_tok_in, ev_tok_out, ev_tok_total, ev_tok_cached, et_tool_calls.

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
