REPORT z_abap_ai_code2.

"---------------------------------------------------------------------
" Z_ABAP_AI_CODE2 - new tool-based agent runner (OpenAI function calling)
"
" Runs in parallel to the legacy proto-tag flow:
"   legacy flow -> AGENTS folder (object_detector / task_orchestrator / ...)
"   this flow   -> TOOLS  folder (<tool_name>.json schemas + .md prompts)
"
" UI: same popup as the legacy program (copied as ZCL_CODE_POPUP2), but
" ASK_AI drives the agentic loop: prompt -> LLM with tools -> tool_calls
" -> ZCL_AI_TOOL_FACTORY -> ZCL_AITOOL_* -> results back -> final answer
"---------------------------------------------------------------------

DATA go_popup TYPE REF TO zcl_code_popup2.

" Cache so the model list is fetched once per (provider+key), not on every PBO.
DATA: gv_models_loaded TYPE abap_bool,
      gv_loaded_key    TYPE string.

*&---------------------------------------------------------------------*
*& Local helper: live Anthropic model list (GET /v1/models, direct,
*& bypassing the SM59 destination which only proxies /v1/messages).
*&---------------------------------------------------------------------*
CLASS lcl_models DEFINITION.
  PUBLIC SECTION.
    CLASS-METHODS fetch_anthropic
      IMPORTING i_apikey TYPE string
      EXPORTING et_ids   TYPE stringtab
                e_error  TYPE string.
ENDCLASS.

CLASS lcl_models IMPLEMENTATION.
  METHOD fetch_anthropic.

    DATA lo_client TYPE REF TO if_http_client.

    cl_http_client=>create_by_url(
      EXPORTING url    = 'https://api.anthropic.com/v1/models'
                ssl_id = 'ANONYM'
      IMPORTING client = lo_client
      EXCEPTIONS OTHERS = 4 ).
    IF sy-subrc <> 0.
      e_error = |create_by_url failed rc={ sy-subrc }|.
      RETURN.
    ENDIF.

    lo_client->request->set_method( 'GET' ).
    lo_client->request->set_header_field( name = 'anthropic-version' value = '2023-06-01' ).
    lo_client->request->set_header_field( name = 'x-api-key'         value = i_apikey ).
    lo_client->propertytype_logon_popup = if_http_client=>co_disabled.

    lo_client->send( EXCEPTIONS OTHERS = 2 ).
    IF sy-subrc <> 0.
      e_error = 'HTTP send failed'.
      RETURN.
    ENDIF.
    lo_client->receive( EXCEPTIONS OTHERS = 2 ).
    IF sy-subrc <> 0.
      e_error = 'HTTP receive failed'.
      RETURN.
    ENDIF.

    DATA(lv_json) = lo_client->response->get_cdata( ).

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
      e_error = |Unexpected response: { lv_json(nmin( val1 = strlen( lv_json ) val2 = 150 )) }|.
    ENDIF.

  ENDMETHOD.
ENDCLASS.

SELECTION-SCREEN BEGIN OF BLOCK b_api WITH FRAME TITLE TEXT-001.
PARAMETERS: p_anth RADIOBUTTON GROUP api,
            p_oai  RADIOBUTTON GROUP api DEFAULT 'X'.

PARAMETERS: p_dest   TYPE text255 MEMORY ID dest,
            p_model  TYPE text255 AS LISTBOX VISIBLE LENGTH 45 MEMORY ID model,
            p_apikey TYPE text255 MEMORY ID api,
            p_tools  TYPE text255 OBLIGATORY,
            p_temp   TYPE text10  DEFAULT '0.2',
            p_maxt   TYPE i       DEFAULT 20000,
            p_nomax  AS CHECKBOX,
            p_log    TYPE text255.
SELECTION-SCREEN END OF BLOCK b_api.

INITIALIZATION.
  p_tools = 'C:/soft/GITHUB/ABAP-AI-CODE/TOOLS'.
  p_log   = 'C:/temp/ABAP_AI_CODE/LOGS'.

  DATA lt_excl TYPE TABLE OF sy-ucomm.
  APPEND 'ONLI' TO lt_excl.
  CALL FUNCTION 'RS_SET_SELSCREEN_STATUS'
    EXPORTING  p_status  = sy-pfkey
    TABLES     p_exclude = lt_excl.

AT SELECTION-SCREEN OUTPUT.
  " Populate the model listbox for Anthropic once the key is known.
  " Re-fetch only when the key changes (cached via gv_loaded_key).
  IF p_anth = 'X' AND p_apikey IS NOT INITIAL
     AND ( gv_models_loaded = abap_false OR gv_loaded_key <> CONV string( p_apikey ) ).

    DATA: lt_ids TYPE stringtab,
          lv_err TYPE string.
    lcl_models=>fetch_anthropic(
      EXPORTING i_apikey = CONV string( p_apikey )
      IMPORTING et_ids   = lt_ids
                e_error  = lv_err ).

    " Fallback to known aliases if the live call failed (offline / SSL / proxy).
    IF lt_ids IS INITIAL.
      lt_ids = VALUE #( ( `claude-haiku-4-5` )
                        ( `claude-sonnet-4-6` )
                        ( `claude-opus-4-8` ) ).
    ENDIF.

    DATA lt_vrm TYPE vrm_values.
    CLEAR lt_vrm.
    LOOP AT lt_ids INTO DATA(lv_id).
      APPEND VALUE #( key = lv_id text = lv_id ) TO lt_vrm.
    ENDLOOP.
    CALL FUNCTION 'VRM_SET_VALUES'
      EXPORTING id     = 'P_MODEL'
                values = lt_vrm.

    " Default to a haiku model when nothing valid is selected yet.
    IF p_model IS INITIAL OR NOT line_exists( lt_ids[ table_line = p_model ] ).
      CLEAR p_model.
      LOOP AT lt_ids INTO lv_id WHERE table_line CS 'haiku'.
        p_model = lv_id.
        EXIT.
      ENDLOOP.
      IF p_model IS INITIAL.
        p_model = lt_ids[ 1 ].
      ENDIF.
    ENDIF.

    gv_models_loaded = abap_true.
    gv_loaded_key    = CONV string( p_apikey ).
  ENDIF.

AT SELECTION-SCREEN.
  CHECK sy-ucomm IS INITIAL OR sy-ucomm = 'UCCHECK'.

  go_popup = NEW zcl_code_popup2(
    i_dest        = p_dest
    i_model       = p_model
    i_apikey      = CONV string( p_apikey )
    i_provider    = COND string( WHEN p_oai = 'X' THEN 'OPENAI' ELSE 'ANTHROPIC' )
    i_agents_path = CONV string( p_tools )
    i_temperature = CONV string( p_temp )
    i_max_tokens  = COND i( WHEN p_nomax = 'X' THEN 0 ELSE p_maxt )
    i_log_path    = CONV string( p_log ) ).

  go_popup->show( ).
