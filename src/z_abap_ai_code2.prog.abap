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

PARAMETERS p_dest   TYPE text255 LOWER CASE OBLIGATORY.        " SM59 destination
PARAMETERS p_model  TYPE text255 LOWER CASE DEFAULT 'gpt-4o'.
PARAMETERS p_apikey TYPE string LOWER CASE.
PARAMETERS p_tools  TYPE string LOWER CASE
                    DEFAULT 'C:\soft\GitHub\ABAP-AI-Code\TOOLS'. " schemas + prompts
PARAMETERS p_temp   TYPE string DEFAULT '0.2'.

START-OF-SELECTION.

  DATA(lo_popup) = NEW zcl_code_popup2(
    i_dest        = p_dest
    i_model       = p_model
    i_apikey      = p_apikey
    i_provider    = 'OPENAI'
    i_agents_path = p_tools
    i_temperature = p_temp ).

  lo_popup->show( ).

  " Keep the report alive so the dialog box stays interactive
  WRITE: / 'AI Tool popup started. Close the popup to leave.'.
