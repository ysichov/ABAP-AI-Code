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
    METHODS read_single
      IMPORTING
        !i_type          TYPE string
        !i_name          TYPE string
      RETURNING VALUE(rv_source) TYPE string.
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

    " The LLM may request several objects at once: comma-separated list
    DATA lt_names TYPE STANDARD TABLE OF string WITH NON-UNIQUE DEFAULT KEY.
    SPLIT lv_name AT ',' INTO TABLE lt_names.

    DATA lv_source TYPE string.
    LOOP AT lt_names INTO DATA(lv_single_name).
      CONDENSE lv_single_name.
      CHECK lv_single_name IS NOT INITIAL.

      DATA(lv_single_source) = read_single(
        i_type = lv_type
        i_name = lv_single_name ).

      IF lv_source IS NOT INITIAL.
        lv_source = lv_source
          && cl_abap_char_utilities=>newline
          && cl_abap_char_utilities=>newline.
      ENDIF.
      lv_source = lv_source && lv_single_source.
    ENDLOOP.

    IF lv_source IS INITIAL.
      rs_result-error_text = |read_sap_object: { lv_type } { lv_name } not found or empty|.
      RETURN.
    ENDIF.

    " Plain payload: source goes back to the LLM as tool result, nothing saved
    rs_result-xml_payload   = lv_source.
    rs_result-save_required = abap_false.

  ENDMETHOD.


  METHOD read_single.

    " Wildcard pattern (e.g. ZCL_AITOOL_*): TADIR list via read_program,
    " which maps CLAS/PROG/FUGR to the right TADIR types
    IF i_name CA '*+'.
      rv_source = zcl_ai_code_reader=>read_program(
        i_program     = i_name
        i_object_type = i_type ).
      RETURN.
    ENDIF.

    CASE i_type.
      WHEN 'CLAS'.
        rv_source = zcl_ai_code_reader=>read_class( i_name ).
      WHEN 'METH'.
        SPLIT i_name AT '=>' INTO DATA(lv_class) DATA(lv_method).
        rv_source = zcl_ai_code_reader=>read_method(
          i_class  = lv_class
          i_method = lv_method ).
      WHEN OTHERS.
        " PROG / REPS / FUNC and everything else
        rv_source = zcl_ai_code_reader=>read_program(
          i_program     = i_name
          i_object_type = i_type ).
    ENDCASE.

  ENDMETHOD.
ENDCLASS.
