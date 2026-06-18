CLASS zcl_ai_tool_factory DEFINITION
  PUBLIC
  CREATE PRIVATE.

  PUBLIC SECTION.
    TYPES:
      BEGIN OF ty_registry_entry,
        tool_name TYPE string,
        instance  TYPE REF TO zif_ai_tool,
      END OF ty_registry_entry,
      tt_registry TYPE STANDARD TABLE OF ty_registry_entry WITH NON-UNIQUE DEFAULT KEY.

    " Discovers all active ZIF_AI_TOOL implementers and builds the registry.
    " Must be called once before get_tool / get_all_tools.
    CLASS-METHODS initialize
      IMPORTING
        !io_context TYPE REF TO zcl_ai_tool_context.

    CLASS-METHODS get_tool
      IMPORTING
        !i_tool_name   TYPE string
      RETURNING VALUE(ro_tool) TYPE REF TO zif_ai_tool.

    CLASS-METHODS get_all_tools
      RETURNING VALUE(rt_registry) TYPE tt_registry.

    " Builds the OpenAI "tools" JSON array from all registered tool schemas
    CLASS-METHODS build_tools_json
      IMPORTING
        !it_tool_names  TYPE string_table OPTIONAL  " subset filter; empty = all
      RETURNING VALUE(rv_json) TYPE string.

  PROTECTED SECTION.
  PRIVATE SECTION.
    CLASS-DATA mt_registry    TYPE tt_registry.
    CLASS-DATA mv_initialized TYPE abap_bool.
ENDCLASS.



CLASS zcl_ai_tool_factory IMPLEMENTATION.


  METHOD initialize.

    " The registry is CLASS-DATA and survives across program runs in the same
    " session. Tool instances cache the context (and its LLM client) handed to
    " them on first init. If we just returned here, a later run with a different
    " provider/key (e.g. switching OpenAI -> Anthropic) would leave the tools
    " pointing at the OLD client - their internal ask() calls would then use the
    " wrong auth (e.g. Bearer for Anthropic -> "Invalid bearer token"). So on a
    " repeat call, re-point every cached tool at the current context.
    IF mv_initialized = abap_true.
      LOOP AT mt_registry INTO DATA(ls_existing).
        ls_existing-instance->init( io_context ).
      ENDLOOP.
      RETURN.
    ENDIF.

    " Find ALL active classes implementing ZIF_AI_TOOL directly...
    SELECT clsname
      FROM seometarel
      INTO TABLE @DATA(lt_implementers)
      WHERE refclsname = 'ZIF_AI_TOOL'
        AND reltype    = '1'
        AND version    = '1'.

    " ...and all subclasses of ZCL_AITOOL_BASE (they inherit the interface
    " from the base class and have no own SEOMETAREL interface entry)
    SELECT clsname
      FROM seometarel
      APPENDING TABLE @lt_implementers
      WHERE refclsname = 'ZCL_AITOOL_BASE'
        AND reltype    = '2'
        AND version    = '1'.

    SORT lt_implementers BY clsname.
    DELETE ADJACENT DUPLICATES FROM lt_implementers COMPARING clsname.

    LOOP AT lt_implementers INTO DATA(ls_impl).
      DATA lo_tool TYPE REF TO zif_ai_tool.
      CLEAR lo_tool.
      TRY.
          CREATE OBJECT lo_tool TYPE (ls_impl-clsname).
        CATCH cx_sy_create_object_error.
          " abstract / CREATE PRIVATE / broken class - skip silently
          CONTINUE.
      ENDTRY.

      lo_tool->init( io_context ).

      IF lo_tool->is_active( ) = abap_false.
        CONTINUE.
      ENDIF.

      DATA(lv_name) = lo_tool->get_tool_name( ).
      IF lv_name IS INITIAL.
        CONTINUE.
      ENDIF.

      " Duplicate-name guard: first registration wins, duplicate is reported
      READ TABLE mt_registry TRANSPORTING NO FIELDS
        WITH KEY tool_name = lv_name.
      IF sy-subrc = 0.
        MESSAGE |Duplicate AI tool name '{ lv_name }' in { ls_impl-clsname }| TYPE 'S'.
        CONTINUE.
      ENDIF.

      APPEND VALUE #( tool_name = lv_name
                      instance  = lo_tool ) TO mt_registry.
    ENDLOOP.

    mv_initialized = abap_true.

  ENDMETHOD.


  METHOD get_tool.

    READ TABLE mt_registry INTO DATA(ls_reg)
      WITH KEY tool_name = i_tool_name.
    IF sy-subrc = 0.
      ro_tool = ls_reg-instance.
    ENDIF.

  ENDMETHOD.


  METHOD get_all_tools.

    rt_registry = mt_registry.

  ENDMETHOD.


  METHOD build_tools_json.

    DATA lv_schemas TYPE string.

    LOOP AT mt_registry INTO DATA(ls_reg).
      " Optional subset filter - keeps each LLM call at <= 5 tools
      IF it_tool_names IS SUPPLIED AND lines( it_tool_names ) > 0.
        READ TABLE it_tool_names TRANSPORTING NO FIELDS
          WITH KEY table_line = ls_reg-tool_name.
        IF sy-subrc <> 0.
          CONTINUE.
        ENDIF.
      ENDIF.

      DATA(lv_schema) = ls_reg-instance->get_schema( ).
      IF lv_schema IS INITIAL.
        " tool without a schema file cannot be offered to the LLM
        MESSAGE |AI tool '{ ls_reg-tool_name }' has no schema - skipped| TYPE 'S'.
        CONTINUE.
      ENDIF.

      IF lv_schemas IS NOT INITIAL.
        lv_schemas = lv_schemas && ','.
      ENDIF.
      lv_schemas = lv_schemas && lv_schema.
    ENDLOOP.

    rv_json = |[{ lv_schemas }]|.

  ENDMETHOD.
ENDCLASS.
