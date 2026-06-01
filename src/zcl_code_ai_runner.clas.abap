class ZCL_CODE_AI_RUNNER definition
  public
  create public .

public section.

  types:
    BEGIN OF ty_result,
      answer       TYPE string,
      answer_log   TYPE string,
      resolved_code TYPE string,
      messages     TYPE zcl_ai_messages=>tt_messages,
      messages_ref TYPE REF TO zcl_ai_messages,
      has_diff     TYPE abap_bool,
      diff_old_code TYPE string,
      diff_new_code TYPE string,
      diff_object_type TYPE string,
      diff_object_name TYPE string,
    END OF ty_result .

  methods CONSTRUCTOR
    importing
      !IO_LLM type ref to ZCL_LLM_CLIENT
      !IO_PROMPTS type ref to ZCL_AI_AGENTS_PROMPTS .
  methods RUN
    importing
      !I_PROMPT type STRING
      !I_SESSION_ID type I
    returning
      value(RS_RESULT) type TY_RESULT .
protected section.
private section.

  types:
    tt_strings TYPE STANDARD TABLE OF string WITH NON-UNIQUE DEFAULT KEY .

  data MO_LLM type ref to ZCL_LLM_CLIENT .
  data MO_PROMPTS type ref to ZCL_AI_AGENTS_PROMPTS .
  data MO_MESSAGES type ref to ZCL_AI_MESSAGES .
  data MO_TASK_PLANNER type ref to ZCL_TASK_PLANNER .

  methods IS_REVIEW_REQUESTED
    importing
      !I_PROMPT type STRING
    returning
      value(RV_REQUESTED) type ABAP_BOOL .
  methods BUILD_EFFECTIVE_PROMPT
    importing
      !I_PROMPT type STRING
      !IT_TASKS type TT_STRINGS
    returning
      value(RV_PROMPT) type STRING .
  methods ASK_ORCHESTRATOR
    importing
      !IT_TASKS type TT_STRINGS
    returning
      value(RV_ANSWER) type STRING .
  methods DETECT_PROMPT_LANGUAGE
    importing
      !I_PROMPT type STRING
    returning
      value(RV_LANGUAGE) type STRING .
  methods RESOLVE_AND_LOG_READ_COMMANDS
    importing
      !I_TEXT type STRING
    changing
      !CT_DONE_COMMANDS type TT_STRINGS
    returning
      value(RV_CONTEXT) type STRING .
ENDCLASS.



