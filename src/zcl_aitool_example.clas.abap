CLASS zcl_aitool_example DEFINITION
  PUBLIC
  INHERITING FROM zcl_aitool_base
  CREATE PUBLIC.

  PUBLIC SECTION.
    CONSTANTS c_tool_name TYPE string VALUE 'show_code_example'.

    METHODS zif_ai_tool~get_tool_name REDEFINITION.
    METHODS zif_ai_tool~execute       REDEFINITION.

  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.



CLASS zcl_aitool_example IMPLEMENTATION.


  METHOD zif_ai_tool~get_tool_name.

    rv_name = c_tool_name.

  ENDMETHOD.


  METHOD zif_ai_tool~execute.

    DATA(lv_topic) = get_json_attribute( i_json = i_arguments i_name = 'topic' ).
    IF lv_topic IS INITIAL.
      rs_result-error_text = 'show_code_example: topic is empty'.
      RETURN.
    ENDIF.

    " Prompt instruction lives in show_code_example.md next to the schema
    DATA(lv_system_prompt) = mo_context->read_agent_file( c_tool_name && '.md' ).
    IF lv_system_prompt IS INITIAL.
      rs_result-error_text = |{ c_tool_name }.md prompt file not found|.
      RETURN.
    ENDIF.

    DATA(lv_answer) = mo_context->ask(
      i_label         = |code example: { lv_topic }|
      i_prompt        = lv_topic
      i_system_prompt = lv_system_prompt ).

    " Display only: never saved, never reviewed
    rs_result-xml_payload   = lv_answer.
    rs_result-save_required = abap_false.

  ENDMETHOD.
ENDCLASS.
