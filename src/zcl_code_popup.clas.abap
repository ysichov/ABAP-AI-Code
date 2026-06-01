class ZCL_CODE_POPUP definition
  public
  create public .

public section.

  methods CONSTRUCTOR
    importing
      !I_DEST type TEXT255
      !I_MODEL type TEXT255
      !I_APIKEY type STRING
      !I_PROVIDER type STRING .
  methods SHOW .
protected section.
private section.

  types:
    ty_textedit_line(255) TYPE c .
  types:
    tt_textedit_lines     TYPE TABLE OF ty_textedit_line .
  types:
    tt_html               TYPE STANDARD TABLE OF w3html WITH NON-UNIQUE DEFAULT KEY .
  types:
    tt_strings            TYPE STANDARD TABLE OF string WITH NON-UNIQUE DEFAULT KEY .

  data MV_SESSION_COUNTER type I .
  data MO_MESSAGES type ref to ZCL_AI_MESSAGES .
  data MO_LLM type ref to ZCL_LLM_CLIENT .
  data MO_TASK_PLANNER type ref to ZCL_TASK_PLANNER .
  data MT_MESSAGE_HISTORY type ZCL_AI_MESSAGES=>TT_MESSAGES .
  data MO_HISTORY type ref to ZCL_API_HISTORY_POPUP .
  data MO_DIALOG type ref to CL_GUI_DIALOGBOX_CONTAINER .
  data MO_TOOLBAR type ref to CL_GUI_TOOLBAR .
  data MO_SPLIT type ref to CL_GUI_SPLITTER_CONTAINER .
  data MO_QUESTION type ref to CL_GUI_TEXTEDIT .
  data MO_ANSWER type ref to CL_GUI_HTML_VIEWER .
  data MV_DIFF_BASE_HTML type STRING .
  data MV_DIFF_KEY type STRING .
  data MV_DIFF_SAVE_STUB_LOGGED type ABAP_BOOL .
  data MT_DIFF_HUNK_INFO type ZIF_AVE_ACR_TYPES=>TY_T_HUNK_INFO .
  data MT_DIFF_APPROVED type ZIF_AVE_ACR_TYPES=>TY_APPROVED .
  data MT_DIFF_DECLINED type ZIF_AVE_ACR_TYPES=>TY_APPROVED .
  data MT_DIFF_DECLINE_NOTES type ZIF_AVE_ACR_TYPES=>TY_T_DECLINE_NOTES .
  data MT_DIFF_HUNK_ACTIONS type ZIF_AVE_ACR_TYPES=>TY_T_HUNK_ACTIONS .
  data MT_DIFF_HUNK_THREADS type ZIF_AVE_ACR_TYPES=>TY_T_HUNK_THREADS .
  data MT_DIFF_ACR_STATS type ZIF_AVE_ACR_TYPES=>TY_T_OBJ_STATS .

  methods ON_TOOLBAR_CLICK
    for event FUNCTION_SELECTED of CL_GUI_TOOLBAR
    importing
      !FCODE .
  methods ON_DIALOG_CLOSE
    for event CLOSE of CL_GUI_DIALOGBOX_CONTAINER .
  methods ON_ANSWER_SAPEVENT
    for event SAPEVENT of CL_GUI_HTML_VIEWER
    importing
      !ACTION
      !GETDATA
      !POSTDATA .
  methods ASK_AI .
  methods SHOW_HISTORY .
  methods RESOLVE_AND_LOG_READ_COMMANDS
    importing
      !I_TEXT type STRING
    changing
      !CT_DONE_COMMANDS type TT_STRINGS
    returning
      value(RV_CONTEXT) type STRING .
  methods DISPLAY_TEXT
    importing
      !I_TEXT type STRING .
  methods DISPLAY_ANSWER
    importing
      !I_ANSWER type STRING
      !I_SOURCE type STRING optional .
  methods SOURCE_TO_HTML
    importing
      !I_SOURCE type STRING
      !I_TITLE type STRING
    returning
      value(RV_HTML) type STRING .
  methods DIFF_TO_HTML
    importing
      !I_OLD_CODE type STRING
      !I_NEW_CODE type STRING
      !I_OBJECT_TYPE type STRING optional
      !I_OBJECT_NAME type STRING optional
    returning
      value(RV_HTML) type STRING .
  methods REFRESH_DIFF_HTML .
  methods NORMALIZE_MARKDOWN
    importing
      !I_TEXT type STRING
    returning
      value(RV_TEXT) type STRING .
  methods RENDER_ABAP_BLOCKS
    importing
      !I_TEXT type STRING
    returning
      value(RV_TEXT) type STRING .
  methods SOURCE_BLOCK_TO_HTML
    importing
      !I_SOURCE type STRING
      !I_TITLE type STRING
    returning
      value(RV_HTML) type STRING .
  methods RENDER_MARKDOWN_TEXT
    importing
      !I_TEXT type STRING
    returning
      value(RV_HTML) type STRING .
  methods RENDER_INLINE_MARKDOWN
    importing
      !I_TEXT type STRING
    returning
      value(RV_HTML) type STRING .
  methods CODE_BLOCK_TO_HTML
    importing
      !I_CODE type STRING
    returning
      value(RV_HTML) type STRING .
  methods ESCAPE_HTML
    importing
      !I_TEXT type STRING
    returning
      value(RV_TEXT) type STRING .
