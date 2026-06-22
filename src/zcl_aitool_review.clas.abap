CLASS zcl_aitool_review DEFINITION
  PUBLIC
  INHERITING FROM zcl_aitool_base
  CREATE PUBLIC.

  PUBLIC SECTION.
    CONSTANTS c_tool_name TYPE string VALUE 'review_sap_code'.

    METHODS zif_ai_tool~get_tool_name REDEFINITION.
    METHODS zif_ai_tool~execute       REDEFINITION.

  PROTECTED SECTION.
  PRIVATE SECTION.
    METHODS read_source
      IMPORTING
        !i_type          TYPE string
        !i_name          TYPE string
      RETURNING VALUE(rv_source) TYPE string.
ENDCLASS.



CLASS zcl_aitool_review IMPLEMENTATION.


  METHOD zif_ai_tool~get_tool_name.

    rv_name = c_tool_name.

  ENDMETHOD.


  METHOD zif_ai_tool~execute.

    DATA(lv_type) = get_json_attribute( i_json = i_arguments i_name = 'object_type' ).
    DATA(lv_name) = get_json_attribute( i_json = i_arguments i_name = 'object_name' ).
    TRANSLATE lv_type TO UPPER CASE.
    TRANSLATE lv_name TO UPPER CASE.
    CONDENSE lv_type.
    CONDENSE lv_name.

    IF lv_name IS INITIAL.
      rs_result-error_text = 'review_sap_code: object_name is empty'.
      RETURN.
    ENDIF.

    " The source may arrive via i_context (already read by a previous
    " read_sap_object call); otherwise read it here - REVIEW requires READ
    DATA(lv_source) = i_context.
    IF lv_source IS INITIAL.
      lv_source = read_source( i_type = lv_type i_name = lv_name ).
    ENDIF.
    IF lv_source IS INITIAL.
      rs_result-error_text = |review_sap_code: { lv_type } { lv_name } not found|.
      RETURN.
    ENDIF.

    DATA(lv_system_prompt) = mo_context->read_agent_file( c_tool_name && '.md' ).
    IF lv_system_prompt IS INITIAL.
      rs_result-error_text = |{ c_tool_name }.md prompt file not found|.
      RETURN.
    ENDIF.

    DATA(lv_answer) = mo_context->ask(
      i_label         = |review { lv_type } { lv_name }|
      i_prompt        = |Object: { lv_type } { lv_name }{ cl_abap_char_utilities=>newline }{ lv_source }|
      i_system_prompt = lv_system_prompt ).

    rs_result-xml_payload   = lv_answer.    " <code_analysis> envelope
    rs_result-save_required = abap_false.

  ENDMETHOD.


  METHOD read_source.

    CASE i_type.
      WHEN 'CLAS'.
        rv_source = zcl_ai_code_reader=>read_class( i_name ).
      WHEN 'METH'.
        SPLIT i_name AT '=>' INTO DATA(lv_class) DATA(lv_method).
        rv_source = zcl_ai_code_reader=>read_method(
          i_class  = lv_class
          i_method = lv_method ).
      WHEN OTHERS.
        rv_source = zcl_ai_code_reader=>read_program(
          i_program     = i_name
          i_object_type = i_type ).
    ENDCASE.

  ENDMETHOD.
ENDCLASS.
