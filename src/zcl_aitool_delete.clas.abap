CLASS zcl_aitool_delete DEFINITION
  PUBLIC
  INHERITING FROM zcl_aitool_base
  CREATE PUBLIC.

  PUBLIC SECTION.
    CONSTANTS c_tool_name TYPE string VALUE 'delete_sap_object'.

    METHODS zif_ai_tool~get_tool_name REDEFINITION.
    METHODS zif_ai_tool~execute       REDEFINITION.

  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.



CLASS zcl_aitool_delete IMPLEMENTATION.


  METHOD zif_ai_tool~get_tool_name.

    rv_name = c_tool_name.

  ENDMETHOD.


  METHOD zif_ai_tool~execute.

    DATA(lv_type)   = get_json_attribute( i_json = i_arguments i_name = 'object_type' ).
    DATA(lv_name)   = get_json_attribute( i_json = i_arguments i_name = 'object_name' ).
    DATA(lv_reason) = get_json_attribute( i_json = i_arguments i_name = 'reason' ).
    TRANSLATE lv_type TO UPPER CASE.
    TRANSLATE lv_name TO UPPER CASE.
    CONDENSE lv_type.
    CONDENSE lv_name.

    IF lv_name IS INITIAL.
      rs_result-error_text = 'delete_sap_object: object_name is empty'.
      RETURN.
    ENDIF.
    IF lv_type <> 'CLAS' AND lv_type <> 'PROG'.
      rs_result-error_text = |delete_sap_object: only CLAS or PROG can be deleted, got '{ lv_type }'|.
      RETURN.
    ENDIF.

    " No LLM call needed. The tool only validates and builds the envelope;
    " the mandatory confirmation popup and the actual deletion are the
    " runner's job (same as confirm + save for modifications).
    rs_result-xml_payload =
      |<code_deleted type="{ lv_type }" name="{ lv_name }" version="1.0">| &&
      |<deletion_reason>{ lv_reason }</deletion_reason>| &&
      |<metadata><confirmed>false</confirmed></metadata>| &&
      |</code_deleted>|.
    rs_result-save_required = abap_true.
    rs_result-object_type   = lv_type.
    rs_result-object_name   = lv_name.

  ENDMETHOD.
ENDCLASS.
