CLASS zcl_ai_tool_runner DEFINITION
  PUBLIC
  CREATE PUBLIC.

  PUBLIC SECTION.
    CONSTANTS c_max_iterations TYPE i VALUE 8.

    METHODS constructor
      IMPORTING
        !io_llm        TYPE REF TO zcl_abapai_llm_client
        !io_context    TYPE REF TO zcl_ai_tool_context
        !io_prompts    TYPE REF TO zcl_ai_agents_prompts OPTIONAL
        !io_ui         TYPE REF TO zcl_code_popup2 OPTIONAL.

    " Agentic loop: LLM -> tool_calls -> execute -> results back -> LLM ...
    " Ends when the LLM answers without tool calls or c_max_iterations is hit.
    METHODS run
      IMPORTING
        !i_prompt        TYPE string
      RETURNING VALUE(rv_answer) TYPE string.

    " Access to the logged messages (for History popup, logging, etc.)
    METHODS get_messages
      RETURNING VALUE(ro_messages) TYPE REF TO zcl_ai_messages.

    " Reset conversation history (new session)
    METHODS clear_session.

    " Progress panel (middle pane): same step log as the legacy runner
    METHODS set_html_viewer
      IMPORTING
        !io_viewer TYPE REF TO cl_gui_html_viewer.

  PROTECTED SECTION.
  PRIVATE SECTION.
    TYPES:
      BEGIN OF ty_step,
        text        TYPE string,
        agent       TYPE string,
        prompt_type TYPE string,
        done        TYPE abap_bool,
        is_llm      TYPE abap_bool,
        seconds     TYPE i,
        tok_in      TYPE i,
        tok_out     TYPE i,
        tok_cached  TYPE i,
      END OF ty_step,
      tt_steps TYPE STANDARD TABLE OF ty_step WITH NON-UNIQUE DEFAULT KEY.

    DATA mo_llm      TYPE REF TO zcl_abapai_llm_client.
    DATA mo_context  TYPE REF TO zcl_ai_tool_context.
    DATA mo_prompts  TYPE REF TO zcl_ai_agents_prompts.
    DATA mo_ui       TYPE REF TO zcl_code_popup2.
    DATA mo_messages TYPE REF TO zcl_ai_messages.
    DATA mt_history TYPE zcl_ai_messages=>tt_messages.

    DATA mo_html_viewer    TYPE REF TO cl_gui_html_viewer.
    DATA mt_progress_steps TYPE tt_steps.
    DATA mv_total_seconds  TYPE i.
    DATA mv_total_tok_in   TYPE i.
    DATA mv_total_tok_out  TYPE i.
    DATA mv_total_tok_cached TYPE i.

    METHODS show_step
      IMPORTING
        !i_text        TYPE string OPTIONAL
        !i_agent       TYPE string OPTIONAL
        !i_prompt_type TYPE string OPTIONAL
        !i_pct         TYPE i DEFAULT 50.

    METHODS complete_last_step
      IMPORTING
        !i_is_llm  TYPE abap_bool DEFAULT abap_false
        !i_seconds TYPE i OPTIONAL
        !i_tok_in  TYPE i OPTIONAL
        !i_tok_out TYPE i OPTIONAL
        !i_tok_cached TYPE i OPTIONAL.

    METHODS render_steps_html
      RETURNING VALUE(rv_html) TYPE string.

    METHODS display_steps.

    METHODS execute_tool_call
      IMPORTING
        !is_call         TYPE zcl_code_ai_api=>ty_tool_call
      RETURNING VALUE(rv_result) TYPE string.

    METHODS confirm_and_apply
      IMPORTING
        !is_result       TYPE zif_ai_tool=>ty_result
      RETURNING VALUE(rv_message) TYPE string.

    METHODS build_system_prompt
      RETURNING VALUE(rv_prompt) TYPE string.
ENDCLASS.



