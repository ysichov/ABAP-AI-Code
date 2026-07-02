class ZCL_ABAPAI_LLM_CLIENT definition
  public
  create public .

public section.

  methods CONSTRUCTOR
    importing
      !I_MODEL type TEXT255
      !I_APIKEY type STRING
      !I_PROVIDER type STRING .
  methods ASK
    importing
      !I_PROMPT type STRING
      !I_SYSTEM_PROMPT type STRING optional
      !IT_HISTORY type ZCL_AI_MESSAGES=>TT_MESSAGES optional
      !I_JSON_SCHEMA type STRING optional
      !I_TEMPERATURE type STRING optional
    returning
      value(RV_ANSWER) type STRING .
  methods ASK_WITH_TOOLS
    importing
      !I_PROMPT type STRING
      !I_SYSTEM_PROMPT type STRING optional
      !IT_HISTORY type ZCL_AI_MESSAGES=>TT_MESSAGES optional
      !I_TOOLS_JSON type STRING
      !I_TEMPERATURE type STRING optional
    exporting
      !ET_TOOL_CALLS type ZCL_CODE_AI_API=>TT_TOOL_CALLS
    returning
      value(RV_ANSWER) type STRING .
  methods GET_LAST_SECONDS
    returning
      value(RV_SECONDS) type STRING .
  " Configured model id (e.g. 'claude-opus-4-8'), used by the
  " claude_compatible JSONL log to fill message.model.
  methods GET_MODEL
    returning
      value(RV_MODEL) type STRING .
  methods SET_TEMPERATURE
    importing
      !I_TEMPERATURE type STRING .
  methods SET_MAX_TOKENS
    importing
      !I_MAX_TOKENS type I .
  methods SET_THINKING_BUDGET
    importing
      !I_BUDGET type I .

  data MV_LAST_TOK_IN      type I .
  data MV_LAST_THINKING    type STRING .
  data MV_LAST_TOK_OUT     type I .
  data MV_LAST_TOK_CACHED  type I .
  data MV_LAST_TOK_CACHE_CREATED type I .
  data MV_LAST_RAW_REQUEST  type STRING .
  data MV_LAST_RAW_RESPONSE type STRING .

protected section.
private section.

  data MV_MODEL type TEXT255 .
  data MV_APIKEY type STRING .
  data MV_PROVIDER type STRING .
  data MV_PROMPT_CACHE_KEY type STRING .
  data MV_LAST_SECONDS type STRING .
  data MV_START type I .
  data MV_END type I .
  data MV_ELAPSED type P LENGTH 16 DECIMALS 2 .
  data MV_TOK_IN_STR type STRING .
  data MV_TOK_OUT_STR type STRING .
  data MV_TEMPERATURE type STRING .
  data MV_MAX_TOKENS  type I .
  data MV_THINKING_BUDGET type I .
ENDCLASS.



CLASS ZCL_ABAPAI_LLM_CLIENT IMPLEMENTATION.


  method ASK.

    CLEAR mv_last_seconds.
    CLEAR mv_last_tok_in.
    CLEAR mv_last_tok_out.
    CLEAR mv_last_tok_cached.
    CLEAR mv_last_tok_cache_created.
    GET RUN TIME FIELD mv_start.

    " Use explicitly passed temperature, fall back to client-level default
    DATA(lv_temperature) = COND string(
      WHEN i_temperature IS NOT INITIAL THEN i_temperature
      ELSE mv_temperature ).

    rv_answer = zcl_code_ai_api=>ask(
      EXPORTING
        i_prompt           = i_prompt
        i_system_prompt    = i_system_prompt
        it_history         = it_history
        i_model            = mv_model
        i_apikey           = mv_apikey
        i_provider         = mv_provider
        i_prompt_cache_key = mv_prompt_cache_key
        i_json_schema      = i_json_schema
        i_temperature      = lv_temperature
        i_max_tokens       = mv_max_tokens
        i_thinking_budget  = mv_thinking_budget
      IMPORTING
        ev_tok_in            = mv_last_tok_in
        ev_tok_out           = mv_last_tok_out
        ev_tok_cached        = mv_last_tok_cached
        ev_tok_cache_created = mv_last_tok_cache_created
        ev_thinking          = mv_last_thinking
        ev_raw_request       = mv_last_raw_request
        ev_raw_response      = mv_last_raw_response ).

    GET RUN TIME FIELD mv_end.
    mv_elapsed = ( mv_end - mv_start ) / 1000000.
    mv_last_seconds = |{ mv_elapsed }|.
    CONDENSE mv_last_seconds.

  endmethod.


  method ASK_WITH_TOOLS.

    CLEAR mv_last_seconds.
    CLEAR mv_last_tok_in.
    CLEAR mv_last_tok_out.
    CLEAR mv_last_tok_cached.
    CLEAR mv_last_tok_cache_created.
    GET RUN TIME FIELD mv_start.

    DATA(lv_temperature) = COND string(
      WHEN i_temperature IS NOT INITIAL THEN i_temperature
      ELSE mv_temperature ).

    rv_answer = zcl_code_ai_api=>ask(
      EXPORTING
        i_prompt           = i_prompt
        i_system_prompt    = i_system_prompt
        it_history         = it_history
        i_model            = mv_model
        i_apikey           = mv_apikey
        i_provider         = mv_provider
        i_prompt_cache_key = mv_prompt_cache_key
        i_temperature      = lv_temperature
        i_max_tokens       = mv_max_tokens
        i_tools_json       = i_tools_json
        i_thinking_budget  = mv_thinking_budget
      IMPORTING
        ev_tok_in            = mv_last_tok_in
        ev_tok_out           = mv_last_tok_out
        ev_tok_cached        = mv_last_tok_cached
        ev_tok_cache_created = mv_last_tok_cache_created
        et_tool_calls        = et_tool_calls
        ev_raw_request       = mv_last_raw_request
        ev_raw_response      = mv_last_raw_response
        ev_thinking          = mv_last_thinking ).

    GET RUN TIME FIELD mv_end.
    mv_elapsed = ( mv_end - mv_start ) / 1000000.
    mv_last_seconds = |{ mv_elapsed }|.
    CONDENSE mv_last_seconds.

  endmethod.


  method CONSTRUCTOR.

    mv_model    = i_model.
    mv_apikey   = i_apikey.
    mv_provider = i_provider.
    mv_prompt_cache_key = |{ sy-mandt }-{ sy-uname }-{ sy-datum }-{ sy-uzeit }|.

  endmethod.


  method GET_LAST_SECONDS.

    rv_seconds = mv_last_seconds.

  endmethod.


  method GET_MODEL.

    rv_model = mv_model.

  endmethod.


  method SET_TEMPERATURE.

    mv_temperature = i_temperature.

  endmethod.


  method SET_MAX_TOKENS.

    mv_max_tokens = i_max_tokens.

  endmethod.


  method SET_THINKING_BUDGET.

    mv_thinking_budget = i_budget.

  endmethod.
ENDCLASS.
