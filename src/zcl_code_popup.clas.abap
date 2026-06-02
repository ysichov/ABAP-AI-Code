class ZCL_CODE_POPUP definition
  public
  create public .

public section.

  methods CONSTRUCTOR
    importing
      !I_DEST type TEXT255
      !I_MODEL type TEXT255
      !I_APIKEY type STRING
      !I_PROVIDER type STRING
      !I_AGENTS_PATH type STRING .
  methods SHOW .
protected section.
private section.

  types:
    ty_textedit_line(255) TYPE c .
  types:
    tt_textedit_lines     TYPE TABLE OF ty_textedit_line .
  types:
    tt_html               TYPE STANDARD TABLE OF w3html WITH NON-UNIQUE DEFAULT KEY .
  data MV_SESSION_COUNTER type I .
  data MO_MESSAGES type ref to ZCL_AI_MESSAGES .
  data MO_LLM type ref to ZCL_LLM_CLIENT .
  data MO_PROMPTS type ref to ZCL_AI_AGENTS_PROMPTS .
  data MT_MESSAGE_HISTORY type ZCL_AI_MESSAGES=>TT_MESSAGES .
  data MO_HISTORY type ref to ZCL_API_HISTORY_POPUP .
  data MO_DIALOG type ref to CL_GUI_DIALOGBOX_CONTAINER .
  data MO_TOOLBAR type ref to CL_GUI_TOOLBAR .
  data MO_SPLIT type ref to CL_GUI_SPLITTER_CONTAINER .
  data MO_QUESTION type ref to CL_GUI_TEXTEDIT .
  data MO_ANSWER type ref to CL_GUI_HTML_VIEWER .
  data MV_DIFF_BASE_HTML type STRING .
  data MV_DIFF_KEY type STRING .
  data MV_DIFF_OBJECT_TYPE type STRING .
  data MV_DIFF_OBJECT_NAME type STRING .
  data MV_DIFF_PACKAGE type STRING .
  data MV_DIFF_NEW_CODE type STRING .
  data MV_DIFF_SAVE_STUB_LOGGED type ABAP_BOOL .
  data MV_SAVE_FIX_ATTEMPTS type I .
  data MV_RUN_PROGRAM type PROGNAME .
  data MV_RUN_BUTTON_ADDED type ABAP_BOOL .
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
  methods DISPLAY_TEXT
    importing
      !I_TEXT type STRING .
  methods DISPLAY_ANSWER
    importing
      !I_ANSWER type STRING
      !I_SOURCE type STRING optional .
  methods DIFF_TO_HTML
    importing
      !I_OLD_CODE type STRING
      !I_NEW_CODE type STRING
      !I_OBJECT_TYPE type STRING optional
      !I_OBJECT_NAME type STRING optional
      !I_PACKAGE type STRING optional
      !I_USAGE_TEXT type STRING optional
    returning
      value(RV_HTML) type STRING .
  methods REFRESH_DIFF_HTML .
  methods CONFIRM_SAVE_APPROVED_DIFF
    returning
      value(RV_CONFIRMED) type ABAP_BOOL .
  methods SAVE_APPROVED_DIFF .
  methods SHOW_RUN_PROGRAM_BUTTON .
  methods RUN_PROGRAM .
  methods REQUEST_SAVE_FIX
    importing
      !I_SAVE_LOG type STRING .
  methods SYNC_MESSAGE_HISTORY .
ENDCLASS.



