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
      EXPORTING
        !ev_not_found    TYPE abap_bool
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

      DATA lv_not_found TYPE abap_bool.
      DATA(lv_single_source) = read_single(
        EXPORTING i_type       = lv_type
                  i_name       = lv_single_name
        IMPORTING ev_not_found = lv_not_found ).

      " The reader signals a missing object explicitly. Do NOT feed "not found"
      " back to the LLM (it would hallucinate / retry): set error_text so the
      " tool runner stops the loop and reports straight away.
      IF lv_not_found = abap_true.
        rs_result-error_text = |read_sap_object: { lv_type } { lv_single_name } not found|.
        RETURN.
      ENDIF.

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
    " which maps CLAS/PROG/FUGR to the right TADIR types. An empty match sets
    " ev_not_found too, so the loop stops instead of feeding it back to the LLM.
    IF i_name CA '*+'.
      rv_source = zcl_ai_code_reader=>read_program(
        EXPORTING i_program     = i_name
                  i_object_type = i_type
        IMPORTING ev_not_found  = ev_not_found ).
      RETURN.
    ENDIF.

    CASE i_type.
      WHEN 'CLAS'.
        IF i_name CS '=>'.
          SPLIT i_name AT '=>' INTO DATA(lv_cls_part) DATA(lv_meth_part).
          rv_source = zcl_ai_code_reader=>read_method(
            EXPORTING i_class      = lv_cls_part
                      i_method     = lv_meth_part
            IMPORTING ev_not_found = ev_not_found ).
        ELSE.
          rv_source = zcl_ai_code_reader=>read_class(
            EXPORTING i_class      = i_name
            IMPORTING ev_not_found = ev_not_found ).
        ENDIF.
      WHEN 'METH'.
        SPLIT i_name AT '=>' INTO DATA(lv_class) DATA(lv_method).
        rv_source = zcl_ai_code_reader=>read_method(
          EXPORTING i_class      = lv_class
                    i_method     = lv_method
          IMPORTING ev_not_found = ev_not_found ).
      WHEN OTHERS.
        " PROG / REPS / FUNC and everything else
        rv_source = zcl_ai_code_reader=>read_program(
          EXPORTING i_program     = i_name
                    i_object_type = i_type
          IMPORTING ev_not_found  = ev_not_found ).
    ENDCASE.

  ENDMETHOD.
ENDCLASS.
