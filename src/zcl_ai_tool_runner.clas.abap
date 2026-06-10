CLASS zcl_ai_tool_runner DEFINITION
  PUBLIC
  CREATE PUBLIC.

  PUBLIC SECTION.
    CONSTANTS c_max_iterations TYPE i VALUE 8.

    METHODS constructor
      IMPORTING
        !io_llm        TYPE REF TO zcl_llm_client
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

  PROTECTED SECTION.
  PRIVATE SECTION.
    DATA mo_llm      TYPE REF TO zcl_llm_client.
    DATA mo_context  TYPE REF TO zcl_ai_tool_context.
    DATA mo_prompts  TYPE REF TO zcl_ai_agents_prompts.
    DATA mo_ui       TYPE REF TO zcl_code_popup2.
    DATA mo_messages TYPE REF TO zcl_ai_messages.
    DATA mt_history TYPE zcl_ai_messages=>tt_messages.

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

    DO c_max_iterations TIMES.

      CLEAR lt_calls.
      DATA(lv_answer) = mo_llm->ask_with_tools(
        EXPORTING
          i_prompt        = lv_prompt
          i_system_prompt = lv_system_prompt
          it_history      = mt_history
          i_tools_json    = lv_tools_json
        IMPORTING
          et_tool_calls   = lt_calls ).

      " No tool calls -> this is the final user-facing answer
      IF lt_calls IS INITIAL.
        rv_answer = lv_answer.
        mo_messages->add_message(
          i_role        = 'assistant'
          i_agent       = 'TOOL_RUNNER'
          i_prompt_type = 'ANSWER'
          i_content     = lv_answer ).
        APPEND VALUE #( role = 'assistant' content = lv_answer ) TO mt_history.
        RETURN.
      ENDIF.

      " LLM requested tool calls - persist this turn to history and log it
      APPEND VALUE #( role = 'user' content = lv_prompt ) TO mt_history.
      IF lv_answer IS NOT INITIAL.
        APPEND VALUE #( role = 'assistant' content = lv_answer ) TO mt_history.
        mo_messages->add_message(
          i_role        = 'assistant'
          i_agent       = 'TOOL_RUNNER'
          i_prompt_type = 'THINKING'
          i_content     = lv_answer ).
      ENDIF.

      " Execute each tool and log separately with tool name as prompt_type
      DATA lv_results TYPE string.
      CLEAR lv_results.
      LOOP AT lt_calls INTO DATA(ls_call).
        DATA(lv_result) = execute_tool_call( ls_call ).
        mo_messages->add_message(
          i_role        = 'tool'
          i_agent       = ls_call-name
          i_prompt_type = ls_call-name
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
      APPEND VALUE #( role = 'user' content = lv_prompt ) TO mt_history.

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

    " For modifications: show diff and use the review flow if UI is available
    IF lv_is_delete = abap_false
    AND is_result-original_source IS NOT INITIAL
    AND mo_ui IS BOUND.
      rv_message = mo_ui->review_and_save(
        i_old_code    = is_result-original_source
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
      |- When the user only wants a code example without saving, use | &&
      |show_code_example - never create_sap_object.| &&
      cl_abap_char_utilities=>newline &&
      |- To delete a method from a class use modify_sap_object on the class, | &&
      |not delete_sap_object.| &&
      cl_abap_char_utilities=>newline &&
      |- When all tool work is done, answer the user in their language.| &&
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
ENDCLASS.