CLASS ZCL_CODE_POPUP IMPLEMENTATION.


  method ASK_AI.

    DATA lt_lines TYPE tt_textedit_lines.
    mo_question->get_text_as_stream( IMPORTING text = lt_lines ).

    DATA lv_prompt TYPE string.
    LOOP AT lt_lines INTO DATA(ls_line).
      DATA(lv_line) = CONV string( ls_line ).
      REPLACE FIRST OCCURRENCE OF REGEX '\s+$' IN lv_line WITH ''.

      IF lv_prompt IS NOT INITIAL.
        lv_prompt = lv_prompt && cl_abap_char_utilities=>newline.
      ENDIF.
      lv_prompt = lv_prompt && lv_line.
    ENDLOOP.

    DATA(lv_prompt_check) = lv_prompt.
    CONDENSE lv_prompt_check.
    IF lv_prompt_check IS INITIAL.
      MESSAGE 'Please enter a question' TYPE 'I'.
      RETURN.
    ENDIF.

    mv_session_counter = mv_session_counter + 1.

    DATA(lo_runner) = NEW zcl_code_ai_runner(
      io_llm     = mo_llm
      io_prompts = mo_prompts ).
    DATA(ls_result) = lo_runner->run(
      i_prompt     = lv_prompt
      i_session_id = mv_session_counter ).

    mo_messages = ls_result-messages_ref.
    APPEND LINES OF ls_result-messages TO mt_message_history.

    CALL FUNCTION 'SAPGUI_PROGRESS_INDICATOR'
      EXPORTING percentage = 0 text = ''.

    DATA(lv_display_answer) = ls_result-answer.
    IF ls_result-has_diff = abap_true.
      lv_display_answer = diff_to_html(
        i_old_code    = ls_result-diff_old_code
        i_new_code    = ls_result-diff_new_code
        i_object_type = ls_result-diff_object_type
        i_object_name = ls_result-diff_object_name
        i_package     = ls_result-diff_package
        i_usage_text  = ls_result-answer_log ).
    ENDIF.

    REPLACE ALL OCCURRENCES OF REGEX '(^|[\r\n]+)\s*CHANGES\s*:\s*(YES|NO)\s*$'
      IN lv_display_answer WITH '' IGNORING CASE.
    REPLACE ALL OCCURRENCES OF REGEX '\s*CHANGES\s*:\s*(YES|NO)\s*$'
      IN lv_display_answer WITH '' IGNORING CASE.

    display_answer(
      i_answer = lv_display_answer
      i_source = ls_result-resolved_code ).

  endmethod.


  method CONSTRUCTOR.

    mo_llm = NEW zcl_llm_client(
      i_dest     = i_dest
      i_model    = i_model
      i_apikey   = i_apikey
      i_provider = i_provider ).

    mo_prompts = NEW zcl_ai_agents_prompts( i_agents_path = i_agents_path ).

  endmethod.


  method DIFF_TO_HTML.

    zcl_code_html_gen=>build_diff_html(
      EXPORTING
        i_old_code    = i_old_code
        i_new_code    = i_new_code
        i_object_type = i_object_type
        i_object_name = i_object_name
        i_usage_text  = i_usage_text
      IMPORTING
        e_html        = rv_html
        e_base_html   = mv_diff_base_html
        e_diff_key    = mv_diff_key
        et_hunk_info  = mt_diff_hunk_info
        et_acr_stats  = mt_diff_acr_stats ).

    mv_diff_object_type = i_object_type.
    mv_diff_object_name = i_object_name.
    mv_diff_package = i_package.
    mv_diff_new_code = i_new_code.

    CLEAR: mt_diff_approved,
           mt_diff_declined,
           mt_diff_decline_notes,
           mt_diff_hunk_actions,
           mt_diff_hunk_threads,
           mv_diff_save_stub_logged,
           mv_save_fix_attempts.

  endmethod.


  method DISPLAY_ANSWER.

    DATA lv_html TYPE string.

    lv_html = zcl_code_html_gen=>answer_to_html(
      i_answer = i_answer
      i_source = i_source ).

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
      IF confirm_save_approved_diff( ) = abap_true.
        mv_diff_save_stub_logged = abap_true.
        save_approved_diff( ).
        RETURN.
      ENDIF.
    ENDIF.

    refresh_diff_html( ).

  endmethod.


  METHOD confirm_save_approved_diff.

    DATA lv_answer TYPE c LENGTH 1.
    DATA lv_question TYPE string.

    lv_question = |All changes are approved. Save { mv_diff_object_type } { mv_diff_object_name } now?|.

    CALL FUNCTION 'POPUP_TO_CONFIRM'
      EXPORTING
        titlebar              = 'Save approved changes'
        text_question         = lv_question
        text_button_1         = 'Yes'
        text_button_2         = 'No'
        default_button        = '1'
        display_cancel_button = abap_true
      IMPORTING
        answer                = lv_answer
      EXCEPTIONS
        text_not_found        = 1
        OTHERS                = 2.

    rv_confirmed = xsdbool( sy-subrc = 0 AND lv_answer = '1' ).

  ENDMETHOD.


  METHOD save_approved_diff.

    DATA(lv_save_command) = |Save approved AI diff: { mv_diff_key }|
                         && cl_abap_char_utilities=>newline
                         && |Object: { mv_diff_object_type } { mv_diff_object_name }|
                         && cl_abap_char_utilities=>newline
                         && |Package: { mv_diff_package }|
                         && cl_abap_char_utilities=>newline
                         && |PROPOSED SOURCE:|
                         && cl_abap_char_utilities=>newline
                         && mv_diff_new_code.

    mo_messages->add_message(
      i_role        = 'user'
      i_agent       = 'SAVE_OBJECT'
      i_prompt_type = 'COMMAND'
      i_content     = lv_save_command ).

    DATA(lv_save_message) = zcl_code_object_saver=>save(
      i_object_type = mv_diff_object_type
      i_object_name = mv_diff_object_name
      i_source      = mv_diff_new_code
      i_package     = mv_diff_package ).

    mo_messages->add_message(
      i_role        = 'assistant'
      i_agent       = 'SAVE_OBJECT'
      i_prompt_type = 'AGENT_RESPONSE'
      i_content     = lv_save_message ).

    sync_message_history( ).

    DATA(lv_save_message_upper) = lv_save_message.
    TRANSLATE lv_save_message_upper TO UPPER CASE.
    IF lv_save_message_upper CS 'SYNTAX ERROR'
    OR lv_save_message_upper CS 'ERROR SAVING'
    OR lv_save_message_upper CS 'ERROR CREATING'
    OR lv_save_message_upper CS 'ERROR UPDATING'
    OR lv_save_message_upper CS 'ERROR ACTIVATING'
    OR lv_save_message_upper CS 'WAS WRITTEN, BUT'.
      CLEAR: mv_diff_base_html,
             mv_diff_key,
             mt_diff_approved,
             mt_diff_declined,
             mt_diff_decline_notes,
             mt_diff_hunk_actions,
             mt_diff_hunk_threads,
             mv_diff_save_stub_logged.
      display_text(
        |Saved inactive version has errors. Asking AI to fix them before showing code review again.|
        && cl_abap_char_utilities=>newline
        && cl_abap_char_utilities=>newline
        && lv_save_message ).
      request_save_fix( lv_save_message ).
      RETURN.
    ENDIF.

    IF lv_save_message_upper CS 'ACTIVATED'.
      MV_RUN_PROGRAM = CONV progname( mv_diff_object_name ).
      SHOW_RUN_PROGRAM_BUTTON( ).
    ENDIF.

    MESSAGE lv_save_message TYPE 'S'.

  ENDMETHOD.


  METHOD request_save_fix.

    mv_save_fix_attempts = mv_save_fix_attempts + 1.

    DATA(lv_fix_prompt) = |You are a Senior ABAP syntax-fix agent.|
                       && cl_abap_char_utilities=>newline
                       && |The SAP save/syntax-check failed. Return the complete corrected ABAP source only in one abap fenced code block.|
                       && cl_abap_char_utilities=>newline
                       && |Do not explain. Do not return CHANGES:NO. Keep the object name and intent.|
                       && cl_abap_char_utilities=>newline
                       && |The corrected source must be different from SOURCE TO FIX and must address the SAP SAVE ERROR LOG.|
                       && cl_abap_char_utilities=>newline
                       && |For selection screens, PARAMETERS and SELECT-OPTIONS names must be at most 8 characters long.|
                       && cl_abap_char_utilities=>newline
                       && cl_abap_char_utilities=>newline
                       && |OBJECT: { mv_diff_object_type } { mv_diff_object_name }|
                       && cl_abap_char_utilities=>newline
                       && |PACKAGE: { mv_diff_package }|
                       && cl_abap_char_utilities=>newline
                       && |FIX ATTEMPT: { mv_save_fix_attempts }|
                       && cl_abap_char_utilities=>newline
                       && cl_abap_char_utilities=>newline
                       && |SAP SAVE ERROR LOG:|
                       && cl_abap_char_utilities=>newline
                       && i_save_log
                       && cl_abap_char_utilities=>newline
                       && cl_abap_char_utilities=>newline
                       && |SOURCE TO FIX:|
                       && cl_abap_char_utilities=>newline
                       && |```abap|
                       && cl_abap_char_utilities=>newline
                       && mv_diff_new_code
                       && cl_abap_char_utilities=>newline
                       && |```|.

    mo_messages->add_message(
      i_role        = 'user'
      i_agent       = 'SAVE_FIX'
      i_prompt_type = 'AGENT_PROMPT'
      i_content     = lv_fix_prompt ).

    CALL FUNCTION 'SAPGUI_PROGRESS_INDICATOR'
      EXPORTING
        percentage = 75
        text       = |Fixing syntax/save error, attempt { mv_save_fix_attempts } of 5...|.

    DATA(lv_fix_answer_log) = mo_llm->ask( lv_fix_prompt ).
    DATA(lv_fixed_source) = zcl_code_answer_tools=>extract_code_from_answer( lv_fix_answer_log ).

    mo_messages->add_message(
      i_role        = 'assistant'
      i_agent       = 'SAVE_FIX'
      i_prompt_type = 'LLM_RESPONSE'
      i_duration_seconds = mo_llm->get_last_seconds( )
      i_content     = lv_fix_answer_log ).

    mo_messages->add_message(
      i_role        = 'assistant'
      i_agent       = 'SAVE_FIX'
      i_prompt_type = 'AGENT_RESPONSE'
      i_content     = COND string(
                        WHEN lv_fixed_source IS INITIAL
                        THEN |No corrected source was extracted from SAVE_FIX response.|
                        ELSE lv_fixed_source ) ).

    sync_message_history( ).

    IF lv_fixed_source IS INITIAL
    OR lv_fixed_source = mv_diff_new_code.
      mo_messages->add_message(
        i_role        = 'assistant'
        i_agent       = 'SAVE_FIX'
        i_prompt_type = 'AGENT_RESPONSE'
        i_content     = COND string(
                          WHEN lv_fixed_source IS INITIAL
                          THEN |SAVE_FIX did not return corrected source.|
                          ELSE |SAVE_FIX returned unchanged source; requesting another correction attempt.| ) ).
      sync_message_history( ).

      IF mv_save_fix_attempts < 5.
        request_save_fix( i_save_log ).
        RETURN.
      ENDIF.

      CLEAR mv_diff_save_stub_logged.
      MESSAGE i_save_log TYPE 'S'.
      RETURN.
    ENDIF.

    DATA(lv_fixed_syntax_error) = zcl_code_object_saver=>check_program_syntax( lv_fixed_source ).
    IF lv_fixed_syntax_error IS NOT INITIAL.
      mo_messages->add_message(
        i_role        = 'assistant'
        i_agent       = 'SAVE_FIX'
        i_prompt_type = 'AGENT_RESPONSE'
        i_content     = |SAVE_FIX returned source with syntax errors: { lv_fixed_syntax_error }| ).
      sync_message_history( ).

      IF mv_save_fix_attempts < 5.
        mv_diff_new_code = lv_fixed_source.
        request_save_fix( lv_fixed_syntax_error ).
        RETURN.
      ENDIF.

      CLEAR mv_diff_save_stub_logged.
      MESSAGE lv_fixed_syntax_error TYPE 'S'.
      RETURN.
    ENDIF.

    DATA(lv_html) = diff_to_html(
      i_old_code    = mv_diff_new_code
      i_new_code    = lv_fixed_source
      i_object_type = mv_diff_object_type
      i_object_name = mv_diff_object_name
      i_package     = mv_diff_package
      i_usage_text  = |SAVE_FIX proposal after SAP save error.| ).

    CLEAR mv_diff_save_stub_logged.
    display_answer( lv_html ).

    MESSAGE 'AI proposed a save-error fix. Review and approve before saving.' TYPE 'S'.

  ENDMETHOD.


  METHOD sync_message_history.

    IF mo_messages IS NOT BOUND.
      RETURN.
    ENDIF.

    DATA(lt_messages) = mo_messages->get_messages( ).
    LOOP AT lt_messages INTO DATA(ls_message).
      READ TABLE mt_message_history TRANSPORTING NO FIELDS
        WITH KEY session_id = ls_message-session_id
                 message_id = ls_message-message_id.
      IF sy-subrc <> 0.
        APPEND ls_message TO mt_message_history.
      ENDIF.
    ENDLOOP.

  ENDMETHOD.


  method ON_DIALOG_CLOSE.

    mo_dialog->free( ).
    CLEAR mo_dialog.
    CALL METHOD cl_gui_cfw=>flush.

  endmethod.


  METHOD SHOW_RUN_PROGRAM_BUTTON.

    IF mo_toolbar IS NOT BOUND
    OR mv_run_program IS INITIAL
    OR mv_run_button_added = abap_true.
      RETURN.
    ENDIF.

    DATA lt_buttons TYPE ttb_button.
    APPEND VALUE #( function  = 'RUN_PROGRAM'
                    icon      = CONV #( icon_execute_object )
                    butn_type = cntb_btype_button
                    text      = 'RUN program'
                    quickinfo = |Run { mv_run_program } via selection screen| ) TO lt_buttons.
    mo_toolbar->add_button_group( lt_buttons ).
    mv_run_button_added = abap_true.

    CALL METHOD cl_gui_cfw=>flush.

  ENDMETHOD.


  METHOD RUN_PROGRAM.

    IF mv_run_program IS INITIAL.
      MESSAGE 'No activated program to run yet' TYPE 'I'.
      RETURN.
    ENDIF.

    SUBMIT (mv_run_program) VIA SELECTION-SCREEN AND RETURN.

  ENDMETHOD.


  method ON_TOOLBAR_CLICK.

    CASE fcode.
      WHEN 'ASK'.
        ask_ai( ).
      WHEN 'HISTORY'.
        show_history( ).
      WHEN 'RUN_PROGRAM'.
        run_program( ).
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


ENDCLASS.
