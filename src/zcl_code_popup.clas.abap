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
      !I_AGENTS_PATH type STRING
      !I_TEMPERATURE type STRING optional
      !I_STREAM type ABAP_BOOL optional .
  methods SHOW .
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
  data MO_PROGRESS type ref to CL_GUI_HTML_VIEWER .
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
  data MV_APIKEY type STRING .
  data MV_MODEL type TEXT255 .
  data MV_PROVIDER type STRING .
  data MV_STREAM_PROMPT_FILE type STRING .
  data MV_STREAM_RESPONSE_FILE type STRING .
  data MV_RUN_PROGRAM type PROGNAME .
  data MV_RUN_BUTTON_ADDED type ABAP_BOOL .
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
      !I_SOURCE type STRING .
  " Show plain text with typewriter animation (streaming effect).
  methods DISPLAY_STREAMING
    importing
      !I_TEXT type STRING .
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

    " --- Streaming path: delegate HTTP call to local Python client ---
    IF mv_stream = abap_true.
      " Fixed exchange folder — easy to find and monitor
      DATA lv_temp_dir TYPE string.
      lv_temp_dir = 'C:\soft\stream'.

      mv_stream_prompt_file   = lv_temp_dir && '\abap_ai_prompt.json'.
      mv_stream_response_file = lv_temp_dir && '\abap_ai_response.txt'.

      " Run all agent prep steps (detect language, plan tasks, read code) but skip
      " the final LLM call — returns the fully assembled prompt in rs_result-final_prompt.
      display_status( |Preparing prompt...| ).
      cl_gui_cfw=>flush( ).

      DATA(lo_runner_s) = NEW zcl_code_ai_runner(
        io_llm     = mo_llm
        io_prompts = mo_prompts ).
      lo_runner_s->set_html_viewer( mo_progress ).
      DATA(ls_stream_prep) = lo_runner_s->run(
        i_prompt          = lv_prompt
        i_session_id      = mv_session_counter
        i_skip_final_llm  = abap_true ).

      mo_messages = ls_stream_prep-messages_ref.
      " Do NOT append messages here — will append after streaming completes (with FINAL message).

      " Build JSON config + assembled final prompt for the Python script
      DATA lv_json_prompt TYPE string.
      DATA lv_esc_prompt  TYPE string.
      DATA lv_esc_apikey  TYPE string.
      DATA lv_cr          TYPE c LENGTH 1.
      lv_cr = cl_abap_char_utilities=>cr_lf(1).

      lv_esc_prompt = ls_stream_prep-final_prompt.
      REPLACE ALL OCCURRENCES OF '\' IN lv_esc_prompt WITH '\\'.
      REPLACE ALL OCCURRENCES OF '"' IN lv_esc_prompt WITH '\"'.
      REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf IN lv_esc_prompt WITH '\n'.
      REPLACE ALL OCCURRENCES OF lv_cr IN lv_esc_prompt WITH ''.
      REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>newline IN lv_esc_prompt WITH '\n'.
      REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>horizontal_tab IN lv_esc_prompt WITH '\t'.

      " Escape API key (may contain special chars)
      lv_esc_apikey = mv_apikey.
      REPLACE ALL OCCURRENCES OF '\' IN lv_esc_apikey WITH '\\'.
      REPLACE ALL OCCURRENCES OF '"' IN lv_esc_apikey WITH '\"'.

      lv_json_prompt = |{ '{' }"prompt":"{ lv_esc_prompt }","model":"{ mv_model }","provider":"{ mv_provider }","api_key":"{ lv_esc_apikey }","temperature":"{ mv_temperature }"{ '}' }|.

      " Write prompt file to client machine
      DATA lt_prompt_file TYPE TABLE OF string.
      APPEND lv_json_prompt TO lt_prompt_file.
      cl_gui_frontend_services=>gui_download(
        EXPORTING filename             = mv_stream_prompt_file
                  filetype             = 'ASC'
                  confirm_overwrite    = ' '
                  show_transfer_status = ' '
        CHANGING  data_tab = lt_prompt_file
        EXCEPTIONS OTHERS  = 1 ).

      " Clear previous response file
      DATA lt_empty TYPE TABLE OF string.
      cl_gui_frontend_services=>gui_download(
        EXPORTING filename             = mv_stream_response_file
                  filetype             = 'ASC'
                  confirm_overwrite    = ' '
                  show_transfer_status = ' '
        CHANGING  data_tab = lt_empty
        EXCEPTIONS OTHERS  = 1 ).

      " Launch Python script via PowerShell hidden — no console window appears.
      " -WindowStyle Hidden suppresses both the PowerShell and child Python window.
      DATA(lv_script) = mv_agents_path && '\llm_stream.py'.
      DATA(lv_params) = |-WindowStyle Hidden -Command "python '{ lv_script }' '{ mv_stream_prompt_file }' '{ mv_stream_response_file }'"|.
      cl_gui_frontend_services=>execute(
        EXPORTING
          application       = 'powershell.exe'
          parameter         = lv_params
          default_directory = lv_temp_dir
          synchronous       = ' '
        EXCEPTIONS OTHERS   = 1 ).

      " Show paths in status so user can debug if Python does not start
      display_status( |Stream started. Files: { mv_stream_prompt_file } / { mv_stream_response_file }| ).
      cl_gui_cfw=>flush( ).

      " Poll response file using wall-clock timestamps (TIMESTAMPL = real time, not CPU time).
      " cl_abap_tstmp=>subtract returns seconds as decimal.
      " Check file every 0.5s, timeout after 30s, flush() keeps GUI alive between checks.
      DATA lv_stream_done  TYPE abap_bool.
      DATA lv_ts_start     TYPE timestampl.
      DATA lv_ts_now       TYPE timestampl.
      DATA lv_ts_last_read TYPE timestampl.
      DATA lv_ts_elapsed   TYPE p DECIMALS 3.
      GET TIME STAMP FIELD lv_ts_start.
      lv_ts_last_read = lv_ts_start.

      WHILE abap_true = abap_true.
        GET TIME STAMP FIELD lv_ts_now.

        " Timeout after 30 seconds
        lv_ts_elapsed = cl_abap_tstmp=>subtract( tstmp1 = lv_ts_now tstmp2 = lv_ts_start ).
        IF lv_ts_elapsed > 30.
          EXIT.
        ENDIF.

        " Read file every 500ms
        lv_ts_elapsed = cl_abap_tstmp=>subtract( tstmp1 = lv_ts_now tstmp2 = lv_ts_last_read ).
        IF lv_ts_elapsed < '0.1'.
          cl_gui_cfw=>flush( ).  " keep GUI alive between half-second checks
          CONTINUE.
        ENDIF.
        GET TIME STAMP FIELD lv_ts_last_read.  " reset half-second counter

        " Read current content from client file
        DATA lt_resp_lines TYPE TABLE OF string.
        CLEAR lt_resp_lines.
        " Check file size first — skip upload if file still empty (avoids "0 of 0" dialog)
        DATA lv_resp_fsize TYPE i.
        cl_gui_frontend_services=>file_get_size(
          EXPORTING file_name  = mv_stream_response_file
          IMPORTING file_size  = lv_resp_fsize
          EXCEPTIONS OTHERS    = 1 ).
        IF lv_resp_fsize > 0.
          cl_gui_frontend_services=>gui_upload(
            EXPORTING filename = mv_stream_response_file
                      filetype = 'ASC'
            CHANGING  data_tab = lt_resp_lines
            EXCEPTIONS OTHERS  = 1 ).
        ENDIF.

        " Concatenate lines
        DATA lv_resp_text TYPE string.
        CLEAR lv_resp_text.
        LOOP AT lt_resp_lines INTO DATA(lv_resp_line).
          IF lv_resp_text IS NOT INITIAL.
            lv_resp_text = lv_resp_text && cl_abap_char_utilities=>newline.
          ENDIF.
          lv_resp_text = lv_resp_text && lv_resp_line.
        ENDLOOP.

        " Check terminal markers
        DATA lv_stream_error TYPE abap_bool.
        IF lv_resp_text CS '##DONE##'.
          lv_stream_done = abap_true.
          REPLACE ALL OCCURRENCES OF '##DONE##' IN lv_resp_text WITH ''.
        ELSEIF lv_resp_text CS '##ERROR##'.
          lv_stream_error = abap_true.
          REPLACE ALL OCCURRENCES OF '##ERROR##' IN lv_resp_text WITH ''.
        ENDIF.
        " Do NOT condense — preserves code indentation and formatting

        " Escape for HTML
        DATA lv_resp_html TYPE string.
        CLEAR lv_resp_html.
        lv_resp_html = lv_resp_text.
        REPLACE ALL OCCURRENCES OF '&' IN lv_resp_html WITH '&amp;'.
        REPLACE ALL OCCURRENCES OF '<' IN lv_resp_html WITH '&lt;'.
        REPLACE ALL OCCURRENCES OF '>' IN lv_resp_html WITH '&gt;'.

        " Build and show HTML with current content
        DATA lv_color TYPE string.
        IF lv_stream_done = abap_true.
          lv_color = '#1a7f1a'.  " dark green when done
        ELSEIF lv_stream_error = abap_true.
          lv_color = '#cc0000'.  " dark red on error
        ELSE.
          lv_color = '#1a1a1a'.  " near-black while streaming
        ENDIF.

        DATA lv_stream_html TYPE string.
        lv_stream_html =
          '<html><head><meta charset="UTF-8"><style>'
          && 'body{margin:0;padding:8px;font-family:Consolas,monospace;background:#ffffff}'
          && 'pre{white-space:pre-wrap;word-break:break-word;font-size:13px;line-height:1.5;color:#1a1a1a}'
          && '</style></head><body>'
          && |<pre style="color:{ lv_color }">{ lv_resp_html }|.
        IF lv_stream_done = abap_false AND lv_stream_error = abap_false.
          lv_stream_html = lv_stream_html && '&#9608;'.  " block cursor while in progress
        ENDIF.
        lv_stream_html = lv_stream_html && '</pre></body></html>'.

        DATA lt_stream_html TYPE tt_html.
        DATA ls_stream_html TYPE w3html.
        DATA lv_stream_off  TYPE i.
        CLEAR lt_stream_html.
        CLEAR lv_stream_off.
        WHILE lv_stream_off < strlen( lv_stream_html ).
          CLEAR ls_stream_html.
          ls_stream_html-line = substring(
            val = lv_stream_html off = lv_stream_off
            len = nmin( val1 = 255 val2 = strlen( lv_stream_html ) - lv_stream_off ) ).
          APPEND ls_stream_html TO lt_stream_html.
          lv_stream_off = lv_stream_off + 255.
        ENDWHILE.

        DATA lv_stream_url TYPE c LENGTH 255.
        mo_answer->load_data(
          EXPORTING type = 'text' subtype = 'html'
          IMPORTING assigned_url = lv_stream_url
          CHANGING  data_table   = lt_stream_html
          EXCEPTIONS OTHERS = 1 ).
        mo_answer->show_url( EXPORTING url = lv_stream_url EXCEPTIONS OTHERS = 1 ).
        IF mo_answer_split IS BOUND.
          mo_answer_split->set_row_height( id = 1 height = 100 ).
          mo_answer_split->set_row_height( id = 2 height = 0 ).
        ENDIF.
        cl_gui_cfw=>flush( ).

        IF lv_stream_done = abap_true OR lv_stream_error = abap_true.
          EXIT.
        ENDIF.
      ENDWHILE.

      " Register streamed answer in message history (so it appears in History popup).
      IF lv_stream_done = abap_true.
        lo_runner_s->register_stream_answer( lv_resp_text ).
        APPEND LINES OF lo_runner_s->get_messages( )->get_messages( ) TO mt_message_history.
      ENDIF.
      " Do NOT call display_status — it would overwrite the streamed answer.
      IF lv_stream_error = abap_true.
        MESSAGE 'Stream error — check C:\soft\stream\llm_stream.log' TYPE 'S'.
      ELSEIF lv_stream_done = abap_false.
        MESSAGE 'Stream timeout (30s)' TYPE 'S'.
      ENDIF.
      RETURN.
    ENDIF.
    " --- End streaming path ---

    display_status( |Asking AI...| ).

    DATA(lo_runner) = NEW zcl_code_ai_runner(
      io_llm     = mo_llm
      io_prompts = mo_prompts ).
    lo_runner->set_html_viewer( mo_progress ).
    DATA(ls_result) = lo_runner->run(
      i_prompt     = lv_prompt
      i_session_id = mv_session_counter ).

    mo_messages = ls_result-messages_ref.
    APPEND LINES OF ls_result-messages TO mt_message_history.

    CALL FUNCTION 'SAPGUI_PROGRESS_INDICATOR'
      EXPORTING percentage = 0 text = ''.

    " Source-only result (direct lookup / SHOW command) → ABAP editor.
    " If is_source_code is false the result is an HTML error/suggestion page
    " (e.g. "not found, similar classes") and goes to the HTML viewer as-is.
    IF ls_result-is_source_code = abap_true AND ls_result-has_diff = abap_false.
      display_program_source( ls_result-answer ).
      RETURN.
    ENDIF.

    " Non-code source result (error / "similar classes") — convert to HTML
    " so the object names become clickable hyperlinks as before.
    DATA(lv_display_answer) = ls_result-answer.
    IF ls_result-is_source_code = abap_false
    AND ls_result-has_diff = abap_false
    AND ls_result-answer IS NOT INITIAL.
      lv_display_answer = zcl_code_html_gen=>source_to_html(
        i_source = ls_result-answer
        i_title  = 'Search result' ).
    ENDIF.
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
      i_source = ls_result-resolved_code
      i_title  = ls_result-source_title ).

  endmethod.


  method CONSTRUCTOR.

    mo_llm = NEW zcl_llm_client(
      i_dest     = i_dest
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
          DATA(lv_open_type) = lt_obj_parts[ 1 ].
          DATA(lv_open_name) = lt_obj_parts[ 2 ].
          DATA(lv_open_source) = VALUE string( ).
          CASE lv_open_type.
            WHEN 'PROG' OR 'REPS'.
              lv_open_source = zcl_ai_code_reader=>read_program( lv_open_name ).
            WHEN 'CLAS' OR 'CLASS' OR 'INTF'.
              lv_open_source = zcl_ai_code_reader=>read_class( lv_open_name ).
            WHEN OTHERS.
              lv_open_source = zcl_ai_code_reader=>read_class( lv_open_name ).
          ENDCASE.
          DATA(lv_open_upper) = lv_open_source.
          TRANSLATE lv_open_upper TO UPPER CASE.
          IF lv_open_source IS INITIAL OR lv_open_upper CS 'NOT FOUND' OR lv_open_upper CS 'SIMILAR CLASSES'.
            DATA(lv_class_fallback) = lv_open_source.
            lv_open_source = zcl_ai_code_reader=>read_program( lv_open_name ).
            DATA(lv_prog_upper) = lv_open_source.
            TRANSLATE lv_prog_upper TO UPPER CASE.
            IF lv_open_source IS INITIAL OR lv_prog_upper CS 'NOT FOUND' OR lv_prog_upper CS 'CANNOT BE READ'.
              " Neither class nor program found - show both error messages
              lv_open_source = lv_class_fallback && cl_abap_char_utilities=>newline && lv_open_source.
            ENDIF.
          ENDIF.
          IF lv_open_source IS NOT INITIAL.
            display_program_source( lv_open_source ).
          ENDIF.
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

    mo_messages->add_message(
      i_role        = 'user'
      i_agent       = 'SAVE_OBJECT'
      i_prompt_type = 'COMMAND'
      i_content     = lv_save_command ).

    display_status( |Saving approved changes for { mv_diff_object_type } { mv_diff_object_name }...| ).

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
    " the correct step chips (✓ OBJECT_DETECTOR, ✓ TASK_ORCHESTRATOR, etc.).
    " Replacing it would either erase those steps (old "✓ saved" banner) or
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
    display_program_source( lv_saved_source ).

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

    " Progress log viewer (middle)
    CREATE OBJECT mo_progress
      EXPORTING parent = lo_middle
      EXCEPTIONS OTHERS = 1.

    " Right panel: split into HTML viewer (top) + ABAP editor (bottom).
    " Heights toggled 0/100 to show one at a time (same pattern as ZCL_AVE_POPUP).
    CREATE OBJECT mo_answer_split
      EXPORTING parent = lo_right rows = 2 columns = 1
      EXCEPTIONS OTHERS = 1.
    mo_answer_cont_html = mo_answer_split->get_container( row = 1 column = 1 ).
    mo_answer_cont_code = mo_answer_split->get_container( row = 2 column = 1 ).
    mo_answer_split->set_row_height( id = 1 height = 100 ).
    mo_answer_split->set_row_height( id = 2 height = 0 ).

    " HTML viewer (top row — default visible)
    CREATE OBJECT mo_answer
      EXPORTING parent = mo_answer_cont_html
      EXCEPTIONS OTHERS = 1.

    DATA lt_html_events TYPE cntl_simple_events.
    APPEND VALUE #( eventid = cl_gui_html_viewer=>m_id_sapevent ) TO lt_html_events.
    mo_answer->set_registered_events( events = lt_html_events ).
    SET HANDLER on_answer_sapevent FOR mo_answer.

    " ABAP editor (bottom row — shown only for program source)
    CREATE OBJECT mo_code_viewer
      EXPORTING parent = mo_answer_cont_code max_number_chars = 255
      EXCEPTIONS OTHERS = 1.
    mo_code_viewer->upload_properties( EXCEPTIONS OTHERS = 1 ).
    mo_code_viewer->set_statusbar_mode(
      statusbar_mode = cl_gui_abapedit=>true ).
    mo_code_viewer->create_document( ).
    mo_code_viewer->set_readonly_mode( 1 ).

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

    zcl_code_popup=>mo_answer_static = io_answer_viewer.
    zcl_code_popup=>mo_messages_static = io_messages.

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


ENDCLASS.
