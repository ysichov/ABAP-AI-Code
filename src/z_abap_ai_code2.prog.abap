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

  " Populate the model listbox (Anthropic, for now). The key is not yet in
  " p_apikey here (MEMORY ID is applied later), so read it straight from
  " SAP memory under its parameter id 'api'.
  DATA lv_apikey TYPE string.
  GET PARAMETER ID 'api' FIELD lv_apikey.

  DATA: lt_ids TYPE stringtab,
        lv_err TYPE string.
  IF lv_apikey IS NOT INITIAL.
    zcl_code_ai_api=>list_models(
      EXPORTING i_url      = 'https://api.anthropic.com/v1/models'
                i_apikey   = lv_apikey
                i_provider = 'ANTHROPIC'
      IMPORTING et_ids     = lt_ids
                e_error    = lv_err ).
  ENDIF.

  " Fallback to known aliases if no key yet or the live call failed.
  IF lt_ids IS INITIAL.
    lt_ids = VALUE #( ( `claude-haiku-4-5` )
                      ( `claude-sonnet-4-6` )
                      ( `claude-opus-4-8` ) ).
  ENDIF.

  DATA lt_vrm TYPE vrm_values.
  LOOP AT lt_ids INTO DATA(lv_id).
    APPEND VALUE #( key = lv_id text = lv_id ) TO lt_vrm.
  ENDLOOP.
  CALL FUNCTION 'VRM_SET_VALUES'
    EXPORTING id     = 'P_MODEL'
              values = lt_vrm.

  " Default to a haiku model.
  LOOP AT lt_ids INTO lv_id WHERE table_line CS 'haiku'.
    p_model = lv_id.
    EXIT.
  ENDLOOP.
  IF p_model IS INITIAL.
    p_model = lt_ids[ 1 ].
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
