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

" Provider key codes for the listbox; also passed straight to the API as the
" provider name (already upper-case, no provider_of() mapping needed).
TYPES ty_prov TYPE c LENGTH 12.

" Remembers the provider+key the model list was built for, so the live
" /v1/models call fires only when provider or key changes - not on every Enter.
DATA gv_loaded_key TYPE string.
" Cached model listbox values - re-applied on every PBO so the list persists
" across screen round-trips (e.g. toggling the thinking checkbox).
DATA gt_model_vrm TYPE vrm_values.

SELECTION-SCREEN BEGIN OF BLOCK b_api WITH FRAME TITLE TEXT-001.
PARAMETERS: p_prov   TYPE ty_prov AS LISTBOX VISIBLE LENGTH 30
                     USER-COMMAND prov DEFAULT 'ANTHROPIC',
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
  " Provider listbox values must be (re)set on every PBO, otherwise they are
  " lost after a round-trip and the selection does not stick. The text shows
  " the base URL the provider resolves to.
  DATA lt_prov TYPE vrm_values.
  lt_prov = VALUE #(
    ( key = 'ANTHROPIC' text = 'https://api.anthropic.com' )
    ( key = 'OPENAI'    text = 'https://api.openai.com' )
    ( key = 'MISTRAL'   text = 'https://api.mistral.ai' ) ).
  CALL FUNCTION 'VRM_SET_VALUES'
    EXPORTING id     = 'P_PROV'
              values = lt_prov.

  " Re-fetch the model list live only when provider or key changed; otherwise
  " reuse the cached list. Re-fetch is skipped on plain Enter (state unchanged).
  DATA(lv_state) = |{ p_prov }\|{ p_apikey }|.
  IF p_apikey IS NOT INITIAL AND gv_loaded_key <> lv_state.

    DATA: lt_ids TYPE stringtab,
          lv_err TYPE string.
    zcl_code_ai_api=>list_models(
      EXPORTING i_url      = |{ zcl_code_ai_api=>base_url( CONV string( p_prov ) ) }/v1/models|
                i_apikey   = CONV string( p_apikey )
                i_provider = CONV string( p_prov )
      IMPORTING et_ids     = lt_ids
                e_error    = lv_err ).

    CLEAR gt_model_vrm.
    LOOP AT lt_ids INTO DATA(lv_id).
      APPEND VALUE #( key = lv_id text = lv_id ) TO gt_model_vrm.
    ENDLOOP.

    IF lt_ids IS NOT INITIAL.
      " Default to a haiku model when the current one is not in the new list.
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
      " Remember the loaded state only on success, so a failed call is retried.
      gv_loaded_key = lv_state.
    ELSE.
      " Fetch failed / empty: clear the stale model and surface the error.
      CLEAR p_model.
      IF lv_err IS NOT INITIAL.
        MESSAGE lv_err TYPE 'W'.
      ENDIF.
    ENDIF.
  ENDIF.

  " Model listbox values, like the provider list, must be set on every PBO.
  CALL FUNCTION 'VRM_SET_VALUES'
    EXPORTING id     = 'P_MODEL'
              values = gt_model_vrm.

AT SELECTION-SCREEN.
  CHECK sy-ucomm IS INITIAL OR sy-ucomm = 'UCCHECK'.

  " Launch the popup only once every required field is filled; otherwise just
  " stay on the screen (Enter still refreshes the model listbox above).
  IF p_apikey IS INITIAL OR p_model IS INITIAL.
    RETURN.
  ENDIF.

  go_popup = NEW zcl_code_popup2(
    i_model       = p_model
    i_apikey      = CONV string( p_apikey )
    i_provider    = CONV string( p_prov )
    i_agents_path = CONV string( p_tools )
    i_temperature = CONV string( p_temp )
    i_max_tokens  = COND i( WHEN p_nomax = 'X' THEN 0 ELSE p_maxt )
    " Extended thinking only applies to Anthropic; 0 = off.
    i_thinking_budget = COND i( WHEN p_think = 'X' AND p_prov = 'ANTHROPIC' THEN p_thbud ELSE 0 )
    i_log_path    = CONV string( p_log ) ).

  go_popup->show( ).
