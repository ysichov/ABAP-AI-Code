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
      diff_package TYPE string,
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
  methods GET_MESSAGES
    returning
      value(RO_MESSAGES) type ref to ZCL_AI_MESSAGES .
  methods SET_HTML_VIEWER
    importing
      !IO_VIEWER type ref to CL_GUI_HTML_VIEWER .
protected section.
private section.

  types:
    tt_strings TYPE STANDARD TABLE OF string WITH NON-UNIQUE DEFAULT KEY .
  types:
    BEGIN OF ty_step,
      text     TYPE string,
      done     TYPE abap_bool,
      is_llm   TYPE abap_bool,
      seconds  TYPE i,
      tok_in   TYPE i,
      tok_out  TYPE i,
    END OF ty_step .
  types:
    tt_steps TYPE STANDARD TABLE OF ty_step WITH NON-UNIQUE DEFAULT KEY .

  data MO_HTML_VIEWER type ref to CL_GUI_HTML_VIEWER .
  data MT_PROGRESS_STEPS type TT_STEPS .
  data MV_TOTAL_SECONDS type I .
  data MV_TOTAL_TOK_IN  type I .
  data MV_TOTAL_TOK_OUT type I .

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
  methods LOG_CLASS_EXTRACT
    importing
      !I_SOURCE type STRING
      !I_OBJECT_NAME type STRING
      !I_PHASE type STRING
      !I_LOG type ABAP_BOOL default ABAP_TRUE
      !I_COMPARE_SOURCE type STRING optional
    returning
      value(RV_SOURCE) type STRING .
  methods FIX_PROGRAM_SYNTAX
    importing
      !I_SOURCE type STRING
      !I_OBJECT_TYPE type STRING
      !I_OBJECT_NAME type STRING
    returning
      value(RV_SOURCE) type STRING .
  methods EXTRACT_PACKAGE
    importing
      !I_TEXT type STRING
    returning
      value(RV_PACKAGE) type STRING .
  methods HAS_CREATE_OBJECT_REQUEST
    importing
      !IT_AGENT_REQUESTS type ZCL_AI_MESSAGES=>TT_AGENT_REQUESTS
      !I_OBJECT_TYPE type STRING
      !I_OBJECT_NAME type STRING
    returning
      value(RV_FOUND) type ABAP_BOOL .
  methods SHOW_STEP
    importing
      !I_TEXT type STRING
      !I_PCT type I default 0 .
  methods COMPLETE_LAST_STEP
    importing
      !I_IS_LLM  type ABAP_BOOL default ABAP_FALSE
      !I_SECONDS type I         default 0
      !I_TOK_IN  type I         default 0
      !I_TOK_OUT type I         default 0 .
  methods RENDER_STEPS_HTML
    returning
      value(RV_HTML) type STRING .
  methods IS_SINGLE_CODE_WORD
    importing
      !I_PROMPT type STRING
    returning
      value(RV_IS) type ABAP_BOOL .
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
      DATA(lv_orchestrator_answer_log) = rv_answer.
      rv_answer = zcl_ai_messages=>strip_log_info( rv_answer ).

      mo_messages->add_message(
        i_role        = 'assistant'
        i_agent       = zcl_ai_agents_prompts=>c_agent_orchestrator
        i_prompt_type = 'LLM_RESPONSE'
        i_duration_seconds = mo_llm->get_last_seconds( )
        i_content     = lv_orchestrator_answer_log ).
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
        DATA(lv_task_answer_log) = lv_task_orchestrator_answer.
        lv_task_orchestrator_answer = zcl_ai_messages=>strip_log_info( lv_task_orchestrator_answer ).

        mo_messages->add_message(
          i_role        = 'assistant'
          i_agent       = zcl_ai_agents_prompts=>c_agent_orchestrator
          i_prompt_type = 'LLM_RESPONSE'
          i_duration_seconds = mo_llm->get_last_seconds( )
          i_content     = lv_task_answer_log ).

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

    DATA(lv_language_answer_log) = mo_llm->ask( lv_language_prompt ).
    rv_language = zcl_ai_messages=>strip_log_info( lv_language_answer_log ).
    CONDENSE rv_language.

    mo_messages->add_message(
      i_role        = 'assistant'
      i_agent       = zcl_ai_agents_prompts=>c_agent_language_detector
      i_prompt_type = 'LLM_RESPONSE'
      i_duration_seconds = mo_llm->get_last_seconds( )
      i_content     = lv_language_answer_log ).

  endmethod.


  METHOD extract_package.

    FIND FIRST OCCURRENCE OF REGEX '\bPACKAGE\s+([^\s\}]+)'
      IN i_text IGNORING CASE SUBMATCHES rv_package.
    IF sy-subrc = 0.
      TRANSLATE rv_package TO UPPER CASE.
      CONDENSE rv_package.
    ENDIF.

  ENDMETHOD.


  METHOD has_create_object_request.

    DATA(lv_object_type) = i_object_type.
    DATA(lv_object_name) = i_object_name.
    TRANSLATE lv_object_type TO UPPER CASE.
    TRANSLATE lv_object_name TO UPPER CASE.

    LOOP AT it_agent_requests INTO DATA(ls_agent_request).
      CHECK ls_agent_request-agent = zcl_ai_agents_prompts=>c_agent_create_obj.

      DATA(lv_create_type) = ls_agent_request-object_type.
      DATA(lv_create_name) = ls_agent_request-object_name.
      TRANSLATE lv_create_type TO UPPER CASE.
      TRANSLATE lv_create_name TO UPPER CASE.

      IF lv_create_type = lv_object_type
      AND lv_create_name = lv_object_name.
        rv_found = abap_true.
        RETURN.
      ENDIF.
    ENDLOOP.

  ENDMETHOD.


  METHOD fix_program_syntax.

    DATA lv_object_type TYPE string.
    DATA lv_source TYPE string.
    DATA lv_syntax_error TYPE string.
    DATA lv_fix_prompt TYPE string.
    DATA lv_fix_answer_log TYPE string.
    DATA lv_fixed_source TYPE string.

    lv_object_type = i_object_type.
    TRANSLATE lv_object_type TO UPPER CASE.
    rv_source = i_source.

    IF NOT ( lv_object_type = 'PROG'
          OR lv_object_type = 'REPS'
          OR lv_object_type = 'PROGRAM'
          OR lv_object_type = 'REPORT' ).
      RETURN.
    ENDIF.

    lv_source = i_source.

    DO 5 TIMES.
      DATA(lv_attempt) = sy-index.
      lv_syntax_error = zcl_code_object_saver=>check_program_syntax( lv_source ).
      IF lv_syntax_error IS INITIAL.
        rv_source = lv_source.
        RETURN.
      ENDIF.

      mo_messages->add_message(
        i_role        = 'assistant'
        i_agent       = 'SYNTAX_FIX'
        i_prompt_type = 'AGENT_RESPONSE'
        i_content     = |Extracted code has syntax errors before review, attempt { lv_attempt } of 5: { lv_syntax_error }| ).

      CALL FUNCTION 'SAPGUI_PROGRESS_INDICATOR'
        EXPORTING
          percentage = 75
          text       = |Fixing extracted code before review, attempt { lv_attempt } of 5...|.

      lv_fix_prompt = |You are a Senior ABAP syntax-fix agent.|
                   && cl_abap_char_utilities=>newline
                   && |Return the complete corrected ABAP program source only in one abap fenced code block.|
                   && cl_abap_char_utilities=>newline
                   && |Do not explain. Keep the object name and intent. Fix the syntax error before code review.|
                   && cl_abap_char_utilities=>newline
                   && |For selection screens, PARAMETERS and SELECT-OPTIONS names must be at most 8 characters long.|
                   && cl_abap_char_utilities=>newline
                   && cl_abap_char_utilities=>newline
                   && |OBJECT: { i_object_type } { i_object_name }|
                   && cl_abap_char_utilities=>newline
                   && |SYNTAX ERROR:|
                   && cl_abap_char_utilities=>newline
                   && lv_syntax_error
                   && cl_abap_char_utilities=>newline
                   && cl_abap_char_utilities=>newline
                   && |SOURCE TO FIX:|
                   && cl_abap_char_utilities=>newline
                   && |```abap|
                   && cl_abap_char_utilities=>newline
                   && lv_source
                   && cl_abap_char_utilities=>newline
                   && |```|.

      mo_messages->add_message(
        i_role        = 'user'
        i_agent       = 'SYNTAX_FIX'
        i_prompt_type = 'AGENT_PROMPT'
        i_content     = lv_fix_prompt ).

      lv_fix_answer_log = mo_llm->ask( lv_fix_prompt ).
      lv_fixed_source = zcl_code_answer_tools=>extract_code_from_answer( lv_fix_answer_log ).

      mo_messages->add_message(
        i_role        = 'assistant'
        i_agent       = 'SYNTAX_FIX'
        i_prompt_type = 'LLM_RESPONSE'
        i_duration_seconds = mo_llm->get_last_seconds( )
        i_content     = lv_fix_answer_log ).

      IF lv_fixed_source IS INITIAL
      OR lv_fixed_source = lv_source.
        mo_messages->add_message(
          i_role        = 'assistant'
          i_agent       = 'SYNTAX_FIX'
          i_prompt_type = 'AGENT_RESPONSE'
          i_content     = |Syntax fix did not return changed source.| ).
        CONTINUE.
      ENDIF.

      lv_source = lv_fixed_source.
    ENDDO.

    CLEAR rv_source.

  ENDMETHOD.


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


  method LOG_CLASS_EXTRACT.

    DATA(lt_parts) = zcl_code_answer_tools=>extract_class_parts( i_source ).
    DATA(lt_compare_parts) = zcl_code_answer_tools=>extract_class_parts( i_compare_source ).

    rv_source = i_source.
    IF lt_parts IS INITIAL.
      RETURN.
    ENDIF.

    CLEAR rv_source.

    LOOP AT lt_parts INTO DATA(ls_part).
      IF rv_source IS NOT INITIAL.
        rv_source = rv_source
                  && cl_abap_char_utilities=>newline
                  && cl_abap_char_utilities=>newline.
      ENDIF.

      rv_source = rv_source
                && |--- { ls_part-title } ---|
                && cl_abap_char_utilities=>newline
                && ls_part-source.

      IF i_log = abap_true.
        mo_messages->add_message(
          i_role        = 'user'
          i_agent       = zcl_ai_agents_prompts=>c_agent_class_extract
          i_prompt_type = 'COMMAND'
          i_content     = ls_part-title ).

        DATA(lv_content) = |CLASS_EXTRACT { i_phase } { i_object_name } part { sy-tabix }: { ls_part-title }|.

        READ TABLE lt_compare_parts INTO DATA(ls_compare_part)
          WITH KEY part_key = ls_part-part_key.
        DATA(lv_has_compare) = xsdbool( sy-subrc = 0 ).
        IF lv_has_compare = abap_true
        AND ls_compare_part-source = ls_part-source.
          lv_content = lv_content
                    && cl_abap_char_utilities=>newline
                    && |NO CHANGES|.
        ELSE.
          DATA lv_current_context TYPE string.
          DATA lv_proposed_context TYPE string.
          zcl_code_answer_tools=>extract_changed_context(
            EXPORTING
              i_current_source  = ls_compare_part-source
              i_proposed_source = ls_part-source
            IMPORTING
              e_current_source  = lv_current_context
              e_proposed_source = lv_proposed_context ).

          IF lv_has_compare = abap_true.
            lv_content = lv_content
                      && cl_abap_char_utilities=>newline
                      && |CURRENT SOURCE:|
                      && cl_abap_char_utilities=>newline
                      && lv_current_context
                      && cl_abap_char_utilities=>newline
                      && cl_abap_char_utilities=>newline.
          ENDIF.

          lv_content = lv_content
                    && cl_abap_char_utilities=>newline
                    && |PROPOSED SOURCE:|
                    && cl_abap_char_utilities=>newline
                    && lv_proposed_context.
        ENDIF.

        mo_messages->add_message(
          i_role        = 'assistant'
          i_agent       = zcl_ai_agents_prompts=>c_agent_class_extract
          i_prompt_type = 'AGENT_RESPONSE'
          i_content     = lv_content ).
      ENDIF.
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
          object_type = 'PROG'
          object_name = lt_show_parts[ 1 ]
          raw_command = |{ '{' }READ TADIR: PROG { lt_show_parts[ 1 ] }{ '}' }| ).
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

    " Optimization: if prompt is a single bare {AGENT:CODE_SEARCH ...} -> skip all LLM, read directly
    DATA(lv_trimmed_prompt) = lv_prompt.
    CONDENSE lv_trimmed_prompt.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>newline IN lv_trimmed_prompt WITH ''.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf    IN lv_trimmed_prompt WITH ''.
    CONDENSE lv_trimmed_prompt.
    DATA(lv_prompt_parsed) = mo_messages->parse_agent_requests( lv_trimmed_prompt ).
    IF lines( lv_prompt_parsed ) = 1
    AND lv_prompt_parsed[ 1 ]-agent = zcl_ai_agents_prompts=>c_agent_code_search
    AND lv_prompt_parsed[ 1 ]-relevant_prompt IS INITIAL.
      DATA(lv_cs_req) = lv_prompt_parsed[ 1 ].
      DATA lv_cs_source TYPE string.
      CASE lv_cs_req-object_type.
        WHEN 'METH' OR 'METHOD'.
          DATA lv_meth_cls TYPE string.
          DATA lv_meth_mth TYPE string.
          IF lv_cs_req-object_name CS '=>'.
            SPLIT lv_cs_req-object_name AT '=>' INTO lv_meth_cls lv_meth_mth.
          ELSE.
            lv_meth_cls = lv_cs_req-object_name.
          ENDIF.
          TRANSLATE lv_meth_cls TO UPPER CASE.
          TRANSLATE lv_meth_mth TO UPPER CASE.
          CONDENSE lv_meth_cls. CONDENSE lv_meth_mth.
          lv_cs_source = zcl_ai_code_reader=>read_method(
            i_class  = lv_meth_cls
            i_method = lv_meth_mth ).
        WHEN 'CLAS' OR 'CLASS'.
          lv_cs_source = zcl_ai_code_reader=>read_class( lv_cs_req-object_name ).
        WHEN 'REPS' OR 'PROG'.
          lv_cs_source = zcl_ai_code_reader=>read_program( lv_cs_req-object_name ).
        WHEN OTHERS.
          IF lv_cs_req-object_name CS '=>'.
            SPLIT lv_cs_req-object_name AT '=>' INTO lv_meth_cls lv_meth_mth.
            TRANSLATE lv_meth_cls TO UPPER CASE.
            TRANSLATE lv_meth_mth TO UPPER CASE.
            CONDENSE lv_meth_cls. CONDENSE lv_meth_mth.
            lv_cs_source = zcl_ai_code_reader=>read_method(
              i_class  = lv_meth_cls
              i_method = lv_meth_mth ).
          ELSE.
            lv_cs_source = zcl_ai_code_reader=>read_class( lv_cs_req-object_name ).
            IF lv_cs_source IS INITIAL.
              lv_cs_source = zcl_ai_code_reader=>read_program( lv_cs_req-object_name ).
            ENDIF.
          ENDIF.
      ENDCASE.
      IF lv_cs_source IS NOT INITIAL.
        DATA(lv_cs_label) = lv_cs_req-object_name.
        TRANSLATE lv_cs_label TO UPPER CASE.
        mo_messages->add_message(
          i_role        = 'user'
          i_agent       = zcl_ai_agents_prompts=>c_agent_code_search
          i_prompt_type = 'AGENT_PROMPT'
          i_content     = |Direct lookup: { lv_cs_label }| ).
        mo_messages->add_message(
          i_role        = 'assistant'
          i_agent       = zcl_ai_agents_prompts=>c_agent_code_search
          i_prompt_type = 'AGENT_RESPONSE'
          i_content     = lv_cs_source ).
        rs_result-answer = zcl_code_html_gen=>source_to_html(
          i_source = lv_cs_source
          i_title  = lv_cs_label ).
        rs_result-answer_log  = lv_cs_source.
        rs_result-messages_ref = mo_messages.
        rs_result-messages    = mo_messages->get_messages( ).
        RETURN.
      ENDIF.
    ENDIF.

    " Optimization: single code word (only latin/digits/_) -> skip LLM steps, find object directly
    IF is_single_code_word( lv_prompt ) = abap_true.
      DATA(lv_word) = lv_prompt.
      CONDENSE lv_word.
      TRANSLATE lv_word TO UPPER CASE.
      show_step( i_text = |Looking up { lv_word }...| i_pct = 30 ).
      mo_messages->add_message(
        i_role        = 'user'
        i_agent       = zcl_ai_agents_prompts=>c_agent_code_search
        i_prompt_type = 'AGENT_PROMPT'
        i_content     = |Direct lookup: { lv_word }| ).
      DATA(lv_direct_source) = zcl_ai_code_reader=>read_class( lv_word ).
      DATA(lv_direct_upper) = lv_direct_source.
      TRANSLATE lv_direct_upper TO UPPER CASE.
      IF lv_direct_source IS INITIAL OR lv_direct_upper CS 'NOT FOUND' OR lv_direct_upper CS 'SIMILAR CLASSES'.
        DATA(lv_class_err) = lv_direct_source.
        lv_direct_source = zcl_ai_code_reader=>read_program( lv_word ).
        DATA(lv_direct_upper2) = lv_direct_source.
        TRANSLATE lv_direct_upper2 TO UPPER CASE.
        IF lv_direct_source IS INITIAL OR lv_direct_upper2 CS 'NOT FOUND' OR lv_direct_upper2 CS 'CANNOT BE READ'.
          " Neither found - show both error messages
          lv_direct_source = lv_class_err && cl_abap_char_utilities=>newline && lv_direct_source.
        ENDIF.
      ENDIF.
      IF lv_direct_source IS NOT INITIAL.
        mo_messages->add_message(
          i_role        = 'assistant'
          i_agent       = zcl_ai_agents_prompts=>c_agent_code_search
          i_prompt_type = 'AGENT_RESPONSE'
          i_content     = lv_direct_source ).
        rs_result-answer = zcl_code_html_gen=>source_to_html(
          i_source = lv_direct_source
          i_title  = lv_word ).
        rs_result-answer_log  = lv_direct_source.
        rs_result-messages_ref = mo_messages.
        rs_result-messages    = mo_messages->get_messages( ).
        RETURN.
      ENDIF.
    ENDIF.

    show_step( i_text = 'Detecting language...' i_pct = 5 ).
    DATA(lv_user_language) = detect_prompt_language( lv_prompt ).
    complete_last_step( i_is_llm = abap_true i_seconds = CONV #( mo_llm->get_last_seconds( ) ) i_tok_in = mo_llm->mv_last_tok_in i_tok_out = mo_llm->mv_last_tok_out ).
    IF lv_user_language IS NOT INITIAL.
      mo_prompts->set_user_language( lv_user_language ).
    ENDIF.

    show_step( i_text = 'Planning tasks...' i_pct = 10 ).
    DATA(lt_tasks) = mo_task_planner->prepare_task_list( lv_prompt ).
    complete_last_step( i_is_llm = abap_true i_seconds = CONV #( mo_llm->get_last_seconds( ) ) i_tok_in = mo_llm->mv_last_tok_in i_tok_out = mo_llm->mv_last_tok_out ).
    DATA(lv_effective_prompt) = build_effective_prompt(
      i_prompt  = lv_prompt
      it_tasks  = lt_tasks ).

    " If task orchestrator returned a single pure CODE_SEARCH command - skip main orchestrator
    DATA lv_orchestrator_answer TYPE string.
    IF lines( lt_tasks ) = 1.
      DATA(lv_single_task) = lt_tasks[ 1 ].
      DATA(lv_single_requests) = mo_messages->parse_agent_requests( lv_single_task ).
      IF lines( lv_single_requests ) = 1
      AND lv_single_requests[ 1 ]-agent = zcl_ai_agents_prompts=>c_agent_code_search
      AND lv_single_requests[ 1 ]-relevant_prompt IS INITIAL.
        lv_orchestrator_answer = lv_single_task.
      ENDIF.
    ENDIF.
    IF lv_orchestrator_answer IS INITIAL.
      show_step( i_text = 'Asking orchestrator...' i_pct = 20 ).
      lv_orchestrator_answer = ask_orchestrator( lt_tasks ).
      complete_last_step( i_is_llm = abap_true i_seconds = CONV #( mo_llm->get_last_seconds( ) ) i_tok_in = mo_llm->mv_last_tok_in i_tok_out = mo_llm->mv_last_tok_out ).
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
      DATA lv_diff_package TYPE string.
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
            show_step( i_text = |Reading code { ls_agent_request-object_name }...| i_pct = lv_percentage ).

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
          DATA(lv_change_is_new_object) = has_create_object_request(
            it_agent_requests = lt_agent_requests
            i_object_type     = ls_agent_request-object_type
            i_object_name     = ls_agent_request-object_name ).

          DATA(lv_change_read_command) = COND string(
            WHEN lv_change_is_new_object = abap_false
            THEN mo_messages->build_read_command( ls_agent_request )
            ELSE '' ).
          IF lv_change_read_command IS NOT INITIAL.
            show_step( i_text = |Reading code { ls_agent_request-object_name }...| i_pct = lv_percentage ).

            lv_ignored_context = resolve_and_log_read_commands(
              EXPORTING
                i_text           = lv_change_read_command
              CHANGING
                ct_done_commands = lt_done_read_commands ).
          ELSEIF lv_change_is_new_object = abap_true.
            mo_messages->add_message(
              i_role        = 'assistant'
              i_agent       = zcl_ai_agents_prompts=>c_agent_code_change
              i_prompt_type = 'AGENT_RESPONSE'
              i_content     = |CODE_CHANGE for new object will be generated without reading current SAP source: { ls_agent_request-object_type } { ls_agent_request-object_name }| ).
          ENDIF.
          lv_has_agent_followup_text = abap_true.
          CONTINUE.
        ENDIF.

        IF ls_agent_request-agent = zcl_ai_agents_prompts=>c_agent_code_review.
          DATA(lv_review_object_type) = ls_agent_request-object_type.
          DATA(lv_review_object_name) = ls_agent_request-object_name.
          TRANSLATE lv_review_object_type TO UPPER CASE.
          TRANSLATE lv_review_object_name TO UPPER CASE.
          DATA(lv_review_has_object_group) = abap_false.

          IF lv_review_object_type IS NOT INITIAL
          AND lv_review_object_name IS NOT INITIAL.
            LOOP AT lt_agent_requests INTO DATA(ls_peer_request).
              CHECK ls_peer_request-agent <> zcl_ai_agents_prompts=>c_agent_code_review.

              DATA(lv_peer_object_type) = ls_peer_request-object_type.
              DATA(lv_peer_object_name) = ls_peer_request-object_name.
              TRANSLATE lv_peer_object_type TO UPPER CASE.
              TRANSLATE lv_peer_object_name TO UPPER CASE.

              IF lv_peer_object_type = lv_review_object_type
              AND lv_peer_object_name = lv_review_object_name.
                lv_review_has_object_group = abap_true.
                EXIT.
              ENDIF.
            ENDLOOP.
          ENDIF.

          IF lv_review_has_object_group = abap_true.
            DATA(lv_group_review_is_new_object) = has_create_object_request(
              it_agent_requests = lt_agent_requests
              i_object_type     = ls_agent_request-object_type
              i_object_name     = ls_agent_request-object_name ).

            DATA(lv_group_review_read_command) = COND string(
              WHEN lv_group_review_is_new_object = abap_false
              THEN mo_messages->build_read_command( ls_agent_request )
              ELSE '' ).
            IF lv_group_review_read_command IS NOT INITIAL.
              show_step( i_text = |Reading code { ls_agent_request-object_name }...| i_pct = lv_percentage ).

              lv_ignored_context = resolve_and_log_read_commands(
                EXPORTING
                  i_text           = lv_group_review_read_command
                CHANGING
                  ct_done_commands = lt_done_read_commands ).
            ELSEIF lv_group_review_is_new_object = abap_true.
              mo_messages->add_message(
                i_role        = 'assistant'
                i_agent       = zcl_ai_agents_prompts=>c_agent_code_review
                i_prompt_type = 'AGENT_RESPONSE'
                i_content     = |CODE_REVIEW for new object will review the proposed code after generation: { ls_agent_request-object_type } { ls_agent_request-object_name }| ).
            ENDIF.

            lv_has_agent_followup_text = abap_true.
            IF lv_final_prompt_tasks IS NOT INITIAL.
              lv_final_prompt_tasks = lv_final_prompt_tasks && cl_abap_char_utilities=>newline.
            ENDIF.
            lv_final_prompt_tasks = lv_final_prompt_tasks
                                  && |Review code for { ls_agent_request-object_type } { ls_agent_request-object_name }.|.
            CONTINUE.
          ENDIF.

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

          DATA(lv_diff_is_new_object) = has_create_object_request(
            it_agent_requests = lt_agent_requests
            i_object_type     = ls_agent_request-object_type
            i_object_name     = ls_agent_request-object_name ).

          DATA(lv_diff_read_command) = COND string(
            WHEN lv_diff_is_new_object = abap_false
            THEN mo_messages->build_read_command( ls_agent_request )
            ELSE '' ).
          IF lv_diff_read_command IS NOT INITIAL.
            show_step( i_text = |Reading code { ls_agent_request-object_name }...| i_pct = lv_percentage ).

            lv_ignored_context = resolve_and_log_read_commands(
              EXPORTING
                i_text           = lv_diff_read_command
              CHANGING
                ct_done_commands = lt_done_read_commands ).
          ELSEIF lv_diff_is_new_object = abap_true.
            mo_messages->add_message(
              i_role        = 'assistant'
              i_agent       = zcl_ai_agents_prompts=>c_agent_code_diff
              i_prompt_type = 'AGENT_RESPONSE'
              i_content     = |CODE_DIFF for new object will use empty current source after code extraction: { ls_agent_request-object_type } { ls_agent_request-object_name }| ).
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
          IF lv_diff_package IS INITIAL.
            lv_diff_package = extract_package( ls_agent_request-relevant_prompt ).
          ENDIF.
          APPEND ls_agent_request TO lt_create_object_commands.
          CONTINUE.
        ENDIF.

        IF ls_agent_request-agent = zcl_ai_agents_prompts=>c_agent_save.
          IF lv_diff_package IS INITIAL.
            lv_diff_package = extract_package( ls_agent_request-relevant_prompt ).
          ENDIF.
          APPEND ls_agent_request TO lt_save_commands.
          CONTINUE.
        ENDIF.

        DATA(lv_direct_read_command) = mo_messages->build_read_command( ls_agent_request ).
        IF lv_direct_read_command IS NOT INITIAL.
          show_step( i_text = |Reading code { ls_agent_request-object_name }...| i_pct = lv_percentage ).

          lv_ignored_context = resolve_and_log_read_commands(
            EXPORTING
              i_text           = lv_direct_read_command
            CHANGING
              ct_done_commands = lt_done_read_commands ).

          CONTINUE.
        ENDIF.

        show_step( i_text = |Asking agent { ls_agent_request-agent }...| i_pct = lv_percentage ).

        DATA(lv_agent_prompt) = mo_messages->build_agent_request( ls_agent_request ).
        DATA(lv_agent_answer) = mo_llm->ask( lv_agent_prompt ).
        DATA(lv_agent_answer_log) = lv_agent_answer.
        lv_agent_answer = zcl_ai_messages=>strip_log_info( lv_agent_answer ).

        complete_last_step( i_is_llm = abap_true i_seconds = CONV #( mo_llm->get_last_seconds( ) ) i_tok_in = mo_llm->mv_last_tok_in i_tok_out = mo_llm->mv_last_tok_out ).

        mo_messages->add_message(
          i_role        = 'assistant'
          i_agent       = ls_agent_request-agent
          i_prompt_type = 'LLM_RESPONSE'
          i_duration_seconds = mo_llm->get_last_seconds( )
          i_content     = lv_agent_answer_log ).

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

          show_step( i_text = |Reading code { ls_review_request-object_name }...| i_pct = 80 ).

          lv_ignored_context = resolve_and_log_read_commands(
            EXPORTING
              i_text           = lv_review_read_command
            CHANGING
              ct_done_commands = lt_done_read_commands ).
        ENDLOOP.

        show_step( i_text = 'Asking code review agent...' i_pct = 90 ).

        DATA(lv_review_prompt) = mo_messages->build_agent_requests( lt_batched_code_review ).
        DATA(lv_review_answer) = mo_llm->ask( lv_review_prompt ).
        DATA(lv_review_answer_log) = lv_review_answer.
        lv_review_answer = zcl_ai_messages=>strip_log_info( lv_review_answer ).

        complete_last_step( i_is_llm = abap_true i_seconds = CONV #( mo_llm->get_last_seconds( ) ) i_tok_in = mo_llm->mv_last_tok_in i_tok_out = mo_llm->mv_last_tok_out ).

        mo_messages->add_message(
          i_role        = 'assistant'
          i_agent       = zcl_ai_agents_prompts=>c_agent_code_review
          i_prompt_type = 'LLM_RESPONSE'
          i_duration_seconds = mo_llm->get_last_seconds( )
          i_content     = lv_review_answer_log ).
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
           OR lv_has_show_command = abap_true
           OR mo_messages->get_resolved_code( ) IS NOT INITIAL ).
        complete_last_step( ).
        DATA(lv_code_only) = mo_messages->get_resolved_code( ).
        lv_answer_log = lv_code_only.
        lv_answer = zcl_code_html_gen=>source_to_html(
          i_source = lv_code_only
          i_title  = 'ABAP Source' ).
      ELSE.
        show_step( i_text = 'Asking AI...' i_pct = 85 ).

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
        complete_last_step( i_is_llm = abap_true i_seconds = CONV #( mo_llm->get_last_seconds( ) ) i_tok_in = mo_llm->mv_last_tok_in i_tok_out = mo_llm->mv_last_tok_out ).
        lv_answer_log = lv_answer.
        lv_answer = zcl_ai_messages=>strip_log_info( lv_answer ).
        DATA(lv_total_usage) = mo_messages->get_total_token_usage( lv_answer_log ).
        IF lv_total_usage IS NOT INITIAL.
          lv_answer = lv_answer
                   && cl_abap_char_utilities=>newline
                   && cl_abap_char_utilities=>newline
                   && |---|
                   && cl_abap_char_utilities=>newline
                   && lv_total_usage.
          lv_answer_log = lv_answer.
        ENDIF.

        lv_resolved_code = mo_messages->get_resolved_code( ).
      ENDIF.

      mo_messages->add_message(
        i_role        = 'assistant'
        i_agent       = 'FINAL'
        i_prompt_type = 'FINAL_ANSWER'
        i_duration_seconds = lv_final_duration_seconds
        i_content     = lv_answer_log ).

      DATA(lv_answer_log_upper) = lv_answer_log.
      TRANSLATE lv_answer_log_upper TO UPPER CASE.
      DATA(lv_has_changes_yes) = xsdbool( lv_answer_log_upper CS 'CHANGES:YES' ).

      IF lv_has_code_change = abap_true AND lv_has_changes_yes = abap_true AND lv_agent_error IS INITIAL.

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

          DATA(lv_diff_old_code) = mo_messages->get_resolved_code( ).
          DATA(lv_diff_new_code) = lv_extracted_code.
          DATA(lv_code_change_type_upper) = lv_code_change_type.
          TRANSLATE lv_code_change_type_upper TO UPPER CASE.
          IF lv_code_change_type_upper CP 'CLAS*'.
            lv_diff_old_code = log_class_extract(
              i_source      = lv_diff_old_code
              i_object_name = lv_code_change_name
              i_phase       = 'CURRENT'
              i_log         = abap_false ).
            lv_diff_new_code = log_class_extract(
              i_source      = lv_diff_new_code
              i_object_name = lv_code_change_name
              i_phase       = 'PROPOSED'
              i_compare_source = lv_diff_old_code ).
          ENDIF.

          lv_diff_new_code = fix_program_syntax(
            i_source      = lv_diff_new_code
            i_object_type = lv_code_change_type
            i_object_name = lv_code_change_name ).

          IF lv_diff_new_code IS INITIAL.
            lv_answer = |Extracted code still has syntax errors after 5 fix attempts. Code review is hidden until the code is fixed.|.
            lv_answer_log = lv_answer.
            mo_messages->add_message(
              i_role        = 'assistant'
              i_agent       = zcl_ai_agents_prompts=>c_agent_code_diff
              i_prompt_type = 'AGENT_RESPONSE'
              i_content     = lv_answer ).
          ELSE.

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
            rs_result-diff_old_code = lv_diff_old_code.
            rs_result-diff_new_code = lv_diff_new_code.
            rs_result-diff_object_type = lv_code_change_type.
            rs_result-diff_object_name = lv_code_change_name.
            rs_result-diff_package = lv_diff_package.
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

          DATA(lv_create_type_upper) = ls_create_object_command-object_type.
          TRANSLATE lv_create_type_upper TO UPPER CASE.
          IF lv_create_type_upper CP 'CLAS*'.
            lv_create_context = log_class_extract(
              i_source      = lv_create_context
              i_object_name = ls_create_object_command-object_name
              i_phase       = 'CURRENT'
              i_log         = abap_false ).
            lv_create_extracted_code = log_class_extract(
              i_source      = lv_create_extracted_code
              i_object_name = ls_create_object_command-object_name
              i_phase       = 'PROPOSED'
              i_compare_source = lv_create_context ).
          ENDIF.

          lv_create_extracted_code = fix_program_syntax(
            i_source      = lv_create_extracted_code
            i_object_type = ls_create_object_command-object_type
            i_object_name = ls_create_object_command-object_name ).

          IF lv_create_extracted_code IS INITIAL.
            lv_answer = |Extracted code still has syntax errors after 5 fix attempts. Code review is hidden until the code is fixed.|.
            lv_answer_log = lv_answer.
            mo_messages->add_message(
              i_role        = 'assistant'
              i_agent       = zcl_ai_agents_prompts=>c_agent_code_diff
              i_prompt_type = 'AGENT_RESPONSE'
              i_content     = lv_answer ).
          ENDIF.
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

          IF lv_create_extracted_code IS NOT INITIAL.
            rs_result-has_diff = abap_true.
            rs_result-diff_old_code = lv_create_context.
            rs_result-diff_new_code = lv_create_extracted_code.
            rs_result-diff_object_type = ls_create_object_command-object_type.
            rs_result-diff_object_name = ls_create_object_command-object_name.
            rs_result-diff_package = lv_diff_package.
          ENDIF.

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
            rs_result-diff_package = lv_diff_package.
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

  method GET_MESSAGES.

    ro_messages = mo_messages.

  endmethod.


  method SET_HTML_VIEWER.

    mo_html_viewer = io_viewer.
    CLEAR mt_progress_steps.
    CLEAR mv_total_seconds.
    CLEAR mv_total_tok_in.
    CLEAR mv_total_tok_out.

  endmethod.


  method SHOW_STEP.

    CALL FUNCTION 'SAPGUI_PROGRESS_INDICATOR'
      EXPORTING percentage = i_pct text = i_text.

    CHECK mo_html_viewer IS BOUND.

    " Mark previous last step as done
    DATA(lv_last) = lines( mt_progress_steps ).
    IF lv_last > 0.
      FIELD-SYMBOLS <ls_prev> TYPE ty_step.
      READ TABLE mt_progress_steps ASSIGNING <ls_prev> INDEX lv_last.
      IF sy-subrc = 0.
        <ls_prev>-done = abap_true.
      ENDIF.
    ENDIF.

    APPEND VALUE ty_step( text = i_text done = abap_false ) TO mt_progress_steps.

    DATA(lv_html) = render_steps_html( ).
    DATA lt_html TYPE STANDARD TABLE OF w3html WITH NON-UNIQUE DEFAULT KEY.
    DATA lv_off TYPE i.
    WHILE lv_off < strlen( lv_html ).
      DATA(lv_chunk) = nmin( val1 = 255 val2 = strlen( lv_html ) - lv_off ).
      APPEND VALUE w3html( line = substring( val = lv_html off = lv_off len = lv_chunk ) )
        TO lt_html.
      lv_off = lv_off + lv_chunk.
    ENDWHILE.
    DATA lv_url TYPE c LENGTH 255.
    mo_html_viewer->load_data(
      EXPORTING type = 'text' subtype = 'html'
      IMPORTING assigned_url = lv_url
      CHANGING  data_table   = lt_html
      EXCEPTIONS OTHERS = 1 ).
    CHECK sy-subrc = 0.
    mo_html_viewer->show_url( EXPORTING url = lv_url EXCEPTIONS OTHERS = 1 ).
    cl_gui_cfw=>flush( ).

  endmethod.


  method COMPLETE_LAST_STEP.

    CHECK mo_html_viewer IS BOUND.

    DATA(lv_last) = lines( mt_progress_steps ).
    CHECK lv_last > 0.

    FIELD-SYMBOLS <ls_step> TYPE ty_step.
    READ TABLE mt_progress_steps ASSIGNING <ls_step> INDEX lv_last.
    CHECK sy-subrc = 0.

    <ls_step>-done    = abap_true.
    <ls_step>-is_llm  = i_is_llm.
    <ls_step>-seconds = i_seconds.
    <ls_step>-tok_in  = i_tok_in.
    <ls_step>-tok_out = i_tok_out.

    IF i_is_llm = abap_true.
      mv_total_seconds = mv_total_seconds + i_seconds.
      mv_total_tok_in  = mv_total_tok_in  + i_tok_in.
      mv_total_tok_out = mv_total_tok_out + i_tok_out.
    ENDIF.

    DATA(lv_html) = render_steps_html( ).
    DATA lt_html TYPE STANDARD TABLE OF w3html WITH NON-UNIQUE DEFAULT KEY.
    DATA lv_off TYPE i.
    WHILE lv_off < strlen( lv_html ).
      DATA(lv_chunk) = nmin( val1 = 255 val2 = strlen( lv_html ) - lv_off ).
      APPEND VALUE w3html( line = substring( val = lv_html off = lv_off len = lv_chunk ) )
        TO lt_html.
      lv_off = lv_off + lv_chunk.
    ENDWHILE.
    DATA lv_url TYPE c LENGTH 255.
    mo_html_viewer->load_data(
      EXPORTING type = 'text' subtype = 'html'
      IMPORTING assigned_url = lv_url
      CHANGING  data_table   = lt_html
      EXCEPTIONS OTHERS = 1 ).
    CHECK sy-subrc = 0.
    mo_html_viewer->show_url( EXPORTING url = lv_url EXCEPTIONS OTHERS = 1 ).
    cl_gui_cfw=>flush( ).

  endmethod.


  method RENDER_STEPS_HTML.

    DATA lv_rows TYPE string.
    LOOP AT mt_progress_steps INTO DATA(ls_step).
      DATA(lv_text) = ls_step-text.
      REPLACE ALL OCCURRENCES OF '&' IN lv_text WITH '&amp;'.
      REPLACE ALL OCCURRENCES OF '<' IN lv_text WITH '&lt;'.
      REPLACE ALL OCCURRENCES OF '>' IN lv_text WITH '&gt;'.

      IF ls_step-done = abap_true.
        DATA(lv_info) = VALUE string( ).
        IF ls_step-is_llm = abap_true.
          lv_info = | &nbsp;<span class="info">{ ls_step-seconds }s|.
          IF ls_step-tok_in > 0.
            lv_info = lv_info && | Tokens: inp:{ ls_step-tok_in }, out:{ ls_step-tok_out }|.
          ENDIF.
          lv_info = lv_info && |</span>|.
        ENDIF.
        lv_rows = lv_rows
          && |<div class="step done">&#x2713; { lv_text }{ lv_info }</div>|.
      ELSE.
        lv_rows = lv_rows
          && |<div class="step active">&#x23F3; { lv_text }</div>|.
      ENDIF.
    ENDLOOP.

    IF mv_total_seconds > 0.
      lv_rows = lv_rows
        && |<div class="total">Total: { mv_total_seconds }s|.
      IF mv_total_tok_in > 0.
        lv_rows = lv_rows && | Tokens: inp:{ mv_total_tok_in }, out:{ mv_total_tok_out }|.
      ENDIF.
      lv_rows = lv_rows && |</div>|.
    ENDIF.

    rv_html =
      |<!DOCTYPE html><html><head><meta charset="utf-8"><style>|
      && |body\{font-family:Segoe UI,Arial,sans-serif;margin:12px;background:#f5f5f5\}|
      && |.step\{padding:5px 10px;margin:3px 0;border-radius:3px;font-size:13px\}|
      && |.done\{color:#2e7d32\}|
      && |.active\{color:#0033aa;font-style:italic\}|
      && |.info\{color:#888;font-size:11px\}|
      && |.total\{margin-top:8px;padding:5px 10px;font-size:12px;border-radius:3px;|
      && |color:#0033aa;font-weight:bold\}|
      && |</style></head><body>|
      && lv_rows
      && |</body></html>|.

  endmethod.


  METHOD is_single_code_word.

    DATA(lv_trimmed) = i_prompt.
    CONDENSE lv_trimmed.

    " Single word = no spaces, only A-Z a-z 0-9 _
    IF lv_trimmed IS INITIAL.
      RETURN.
    ENDIF.
    IF lv_trimmed CA ' '.
      RETURN.
    ENDIF.
    FIND FIRST OCCURRENCE OF REGEX '[^A-Za-z0-9_]' IN lv_trimmed.
    IF sy-subrc <> 0.
      rv_is = abap_true.
    ENDIF.

  ENDMETHOD.

ENDCLASS.
