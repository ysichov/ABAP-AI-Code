CLASS zcl_aitool_base DEFINITION
  PUBLIC
  ABSTRACT
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_ai_tool
      ABSTRACT METHODS get_tool_name execute.

  PROTECTED SECTION.
    DATA mo_context TYPE REF TO zcl_ai_tool_context.

    " Parses one string attribute out of the raw JSON arguments from the LLM
    METHODS get_json_attribute
      IMPORTING
        !i_json         TYPE string
        !i_name         TYPE string
      RETURNING VALUE(rv_value) TYPE string.

  PRIVATE SECTION.
ENDCLASS.



CLASS zcl_aitool_base IMPLEMENTATION.


  METHOD zif_ai_tool~init.

    mo_context = io_context.

  ENDMETHOD.


  METHOD zif_ai_tool~is_active.

    " Active by default; override to disable a tool without deleting it
    rv_active = abap_true.

  ENDMETHOD.


  METHOD zif_ai_tool~get_schema.

    " Convention: schema file name = tool name + '.json'
    rv_schema = mo_context->read_agent_file(
      zif_ai_tool~get_tool_name( ) && '.json' ).

    " Anything that does not start with '{' or '[' is not a schema
    DATA(lv_trimmed) = rv_schema.
    CONDENSE lv_trimmed.
    IF lv_trimmed IS INITIAL
    OR ( lv_trimmed(1) <> '{' AND lv_trimmed(1) <> '[' ).
      CLEAR rv_schema.
    ENDIF.

  ENDMETHOD.


  METHOD get_json_attribute.

    " Tolerant extraction via /ui2/cl_json into a generic map is overkill
    " for flat argument objects - a regex on "name":"value" is sufficient
    " and avoids dynamic structure generation.
    DATA(lv_pattern) = |"{ i_name }"\\s*:\\s*"([^"]*)"|.
    FIND FIRST OCCURRENCE OF REGEX lv_pattern IN i_json
      SUBMATCHES rv_value.

  ENDMETHOD.
ENDCLASS.
