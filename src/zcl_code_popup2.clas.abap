class ZCL_CODE_POPUP2 definition
  public
  create public .

public section.

  methods CONSTRUCTOR
    importing
      !I_MODEL type TEXT255
      !I_APIKEY type STRING
      !I_PROVIDER type STRING
      !I_AGENTS_PATH type STRING
      !I_TEMPERATURE type STRING optional
      !I_STREAM type ABAP_BOOL optional
      !I_LOG_PATH type STRING optional
      !I_MAX_TOKENS type I optional
      !I_THINKING_BUDGET type I optional .
  methods SHOW .
  " Navigate the ABAP editor to an include and position on the first line that
  " contains i_search (plain text search - no parsing). Called by the object tree
  " on double-click. i_program = breakpoint main program (class pool / report).
  methods NAVIGATE_TO
    importing
      !I_PROGRAM type PROGNAME
      !I_INCLUDE type PROGNAME
      !I_SEARCH  type STRING optional .
  " Show diff, ask user to approve/decline changes via diff toolbar. Returns status message.
  methods REVIEW_AND_SAVE
    importing
      !I_OLD_CODE    type STRING
      !I_NEW_CODE    type STRING
      !I_OBJECT_TYPE type STRING
      !I_OBJECT_NAME type STRING
    returning
      value(RV_MESSAGE) type STRING .
  class-methods BUILD_STEPS_HTML
    importing
      !IO_MESSAGES type ref to ZCL_AI_MESSAGES
    returning
      value(RV_HTML) type STRING .
  class-methods SET_LIVE_UPDATE_CONTEXT
    importing
      !IO_ANSWER_VIEWER type ref to CL_GUI_HTML_VIEWER
      !IO_MESSAGES type ref to ZCL_AI_MESSAGES .
  class-methods UPDATE_HTML_WITH_STEPS .
protected section.
private section.

  types:
    ty_textedit_line(255) TYPE c .
  types:
    tt_textedit_lines     TYPE TABLE OF ty_textedit_line .
  types:
    tt_html               TYPE STANDARD TABLE OF w3html WITH NON-UNIQUE DEFAULT KEY .
  types:
    BEGIN OF ts_bpoint,
      program TYPE string,
      include TYPE string,
      line    TYPE i,
      type    TYPE char1,
      del     TYPE char1,
    END OF ts_bpoint .
  types:
    tt_bpoints TYPE STANDARD TABLE OF ts_bpoint WITH EMPTY KEY .
  data MV_SESSION_COUNTER type I .
  data MO_MESSAGES type ref to ZCL_AI_MESSAGES .
  data MO_LLM type ref to ZCL_ABAPAI_LLM_CLIENT .
  data MO_PROMPTS type ref to ZCL_AI_AGENTS_PROMPTS .
  " New tool-based flow: context + agentic runner (replaces legacy planner)
  data MO_TOOL_CONTEXT type ref to ZCL_AI_TOOL_CONTEXT .
  data MO_TOOL_RUNNER type ref to ZCL_AI_TOOL_RUNNER .
  data MT_MESSAGE_HISTORY type ZCL_AI_MESSAGES=>TT_MESSAGES .
  data MO_HISTORY type ref to ZCL_API_HISTORY_POPUP .
  data MO_DIALOG type ref to CL_GUI_DIALOGBOX_CONTAINER .
  data MO_TOOLBAR type ref to CL_GUI_TOOLBAR .
  data MO_SPLIT type ref to CL_GUI_SPLITTER_CONTAINER .
  data MO_QUESTION type ref to CL_GUI_TEXTEDIT .
  data MO_PROGRESS type ref to CL_GUI_HTML_VIEWER .
  " Middle pane split: progress log (top) + object structure tree (bottom).
  " Heights toggled 0/100 to show one at a time (same pattern as the answer pane).
  data MO_MID_SPLIT type ref to CL_GUI_SPLITTER_CONTAINER .
  data MO_MID_CONT_LOG type ref to CL_GUI_CONTAINER .
  data MO_MID_CONT_TREE type ref to CL_GUI_CONTAINER .
  data MO_OBJ_TREE type ref to ZCL_CODE_OBJECT_TREE .
  data MO_ANSWER type ref to CL_GUI_HTML_VIEWER .
  " Right panel split: HTML viewer on top, ABAP editor on bottom.
  " Heights toggled 0/100 to show one at a time (same pattern as ZCL_AVE_POPUP).
  data MO_ANSWER_SPLIT type ref to CL_GUI_SPLITTER_CONTAINER .
  data MO_ANSWER_CONT_HTML type ref to CL_GUI_CONTAINER .
  data MO_ANSWER_CONT_CODE type ref to CL_GUI_CONTAINER .
  data MO_CODE_VIEWER type ref to CL_GUI_ABAPEDIT .
  data MV_DIFF_BASE_HTML type STRING .
  data MV_DIFF_KEY type STRING .
  data MV_DIFF_OBJECT_TYPE type STRING .
  data MV_DIFF_OBJECT_NAME type STRING .
  data MV_DIFF_PACKAGE type STRING .
  data MV_DIFF_NEW_CODE type STRING .
  data MV_DIFF_SAVE_STUB_LOGGED type ABAP_BOOL .
  data MV_SAVE_FIX_ATTEMPTS type I .
  data MV_TEMPERATURE type STRING .
  data MV_STREAM type ABAP_BOOL .
  data MV_AGENTS_PATH type STRING .
  data MV_LOG_PATH   type STRING .
  data MV_MAX_TOKENS type I .
  data MV_APIKEY type STRING .
  data MV_MODEL type TEXT255 .
  data MV_PROVIDER type STRING .
  data MV_STREAM_PROMPT_FILE type STRING .
  data MV_STREAM_RESPONSE_FILE type STRING .
  data MV_RUN_PROGRAM type PROGNAME .
  data MV_RUN_BUTTON_ADDED type ABAP_BOOL .
  data MT_BPOINTS type TT_BPOINTS .
  data MV_DISPLAYED_PROGRAM type PROGNAME .
  data MV_DISPLAYED_INCLUDE type PROGNAME .
  data MT_DIFF_HUNK_INFO type ZIF_AVE_ACR_TYPES=>TY_T_HUNK_INFO .
  data MT_DIFF_APPROVED type ZIF_AVE_ACR_TYPES=>TY_APPROVED .
  data MT_DIFF_DECLINED type ZIF_AVE_ACR_TYPES=>TY_APPROVED .
  data MT_DIFF_DECLINE_NOTES type ZIF_AVE_ACR_TYPES=>TY_T_DECLINE_NOTES .
  data MT_DIFF_HUNK_ACTIONS type ZIF_AVE_ACR_TYPES=>TY_T_HUNK_ACTIONS .
  data MT_DIFF_HUNK_THREADS type ZIF_AVE_ACR_TYPES=>TY_T_HUNK_THREADS .
  data MT_DIFF_ACR_STATS type ZIF_AVE_ACR_TYPES=>TY_T_OBJ_STATS .

  class-data MO_ANSWER_STATIC type ref to CL_GUI_HTML_VIEWER .
  class-data MO_MESSAGES_STATIC type ref to ZCL_AI_MESSAGES .

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
  methods DISPLAY_STATUS
    importing
      !I_TEXT type STRING .
  methods DISPLAY_ANSWER
    importing
      !I_ANSWER type STRING
      !I_SOURCE type STRING optional
      !I_TITLE  type STRING optional .
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
  " Show ABAP program source in the ABAP editor (right panel, bottom row).
  " Used after saving/creating a program so the user sees syntax-highlighted code.
  methods DISPLAY_PROGRAM_SOURCE
    importing
      !I_SOURCE  type STRING
      !I_PROGRAM type PROGNAME optional
      !I_INCLUDE type PROGNAME optional .
  methods ON_CODE_BORDER_CLICK
    for event BORDER_CLICK of CL_GUI_ABAPEDIT
    importing !CNTRL_PRESSED_SET !LINE !SHIFT_PRESSED_SET .
  methods REFRESH_BREAKPOINT_MARKERS .
  " Middle-pane toggles: progress log vs object structure tree.
  methods SHOW_LOG_PANE .
  methods SHOW_TREE_PANE .
  " Read an SAP object (PROG/CLAS/method CLASS=>METHOD) and show it in the ABAP
  " editor with breakpoint support. For a single method, reads the raw method
  " include so editor line numbers map 1:1 to real source lines.
  methods SHOW_OBJECT_IN_EDITOR
    importing
      !I_TYPE type STRING
      !I_NAME type STRING .
  methods BUILD_PLAIN_HTML
    importing
      !I_TEXT type STRING
    returning
      value(RV_HTML) type STRING .
  " Show plain text with typewriter animation (streaming effect).
  methods DISPLAY_STREAMING
    importing
      !I_TEXT type STRING .
