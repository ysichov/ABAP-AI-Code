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
protected section.
private section.

  data MV_DEST type TEXT255 .
  data MV_MODEL type TEXT255 .
  data MV_APIKEY type STRING .
  data MV_PROVIDER type STRING .
  data MV_PROMPT_CACHE_KEY type STRING .
  data MV_LAST_SECONDS type STRING .
ENDCLASS.



CLASS ZCL_LLM_CLIENT IMPLEMENTATION.


  method ASK.

    DATA lv_start TYPE i.
    DATA lv_end TYPE i.
    DATA lv_elapsed TYPE p LENGTH 16 DECIMALS 2.

    CLEAR mv_last_seconds.
    GET RUN TIME FIELD lv_start.

    rv_answer = zcl_code_ai_api=>ask(
      i_prompt           = i_prompt
      i_dest             = mv_dest
      i_model            = mv_model
      i_apikey           = mv_apikey
      i_provider         = mv_provider
      i_prompt_cache_key = mv_prompt_cache_key ).

    GET RUN TIME FIELD lv_end.
    lv_elapsed = ( lv_end - lv_start ) / 1000000.
    mv_last_seconds = |{ lv_elapsed }|.
    CONDENSE mv_last_seconds.

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
