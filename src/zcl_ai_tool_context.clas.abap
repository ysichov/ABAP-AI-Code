CLASS zcl_ai_tool_context DEFINITION
  PUBLIC
  CREATE PUBLIC.

  PUBLIC SECTION.
    " Shared dependencies handed to every tool by the factory
    DATA mo_llm         TYPE REF TO zcl_abapai_llm_client.
    DATA mo_prompts     TYPE REF TO zcl_ai_agents_prompts.
    DATA mo_messages    TYPE REF TO zcl_ai_messages.
    DATA mv_agents_path TYPE string.

    METHODS constructor
      IMPORTING
        !io_llm         TYPE REF TO zcl_abapai_llm_client
        !io_prompts     TYPE REF TO zcl_ai_agents_prompts OPTIONAL
        !io_messages    TYPE REF TO zcl_ai_messages OPTIONAL
        !i_agents_path  TYPE string.

    " Reads <filename> from the agents folder. Returns '' when missing.
    METHODS read_agent_file
      IMPORTING
        !i_filename       TYPE string
      RETURNING VALUE(rv_content) TYPE string.

  PROTECTED SECTION.
  PRIVATE SECTION.
    TYPES tt_strings TYPE STANDARD TABLE OF string WITH NON-UNIQUE DEFAULT KEY.
ENDCLASS.



CLASS zcl_ai_tool_context IMPLEMENTATION.


  METHOD constructor.

    mo_llm         = io_llm.
    mo_prompts     = io_prompts.
    mo_messages    = io_messages.
    mv_agents_path = i_agents_path.

  ENDMETHOD.


  METHOD read_agent_file.

    DATA lt_lines TYPE tt_strings.

    DATA(lv_path) = mv_agents_path.
    REPLACE ALL OCCURRENCES OF '\' IN lv_path WITH '/'.
    IF lv_path IS NOT INITIAL.
      DATA(lv_last_offset) = strlen( lv_path ) - 1.
      IF lv_path+lv_last_offset(1) <> '/'.
        lv_path = lv_path && '/'.
      ENDIF.
    ENDIF.
    lv_path = lv_path && i_filename.

    cl_gui_frontend_services=>gui_upload(
      EXPORTING
        filename = lv_path
        filetype = 'ASC'
      CHANGING
        data_tab = lt_lines
      EXCEPTIONS
        OTHERS   = 1 ).

    IF sy-subrc <> 0.
      CLEAR rv_content.
      RETURN.
    ENDIF.

    LOOP AT lt_lines INTO DATA(lv_line).
      IF rv_content IS NOT INITIAL.
        rv_content = rv_content && cl_abap_char_utilities=>newline.
      ENDIF.
      rv_content = rv_content && lv_line.
    ENDLOOP.

  ENDMETHOD.
ENDCLASS.
