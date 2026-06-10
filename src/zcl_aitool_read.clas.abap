CLASS zcl_aitool_read DEFINITION
  PUBLIC
  INHERITING FROM zcl_aitool_base
  CREATE PUBLIC.

  PUBLIC SECTION.
    " THE single binding point: tool name = schema file name = md file name
    CONSTANTS c_tool_name TYPE string VALUE 'read_sap_object'.

    METHODS zif_ai_tool~get_tool_name REDEFINITION.
    METHODS zif_ai_tool~execute       REDEFINITION.

  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.



CLASS zcl_aitool_read IMPLEMENTATION.


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
      rs_result-error_text = 'read_sap_object: object_name is empty'.
      RETURN.
    ENDIF.

    DATA lv_source TYPE string.
    CASE lv_type.
      WHEN 'CLAS'.
        lv_source = zcl_ai_code_reader=>read_class( lv_name ).
      WHEN 'METH'.
        SPLIT lv_name AT '=>' INTO DATA(lv_class) DATA(lv_method).
        lv_source = zcl_ai_code_reader=>read_method(
          i_class  = lv_class
          i_method = lv_method ).
      WHEN OTHERS.
        " PROG / REPS / FUNC and everything else
        lv_source = zcl_ai_code_reader=>read_program(
          i_program     = lv_name
          i_object_type = lv_type ).
    ENDCASE.

    IF lv_source IS INITIAL.
      rs_result-error_text = |read_sap_object: { lv_type } { lv_name } not found or empty|.
      RETURN.
    ENDIF.

    " Plain payload: source goes back to the LLM as tool result, nothing saved
    rs_result-xml_payload   = lv_source.
    rs_result-save_required = abap_false.

  ENDMETHOD.
ENDCLASS.
