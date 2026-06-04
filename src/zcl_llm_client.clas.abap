class ZCL_LLM_CLIENT definition
  public
  create public .

public section.

  methods CONSTRUCTOR
    importing
      !I_DEST type TEXT255
      !I_MODEL type TEXT255
      !I_APIKEY type STRING
      !I_PROVIDER type STRING .
  methods ASK
    importing
      !I_PROMPT type STRING
    returning
      value(RV_ANSWER) type STRING .
  methods GET_LAST_SECONDS
    returning
      value(RV_SECONDS) type STRING .

  data MV_LAST_TOK_IN  type I .
  data MV_LAST_TOK_OUT type I .

protected section.
private section.

  data MV_DEST type TEXT255 .
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
ENDCLASS.



CLASS ZCL_LLM_CLIENT IMPLEMENTATION.


  method ASK.

    CLEAR mv_last_seconds.
    CLEAR mv_last_tok_in.
    CLEAR mv_last_tok_out.
    GET RUN TIME FIELD mv_start.

    rv_answer = zcl_code_ai_api=>ask(
      i_prompt           = i_prompt
      i_dest             = mv_dest
      i_model            = mv_model
      i_apikey           = mv_apikey
      i_provider         = mv_provider
      i_prompt_cache_key = mv_prompt_cache_key ).

    GET RUN TIME FIELD mv_end.
    mv_elapsed = ( mv_end - mv_start ) / 1000000.
    mv_last_seconds = |{ mv_elapsed }|.
    CONDENSE mv_last_seconds.

    " Parse token counts from embedded usage info in the answer
    CLEAR mv_tok_in_str.
    CLEAR mv_tok_out_str.
    FIND FIRST OCCURRENCE OF REGEX 'input=([0-9]+)' IN rv_answer SUBMATCHES mv_tok_in_str.
    IF mv_tok_in_str IS INITIAL.
      FIND FIRST OCCURRENCE OF REGEX 'prompt=([0-9]+)' IN rv_answer SUBMATCHES mv_tok_in_str.
    ENDIF.
    FIND FIRST OCCURRENCE OF REGEX 'output=([0-9]+)' IN rv_answer SUBMATCHES mv_tok_out_str.
    IF mv_tok_out_str IS INITIAL.
      FIND FIRST OCCURRENCE OF REGEX 'completion=([0-9]+)' IN rv_answer SUBMATCHES mv_tok_out_str.
    ENDIF.
    IF mv_tok_in_str IS NOT INITIAL.
      mv_last_tok_in = mv_tok_in_str.
    ENDIF.
    IF mv_tok_out_str IS NOT INITIAL.
      mv_last_tok_out = mv_tok_out_str.
    ENDIF.

  endmethod.


  method CONSTRUCTOR.

    mv_dest     = i_dest.
    mv_model    = i_model.
    mv_apikey   = i_apikey.
    mv_provider = i_provider.
    mv_prompt_cache_key = |{ sy-mandt }-{ sy-uname }-{ sy-datum }-{ sy-uzeit }|.

  endmethod.


  method GET_LAST_SECONDS.

    rv_seconds = mv_last_seconds.

  endmethod.
ENDCLASS.