CLASS ZCL_CODE_AI_RUNNER IMPLEMENTATION.


  method CONSTRUCTOR.

    mo_llm = io_llm.
    mo_prompts = io_prompts.

  endmethod.


  method ASK_ORCHESTRATOR.

    CALL FUNCTION 'SAPGUI_PROGRESS_INDICATOR'
      EXPORTING percentage = 20 text = 'Asking orchestrator...'.

    IF it_tasks IS INITIAL.
      DATA(lv_orchestrator_prompt) = mo_messages->build_orchestrator_request( ).
      rv_answer = mo_llm->ask( lv_orchestrator_prompt ).

      mo_messages->add_message(
        i_role        = 'assistant'
        i_agent       = zcl_ai_agents_prompts=>c_agent_orchestrator
        i_prompt_type = 'LLM_RESPONSE'
        i_duration_seconds = mo_llm->get_last_seconds( )
        i_content     = rv_answer ).
    ELSE.
      DATA(lv_task_count) = lines( it_tasks ).
      LOOP AT it_tasks INTO DATA(lv_task).
        DATA(lv_task_idx) = sy-tabix.
        DATA(lv_task_prompt_text) = lv_task.
        REPLACE FIRST OCCURRENCE OF REGEX '^TASK\s*[0-9]+(\.[0-9]+)?\s*:\s*'
          IN lv_task_prompt_text WITH '' IGNORING CASE.
        CONDENSE lv_task_prompt_text.

        CALL FUNCTION 'SAPGUI_PROGRESS_INDICATOR'
          EXPORTING percentage = 10 + ( lv_task_idx * 20 / lv_task_count )
                    text       = |Asking orchestrator for task { lv_task_idx }...|.

        DATA(lv_task_orchestrator_prompt) = mo_prompts->get_orchestrator_prompt( )
          && cl_abap_char_utilities=>newline
          && cl_abap_char_utilities=>newline
          && |PROMPT: { lv_task_prompt_text }|.

        mo_messages->add_message(
          i_role        = 'user'
          i_agent       = zcl_ai_agents_prompts=>c_agent_orchestrator
          i_prompt_type = 'SYSTEM_PROMPT'
          i_content     = lv_task_orchestrator_prompt ).

        DATA(lv_task_orchestrator_answer) = mo_llm->ask( lv_task_orchestrator_prompt ).

        mo_messages->add_message(
          i_role        = 'assistant'
          i_agent       = zcl_ai_agents_prompts=>c_agent_orchestrator
          i_prompt_type = 'LLM_RESPONSE'
          i_duration_seconds = mo_llm->get_last_seconds( )
          i_content     = lv_task_orchestrator_answer ).

        IF rv_answer IS NOT INITIAL.
          rv_answer = rv_answer && cl_abap_char_utilities=>newline.
        ENDIF.
        rv_answer = rv_answer && lv_task_orchestrator_answer.
      ENDLOOP.
    ENDIF.

  endmethod.


  method BUILD_EFFECTIVE_PROMPT.

    rv_prompt = i_prompt.
    LOOP AT it_tasks INTO DATA(lv_task).
      rv_prompt = rv_prompt
               && cl_abap_char_utilities=>newline
               && lv_task.
    ENDLOOP.

  endmethod.


  method DETECT_PROMPT_LANGUAGE.

    CALL FUNCTION 'SAPGUI_PROGRESS_INDICATOR'
      EXPORTING percentage = 5 text = 'Detecting prompt language...'.

    DATA(lv_language_prompt) = mo_prompts->get_language_detector_prompt( )
                            && cl_abap_char_utilities=>newline
                            && cl_abap_char_utilities=>newline
                            && |PROMPT: { i_prompt }|.

    mo_messages->add_message(
      i_role        = 'user'
      i_agent       = zcl_ai_agents_prompts=>c_agent_language_detector
      i_prompt_type = 'AGENT_PROMPT'
      i_content     = lv_language_prompt ).

    rv_language = mo_llm->ask( lv_language_prompt ).
    CONDENSE rv_language.

    mo_messages->add_message(
      i_role        = 'assistant'
      i_agent       = zcl_ai_agents_prompts=>c_agent_language_detector
      i_prompt_type = 'LLM_RESPONSE'
      i_duration_seconds = mo_llm->get_last_seconds( )
      i_content     = rv_language ).

  endmethod.


  method IS_REVIEW_REQUESTED.

    DATA(lv_prompt_upper) = i_prompt.
    TRANSLATE lv_prompt_upper TO UPPER CASE.
    rv_requested = xsdbool(
      lv_prompt_upper CS 'CODE_REVIEW'
      OR lv_prompt_upper CS 'CODE REVIEW'
      OR lv_prompt_upper CS 'REVIEW'
      OR lv_prompt_upper CS 'CHECK'
      OR lv_prompt_upper CS 'SYNTAX'
      OR lv_prompt_upper CS 'ПРОВЕР'
      OR lv_prompt_upper CS 'ОШИБ'
      OR lv_prompt_upper CS 'СИНТАКС'
      OR i_prompt CS 'Провер'
      OR i_prompt CS 'провер'
      OR i_prompt CS 'Ошиб'
      OR i_prompt CS 'ошиб'
      OR i_prompt CS 'Синтакс'
      OR i_prompt CS 'синтакс' ).

  endmethod.


  method RESOLVE_AND_LOG_READ_COMMANDS.

    DATA(lt_commands) = zcl_ai_code_reader=>parse_read_commands( i_text ).

    IF lt_commands IS INITIAL.
      DATA(lv_show_rest) = i_text.
      REPLACE ALL OCCURRENCES OF REGEX '\{\s*SHOW' IN lv_show_rest WITH '{SHOW'.

      WHILE lv_show_rest CS '{SHOW'.
        FIND FIRST OCCURRENCE OF '{SHOW' IN lv_show_rest MATCH OFFSET DATA(lv_show_pos).
        lv_show_rest = substring( val = lv_show_rest off = lv_show_pos + 1 ).

        FIND FIRST OCCURRENCE OF '}' IN lv_show_rest MATCH OFFSET DATA(lv_show_end).
        IF sy-subrc <> 0.
          EXIT.
        ENDIF.

        DATA(lv_show_command) = substring( val = lv_show_rest len = lv_show_end ).
        lv_show_rest = substring( val = lv_show_rest off = lv_show_end + 1 ).

        DATA(lv_show_object) = lv_show_command.
        REPLACE FIRST OCCURRENCE OF REGEX '^SHOW\s*-?' IN lv_show_object WITH ''.
        CONDENSE lv_show_object.

        DATA lt_show_parts TYPE STANDARD TABLE OF string WITH NON-UNIQUE DEFAULT KEY.
        SPLIT lv_show_object AT space INTO TABLE lt_show_parts.
        DELETE lt_show_parts WHERE table_line IS INITIAL.
        IF lt_show_parts IS INITIAL.
          CONTINUE.
        ENDIF.

        DATA(ls_show_read_command) = VALUE zcl_ai_code_reader=>ty_read_command(
          object_type = 'REPS'
          object_name = lt_show_parts[ 1 ]
          raw_command = |{ '{' }READ TADIR: REPS { lt_show_parts[ 1 ] }{ '}' }| ).
        APPEND ls_show_read_command TO lt_commands.
      ENDWHILE.
    ENDIF.

    LOOP AT lt_commands INTO DATA(ls_command).
      DATA(lv_read_command) = ls_command-raw_command.
      DATA(lv_read_command_key) = lv_read_command.
      TRANSLATE lv_read_command_key TO UPPER CASE.
      CONDENSE lv_read_command_key.

      READ TABLE ct_done_commands
        WITH KEY table_line = lv_read_command_key
        TRANSPORTING NO FIELDS.
      IF sy-subrc = 0.
        CONTINUE.
      ENDIF.
      APPEND lv_read_command_key TO ct_done_commands.

      DATA(lv_code_context) = zcl_ai_code_reader=>resolve_read_commands( lv_read_command ).

      mo_messages->add_message(
        i_role        = 'user'
        i_agent       = zcl_ai_agents_prompts=>c_agent_code_reader
        i_prompt_type = 'COMMAND'
        i_content     = lv_read_command ).

      mo_messages->add_message(
        i_role        = 'assistant'
        i_agent       = zcl_ai_agents_prompts=>c_agent_code_reader
        i_prompt_type = 'AGENT_RESPONSE'
        i_content     = lv_code_context ).

      IF rv_context IS NOT INITIAL.
        rv_context = rv_context
                  && cl_abap_char_utilities=>newline
                  && cl_abap_char_utilities=>newline.
      ENDIF.
      rv_context = rv_context && lv_code_context.
    ENDLOOP.

  endmethod.


  method RUN.

    DATA(lv_prompt) = i_prompt.
    DATA(lv_user_requested_review) = is_review_requested( lv_prompt ).

    mo_messages = NEW zcl_ai_messages(
      i_user_prompt = lv_prompt
      io_prompts    = mo_prompts
      i_session_id  = i_session_id ).
    mo_task_planner = NEW zcl_task_planner(
      io_messages = mo_messages
      io_llm      = mo_llm
      io_prompts  = mo_prompts ).

    DATA(lv_user_language) = detect_prompt_language( lv_prompt ).
    IF lv_user_language IS NOT INITIAL.
      mo_prompts->set_user_language( lv_user_language ).
    ENDIF.

    DATA(lt_tasks) = mo_task_planner->prepare_task_list( lv_prompt ).
    DATA(lv_effective_prompt) = build_effective_prompt(
      i_prompt  = lv_prompt
      it_tasks  = lt_tasks ).
    DATA(lv_orchestrator_answer) = ask_orchestrator( lt_tasks ).

    DATA(lt_agent_requests) = mo_messages->parse_agent_requests( lv_orchestrator_answer ).
    DATA(lv_orchestrator_read_commands) = zcl_ai_code_reader=>extract_read_command_text( lv_orchestrator_answer ).
    DATA lv_orchestrator_code_context TYPE string.
    DATA(lv_orchestrator_upper) = lv_orchestrator_answer.
    TRANSLATE lv_orchestrator_upper TO UPPER CASE.

    DATA(lv_answer) = lv_orchestrator_answer.
    DATA(lv_answer_log) = lv_answer.
    DATA lv_resolved_code TYPE string.
    DATA lv_final_duration_seconds TYPE string.

    IF lt_agent_requests IS INITIAL
    AND lv_orchestrator_read_commands IS INITIAL
    AND lv_orchestrator_upper CS 'AGENT'.
      lv_answer = |Error: Orchestrator returned an agent command that could not be parsed. Check History for the raw response.|.
      lv_answer_log = lv_answer.
    ENDIF.

    IF lt_agent_requests IS NOT INITIAL OR lv_orchestrator_read_commands IS NOT INITIAL.
      DATA(lv_index) = 0.
      DATA(lv_total) = lines( lt_agent_requests ).
      DATA lt_done_read_commands TYPE tt_strings.
      DATA lt_batched_code_review TYPE zcl_ai_messages=>tt_agent_requests.
      DATA lt_code_diff_commands TYPE zcl_ai_messages=>tt_agent_requests.
      DATA lt_create_object_commands TYPE zcl_ai_messages=>tt_agent_requests.
      DATA lt_save_commands TYPE zcl_ai_messages=>tt_agent_requests.
      DATA lv_ignored_context TYPE string.
      DATA lv_has_agent_followup_text TYPE abap_bool.
      DATA lv_has_code_change TYPE abap_bool.
      DATA lv_has_create_object TYPE abap_bool.
      DATA lv_has_code_diff TYPE abap_bool.
      DATA lv_has_show_command TYPE abap_bool.
      DATA lv_code_change_type TYPE string.
      DATA lv_code_change_name TYPE string.
      DATA lv_create_object_type TYPE string.
      DATA lv_create_object_name TYPE string.
      DATA lv_final_prompt_tasks TYPE string.

      IF lv_orchestrator_upper CS '{SHOW'.
        lv_has_show_command = abap_true.
      ENDIF.

      IF lv_orchestrator_read_commands IS NOT INITIAL.
        lv_orchestrator_code_context = resolve_and_log_read_commands(
          EXPORTING
            i_text           = lv_orchestrator_answer
          CHANGING
            ct_done_commands = lt_done_read_commands ).
      ENDIF.

      LOOP AT lt_agent_requests INTO DATA(ls_agent_request).
        lv_index = lv_index + 1.
        DATA(lv_percentage) = 50.
        IF lv_total > 0.
          lv_percentage = 20 + ( lv_index * 50 / lv_total ).
        ENDIF.

        IF ls_agent_request-agent = zcl_ai_agents_prompts=>c_agent_code_search.
          DATA(lv_search_read_command) = mo_messages->build_read_command( ls_agent_request ).
          IF lv_search_read_command IS NOT INITIAL.
            CALL FUNCTION 'SAPGUI_PROGRESS_INDICATOR'
              EXPORTING percentage = lv_percentage
                        text       = |Reading code { ls_agent_request-object_name }...|.

            lv_ignored_context = resolve_and_log_read_commands(
              EXPORTING
                i_text           = lv_search_read_command
              CHANGING
                ct_done_commands = lt_done_read_commands ).

            IF ls_agent_request-relevant_prompt IS INITIAL.
              lv_has_show_command = abap_true.
            ELSE.
              lv_has_agent_followup_text = abap_true.
              IF ls_agent_request-relevant_prompt IS NOT INITIAL.
                IF lv_final_prompt_tasks IS NOT INITIAL.
                  lv_final_prompt_tasks = lv_final_prompt_tasks && cl_abap_char_utilities=>newline.
                ENDIF.
                lv_final_prompt_tasks = lv_final_prompt_tasks && ls_agent_request-relevant_prompt.
              ENDIF.
            ENDIF.
          ENDIF.

          CONTINUE.
        ENDIF.

        IF ls_agent_request-agent = zcl_ai_agents_prompts=>c_agent_code_change.
          lv_has_code_change = abap_true.
          IF lv_code_change_name IS INITIAL.
            lv_code_change_type = ls_agent_request-object_type.
            lv_code_change_name = ls_agent_request-object_name.
          ENDIF.
          DATA(lv_change_read_command) = mo_messages->build_read_command( ls_agent_request ).
          IF lv_change_read_command IS NOT INITIAL.
            CALL FUNCTION 'SAPGUI_PROGRESS_INDICATOR'
              EXPORTING percentage = lv_percentage
                        text       = |Reading code { ls_agent_request-object_name }...|.

            lv_ignored_context = resolve_and_log_read_commands(
              EXPORTING
                i_text           = lv_change_read_command
              CHANGING
                ct_done_commands = lt_done_read_commands ).
          ENDIF.
          lv_has_agent_followup_text = abap_true.
          CONTINUE.
        ENDIF.

        IF ls_agent_request-agent = zcl_ai_agents_prompts=>c_agent_code_review.
          IF lv_user_requested_review = abap_true.
            APPEND ls_agent_request TO lt_batched_code_review.
          ELSE.
            mo_messages->add_message(
              i_role        = 'assistant'
              i_agent       = zcl_ai_agents_prompts=>c_agent_code_review
              i_prompt_type = 'AGENT_RESPONSE'
              i_content     = |CODE_REVIEW ignored. User did not explicitly request review.| ).
          ENDIF.
          CONTINUE.
        ENDIF.

        IF ls_agent_request-agent = zcl_ai_agents_prompts=>c_agent_code_diff.
          lv_has_code_diff = abap_true.
          APPEND ls_agent_request TO lt_code_diff_commands.

          DATA(lv_diff_read_command) = mo_messages->build_read_command( ls_agent_request ).
          IF lv_diff_read_command IS NOT INITIAL.
            CALL FUNCTION 'SAPGUI_PROGRESS_INDICATOR'
              EXPORTING percentage = lv_percentage
                        text       = |Reading code { ls_agent_request-object_name }...|.

            lv_ignored_context = resolve_and_log_read_commands(
              EXPORTING
                i_text           = lv_diff_read_command
              CHANGING
                ct_done_commands = lt_done_read_commands ).
          ENDIF.

          CONTINUE.
        ENDIF.

        IF ls_agent_request-agent = zcl_ai_agents_prompts=>c_agent_create_obj.
          lv_has_create_object = abap_true.
          lv_has_agent_followup_text = abap_true.
          IF lv_create_object_name IS INITIAL.
            lv_create_object_type = ls_agent_request-object_type.
            lv_create_object_name = ls_agent_request-object_name.
          ENDIF.
          APPEND ls_agent_request TO lt_create_object_commands.
          CONTINUE.
        ENDIF.

        IF ls_agent_request-agent = zcl_ai_agents_prompts=>c_agent_save.
          APPEND ls_agent_request TO lt_save_commands.
          CONTINUE.
        ENDIF.

        DATA(lv_direct_read_command) = mo_messages->build_read_command( ls_agent_request ).
        IF lv_direct_read_command IS NOT INITIAL.
          CALL FUNCTION 'SAPGUI_PROGRESS_INDICATOR'
            EXPORTING percentage = lv_percentage
                      text       = |Reading code { ls_agent_request-object_name }...|.

          lv_ignored_context = resolve_and_log_read_commands(
            EXPORTING
              i_text           = lv_direct_read_command
            CHANGING
              ct_done_commands = lt_done_read_commands ).

          CONTINUE.
        ENDIF.

        CALL FUNCTION 'SAPGUI_PROGRESS_INDICATOR'
          EXPORTING percentage = lv_percentage
                    text       = |Asking agent { ls_agent_request-agent }...|.

        DATA(lv_agent_prompt) = mo_messages->build_agent_request( ls_agent_request ).
        DATA(lv_agent_answer) = mo_llm->ask( lv_agent_prompt ).

        mo_messages->add_message(
          i_role        = 'assistant'
          i_agent       = ls_agent_request-agent
          i_prompt_type = 'LLM_RESPONSE'
          i_duration_seconds = mo_llm->get_last_seconds( )
          i_content     = lv_agent_answer ).

        IF mo_messages->has_text_after_agent_commands( lv_agent_answer ) = abap_true.
          lv_has_agent_followup_text = abap_true.
        ENDIF.

        DATA(lv_agent_answer_upper) = lv_agent_answer.
        TRANSLATE lv_agent_answer_upper TO UPPER CASE.
        IF lv_agent_answer_upper CS '{SHOW'.
          lv_has_show_command = abap_true.
        ENDIF.

        lv_ignored_context = resolve_and_log_read_commands(
          EXPORTING
            i_text           = lv_agent_answer
          CHANGING
            ct_done_commands = lt_done_read_commands ).
      ENDLOOP.

      IF lt_batched_code_review IS NOT INITIAL
      AND lv_has_code_change = abap_false
      AND lv_has_create_object = abap_false.
        LOOP AT lt_batched_code_review INTO DATA(ls_review_request).
          DATA(lv_review_read_command) = mo_messages->build_read_command( ls_review_request ).
          IF lv_review_read_command IS INITIAL.
            CONTINUE.
          ENDIF.

          CALL FUNCTION 'SAPGUI_PROGRESS_INDICATOR'
            EXPORTING percentage = 80
                      text       = |Reading code { ls_review_request-object_name }...|.

          lv_ignored_context = resolve_and_log_read_commands(
            EXPORTING
              i_text           = lv_review_read_command
            CHANGING
              ct_done_commands = lt_done_read_commands ).
        ENDLOOP.

        CALL FUNCTION 'SAPGUI_PROGRESS_INDICATOR'
          EXPORTING percentage = 90
                    text       = 'Asking code review agent...'.

        DATA(lv_review_prompt) = mo_messages->build_agent_requests( lt_batched_code_review ).
        DATA(lv_review_answer) = mo_llm->ask( lv_review_prompt ).

        mo_messages->add_message(
          i_role        = 'assistant'
          i_agent       = zcl_ai_agents_prompts=>c_agent_code_review
          i_prompt_type = 'LLM_RESPONSE'
          i_duration_seconds = mo_llm->get_last_seconds( )
          i_content     = lv_review_answer ).
      ENDIF.

      DATA(lv_only_code_search) = abap_true.
      LOOP AT lt_agent_requests INTO ls_agent_request.
        IF ls_agent_request-agent <> zcl_ai_agents_prompts=>c_agent_code_search.
          lv_only_code_search = abap_false.
          EXIT.
        ENDIF.
        IF ls_agent_request-relevant_prompt IS NOT INITIAL.
          lv_only_code_search = abap_false.
          EXIT.
        ENDIF.
      ENDLOOP.

      IF lv_has_agent_followup_text = abap_true.
        lv_only_code_search = abap_false.
      ENDIF.

      DATA(lv_agent_error) = mo_messages->get_agent_error( ).
      IF lv_agent_error IS NOT INITIAL.
        lv_answer = lv_agent_error.
        lv_answer_log = lv_answer.
      ELSEIF lt_batched_code_review IS NOT INITIAL
        AND lv_has_code_change = abap_false
        AND lv_has_create_object = abap_false.
        lv_answer = lv_review_answer.
        lv_answer_log = lv_answer.
        lv_resolved_code = mo_messages->get_resolved_code( ).
      ELSEIF lv_has_code_change = abap_false
        AND lv_has_code_diff = abap_true
        AND lv_has_agent_followup_text = abap_false.
        lv_answer = |CODE_DIFF command stub. No changed code was extracted yet, so there is nothing to diff.|.
        lv_answer_log = lv_answer.
        lv_resolved_code = mo_messages->get_resolved_code( ).
      ELSEIF lv_has_code_change = abap_false
        AND lv_has_agent_followup_text = abap_false
        AND lv_only_code_search = abap_true
        AND lt_tasks IS INITIAL
        AND ( lv_orchestrator_read_commands IS NOT INITIAL
           OR lv_has_show_command = abap_true ).
        DATA(lv_code_only) = mo_messages->get_resolved_code( ).
        lv_answer_log = lv_code_only.
        lv_answer = zcl_code_html_gen=>source_to_html(
          i_source = lv_code_only
          i_title  = 'ABAP Source' ).
      ELSE.
        CALL FUNCTION 'SAPGUI_PROGRESS_INDICATOR'
          EXPORTING percentage = 85 text = 'Asking AI with agent context...'.

        DATA(lv_final_user_prompt) = lv_effective_prompt.
        IF lv_final_prompt_tasks IS NOT INITIAL.
          lv_final_user_prompt = lv_final_user_prompt
                              && cl_abap_char_utilities=>newline
                              && cl_abap_char_utilities=>newline
                              && lv_final_prompt_tasks.
        ENDIF.

        DATA(lv_final_prompt) = mo_messages->build_final_request(
          i_user_prompt = lv_final_user_prompt ).
        lv_answer = mo_llm->ask( lv_final_prompt ).
        lv_final_duration_seconds = mo_llm->get_last_seconds( ).
        lv_answer_log = lv_answer.

        lv_resolved_code = mo_messages->get_resolved_code( ).
      ENDIF.

      mo_messages->add_message(
        i_role        = 'assistant'
        i_agent       = 'FINAL'
        i_prompt_type = 'FINAL_ANSWER'
        i_duration_seconds = lv_final_duration_seconds
        i_content     = lv_answer_log ).

      IF lv_has_code_change = abap_true AND lv_agent_error IS INITIAL.
        DATA(lv_answer_log_upper) = lv_answer_log.
        TRANSLATE lv_answer_log_upper TO UPPER CASE.

        IF lv_answer_log_upper CS 'CHANGES:NO'.
          mo_messages->add_message(
            i_role        = 'user'
            i_agent       = zcl_ai_agents_prompts=>c_agent_code_extract
            i_prompt_type = 'COMMAND'
            i_content     = |Extract changed code from final answer| ).

          mo_messages->add_message(
            i_role        = 'assistant'
            i_agent       = zcl_ai_agents_prompts=>c_agent_code_extract
            i_prompt_type = 'AGENT_RESPONSE'
            i_content     = |No changed code extracted. LLM returned CHANGES:NO.| ).

        ELSE.
          DATA(lv_extracted_code) = zcl_code_answer_tools=>extract_code_from_answer( lv_answer_log ).

          mo_messages->add_message(
            i_role        = 'user'
            i_agent       = zcl_ai_agents_prompts=>c_agent_code_extract
            i_prompt_type = 'COMMAND'
            i_content     = |Extract changed code from final answer| ).

          mo_messages->add_message(
            i_role        = 'assistant'
            i_agent       = zcl_ai_agents_prompts=>c_agent_code_extract
            i_prompt_type = 'AGENT_RESPONSE'
            i_content     = lv_extracted_code ).

          mo_messages->add_message(
            i_role        = 'user'
            i_agent       = zcl_ai_agents_prompts=>c_agent_code_diff
            i_prompt_type = 'COMMAND'
            i_content     = |Diff original code with extracted changed code| ).

          mo_messages->add_message(
            i_role        = 'assistant'
            i_agent       = zcl_ai_agents_prompts=>c_agent_code_diff
            i_prompt_type = 'AGENT_RESPONSE'
            i_content     = |CODE_DIFF command stub. Diff original code with CODE_EXTRACT result.| ).

          rs_result-has_diff = abap_true.
          rs_result-diff_old_code = mo_messages->get_resolved_code( ).
          rs_result-diff_new_code = lv_extracted_code.
          rs_result-diff_object_type = lv_code_change_type.
          rs_result-diff_object_name = lv_code_change_name.
        ENDIF.
      ENDIF.

      LOOP AT lt_code_diff_commands INTO DATA(ls_code_diff_command).
        mo_messages->add_message(
          i_role        = 'user'
          i_agent       = zcl_ai_agents_prompts=>c_agent_code_diff
          i_prompt_type = 'COMMAND'
          i_content     = ls_code_diff_command-raw_command ).

        mo_messages->add_message(
          i_role        = 'assistant'
          i_agent       = zcl_ai_agents_prompts=>c_agent_code_diff
          i_prompt_type = 'AGENT_RESPONSE'
          i_content     = COND string(
                            WHEN lv_has_code_change = abap_true
                            THEN |CODE_DIFF command handled by the CODE_CHANGE diff UI: { ls_code_diff_command-object_type } { ls_code_diff_command-object_name } { ls_code_diff_command-relevant_prompt }|
                            ELSE |CODE_DIFF command stub. No CODE_EXTRACT result exists yet: { ls_code_diff_command-object_type } { ls_code_diff_command-object_name } { ls_code_diff_command-relevant_prompt }| ) ).
      ENDLOOP.

      LOOP AT lt_create_object_commands INTO DATA(ls_create_object_command).
        DATA(lv_create_read_command) = mo_messages->build_read_command( ls_create_object_command ).
        DATA(lv_create_context) = VALUE string( ).

        IF lv_create_read_command IS NOT INITIAL.
          lv_create_context = resolve_and_log_read_commands(
            EXPORTING
              i_text           = lv_create_read_command
            CHANGING
              ct_done_commands = lt_done_read_commands ).
        ENDIF.

        DATA(lv_create_context_upper) = lv_create_context.
        TRANSLATE lv_create_context_upper TO UPPER CASE.
        DATA(lv_create_object_exists) = xsdbool(
          lv_create_read_command IS NOT INITIAL AND
          lv_create_context IS NOT INITIAL AND
          NOT ( lv_create_context_upper CS 'WAS NOT FOUND OR CANNOT BE READ' OR
                lv_create_context_upper CS 'WAS NOT FOUND' OR
                lv_create_context_upper CS 'CANNOT BE READ' OR
                lv_create_context_upper CS 'METHOD COMMAND IS INCOMPLETE' ) ).

        DATA(lv_create_answer_upper) = lv_answer_log.
        TRANSLATE lv_create_answer_upper TO UPPER CASE.
        DATA lv_create_extracted_code TYPE string.

        IF NOT lv_create_answer_upper CS 'CHANGES:NO'.
          lv_create_extracted_code = zcl_code_answer_tools=>extract_code_from_answer( lv_answer_log ).

          mo_messages->add_message(
            i_role        = 'user'
            i_agent       = zcl_ai_agents_prompts=>c_agent_code_extract
            i_prompt_type = 'COMMAND'
            i_content     = |Extract new object code from final answer| ).

          mo_messages->add_message(
            i_role        = 'assistant'
            i_agent       = zcl_ai_agents_prompts=>c_agent_code_extract
            i_prompt_type = 'AGENT_RESPONSE'
            i_content     = lv_create_extracted_code ).
        ELSE.
          mo_messages->add_message(
            i_role        = 'user'
            i_agent       = zcl_ai_agents_prompts=>c_agent_code_extract
            i_prompt_type = 'COMMAND'
            i_content     = |Extract new object code from final answer| ).

          mo_messages->add_message(
            i_role        = 'assistant'
            i_agent       = zcl_ai_agents_prompts=>c_agent_code_extract
            i_prompt_type = 'AGENT_RESPONSE'
            i_content     = |No new object code extracted. LLM returned CHANGES:NO.| ).

        ENDIF.

        IF lv_create_object_exists = abap_true.
          mo_messages->add_message(
            i_role        = 'user'
            i_agent       = zcl_ai_agents_prompts=>c_agent_create_obj
            i_prompt_type = 'COMMAND'
            i_content     = ls_create_object_command-raw_command ).

          mo_messages->add_message(
            i_role        = 'assistant'
            i_agent       = zcl_ai_agents_prompts=>c_agent_create_obj
            i_prompt_type = 'AGENT_RESPONSE'
            i_content     = |Object already exists. Confirm overwrite before create/replace: { ls_create_object_command-object_type } { ls_create_object_command-object_name } { ls_create_object_command-relevant_prompt }| ).

          mo_messages->add_message(
            i_role        = 'user'
            i_agent       = zcl_ai_agents_prompts=>c_agent_code_diff
            i_prompt_type = 'COMMAND'
            i_content     = ls_create_object_command-raw_command ).

          mo_messages->add_message(
            i_role        = 'assistant'
            i_agent       = zcl_ai_agents_prompts=>c_agent_code_diff
            i_prompt_type = 'AGENT_RESPONSE'
            i_content     = |CODE_DIFF command stub. Object exists, diff path selected before overwrite: { ls_create_object_command-object_type } { ls_create_object_command-object_name } { ls_create_object_command-relevant_prompt }| ).

        ELSE.
          mo_messages->add_message(
            i_role        = 'user'
            i_agent       = zcl_ai_agents_prompts=>c_agent_create_obj
            i_prompt_type = 'COMMAND'
            i_content     = ls_create_object_command-raw_command ).

          IF lv_create_extracted_code IS NOT INITIAL.
            mo_messages->add_message(
              i_role        = 'assistant'
              i_agent       = zcl_ai_agents_prompts=>c_agent_create_obj
              i_prompt_type = 'AGENT_RESPONSE'
              i_content     = |CREATE_OBJECT command stub. Object was not found. Opening new object diff before save/create: { ls_create_object_command-object_type } { ls_create_object_command-object_name } { ls_create_object_command-relevant_prompt }| ).

            mo_messages->add_message(
              i_role        = 'user'
              i_agent       = zcl_ai_agents_prompts=>c_agent_code_diff
              i_prompt_type = 'COMMAND'
              i_content     = |Diff empty current object with proposed new object code| ).

            mo_messages->add_message(
              i_role        = 'assistant'
              i_agent       = zcl_ai_agents_prompts=>c_agent_code_diff
              i_prompt_type = 'AGENT_RESPONSE'
              i_content     = |CODE_DIFF command stub. New object diff uses empty old source and proposed extracted code.| ).

            rs_result-has_diff = abap_true.
            rs_result-diff_old_code = ''.
            rs_result-diff_new_code = lv_create_extracted_code.
            rs_result-diff_object_type = ls_create_object_command-object_type.
            rs_result-diff_object_name = ls_create_object_command-object_name.
          ELSE.
            mo_messages->add_message(
              i_role        = 'assistant'
              i_agent       = zcl_ai_agents_prompts=>c_agent_create_obj
              i_prompt_type = 'AGENT_RESPONSE'
              i_content     = |CREATE_OBJECT command skipped. No proposed source code was extracted for missing object: { ls_create_object_command-object_type } { ls_create_object_command-object_name }| ).
          ENDIF.
        ENDIF.
      ENDLOOP.

      LOOP AT lt_save_commands INTO DATA(ls_save_command).
        DATA(lv_save_read_command) = mo_messages->build_read_command( ls_save_command ).
        DATA(lv_save_context) = VALUE string( ).

        IF lv_save_read_command IS NOT INITIAL.
          lv_save_context = resolve_and_log_read_commands(
            EXPORTING
              i_text           = lv_save_read_command
            CHANGING
              ct_done_commands = lt_done_read_commands ).
        ENDIF.

        DATA(lv_save_context_upper) = lv_save_context.
        TRANSLATE lv_save_context_upper TO UPPER CASE.
        DATA(lv_save_object_missing) = xsdbool(
          lv_save_read_command IS INITIAL OR
          lv_save_context_upper CS 'WAS NOT FOUND OR CANNOT BE READ' OR
          lv_save_context_upper CS 'WAS NOT FOUND' OR
          lv_save_context_upper CS 'CANNOT BE READ' OR
          lv_save_context_upper CS 'METHOD COMMAND IS INCOMPLETE' ).

        IF lv_save_object_missing = abap_true.
          mo_messages->add_message(
            i_role        = 'user'
            i_agent       = zcl_ai_agents_prompts=>c_agent_create_obj
            i_prompt_type = 'COMMAND'
            i_content     = ls_save_command-raw_command ).

          mo_messages->add_message(
            i_role        = 'assistant'
            i_agent       = zcl_ai_agents_prompts=>c_agent_create_obj
            i_prompt_type = 'AGENT_RESPONSE'
            i_content     = |CREATE_OBJECT command stub. Object was not found, create path selected: { ls_save_command-object_type } { ls_save_command-object_name } { ls_save_command-relevant_prompt }| ).

        ELSE.
          mo_messages->add_message(
            i_role        = 'user'
            i_agent       = zcl_ai_agents_prompts=>c_agent_code_diff
            i_prompt_type = 'COMMAND'
            i_content     = ls_save_command-raw_command ).

          mo_messages->add_message(
            i_role        = 'assistant'
            i_agent       = zcl_ai_agents_prompts=>c_agent_code_diff
            i_prompt_type = 'AGENT_RESPONSE'
            i_content     = |CODE_DIFF command stub. Object exists, diff path selected before modify: { ls_save_command-object_type } { ls_save_command-object_name } { ls_save_command-relevant_prompt }| ).

          mo_messages->add_message(
            i_role        = 'user'
            i_agent       = zcl_ai_agents_prompts=>c_agent_save
            i_prompt_type = 'COMMAND'
            i_content     = ls_save_command-raw_command ).

          mo_messages->add_message(
            i_role        = 'assistant'
            i_agent       = zcl_ai_agents_prompts=>c_agent_save
            i_prompt_type = 'AGENT_RESPONSE'
            i_content     = |AGENT_SAVE command stub. Object exists, modify path selected: { ls_save_command-object_type } { ls_save_command-object_name } { ls_save_command-relevant_prompt }| ).
        ENDIF.
      ENDLOOP.
    ENDIF.

    rs_result-answer = lv_answer.
    rs_result-answer_log = lv_answer_log.
    rs_result-resolved_code = lv_resolved_code.
    rs_result-messages_ref = mo_messages.
    rs_result-messages = mo_messages->get_messages( ).

  endmethod.
ENDCLASS.
