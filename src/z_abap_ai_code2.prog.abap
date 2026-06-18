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

" Set once the model listbox has been filled, so the live /v1/models call
" fires only once - not on every screen refresh. (The key is not needed for
" the models endpoint.)
DATA gv_models_loaded TYPE abap_bool.

SELECTION-SCREEN BEGIN OF BLOCK b_api WITH FRAME TITLE TEXT-001.
PARAMETERS: p_anth RADIOBUTTON GROUP api USER-COMMAND prov,
            p_oai  RADIOBUTTON GROUP api DEFAULT 'X'.

PARAMETERS: p_dest   TYPE text255 MEMORY ID dest,
            p_model  TYPE text255 AS LISTBOX VISIBLE LENGTH 45 MEMORY ID model,
            p_apikey TYPE text255 MEMORY ID api,
            p_tools  TYPE text255 OBLIGATORY,
            p_temp   TYPE text10  DEFAULT '0.2',
            p_maxt   TYPE i       DEFAULT 20000,
            p_nomax  AS CHECKBOX,
            p_think  AS CHECKBOX,                 " enable extended thinking (Anthropic)
            p_thbud  TYPE i       DEFAULT 10000,  " thinking token budget
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
  " Populate the model listbox live (Anthropic, for now). The /v1/models
  " endpoint does not need the key, so fetch as soon as Anthropic is chosen.
  " Fires only once (cached in gv_models_loaded) - plain Enter does not re-hit
  " the API.
  IF p_anth = 'X' AND gv_models_loaded = abap_false.

    DATA: lt_ids TYPE stringtab,
          lv_err TYPE string.
    zcl_code_ai_api=>list_models(
      EXPORTING i_url      = 'https://api.anthropic.com/v1/models'
                i_apikey   = CONV string( p_apikey )
                i_provider = 'ANTHROPIC'
      IMPORTING et_ids     = lt_ids
                e_error    = lv_err ).

    " Only fill the listbox if the live call returned something. On failure
    " leave it empty (no static defaults) and retry on the next refresh.
    IF lt_ids IS NOT INITIAL.
      DATA lt_vrm TYPE vrm_values.
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
    ENDIF.
  ELSEIF p_anth <> 'X'.
    " Not Anthropic: clear the leftover Anthropic list and force a reload when
    " Anthropic is selected again.
    CALL FUNCTION 'VRM_SET_VALUES'
      EXPORTING id     = 'P_MODEL'
                values = VALUE vrm_values( ).
    CLEAR: p_model, gv_models_loaded.
  ENDIF.

AT SELECTION-SCREEN.
  CHECK sy-ucomm IS INITIAL OR sy-ucomm = 'UCCHECK'.

  " Launch the popup only once every required field is filled; otherwise just
  " stay on the screen (Enter still refreshes the model listbox above).
  IF p_dest IS INITIAL OR p_apikey IS INITIAL OR p_model IS INITIAL.
    RETURN.
  ENDIF.

  go_popup = NEW zcl_code_popup2(
    i_dest        = p_dest
    i_model       = p_model
    i_apikey      = CONV string( p_apikey )
    i_provider    = COND string( WHEN p_oai = 'X' THEN 'OPENAI' ELSE 'ANTHROPIC' )
    i_agents_path = CONV string( p_tools )
    i_temperature = CONV string( p_temp )
    i_max_tokens  = COND i( WHEN p_nomax = 'X' THEN 0 ELSE p_maxt )
    " Extended thinking only applies to Anthropic; 0 = off.
    i_thinking_budget = COND i( WHEN p_think = 'X' AND p_anth = 'X' THEN p_thbud ELSE 0 )
    i_log_path    = CONV string( p_log ) ).

  go_popup->show( ).
