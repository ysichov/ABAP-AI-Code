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

SELECTION-SCREEN BEGIN OF BLOCK b_api WITH FRAME TITLE 'OpenAI'.
PARAMETERS: p_dest   TYPE text255 MEMORY ID dest,
            p_model  TYPE text255 MEMORY ID model DEFAULT 'gpt-4o',
            p_apikey TYPE text255 MEMORY ID api,
            p_tools  TYPE text255 OBLIGATORY,
            p_temp   TYPE text10  DEFAULT '0.2'.
SELECTION-SCREEN END OF BLOCK b_api.

INITIALIZATION.
  p_tools = 'C:/soft/GITHUB/ABAP-AI-CODE/TOOLS'.

  DATA lt_excl TYPE TABLE OF sy-ucomm.
  APPEND 'ONLI' TO lt_excl.
  CALL FUNCTION 'RS_SET_SELSCREEN_STATUS'
    EXPORTING  p_status  = sy-pfkey
    TABLES     p_exclude = lt_excl.

AT SELECTION-SCREEN.
  CHECK sy-ucomm IS INITIAL OR sy-ucomm = 'UCCHECK'.

  go_popup = NEW zcl_code_popup2(
    i_dest        = p_dest
    i_model       = p_model
    i_apikey      = CONV string( p_apikey )
    i_provider    = 'OPENAI'
    i_agents_path = CONV string( p_tools )
    i_temperature = CONV string( p_temp ) ).

  go_popup->show( ).
