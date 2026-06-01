CLASS zcl_ai_agents_prompts DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    CONSTANTS:
      c_agent_orchestrator      TYPE string VALUE 'ORCHESTRATOR',
      c_agent_task_orchestrator TYPE string VALUE 'TASK_ORCHESTRATOR',
      c_agent_code_search       TYPE string VALUE 'CODE_SEARCH',
      c_agent_code_change       TYPE string VALUE 'CODE_CHANGE',
      c_agent_code_review       TYPE string VALUE 'CODE_REVIEW',
      c_agent_data_search       TYPE string VALUE 'DATA_SEARCH',
      c_agent_create_obj        TYPE string VALUE 'CREATE_OBJECT',
      c_agent_save              TYPE string VALUE 'AGENT_SAVE',
      c_agent_code_extract      TYPE string VALUE 'CODE_EXTRACT',
      c_agent_code_diff         TYPE string VALUE 'CODE_DIFF',
      c_agent_code_reader       TYPE string VALUE 'CODE_READER'.

    METHODS constructor
      IMPORTING
        !i_agents_path TYPE string.

    METHODS get_orchestrator_prompt
      RETURNING VALUE(rv_prompt) TYPE string.

    METHODS get_system_prompt_prefix
      RETURNING VALUE(rv_prompt) TYPE string.

    METHODS get_task_orchestrator_prompt
      RETURNING VALUE(rv_prompt) TYPE string.

    METHODS get_code_agent_prompt
      RETURNING VALUE(rv_prompt) TYPE string.

    METHODS get_data_agent_prompt
      RETURNING VALUE(rv_prompt) TYPE string.

    METHODS get_code_review_prompt
      RETURNING VALUE(rv_prompt) TYPE string.

    METHODS get_create_object_prompt
      RETURNING VALUE(rv_prompt) TYPE string.

    METHODS get_code_reader_prompt
      RETURNING VALUE(rv_prompt) TYPE string.

    METHODS get_prompt_by_agent
      IMPORTING i_agent          TYPE string
      RETURNING VALUE(rv_prompt) TYPE string.

  PROTECTED SECTION.
  PRIVATE SECTION.
    TYPES:
      tt_strings TYPE STANDARD TABLE OF string WITH NON-UNIQUE DEFAULT KEY.

    DATA mv_agents_path              TYPE string.
    DATA mv_system_prompt            TYPE string.
    DATA mv_orchestrator_prompt      TYPE string.
    DATA mv_task_orchestrator_prompt TYPE string.
    DATA mv_code_review_prompt       TYPE string.

    METHODS load_agent_prompts.

    METHODS read_prompt_file
      IMPORTING
        !i_filename       TYPE string
      RETURNING
        VALUE(rv_content) TYPE string.

    METHODS build_agent_prompt
      IMPORTING
        !i_agent_filename TYPE string
      RETURNING
        VALUE(rv_prompt)  TYPE string.

    METHODS build_file_path
      IMPORTING
        !i_filename     TYPE string
      RETURNING
        VALUE(rv_path)  TYPE string.
ENDCLASS.



