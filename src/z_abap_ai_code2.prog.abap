REPORT z_abap_ai_code2.

"---------------------------------------------------------------------
" Z_ABAP_AI_CODE2 - new tool-based agent runner (OpenAI function calling)
"
" Runs in parallel to the legacy proto-tag flow:
"   legacy flow -> AGENTS folder (object_detector / task_orchestrator / ...)
"   this flow   -> TOOLS  folder (<tool_name>.json schemas + .md prompts)
"
" Pipeline: prompt -> LLM with tools -> tool_calls -> ZCL_AI_TOOL_FACTORY
"           -> ZCL_AITOOL_* -> results back to LLM -> final answer
"---------------------------------------------------------------------

PARAMETERS p_prompt TYPE c LENGTH 255 LOWER CASE OBLIGATORY.
PARAMETERS p_dest   TYPE text255 LOWER CASE OBLIGATORY.        " SM59 destination
PARAMETERS p_model  TYPE text255 LOWER CASE DEFAULT 'gpt-4o'.
PARAMETERS p_apikey TYPE string LOWER CASE.
PARAMETERS p_tools  TYPE string LOWER CASE
                    DEFAULT 'C:\soft\GitHub\ABAP-AI-Code\TOOLS'. " schemas + prompts
PARAMETERS p_temp   TYPE string DEFAULT '0.2'.

START-OF-SELECTION.

  DATA(lo_llm) = NEW zcl_llm_client(
    i_dest     = p_dest
    i_model    = p_model
    i_apikey   = p_apikey
    i_provider = 'OPENAI' ).
  lo_llm->set_temperature( p_temp ).

  " The new flow reads tool schemas/prompts from TOOLS, not AGENTS.
  " io_prompts/io_messages stay unbound - tools only need llm + files.
  DATA(lo_context) = NEW zcl_ai_tool_context(
    io_llm        = lo_llm
    i_agents_path = p_tools ).

  DATA(lo_runner) = NEW zcl_ai_tool_runner(
    io_llm     = lo_llm
    io_context = lo_context ).

  " Show what the factory discovered before running
  DATA(lt_tools) = zcl_ai_tool_factory=>get_all_tools( ).
  WRITE: / |Discovered tools: { lines( lt_tools ) }|.
  LOOP AT lt_tools INTO DATA(ls_tool).
    WRITE: / |  - { ls_tool-tool_name }|.
  ENDLOOP.
  ULINE.

  DATA(lv_answer) = lo_runner->run( CONV string( p_prompt ) ).

  WRITE: / 'ANSWER:'.
  SPLIT lv_answer AT cl_abap_char_utilities=>newline INTO TABLE DATA(lt_lines).
  LOOP AT lt_lines INTO DATA(lv_line).
    WRITE: / lv_line.
  ENDLOOP.
