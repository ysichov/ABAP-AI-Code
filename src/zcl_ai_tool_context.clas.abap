CLASS zcl_ai_tool_context DEFINITION
  PUBLIC
  CREATE PUBLIC.

  PUBLIC SECTION.
    " Shared dependencies handed to every tool by the factory
    DATA mo_llm         TYPE REF TO zcl_abapai_llm_client.
    DATA mo_prompts     TYPE REF TO zcl_ai_agents_prompts.
    DATA mo_messages    TYPE REF TO zcl_ai_messages.
    DATA mv_agents_path TYPE string.

    METHODS constructor
      IMPORTING
        !io_llm         TYPE REF TO zcl_abapai_llm_client
        !io_prompts     TYPE REF TO zcl_ai_agents_prompts OPTIONAL
        !io_messages    TYPE REF TO zcl_ai_messages OPTIONAL
        !i_agents_path  TYPE string.

    " Reads <filename> from the agents folder. Returns '' when missing.
    METHODS read_agent_file
      IMPORTING
        !i_filename       TYPE string
      RETURNING VALUE(rv_content) TYPE string.

    " Back-reference to the orchestrator runner, set once by the runner. Typed as
    " a generic object ref ON PURPOSE: a concrete REF TO zcl_ai_tool_runner here
    " would create a class<->class cycle (runner already references this context),
    " which makes activation order fragile. The actual call is dynamic in ask( ).
    METHODS set_host
      IMPORTING
        !io_host TYPE REF TO object.

    " THE entry point a tool must use for its own (sub-agent) LLM call. Routed
    " through the runner so the call is shown in the progress panel, logged and
    " counted in the token totals - just like the orchestrator's calls. A tool
    " must NEVER call mo_llm->ask directly, otherwise it becomes invisible to the
    " orchestrator (no step, no log, no token count). Falls back to the raw
    " client only when no runner is attached (e.g. unit tests).
    METHODS ask
      IMPORTING
        !i_label         TYPE string OPTIONAL
        !i_prompt        TYPE string
        !i_system_prompt TYPE string OPTIONAL
      RETURNING VALUE(rv_answer) TYPE string.

  PROTECTED SECTION.
  PRIVATE SECTION.
    TYPES tt_strings TYPE STANDARD TABLE OF string WITH NON-UNIQUE DEFAULT KEY.
    " Generic ref to the runner (breaks the class<->class cycle - see set_host).
    DATA mo_host TYPE REF TO object.
ENDCLASS.



CLASS zcl_ai_tool_context IMPLEMENTATION.


  METHOD constructor.

    mo_llm         = io_llm.
    mo_prompts     = io_prompts.
    mo_messages    = io_messages.
    mv_agents_path = i_agents_path.

  ENDMETHOD.


  METHOD set_host.

    mo_host = io_host.

  ENDMETHOD.


  METHOD ask.

    IF mo_host IS BOUND.
      " Instrumented path: shown in the panel, logged, counted in Total. Called
      " dynamically so this class carries no compile-time dependency on the runner
      " (avoids the activation-order cycle).
      CALL METHOD mo_host->('AGENT_ASK')
        EXPORTING
          i_label         = i_label
          i_prompt        = i_prompt
          i_system_prompt = i_system_prompt
        RECEIVING
          rv_answer       = rv_answer.
    ELSE.
      " Fallback (no runner attached, e.g. unit tests): raw client call.
      rv_answer = mo_llm->ask(
        i_prompt        = i_prompt
        i_system_prompt = i_system_prompt ).
    ENDIF.

  ENDMETHOD.


  METHOD read_agent_file.

    DATA lt_lines TYPE tt_strings.

    DATA(lv_path) = mv_agents_path.
    REPLACE ALL OCCURRENCES OF '\' IN lv_path WITH '/'.
    IF lv_path IS NOT INITIAL.
      DATA(lv_last_offset) = strlen( lv_path ) - 1.
      IF lv_path+lv_last_offset(1) <> '/'.
        lv_path = lv_path && '/'.
      ENDIF.
    ENDIF.
    lv_path = lv_path && i_filename.

    cl_gui_frontend_services=>gui_upload(
      EXPORTING
        filename = lv_path
        filetype = 'ASC'
      CHANGING
        data_tab = lt_lines
      EXCEPTIONS
        OTHERS   = 1 ).

    IF sy-subrc <> 0.
      CLEAR rv_content.
      RETURN.
    ENDIF.

    LOOP AT lt_lines INTO DATA(lv_line).
      IF rv_content IS NOT INITIAL.
        rv_content = rv_content && cl_abap_char_utilities=>newline.
      ENDIF.
      rv_content = rv_content && lv_line.
    ENDLOOP.

  ENDMETHOD.
ENDCLASS.
