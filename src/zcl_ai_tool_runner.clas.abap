CLASS zcl_ai_tool_runner DEFINITION
  PUBLIC
  CREATE PUBLIC.

  PUBLIC SECTION.
    CONSTANTS c_max_iterations TYPE i VALUE 8.

    METHODS constructor
      IMPORTING
        !io_llm     TYPE REF TO zcl_llm_client
        !io_context TYPE REF TO zcl_ai_tool_context.

    " Agentic loop: LLM -> tool_calls -> execute -> results back -> LLM ...
    " Ends when the LLM answers without tool calls or c_max_iterations is hit.
    METHODS run
      IMPORTING
        !i_prompt        TYPE string
      RETURNING VALUE(rv_answer) TYPE string.

  PROTECTED SECTION.
  PRIVATE SECTION.
    DATA mo_llm     TYPE REF TO zcl_llm_client.
    DATA mo_context TYPE REF TO zcl_ai_tool_context.

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
    zcl_ai_tool_factory=>initialize( io_context ).

  ENDMETHOD.


  METHOD run.

    DATA lt_history TYPE zcl_ai_messages=>tt_messages.
    DATA lt_calls   TYPE zcl_code_ai_api=>tt_tool_calls.

    DATA(lv_tools_json)    = zcl_ai_tool_factory=>build_tools_json( ).
    DATA(lv_system_prompt) = build_system_prompt( ).
    DATA(lv_prompt)        = i_prompt.

    DO c_max_iterations TIMES.

      CLEAR lt_calls.
      DATA(lv_answer) = mo_llm->ask_with_tools(
        EXPORTING
          i_prompt        = lv_prompt
          i_system_prompt = lv_system_prompt
          it_history      = lt_history
          i_tools_json    = lv_tools_json
        IMPORTING
          et_tool_calls   = lt_calls ).

      " No tool calls -> this is the final user-facing answer
      IF lt_calls IS INITIAL.
        rv_answer = lv_answer.
        RETURN.
      ENDIF.

      " Log this turn into the history before appending tool results
      APPEND VALUE #( role    = 'user'
                      content = lv_prompt ) TO lt_history.
      IF lv_answer IS NOT INITIAL.
        APPEND VALUE #( role    = 'assistant'
                        content = lv_answer ) TO lt_history.
      ENDIF.

      " Execute every requested tool; feed results back as the next prompt.
      " NOTE v1 simplification: results are passed as a user message instead
      " of role:"tool" messages with tool_call_id (BUILD_PAYLOAD supports
      " only user/assistant history so far).
      DATA lv_results TYPE string.
      CLEAR lv_results.
      LOOP AT lt_calls INTO DATA(ls_call).
        DATA(lv_result) = execute_tool_call( ls_call ).
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

    DATA lv_answer TYPE c LENGTH 1.

    DATA(lv_is_delete) = boolc( is_result-xml_payload CS '<code_deleted' ).
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
      |- When all tool work is done, answer the user in their language.|.

  ENDMETHOD.
ENDCLASS.
