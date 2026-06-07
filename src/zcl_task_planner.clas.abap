class ZCL_TASK_PLANNER definition
  public
  create public .

public section.

  types:
    tt_strings TYPE STANDARD TABLE OF string WITH NON-UNIQUE DEFAULT KEY .

  methods CONSTRUCTOR
    importing
      !IO_MESSAGES type ref to ZCL_AI_MESSAGES
      !IO_LLM type ref to ZCL_LLM_CLIENT
      !IO_PROMPTS type ref to ZCL_AI_AGENTS_PROMPTS .
  methods PREPARE_TASK_LIST
    importing
      !I_PROMPT type STRING
    returning
      value(RT_TASKS) type TT_STRINGS .
protected section.
private section.

  data MO_MESSAGES type ref to ZCL_AI_MESSAGES .
  data MO_LLM type ref to ZCL_LLM_CLIENT .
  data MO_PROMPTS type ref to ZCL_AI_AGENTS_PROMPTS .

  methods PARSE_JSON_TASKS
    importing
      !I_JSON type STRING
    returning
      value(RT_TASKS) type TT_STRINGS .
  methods DETERMINE_AGENT
    importing
      !I_ACTION type STRING
    returning
      value(RV_AGENT) type STRING .
ENDCLASS.



CLASS ZCL_TASK_PLANNER IMPLEMENTATION.


  method CONSTRUCTOR.

    mo_messages = io_messages.
    mo_llm = io_llm.
    mo_prompts = io_prompts.

  endmethod.


  method PARSE_JSON_TASKS.

    " Types matching task_orchestrator.JSON schema
    TYPES: BEGIN OF ty_task,
             task_id                TYPE string,
             target_tool            TYPE string,
             sap_object_type        TYPE string,
             sap_object_name        TYPE string,
             action_description     TYPE string,
             depends_on_task_id     TYPE string,
             requires_clarification TYPE abap_bool,
             clarification_question TYPE string,
           END OF ty_task,
           tt_json_tasks TYPE STANDARD TABLE OF ty_task WITH NON-UNIQUE DEFAULT KEY,
           BEGIN OF ty_response,
             is_pure_code_request  TYPE abap_bool,
             pure_code_object_type TYPE string,
             pure_code_object_name TYPE string,
             summary               TYPE string,
             tasks                 TYPE tt_json_tasks,
           END OF ty_response.

    DATA ls_response TYPE ty_response.
    /ui2/cl_json=>deserialize( EXPORTING json = i_json CHANGING data = ls_response ).

    " Handle pure "show code" request - return single CODE_SEARCH command
    IF ls_response-is_pure_code_request = abap_true.
      DATA(lv_obj_type) = ls_response-pure_code_object_type.
      DATA(lv_obj_name) = ls_response-pure_code_object_name.
      CONDENSE lv_obj_type.
      CONDENSE lv_obj_name.
      IF lv_obj_name IS NOT INITIAL.
        APPEND |{ '{' }AGENT:CODE_SEARCH { lv_obj_type } { lv_obj_name }{ '}' }| TO rt_tasks.
      ENDIF.
      RETURN.
    ENDIF.

    " Process structured task list - build agent command strings directly
    LOOP AT ls_response-tasks INTO DATA(ls_task).

      " Ask clarification via popup if required
      IF ls_task-requires_clarification = abap_true
      AND ls_task-clarification_question IS NOT INITIAL.
        DATA lt_fields TYPE TABLE OF sval.
        CLEAR lt_fields.
        APPEND VALUE #(
          tabname   = 'TLINE'
          fieldname = 'TDLINE'
          value     = '' ) TO lt_fields.

        CALL FUNCTION 'POPUP_GET_VALUES'
          EXPORTING
            popup_title = CONV text80( |{ ls_task-task_id }: { ls_task-clarification_question }| )
          TABLES
            fields      = lt_fields
          EXCEPTIONS
            error_in_fields = 1
            OTHERS          = 2.

        IF sy-subrc = 0.
          READ TABLE lt_fields INTO DATA(ls_field) INDEX 1.
          IF ls_field-value IS NOT INITIAL.
            DATA(lv_clarification) = CONV string( ls_field-value ).
            CONDENSE lv_clarification.
            ls_task-action_description =
              ls_task-action_description
              && | (User clarification: { lv_clarification })|.
            mo_messages->add_message(
              i_role        = 'user'
              i_agent       = zcl_ai_agents_prompts=>c_agent_task_orchestrator
              i_prompt_type = 'TASK_ANSWER'
              i_content     = |{ ls_task-task_id }: { ls_task-clarification_question } -> { lv_clarification }| ).
          ENDIF.
        ELSE.
          MESSAGE |Task clarification skipped: { ls_task-task_id }| TYPE 'S'.
        ENDIF.
      ENDIF.

      " Map target_tool to agent command
      DATA lv_agent TYPE string.
      CASE ls_task-target_tool.
        WHEN 'ZCL_AI_TOOL=>READ'.
          lv_agent = 'CODE_SEARCH'.
        WHEN 'ZCL_AI_TOOL=>SAVE'.
          lv_agent = 'CODE_CHANGE'.
        WHEN 'NONE' OR ''.
          " No SAP object involved - skip as standalone task text
          APPEND ls_task-action_description TO rt_tasks.
          CONTINUE.
        WHEN OTHERS.
          " Fallback: infer from action description keywords
          lv_agent = determine_agent( ls_task-action_description ).
      ENDCASE.

      DATA(lv_type) = ls_task-sap_object_type.
      DATA(lv_name) = ls_task-sap_object_name.
      CONDENSE lv_type.
      CONDENSE lv_name.

      " Format: {AGENT:CMD TYPE NAME} action_description
      APPEND |{ '{' }AGENT:{ lv_agent } { lv_type } { lv_name }{ '}' } { ls_task-action_description }|
        TO rt_tasks.
    ENDLOOP.

  endmethod.


  method DETERMINE_AGENT.

    " Infer agent command type from action description keywords
    DATA lv_upper TYPE string.
    lv_upper = i_action.
    TRANSLATE lv_upper TO UPPER CASE.

    IF lv_upper CS 'REVIEW' OR lv_upper CS 'INSPECT' OR lv_upper CS 'AUDIT'.
      rv_agent = 'CODE_REVIEW'.
    ELSEIF lv_upper CS 'READ'    OR lv_upper CS 'ANALYZ' OR lv_upper CS 'IDENTIF'
        OR lv_upper CS 'FIND'    OR lv_upper CS 'EXAMIN' OR lv_upper CS 'SEARCH'
        OR lv_upper CS 'LOOK AT' OR lv_upper CS 'LOCATE'.
      rv_agent = 'CODE_SEARCH'.
    ELSE.
      " Default: modification task
      rv_agent = 'CODE_CHANGE'.
    ENDIF.

  endmethod.


  " --- Kept for backward compatibility but no longer called ---
  method ENRICH_TASKS_WITH_ANSWERS.

    rt_tasks = it_tasks.

    LOOP AT it_tasks INTO DATA(lv_task_line).
      DATA(lv_task_upper) = lv_task_line.
      TRANSLATE lv_task_upper TO UPPER CASE.
      CHECK lv_task_upper CS '-ASK'.

      DATA(lv_colon_off) = 0.
      FIND FIRST OCCURRENCE OF ':' IN lv_task_line MATCH OFFSET lv_colon_off.
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.

      DATA(lv_ask_key) = substring( val = lv_task_line len = lv_colon_off ).
      DATA(lv_question_start) = lv_colon_off + 1.
      DATA(lv_question) = substring( val = lv_task_line off = lv_question_start ).
      CONDENSE lv_ask_key.
      CONDENSE lv_question.

      DATA(lv_base_key) = lv_ask_key.
      REPLACE FIRST OCCURRENCE OF REGEX '\s*-\s*ASK\s*[0-9]+$' IN lv_base_key WITH ''.
      REPLACE FIRST OCCURRENCE OF REGEX '-ASK[0-9]+$' IN lv_base_key WITH ''.
      CONDENSE lv_base_key.

      DATA lt_fields TYPE TABLE OF sval.
      APPEND VALUE #(
        tabname   = 'TLINE'
        fieldname = 'TDLINE'
        value     = '' ) TO lt_fields.

      CALL FUNCTION 'POPUP_GET_VALUES'
        EXPORTING
          popup_title = CONV text80( |{ lv_ask_key }: { lv_question }| )
        TABLES
          fields      = lt_fields
        EXCEPTIONS
          error_in_fields = 1
          OTHERS          = 2.

      DATA(lv_answer) = VALUE string( ).
      IF sy-subrc = 0.
        READ TABLE lt_fields INTO DATA(ls_field) INDEX 1.
        IF sy-subrc = 0.
          lv_answer = ls_field-value.
          CONDENSE lv_answer.
        ENDIF.
      ENDIF.

      IF lv_answer IS INITIAL.
        MESSAGE |Task clarification skipped: { lv_ask_key }| TYPE 'S'.
        CONTINUE.
      ENDIF.

      mo_messages->add_message(
        i_role        = 'user'
        i_agent       = zcl_ai_agents_prompts=>c_agent_task_orchestrator
        i_prompt_type = 'TASK_ANSWER'
        i_content     = |{ lv_ask_key }: { lv_question } -> { lv_answer }| ).

      LOOP AT rt_tasks ASSIGNING FIELD-SYMBOL(<task_to_enrich>).
        DATA(lv_enrich_upper) = <task_to_enrich>.
        TRANSLATE lv_enrich_upper TO UPPER CASE.
        CHECK NOT lv_enrich_upper CS '-ASK'.

        DATA(lv_current_key) = <task_to_enrich>.
        FIND FIRST OCCURRENCE OF ':' IN lv_current_key MATCH OFFSET DATA(lv_current_colon).
        IF sy-subrc = 0.
          lv_current_key = substring( val = lv_current_key len = lv_current_colon ).
        ENDIF.
        CONDENSE lv_current_key.

        IF lv_current_key = lv_base_key.
          <task_to_enrich> = <task_to_enrich>
                          && | Clarification for { lv_ask_key }: { lv_question } Answer: { lv_answer }|.
          EXIT.
        ENDIF.
      ENDLOOP.
    ENDLOOP.

    DATA lt_filtered_tasks TYPE tt_strings.
    LOOP AT rt_tasks INTO DATA(lv_filtered_task).
      DATA(lv_filtered_upper) = lv_filtered_task.
      TRANSLATE lv_filtered_upper TO UPPER CASE.
      CHECK NOT lv_filtered_upper CS '-ASK'.
      APPEND lv_filtered_task TO lt_filtered_tasks.
    ENDLOOP.
    rt_tasks = lt_filtered_tasks.

  endmethod.


  method PREPARE_TASK_LIST.

    CALL FUNCTION 'SAPGUI_PROGRESS_INDICATOR'
      EXPORTING percentage = 10 text = 'Asking task orchestrator...'.

    " System prompt (persona/rules) goes to system role
    " User prompt (actual request) goes to user role - separated for better model behavior
    DATA(lv_system_prompt) = mo_prompts->get_task_orchestrator_prompt( ).
    DATA(lv_user_prompt)   = i_prompt.

    mo_messages->add_message(
      i_role        = 'system'
      i_agent       = zcl_ai_agents_prompts=>c_agent_task_orchestrator
      i_prompt_type = 'SYSTEM_PROMPT'
      i_content     = lv_system_prompt ).

    mo_messages->add_message(
      i_role        = 'user'
      i_agent       = zcl_ai_agents_prompts=>c_agent_task_orchestrator
      i_prompt_type = 'AGENT_PROMPT'
      i_content     = lv_user_prompt ).

    " Load JSON schema for this agent (optional - empty if no .JSON file exists)
    DATA(lv_schema) = mo_prompts->get_schema_by_agent( zcl_ai_agents_prompts=>c_agent_task_orchestrator ).
    DATA(lv_task_answer) = mo_llm->ask(
      i_prompt        = lv_user_prompt
      i_system_prompt = lv_system_prompt
      i_json_schema   = lv_schema ).

    mo_messages->add_message(
      i_role        = 'assistant'
      i_agent       = zcl_ai_agents_prompts=>c_agent_task_orchestrator
      i_prompt_type = 'LLM_RESPONSE'
      i_duration_seconds = mo_llm->get_last_seconds( )
      i_tok_in      = mo_llm->mv_last_tok_in
      i_tok_out     = mo_llm->mv_last_tok_out
      i_content     = lv_task_answer ).

    " Parse structured JSON response into agent command strings
    rt_tasks = parse_json_tasks( zcl_ai_messages=>strip_log_info( lv_task_answer ) ).

  endmethod.


  method SPLIT_TASK_LIST.

    DATA(lv_text) = i_text.
    DATA(lv_nl) = cl_abap_char_utilities=>newline.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf IN lv_text WITH lv_nl.

    " If no TASK-prefixed lines but answer is a direct agent command - return as single task
    DATA(lv_text_upper_check) = lv_text.
    TRANSLATE lv_text_upper_check TO UPPER CASE.
    IF lv_text_upper_check CP '{AGENT:*}' AND NOT lv_text_upper_check CS 'TASK'.
      DATA(lv_direct_cmd) = lv_text.
      CONDENSE lv_direct_cmd.
      APPEND lv_direct_cmd TO rt_tasks.
      RETURN.
    ENDIF.

    " Split by <TASK>...</TASK> tags
    DATA(lv_text_tag_check) = lv_text_upper_check.
    IF lv_text_tag_check CS '<TASK>'.
      DATA(lv_rest) = lv_text.
      WHILE lv_rest CS '<TASK>' OR lv_rest CS '<task>'.
        DATA(lv_open_pos)  = 0.
        DATA(lv_close_pos) = 0.
        FIND FIRST OCCURRENCE OF REGEX '<TASK>' IN lv_rest
          MATCH OFFSET lv_open_pos IGNORING CASE.
        IF sy-subrc <> 0. EXIT. ENDIF.
        DATA(lv_after_open) = lv_open_pos + 6.
        DATA(lv_inner_rest) = substring( val = lv_rest off = lv_after_open ).
        FIND FIRST OCCURRENCE OF REGEX '</TASK>' IN lv_inner_rest
          MATCH OFFSET lv_close_pos IGNORING CASE.
        IF sy-subrc <> 0. EXIT. ENDIF.
        DATA(lv_block) = substring( val = lv_inner_rest len = lv_close_pos ).
        CONDENSE lv_block.
        IF lv_block IS NOT INITIAL.
          APPEND lv_block TO rt_tasks.
        ENDIF.
        lv_rest = substring( val = lv_inner_rest off = lv_close_pos + 7 ).
      ENDWHILE.
      IF rt_tasks IS NOT INITIAL.
        RETURN.
      ENDIF.
    ENDIF.

    " Fallback: old merge logic by TASK N / TASK N.N prefixes
    REPLACE ALL OCCURRENCES OF REGEX '\s+(TASK\s*[0-9]+(\.[0-9]+)?(\s*-\s*ASK\s*[0-9]+|-ASK[0-9]+)?:)'
      IN lv_text WITH |{ lv_nl }$1|.
    REPLACE ALL OCCURRENCES OF REGEX '\s+([0-9]+\.[0-9]+:)'
      IN lv_text WITH |{ lv_nl }$1|.

    DATA lt_lines TYPE tt_strings.
    SPLIT lv_text AT lv_nl INTO TABLE lt_lines.

    LOOP AT lt_lines INTO DATA(lv_line).
      CONDENSE lv_line.
      DATA(lv_line_upper) = lv_line.
      TRANSLATE lv_line_upper TO UPPER CASE.
      DATA(lv_is_task_line) = abap_false.
      IF lv_line_upper CP 'TASK*'.
        lv_is_task_line = abap_true.
      ELSE.
        FIND FIRST OCCURRENCE OF REGEX '^[0-9]+\.[0-9]+:' IN lv_line_upper.
        IF sy-subrc = 0. lv_is_task_line = abap_true. ENDIF.
      ENDIF.
      CHECK lv_is_task_line = abap_true.

      IF lv_line_upper CS '-ASK'.
        APPEND lv_line TO rt_tasks.
        CONTINUE.
      ENDIF.

      DATA(lv_colon_pos) = 0.
      FIND FIRST OCCURRENCE OF ':' IN lv_line MATCH OFFSET lv_colon_pos.
      IF sy-subrc <> 0.
        APPEND lv_line TO rt_tasks.
        CONTINUE.
      ENDIF.

      DATA(lv_task_key) = substring( val = lv_line len = lv_colon_pos ).
      DATA(lv_task_text) = substring( val = lv_line off = lv_colon_pos + 1 ).
      CONDENSE lv_task_key.
      CONDENSE lv_task_text.

      DATA(lv_root_key) = lv_task_key.
      REPLACE FIRST OCCURRENCE OF REGEX '^TASK\s+' IN lv_root_key WITH 'TASK' IGNORING CASE.
      REPLACE FIRST OCCURRENCE OF REGEX '^([0-9]+)\.[0-9]+$' IN lv_root_key WITH 'TASK$1'.
      REPLACE FIRST OCCURRENCE OF REGEX '^([0-9]+)$' IN lv_root_key WITH 'TASK$1'.
      REPLACE FIRST OCCURRENCE OF REGEX '\.[0-9]+$' IN lv_root_key WITH ''.
      CONDENSE lv_root_key.

      DATA(lv_merged) = abap_false.
      LOOP AT rt_tasks ASSIGNING FIELD-SYMBOL(<task_line>).
        DATA(lv_existing_key) = <task_line>.
        FIND FIRST OCCURRENCE OF ':' IN lv_existing_key MATCH OFFSET DATA(lv_existing_colon).
        IF sy-subrc = 0.
          lv_existing_key = substring( val = lv_existing_key len = lv_existing_colon ).
        ENDIF.
        REPLACE FIRST OCCURRENCE OF REGEX '^TASK\s+' IN lv_existing_key WITH 'TASK' IGNORING CASE.
        REPLACE FIRST OCCURRENCE OF REGEX '^([0-9]+)$' IN lv_existing_key WITH 'TASK$1'.
        CONDENSE lv_existing_key.
        IF lv_existing_key = lv_root_key.
          <task_line> = <task_line> && |; { lv_task_text }|.
          lv_merged = abap_true.
          EXIT.
        ENDIF.
      ENDLOOP.

      IF lv_merged = abap_false.
        APPEND |{ lv_root_key }: { lv_task_text }| TO rt_tasks.
      ENDIF.
    ENDLOOP.

  endmethod.


  method STRIP_TASK_LABELS.

    LOOP AT it_tasks INTO DATA(lv_task).
      REPLACE FIRST OCCURRENCE OF REGEX '^TASK\s*[0-9]+(\.[0-9]+)?\s*:\s*'
        IN lv_task WITH '' IGNORING CASE.
      CONDENSE lv_task.
      IF lv_task IS NOT INITIAL.
        APPEND lv_task TO rt_tasks.
      ENDIF.
    ENDLOOP.

  endmethod.
ENDCLASS.
