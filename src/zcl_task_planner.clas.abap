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


ENDCLASS.
