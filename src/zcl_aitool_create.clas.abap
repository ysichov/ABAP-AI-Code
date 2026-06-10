CLASS zcl_aitool_create DEFINITION
  PUBLIC
  INHERITING FROM zcl_aitool_base
  CREATE PUBLIC.

  PUBLIC SECTION.
    CONSTANTS c_tool_name TYPE string VALUE 'create_sap_object'.

    METHODS zif_ai_tool~get_tool_name REDEFINITION.
    METHODS zif_ai_tool~execute       REDEFINITION.

  PROTECTED SECTION.
  PRIVATE SECTION.
    METHODS extract_full_source
      IMPORTING
        !i_answer        TYPE string
      RETURNING VALUE(rv_source) TYPE string.
ENDCLASS.



CLASS zcl_aitool_create IMPLEMENTATION.


  METHOD zif_ai_tool~get_tool_name.

    rv_name = c_tool_name.

  ENDMETHOD.


  METHOD zif_ai_tool~execute.

    DATA(lv_type) = get_json_attribute( i_json = i_arguments i_name = 'object_type' ).
    DATA(lv_name) = get_json_attribute( i_json = i_arguments i_name = 'object_name' ).
    DATA(lv_reqs) = get_json_attribute( i_json = i_arguments i_name = 'requirements' ).
    TRANSLATE lv_type TO UPPER CASE.
    TRANSLATE lv_name TO UPPER CASE.
    CONDENSE lv_type.
    CONDENSE lv_name.

    IF lv_name IS INITIAL OR lv_reqs IS INITIAL.
      rs_result-error_text = 'create_sap_object: object_name or requirements is empty'.
      RETURN.
    ENDIF.

    DATA(lv_system_prompt) = mo_context->read_agent_file( c_tool_name && '.md' ).
    IF lv_system_prompt IS INITIAL.
      rs_result-error_text = |{ c_tool_name }.md prompt file not found|.
      RETURN.
    ENDIF.

    DATA(lv_prompt) =
      |Create { lv_type } { lv_name }.| && cl_abap_char_utilities=>newline &&
      |REQUIREMENTS: { lv_reqs }|.

    DATA(lv_answer) = mo_context->mo_llm->ask(
      i_prompt        = lv_prompt
      i_system_prompt = lv_system_prompt ).

    IF lv_answer NS '<code_created'.
      rs_result-error_text = 'create_sap_object: LLM returned no <code_created> envelope'.
      rs_result-xml_payload = lv_answer.
      RETURN.
    ENDIF.

    rs_result-xml_payload   = lv_answer.
    rs_result-save_required = abap_true.
    rs_result-object_type   = lv_type.
    rs_result-object_name   = lv_name.
    rs_result-final_source  = extract_full_source( lv_answer ).

  ENDMETHOD.


  METHOD extract_full_source.

    DATA(lv_off_open)  = find( val = i_answer sub = '<full_source>' ).
    DATA(lv_off_close) = find( val = i_answer sub = '</full_source>' ).
    IF lv_off_open < 0 OR lv_off_close <= lv_off_open.
      RETURN.
    ENDIF.
    DATA(lv_start) = lv_off_open + strlen( '<full_source>' ).
    rv_source = substring( val = i_answer
                           off = lv_start
                           len = lv_off_close - lv_start ).

  ENDMETHOD.
ENDCLASS.