CLASS zcl_ai_agents_prompts IMPLEMENTATION.


  METHOD build_agent_prompt.

    rv_prompt = get_system_prompt_prefix( )
             && read_prompt_file( i_agent_filename ).

  ENDMETHOD.


  METHOD build_file_path.

    rv_path = mv_agents_path.
    REPLACE ALL OCCURRENCES OF '\' IN rv_path WITH '/'.

    IF rv_path IS INITIAL.
      rv_path = i_filename.
      RETURN.
    ENDIF.

    DATA(lv_last_offset) = strlen( rv_path ) - 1.
    IF rv_path+lv_last_offset(1) <> '/'.
      rv_path = rv_path && '/'.
    ENDIF.

    rv_path = rv_path && i_filename.

  ENDMETHOD.


  METHOD constructor.

    mv_agents_path = i_agents_path.
    load_agent_prompts( ).

  ENDMETHOD.


  METHOD get_code_agent_prompt.

    rv_prompt = |CODE_SEARCH is a command, not an LLM agent.|.

  ENDMETHOD.


  METHOD get_code_reader_prompt.

    rv_prompt = |CODE_READER is a command, not an LLM agent.|.

  ENDMETHOD.


  METHOD get_code_review_prompt.

    rv_prompt = mv_code_review_prompt.

  ENDMETHOD.


  METHOD get_create_object_prompt.

    rv_prompt = |CREATE_OBJECT is a command, not an LLM agent.|.

  ENDMETHOD.


  METHOD get_data_agent_prompt.

    rv_prompt = |DATA_SEARCH is a command, not an LLM agent.|.

  ENDMETHOD.


  METHOD get_orchestrator_prompt.

    rv_prompt = mv_orchestrator_prompt.

  ENDMETHOD.


  METHOD get_prompt_by_agent.

    CASE i_agent.
      WHEN c_agent_orchestrator.
        rv_prompt = get_orchestrator_prompt( ).
      WHEN c_agent_task_orchestrator OR 'TASK_ORCHESTRATOR'.
        rv_prompt = get_task_orchestrator_prompt( ).
      WHEN c_agent_code_search.
        rv_prompt = |CODE_SEARCH is a command, not an LLM agent.|.
      WHEN c_agent_code_change.
        rv_prompt = |CODE_CHANGE is a command, not an LLM agent.|.
      WHEN c_agent_code_review.
        rv_prompt = get_code_review_prompt( ).
      WHEN c_agent_data_search.
        rv_prompt = get_data_agent_prompt( ).
      WHEN c_agent_create_obj.
        rv_prompt = get_create_object_prompt( ).
      WHEN c_agent_save.
        rv_prompt = |AGENT_SAVE is a command, not an LLM agent.|.
      WHEN c_agent_code_extract.
        rv_prompt = |CODE_EXTRACT is a command, not an LLM agent.|.
      WHEN c_agent_code_diff.
        rv_prompt = |CODE_DIFF is a command, not an LLM agent.|.
      WHEN c_agent_code_reader.
        rv_prompt = get_code_reader_prompt( ).
      WHEN OTHERS.
        rv_prompt = |Agent '{ i_agent }' not found|.
    ENDCASE.

  ENDMETHOD.


  METHOD get_system_prompt_prefix.

    rv_prompt = mv_system_prompt.
    IF rv_prompt IS NOT INITIAL.
      rv_prompt = rv_prompt
               && cl_abap_char_utilities=>newline
               && cl_abap_char_utilities=>newline.
    ENDIF.

  ENDMETHOD.


  METHOD get_task_orchestrator_prompt.

    rv_prompt = mv_task_orchestrator_prompt.

  ENDMETHOD.


  METHOD load_agent_prompts.

    mv_system_prompt = read_prompt_file( 'system.md' ).
    mv_orchestrator_prompt = build_agent_prompt( 'orchestrator.md' ).
    mv_task_orchestrator_prompt = build_agent_prompt( 'task_orchestrator.md' ).
    mv_code_review_prompt = build_agent_prompt( 'code_review.md' ).

  ENDMETHOD.


  METHOD read_prompt_file.

    DATA lt_lines TYPE tt_strings.
    DATA(lv_filename) = build_file_path( i_filename ).

    cl_gui_frontend_services=>gui_upload(
      EXPORTING
        filename                = lv_filename
        filetype                = 'ASC'
      CHANGING
        data_tab                = lt_lines
      EXCEPTIONS
        file_open_error         = 1
        file_read_error         = 2
        no_batch                = 3
        gui_refuse_filetransfer = 4
        invalid_type            = 5
        no_authority            = 6
        unknown_error           = 7
        bad_data_format         = 8
        header_not_allowed      = 9
        separator_not_allowed   = 10
        header_too_long         = 11
        unknown_dp_error        = 12
        access_denied           = 13
        dp_out_of_memory        = 14
        disk_full               = 15
        dp_timeout              = 16
        not_supported_by_gui    = 17
        error_no_gui            = 18
        OTHERS                  = 19 ).

    IF sy-subrc <> 0.
      rv_content = |Prompt file cannot be read: { lv_filename }|.
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
