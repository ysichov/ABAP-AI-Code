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

  methods SPLIT_TASK_LIST
    importing
      !I_TEXT type STRING
    returning
      value(RT_TASKS) type TT_STRINGS .
  methods ENRICH_TASKS_WITH_ANSWERS
    importing
      !IT_TASKS type TT_STRINGS
    returning
      value(RT_TASKS) type TT_STRINGS .
  methods STRIP_TASK_LABELS
    importing
      !IT_TASKS type TT_STRINGS
    returning
      value(RT_TASKS) type TT_STRINGS .
ENDCLASS.



CLASS ZCL_TASK_PLANNER IMPLEMENTATION.


  method CONSTRUCTOR.

    mo_messages = io_messages.
    mo_llm = io_llm.
    mo_prompts = io_prompts.

  endmethod.


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

    DATA(lv_task_prompt) = mo_prompts->get_task_orchestrator_prompt( )
                          && cl_abap_char_utilities=>newline
                          && i_prompt.
    mo_messages->add_message(
      i_role        = 'user'
      i_agent       = zcl_ai_agents_prompts=>c_agent_task_orchestrator
      i_prompt_type = 'AGENT_PROMPT'
      i_content     = lv_task_prompt ).

    DATA(lv_task_answer) = mo_llm->ask( lv_task_prompt ).

    mo_messages->add_message(
      i_role        = 'assistant'
      i_agent       = zcl_ai_agents_prompts=>c_agent_task_orchestrator
      i_prompt_type = 'LLM_RESPONSE'
      i_duration_seconds = mo_llm->get_last_seconds( )
      i_content     = lv_task_answer ).

    rt_tasks = split_task_list( lv_task_answer ).
    rt_tasks = enrich_tasks_with_answers( rt_tasks ).
    rt_tasks = strip_task_labels( rt_tasks ).

  endmethod.


  method SPLIT_TASK_LIST.

    DATA(lv_text) = i_text.
    DATA(lv_nl) = cl_abap_char_utilities=>newline.

    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf IN lv_text WITH lv_nl.
    REPLACE ALL OCCURRENCES OF REGEX '\s+(TASK\s*[0-9]+(\.[0-9]+)?(\s*-\s*ASK\s*[0-9]+|-ASK[0-9]+)?:)'
      IN lv_text WITH |{ lv_nl }$1|.

    DATA lt_lines TYPE tt_strings.
    SPLIT lv_text AT lv_nl INTO TABLE lt_lines.

    LOOP AT lt_lines INTO DATA(lv_line).
      CONDENSE lv_line.
      DATA(lv_line_upper) = lv_line.
      TRANSLATE lv_line_upper TO UPPER CASE.
      CHECK lv_line_upper CP 'TASK*'.
      APPEND lv_line TO rt_tasks.
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