ENDCLASS.



CLASS ZCL_CODE_POPUP IMPLEMENTATION.


  method ASK_AI.

    DATA lt_lines TYPE tt_textedit_lines.
    mo_question->get_text_as_stream( IMPORTING text = lt_lines ).

    DATA lv_prompt TYPE string.
    LOOP AT lt_lines INTO DATA(ls_line).
      DATA(lv_line) = CONV string( ls_line ).
      SHIFT lv_line RIGHT DELETING TRAILING space.

      IF lv_prompt IS NOT INITIAL.
        lv_prompt = lv_prompt && cl_abap_char_utilities=>newline.
      ENDIF.
      lv_prompt = lv_prompt && lv_line.
    ENDLOOP.

    DATA(lv_prompt_check) = lv_prompt.
    CONDENSE lv_prompt_check.
    DATA(lv_user_prompt_upper) = lv_prompt.
    TRANSLATE lv_user_prompt_upper TO UPPER CASE.
    DATA(lv_user_requested_review) = xsdbool(
      lv_user_prompt_upper CS 'CODE_REVIEW'
      OR lv_user_prompt_upper CS 'CODE REVIEW'
      OR lv_user_prompt_upper CS 'REVIEW'
      OR lv_user_prompt_upper CS 'РЕВЬЮ' ).
    IF lv_prompt_check IS INITIAL.
      MESSAGE 'Please enter a question' TYPE 'I'.
      RETURN.
    ENDIF.

    mv_session_counter = mv_session_counter + 1.
    mo_messages = NEW zcl_ai_messages(
      i_user_prompt = lv_prompt
      i_session_id  = mv_session_counter ).
    mo_task_planner = NEW zcl_task_planner(
      io_messages = mo_messages
      io_llm      = mo_llm ).

    DATA(lt_tasks) = mo_task_planner->prepare_task_list( lv_prompt ).
    DATA(lv_effective_prompt) = lv_prompt.
    DATA lv_code_search_task_prompts TYPE string.
    IF lt_tasks IS NOT INITIAL.
      LOOP AT lt_tasks INTO DATA(lv_effective_task).
        DATA(lv_effective_task_upper) = lv_effective_task.
        TRANSLATE lv_effective_task_upper TO UPPER CASE.
        CHECK lv_effective_task_upper CS 'CLARIFICATION FOR'.

        IF lv_effective_prompt NS 'TASK CLARIFICATIONS:'.
          lv_effective_prompt = lv_effective_prompt
                             && cl_abap_char_utilities=>newline
                             && cl_abap_char_utilities=>newline
                             && |TASK CLARIFICATIONS:|.
        ENDIF.

        lv_effective_prompt = lv_effective_prompt
                         && cl_abap_char_utilities=>newline
                         && lv_effective_task.
      ENDLOOP.
    ENDIF.

    CALL FUNCTION 'SAPGUI_PROGRESS_INDICATOR'
      EXPORTING percentage = 20 text = 'Asking orchestrator...'.

    DATA lv_orchestrator_answer TYPE string.

    IF lt_tasks IS INITIAL.
      DATA(lv_orchestrator_prompt) = mo_messages->build_orchestrator_request( ).
      lv_orchestrator_answer = mo_llm->ask( lv_orchestrator_prompt ).

      mo_messages->add_message(
        i_role        = 'assistant'
        i_agent       = zcl_ai_agents_prompts=>c_agent_orchestrator
        i_prompt_type = 'LLM_RESPONSE'
        i_duration_seconds = mo_llm->get_last_seconds( )
        i_content     = lv_orchestrator_answer ).
    ELSE.
      DATA(lv_task_count) = lines( lt_tasks ).
      LOOP AT lt_tasks INTO DATA(lv_task).
        DATA(lv_task_idx) = sy-tabix.
        CALL FUNCTION 'SAPGUI_PROGRESS_INDICATOR'
          EXPORTING percentage = 10 + ( lv_task_idx * 20 / lv_task_count )
                    text       = |Asking orchestrator for task { lv_task_idx }...|.

        DATA(lv_task_orchestrator_prompt) = zcl_ai_agents_prompts=>get_orchestrator_prompt( )
          && cl_abap_char_utilities=>newline
          && cl_abap_char_utilities=>newline
          && |PROMPT: { lv_task }|.

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

        DATA(lt_task_agent_requests) = mo_messages->parse_agent_requests( lv_task_orchestrator_answer ).
        LOOP AT lt_task_agent_requests INTO DATA(ls_task_agent_request).
          CHECK ls_task_agent_request-agent = zcl_ai_agents_prompts=>c_agent_code_search.
          CHECK ls_task_agent_request-relevant_prompt IS NOT INITIAL.

          DATA(lv_clean_task_prompt) = lv_task.
          REPLACE FIRST OCCURRENCE OF REGEX '^TASK\s*[0-9]+(\.[0-9]+)?\s*:\s*'
            IN lv_clean_task_prompt WITH ''.
          CONDENSE lv_clean_task_prompt.

          IF lv_code_search_task_prompts IS NOT INITIAL.
            lv_code_search_task_prompts = lv_code_search_task_prompts && cl_abap_char_utilities=>newline.
          ENDIF.
          lv_code_search_task_prompts = lv_code_search_task_prompts && lv_clean_task_prompt.
        ENDLOOP.

        IF lv_orchestrator_answer IS NOT INITIAL.
          lv_orchestrator_answer = lv_orchestrator_answer && cl_abap_char_utilities=>newline.
        ENDIF.
        lv_orchestrator_answer = lv_orchestrator_answer && lv_task_orchestrator_answer.
      ENDLOOP.
    ENDIF.

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
      DATA(lv_final_prompt_tasks) = lv_code_search_task_prompts.

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
              IF lv_code_search_task_prompts IS INITIAL.
                IF lv_final_prompt_tasks IS NOT INITIAL.
                  lv_final_prompt_tasks = lv_final_prompt_tasks && cl_abap_char_utilities=>newline.
                ENDIF.
                DATA(lv_clean_prompt_task) = ls_agent_request-raw_command.
                REPLACE FIRST OCCURRENCE OF REGEX '^\{\s*AGENT\s*:\s*CODE_SEARCH\s+\S+\s+\S+\s*'
                  IN lv_clean_prompt_task WITH ''.
                REPLACE FIRST OCCURRENCE OF REGEX '\}\s*$'
                  IN lv_clean_prompt_task WITH ''.
                CONDENSE lv_clean_prompt_task.
                lv_final_prompt_tasks = lv_final_prompt_tasks && lv_clean_prompt_task.
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
        AND ( lv_orchestrator_read_commands IS NOT INITIAL
           OR lv_has_show_command = abap_true ).
        DATA(lv_code_only) = mo_messages->get_resolved_code( ).
        lv_answer_log = lv_code_only.
        lv_answer = source_to_html(
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

          lv_answer = diff_to_html(
            i_old_code   = mo_messages->get_resolved_code( )
            i_new_code   = lv_extracted_code
            i_object_type = lv_code_change_type
            i_object_name = lv_code_change_name ).
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

            lv_answer = diff_to_html(
              i_old_code    = ''
              i_new_code    = lv_create_extracted_code
              i_object_type = ls_create_object_command-object_type
              i_object_name = ls_create_object_command-object_name ).
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

    DATA(lt_dbg_msgs) = mo_messages->get_messages( ).
    APPEND LINES OF lt_dbg_msgs TO mt_message_history.

    CALL FUNCTION 'SAPGUI_PROGRESS_INDICATOR'
      EXPORTING percentage = 0 text = ''.

    display_answer(
      i_answer = lv_answer
      i_source = lv_resolved_code ).

  endmethod.


  method CODE_BLOCK_TO_HTML.

    DATA lt_lines TYPE STANDARD TABLE OF string WITH NON-UNIQUE DEFAULT KEY.
    DATA lv_lno TYPE i.

    SPLIT i_code AT cl_abap_char_utilities=>newline INTO TABLE lt_lines.
    rv_html = |<table class="code_tbl"><tbody>|.

    LOOP AT lt_lines INTO DATA(lv_line).
      lv_lno = lv_lno + 1.
      DATA(lv_class) = COND string(
        WHEN lv_line CS 'was not found or cannot be read'
          THEN 'cd-error'
          ELSE 'cd' ).
      rv_html = rv_html
             && |<tr><td class="ln">{ lv_lno }</td>|
             && |<td class="{ lv_class }">{ escape_html( i_text = lv_line ) }</td></tr>|.
    ENDLOOP.

    rv_html = rv_html && |</tbody></table>|.

  endmethod.


  method CONSTRUCTOR.

    mo_llm = NEW zcl_llm_client(
      i_dest     = i_dest
      i_model    = i_model
      i_apikey   = i_apikey
      i_provider = i_provider ).

  endmethod.


  method DIFF_TO_HTML.

    DATA lt_old TYPE abaptxt255_tab.
    DATA lt_new TYPE abaptxt255_tab.
    DATA lt_hunk_html TYPE string_table.
    DATA lt_hunk_info TYPE zif_ave_acr_types=>ty_t_hunk_info.
    DATA lt_acr_stats TYPE zif_ave_acr_types=>ty_t_obj_stats.
    DATA lt_blame TYPE zif_ave_popup_types=>ty_blame_map.
    DATA lv_hunk_count TYPE i.
    DATA lv_hunk_ins TYPE i.
    DATA lv_hunk_mod TYPE i.
    DATA lv_hunk_del TYPE i.
    DATA lv_author TYPE versuser.
    DATA ls_part TYPE zif_ave_popup_types=>ty_part_row.

    SPLIT i_old_code AT cl_abap_char_utilities=>newline INTO TABLE lt_old.
    SPLIT i_new_code AT cl_abap_char_utilities=>newline INTO TABLE lt_new.

    DATA(lt_diff) = zcl_ave_popup_diff=>compute_diff(
      it_old = lt_old
      it_new = lt_new
      i_title = 'Computing AI code diff' ).

    lt_diff = zcl_ave_acr_hunk_html=>filter_moved_lines( it_diff = lt_diff ).

    rv_html = zcl_ave_popup_html=>diff_to_html(
      it_diff       = lt_diff
      i_title       = 'AI Code Change'
      i_meta        = 'LLM proposal vs current SAP source'
      i_two_pane    = abap_false
      i_compact     = abap_false
      i_plain       = abap_false
      i_code_review = abap_true ).

    DATA(lv_hunk_full_html) = zcl_ave_popup_html=>diff_to_html(
      it_diff       = lt_diff
      i_title       = 'AI Code Change'
      i_meta        = 'LLM proposal vs current SAP source'
      i_two_pane    = abap_true
      i_compact     = abap_false
      i_plain       = abap_false
      i_code_review = abap_true ).

    lt_hunk_html = zcl_ave_acr_hunk_html=>collect_rows(
      it_diff        = lt_diff
      iv_full_html   = lv_hunk_full_html
      iv_title       = 'AI Code Change'
      iv_meta        = 'LLM proposal vs current SAP source'
      iv_two_pane    = abap_true
      iv_plain       = abap_false
      iv_ignore_case = abap_false
      iv_is_created  = abap_false ).

    lv_author = 'AI_AGENT'.
    ls_part-type = COND #( WHEN i_object_type IS NOT INITIAL THEN i_object_type ELSE 'PROG' ).
    ls_part-object_name = COND #( WHEN i_object_name IS NOT INITIAL THEN i_object_name ELSE 'AI_CODE_CHANGE' ).
    ls_part-name = ls_part-object_name.
    ls_part-display_name = |{ ls_part-type } { ls_part-object_name }|.

    zcl_ave_acr_hunk_info=>collect(
      EXPORTING
        is_part            = ls_part
        it_diff            = lt_diff
        it_hunk_html       = lt_hunk_html
        it_blame           = lt_blame
        iv_author          = lv_author
        iv_display_name    = ls_part-display_name
        iv_versno_new      = '00000'
        iv_versno_old      = '00000'
        iv_versno_new_text = 'LLM proposal'
        iv_versno_old_text = 'Current source'
        iv_is_created      = abap_false
      IMPORTING
        et_hunk_info       = lt_hunk_info
        ev_hunk_count      = lv_hunk_count
        ev_hunk_ins        = lv_hunk_ins
        ev_hunk_mod        = lv_hunk_mod
        ev_hunk_del        = lv_hunk_del ).

    APPEND VALUE zif_ave_acr_types=>ty_obj_stats(
      objtype      = ls_part-type
      obj_name     = ls_part-object_name
      author       = lv_author
      author_name  = zcl_ave_popup_data=>get_user_name( lv_author )
      hunk_count   = lv_hunk_count
      hunk_ins     = lv_hunk_ins
      hunk_mod     = lv_hunk_mod
      hunk_del     = lv_hunk_del
      display_name = ls_part-display_name ) TO lt_acr_stats.

    mv_diff_base_html = rv_html.
    mv_diff_key = |{ ls_part-type }~{ ls_part-object_name }|.
    mt_diff_hunk_info = lt_hunk_info.
    CLEAR: mt_diff_approved,
           mt_diff_declined,
           mt_diff_decline_notes,
           mt_diff_hunk_actions,
           mt_diff_hunk_threads,
           mt_diff_acr_stats,
           mv_diff_save_stub_logged.
    mt_diff_acr_stats = lt_acr_stats.

    zcl_ave_acr_hunk_renderer=>inject_approve_btn(
      EXPORTING
        iv_key           = mv_diff_key
        it_hunk_info     = mt_diff_hunk_info
        it_approved      = mt_diff_approved
        it_declined      = mt_diff_declined
        it_decline_notes = mt_diff_decline_notes
        it_hunk_actions  = mt_diff_hunk_actions
        it_hunk_threads  = mt_diff_hunk_threads
        iv_ai_enabled    = abap_true
      CHANGING
        cv_html          = rv_html
        ct_acr_stats     = mt_diff_acr_stats ).

  endmethod.


  method DISPLAY_ANSWER.

    DATA lv_html TYPE string.
    DATA lv_text_upper TYPE string.

    lv_text_upper = i_answer.
    SHIFT lv_text_upper LEFT DELETING LEADING space.
    TRANSLATE lv_text_upper TO UPPER CASE.

    IF lv_text_upper CP '<!DOCTYPE HTML*'
    OR lv_text_upper CP '<!DOCTYPE*'
    OR lv_text_upper CP '<HTML*'.
      lv_html = i_answer.
    ELSE.
      DATA(lv_render_text) = render_abap_blocks( i_answer ).
      DATA(lv_source_html) = source_block_to_html(
        i_source = i_source
        i_title  = 'Source code from code_agent' ).

      lv_html = |<!doctype html><html><head><meta charset="utf-8">|
             && |<style>body\{font-family:"Segoe UI",Arial,sans-serif;font-size:14px;margin:0;|
             && |min-height:100vh;background:linear-gradient(135deg,#f8fbff 0%,#eef6ff 45%,#f7fff9 100%);|
             && |color:#1f2933;\}|
             && |.answer\{white-space:pre-wrap;font-family:"Segoe UI",Arial,sans-serif;line-height:1.45;|
             && |margin:14px;padding:16px 18px;background:rgba(255,255,255,.88);border:1px solid #dce8f6;|
             && |box-shadow:0 2px 10px rgba(56,96,140,.10);\}|
             && |.md_h\{display:block;font-size:17px;font-weight:700;color:#23476f;margin:4px 0 8px\}|
             && |.md_li\{display:block;margin:2px 0 2px 18px;text-indent:-18px\}|
             && |code\{font-family:Consolas,monospace;background:#eef3f8;border:1px solid #d7e0ea;|
             && |padding:0 4px;color:#18324a\}|
             && |strong\{font-weight:700\}|
             && |.tokens\{display:inline-block;color:#005ea8;font-weight:700;background:#e8f3ff;|
             && |border:1px solid #b9dcff;padding:3px 7px;margin-top:6px;\}|
             && |.code_tbl\{border-collapse:collapse;width:100%;font:12px/1.5 Consolas,monospace;|
             && |background:#fff;border:1px solid #d7e0ea;margin:10px 0;\}|
             && |.source_title\{font-weight:700;color:#23476f;margin:14px 0 6px\}|
             && |.code_tbl tr:hover td\{background:#f0f4fa\}|
             && |.ln\{color:#aaa;text-align:right;padding:1px 10px 1px 5px;min-width:42px;|
             && |border-right:1px solid #e0e0e0;white-space:nowrap;background:#fafafa;user-select:none;\}|
             && |.cd\{padding:1px 8px;white-space:pre;\}|
             && |.cd-error\{padding:1px 8px;white-space:pre;color:red;font-weight:bold;\}|
             && |</style></head><body><div class="answer">|
             && lv_render_text
             && lv_source_html
             && |</div></body></html>|.
    ENDIF.

    DATA lt_html TYPE tt_html.
    DATA ls_html TYPE w3html.
    DATA lv_offset TYPE i.

    WHILE lv_offset < strlen( lv_html ).
      CLEAR ls_html.
      ls_html-line = substring(
        val = lv_html
        off = lv_offset
        len = nmin( val1 = 255 val2 = strlen( lv_html ) - lv_offset ) ).
      APPEND ls_html TO lt_html.
      lv_offset = lv_offset + 255.
    ENDWHILE.

    DATA lv_url TYPE c LENGTH 255.
    mo_answer->load_data(
      EXPORTING
        type         = 'text'
        subtype      = 'html'
      IMPORTING
        assigned_url = lv_url
      CHANGING
        data_table   = lt_html
      EXCEPTIONS
        OTHERS       = 1 ).

    mo_answer->show_url(
      EXPORTING url = lv_url
      EXCEPTIONS OTHERS = 1 ).

    CALL METHOD cl_gui_cfw=>flush.

  endmethod.


  method DISPLAY_TEXT.

    display_answer( i_answer = i_text ).

  endmethod.


  method ESCAPE_HTML.

    rv_text = i_text.
    REPLACE ALL OCCURRENCES OF '&' IN rv_text WITH '&amp;'.
    REPLACE ALL OCCURRENCES OF '<' IN rv_text WITH '&lt;'.
    REPLACE ALL OCCURRENCES OF '>' IN rv_text WITH '&gt;'.
    REPLACE ALL OCCURRENCES OF '"' IN rv_text WITH '&quot;'.

  endmethod.


  method NORMALIZE_MARKDOWN.

    rv_text = i_text.

    DATA(lv_nl) = cl_abap_char_utilities=>newline.

    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf IN rv_text WITH lv_nl.
    REPLACE ALL OCCURRENCES OF REGEX '\s+(#{1,6})\s+' IN rv_text WITH |{ lv_nl }{ lv_nl }$1 |.
    REPLACE ALL OCCURRENCES OF '## Overall Assessment ' IN rv_text WITH |## Overall Assessment{ lv_nl }|.
    REPLACE ALL OCCURRENCES OF '## Strengths ' IN rv_text WITH |## Strengths{ lv_nl }|.
    REPLACE ALL OCCURRENCES OF '## Areas for Improvement ' IN rv_text WITH |## Areas for Improvement{ lv_nl }|.
    REPLACE ALL OCCURRENCES OF '## Specific Recommendations ' IN rv_text WITH |## Specific Recommendations{ lv_nl }|.
    REPLACE ALL OCCURRENCES OF '## Recommendations ' IN rv_text WITH |## Recommendations{ lv_nl }|.
    REPLACE ALL OCCURRENCES OF '## Conclusion ' IN rv_text WITH |## Conclusion{ lv_nl }|.
    REPLACE ALL OCCURRENCES OF REGEX '\s+([0-9]+)\.\s+(\*\*)' IN rv_text WITH |{ lv_nl }$1. $2|.
    REPLACE ALL OCCURRENCES OF REGEX '\s+-\s+' IN rv_text WITH |{ lv_nl }- |.

  endmethod.


  method ON_ANSWER_SAPEVENT.

    DATA lv_cmd TYPE string.
    DATA lv_rest TYPE string.
    DATA lv_sep_off TYPE i.

    FIND FIRST OCCURRENCE OF '~' IN action MATCH OFFSET lv_sep_off.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    lv_cmd = action(lv_sep_off).
    DATA(lv_rest_start) = lv_sep_off + 1.
    lv_rest = action+lv_rest_start.

    CASE lv_cmd.
      WHEN 'approve'.
        INSERT lv_rest INTO TABLE mt_diff_approved.
        DELETE TABLE mt_diff_declined FROM lv_rest.
        zcl_ave_acr_state=>set_hunk_action(
          EXPORTING
            iv_hunk_key     = lv_rest
            iv_action       = 'A'
          CHANGING
            ct_hunk_actions = mt_diff_hunk_actions ).

      WHEN 'decline'.
        INSERT lv_rest INTO TABLE mt_diff_declined.
        DELETE TABLE mt_diff_approved FROM lv_rest.
        zcl_ave_acr_state=>set_hunk_action(
          EXPORTING
            iv_hunk_key     = lv_rest
            iv_action       = 'D'
          CHANGING
            ct_hunk_actions = mt_diff_hunk_actions ).

      WHEN 'approveall'.
        LOOP AT mt_diff_hunk_info INTO DATA(ls_hunk).
          INSERT ls_hunk-hunk_key INTO TABLE mt_diff_approved.
          DELETE TABLE mt_diff_declined FROM ls_hunk-hunk_key.
          zcl_ave_acr_state=>set_hunk_action(
            EXPORTING
              iv_hunk_key     = ls_hunk-hunk_key
              iv_action       = 'A'
            CHANGING
              ct_hunk_actions = mt_diff_hunk_actions ).
        ENDLOOP.

      WHEN 'undo'.
        DELETE TABLE mt_diff_approved FROM lv_rest.
        DELETE TABLE mt_diff_declined FROM lv_rest.
        DELETE TABLE mt_diff_decline_notes WITH TABLE KEY hunk_key = lv_rest.
        zcl_ave_acr_state=>clear_hunk_action(
          EXPORTING
            iv_hunk_key     = lv_rest
          CHANGING
            ct_hunk_actions = mt_diff_hunk_actions ).

      WHEN 'addcomment' OR 'editreview'.
        MESSAGE 'ADD COMMENT stub for AI code diff' TYPE 'S'.

      WHEN 'askai'.
        MESSAGE 'ASK AI stub for AI code diff' TYPE 'S'.

      WHEN OTHERS.
        RETURN.
    ENDCASE.

    DATA(lv_all_approved) = abap_true.
    IF mt_diff_hunk_info IS INITIAL.
      lv_all_approved = abap_false.
    ENDIF.
    LOOP AT mt_diff_hunk_info INTO DATA(ls_approved_check).
      IF NOT line_exists( mt_diff_approved[ table_line = ls_approved_check-hunk_key ] ).
        lv_all_approved = abap_false.
        EXIT.
      ENDIF.
    ENDLOOP.

    IF lv_all_approved = abap_true
       AND mv_diff_save_stub_logged = abap_false.
      mv_diff_save_stub_logged = abap_true.
      mo_messages->add_message(
        i_role        = 'user'
        i_agent       = 'SAVE_OBJECT'
        i_prompt_type = 'COMMAND'
        i_content     = |SAVE_OBJECT command stub after all AI diff approvals: { mv_diff_key }| ).
      mo_messages->add_message(
        i_role        = 'assistant'
        i_agent       = 'SAVE_OBJECT'
        i_prompt_type = 'AGENT_RESPONSE'
        i_content     = |SAVE_OBJECT command stub. All hunks approved for { mv_diff_key }.| ).
    ENDIF.

    refresh_diff_html( ).

  endmethod.


  method ON_DIALOG_CLOSE.

    mo_dialog->free( ).
    CLEAR mo_dialog.
    CALL METHOD cl_gui_cfw=>flush.

  endmethod.


  method ON_TOOLBAR_CLICK.

    CASE fcode.
      WHEN 'ASK'.
        ask_ai( ).
      WHEN 'HISTORY'.
        show_history( ).
    ENDCASE.

  endmethod.


  method REFRESH_DIFF_HTML.

    DATA(lv_html) = mv_diff_base_html.

    IF lv_html IS INITIAL.
      RETURN.
    ENDIF.

    zcl_ave_acr_hunk_renderer=>inject_approve_btn(
      EXPORTING
        iv_key           = mv_diff_key
        it_hunk_info     = mt_diff_hunk_info
        it_approved      = mt_diff_approved
        it_declined      = mt_diff_declined
        it_decline_notes = mt_diff_decline_notes
        it_hunk_actions  = mt_diff_hunk_actions
        it_hunk_threads  = mt_diff_hunk_threads
        iv_ai_enabled    = abap_true
      CHANGING
        cv_html          = lv_html
        ct_acr_stats     = mt_diff_acr_stats ).

    display_answer( lv_html ).

  endmethod.


  method RENDER_ABAP_BLOCKS.

    DATA lv_rest TYPE string.
    DATA lv_before TYPE string.
    DATA lv_code TYPE string.
    DATA lv_after TYPE string.
    DATA lv_start TYPE i.
    DATA lv_end TYPE i.
    DATA lv_code_start TYPE i.
    DATA lv_fence_len TYPE i.

    lv_rest = i_text.

    DO.
      FIND FIRST OCCURRENCE OF REGEX '```\s*[A-Za-z0-9_-]*\s*' IN lv_rest
        MATCH OFFSET lv_start
        MATCH LENGTH lv_fence_len.
      IF sy-subrc <> 0.
        EXIT.
      ENDIF.

      lv_before = substring( val = lv_rest len = lv_start ).
      lv_code_start = lv_start + lv_fence_len.
      lv_after = substring( val = lv_rest off = lv_code_start ).
      FIND FIRST OCCURRENCE OF '```' IN lv_after MATCH OFFSET lv_end.
      IF sy-subrc <> 0.
        EXIT.
      ENDIF.

      lv_code = substring( val = lv_after len = lv_end ).
      SHIFT lv_code LEFT DELETING LEADING cl_abap_char_utilities=>newline.
      rv_text = rv_text
             && render_markdown_text( lv_before )
             && code_block_to_html( lv_code ).
      lv_rest = substring( val = lv_after off = lv_end + 3 ).
    ENDDO.

    rv_text = rv_text && render_markdown_text( lv_rest ).

  endmethod.


  method RENDER_INLINE_MARKDOWN.

    rv_html = escape_html( i_text ).
    REPLACE ALL OCCURRENCES OF REGEX '\*\*([^*]+)\*\*' IN rv_html WITH '<strong>$1</strong>'.
    REPLACE ALL OCCURRENCES OF REGEX '`([^`]+)`' IN rv_html WITH '<code>$1</code>'.

  endmethod.


  method RENDER_MARKDOWN_TEXT.

    DATA lt_lines TYPE STANDARD TABLE OF string WITH NON-UNIQUE DEFAULT KEY.
    DATA lv_text TYPE string.
    DATA lv_hashes TYPE string.
    DATA lv_content TYPE string.
    DATA lv_marker TYPE string.
    DATA lv_item TYPE string.

    lv_text = normalize_markdown( i_text ).
    SPLIT lv_text AT cl_abap_char_utilities=>newline INTO TABLE lt_lines.

    LOOP AT lt_lines INTO DATA(lv_line).
      DATA(lv_trimmed) = lv_line.
      SHIFT lv_trimmed LEFT DELETING LEADING space.

      IF lv_trimmed IS INITIAL.
        rv_html = rv_html && cl_abap_char_utilities=>newline.
        CONTINUE.
      ENDIF.

      FIND FIRST OCCURRENCE OF REGEX '^(#{1,6})\s+(.+)$' IN lv_trimmed
        SUBMATCHES lv_hashes lv_content.
      IF sy-subrc = 0.
        rv_html = rv_html
               && |<div class="md_h">{ render_inline_markdown( lv_content ) }</div>|
               && cl_abap_char_utilities=>newline.
        CONTINUE.
      ENDIF.

      FIND FIRST OCCURRENCE OF REGEX '^([0-9]+\.)\s+(.+)$' IN lv_trimmed
        SUBMATCHES lv_marker lv_item.
      IF sy-subrc = 0.
        rv_html = rv_html
               && |<div class="md_li">{ escape_html( lv_marker ) } { render_inline_markdown( lv_item ) }</div>|
               && cl_abap_char_utilities=>newline.
        CONTINUE.
      ENDIF.

      FIND FIRST OCCURRENCE OF REGEX '^-\s+(.+)$' IN lv_trimmed
        SUBMATCHES lv_item.
      IF sy-subrc = 0.
        rv_html = rv_html
               && |<div class="md_li">- { render_inline_markdown( lv_item ) }</div>|
               && cl_abap_char_utilities=>newline.
        CONTINUE.
      ENDIF.

      FIND FIRST OCCURRENCE OF REGEX '^Tokens:' IN lv_trimmed.
      IF sy-subrc = 0.
        rv_html = rv_html
               && |<span class="tokens">{ render_inline_markdown( lv_trimmed ) }</span>|
               && cl_abap_char_utilities=>newline.
        CONTINUE.
      ENDIF.

      rv_html = rv_html
             && render_inline_markdown( lv_line )
             && cl_abap_char_utilities=>newline.
    ENDLOOP.

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


  method SHOW.

    " Dialog popup container
    CREATE OBJECT mo_dialog
      EXPORTING
        caption  = 'Easy AI'
        top      = 20
        left     = 20
        width    = 1400
        height   = 800
        metric   = cl_gui_dialogbox_container=>metric_pixel
      EXCEPTIONS
        OTHERS   = 1.

    SET HANDLER on_dialog_close FOR mo_dialog.

    " Outer splitter: row1=toolbar, row2=editors
    DATA lo_outer TYPE REF TO cl_gui_splitter_container.
    CREATE OBJECT lo_outer
      EXPORTING
        parent  = mo_dialog
        rows    = 2
        columns = 1
      EXCEPTIONS
        OTHERS  = 1.

    lo_outer->set_row_height( id = 1 height = 8 ).
    lo_outer->set_row_height( id = 2 height = 92 ).

    DATA lo_toolbar_cont TYPE REF TO cl_gui_container.
    lo_toolbar_cont = lo_outer->get_container( row = 1 column = 1 ).

    DATA lo_editors_cont TYPE REF TO cl_gui_container.
    lo_editors_cont = lo_outer->get_container( row = 2 column = 1 ).

    " Toolbar
    CREATE OBJECT mo_toolbar
      EXPORTING parent = lo_toolbar_cont
      EXCEPTIONS OTHERS = 1.

    DATA: lt_events TYPE cntl_simple_events,
          ls_event  TYPE cntl_simple_event.

    ls_event-eventid    = cl_gui_toolbar=>m_id_function_selected.
    ls_event-appl_event = space.
    APPEND ls_event TO lt_events.
    mo_toolbar->set_registered_events( events = lt_events ).

    DATA lt_buttons TYPE ttb_button.
    APPEND VALUE #( function  = 'ASK'
                    icon      = CONV #( icon_execute_object )
                    butn_type = cntb_btype_button
                    text      = 'Ask AI'
                    quickinfo = 'Send question to AI' ) TO lt_buttons.
    APPEND VALUE #( function  = 'HISTORY'
                    icon      = CONV #( icon_protocol )
                    butn_type = cntb_btype_button
                    text      = 'History'
                    quickinfo = 'Show message history' ) TO lt_buttons.
    mo_toolbar->add_button_group( lt_buttons ).

    SET HANDLER on_toolbar_click FOR mo_toolbar.

    " Horizontal splitter: left=question, right=answer
    CREATE OBJECT mo_split
      EXPORTING
        parent  = lo_editors_cont
        rows    = 1
        columns = 2
      EXCEPTIONS
        OTHERS  = 1.

    mo_split->set_column_width( id = 1 width = 40 ).
    mo_split->set_column_width( id = 2 width = 60 ).

    DATA lo_left  TYPE REF TO cl_gui_container.
    DATA lo_right TYPE REF TO cl_gui_container.
    lo_left  = mo_split->get_container( row = 1 column = 1 ).
    lo_right = mo_split->get_container( row = 1 column = 2 ).

    " Question editor (left)
    CREATE OBJECT mo_question
      EXPORTING parent = lo_left
      EXCEPTIONS OTHERS = 1.
    mo_question->set_toolbar_mode( 0 ).  " 0 = toolbar off

    " Answer viewer (right)
    CREATE OBJECT mo_answer
      EXPORTING parent = lo_right
      EXCEPTIONS OTHERS = 1.

    DATA lt_html_events TYPE cntl_simple_events.
    APPEND VALUE #( eventid = cl_gui_html_viewer=>m_id_sapevent ) TO lt_html_events.
    mo_answer->set_registered_events( events = lt_html_events ).
    SET HANDLER on_answer_sapevent FOR mo_answer.

    CALL METHOD cl_gui_cfw=>flush.

  endmethod.


  method SHOW_HISTORY.

    IF mt_message_history IS INITIAL.
      MESSAGE 'No message history yet' TYPE 'I'.
      RETURN.
    ENDIF.

    mo_history = NEW zcl_api_history_popup( mt_message_history ).
    mo_history->show( ).

  endmethod.


  method SOURCE_BLOCK_TO_HTML.

    IF i_source IS INITIAL.
      RETURN.
    ENDIF.

    rv_html = cl_abap_char_utilities=>newline
           && |<div class="source_title">{ escape_html( i_title ) }</div>|
           && code_block_to_html( i_source ).

  endmethod.


  method SOURCE_TO_HTML.

    DATA lv_rows TYPE string.
    DATA lv_lno TYPE i.
    DATA lt_lines TYPE STANDARD TABLE OF string WITH NON-UNIQUE DEFAULT KEY.

    SPLIT i_source AT cl_abap_char_utilities=>newline INTO TABLE lt_lines.

    LOOP AT lt_lines INTO DATA(lv_line).
      lv_lno = lv_lno + 1.
      lv_rows = lv_rows
             && |<tr><td class="ln">{ lv_lno }</td>|
             && |<td class="cd">{ escape_html( i_text = lv_line ) }</td></tr>|.
    ENDLOOP.

    DATA(lv_title) = escape_html( i_text = i_title ).

    rv_html = |<!DOCTYPE html><html><head><meta charset="utf-8"><style>|
           && |*\{margin:0;padding:0;box-sizing:border-box\}|
           && |body\{background:#ffffff;color:#1e1e1e;font:12px/1.5 Consolas,monospace\}|
           && |.hdr\{background:#f3f3f3;padding:5px 12px;border-bottom:1px solid #ddd;|
           && |color:#444;font-size:11px;display:flex;gap:16px;flex-wrap:wrap\}|
           && |.ttl\{color:#0066aa;font-weight:bold\}|
           && |table\{border-collapse:collapse;width:100%\}|
           && |tr:hover td\{background:#f0f4fa\}|
           && |.ln\{color:#aaa;text-align:right;padding:1px 10px 1px 5px;|
           && |user-select:none;min-width:42px;border-right:1px solid #e0e0e0;|
           && |white-space:nowrap;background:#fafafa\}|
           && |.cd\{padding:1px 8px;white-space:pre\}|
           && |</style></head><body>|
           && |<div class="hdr"><span class="ttl">{ lv_title }</span></div>|
           && |<table><tbody>| && lv_rows && |</tbody></table></body></html>|.

  endmethod.
ENDCLASS.
