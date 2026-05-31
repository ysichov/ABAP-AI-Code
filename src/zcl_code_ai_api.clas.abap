class ZCL_CODE_AI_API definition
  public
  create public .

public section.

  class-methods ASK
    importing
      !I_PROMPT type STRING
      !I_DEST type TEXT255
      !I_MODEL type TEXT255
      !I_APIKEY type STRING
      !I_PROVIDER type STRING default 'ANTHROPIC'
      !I_PROMPT_CACHE_KEY type STRING optional
    returning
      value(RV_ANSWER) type STRING .
protected section.
private section.

  class-methods BUILD_PAYLOAD
    importing
      !I_PROMPT type STRING
      !I_MODEL type TEXT255
      !I_PROVIDER type STRING
      !I_PROMPT_CACHE_KEY type STRING optional
    returning
      value(RV_JSON) type STRING .
  class-methods PARSE_RESPONSE
    importing
      !I_JSON type STRING
      !I_PROVIDER type STRING
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
      i_model            = i_model
      i_provider         = lv_provider
      i_prompt_cache_key = i_prompt_cache_key ).

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
    rv_answer = parse_response( i_json = lv_response i_provider = lv_provider ).

  endmethod.


  method BUILD_PAYLOAD.

    DATA: lv_prompt           TYPE string,
          lv_prompt_cache_key TYPE string,
          lv_provider         TYPE string,
          lv_cr               TYPE c LENGTH 1.

    lv_provider = i_provider.
    TRANSLATE lv_provider TO UPPER CASE.
    lv_cr = cl_abap_char_utilities=>cr_lf(1).

    lv_prompt = i_prompt.
    REPLACE ALL OCCURRENCES OF '\' IN lv_prompt WITH '\\'.
    REPLACE ALL OCCURRENCES OF '"' IN lv_prompt WITH '\"'.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf IN lv_prompt WITH '\n'.
    REPLACE ALL OCCURRENCES OF lv_cr IN lv_prompt WITH '\r'.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>newline IN lv_prompt WITH '\n'.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>form_feed IN lv_prompt WITH '\f'.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>horizontal_tab IN lv_prompt WITH '\t'.

    rv_json = |{ '{' }"model": "{ i_model }", "messages": [{ '{' }"role": "user", "content": "{ lv_prompt }"{ '}' }], "max_tokens": 2000{ '}' }|.
    IF lv_provider = 'OPENAI' AND i_prompt_cache_key IS NOT INITIAL.
      lv_prompt_cache_key = i_prompt_cache_key.
      REPLACE ALL OCCURRENCES OF '\' IN lv_prompt_cache_key WITH '\\'.
      REPLACE ALL OCCURRENCES OF '"' IN lv_prompt_cache_key WITH '\"'.
      rv_json = |{ '{' }"model": "{ i_model }", "messages": [{ '{' }"role": "user", "content": "{ lv_prompt }"{ '}' }], "max_tokens": 2000, "prompt_cache_key": "{ lv_prompt_cache_key }"{ '}' }|.
    ENDIF.

  endmethod.


  method PARSE_RESPONSE.

    TYPES: BEGIN OF t_prompt_tokens_details,
             cached_tokens TYPE string,
           END OF t_prompt_tokens_details,
           BEGIN OF t_usage,
             prompt_tokens         TYPE string,
             completion_tokens     TYPE string,
             total_tokens          TYPE string,
             prompt_tokens_details TYPE t_prompt_tokens_details,
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

    TYPES: BEGIN OF t_openai_message,
             role              TYPE string,
             content           TYPE string,
             reasoning_content TYPE string,
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
          openai_response TYPE t_openai_res,
          lv_text         TYPE string,
          lv_usage_info   TYPE string.

    lv_provider = i_provider.
    TRANSLATE lv_provider TO UPPER CASE.

    IF lv_provider = 'OPENAI'.
      /ui2/cl_json=>deserialize( EXPORTING json = i_json CHANGING data = openai_response ).
      IF openai_response-choices IS NOT INITIAL.
        lv_text = openai_response-choices[ 1 ]-message-content.
        IF openai_response-usage-total_tokens IS NOT INITIAL.
          lv_usage_info = |---| && cl_abap_char_utilities=>newline
                       && |Tokens: prompt={ openai_response-usage-prompt_tokens } completion={ openai_response-usage-completion_tokens } total={ openai_response-usage-total_tokens } cached={ openai_response-usage-prompt_tokens_details-cached_tokens }|.
          rv_answer = lv_text && cl_abap_char_utilities=>newline && cl_abap_char_utilities=>newline && lv_usage_info.
        ELSE.
          rv_answer = lv_text.
        ENDIF.
      ELSE.
        rv_answer = i_json.
      ENDIF.
      RETURN.
    ENDIF.

    /ui2/cl_json=>deserialize( EXPORTING json = i_json CHANGING data = response ).

    IF response-content IS NOT INITIAL.
      lv_text = response-content[ 1 ]-text.
      IF response-usage-total_tokens IS NOT INITIAL.
        lv_usage_info = |---| && cl_abap_char_utilities=>newline
                     && |Tokens: input={ response-usage-prompt_tokens } output={ response-usage-completion_tokens } total={ response-usage-total_tokens }|.
        rv_answer = lv_text && cl_abap_char_utilities=>newline && cl_abap_char_utilities=>newline && lv_usage_info.
      ELSE.
        rv_answer = lv_text.
      ENDIF.
    ELSE.
      rv_answer = i_json.
    ENDIF.

  endmethod.
ENDCLASS.