CLASS zcl_ai_tool_runner IMPLEMENTATION.


  METHOD constructor.

    mo_llm     = io_llm.
    mo_context = io_context.
    mo_prompts = io_prompts.
    mo_ui      = io_ui.
    zcl_ai_tool_factory=>initialize( io_context ).

  ENDMETHOD.


  METHOD run.

    " Optimization: if prompt is a single code word (object name), skip LLM and read directly
    DATA(lv_trimmed_prompt) = i_prompt.
    CONDENSE lv_trimmed_prompt.
    FIND FIRST OCCURRENCE OF REGEX '[^A-Za-z0-9_]' IN lv_trimmed_prompt.
    IF lv_trimmed_prompt IS NOT INITIAL
    AND lv_trimmed_prompt NA ' '
    AND sy-subrc <> 0.
      DATA(lv_word) = lv_trimmed_prompt.
      TRANSLATE lv_word TO UPPER CASE.
      " Try CLASS first, then PROG, then wildcard search
      DATA(lv_direct_source) = zcl_ai_code_reader=>read_class( lv_word ).
      IF lv_direct_source IS INITIAL OR lv_direct_source CS 'not found'.
        CLEAR lv_direct_source.
        lv_direct_source = zcl_ai_code_reader=>read_program( lv_word ).
      ENDIF.
      IF lv_direct_source IS INITIAL OR lv_direct_source CS 'not found'.
        CLEAR lv_direct_source.
        lv_direct_source = zcl_ai_code_reader=>read_program( lv_word && '*' ).
        IF lv_direct_source CS 'not found' OR lv_direct_source CS 'No objects found'.
          CLEAR lv_direct_source.
        ENDIF.
      ENDIF.
      IF lv_direct_source IS NOT INITIAL.
        rv_answer = lv_direct_source.
        mo_messages = NEW zcl_ai_messages(
          i_user_prompt = i_prompt
          io_prompts    = mo_prompts
          i_session_id  = 1 ).
        mo_messages->add_message(
          i_role        = 'user'
          i_agent       = 'read_sap_object'
          i_prompt_type = 'TOOL_CALL'
          i_content     = |read_sap_object( { lv_word } )| ).
        mo_messages->add_message(
          i_role        = 'tool'
          i_agent       = 'read_sap_object'
          i_prompt_type = 'AGENT_RESPONSE'
          i_content     = rv_answer ).
        RETURN.
      ENDIF.
    ENDIF.

    DATA lt_calls   TYPE zcl_code_ai_api=>tt_tool_calls.

    DATA(lv_tools_json)    = zcl_ai_tool_factory=>build_tools_json( ).
    DATA(lv_system_prompt) = build_system_prompt( ).

    mo_messages = NEW zcl_ai_messages(
      i_user_prompt   = i_prompt
      io_prompts      = mo_prompts
      i_session_id    = 1
      i_system_prompt = lv_system_prompt ).

    DATA(lv_prompt) = i_prompt.

    " Fresh progress panel for every question
    CLEAR mt_progress_steps.
    CLEAR mv_total_seconds.
    CLEAR mv_total_tok_in.
    CLEAR mv_total_tok_out.
    CLEAR mv_total_tok_cached.

    DO c_max_iterations TIMES.

      show_step(
        i_text        = COND #( WHEN sy-index = 1
                                THEN 'Asking LLM'
                                ELSE |Asking LLM (step { sy-index })| )
        i_prompt_type = 'LLM'
        i_pct         = sy-index * 100 / c_max_iterations ).

      CLEAR lt_calls.
      DATA(lv_answer) = mo_llm->ask_with_tools(
        EXPORTING
          i_prompt        = lv_prompt
          i_system_prompt = lv_system_prompt
          it_history      = mt_history
          i_tools_json    = lv_tools_json
        IMPORTING
          et_tool_calls   = lt_calls ).

      complete_last_step(
        i_is_llm     = abap_true
        i_seconds    = CONV #( mo_llm->get_last_seconds( ) )
        i_tok_in     = mo_llm->mv_last_tok_in
        i_tok_out    = mo_llm->mv_last_tok_out
        i_tok_cached = mo_llm->mv_last_tok_cached ).

      " Persist the user turn to the multi-turn history (both paths)
      APPEND VALUE #( role = 'user' content = lv_prompt ) TO mt_history.

      " Always log the LLM output (text and/or requested tool calls) so the
      " History popup pairs it with the prompt: input left, output right
      DATA(lv_llm_log) = lv_answer.
      LOOP AT lt_calls INTO DATA(ls_call).
        IF lv_llm_log IS NOT INITIAL.
          lv_llm_log = lv_llm_log && cl_abap_char_utilities=>newline.
        ENDIF.
        lv_llm_log = lv_llm_log
          && |TOOL CALL: { ls_call-name }( { ls_call-arguments } )|.
      ENDLOOP.
      mo_messages->add_message(
        i_role             = 'assistant'
        i_agent            = 'TOOL_RUNNER'
        i_prompt_type      = COND #( WHEN lt_calls IS INITIAL
                                     THEN 'FINAL_ANSWER'
                                     ELSE 'LLM_RESPONSE' )
        i_duration_seconds = mo_llm->get_last_seconds( )
        i_tok_in           = mo_llm->mv_last_tok_in
        i_tok_out          = mo_llm->mv_last_tok_out
        i_tok_cached       = mo_llm->mv_last_tok_cached
        i_content          = lv_llm_log ).

      " No tool calls -> this is the final user-facing answer
      IF lt_calls IS INITIAL.
        rv_answer = lv_answer.
        APPEND VALUE #( role = 'assistant' content = lv_answer ) TO mt_history.
        RETURN.
      ENDIF.

      IF lv_answer IS NOT INITIAL.
        APPEND VALUE #( role = 'assistant' content = lv_answer ) TO mt_history.
      ENDIF.

      " Execute each tool; log the call (input) and its result (output) as a
      " pair so the History popup shows them side by side
      DATA lv_results TYPE string.
      CLEAR lv_results.
      LOOP AT lt_calls INTO ls_call.
        mo_messages->add_message(
          i_role        = 'user'
          i_agent       = ls_call-name
          i_prompt_type = 'TOOL_CALL'
          i_content     = |{ ls_call-name }( { ls_call-arguments } )| ).
        " Show target object (type + name from JSON arguments) in the step label
        DATA lv_step_type TYPE string.
        DATA lv_step_name TYPE string.
        CLEAR: lv_step_type, lv_step_name.
        FIND FIRST OCCURRENCE OF REGEX '"object_type"\s*:\s*"([^"]*)"'
          IN ls_call-arguments SUBMATCHES lv_step_type.
        FIND FIRST OCCURRENCE OF REGEX '"object_name"\s*:\s*"([^"]*)"'
          IN ls_call-arguments SUBMATCHES lv_step_name.
        DATA(lv_step_object) = |{ lv_step_type } { lv_step_name }|.
        CONDENSE lv_step_object.
        show_step( i_text = COND #(
          WHEN lv_step_object IS NOT INITIAL
          THEN |Tool { ls_call-name } { lv_step_object }...|
          ELSE |Tool { ls_call-name }...| ) ).
        DATA(lv_result) = execute_tool_call( ls_call ).
        complete_last_step( ).
        mo_messages->add_message(
          i_role        = 'tool'
          i_agent       = ls_call-name
          i_prompt_type = 'AGENT_RESPONSE'
          i_content     = lv_result ).
        lv_results = lv_results
          && |TOOL RESULT [{ ls_call-name }]:|
          && cl_abap_char_utilities=>newline
          && lv_result
          && cl_abap_char_utilities=>newline.
      ENDLOOP.

      lv_prompt = lv_results
        && cl_abap_char_utilities=>newline
        && |Continue with the user request. Call further tools if needed, |
        && |otherwise produce the final answer.|.
      mo_messages->add_message(
        i_role        = 'user'
        i_agent       = 'TOOL_RUNNER'
        i_prompt_type = 'LLM_INPUT'
        i_content     = lv_prompt ).

    ENDDO.

    rv_answer = |Error: tool loop did not finish within { c_max_iterations } iterations.|.

  ENDMETHOD.


  METHOD execute_tool_call.

    DATA(lo_tool) = zcl_ai_tool_factory=>get_tool( is_call-name ).
    IF lo_tool IS INITIAL.
      rv_result = |Error: unknown tool '{ is_call-name }'|.
      RETURN.
    ENDIF.

    DATA(ls_result) = lo_tool->execute( i_arguments = is_call-arguments ).

    IF ls_result-error_text IS NOT INITIAL.
      rv_result = |Error: { ls_result-error_text }|.
      RETURN.
    ENDIF.

    rv_result = ls_result-xml_payload.

    " Destructive actions stay in ONE place: confirmation + save/delete here,
    " never inside the tools themselves
    IF ls_result-save_required = abap_true.
      DATA(lv_apply_msg) = confirm_and_apply( ls_result ).
      rv_result = rv_result
        && cl_abap_char_utilities=>newline
        && |APPLY RESULT: { lv_apply_msg }|.
    ENDIF.

  ENDMETHOD.


  METHOD confirm_and_apply.

    DATA(lv_is_delete) = boolc( is_result-xml_payload CS '<code_deleted' ).

    " Diff review is mandatory for every save when UI is available. When the
    " tool did not supply the original source (e.g. create_sap_object on an
    " existing object), read the current version so the user still sees a diff;
    " for a truly new object the diff is shown against empty code.
    IF lv_is_delete = abap_false
    AND is_result-final_source IS NOT INITIAL
    AND mo_ui IS BOUND.
      DATA(lv_old_code) = is_result-original_source.
      IF lv_old_code IS INITIAL.
        CASE is_result-object_type.
          WHEN 'CLAS' OR 'METH'.
            lv_old_code = zcl_ai_code_reader=>read_class( is_result-object_name ).
          WHEN OTHERS.
            lv_old_code = zcl_ai_code_reader=>read_program(
              i_program     = is_result-object_name
              i_object_type = is_result-object_type ).
        ENDCASE.
        IF lv_old_code CS 'not found' OR lv_old_code CS 'cannot be read'.
          CLEAR lv_old_code.
        ENDIF.
      ENDIF.
      rv_message = mo_ui->review_and_save(
        i_old_code    = lv_old_code
        i_new_code    = is_result-final_source
        i_object_type = is_result-object_type
        i_object_name = is_result-object_name ).
      RETURN.
    ENDIF.

    " Fallback: simple confirm popup (delete or no UI)
    DATA lv_answer TYPE c LENGTH 1.
    DATA(lv_question) = COND string(
      WHEN lv_is_delete = abap_true
      THEN |Delete { is_result-object_type } { is_result-object_name }?|
      ELSE |Save changes to { is_result-object_type } { is_result-object_name }?| ).

    CALL FUNCTION 'POPUP_TO_CONFIRM'
      EXPORTING
        titlebar              = 'AI Tool Runner'
        text_question         = lv_question
        text_button_1         = 'Yes'
        text_button_2         = 'No'
        default_button        = '2'
        display_cancel_button = ' '
      IMPORTING
        answer                = lv_answer
      EXCEPTIONS
        OTHERS                = 1.

    IF sy-subrc <> 0 OR lv_answer <> '1'.
      rv_message = 'Rejected by user - nothing was changed.'.
      RETURN.
    ENDIF.

    IF lv_is_delete = abap_true.
      rv_message = zcl_code_object_saver=>delete(
        i_object_type = is_result-object_type
        i_object_name = is_result-object_name ).
    ELSE.
      IF is_result-final_source IS INITIAL.
        rv_message = 'Error: no final source to save.'.
        RETURN.
      ENDIF.
      rv_message = zcl_code_object_saver=>save(
        i_object_type = is_result-object_type
        i_object_name = is_result-object_name
        i_source      = is_result-final_source ).
    ENDIF.

  ENDMETHOD.


  METHOD build_system_prompt.

    rv_prompt =
      |We are in an SAP system. The programming language is ABAP.| &&
      cl_abap_char_utilities=>newline &&
      |You are an assistant with tools for working with SAP objects.| &&
      cl_abap_char_utilities=>newline &&
      |RULES:| && cl_abap_char_utilities=>newline &&
      |- NEVER invent SAP object names. Use only names from the user request.| &&
      cl_abap_char_utilities=>newline &&
      |- Call read_sap_object before modify_sap_object or review_sap_code.| &&
      cl_abap_char_utilities=>newline &&
      |- read_sap_object accepts a wildcard pattern (ZCL_AITOOL_*) to list | &&
      |matching objects, and a comma-separated list of names to read several | &&
      |objects in one call.| &&
      cl_abap_char_utilities=>newline &&
      |- When the user only wants a code example without saving, use | &&
      |show_code_example - never create_sap_object.| &&
      cl_abap_char_utilities=>newline &&
      |- To delete a method from a class use modify_sap_object on the class, | &&
      |not delete_sap_object.| &&
      cl_abap_char_utilities=>newline &&
      |- To add or change anything in an EXISTING object (e.g. add a method to | &&
      |an existing class) use modify_sap_object. create_sap_object is ONLY for | &&
      |objects that do not exist yet.| &&
      cl_abap_char_utilities=>newline &&
      |- When all tool work is done, answer the user in their language.| &&
      cl_abap_char_utilities=>newline &&
      |- Use web_search when the user asks to find, check, or verify something online.|
      cl_abap_char_utilities=>newline &&
      |- NEVER ask clarifying questions. Execute the full requested task autonomously.| &&
      cl_abap_char_utilities=>newline &&
      |- If the user asks for a code review, call read_sap_object then review_sap_code immediately.| &&
      cl_abap_char_utilities=>newline &&
      |- NEVER return raw XML to the user. Always interpret tool results and present them| &&
      | as a clear human-readable summary in the user language.|.

  ENDMETHOD.


  METHOD get_messages.

    ro_messages = mo_messages.

  ENDMETHOD.


  METHOD clear_session.

    CLEAR mt_history.
    CLEAR mo_messages.

  ENDMETHOD.


  METHOD set_html_viewer.

    mo_html_viewer = io_viewer.
    CLEAR mt_progress_steps.
    CLEAR mv_total_seconds.
    CLEAR mv_total_tok_in.
    CLEAR mv_total_tok_out.
    CLEAR mv_total_tok_cached.

  ENDMETHOD.


  METHOD show_step.

    CALL FUNCTION 'SAPGUI_PROGRESS_INDICATOR'
      EXPORTING percentage = i_pct text = i_text.

    CHECK mo_html_viewer IS BOUND.

    " Mark previous last step as done
    DATA(lv_last) = lines( mt_progress_steps ).
    IF lv_last > 0.
      FIELD-SYMBOLS <ls_prev> TYPE ty_step.
      READ TABLE mt_progress_steps ASSIGNING <ls_prev> INDEX lv_last.
      IF sy-subrc = 0.
        <ls_prev>-done = abap_true.
      ENDIF.
    ENDIF.

    APPEND VALUE ty_step(
      text        = i_text
      agent       = i_agent
      prompt_type = i_prompt_type
      done        = abap_false ) TO mt_progress_steps.

    display_steps( ).

  ENDMETHOD.


  METHOD complete_last_step.

    CHECK mo_html_viewer IS BOUND.

    DATA(lv_last) = lines( mt_progress_steps ).
    CHECK lv_last > 0.

    FIELD-SYMBOLS <ls_step> TYPE ty_step.
    READ TABLE mt_progress_steps ASSIGNING <ls_step> INDEX lv_last.
    CHECK sy-subrc = 0.

    <ls_step>-done       = abap_true.
    <ls_step>-is_llm     = i_is_llm.
    <ls_step>-seconds    = i_seconds.
    <ls_step>-tok_in     = i_tok_in.
    <ls_step>-tok_out    = i_tok_out.
    <ls_step>-tok_cached = i_tok_cached.

    IF i_is_llm = abap_true.
      mv_total_seconds    = mv_total_seconds    + i_seconds.
      mv_total_tok_in     = mv_total_tok_in     + i_tok_in.
      mv_total_tok_out    = mv_total_tok_out    + i_tok_out.
      mv_total_tok_cached = mv_total_tok_cached + i_tok_cached.
    ENDIF.

    display_steps( ).

  ENDMETHOD.


  METHOD display_steps.

    DATA(lv_html) = render_steps_html( ).
    DATA lt_html TYPE STANDARD TABLE OF w3html WITH NON-UNIQUE DEFAULT KEY.
    DATA lv_off TYPE i.
    WHILE lv_off < strlen( lv_html ).
      DATA(lv_chunk) = nmin( val1 = 255 val2 = strlen( lv_html ) - lv_off ).
      APPEND VALUE w3html( line = substring( val = lv_html off = lv_off len = lv_chunk ) )
        TO lt_html.
      lv_off = lv_off + lv_chunk.
    ENDWHILE.
    DATA lv_url TYPE c LENGTH 255.
    mo_html_viewer->load_data(
      EXPORTING type = 'text' subtype = 'html'
      IMPORTING assigned_url = lv_url
      CHANGING  data_table   = lt_html
      EXCEPTIONS OTHERS = 1 ).
    CHECK sy-subrc = 0.
    mo_html_viewer->show_url( EXPORTING url = lv_url EXCEPTIONS OTHERS = 1 ).
    cl_gui_cfw=>flush( ).

  ENDMETHOD.


  METHOD render_steps_html.

    DATA lv_rows TYPE string.
    LOOP AT mt_progress_steps INTO DATA(ls_step).
      DATA(lv_label) = COND string(
        WHEN ls_step-agent IS NOT INITIAL THEN |Agent { ls_step-agent }|
        WHEN ls_step-text  IS NOT INITIAL THEN ls_step-text
        WHEN ls_step-prompt_type IS NOT INITIAL THEN ls_step-prompt_type ).
      REPLACE ALL OCCURRENCES OF '&' IN lv_label WITH '&amp;'.
      REPLACE ALL OCCURRENCES OF '<' IN lv_label WITH '&lt;'.
      REPLACE ALL OCCURRENCES OF '>' IN lv_label WITH '&gt;'.

      DATA(lv_is_llm) = xsdbool( ls_step-prompt_type = 'LLM' OR ls_step-is_llm = abap_true ).

      IF ls_step-done = abap_true.
        DATA(lv_info) = VALUE string( ).
        IF lv_is_llm = abap_true.
          lv_info = |<span class="info">{ ls_step-seconds }s|.
          IF ls_step-tok_in > 0.
            lv_info = lv_info && | Tokens: inp:{ ls_step-tok_in }, out:{ ls_step-tok_out }|.
            IF ls_step-tok_cached > 0.
              lv_info = lv_info && |, cached:{ ls_step-tok_cached }|.
            ENDIF.
          ENDIF.
          lv_info = lv_info && |</span>|.
          lv_rows = lv_rows
            && |<div class="step done">&#x2713; { lv_label }: { lv_info }</div>|.
        ELSE.
          lv_rows = lv_rows
            && |<div class="step done">&#x2713; { lv_label }</div>|.
        ENDIF.
      ELSE.
        IF lv_is_llm = abap_true.
          lv_rows = lv_rows
            && |<div class="step active">&#x23F3; { lv_label } is working...</div>|.
        ELSE.
          lv_rows = lv_rows
            && |<div class="step active">&#x23F3; { lv_label }</div>|.
        ENDIF.
      ENDIF.
    ENDLOOP.

    IF mv_total_seconds > 0.
      lv_rows = lv_rows
        && |<div class="total">Total: { mv_total_seconds }s|.
      IF mv_total_tok_in > 0.
        lv_rows = lv_rows && | Tokens: inp:{ mv_total_tok_in }, out:{ mv_total_tok_out }|.
        IF mv_total_tok_cached > 0.
          lv_rows = lv_rows && |, cached:{ mv_total_tok_cached }|.
        ENDIF.
      ENDIF.
      lv_rows = lv_rows && |</div>|.
    ENDIF.

    rv_html =
      |<!DOCTYPE html><html><head><meta charset="utf-8"><style>|
      && |body\{font-family:Segoe UI,Arial,sans-serif;margin:12px;background:#f5f5f5\}|
      && |.step\{padding:5px 10px;margin:3px 0;border-radius:3px;font-size:13px\}|
      && |.done\{color:#2e7d32\}|
      && |.active\{color:#0033aa;font-style:italic\}|
      && |.info\{color:#888;font-size:11px\}|
      && |.total\{margin-top:8px;padding:5px 10px;font-size:12px;border-radius:3px;|
      && |color:#0033aa;font-weight:bold\}|
      && |</style></head><body>|
      && lv_rows
      && |</body></html>|.

  ENDMETHOD.
ENDCLASS.