ENDCLASS.



CLASS ZCL_CODE_POPUP2 IMPLEMENTATION.


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

    " Show the progress log in the middle pane (a previous answer may have left
    " the object tree visible there).
    show_log_pane( ).

    " =====================================================================
    " NEW TOOL-BASED FLOW (OpenAI function calling).
    " The agentic loop below replaces the legacy planner/proto-tag pipeline.
    " Everything after this block is legacy code kept from ZCL_CODE_POPUP
    " for the display helpers it contains - it is never reached.
    " =====================================================================
    display_status( |Asking AI (tools)...| ).
    cl_gui_cfw=>flush( ).

    " Live step log in the middle pane - same behaviour as the legacy runner
    mo_tool_runner->set_html_viewer( mo_progress ).
    " Pass current session counter so log filenames include it
    mo_tool_runner->mv_session_num = mv_session_counter.

    DATA(lv_tool_answer) = mo_tool_runner->run( lv_prompt ).

    " Restore question text (display_answer may cause editor repaint)
    DATA lt_restore TYPE tt_textedit_lines.
    SPLIT lv_prompt AT cl_abap_char_utilities=>newline INTO TABLE lt_restore.
    mo_question->set_text_as_stream( text = lt_restore ).

    " Pull all logged messages from the tool runner (includes system prompt + all turns)
    DATA(lo_messages) = mo_tool_runner->get_messages( ).
    IF lo_messages IS NOT INITIAL.
      APPEND LINES OF lo_messages->get_messages( ) TO mt_message_history.
      " Share the runner's message log so the later diff approve/save flow
      " (save_approved_diff, request_save_fix) can log without a null reference.
      mo_messages = lo_messages.
    ENDIF.

    " A tool launched an interactive diff code-review: the diff is already shown
    " in the answer panel and the save is driven by its toolbar. Do NOT render the
    " tool answer over it (that would replace the diff with plain text).
    IF mo_tool_runner->is_review_pending( ) = abap_true.
      RETURN.
    ENDIF.

    " Pure object read (the runner answered straight from read_sap_object, with no
    " LLM synthesis). This is plain source, not an LLM answer - show it in the ABAP
    " editor where breakpoints can be set, not as HTML in the answer panel.
    IF mo_tool_runner->mv_read_object_name IS NOT INITIAL.
      show_object_in_editor(
        i_type = mo_tool_runner->mv_read_object_type
        i_name = mo_tool_runner->mv_read_object_name ).
      RETURN.
    ENDIF.

    " Strip raw XML envelopes that LLM should have interpreted but didn't
    DATA(lv_display_answer) = lv_tool_answer.
    IF lv_display_answer CP '<code_analysis*' OR lv_display_answer CP '<code_modified*'.
      REPLACE ALL OCCURRENCES OF REGEX '<[^>]+>' IN lv_display_answer WITH ''.
      CONDENSE lv_display_answer.
    ENDIF.
    " Markdown indicators (pipe tables, headings, bold, fences) win over the
    " code heuristic - a comparison table also contains '--- ' and 'METHOD '
    DATA(lv_is_markdown) = abap_false.
    DATA lt_md_check TYPE STANDARD TABLE OF string WITH NON-UNIQUE DEFAULT KEY.
    DATA lv_pipe_rows TYPE i.
    DATA(lv_md_text) = lv_display_answer.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf
      IN lv_md_text WITH cl_abap_char_utilities=>newline.
    SPLIT lv_md_text AT cl_abap_char_utilities=>newline INTO TABLE lt_md_check.
    LOOP AT lt_md_check INTO DATA(lv_md_line).
      SHIFT lv_md_line LEFT DELETING LEADING space.
      IF strlen( lv_md_line ) >= 2 AND lv_md_line(1) = '|'.
        " Markdown table row: starts AND ends with a pipe
        DATA(lv_md_tail) = strlen( lv_md_line ) - 1.
        IF lv_md_line+lv_md_tail(1) = '|'.
          lv_pipe_rows = lv_pipe_rows + 1.
        ENDIF.
      ENDIF.
    ENDLOOP.
    " 3+ pipe rows = header + separator + data: clearly a table
    IF lv_pipe_rows >= 3.
      lv_is_markdown = abap_true.
    ELSE.
      FIND FIRST OCCURRENCE OF REGEX '(^|\n)#{1,6} |\*\*[^\n*]+\*\*|(^|\n)```'
        IN lv_display_answer.
      IF sy-subrc = 0.
        lv_is_markdown = abap_true.
      ENDIF.
    ENDIF.

    " Check if response is raw ABAP source (first non-empty line starts with a known keyword)
    DATA lv_first_line TYPE string.
    DATA lt_src_lines TYPE STANDARD TABLE OF string WITH NON-UNIQUE DEFAULT KEY.
    SPLIT lv_display_answer AT cl_abap_char_utilities=>newline INTO TABLE lt_src_lines.
    LOOP AT lt_src_lines INTO lv_first_line.
      CONDENSE lv_first_line.
      IF lv_first_line IS NOT INITIAL.
        EXIT.
      ENDIF.
    ENDLOOP.
    DATA lv_first_upper TYPE string.
    lv_first_upper = lv_first_line.
    TRANSLATE lv_first_upper TO UPPER CASE.

    " Source detection: first non-empty line starts with a known ABAP keyword
    " OR with a '--- * ---' section marker produced by zcl_ai_code_reader
    " (read_class / read_method always prefix their output with such a marker).
    DATA lv_is_abap_source TYPE abap_bool.
    IF lv_is_markdown = abap_false
    AND ( lv_first_upper CP 'REPORT *'
       OR lv_first_upper CP 'PROGRAM *'
       OR lv_first_upper CP 'CLASS * DEFINITION*'
       OR lv_first_upper CP 'CLASS * IMPLEMENTATION*'
       OR lv_first_upper CP 'INTERFACE *'
       OR lv_first_upper CP 'METHOD *'
       OR lv_first_upper CP 'FUNCTION *'
       OR lv_first_upper CP '--- * ---' ).
      lv_is_abap_source = abap_true.
    ENDIF.

    IF lv_is_abap_source = abap_true.
      display_program_source( lv_display_answer ).
    ELSE.
      DATA(lv_tool_html) = COND string(
        WHEN lv_is_markdown = abap_true
        THEN zcl_code_html_gen=>markdown_to_html( lv_display_answer )
        WHEN lv_display_answer CP '*CLAS *' OR lv_display_answer CP '*PROG *'
          OR lv_display_answer CP '*DEVC *' OR lv_display_answer CP '*FUGR *'
          OR lv_display_answer CS 'Objects matching'
        THEN zcl_code_html_gen=>search_result_to_html( lv_display_answer )
        ELSE zcl_code_html_gen=>markdown_to_html( lv_display_answer ) ).
      display_answer( i_answer = lv_tool_html ).
    ENDIF.

  endmethod.


  method CONSTRUCTOR.

    mo_llm = NEW zcl_abapai_llm_client(
      i_model    = i_model
      i_apikey   = i_apikey
      i_provider = i_provider ).

    " Apply initial temperature (default 0.1 from selection screen)
    mv_temperature = COND string( WHEN i_temperature IS NOT INITIAL THEN i_temperature ELSE '0.1' ).
    mo_llm->set_temperature( mv_temperature ).

    mv_stream      = i_stream.
    mv_agents_path = i_agents_path.
    mv_apikey      = i_apikey.
    mv_model       = i_model.
    mv_provider    = i_provider.
    mv_log_path    = i_log_path.
    mv_max_tokens  = i_max_tokens.
    mo_llm->set_max_tokens( i_max_tokens ).
    mo_llm->set_thinking_budget( i_thinking_budget ).

    mo_prompts = NEW zcl_ai_agents_prompts( i_agents_path = i_agents_path ).

    " New flow: i_agents_path points to the TOOLS folder
    " (<tool_name>.json schemas + <tool_name>.md prompts)
    mo_tool_context = NEW zcl_ai_tool_context(
      io_llm        = mo_llm
      i_agents_path = i_agents_path ).
    mo_tool_runner = NEW zcl_ai_tool_runner(
      io_llm     = mo_llm
      io_context = mo_tool_context
      io_ui      = me
      i_log_path = i_log_path
      i_provider = i_provider ).

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
      i_source = i_source
      i_title  = i_title ).

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

    " Switch right panel back to HTML viewer (in case ABAP editor was shown before)
    IF mo_answer_split IS BOUND.
      mo_answer_split->set_row_height( id = 1 height = 100 ).
      mo_answer_split->set_row_height( id = 2 height = 0 ).
    ENDIF.

    CALL METHOD cl_gui_cfw=>flush.

  endmethod.


  method DISPLAY_TEXT.

    display_answer( i_answer = i_text ).

  endmethod.


  METHOD display_status.

    display_text( i_text ).

  ENDMETHOD.


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

      WHEN 'openobj'.
        DATA lt_obj_parts TYPE STANDARD TABLE OF string WITH NON-UNIQUE DEFAULT KEY.
        SPLIT lv_rest AT '~' INTO TABLE lt_obj_parts.
        IF lines( lt_obj_parts ) >= 2.
          show_object_in_editor(
            i_type = lt_obj_parts[ 1 ]
            i_name = lt_obj_parts[ 2 ] ).
        ENDIF.
        RETURN.

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

    IF mo_messages IS BOUND.
      mo_messages->add_message(
        i_role        = 'user'
        i_agent       = 'SAVE_OBJECT'
        i_prompt_type = 'COMMAND'
        i_content     = lv_save_command ).
    ENDIF.

    display_status( |Saving approved changes for { mv_diff_object_type } { mv_diff_object_name }...| ).

    " Dynamic call by name: the UI carries no compile-time dependency on the
    " saver, so a read-only delivery (no write tools installed) still activates.
    " Without the saver, the approve-save path reports read-only instead.
    DATA lv_save_message TYPE string.
    TRY.
        CALL METHOD ('ZCL_CODE_OBJECT_SAVER')=>save
          EXPORTING
            i_object_type = mv_diff_object_type
            i_object_name = mv_diff_object_name
            i_source      = mv_diff_new_code
            i_package     = mv_diff_package
          RECEIVING
            rv_message    = lv_save_message.
      CATCH cx_sy_dyn_call_error.
        lv_save_message = 'Write capability is not installed (read-only platform) - '
                       && 'nothing was saved. To enable create/modify/delete, install '
                       && 'https://github.com/ysichov/ABAP-AI-CODE-TOOLS'.
    ENDTRY.

    IF mo_messages IS BOUND.
      mo_messages->add_message(
        i_role        = 'assistant'
        i_agent       = 'SAVE_OBJECT'
        i_prompt_type = 'AGENT_RESPONSE'
        i_content     = lv_save_message ).
    ENDIF.

    sync_message_history( ).

    DATA(lv_save_message_upper) = lv_save_message.
    TRANSLATE lv_save_message_upper TO UPPER CASE.
    DATA(lv_save_obj_type_upper) = mv_diff_object_type.
    TRANSLATE lv_save_obj_type_upper TO UPPER CASE.
    IF lv_save_message_upper CS 'SYNTAX ERROR'
    OR lv_save_message_upper CS 'ERROR SAVING'
    OR lv_save_message_upper CS 'ERROR CREATING'
    OR lv_save_message_upper CS 'ERROR UPDATING'
    OR lv_save_message_upper CS 'ERROR ACTIVATING'
    OR lv_save_message_upper CS 'ERROR WRITING'
    OR lv_save_message_upper CS 'ERROR READING'
    OR lv_save_message_upper CS 'CANNOT READ'
    OR lv_save_message_upper CS 'LOCKED'
    OR lv_save_message_upper CS 'WAS WRITTEN, BUT'.
      CLEAR: mv_diff_base_html,
             mv_diff_key,
             mt_diff_approved,
             mt_diff_declined,
             mt_diff_decline_notes,
             mt_diff_hunk_actions,
             mt_diff_hunk_threads,
             mv_diff_save_stub_logged.
      IF lv_save_obj_type_upper = 'CLAS' OR lv_save_obj_type_upper = 'CLASS'
      OR lv_save_obj_type_upper = 'METH' OR lv_save_obj_type_upper = 'METHOD'.
        display_text( |Save error (auto-fix not supported for classes/methods):| &&
                      cl_abap_char_utilities=>newline && lv_save_message ).
        RETURN.
      ENDIF.
      display_text(
        |Saved inactive version has errors. Asking AI to fix them before showing code review again.|
        && cl_abap_char_utilities=>newline
        && cl_abap_char_utilities=>newline
        && lv_save_message ).
      request_save_fix( lv_save_message ).
      RETURN.
    ENDIF.

    DATA(lv_run_type_upper) = mv_diff_object_type.
    TRANSLATE lv_run_type_upper TO UPPER CASE.
    IF lv_save_message_upper CS 'ACTIVATED'
    AND lv_run_type_upper <> 'METH' AND lv_run_type_upper <> 'METHOD'
    AND lv_run_type_upper <> 'CLAS' AND lv_run_type_upper <> 'CLASS'.
      MV_RUN_PROGRAM = CONV progname( mv_diff_object_name ).
      SHOW_RUN_PROGRAM_BUTTON( ).
    ENDIF.

    " Do NOT overwrite mo_progress here - the runner already filled it with
    " the correct step chips (вњ“ OBJECT_DETECTOR, вњ“ TASK_ORCHESTRATOR, etc.).
    " Replacing it would either erase those steps (old "вњ“ saved" banner) or
    " show raw message internals (build_steps_html). Just leave it as-is.

    " Read saved object and show in answer viewer (right)
    DATA(lv_saved_type_upper) = mv_diff_object_type.
    TRANSLATE lv_saved_type_upper TO UPPER CASE.
    DATA(lv_saved_source) = VALUE string( ).
    CASE lv_saved_type_upper.
      WHEN 'PROG' OR 'REPS' OR 'PROGRAM' OR 'REPORT'.
        lv_saved_source = zcl_ai_code_reader=>read_program( mv_diff_object_name ).
      WHEN 'CLAS' OR 'CLASS' OR 'INTF'.
        lv_saved_source = zcl_ai_code_reader=>read_class( mv_diff_object_name ).
      WHEN 'METH' OR 'METHOD'.
        DATA(lv_saved_cls) = mv_diff_object_name.
        DATA(lv_saved_mth) = VALUE string( ).
        IF mv_diff_object_name CS '=>'.
          SPLIT mv_diff_object_name AT '=>' INTO lv_saved_cls lv_saved_mth.
        ENDIF.
        lv_saved_source = zcl_ai_code_reader=>read_method(
          i_class  = lv_saved_cls
          i_method = lv_saved_mth ).
      WHEN OTHERS.
        lv_saved_source = zcl_ai_code_reader=>read_program( mv_diff_object_name ).
    ENDCASE.
    " For programs/reports show source in the ABAP editor (syntax-highlighted,
    " native SAP editor). For classes/methods keep the HTML view.
    DATA(lv_show_type) = mv_diff_object_type.
    TRANSLATE lv_show_type TO UPPER CASE.
    " Show all code types in the ABAP editor (programs, classes, methods, interfaces)
    display_program_source(
      i_source  = lv_saved_source
      i_program = CONV progname( mv_diff_object_name ) ).

    cl_gui_cfw=>flush( ).
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

    DATA(lv_fix_status) = |Fixing syntax/save error, attempt { mv_save_fix_attempts } of 5...|.

    display_status( lv_fix_status ).

    CALL FUNCTION 'SAPGUI_PROGRESS_INDICATOR'
      EXPORTING
        percentage = 75
        text       = lv_fix_status.

    DATA(lv_fix_answer_log) = mo_llm->ask( lv_fix_prompt ).
    DATA(lv_fixed_source) = zcl_code_answer_tools=>extract_code_from_answer( lv_fix_answer_log ).

    mo_messages->add_message(
      i_role        = 'assistant'
      i_agent       = 'SAVE_FIX'
      i_prompt_type = 'LLM_RESPONSE'
      i_duration_seconds = mo_llm->get_last_seconds( )
      i_tok_in      = mo_llm->mv_last_tok_in
      i_tok_out     = mo_llm->mv_last_tok_out
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

    " Dynamic call by name (no compile-time dependency on the saver). Without
    " the saver installed the pre-save syntax check is simply skipped.
    DATA lv_fixed_syntax_error TYPE string.
    TRY.
        CALL METHOD ('ZCL_CODE_OBJECT_SAVER')=>check_program_syntax
          EXPORTING
            i_source   = lv_fixed_source
          RECEIVING
            rv_message = lv_fixed_syntax_error.
      CATCH cx_sy_dyn_call_error.
        CLEAR lv_fixed_syntax_error.
    ENDTRY.
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
      WHEN 'SET_TEMP'.
        " Popup to enter temperature value 0.0 - 1.0
        DATA lt_temp_fields TYPE TABLE OF sval.
        APPEND VALUE #(
          tabname   = 'TLINE'
          fieldname = 'TDLINE'
          fieldtext = 'Temperature (0.0-1.0)'
          value     = mv_temperature ) TO lt_temp_fields.
        CALL FUNCTION 'POPUP_GET_VALUES'
          EXPORTING  popup_title     = 'Set LLM Temperature'
          TABLES     fields          = lt_temp_fields
          EXCEPTIONS error_in_fields = 1  OTHERS = 2.
        IF sy-subrc = 0.
          READ TABLE lt_temp_fields INTO DATA(ls_temp_field) INDEX 1.
          DATA(lv_new_temp) = CONV string( ls_temp_field-value ).
          CONDENSE lv_new_temp.
          IF lv_new_temp IS NOT INITIAL.
            mv_temperature = lv_new_temp.
            mo_llm->set_temperature( mv_temperature ).
            " Update button label to show current temperature value
            mo_toolbar->set_button_info(
              EXPORTING fcode = 'SET_TEMP'
                        text  = |Temp: { mv_temperature }| ).
            cl_gui_cfw=>flush( ).
            MESSAGE |Temperature set to { mv_temperature }| TYPE 'S'.
          ENDIF.
        ENDIF.
      WHEN 'RUN_PROGRAM'.
        run_program( ).
      WHEN 'NEW_SESSION'.
        mo_tool_runner->clear_session( ).
        display_answer( i_answer = build_plain_html( 'New session started.' ) ).
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
        width    = 1800
        height   = 900
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

    lo_outer->set_row_height( id = 1 height = 4 ).
    lo_outer->set_row_height( id = 2 height = 96 ).
    lo_outer->set_row_sash( id = 1 type = 0 value = 0 ).

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
    APPEND VALUE #( function  = 'SET_TEMP'
                    icon      = CONV #( icon_start_viewer )
                    butn_type = cntb_btype_button
                    text      = |Temp: { mv_temperature }|
                    quickinfo = 'Set LLM temperature (0.0 = deterministic, 1.0 = creative)' ) TO lt_buttons.
    APPEND VALUE #( function  = 'NEW_SESSION'
                    icon      = CONV #( icon_create )
                    butn_type = cntb_btype_button
                    text      = 'New Session'
                    quickinfo = 'Start a new conversation (clears history)' ) TO lt_buttons.
    mo_toolbar->add_button_group( lt_buttons ).

    SET HANDLER on_toolbar_click FOR mo_toolbar.

    " Horizontal splitter: question | progress | answer
    CREATE OBJECT mo_split
      EXPORTING
        parent  = lo_editors_cont
        rows    = 1
        columns = 3
      EXCEPTIONS
        OTHERS  = 1.

    mo_split->set_column_width( id = 1 width = 25 ).
    mo_split->set_column_width( id = 2 width = 25 ).
    mo_split->set_column_width( id = 3 width = 50 ).

    DATA lo_left   TYPE REF TO cl_gui_container.
    DATA lo_middle TYPE REF TO cl_gui_container.
    DATA lo_right  TYPE REF TO cl_gui_container.
    lo_left   = mo_split->get_container( row = 1 column = 1 ).
    lo_middle = mo_split->get_container( row = 1 column = 2 ).
    lo_right  = mo_split->get_container( row = 1 column = 3 ).

    " Question editor (left)
    CREATE OBJECT mo_question
      EXPORTING parent = lo_left
      EXCEPTIONS OTHERS = 1.
    mo_question->set_toolbar_mode( 0 ).  " 0 = toolbar off

    " Middle pane: split into progress log (top) + object tree (bottom).
    " Toggled 0/100 like the answer pane: log during a run, tree when an object
    " is shown in the editor.
    CREATE OBJECT mo_mid_split
      EXPORTING parent = lo_middle rows = 2 columns = 1
      EXCEPTIONS OTHERS = 1.
    mo_mid_cont_log  = mo_mid_split->get_container( row = 1 column = 1 ).
    mo_mid_cont_tree = mo_mid_split->get_container( row = 2 column = 1 ).
    mo_mid_split->set_row_height( id = 1 height = 100 ).
    mo_mid_split->set_row_height( id = 2 height = 0 ).

    " Progress log viewer (top row - default visible)
    CREATE OBJECT mo_progress
      EXPORTING parent = mo_mid_cont_log
      EXCEPTIONS OTHERS = 1.

    " Object structure tree (bottom row - shown when an object is in the editor)
    mo_obj_tree = NEW zcl_code_object_tree(
      io_container = mo_mid_cont_tree
      io_popup     = me ).

    " Right panel: split into HTML viewer (top) + ABAP editor (bottom).
    " Heights toggled 0/100 to show one at a time (same pattern as ZCL_AVE_POPUP).
    CREATE OBJECT mo_answer_split
      EXPORTING parent = lo_right rows = 2 columns = 1
      EXCEPTIONS OTHERS = 1.
    mo_answer_cont_html = mo_answer_split->get_container( row = 1 column = 1 ).
    mo_answer_cont_code = mo_answer_split->get_container( row = 2 column = 1 ).
    mo_answer_split->set_row_height( id = 1 height = 100 ).
    mo_answer_split->set_row_height( id = 2 height = 0 ).

    " HTML viewer (top row вЂ” default visible)
    CREATE OBJECT mo_answer
      EXPORTING parent = mo_answer_cont_html
      EXCEPTIONS OTHERS = 1.

    DATA lt_html_events TYPE cntl_simple_events.
    APPEND VALUE #( eventid = cl_gui_html_viewer=>m_id_sapevent ) TO lt_html_events.
    mo_answer->set_registered_events( events = lt_html_events ).
    SET HANDLER on_answer_sapevent FOR mo_answer.

    " ABAP editor (bottom row вЂ” shown only for program source)
    CREATE OBJECT mo_code_viewer
      EXPORTING parent = mo_answer_cont_code max_number_chars = 255
      EXCEPTIONS OTHERS = 1.
    mo_code_viewer->upload_properties( EXCEPTIONS OTHERS = 1 ).
    mo_code_viewer->set_statusbar_mode(
      statusbar_mode = cl_gui_abapedit=>true ).
    mo_code_viewer->create_document( ).
    mo_code_viewer->set_readonly_mode( 1 ).
    mo_code_viewer->register_event_border_click( ).
    SET HANDLER on_code_border_click FOR mo_code_viewer.

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


  method BUILD_STEPS_HTML.

    IF io_messages IS NOT BOUND.
      rv_html = |<!DOCTYPE html><html><body>No messages</body></html>|.
      RETURN.
    ENDIF.

    DATA(lt_messages) = io_messages->get_messages( ).

    DATA lv_steps_html TYPE string.
    DATA lv_last_agent TYPE string.
    DATA lt_agents_seen TYPE STANDARD TABLE OF string WITH NON-UNIQUE DEFAULT KEY.
    DATA lv_esc TYPE string.

    LOOP AT lt_messages INTO DATA(ls_msg).
      IF ls_msg-agent IS NOT INITIAL
      AND ls_msg-agent <> lv_last_agent.

        READ TABLE lt_agents_seen WITH KEY table_line = ls_msg-agent TRANSPORTING NO FIELDS.
        IF sy-subrc <> 0.
          APPEND ls_msg-agent TO lt_agents_seen.

          lv_esc = ls_msg-agent.
          REPLACE ALL OCCURRENCES OF '&' IN lv_esc WITH '&amp;'.
          REPLACE ALL OCCURRENCES OF '<' IN lv_esc WITH '&lt;'.
          REPLACE ALL OCCURRENCES OF '>' IN lv_esc WITH '&gt;'.

          lv_steps_html = lv_steps_html &&
            |<div class="step completed">&#x2713; { lv_esc }</div>|.

          lv_last_agent = ls_msg-agent.
        ENDIF.
      ENDIF.
    ENDLOOP.

    DATA lv_messages_html TYPE string.
    LOOP AT lt_messages INTO ls_msg.
      DATA(lv_msg_role) = COND string(
        WHEN ls_msg-role = 'user' THEN 'user-msg'
        WHEN ls_msg-role = 'assistant' THEN 'assistant-msg'
        ELSE 'system-msg' ).

      DATA(lv_agent_esc) = ls_msg-agent.
      REPLACE ALL OCCURRENCES OF '&' IN lv_agent_esc WITH '&amp;'.
      REPLACE ALL OCCURRENCES OF '<' IN lv_agent_esc WITH '&lt;'.
      REPLACE ALL OCCURRENCES OF '>' IN lv_agent_esc WITH '&gt;'.

      DATA(lv_msg_content) = ls_msg-content.
      REPLACE ALL OCCURRENCES OF '&' IN lv_msg_content WITH '&amp;'.
      REPLACE ALL OCCURRENCES OF '<' IN lv_msg_content WITH '&lt;'.
      REPLACE ALL OCCURRENCES OF '>' IN lv_msg_content WITH '&gt;'.
      REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>newline IN lv_msg_content WITH '<br>'.

      lv_messages_html = lv_messages_html &&
        |<div class="{ lv_msg_role }">|
        && |<span class="agent">{ lv_agent_esc }</span>|
        && |<div class="content">{ lv_msg_content }</div>|
        && |</div>|.
    ENDLOOP.

    rv_html =
      |<!DOCTYPE html><html><head><meta charset="utf-8"><style>|
      && |body\{font-family:Segoe UI,Arial,sans-serif;margin:10px;background:#f5f5f5\}|
      && |.steps\{margin-bottom:20px;padding:10px;background:white;border-radius:4px\}|
      && |.step\{padding:8px 12px;margin:4px 0;border-radius:3px;font-size:14px\}|
      && |.step.completed\{background:#e8f5e9;color:#2e7d32\}|
      && |.step.active\{background:#fff3e0;color:#f57f17\}|
      && |.messages\{background:white;padding:10px;border-radius:4px\}|
      && |.user-msg\{margin:8px 0;padding:10px;background:#e3f2fd;border-left:3px solid #1976d2\}|
      && |.assistant-msg\{margin:8px 0;padding:10px;background:#f3e5f5;border-left:3px solid #7b1fa2\}|
      && |.system-msg\{margin:8px 0;padding:10px;background:#fce4ec;border-left:3px solid #c2185b\}|
      && |.agent\{font-weight:bold;color:#0066aa\}|
      && |.content\{margin-top:4px;font-family:Consolas,monospace;font-size:12px;white-space:pre-wrap\}|
      && |</style></head><body>|
      && |<div class="steps">| && lv_steps_html && |</div>|
      && |<div class="messages">| && lv_messages_html && |</div>|
      && |</body></html>|.

  endmethod.


  method SET_LIVE_UPDATE_CONTEXT.

    ZCL_CODE_POPUP2=>mo_answer_static = io_answer_viewer.
    ZCL_CODE_POPUP2=>mo_messages_static = io_messages.

  endmethod.


  method UPDATE_HTML_WITH_STEPS.

    IF mo_answer_static IS NOT BOUND
    OR mo_messages_static IS NOT BOUND.
      RETURN.
    ENDIF.

    DATA(lv_html) = build_steps_html( mo_messages_static ).

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
    mo_answer_static->load_data(
      EXPORTING
        type         = 'text'
        subtype      = 'html'
      IMPORTING
        assigned_url = lv_url
      CHANGING
        data_table   = lt_html
      EXCEPTIONS
        OTHERS       = 1 ).

    mo_answer_static->show_url(
      EXPORTING url = lv_url
      EXCEPTIONS OTHERS = 1 ).

    CALL METHOD cl_gui_cfw=>flush.

  endmethod.


  METHOD display_program_source.

    " Show ABAP program source in the ABAP editor panel (right, bottom row).
    " Converts string source to char255 table as required by CL_GUI_ABAPEDIT.
    IF mo_code_viewer IS NOT BOUND.
      " Fallback: editor not created yet - show as HTML
      display_answer( i_answer = zcl_code_html_gen=>source_to_html(
        i_source = i_source i_title = 'PROG' ) ).
      RETURN.
    ENDIF.

    DATA lt_src   TYPE STANDARD TABLE OF char255.
    DATA lt_lines TYPE STANDARD TABLE OF string.
    SPLIT i_source AT cl_abap_char_utilities=>newline INTO TABLE lt_lines.
    LOOP AT lt_lines INTO DATA(lv_line).
      " Strip section/method markers added for LLM context
      " (e.g. "--- Public section ---", "--- Method GET_NAME ---")
      DATA(lv_trimmed) = lv_line.
      CONDENSE lv_trimmed.
      IF lv_trimmed CP '--- * ---'.
        CONTINUE.
      ENDIF.
      APPEND CONV char255( lv_line ) TO lt_src.
    ENDLOOP.

    mo_code_viewer->set_text( table = lt_src ).
    mo_code_viewer->set_readonly_mode( 1 ).

    " Switch right panel to ABAP editor row
    IF mo_answer_split IS BOUND.
      mo_answer_split->set_row_height( id = 1 height = 0 ).
      mo_answer_split->set_row_height( id = 2 height = 100 ).
    ENDIF.

    IF i_program IS NOT INITIAL.
      mv_displayed_program = i_program.
      mv_displayed_include = COND progname( WHEN i_include IS NOT INITIAL THEN i_include ELSE i_program ).
      " Show RUN button for executable programs (subc = '1') if not already shown
      IF mv_run_program IS INITIAL.
        SELECT SINGLE subc FROM reposrc INTO @DATA(lv_dp_subc)
          WHERE progname = @i_program AND subc = '1'.
        IF sy-subrc = 0.
          mv_run_program = i_program.
          show_run_program_button( ).
        ENDIF.
      ENDIF.
    ENDIF.
    refresh_breakpoint_markers( ).

    cl_gui_cfw=>flush( ).

  ENDMETHOD.




  METHOD display_streaming.

    " Show plain text with JS typewriter animation (streaming effect).
    " The full response is already received; animation gives a "live" feel.
    " Animation speed auto-scales: always ~2-3 seconds regardless of text length.

    DATA lv_js_text TYPE string.
    DATA lv_cr      TYPE c LENGTH 1.
    lv_cr = cl_abap_char_utilities=>cr_lf(1).

    " Escape text for embedding inside a JS double-quoted string literal
    lv_js_text = i_text.
    REPLACE ALL OCCURRENCES OF '\' IN lv_js_text WITH '\\'.
    REPLACE ALL OCCURRENCES OF '"' IN lv_js_text WITH '\"'.
    REPLACE ALL OCCURRENCES OF '`' IN lv_js_text WITH '\`'.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf IN lv_js_text WITH '\n'.
    REPLACE ALL OCCURRENCES OF lv_cr IN lv_js_text WITH ''.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>newline IN lv_js_text WITH '\n'.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>horizontal_tab IN lv_js_text WITH '\t'.

    " Build HTML page with embedded typewriter JavaScript.
    " IMPORTANT: CSS/JS curly braces { } cannot be inside ABAP template strings | |
    " because ABAP interprets { as start of variable reference.
    " Use '...' literals for static HTML/CSS/JS, | | only where ABAP vars are embedded.
    DATA lv_html TYPE string.
    lv_html =
      '<html><head><meta charset="UTF-8"><style>'
      && 'body{margin:0;padding:8px;font-family:Consolas,monospace;background:#1e1e1e;color:#d4d4d4}'
      && 'pre{white-space:pre-wrap;word-break:break-word;font-size:13px;line-height:1.5}'
      && '</style></head><body>'
      && '<pre id="out"></pre><span id="cur">&#9608;</span>'
      && '<script>'
      && |var full="{ lv_js_text }";|
      && 'var i=0,el=document.getElementById("out"),cur=document.getElementById("cur");'
      && 'var total=full.length,batch=Math.max(1,Math.ceil(total/80));'
      && 'function type(){'
      &&   'if(i<total){el.innerText+=full.substr(i,batch);i+=batch;setTimeout(type,30);}'
      &&   'else{cur.style.display="none";}'
      && '}'
      && 'type();'
      && '</script></body></html>'.

    " Load HTML into the answer viewer
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
      EXPORTING type = 'text' subtype = 'html'
      IMPORTING assigned_url = lv_url
      CHANGING  data_table   = lt_html
      EXCEPTIONS OTHERS = 1 ).

    mo_answer->show_url(
      EXPORTING url = lv_url
      EXCEPTIONS OTHERS = 1 ).

    " Switch right panel to HTML viewer row
    IF mo_answer_split IS BOUND.
      mo_answer_split->set_row_height( id = 1 height = 100 ).
      mo_answer_split->set_row_height( id = 2 height = 0 ).
    ENDIF.

    cl_gui_cfw=>flush( ).

  ENDMETHOD.

  METHOD build_plain_html.
    rv_html = zcl_code_html_gen=>markdown_to_html( i_text ).
  ENDMETHOD.


  METHOD show_object_in_editor.

    DATA(lv_type)     = i_type.
    DATA(lv_name)     = i_name.
    DATA(lv_source)   = VALUE string( ).
    DATA(lv_mainprog) = VALUE progname( ).
    DATA(lv_include)  = VALUE progname( ).
    TRANSLATE lv_type TO UPPER CASE.

    " Detect CLASS=>METHOD pattern (carried either as CLAS or METH type)
    DATA lv_is_meth TYPE abap_bool.
    DATA lv_cls     TYPE string.
    DATA lv_meth    TYPE string.
    IF ( lv_type = 'CLAS' OR lv_type = 'CLASS'
      OR lv_type = 'METH' OR lv_type = 'METHOD' )
      AND lv_name CS '=>'.
      SPLIT lv_name AT '=>' INTO lv_cls lv_meth.
      lv_is_meth = abap_true.
    ENDIF.

    IF lv_is_meth = abap_true.
      " Read raw include source for exact line-number mapping (breakpoints)
      DATA ls_clskey TYPE seoclskey.
      DATA lt_meths  TYPE seop_methods_w_include.
      ls_clskey-clsname = lv_cls.
      TRANSLATE ls_clskey-clsname TO UPPER CASE.
      CONDENSE ls_clskey-clsname.
      DATA(lv_meth_up) = lv_meth.
      TRANSLATE lv_meth_up TO UPPER CASE.
      CONDENSE lv_meth_up.
      CALL FUNCTION 'SEO_CLASS_GET_METHOD_INCLUDES'
        EXPORTING  clskey   = ls_clskey
        IMPORTING  includes = lt_meths
        EXCEPTIONS OTHERS   = 1.
      IF sy-subrc = 0.
        READ TABLE lt_meths INTO DATA(ls_mi)
          WITH KEY cpdkey-cpdname = lv_meth_up.
        IF sy-subrc = 0.
          lv_include = ls_mi-incname.
          DATA lt_raw_src TYPE STANDARD TABLE OF string WITH NON-UNIQUE DEFAULT KEY.
          READ REPORT lv_include INTO lt_raw_src.
          IF sy-subrc = 0.
            LOOP AT lt_raw_src INTO DATA(lv_raw_line).
              IF lv_source IS NOT INITIAL.
                lv_source = lv_source && cl_abap_char_utilities=>newline.
              ENDIF.
              lv_source = lv_source && lv_raw_line.
            ENDLOOP.
          ENDIF.
        ENDIF.
      ENDIF.
      IF lv_source IS INITIAL.
        lv_source = zcl_ai_code_reader=>read_method(
          i_class = lv_cls i_method = lv_meth ).
      ENDIF.
      " Breakpoint main program for a class method is the class POOL include
      " (ZCL_..====CP), not the bare class name. RS_SET_BREAKPOINT needs the
      " exact method include as 'program' and the class pool as 'mainprogram'.
      lv_mainprog = cl_oo_classname_service=>get_classpool_name(
                      clsname = ls_clskey-clsname ).
      IF lv_mainprog IS INITIAL.
        lv_mainprog = CONV progname( ls_clskey-clsname ).
      ENDIF.
    ELSE.
      CASE lv_type.
        WHEN 'PROG' OR 'REPS'.
          lv_source = zcl_ai_code_reader=>read_program( lv_name ).
        WHEN 'CLAS' OR 'CLASS' OR 'INTF'.
          lv_source = zcl_ai_code_reader=>read_class( lv_name ).
        WHEN OTHERS.
          lv_source = zcl_ai_code_reader=>read_class( lv_name ).
      ENDCASE.
      DATA(lv_upper) = lv_source.
      TRANSLATE lv_upper TO UPPER CASE.
      IF lv_source IS INITIAL OR lv_upper CS 'NOT FOUND' OR lv_upper CS 'SIMILAR CLASSES'.
        DATA(lv_class_fallback) = lv_source.
        lv_source = zcl_ai_code_reader=>read_program( lv_name ).
        DATA(lv_prog_upper) = lv_source.
        TRANSLATE lv_prog_upper TO UPPER CASE.
        IF lv_source IS INITIAL OR lv_prog_upper CS 'NOT FOUND' OR lv_prog_upper CS 'CANNOT BE READ'.
          lv_source = lv_class_fallback && cl_abap_char_utilities=>newline && lv_source.
        ENDIF.
      ENDIF.
      lv_mainprog = CONV progname( lv_name ).
    ENDIF.

    IF lv_source IS NOT INITIAL.
      display_program_source(
        i_source  = lv_source
        i_program = lv_mainprog
        i_include = lv_include ).
      " Build the structure tree for this object and switch the middle pane to it.
      IF mo_obj_tree IS BOUND
      AND mo_obj_tree->build_for_object( i_type = i_type i_name = i_name ) = abap_true.
        show_tree_pane( ).
      ENDIF.
    ENDIF.

  ENDMETHOD.


  METHOD navigate_to.

    DATA lt_src TYPE STANDARD TABLE OF string WITH NON-UNIQUE DEFAULT KEY.
    READ REPORT i_include INTO lt_src.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    DATA lv_text TYPE string.
    LOOP AT lt_src INTO DATA(lv_line).
      IF lv_text IS NOT INITIAL.
        lv_text = lv_text && cl_abap_char_utilities=>newline.
      ENDIF.
      lv_text = lv_text && lv_line.
    ENDLOOP.

    " Load the include (1:1 line mapping, breakpoints stay valid).
    display_program_source(
      i_source  = lv_text
      i_program = i_program
      i_include = i_include ).

    CHECK i_search IS NOT INITIAL.

    " Plain text search for the first matching line, then select + mark it.
    DATA(lv_needle) = i_search.
    TRANSLATE lv_needle TO UPPER CASE.
    DATA lv_hit TYPE i.
    LOOP AT lt_src INTO lv_line.
      DATA(lv_hay) = lv_line.
      TRANSLATE lv_hay TO UPPER CASE.
      IF lv_hay CS lv_needle.
        lv_hit = sy-tabix.
        EXIT.
      ENDIF.
    ENDLOOP.

    CHECK lv_hit > 0.
    DATA lt_mark TYPE STANDARD TABLE OF i WITH NON-UNIQUE DEFAULT KEY.
    APPEND lv_hit TO lt_mark.
    mo_code_viewer->set_marker( EXPORTING marker_number = 7 marker_lines = lt_mark ).
    mo_code_viewer->select_lines( EXPORTING from_line = lv_hit to_line = lv_hit ).
    mo_code_viewer->draw( ).

  ENDMETHOD.


  METHOD show_log_pane.
    IF mo_mid_split IS BOUND.
      mo_mid_split->set_row_height( id = 1 height = 100 ).
      mo_mid_split->set_row_height( id = 2 height = 0 ).
    ENDIF.
  ENDMETHOD.


  METHOD show_tree_pane.
    IF mo_mid_split IS BOUND.
      mo_mid_split->set_row_height( id = 1 height = 0 ).
      mo_mid_split->set_row_height( id = 2 height = 100 ).
    ENDIF.
  ENDMETHOD.


  METHOD on_code_border_click.
    DATA: lv_type    TYPE char1,
          lv_program TYPE progname,
          lv_include TYPE progname,
          lv_line    TYPE i.
    CHECK mv_displayed_program IS NOT INITIAL.
    CHECK mo_code_viewer IS BOUND.
    lv_program = mv_displayed_program.
    lv_include = COND progname( WHEN mv_displayed_include IS NOT INITIAL
                                THEN mv_displayed_include
                                ELSE mv_displayed_program ).
    lv_line    = line.
    IF cntrl_pressed_set IS INITIAL. lv_type = 'S'. ELSE. lv_type = 'E'. ENDIF.
    LOOP AT mt_bpoints ASSIGNING FIELD-SYMBOL(<point>) WHERE line = lv_line.
      lv_type = <point>-type.
      CALL FUNCTION 'RS_DELETE_BREAKPOINT'
        EXPORTING
          index    = lv_line
          mainprog = lv_program
          program  = lv_include
          bp_type  = lv_type
        EXCEPTIONS
          not_executed = 1
          OTHERS       = 2.
      IF sy-subrc = 0. <point>-del = abap_true. ENDIF.
    ENDLOOP.
    IF sy-subrc <> 0.
      CALL FUNCTION 'RS_SET_BREAKPOINT'
        EXPORTING
          index       = lv_line
          program     = lv_include
          mainprogram = lv_program
          bp_type     = lv_type
        EXCEPTIONS
          not_executed = 1
          OTHERS       = 2.
    ENDIF.
    DELETE mt_bpoints WHERE del IS NOT INITIAL.
    refresh_breakpoint_markers( ).
  ENDMETHOD.


  METHOD refresh_breakpoint_markers.
    TYPES: lntab TYPE STANDARD TABLE OF i WITH NON-UNIQUE DEFAULT KEY.
    DATA: lines TYPE lntab.
    DATA  lv_inc TYPE progname.
    CHECK mv_displayed_program IS NOT INITIAL.
    CHECK mo_code_viewer IS BOUND.
    lv_inc = COND progname( WHEN mv_displayed_include IS NOT INITIAL
                            THEN mv_displayed_include
                            ELSE mv_displayed_program ).
    mo_code_viewer->remove_all_marker( 2 ).
    mo_code_viewer->remove_all_marker( 4 ).
    CLEAR mt_bpoints.
    " Session breakpoints (marker 2 — red circle)
    CALL METHOD cl_abap_debugger=>read_breakpoints
      EXPORTING  main_program         = mv_displayed_program
      IMPORTING  breakpoints_complete = DATA(points)
      EXCEPTIONS c_call_error = 1 generate = 2 wrong_parameters = 3 OTHERS = 4.
    CLEAR lines.
    LOOP AT points INTO DATA(point).
      CHECK point-include = lv_inc.
      APPEND point-line TO lines.
      READ TABLE mt_bpoints TRANSPORTING NO FIELDS
        WITH KEY include = point-include line = point-line.
      IF sy-subrc <> 0.
        APPEND VALUE ts_bpoint(
          program = mv_displayed_program include = lv_inc
          line = point-line type = 'S' ) TO mt_bpoints.
      ENDIF.
    ENDLOOP.
    mo_code_viewer->set_marker( EXPORTING marker_number = 2 marker_lines = lines ).
    " External breakpoints — other sessions (marker 4 — yellow circle)
    CLEAR lines.
    CALL METHOD cl_abap_debugger=>read_breakpoints
      EXPORTING  main_program         = mv_displayed_program
                 flag_other_session   = abap_true
      IMPORTING  breakpoints_complete = points
      EXCEPTIONS c_call_error = 1 generate = 2 wrong_parameters = 3 OTHERS = 4.
    LOOP AT points INTO point WHERE include = lv_inc.
      APPEND point-line TO lines.
      READ TABLE mt_bpoints TRANSPORTING NO FIELDS
        WITH KEY include = point-include line = point-line.
      IF sy-subrc <> 0.
        APPEND VALUE ts_bpoint(
          program = mv_displayed_program include = lv_inc
          line = point-line type = 'E' ) TO mt_bpoints.
      ENDIF.
    ENDLOOP.
    mo_code_viewer->set_marker( EXPORTING marker_number = 4 marker_lines = lines ).
    mo_code_viewer->clear_line_markers( 'S' ).
    mo_code_viewer->draw( ).
  ENDMETHOD.


  METHOD review_and_save.

    " Show diff - user reviews hunks and approves/declines via diff toolbar.
    " ON_ANSWER_SAPEVENT handles the actual save when all hunks are approved.
    DATA(lv_diff_html) = diff_to_html(
      i_old_code    = i_old_code
      i_new_code    = i_new_code
      i_object_type = i_object_type
      i_object_name = i_object_name ).
    display_answer( i_answer = lv_diff_html ).
    cl_gui_cfw=>flush( ).

    rv_message = |Review diff for { i_object_type } { i_object_name } and approve/decline changes.|.

  ENDMETHOD.

ENDCLASS.
